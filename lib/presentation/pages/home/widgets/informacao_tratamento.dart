import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../providers/user_data_provider.dart';
import '../../../themes/app_colors.dart';
import '../service/alterar_lembrete.dart';

class InformacaoTratamento extends StatelessWidget {
  final VoidCallback onCancel;
  final Map<String, dynamic> tratamento;
  final String idUsuario;
  final ValueChanged<String> onEditar;

  const InformacaoTratamento({
    super.key,
    required this.onCancel,
    required this.tratamento,
    required this.idUsuario,
    required this.onEditar,
  });

  // ===================== Helpers =====================

  String _cap(String s) =>
      (s.isEmpty) ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

  T _get<T>(String key, {T? defaultValue}) {
    final v = tratamento[key];
    if (v is T) return v;
    // conversões comuns para String
    if (T == String && v != null) return v.toString() as T;
    return (defaultValue ?? (T == String ? '' as T : null as T)) as T;
  }

  Map<String, dynamic>? _getMap(String key) {
    final v = tratamento[key];
    if (v is Map) return v.cast<String, dynamic>();
    return null;
  }

  /// Converte o campo 'lembretes' para lista de mapas segura
  List<Map<String, dynamic>> _lembretes() {
    final raw = tratamento['lembretes'];
    if (raw is List) {
      return raw
          .where((e) => e is Map)
          .map<Map<String, dynamic>>((e) => (e as Map).cast<String, dynamic>())
          .toList(growable: false);
    }
    return const [];
  }

  /// Normaliza e valida HH:mm
  String? _normalizeHora(String raw) {
    final v = raw.trim();
    final re = RegExp(r'^(\d{1,2}):(\d{2})$');
    final m = re.firstMatch(v);
    if (m == null) return null;
    final h = int.tryParse(m.group(1)!);
    final min = int.tryParse(m.group(2)!);
    if (h == null || min == null) return null;
    if (h < 0 || h > 23 || min < 0 || min > 59) return null;
    return '${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
  }

  /// Caso "Horários Fixos": ["08:30", "20:30"]
  List<String> _formatHorariosFixos() {
    final ls = _lembretes()
        .map((e) => (e['valor'] ?? '').toString())
        .map(_normalizeHora)
        .whereType<String>()
        .toList();
    ls.sort((a, b) => a.compareTo(b));
    return ls;
  }

