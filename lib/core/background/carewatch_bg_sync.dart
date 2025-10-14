import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:workmanager/workmanager.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tzData;

import '../services/notification_service.dart';
import 'package:smartmed/firebase_options.dart';
import 'dart:math' as math;

class CarewatchSync {
  static const taskName = 'alertamed-carewatch-1h';

  /// Registrar quando o CUIDADOR faz login.
  static Future<void> register({required String cuidadorUid}) async {
    await Workmanager().registerPeriodicTask(
      'bg-$taskName-$cuidadorUid',
      taskName,
      frequency: const Duration(hours: 1),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      constraints: Constraints(networkType: NetworkType.connected),
      inputData: {'cuidadorUid': cuidadorUid},
      backoffPolicy: BackoffPolicy.exponential,
    );
  }

  /// Cancelar no logout do cuidador.
  static Future<void> cancelAll() async {
    // Não existe "wildcard" no cancelByUniqueName; se quiser granular,
    // guarde o nome único em algum lugar. Aqui, um cancelAll simples:
    await Workmanager().cancelAll();
  }

  @pragma('vm:entry-point')
  static Future<bool> runPeriodicTask(String task, Map<String, dynamic>? input) async {
    try {
      // bootstrap
      tzData.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('America/Sao_Paulo'));

      try {
        await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      } catch (_) {}

      try {
        await NotificationService().init();
      } catch (_) {}

      final cuidadorUid = (input?['cuidadorUid'] as String?)?.trim();
      if (cuidadorUid == null || cuidadorUid.isEmpty) return false;
      // 📝 Log no Firestore (auditoria)
      try {
        await FirebaseFirestore.instance
            .collection('usuarios').doc(cuidadorUid)
            .collection('_debugTasks').add({
          'task': 'CarewatchSync',
          'ts': FieldValue.serverTimestamp(),
          'note': 'dispatcher OK',
        });
      } catch (_) {}
      await _scanAndNotify(cuidadorUid);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _scanAndNotify(String cuidadorUid) async {
    final db = FirebaseFirestore.instance;
    final notif = NotificationService();

    // 1) vínculos onde EU sou cuidador e está ativo
    final vincQs = await db
        .collection('usuarios').doc(cuidadorUid)
        .collection('vinculos')
        .where('meuPapel', isEqualTo: 'cuidador')
        .where('status', isEqualTo: 'ativo')
        .get(const GetOptions(source: Source.server));

    if (vincQs.docs.isEmpty) return;

    final agora = DateTime.now();
    final tolerancia = const Duration(minutes: 15);
    final janela = const Duration(hours: 24);
    final limite = agora.subtract(janela);

    // cache de nomes
    final Map<String, String> nomePacCache = {};

    for (final vinc in vincQs.docs) {
      final pacienteUid = vinc.id;
      if (pacienteUid.isEmpty) continue;

      // 2) Lembretes atrasados (não tomados/adiados/cancelados)
      final lembQs = await db
          .collection('usuarios').doc(pacienteUid)
          .collection('lembretes')
          .where('dataHoraAgendado', isLessThanOrEqualTo: Timestamp.fromDate(agora.subtract(tolerancia)))
          .where('dataHoraAgendado', isGreaterThanOrEqualTo: Timestamp.fromDate(limite))
          .where('tomado', isEqualTo: false)
          .where('adiado', isEqualTo: false)
          .where('cancelado', isEqualTo: false)
          .limit(50)
          .get(const GetOptions(source: Source.server));

      if (lembQs.docs.isEmpty) continue;

      Future<String> nomePaciente() async {
        if (nomePacCache.containsKey(pacienteUid)) return nomePacCache[pacienteUid]!;
        try {
          final pub = await db.collection('usuarios_publicos').doc(pacienteUid)
              .get(const GetOptions(source: Source.server));
          final nome = (pub.data()?['displayName'] ?? 'Paciente').toString();
          nomePacCache[pacienteUid] = nome;
          return nome;
        } catch (_) {
          return 'Paciente';
        }
      }

      for (final d in lembQs.docs) {
        final m = d.data();
        // evita repetir alerta para o mesmo cuidador
        final Map<String, dynamic> alertas =
            (m['alertasCuidador'] as Map?)?.cast<String, dynamic>() ?? {};
        if (alertas[cuidadorUid] == true) continue;

        final ts = m['dataHoraAgendado'] as Timestamp?;
        if (ts == null) continue;
        final quando = ts.toDate();

        final nomePac = await nomePaciente();
        final nomeMed = (m['nomeMedicamento'] ?? '').toString().trim();
        final conc    = (m['concentracaoMedicamento'] ?? '').toString().trim();
        final qtd     = (m['qtdMedicamento'] ?? '').toString().trim();
        final unid    = (m['unidadeMedida'] ?? '').toString().trim();

        String medStr = [nomeMed, conc].where((s) => s.isNotEmpty).join(' ').trim();
        final doseStr = [if (qtd.isNotEmpty) qtd, if (unid.isNotEmpty) unid].join(' ').trim();
        if (doseStr.isNotEmpty) {
          medStr = medStr.isNotEmpty ? '$medStr ($doseStr)' : '($doseStr)';
        }
        if (medStr.isEmpty) medStr = 'medicamento';

        final hh = quando.hour.toString().padLeft(2, '0');
        final mm = quando.minute.toString().padLeft(2, '0');

        final title = 'Atraso de medicação';
        final body  = '$nomePac atrasou $medStr das $hh:$mm.';

        // ID estável (cuidador + paciente + lembrete)
        final idNot = _stableId('${cuidadorUid}::$pacienteUid::${d.id}');

        try {
          // tenta exibir agora; se falhar, agenda pra +5s
          await notif.showNowCarewatch(
            id: idNot,
            title: title,
            body: body,
            pacienteUid: pacienteUid,
            lembreteId: d.id,
          );
        } catch (_) {
          await notif.scheduleCarewatchOneShot(
            id: idNot,
            title: title,
            body: body,
            when: DateTime.now().add(const Duration(seconds: 5)),
            pacienteUid: pacienteUid,
            lembreteId: d.id,
          );
        }

        // marca para não avisar de novo o mesmo cuidador
        try {
          await d.reference.update({
            'alertasCuidador.$cuidadorUid': true,
            'alertasCuidadorAt.$cuidadorUid': FieldValue.serverTimestamp(),
          });
        } catch (_) {/* ignora */}
      }
    }
  }

  /// Hash 32-bit estável para ID de notificação
  static int _stableId(String s) {
    int h = 0;
    for (int i = 0; i < s.length; i++) {
      h = 0x1fffffff & (h + s.codeUnitAt(i));
      h = 0x1fffffff & (h + ((0x0007ffff & h) << 10));
      h ^= (h >> 6);
    }
    h = 0x1fffffff & (h + ((0x03ffffff & h) << 3));
    h ^= (h >> 11);
    h = 0x1fffffff & (h + ((0x00003fff & h) << 15));
    if (h < 0) h = -h;
    // evita colidir com IDs dos lembretes do paciente, se quiser reservar um range:
    return math.max(h, 100000); // ex.: garante 6 dígitos
  }
}
