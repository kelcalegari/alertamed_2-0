// card_gerar_relatorio.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../providers/user_data_provider.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../../../themes/app_colors.dart';
import '../service/relatorio_service.dart';

class CardGerarRelatorio extends StatefulWidget {
  final VoidCallback onCancel;

  const CardGerarRelatorio({
    super.key,
    required this.onCancel,
  });

  @override
  State<CardGerarRelatorio> createState() => _CardGerarRelatorioState();
}

class _CardGerarRelatorioState extends State<CardGerarRelatorio> {
  final TextEditingController _inicioCtrl = TextEditingController();
  final TextEditingController _fimCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  DateTime? _inicio;
  DateTime? _fim;
  bool _anonimizar = false;
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isSharing = false;

  // Seleção de formatos
  bool _optPdf = true;
  bool _optCsvTimeline = false;
  bool _optCsvResumo = false;

  ReportResult? _lastResult;

  final _df = DateFormat('dd/MM/yyyy HH:mm');

  // ---- Config do gesto de fechar ----
  static const double _closeDragDistance = 80;  // um pouco menor no handle
  static const double _closeDragVelocity = 900; // px/s
  double _dragAccumulatedDy = 0;

  void _maybeCloseOnDragEnd(DragEndDetails details) {
    final v = details.primaryVelocity ?? 0;
    if (_dragAccumulatedDy >= _closeDragDistance || v > _closeDragVelocity) {
      widget.onCancel();
    }
    _dragAccumulatedDy = 0;
  }

