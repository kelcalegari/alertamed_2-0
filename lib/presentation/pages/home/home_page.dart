import 'package:smartmed/presentation/pages/home/widgets/assistente_card.dart';
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
  DateTime? _lastBackPressTime;
  Map<String, dynamic>? tratamentoSelecionado;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // bloqueia pop automático
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (mostrandoCardSintoma ||
            mostrandoCardTratamento ||
            mostrandoCardInformacaoTratamento || mostrandoCardAssistenteIa) {
          setState(() {
            mostrandoCardSintoma = false;
            mostrandoCardTratamento = false;
            mostrandoCardInformacaoTratamento = false;
            mostrandoCardAssistenteIa = false;
          });
          return;
        }

        final now = DateTime.now();
        if (_lastBackPressTime == null ||
            now.difference(_lastBackPressTime!) > Duration(seconds: 5)) {
          _lastBackPressTime = now;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Toque novamente para sair')),
          );
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
                onSemanaChanged: (novoDia) {
                  setState(() {
                    diaSelecionado = novoDia;
                  });
                },
              ),
              Expanded(
                child:
                mostrandoCardAssistenteIa
                    ? CardAssistenteIA(
                  onClose: () {
                    setState(() => mostrandoCardSintoma = false);
                  }
                )
                    :mostrandoCardSintoma
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
                          onCancel:
                              () => setState(
                                () => mostrandoCardTratamento = false,
                              ),
                          onConcluir: () {
                            _handleRefresh();
                            setState(() => mostrandoCardTratamento = false);
                          },
                        )
                        : mostrandoCardInformacaoTratamento
                        ? InformacaoTratamento(
                      tratamento: tratamentoSelecionado!,
                      onCancel: () => setState(() => mostrandoCardInformacaoTratamento = false),
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
                                      setState(
                                        () => mostrandoCardSintoma = true,
                                      );
                                    },
                                    onRegistrarTratamento: () {
                                      setState(
                                        () => mostrandoCardTratamento = true,
                                      );
                                    },
                                    onCardAssistenteIa: () {
                                      setState(
                                            () => mostrandoCardAssistenteIa = true,
                                      );
                                    },
                                    dia: diaSelecionado ?? DateTime.now(),
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
                                          mostrandoCardInformacaoTratamento =
                                              true;
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