  /// Caso "Por Refeições": ordena por ordem padrão
  List<String> _formatRefeicoes() {
    final refeicoes = _lembretes()
        .map((e) => (e['momento'] ?? '').toString().trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();

    const ordem = [
      'cafe',
      'lanche_manha',
      'almoco',
      'lanche_tarde',
      'jantar',
      'ceia',
    ];

    refeicoes.sort((a, b) {
      int ia = ordem.indexOf(a);
      int ib = ordem.indexOf(b);
      ia = ia < 0 ? 1 << 20 : ia;
      ib = ib < 0 ? 1 << 20 : ib;
      if (ia != ib) return ia.compareTo(ib);
      return a.compareTo(b);
    });

    return refeicoes.map((k) => _cap(k.replaceAll('_', ' '))).toList();
  }

  /// Caso "Intervalos Fixos": extrai "a cada Xh"
  String? _formatIntervalo() {
    final lembretes = _lembretes();
    if (lembretes.isEmpty) return null;

    // aceita 'valor' como num ou string
    final first = lembretes.first['valor'];
    num? horas;
    if (first is num) {
      horas = first;
    } else if (first is String) {
      horas = num.tryParse(first.trim());
    }

    if (horas == null || horas <= 0) return null;
    return (horas % 1 == 0)
        ? 'a cada ${horas.toInt()}h'
        : 'a cada ${horas.toString()}h';
  }

  String _formatData(dynamic tsOrNull) {
    if (tsOrNull == null) return 'Não informado';

    DateTime? dt;
    if (tsOrNull is Timestamp) {
      dt = tsOrNull.toDate();
    } else if (tsOrNull is DateTime) {
      dt = tsOrNull;
    } else if (tsOrNull is String && tsOrNull.trim().isNotEmpty) {
      // tenta ler 'dd/MM/yyyy'
      try {
        dt = DateFormat('dd/MM/yyyy').parse(tsOrNull.trim());
      } catch (_) {}
      // tenta ISO
      dt ??= DateTime.tryParse(tsOrNull.trim());
    }

    if (dt == null) return 'Não informado';
    return DateFormat('dd/MM/yyyy').format(dt);
  }

  bool _temEstoqueValido(Map<String, dynamic>? estoque) {
    if (estoque == null) return false;
    final qtdAtual = estoque['qtdAtual'];
    final qtdMinima = estoque['qtdMinima'];
    final validade = estoque['dataValidade'];
    return qtdAtual != null && qtdMinima != null && validade != null;
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final usuarioProvider = Provider.of<UsuarioProvider>(context);

    // --------- Campos base, com segurança ---------
    final nomeMedicamento = _get<String>('nomeMedicamento');
    final concentracaoMedicamento = _get<String>('concentracaoMedicamento');
    final tipoMedicamento = _get<String>('tipoMedicamento');
    final dosagem = _get<String>('dosagem');

    final frequencia = _get<String>('frequencia');
    final tipoFrequencia = _get<String>('tipoFrequencia');

    final tipoTratamento = _get<String>('tipoTratamento');
    final status = _get<String>('status');

    final idMedicamento = _get<String>('idMedicamento');
    final idTratamento = _get<String>('idTratamento');

    final dataInicio = tratamento['dataInicio'];
    final dataTermino = tratamento['dataTermino'];

    // --------- Derivados ---------
    final isContinuo =
        tipoTratamento.trim().toLowerCase() == 'tratamento contínuo';
    final inativado = ['finalizado', 'inativado', 'cancelado']
        .contains(status.toLowerCase());

    final terminoStr = (isContinuo && !inativado)
        ? '—'
        : _formatData(dataTermino);

    final Map<String, dynamic>? estoque = usuarioProvider.estoqueMap[idMedicamento];
    final hasEstoque = _temEstoqueValido(estoque);

    final freqLower = tipoFrequencia.toLowerCase();
    final isRef = freqLower.contains('refei');
    final isFixos = freqLower.contains('horários fixos') ||
        freqLower.contains('horarios fixos');
    final isIntervalo = freqLower.contains('intervalos fixos');

    final horariosFixos = isFixos ? _formatHorariosFixos() : const <String>[];
    final refeicoes = isRef ? _formatRefeicoes() : const <String>[];
    final intervalo = isIntervalo ? _formatIntervalo() : null;

    final podeEditarOuConcluir =
        (usuarioProvider.isContextoSouEu &&
            !usuarioProvider.bloquearEdicaoPorPoliticaDoCuidador) ||
            (!usuarioProvider.isContextoSouEu &&
                !usuarioProvider.isPacienteComVisualizacao);

    return GestureDetector(
      onVerticalDragUpdate: (details) {
        if (details.primaryDelta != null && details.primaryDelta! > 10) {
          onCancel();
        }
      },
      child: Container(
        height: mediaQuery.size.height,
        decoration: BoxDecoration(
          color:
          hasEstoque ? AppColors.cardBackgroundVerde : AppColors.cardBackgroundBranco,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // "grabber"
                const SizedBox(height: 10),
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // ---------- Card superior (resumo) ----------
                _HeaderCard(
                  nome: nomeMedicamento,
                  concentracao: concentracaoMedicamento,
                  tipoMedicamento: tipoMedicamento,
                ),

                // ---------- Card do tratamento atual ----------
                _TratamentoCard(
                  dosagem: tipoMedicamento.isEmpty ? dosagem : '$dosagem $tipoMedicamento',
                  frequencia: frequencia.isEmpty ? 'Não informada' : frequencia,
                  tipoFrequencia:
                  tipoFrequencia.isEmpty ? 'Não informada' : tipoFrequencia,
                  tipoTratamento:
                  tipoTratamento.isEmpty ? 'Não informada' : tipoTratamento,
                  refeicoes: refeicoes,
                  horariosFixos: horariosFixos,
                  intervalo: intervalo,
                  inicio: _formatData(dataInicio),
                  termino: terminoStr,
                  status: status.isEmpty ? 'Não informado' : status,
                  observacoes:
                  _get<String>('observacoes', defaultValue: '').trim(),
                ),

                // ---------- Estoque ----------
                if (hasEstoque)
                  _EstoqueCard(
                    qtdAtual: estoque!['qtdAtual'].toString(),
                    qtdMinima: estoque['qtdMinima'].toString(),
                    validade: _formatData(estoque['dataValidade']),
                    unidade: tipoMedicamento,
                  ),

                // ---------- Ações ----------
                if (podeEditarOuConcluir)
                  _ActionsCard(
                    hasEstoque: hasEstoque,
                    onEditar: () => onEditar(idTratamento),
                    onConcluir: () async {
                      await LembreteService().finalizarTratamento(
                        context: context,
                        idUsuario: idUsuario,
                        idTratamento: idTratamento,
                      );
                      onCancel();
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===================== Subcomponentes =====================

class _HeaderCard extends StatelessWidget {
  final String nome;
  final String concentracao;
  final String tipoMedicamento;

  const _HeaderCard({
    required this.nome,
    required this.concentracao,
    required this.tipoMedicamento,
  });

  @override
  Widget build(BuildContext context) {
    final titulo = (concentracao.isNotEmpty) ? '$nome $concentracao' : nome;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.cardBackgroundBranco,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textVerde,
              ),
            ),
            const SizedBox(height: 12),
            _InfoRow(
              label: 'Tipo',
              value: tipoMedicamento,
              color: AppColors.textVerde,
            ),
            if (concentracao.isNotEmpty)
              _InfoRow(
                label: 'Concentração',
                value: concentracao,
                color: AppColors.textVerde,
              ),
          ],
        ),
      ),
    );
  }
}

class _TratamentoCard extends StatelessWidget {
  final String dosagem;
  final String frequencia;
  final String tipoFrequencia;
  final String tipoTratamento;
  final List<String> refeicoes;
  final List<String> horariosFixos;
  final String? intervalo;
  final String inicio;
  final String termino;
  final String status;
  final String observacoes;

  const _TratamentoCard({
    required this.dosagem,
    required this.frequencia,
    required this.tipoFrequencia,
    required this.tipoTratamento,
    required this.refeicoes,
    required this.horariosFixos,
    required this.intervalo,
    required this.inicio,
    required this.termino,
    required this.status,
    required this.observacoes,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: AppColors.cardBackgroundBranco),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.cardBackgroundVerde,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tratamento Atual',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textBranco,
                ),
              ),
              const SizedBox(height: 12),
              _InfoRow(
                label: 'Dosagem',
                value: dosagem.isEmpty ? 'Não informada' : dosagem,
                color: AppColors.textBranco,
              ),
              _InfoRow(
                label: 'Frequência',
                value: frequencia,
                color: AppColors.textBranco,
              ),
              _InfoRow(
                label: 'Tipo de frequência',
                value: tipoFrequencia,
                color: AppColors.textBranco,
              ),
              _InfoRow(
                label: 'Tipo de tratamento',
                value: tipoTratamento,
                color: AppColors.textBranco,
              ),
              if (refeicoes.isNotEmpty)
                _InfoRow(
                  label: 'Por refeição',
                  value: refeicoes.join('  •  '),
                  color: AppColors.textBranco,
                ),
              if (horariosFixos.isNotEmpty)
                _InfoRow(
                  label: 'Horários fixos',
                  value: horariosFixos.join(', '),
                  color: AppColors.textBranco,
                ),
              if (intervalo != null)
                _InfoRow(
                  label: 'Intervalo',
                  value: intervalo!,
                  color: AppColors.textBranco,
                ),
              _InfoRow(
                label: 'Início',
                value: inicio,
                color: AppColors.textBranco,
              ),
              _InfoRow(
                label: 'Término',
                value: termino,
                color: AppColors.textBranco,
              ),
              _InfoRow(
                label: 'Status',
                value: status,
                color: AppColors.textBranco,
              ),
              if (observacoes.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Observações',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textBranco,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  observacoes,
                  style: const TextStyle(color: AppColors.textBranco),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EstoqueCard extends StatelessWidget {
  final String qtdAtual;
  final String qtdMinima;
  final String validade;
  final String unidade;

  const _EstoqueCard({
    required this.qtdAtual,
    required this.qtdMinima,
    required this.validade,
    required this.unidade,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: AppColors.cardBackgroundVerde),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.cardBackgroundBranco,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Estoque',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textVerde,
                ),
              ),
              const SizedBox(height: 12),
              _InfoRow(
                label: 'Quantidade',
                value: '$qtdAtual ${unidade.isEmpty ? '' : unidade}',
                color: AppColors.textVerde,
              ),
              _InfoRow(
                label: 'Avisar em',
                value: '$qtdMinima ${unidade.isEmpty ? '' : unidade}',
                color: AppColors.textVerde,
              ),
              _InfoRow(
                label: 'Validade',
                value: validade,
                color: AppColors.textVerde,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionsCard extends StatelessWidget {
  final bool hasEstoque;
  final VoidCallback onEditar;
  final Future<void> Function() onConcluir;

  const _ActionsCard({
    required this.hasEstoque,
    required this.onEditar,
    required this.onConcluir,
  });

  @override
  Widget build(BuildContext context) {
    final bg = hasEstoque ? AppColors.cardBackgroundBranco : AppColors.cardBackgroundVerde;
    final inner = hasEstoque ? AppColors.cardBackgroundVerde : AppColors.cardBackgroundBranco;
    final btnBg = hasEstoque ? AppColors.botoesBrancos : AppColors.botoesVerdes;
    final btnText = hasEstoque ? AppColors.textVerde : AppColors.textBranco;

    return Container(
      decoration: BoxDecoration(color: bg),
      child: Container(
        decoration: BoxDecoration(
          color: inner,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const SizedBox(height: 20),/*
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: btnBg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  onPressed: onEditar,
                  child: Text(
                    'Editar',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: btnText,
                    ),
                  ),
                ),
              ),*/
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: btnBg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  onPressed: () async {
                    try {
                      await onConcluir();
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Erro ao concluir tratamento')),
                      );
                    }
                  },
                  child: Text(
                    'Concluir Tratamento',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: btnText,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _InfoRow({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final v = value.isEmpty ? '—' : value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: TextStyle(color: color),
              textAlign: TextAlign.right,
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }
}