  Future<void> _pickDateTime({required bool isInicio}) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: isInicio ? (_inicio ?? now) : (_fim ?? now),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: isInicio ? 'Selecione a DATA inicial' : 'Selecione a DATA final',
      confirmText: 'CONTINUAR',
      cancelText: 'CANCELAR',
    );
    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(isInicio ? (_inicio ?? now) : (_fim ?? now)),
      helpText: isInicio ? 'Selecione o HORÁRIO inicial' : 'Selecione o HORÁRIO final',
      confirmText: 'OK',
      cancelText: 'CANCELAR',
    );
    if (time == null) return;

    final selected = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isInicio) {
        _inicio = selected;
        _inicioCtrl.text = _df.format(selected);
      } else {
        _fim = selected;
        _fimCtrl.text = _df.format(selected);
      }
    });
  }

  Future<void> _gerar() async {
    if (_inicio == null || _fim == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe início e fim do período.')),
      );
      return;
    }
    if (_fim!.isBefore(_inicio!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A data/hora final deve ser após a inicial.')),
      );
      return;
    }
    if (!_optPdf && !_optCsvTimeline && !_optCsvResumo) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione ao menos um formato (PDF/CSV).')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final provider = Provider.of<UsuarioProvider>(context, listen: false);
      final String idUsuario = provider.userId ?? '';
      final String nomeUsuario = provider.dadosUsuario["nome"] ?? 'Usuário';

      final service = RelatorioService();
      final result = await service.gerarTimelineEResumo(
        idUsuario: idUsuario,
        nomeUsuario: nomeUsuario,
        inicio: _inicio!,
        fim: _fim!,
        anonimizar: _anonimizar,
        makePdf: _optPdf,
        makeCsvTimeline: _optCsvTimeline,
        makeCsvResumo: _optCsvResumo,
      );

      setState(() => _lastResult = result);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Arquivos gerados. Agora salve e/ou compartilhe.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao gerar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _salvarNoDispositivo() async {
    if (_lastResult == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gere os arquivos antes de salvar.')),
      );
      return;
    }
    final service = RelatorioService();
    final paths = _lastResult!.selectedPaths(
      pdf: _optPdf,
      csvTimeline: _optCsvTimeline,
      csvResumo: _optCsvResumo,
    );
    if (paths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum formato selecionado para salvar.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await service.salvarNoDispositivo(paths: paths); // usa file_saver (MimeType enum)
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Arquivos salvos no dispositivo.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha ao salvar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _compartilhar() async {
    if (_lastResult == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gere os arquivos antes de compartilhar.')),
      );
      return;
    }
    final service = RelatorioService();
    final paths = _lastResult!.selectedPaths(
      pdf: _optPdf,
      csvTimeline: _optCsvTimeline,
      csvResumo: _optCsvResumo,
    );
    if (paths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum formato selecionado para compartilhar.')),
      );
      return;
    }

    setState(() => _isSharing = true);
    try {
      await service.compartilharArquivos(
        paths: paths,
        texto: 'Relatório AlertaMED - ${_df.format(_inicio!)} a ${_df.format(_fim!)}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha ao compartilhar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);

    return Container(
      height: mediaQuery.size.height,
      decoration: const BoxDecoration(
        color: AppColors.cardBackgroundBranco,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: mediaQuery.viewInsets.bottom + 16,
        left: 16,
        right: 16,
        top: 10,
      ),
      child: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              // Quando estiver no topo e houver overscroll negativo, fecha
              if (n is OverscrollNotification && n.overscroll < 0) {
                // Você pode exigir uma “força” mínima se quiser
                widget.onCancel();
                return true;
              }
              return false;
            },

            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // --- pegador/handle para indicar gesto ---
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragStart: (_) => _dragAccumulatedDy = 0,
                    onVerticalDragUpdate: (details) {
                      if (details.primaryDelta != null && details.primaryDelta! > 0) {
                        _dragAccumulatedDy += details.primaryDelta!;
                      }
                    },
                    onVerticalDragEnd: _maybeCloseOnDragEnd,
                    child: Center(
                      child: Container(
                        width: 42,
                        height: 5,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: AppColors.textVerde.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(100),
                        ),
                      ),
                    ),
                  ),
                
                  const Text(
                    'Resumo e Histórico do Tratamento',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textVerde,
                    ),
                  ),
                  const SizedBox(height: 16),
                
                  CustomTextField(
                    ctrl: _inicioCtrl,
                    label: 'Início',
                    readOnly: true,
                    onTap: () => _pickDateTime(isInicio: true),
                    validador: (v) =>
                    (v == null || v.isEmpty) ? 'Informe a data/hora inicial' : null,
                    textInputType: TextInputType.datetime,
                  ),
                  const SizedBox(height: 12),
                  CustomTextField(
                    ctrl: _fimCtrl,
                    label: 'Fim',
                    readOnly: true,
                    onTap: () => _pickDateTime(isInicio: false),
                    validador: (v) =>
                    (v == null || v.isEmpty) ? 'Informe a data/hora final' : null,
                    textInputType: TextInputType.datetime,
                  ),
                  const SizedBox(height: 8),
                
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Anonimizar dados (oculta nome/e-mail)'),
                    value: _anonimizar,
                    onChanged: (v) => setState(() => _anonimizar = v),
                    activeColor: AppColors.botoesVerdes,
                  ),
                
                  const SizedBox(height: 16),
                  const Text(
                    'O que você quer gerar?',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _optPdf,
                    onChanged: (v) => setState(() => _optPdf = v ?? false),
                    title: const Text('PDF (Relatório completo)'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _optCsvTimeline,
                    onChanged: (v) => setState(() => _optCsvTimeline = v ?? false),
                    title: const Text('CSV – Timeline de eventos'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _optCsvResumo,
                    onChanged: (v) => setState(() => _optCsvResumo = v ?? false),
                    title: const Text('CSV – Resumo de tratamentos ativos'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                
                  const SizedBox(height: 12),
                
                  // 1º passo: GERAR
                  ElevatedButton.icon(
                    icon: _isLoading
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.textBranco,
                      ),
                    )
                        : const Icon(Icons.build_circle, color: AppColors.textBranco),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.botoesVerdes,
                      foregroundColor: AppColors.botoesBrancos,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _isLoading ? null : _gerar,
                    label: const Text(
                      'Gerar',
                      style: TextStyle(color: AppColors.textBranco, fontWeight: FontWeight.bold),
                    ),
                  ),
                
                  const SizedBox(height: 8),
                
                  // 2º passo: SALVAR / COMPARTILHAR
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: _isSaving
                              ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.textBranco,
                            ),
                          )
                              : const Icon(Icons.download, color: AppColors.textBranco),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.textVerde,
                            foregroundColor: AppColors.botoesBrancos,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: (_lastResult == null || _isSaving)
                              ? null
                              : () async {
                            final service = RelatorioService();
                            final pathsSelecionados = _lastResult!.selectedPaths(
                              pdf: _optPdf,
                              csvTimeline: _optCsvTimeline,
                              csvResumo: _optCsvResumo,
                            );
                            await service.salvarComPicker(paths: pathsSelecionados);
                          },
                          label: const Text(
                            'Salvar',
                            style: TextStyle(
                              color: AppColors.textBranco,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: _isSharing
                              ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.textBranco,
                            ),
                          )
                              : const Icon(Icons.share, color: AppColors.textBranco),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.botoesVerdes,
                            foregroundColor: AppColors.botoesBrancos,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: (_lastResult == null || _isSharing) ? null : _compartilhar,
                          label: const Text(
                            'Compartilhar',
                            style: TextStyle(
                              color: AppColors.textBranco,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                
                  const SizedBox(height: 8),
                  // (fecha arrastando; sem botão Fechar)
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
