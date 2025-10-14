import 'package:smartmed/presentation/pages/home/widgets/assistente_card.dart';
import 'package:smartmed/presentation/pages/home/widgets/gerar_relatorio_card.dart';
import 'package:smartmed/presentation/pages/home/widgets/gerenciador_tratamento.dart';
import 'package:smartmed/presentation/pages/home/widgets/historico_card.dart';
import 'package:smartmed/presentation/pages/home/widgets/informacao_tratamento.dart';
import 'package:smartmed/presentation/pages/home/widgets/proximos_tratamentos_card.dart';
import 'package:smartmed/presentation/pages/home/widgets/registrar_sintomas_card.dart';
import 'package:smartmed/presentation/pages/home/widgets/semana_selector.dart';
import 'package:smartmed/presentation/pages/home/widgets/tratamentos_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart'; // PopResult está aqui
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../providers/user_data_provider.dart';
import '../../themes/app_colors.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  DateTime? diaSelecionado;
  bool mostrandoCardSintoma = false;
  bool mostrandoCardTratamento = false;
  bool mostrandoCardInformacaoTratamento = false;
  bool mostrandoCardAssistenteIa = false;
  bool mostrandoCardRelatorio = false;
  DateTime? _lastBackPressTime;
  Map<String, dynamic>? tratamentoSelecionado;
  String? idTratamentoEditar;

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool get _estaEmHoje {
    final hoje = DateTime.now();
    final ref = diaSelecionado ?? hoje;
    return _isSameDay(ref, hoje);
  }


  @override
  Widget build(BuildContext context) {

    return PopScope(
      canPop: false, // bloqueia pop automático
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        // 1) Fecha qualquer card aberto
        if (mostrandoCardSintoma ||
            mostrandoCardTratamento ||
            mostrandoCardInformacaoTratamento ||
            mostrandoCardAssistenteIa ||
            mostrandoCardRelatorio) {
          setState(() {
            mostrandoCardSintoma = false;
            mostrandoCardTratamento = false;
            mostrandoCardInformacaoTratamento = false;
            mostrandoCardAssistenteIa = false;
            mostrandoCardRelatorio = false;
            idTratamentoEditar = null;
          });
          return;
        }

        // 2) Se não está em "hoje", primeiro voltar apenas redefine para hoje
        if (!_estaEmHoje) {
          setState(() {
            final hoje = DateTime.now();
            diaSelecionado = DateTime(hoje.year, hoje.month, hoje.day);
          });
          return;
        }

        // 3) Já está em "hoje": aplica o fluxo de dois cliques para sair
        final now = DateTime.now();
        if (_lastBackPressTime == null ||
            now.difference(_lastBackPressTime!) > const Duration(seconds: 5)) {
          _lastBackPressTime = now;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Toque novamente para sair')),
            );

          }
          return;
        }

        await SystemNavigator.pop();
      },

      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              SemanaSelector(
                selectedDate: diaSelecionado ?? DateTime.now(),
                onSemanaChanged: (novoDia) {
                  setState(() {
                    // normaliza para yyyy-MM-dd
                    diaSelecionado = DateTime(novoDia.year, novoDia.month, novoDia.day);
                  });
                },
              ),
              Expanded(
                child: mostrandoCardAssistenteIa
                    ? CardAssistenteIA(
                  onClose: () {
                    setState(() => mostrandoCardAssistenteIa = false); // FIX
                  },
                )
                    : mostrandoCardSintoma
                    ? CardAdicionarSintomas(
                  onCancel: () {
                    setState(() => mostrandoCardSintoma = false);
                  },
                  onSave: (s, i, o) {
                    _handleRefresh();
                    setState(() => mostrandoCardSintoma = false);
                  },
                )
                    : mostrandoCardTratamento
                    ? GerenciadorTratamento(
                  onCancel: () => setState(() {
                    mostrandoCardTratamento = false;
                    idTratamentoEditar = null;
                  }),
                  onConcluir: () {
                    _handleRefresh();
                    setState(() => mostrandoCardTratamento = false);
                  },
                  idTratamento: idTratamentoEditar,
                )
                    : mostrandoCardInformacaoTratamento
                    ? InformacaoTratamento(
                  tratamento: tratamentoSelecionado!,
                  onCancel: () => setState(
                        () => mostrandoCardInformacaoTratamento = false,
                  ),
                  idUsuario: context.read<UsuarioProvider>().userId,
                  onEditar: (String value) {
                    setState(() {
                      idTratamentoEditar = value;
                      mostrandoCardInformacaoTratamento = false;
                      mostrandoCardTratamento = true;
                    });
                  },
                )
                    : mostrandoCardRelatorio
                    ? CardGerarRelatorio(
                  onCancel: () {
                    setState(() => mostrandoCardRelatorio = false);
                  },
                )
                    : Container(
                  decoration: const BoxDecoration(
                    color: AppColors.cardBackgroundBranco,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: RefreshIndicator(
                    onRefresh: _handleRefresh,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Column(
                        children: [
                          ProximosTratamentosCard(
                            onRegistrarSintoma: () {
                              setState(() => mostrandoCardSintoma = true);
                            },
                            onRegistrarTratamento: () {
                              setState(
                                      () => mostrandoCardTratamento = true);
                            },
                            onCardAssistenteIa: () {
                              setState(
                                      () => mostrandoCardAssistenteIa = true);
                            },
                            dia: diaSelecionado ?? DateTime.now(),
                            onCardRelatorio: () {
                              setState(
                                      () => mostrandoCardRelatorio = true);
                            },
                          ),
                          Transform.translate(
                            offset: const Offset(0, -80),
                            child: HistoricoCard(
                              dia: diaSelecionado ?? DateTime.now(),
                            ),
                          ),
                          Transform.translate(
                            offset: const Offset(0, -140),
                            child: TratamentosCard(
                              dataReferencia:
                              diaSelecionado ?? DateTime.now(),
                              onTapTratamento: (
                                  medicamento,
                                  tratamento,
                                  ) {
                                setState(() {
                                  tratamentoSelecionado = tratamento;
                                  mostrandoCardInformacaoTratamento = true;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
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

  Future<void> _handleRefresh() async {
    final usuarioProvider = context.read<UsuarioProvider>();
    usuarioProvider.isLoading = true;
    await usuarioProvider.fetchData();
  }
}
