import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../providers/user_data_provider.dart';
import '../../../shared/widgets/custom_seletor_field.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../../../themes/app_colors.dart';

import '../service/info_medica.dart';      // <- ajuste o path conforme seu projeto

class InfoMedicaWidget extends StatefulWidget {
  const InfoMedicaWidget({super.key});

  @override
  State<InfoMedicaWidget> createState() => _InfoMedicaWidgetState();
}

class _InfoMedicaWidgetState extends State<InfoMedicaWidget> {
  final TextEditingController alergiasCtrl = TextEditingController();
  final TextEditingController deficienciasCtrl = TextEditingController();
  final TextEditingController comorbidadesCtrl = TextEditingController();

  String? gravida; // "Sim" | "Não" | "Não se aplica"
  bool _carregadoDoProvider = false;
  bool _enviando = false;

  @override
  void dispose() {
    alergiasCtrl.dispose();
    deficienciasCtrl.dispose();
    comorbidadesCtrl.dispose();
    super.dispose();
  }

  void _preencherComProvider(Map<String, dynamic> info) {
    gravida = (info['gravidez'] as String?) ?? gravida;
    alergiasCtrl.text = (info['alergias'] as String?) ?? '';
    deficienciasCtrl.text = (info['deficiencias'] as String?) ?? '';
    comorbidadesCtrl.text = (info['comorbidades'] as String?) ?? '';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Preenche uma única vez quando houver dados no provider
    if (!_carregadoDoProvider) {
      final info = context.read<UsuarioProvider>().infoMedica;
      if (info.isNotEmpty) {
        _preencherComProvider(info);
      }
      _carregadoDoProvider = true;
    }
  }

  Future<void> _atualizarOuCriar() async {
    final provider = context.read<UsuarioProvider>();
    final uid = provider.userId;
    if (uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Usuário não autenticado.')),
      );
      return;
    }

    final payload = <String, dynamic>{
      'gravidez': gravida,
      'alergias': alergiasCtrl.text.trim(),
      'deficiencias': deficienciasCtrl.text.trim(),
      'comorbidades': comorbidadesCtrl.text.trim(),
    };

    setState(() => _enviando = true);
    final service = InfoMedicaService();

    try {
      final jaExiste = provider.infoMedica.isNotEmpty;
      if (jaExiste) {
        await service.updateCampos(uid, payload);  // atualiza somente campos
      } else {
        await service.upsertPerfil(uid, payload);  // cria/merge
      }

      await provider.refreshInfoMedica();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(jaExiste ? 'Informações médicas atualizadas.' : 'Informações médicas salvas.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar: $e')),
      );
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<UsuarioProvider>();
    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: AbsorbPointer(
        absorbing: _enviando,
        child: Opacity(
          opacity: _enviando ? 0.6 : 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Informações Médicas",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textVerde,
                ),
              ),
              const SizedBox(height: 16),

              // Gravidez
              CustomSelectorField<String>(
                selectedValue: gravida,
                label: "Está grávida?",
                hint: "Selecione",
                items: const [
                  DropdownMenuItem(value: "Sim", child: Text("Sim")),
                  DropdownMenuItem(value: "Não", child: Text("Não")),
                  DropdownMenuItem(value: "Não se aplica", child: Text("Não se aplica")),
                ],
                onChanged: (value) => setState(() => gravida = value),
              ),
              const SizedBox(height: 16),

              // Alergias
              CustomTextField(
                ctrl: alergiasCtrl,
                label: "Alergias",
                hint: "Ex: Dipirona, Amendoim...",
                textInputType: TextInputType.text,
                maxLines: 2,
              ),
              const SizedBox(height: 16),

              // Deficiências
              CustomTextField(
                ctrl: deficienciasCtrl,
                label: "Deficiências",
                hint: "Ex: auditiva, motora...",
                textInputType: TextInputType.text,
                maxLines: 2,
              ),
              const SizedBox(height: 16),

              // Comorbidades
              CustomTextField(
                ctrl: comorbidadesCtrl,
                label: "Comorbidades",
                hint: "Ex: diabetes, hipertensão...",
                textInputType: TextInputType.text,
                maxLines: 2,
              ),
              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.botoesVerdes,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  onPressed: _enviando ? null : _atualizarOuCriar,
                  child: Text(
                    _enviando
                        ? "Enviando..."
                        : (provider.infoMedica.isNotEmpty ? "Atualizar" : "Salvar"),
                    style: const TextStyle(color: AppColors.textBranco),
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
