// lib/background/bg_sync.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';

import 'notification_service.dart';
import 'package:timezone/data/latest_all.dart' as tzData;
import 'package:timezone/timezone.dart' as tz;
import 'package:smartmed/firebase_options.dart';

/// Nome da task periódica
class BgSync {
  static const taskName = 'alertamed-sync-15min';

  /// Cache simples em memória por execução da task
  static final Map<String, Map<String, dynamic>> _tratamentosCache = {};

  /// Registra a task para o UID do paciente atual.
  static Future<void> register({required String pacienteUid}) async {
    await Workmanager().registerPeriodicTask(
      'bg-$taskName-$pacienteUid', // id único por paciente
      taskName,
      frequency: const Duration(minutes: 15), // mínimo do Android
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      constraints: Constraints(networkType: NetworkType.connected),
      inputData: {'pacienteUid': pacienteUid},
      backoffPolicy: BackoffPolicy.exponential,
    );
  }

  /// Cancela todas as tasks (chame no logout)
  static Future<void> cancelAll() => Workmanager().cancelAll();

  /// Executa a task (chamado pelo dispatcher)
  @pragma('vm:entry-point')
  static Future<bool> runPeriodicTask(String task, Map<String, dynamic>? input) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      } catch (_) {}

      try {
        tzData.initializeTimeZones();
        tz.setLocalLocation(tz.getLocation('America/Sao_Paulo'));
      } catch (_) {}

      try {
        await NotificationService().init();
      } catch (_) {}

      final pacienteUid = input?['pacienteUid'] as String?;
      if (pacienteUid == null || pacienteUid.isEmpty) return false;

      // Sincroniza lembretes (e tratamentos, se você usa pendingSync neles)
      await _syncLembretes(pacienteUid);
      await _syncColecao(pacienteUid, 'tratamentos'); // opcional

      // limpa cache ao final
      _tratamentosCache.clear();
      return true;
    } catch (_) {
      _tratamentosCache.clear();
      return false;
    }
  }

  /// === Sincroniza LEMBRETES com pendingSync, hidratando do TRATAMENTO ===
  static Future<void> _syncLembretes(String pacienteUid) async {
    final col = FirebaseFirestore.instance
        .collection('usuarios').doc(pacienteUid).collection('lembretes');

    // 1) Busca todos os lembretes pendentes no servidor (evita provider)
    final qs = await col
        .where('pendingSync', isEqualTo: true)
        .get(const GetOptions(source: Source.server));
    if (qs.docs.isEmpty) return;

    // 2) Pré-coleta dos tratamentoId para um pré-fetch em lote (melhor performance)
    final Set<String> tratamentoIds = {};
    for (final d in qs.docs) {
      final data = d.data();
      final String? tId = (data['idTratamento'] as String?)?.trim();
      if (tId != null && tId.isNotEmpty && !_tratamentosCache.containsKey(tId)) {
        tratamentoIds.add(tId);
      }
    }
    if (tratamentoIds.isNotEmpty) {
      await _prefetchTratamentos(
        pacienteUid: pacienteUid,
        ids: tratamentoIds.toList(),
      );
    }

    final notif = NotificationService();

    for (final d in qs.docs) {
      final m = d.data();

      // 2.1) Cancelar se removido/cancelado
      if ((m['status'] ?? 'ativo') == 'removido' || (m['cancelado'] == true)) {
        final int? idN = _toIntOrNull(m['idNotificacao']);
        if (idN != null) {
          try {
            await notif.cancelNotification(idN);
          } catch (_) {}
        }
        await _marcarSincronizado(d);
        continue;
      }

      // 2.2) Hidrata a partir do tratamento se necessário
      final hydrated = await _hydrateFromTratamento(
        pacienteUid: pacienteUid,
        lembreteData: m,
      );

      // 2.3) Dados mínimos para agendar
      final int? idN = _toIntOrNull(hydrated['idNotificacao']);
      final Timestamp? ts = hydrated['dataHoraAgendado'] as Timestamp?;
      if (idN == null || ts == null) {
        // Desmarca para não travar fila, mas registre um motivo (opcional)
        await _marcarSincronizado(d, extra: {'_syncNote': 'faltam_campos_para_agendar'});
        continue;
      }

      // 2.4) Monta título e corpo no mesmo padrão do app
      final titulo = 'Hora do medicamento';
      final corpo = _montarCorpoPadrao(hydrated);

      try {
        await notif.scheduleNotification(
          id: idN,
          title: titulo,
          body: corpo,
          scheduledDateTime: ts.toDate(),
          idLembrete: d.id,
          idUsuario: pacienteUid,
        );
      } catch (_) {
        // Não marca como sincronizado para tentar novamente depois
        continue;
      }

      // 2.5) Opcional: persistir desnormalização no doc do lembrete (para futuras execuções)
      await _persistirDesnormalizacaoSeFaltava(d, m, hydrated);

      await _marcarSincronizado(d);
    }
  }

  /// === Sincroniza outra coleção com pendingSync (genérico) ===
  static Future<void> _syncColecao(String pacienteUid, String scope) async {
    final col = FirebaseFirestore.instance
        .collection('usuarios').doc(pacienteUid).collection(scope);

    final qs = await col
        .where('pendingSync', isEqualTo: true)
        .get(const GetOptions(source: Source.server));
    if (qs.docs.isEmpty) return;

    for (final d in qs.docs) {
      await _marcarSincronizado(d);
    }
  }

  /// Hidrata dados do lembrete a partir do tratamento (forçando Source.server)
  /// Campos alvo (se ausentes no lembrete): nomeMedicamento, concentracaoMedicamento,
  /// qtdMedicamento, unidadeMedida, etc.
  static Future<Map<String, dynamic>> _hydrateFromTratamento({
    required String pacienteUid,
    required Map<String, dynamic> lembreteData,
  }) async {
    final out = Map<String, dynamic>.from(lembreteData);

    bool precisaNome   = _isEmpty(out['nomeMedicamento']);
    bool precisaConc   = _isEmpty(out['concentracaoMedicamento']);
    bool precisaQtd    = _isEmpty(out['qtdMedicamento']);
    bool precisaUnid   = _isEmpty(out['unidadeMedida']);

    // Se já tem tudo, retorna
    if (!precisaNome && !precisaConc && !precisaQtd && !precisaUnid) {
      return out;
    }

    final String? idTratamento = (out['idTratamento'] as String?)?.trim();
    if (idTratamento == null || idTratamento.isEmpty) {
      return out; // sem como hidratar
    }

    // Tenta cache primeiro
    Map<String, dynamic>? tData = _tratamentosCache[idTratamento];

    // Se não tem em cache, busca no servidor
    if (tData == null) {
      try {
        final tDoc = await FirebaseFirestore.instance
            .collection('usuarios').doc(pacienteUid)
            .collection('tratamentos').doc(idTratamento)
            .get(const GetOptions(source: Source.server));
        if (tDoc.exists) {
          tData = tDoc.data();
          if (tData != null) _tratamentosCache[idTratamento] = tData;
        }
      } catch (_) {}
    }

    if (tData != null) {
      if (precisaNome) out['nomeMedicamento'] = (tData['nomeMedicamento'] ?? '').toString();
      if (precisaConc) out['concentracaoMedicamento'] = (tData['concentracaoMedicamento'] ?? '').toString();
      if (precisaQtd)  out['qtdMedicamento'] = (tData['qtdMedicamento'] ?? tData['qtdPorDose'] ?? '').toString();
      if (precisaUnid) out['unidadeMedida']  = (tData['unidadeMedida'] ?? tData['formaFarmaceutica'] ?? '').toString();

      // Se quiser, pode copiar outras chaves úteis:
      out['tipoMedicamento'] ??= (tData['tipoMedicamento'] ?? '');
    }

    return out;
  }

  /// Pré-busca em lote de tratamentos por ids (chunk de 10 para whereIn)
  static Future<void> _prefetchTratamentos({
    required String pacienteUid,
    required List<String> ids,
  }) async {
    const chunkSize = 10;
    for (var i = 0; i < ids.length; i += chunkSize) {
      final slice = ids.sublist(i, i + chunkSize > ids.length ? ids.length : i + chunkSize);
      try {
        final qs = await FirebaseFirestore.instance
            .collection('usuarios').doc(pacienteUid)
            .collection('tratamentos')
            .where(FieldPath.documentId, whereIn: slice)
            .get(const GetOptions(source: Source.server));
        for (final d in qs.docs) {
          final data = d.data();
          _tratamentosCache[d.id] = data;
        }
      } catch (_) {
        // Em algumas versões/planos, whereIn pode falhar ou ultrapassar limites — ignore e deixe para GET individual
      }
    }
  }

  /// Persiste no documento do lembrete os campos que estavam faltando (desnormalização)
  static Future<void> _persistirDesnormalizacaoSeFaltava(
      DocumentSnapshot<Map<String, dynamic>> doc,
      Map<String, dynamic> antes,
      Map<String, dynamic> depois,
      ) async {
    final updates = <String, dynamic>{};

    void putIfMissing(String k) {
      if (_isEmpty(antes[k]) && !_isEmpty(depois[k])) updates[k] = depois[k];
    }

    putIfMissing('nomeMedicamento');
    putIfMissing('concentracaoMedicamento');
    putIfMissing('qtdMedicamento');
    putIfMissing('unidadeMedida');
    putIfMissing('tipoMedicamento');

    if (updates.isNotEmpty) {
      // Não toque em pendingSync aqui — quem controla é o fluxo principal
      try {
        await doc.reference.update(updates);
      } catch (_) {}
    }
  }

  /// Constrói o corpo com os mesmos campos usados no app (robusto a nulos)
  static String _montarCorpoPadrao(Map<String, dynamic> m) {
    final nome = (m['nomeMedicamento'] ?? '').toString().trim();
    final conc = (m['concentracaoMedicamento'] ?? '').toString().trim();
    final qtd = (m['qtdMedicamento'] ?? '').toString().trim();
    final unidade = (m['unidadeMedida'] ?? '').toString().trim();

    final temNome = nome.isNotEmpty;
    final temConc = conc.isNotEmpty;
    final temQtd = qtd.isNotEmpty;
    final temUnid = unidade.isNotEmpty;

    final p1 = [
      if (temNome) nome,
      if (temConc) conc,
    ].join(' ').trim();

    String p2 = '';
    if (temQtd && temUnid) {
      p2 = '($qtd $unidade)';
    } else if (temQtd) {
      p2 = '($qtd)';
    } else if (temUnid) {
      p2 = '($unidade)';
    }

    final corpo = [p1, p2].where((s) => s.isNotEmpty).join(' ').trim();
    return corpo.isNotEmpty ? corpo : 'Lembrete de medicamento';
  }

  static bool _isEmpty(dynamic v) {
    if (v == null) return true;
    if (v is String) return v.trim().isEmpty;
    return false;
  }

  static int? _toIntOrNull(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is String) return int.tryParse(v);
    return null;
  }

  static Future<void> _marcarSincronizado(
      DocumentSnapshot<Map<String, dynamic>> d, {
        Map<String, dynamic>? extra,
      }) {
    return d.reference.update({
      'pendingSync': false,
      'classSync': "bq_sync",
      'lastSyncedAt': FieldValue.serverTimestamp(),
      if (extra != null) ...extra,
    });
  }
}

/// Dispatcher de background (precisa ser top-level, com entry-point)
@pragma('vm:entry-point')
void bgCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    return await BgSync.runPeriodicTask(task, Map<String, dynamic>.from(inputData ?? {}));
  });
}
