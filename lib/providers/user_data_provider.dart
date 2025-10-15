import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/background/bg_sync.dart';
import '../core/services/notification_service.dart';

import 'package:workmanager/workmanager.dart';
import '../core/background/carewatch_bg_sync.dart';
/// Provider responsável por separar dados do usuário logado (self)
/// e do usuário em contexto (paciente atual) + controle de permissões.
///
/// - Sempre do LOGADO (self): dadosUsuario, horariosRefeicoes, horariosSilenciosos, vinculosMap
/// - Dependente do CONTEXTO: sintomas, lembretes, tratamentosMap, estoqueMap, infoMedica
///
/// Permissões:
/// - Quando contexto == self: leitura sempre permitida; edição/criação de tratamentos
///   é bloqueada se houver em qualquer vínculo do LOGADO (meuPapel="paciente", status="ativo")
///   o escopo "bloquear_paciente_editar".
/// - Quando contexto != self: busca /usuarios/{contexto}/vinculos/{userId}
///   e usa seus "scopes" (se status = "ativo") para decidir.
class UsuarioProvider extends ChangeNotifier {
  // ========================= CAMPOS PRINCIPAIS =========================

  // ---- Self (usuário logado) ----
  Map<String, dynamic> dadosUsuario = {};
  List<Map<String, dynamic>> horariosRefeicoes = [];
  List<Map<String, dynamic>> horariosSilenciosos = [];
  Map<String, Map<String, dynamic>> vinculosMap = {};

  // ---- Dependentes do contexto (paciente atual) ----
  List<Map<String, dynamic>> sintomas = [];
  List<Map<String, dynamic>> lembretes = [];
  Map<String, dynamic> tratamentosMap = {};
  Map<String, dynamic> estoqueMap = {};
  Map<String, dynamic> infoMedica = {};

  // ---- Controle de contexto ----
  String? _contextoUsuarioId;
  String get contextoUsuarioId => _contextoUsuarioId ?? userId;
  bool get isContextoSouEu => contextoUsuarioId == userId;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subPendLembretes;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subPendTratamentos;


  // ---- Permissões do contexto (resumo) ----
  // Scopes que o LOGADO tem sobre o PACIENTE EM CONTEXTO (quando contexto != self)
  List<String> _contextoScopes = [];
  bool _contextoVinculoAtivo = false;

  String _contextoNomePublico = '';
  String get contextoNomePublico => _contextoNomePublico;

  // ---- Estado / Infra ----
  bool isLoading = true;
  bool isLoadingContexto = false;
  StreamSubscription<User?>? _authSub;
  Timer? _authNullDebounce;

  String get userId => FirebaseAuth.instance.currentUser?.uid ?? '';

  // ========================= CONSTRUTOR / CICLO DE VIDA =========================

