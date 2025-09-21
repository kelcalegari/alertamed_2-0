import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  String get userId => FirebaseAuth.instance.currentUser?.uid ?? '';

  // ========================= CONSTRUTOR / CICLO DE VIDA =========================

  UsuarioProvider() {
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) {
        clearState();
      } else {
        fetchData();
      }
    });
  }

  @override
  void dispose() {
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
    } finally {
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

  Future<void> setContextoUsuario(String uid, {bool persist = true}) async {
    if (_contextoUsuarioId == uid) return;

    _contextoUsuarioId = uid;
    notifyListeners();

    await _fetchContextoData(uid);

    if (persist && userId.isNotEmpty) {
      try {
        await _selfRef.set({'contextoUsuarioId': uid}, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Erro ao persistir contextoUsuarioId: $e');
      }
    }
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

    notifyListeners();
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
}