  UsuarioProvider() {
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) {
        // Espera a hidratação do Firebase antes de limpar estado
        _authNullDebounce?.cancel();
        _authNullDebounce = Timer(const Duration(milliseconds: 900), () async {
          final stillNull = FirebaseAuth.instance.currentUser == null;
          if (stillNull) {
            clearState();          // continua sem usuário -> limpa
          } else {
            await fetchData();     // já hidratou -> carrega dados
          }
        });
      } else {
        // Usuário notificado pela stream: cancela debounce e carrega dados
        _authNullDebounce?.cancel();
        unawaited(fetchData());
      }
    });
  }

  @override
  void dispose() {
    _authNullDebounce?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  // ========================= FIRESTORE HELPERS =========================

  CollectionReference get _usersCol =>
      FirebaseFirestore.instance.collection('usuarios');

  DocumentReference get _selfRef => _usersCol.doc(userId);
  DocumentReference get _ctxRef => _usersCol.doc(contextoUsuarioId);

  // ========================= FLUXO DE CARREGAMENTO =========================

  Future<void> fetchData() async {
    if (userId.isEmpty) {
      isLoading = false;
      notifyListeners();
      return;
    }

    isLoading = true;
    notifyListeners();

    try {
      // 1) Carrega SELF
      await Future.wait([
        _loadDadosUsuario(_selfRef), // restaura contexto salvo
        _loadHorariosRefeicoes(_selfRef),
        _loadHorariosSilenciosos(_selfRef),
        _loadVinculos(_selfRef),
      ]);

      // Garante contexto válido
      final ctxUid = _contextoUsuarioId ?? userId;
      _contextoUsuarioId = ctxUid;

      // 2) Carrega CONTEXTO (dados + permissões)
      await _fetchContextoData(ctxUid);
      await carewatchScanNow();
    } finally {
      _stopPendingListeners();
      if (isContextoSouEu) _startPendingListeners();
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _fetchContextoData(String ctxUid) async {
    isLoadingContexto = true;
    notifyListeners();

    try {
      final ctxRef = _usersCol.doc(ctxUid);
      await Future.wait([
        _loadSintomas(ctxRef),
        _loadLembretes(ctxRef),
        _loadTratamentos(ctxRef),
        _loadEstoque(ctxRef),
        _loadInfoMedicaDireto(ctxRef),
        _loadPermissoesDoContexto(ctxRef),
        _loadNomePublico(ctxUid),
      ]);
    } finally {
      isLoadingContexto = false;
      notifyListeners();
    }
  }
  Future<void> onLogin() async {
    // ... sua lógica
    if (isContextoSouEu && userId.isNotEmpty) {
      await BgSync.register(pacienteUid: userId);
      await _ensureCarewatchRegisteredIfNeeded();
    }

    fetchData();
  }

  Future<void> _ensureCarewatchRegisteredIfNeeded() async {
    if (userId.isEmpty) return;
    try {
      final qs = await FirebaseFirestore.instance
          .collection('usuarios').doc(userId)
          .collection('vinculos')
          .where('meuPapel', isEqualTo: 'cuidador')
          .where('status', isEqualTo: 'ativo')
          .limit(1)
          .get(const GetOptions(source: Source.server));
      if (qs.docs.isNotEmpty) {
        await CarewatchSync.register(cuidadorUid: userId);
      }
    } catch (_) {
      // offline/erro -> ignora; próxima rodada tenta de novo
    }
  }

  Future<void> logout() async {

    await Workmanager().cancelAll();     // cancela BgSync + CarewatchSync

    clearState();
  }



  Future<void> setContextoUsuario(String uid, {bool persist = true}) async {
    if (_contextoUsuarioId == uid) return;

    _contextoUsuarioId = uid;

    await _ensureCarewatchRegisteredIfNeeded();
    notifyListeners();

    await _fetchContextoData(uid);

    if (persist && userId.isNotEmpty) {
      try {
        await _selfRef.set({'contextoUsuarioId': uid}, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Erro ao persistir contextoUsuarioId: $e');
      }
    }
    _stopPendingListeners();
    if (isContextoSouEu) _startPendingListeners();
  }

  Future<void> _loadNomePublico(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('usuarios_publicos')
          .doc(uid)
          .get();

      if (doc.exists && doc.data() != null) {
        final nome = (doc.data()?['displayName'] as String?)?.trim() ?? '';
        _contextoNomePublico = nome;
      } else {
        _contextoNomePublico = '';
      }
    } catch (e) {
      debugPrint('Erro ao carregar nome público: $e');
      _contextoNomePublico = '';
    }
  }

  // Se quiser poder atualizar manualmente:
  Future<void> refreshContextoNomePublico() async {
    if (contextoUsuarioId.isEmpty) return;
    await _loadNomePublico(contextoUsuarioId);
    notifyListeners();
  }

  void clearState() {
    // Self
    dadosUsuario = {};
    horariosRefeicoes = [];
    horariosSilenciosos = [];
    vinculosMap = {};

    // Contexto
    sintomas = [];
    lembretes = [];
    tratamentosMap = {};
    estoqueMap = {};
    infoMedica = {};

    // Permissões de contexto
    _contextoScopes = [];
    _contextoVinculoAtivo = false;

    // Flags
    isLoading = false;
    isLoadingContexto = false;

    _contextoUsuarioId = null;
    _stopPendingListeners();
    notifyListeners();
  }

  // ✅ Deixe a função aceitar nulo e trate campos ausentes
  String notifBodyFromTrat(Map<String, dynamic>? t) {
    if (t == null) return 'Lembrete de medicamento';

    final nome = (t['nomeMedicamento'] ?? '').toString().trim();
    final conc = (t['concentracaoMedicamento'] ?? '').toString().trim();

    // use o que você realmente salva no Firestore:
    // se usa 'qtdMedicamento' e 'unidadeMedida', caia neles;
    // se o seu doc tiver 'dosagem', também cobre.
    final dose = (t['qtdMedicamento'] ?? t['dosagem'] ?? '').toString().trim();
    final un   = (t['unidadeMedida'] ?? '').toString().trim();

    if (nome.isNotEmpty && conc.isNotEmpty && dose.isNotEmpty && un.isNotEmpty) {
      return '$nome $conc ($dose $un)';
    }
    if (nome.isNotEmpty && conc.isNotEmpty) return '$nome $conc';
    if (nome.isNotEmpty) return nome;

    return 'Lembrete de medicamento';
  }

  /// Busca um tratamento específico direto do servidor (opção padrão),
  /// atualiza o cache local (tratamentosMap) se `updateProvider` = true
  /// e retorna o mapa do tratamento (ou null se não existir).
  Future<Map<String, dynamic>?> getTratamentoFresh(
      String idTratamento, {
        bool updateProvider = true,
        bool preferServer = true, // se false, tenta cache e cai pro server
      }) async {
    if (contextoUsuarioId.isEmpty || idTratamento.isEmpty) return null;

    final docRef = _usersCol
        .doc(contextoUsuarioId)
        .collection('tratamentos')
        .doc(idTratamento);

    try {
      // Tenta servidor primeiro (evita retornar dado velho do cache)
      final doc = await docRef.get(
        preferServer
            ? const GetOptions(source: Source.server)
            : const GetOptions(source: Source.cache),
      );

      // Se preferiu cache e não achou, tenta o servidor como fallback
      final snapshot = (doc.exists || preferServer)
          ? doc
          : await docRef.get(const GetOptions(source: Source.server));

      if (!snapshot.exists || snapshot.data() == null) {
        return null;
      }

      final data = snapshot.data()!;
      data['idTratamento'] = snapshot.id;

      if (updateProvider) {
        tratamentosMap[idTratamento] = data;
        notifyListeners();
      }

      return data;
    } catch (e) {
      debugPrint('getTratamentoFresh erro: $e');

      // Fallback final: tenta cache se o server falhar (offline, etc.)
      try {
        final cacheDoc =
        await docRef.get(const GetOptions(source: Source.cache));
        if (cacheDoc.exists && cacheDoc.data() != null) {
          final data = cacheDoc.data()!;
          data['idTratamento'] = cacheDoc.id;
          if (updateProvider) {
            tratamentosMap[idTratamento] = data;
            notifyListeners();
          }
          return data;
        }
      } catch (_) {}
      return null;
    }
  }


  void _startPendingListeners() {
    // só no próprio contexto (um device por usuário)
    if (!isContextoSouEu || contextoUsuarioId.isEmpty) return;

    final colL = FirebaseFirestore.instance
        .collection('usuarios').doc(contextoUsuarioId)
        .collection('lembretes')
        .where('pendingSync', isEqualTo: true);

    _subPendLembretes?.cancel();
    _subPendLembretes = colL.snapshots().listen((qs) async {
      final notif = NotificationService();
      for (final d in qs.docs) {
        final m = d.data();

        // cancelar/agendar conforme status
        if (m['adiado'] == true || m['cancelado'] == true) {
          final int? idN = m['idNotificacao'] as int?;
          if (idN != null) {
            try { await notif.cancelNotification(idN); } catch (_) {}
          }
        } else {
          // (re)agenda
          final int? idN = m['idNotificacao'] as int?;
          final ts = m['dataHoraAgendado'] as Timestamp?;
          if (idN != null && ts != null) {
            final trat = await getTratamentoFresh(
              (m['idTratamento'] ?? '').toString(),
              updateProvider: false,
              preferServer: true,
            );
            final body = notifBodyFromTrat(trat);
            try {
              await notif.scheduleNotification(
                id: idN,
                title: 'Hora do medicamento',
                body: body,
                scheduledDateTime: ts.toDate(),
                idLembrete: d.id,
                idUsuario: contextoUsuarioId,
              );
            } catch (_) {}
          }
        }

        // marca sincronizado
        await d.reference.update({
          'pendingSync': false,
          'classSync': "provider_sync",
          'lastSyncedAt': FieldValue.serverTimestamp(),
        });
      }
    });

    // Se você deriva lembretes a partir de tratamentos, habilite também:
    final colT = FirebaseFirestore.instance
        .collection('usuarios').doc(contextoUsuarioId)
        .collection('tratamentos')
        .where('pendingSync', isEqualTo: true);

    _subPendTratamentos?.cancel();
    _subPendTratamentos = colT.snapshots().listen((qs) async {
      for (final d in qs.docs) {
        final t = d.data();
        // Se precisar criar/atualizar lembretes locais a partir do tratamento, faça aqui.
        // Caso contrário, basta marcar como sincronizado:
        await d.reference.update({
          'pendingSync': false,
          'lastSyncedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  void _stopPendingListeners() {
    _subPendLembretes?.cancel();
    _subPendTratamentos?.cancel();
    _subPendLembretes = null;
    _subPendTratamentos = null;
  }

  // ========================= LOADERS SELF =========================

  Future<void> _loadDadosUsuario(DocumentReference usuarioRef) async {
    try {
      final doc = await usuarioRef.get();
      if (doc.exists && doc.data() != null) {
        dadosUsuario = doc.data() as Map<String, dynamic>;
        final ctx = (dadosUsuario['contextoUsuarioId'] as String?);
        _contextoUsuarioId = (ctx != null && ctx.isNotEmpty) ? ctx : userId;
      } else {
        dadosUsuario = {};
        _contextoUsuarioId = userId;
      }
    } catch (e) {
      debugPrint('Erro ao carregar dados do usuário: $e');
      dadosUsuario = {};
      _contextoUsuarioId = userId;
    }
  }

  Future<void> _loadVinculos(DocumentReference usuarioRef) async {
    try {
      final snap = await usuarioRef.collection('vinculos').get();
      vinculosMap = {for (final d in snap.docs) d.id: d.data()};
    } catch (e) {
      debugPrint('Erro ao carregar vínculos: $e');
      vinculosMap = {};
    }
  }

  // ========================= LOADERS CONTEXTO =========================

  Future<void> _loadSintomas(DocumentReference usuarioRef) async {
    try {
      final snapshot = await usuarioRef.collection('sintomas').get();
      sintomas = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      debugPrint('Erro ao carregar sintomas: $e');
      sintomas = [];
    }
  }

  Future<void> _loadLembretes(DocumentReference usuarioRef) async {
    try {
      final snapshot = await usuarioRef.collection('lembretes').get();
      lembretes = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      debugPrint('Erro ao carregar lembretes: $e');
      lembretes = [];
    }
  }

  Future<void> _loadTratamentos(DocumentReference usuarioRef) async {
    try {
      final tratamentosSnapshot = await usuarioRef.collection('tratamentos').get();
      final tratamentos = tratamentosSnapshot.docs.map((doc) {
        final data = doc.data();
        data['idTratamento'] = doc.id;
        return data;
      }).toList();

      tratamentosMap = {
        for (var tratamento in tratamentos) tratamento['idTratamento']: tratamento,
      };
    } catch (e) {
      debugPrint('Erro ao carregar tratamentos: $e');
      tratamentosMap = {};
    }
  }

  Future<void> _loadEstoque(DocumentReference usuarioRef) async {
    try {
      final snapshot = await usuarioRef.collection('estoque').get();
      estoqueMap = {for (var doc in snapshot.docs) doc.id: doc.data()};
    } catch (e) {
      debugPrint('Erro ao carregar estoque: $e');
      estoqueMap = {};
    }
  }

  Future<void> _loadInfoMedicaDireto(DocumentReference usuarioRef) async {
    try {
      final doc = await usuarioRef.collection('informacoesmedicas').doc('perfil').get();
      infoMedica = (doc.exists && doc.data() != null) ? doc.data()! : {};
    } catch (e) {
      debugPrint('Erro ao carregar informacoesmedicas: $e');
      infoMedica = {};
    }
  }

  // ========================= PERMISSÕES (CORE) =========================

  /// Carrega as permissões do LOGADO sobre o CONTEXTO:
  /// Lê /usuarios/{contexto}/vinculos/{userId} e aplica se status = "ativo".
  Future<void> _loadPermissoesDoContexto(DocumentReference ctxRef) async {
    // Se estou no meu próprio contexto, não há doc de vínculo a ler para permissões
    if (isContextoSouEu) {
      _contextoScopes = [];         // não usados nesse caso (regras do "self" dominam)
      _contextoVinculoAtivo = true; // leitura sempre permitida em self
      return;
    }

    try {
      final doc = await ctxRef.collection('vinculos').doc(userId).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data() as Map<String, dynamic>;
        final status = (data['status'] as String?) ?? 'revogado';
        _contextoVinculoAtivo = status == 'ativo';
        final scopes = (data['scopes'] as List?)?.cast<String>() ?? <String>[];
        _contextoScopes = scopes;
      } else {
        _contextoVinculoAtivo = false;
        _contextoScopes = [];
      }
    } catch (e) {
      debugPrint('Erro ao carregar permissões do contexto: $e');
      _contextoVinculoAtivo = false;
      _contextoScopes = [];
    }
  }


  /// Tem o escopo X sobre o contexto atual?
  bool _hasNivelPaciente(String nivelAlvo) {
    for (final entry in vinculosMap.entries) {
      final data = entry.value;
      final meuPapel = (data['meuPapel'] as String?) ?? '';
      final status = (data['status'] as String?) ?? 'revogado';
      final nivel = (data['nivel'] as String?) ?? '';

      if (meuPapel != 'paciente' || status != 'ativo') continue;

      if (nivel == nivelAlvo) {
        return true;
      }
    }
    return false;
  }

  // ====== GETTERS PRONTOS PARA A UI ======

  /// Se estou no meu próprio contexto, retorna true se tenho bloqueio de edição - permisao de visualizar e criar/editar tratamentos.
  bool get isPacienteComEdicaoBloqueada {
    if (!isContextoSouEu) return false;
    return _hasNivelPaciente('acesso_completo');
  }

  /// Se estou no meu próprio contexto, retorna true se tenho gerenciamento restrito - permisao de visualizar e criar/editar tratamentos.
  bool get isPacienteComGerenciamentoRestrito {
    if (!isContextoSouEu) return false;
    return _hasNivelPaciente('gerenciamento_restrito');
  }

  /// Se estou no meu próprio contexto, retorna true se tenho só visualização.
  bool get isPacienteComVisualizacao {
    if (!isContextoSouEu) return false;
    return _hasNivelPaciente('visualizacao_basica');
  }

  /// Quando estou no meu próprio contexto e algum cuidador tem
  /// 'bloquear_paciente_editar', devo impedir UI de editar/criar.
  bool get bloquearEdicaoPorPoliticaDoCuidador =>
      isContextoSouEu && isPacienteComEdicaoBloqueada;
  /// Pode editar/criar tratamentos no contexto atual?
  /// - Se for self: respeita o bloqueio imposto por cuidador.
  /// - Se for outro paciente: exige vínculo ativo + 'edicao_tratamentos'.
  bool get podeEditarTratamentosNoContexto {
    if (isContextoSouEu) {
      return !bloquearEdicaoPorPoliticaDoCuidador;
    }
    // estes campos já são mantidos pelo _loadPermissoesDoContexto
    return _contextoVinculoAtivo && _contextoScopes.contains('edicao_tratamentos');
  }

  /// Pode gerir lembretes (criar/editar/apagar) no contexto atual?
  /// - Self: sim (seguindo a política geral do app).
  /// - Outro paciente: exige 'lembretes'.
  bool get podeGerirLembretesNoContexto {
    if (isContextoSouEu) return true;
    return _contextoVinculoAtivo && _contextoScopes.contains('lembretes');
  }
  // ========================= REFRESH (SELF x CONTEXTO) =========================

  Future<void> refreshSintomas() async {
    if (contextoUsuarioId.isEmpty) return;
    try {
      final snapshot = await _ctxRef
          .collection('sintomas')
          .orderBy('dataHora', descending: true)
          .get();

      sintomas = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      notifyListeners();
    } catch (e) {
      debugPrint('Erro ao atualizar sintomas: $e');
    }
  }

  Future<void> refreshInfoMedica() async {
    await _loadInfoMedicaDireto(_ctxRef);
    notifyListeners();
  }

  Future<void> refreshVinculos() async {
    if (userId.isEmpty) return;
    try {
      final snap = await _selfRef.collection('vinculos').get();
      vinculosMap = {for (final d in snap.docs) d.id: d.data()};
      notifyListeners();
    } catch (e) {
      debugPrint('Erro ao atualizar vínculos: $e');
    }
  }

  Future<void> refreshPermissoesContexto() async {
    await _loadPermissoesDoContexto(_ctxRef);
    notifyListeners();
  }

  // ========================= HORÁRIOS (SELF) =========================

  List<Map<String, dynamic>> _defaultHorariosRefeicoes() => [
    {
      'dia': 'Padrão',
      'horaCafe': '07:30',
      'horaAlmoco': '12:00',
      'horaJanta': '19:00',
    },
  ];

  List<Map<String, dynamic>> _defaultHorariosSilenciosos() => [
    {'dia': 'Todos', 'horaInicio': '22:00', 'horaFim': '06:00'},
  ];

  Future<void> _loadHorariosRefeicoes(DocumentReference usuarioRef) async {
    try {
      final doc = await usuarioRef.get();
      final data = (doc.data() as Map<String, dynamic>?) ?? {};
      final list =
      (data['horariosRefeicoes'] as List?)?.cast<Map<String, dynamic>>();
      horariosRefeicoes =
      (list == null || list.isEmpty) ? _defaultHorariosRefeicoes() : list;
    } catch (e) {
      debugPrint('Erro ao carregar horariosRefeicoes: $e');
      horariosRefeicoes = _defaultHorariosRefeicoes();
    }
  }

  Future<void> _loadHorariosSilenciosos(DocumentReference usuarioRef) async {
    try {
      final doc = await usuarioRef.get();
      final data = (doc.data() as Map<String, dynamic>?) ?? {};
      final list =
      (data['horariosSilenciosos'] as List?)?.cast<Map<String, dynamic>>();
      horariosSilenciosos =
      (list == null || list.isEmpty) ? _defaultHorariosSilenciosos() : list;
    } catch (e) {
      debugPrint('Erro ao carregar horariosSilenciosos: $e');
      horariosSilenciosos = _defaultHorariosSilenciosos();
    }
  }

  Future<void> salvarHorariosRefeicoes(List<Map<String, dynamic>> novos) async {
    if (userId.isEmpty) return;
    try {
      await _selfRef.set({'horariosRefeicoes': novos}, SetOptions(merge: true));
      horariosRefeicoes = novos;
      notifyListeners();
    } catch (e) {
      debugPrint('Erro ao salvar horariosRefeicoes: $e');
    }
  }

  Future<void> salvarHorariosSilenciosos(
      List<Map<String, dynamic>> novos,
      ) async {
    if (userId.isEmpty) return;
    try {
      await _selfRef.set({'horariosSilenciosos': novos}, SetOptions(merge: true));
      horariosSilenciosos = novos;
      notifyListeners();
    } catch (e) {
      debugPrint('Erro ao salvar horariosSilenciosos: $e');
    }
  }

  // ========================= UTILIDADES =========================

  List<Map<String, String>> _toStringList(List<Map<String, dynamic>> src) {
    return src
        .map((m) => m.map((k, v) => MapEntry(k, v?.toString() ?? '')))
        .toList();
  }

  Map<String, String> horarioRefeicaoParaDia(String dia) {
    final List<Map<String, String>> horariosRefeicoesStr = _toStringList(
      horariosRefeicoes,
    );

    final item = horariosRefeicoesStr.firstWhere(
          (h) => (h['dia'] ?? '').toLowerCase() == dia.toLowerCase(),
      orElse: () => <String, String>{},
    );

    if (item.isNotEmpty) return item;

    return horariosRefeicoesStr.firstWhere(
          (h) {
        final d = (h['dia'] ?? '').toLowerCase();
        return d == 'padrão' || d == 'padrao';
      },
      orElse: () => _toStringList(_defaultHorariosRefeicoes()).first,
    );
  }

  /// Varre, agora, os pacientes que o LOGADO cuida e emite notificações
  /// de lembretes atrasados (não tomados/adiados/cancelados).
  /// Retorna a quantidade de alertas emitidos.
  ///
  /// Use:
  ///   final qtd = await provider.carewatchScanNow();
  ///   if (qtd > 0) { /* ...atualize UI, badge, etc. */ }
  Future<int> carewatchScanNow({
    Duration tolerancia = const Duration(minutes: 15),
    Duration janela = const Duration(hours: 24),
  }) async {
    final cuidadorUid = userId.trim();
    if (cuidadorUid.isEmpty) return 0;

    // Garante notificação pronta (idempotente)
    try { await NotificationService().init(); } catch (_) {}

    final db = FirebaseFirestore.instance;
    int totalAlertas = 0;

    // 1) vínculos onde EU sou cuidador e está ativo
    QuerySnapshot<Map<String, dynamic>> vincQs;
    try {
      vincQs = await db
          .collection('usuarios').doc(cuidadorUid)
          .collection('vinculos')
          .where('meuPapel', isEqualTo: 'cuidador')
          .where('status', isEqualTo: 'ativo')
          .get(const GetOptions(source: Source.server));
    } catch (_) {
      // offline? tenta cache como fallback
      vincQs = await db
          .collection('usuarios').doc(cuidadorUid)
          .collection('vinculos')
          .where('meuPapel', isEqualTo: 'cuidador')
          .where('status', isEqualTo: 'ativo')
          .get(const GetOptions(source: Source.cache));
    }
    if (vincQs.docs.isEmpty) return 0;

    final agora = DateTime.now();
    final limiteInicio = agora.subtract(janela);

    // cache simples de nomes públicos para evitar múltiplos gets
    final Map<String, String> nomePacCache = {};
    final notif = NotificationService();

    Future<String> _nomePaciente(String pacienteUid) async {
      if (nomePacCache.containsKey(pacienteUid)) return nomePacCache[pacienteUid]!;
      try {
        final pub = await db
            .collection('usuarios_publicos')
            .doc(pacienteUid)
            .get(const GetOptions(source: Source.server));
        final nome = (pub.data()?['displayName'] ?? 'Paciente').toString();
        nomePacCache[pacienteUid] = nome;
        return nome;
      } catch (_) {
        // fallback cache
        try {
          final pub = await db
              .collection('usuarios_publicos')
              .doc(pacienteUid)
              .get(const GetOptions(source: Source.cache));
          final nome = (pub.data()?['displayName'] ?? 'Paciente').toString();
          nomePacCache[pacienteUid] = nome;
          return nome;
        } catch (_) {
          return 'Paciente';
        }
      }
    }

    for (final vinc in vincQs.docs) {
      final pacienteUid = vinc.id;
      if (pacienteUid.isEmpty) continue;

      // 2) Lembretes atrasados da janela (<= agora - tolerância, >= limiteInicio)
      QuerySnapshot<Map<String, dynamic>> lembQs;
      try {
        lembQs = await db
            .collection('usuarios').doc(pacienteUid)
            .collection('lembretes')
            .where('dataHoraAgendado',
            isLessThanOrEqualTo:
            Timestamp.fromDate(agora.subtract(tolerancia)))
            .where('dataHoraAgendado',
            isGreaterThanOrEqualTo: Timestamp.fromDate(limiteInicio))
            .where('tomado', isEqualTo: false)
            .where('adiado', isEqualTo: false)
            .where('cancelado', isEqualTo: false)
            .limit(50)
            .get(const GetOptions(source: Source.server));
      } catch (_) {
        // offline fallback
        lembQs = await db
            .collection('usuarios').doc(pacienteUid)
            .collection('lembretes')
            .where('dataHoraAgendado',
            isLessThanOrEqualTo:
            Timestamp.fromDate(agora.subtract(tolerancia)))
            .where('dataHoraAgendado',
            isGreaterThanOrEqualTo: Timestamp.fromDate(limiteInicio))
            .where('tomado', isEqualTo: false)
            .where('adiado', isEqualTo: false)
            .where('cancelado', isEqualTo: false)
            .limit(50)
            .get(const GetOptions(source: Source.cache));
      }

      if (lembQs.docs.isEmpty) continue;

      final nomePac = await _nomePaciente(pacienteUid);

      for (final d in lembQs.docs) {
        final m = d.data();

        // evita repetir alerta para o mesmo cuidador
        final Map<String, dynamic> alertas =
            (m['alertasCuidador'] as Map?)?.cast<String, dynamic>() ?? {};
        if (alertas[cuidadorUid] == true) continue;

        final ts = m['dataHoraAgendado'] as Timestamp?;
        if (ts == null) continue;
        final quando = ts.toDate();

        final nomeMed = (m['nomeMedicamento'] ?? '').toString().trim();
        final conc    = (m['concentracaoMedicamento'] ?? '').toString().trim();
        final qtd     = (m['qtdMedicamento'] ?? '').toString().trim();
        final unid    = (m['unidadeMedida'] ?? '').toString().trim();

        String medStr =
        [nomeMed, conc].where((s) => s.isNotEmpty).join(' ').trim();
        final doseStr =
        [if (qtd.isNotEmpty) qtd, if (unid.isNotEmpty) unid].join(' ').trim();
        if (doseStr.isNotEmpty) {
          medStr = medStr.isNotEmpty ? '$medStr ($doseStr)' : '($doseStr)';
        }
        if (medStr.isEmpty) medStr = 'medicamento';

        final hh = quando.hour.toString().padLeft(2, '0');
        final mm = quando.minute.toString().padLeft(2, '0');

        final title = 'Atraso de medicação';
        final body  = '$nomePac atrasou $medStr das $hh:$mm.';

        // ID estável (cuidador + paciente + lembrete)
        final idNot = _stableIdCarewatch('${cuidadorUid}::$pacienteUid::${d.id}');

        // emite agora; se não conseguir, agenda +5s
        try {
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

        // marca para não avisar de novo este cuidador
        try {
          await d.reference.update({
            'alertasCuidador.$cuidadorUid': true,
            'alertasCuidadorAt.$cuidadorUid': FieldValue.serverTimestamp(),
          });
        } catch (_) {/* ignora falha de marcação */}

        totalAlertas++;
      }
    }

    return totalAlertas;
  }

  /// Hash 32-bit estável para IDs de notificação do Carewatch.
  /// Mantém separado dos IDs dos lembretes do paciente.
  int _stableIdCarewatch(String s) {
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
    return h < 100000 ? 100000 : h; // reserva faixa alta
  }

}
