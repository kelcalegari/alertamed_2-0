import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../shared/widgets/custom_seletor_field.dart';
import '../../../themes/app_colors.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../../auth/cadastro/cadastro_texts.dart';
import '../../auth/utils/auth_validator.dart';
import '../service/vinculo_service.dart';

class AdicionarUsuarioWidget extends StatefulWidget {
  const AdicionarUsuarioWidget({super.key});

  @override
  State<AdicionarUsuarioWidget> createState() => _AdicionarUsuarioWidgetState();
}

class _AdicionarUsuarioWidgetState extends State<AdicionarUsuarioWidget> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailCtrl = TextEditingController();
  final _svc = VinculoService();
  bool _loading = false;

  // opções do dropdown (valor interno, rótulo)
  static const List<List<String>> vectorNiveis = [
    ['visualizacao_basica','Visualização básica'],
    ['gerenciamento_restrito','Gerenciamento restrito'],
    ['acesso_completo','Acesso completo (bloqueia paciente)'],
  ];

  String _nivelSugerido = 'visualizacao_basica';

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  // ===== Helpers de nível/escopos/descrição =====
  String _tituloNivel(String nivel) {
    switch (nivel) {
      case 'visualizacao_basica': return 'Visualização básica';
      case 'gerenciamento_restrito': return 'Gerenciamento restrito';
      case 'acesso_completo': return 'Acesso completo (bloqueia paciente)';
      default: return nivel;
    }
  }

  String _descricaoNivel(String nivel) {
    switch (nivel) {
      case 'visualizacao_basica':
        return 'Leitura de informações essenciais do paciente. Não pode alterar tratamentos ou lembretes.';
      case 'gerenciamento_restrito':
        return 'Pode editar/criar tratamentos e ajustar lembretes. O paciente mantém liberdade para editar.';
      case 'acesso_completo':
        return 'Permissões totais. Pode bloquear alterações do próprio paciente quando necessário.';
      default:
        return '';
    }
  }

  List<String> _scopesFromNivel(String nivel) {
    switch (nivel) {
      case 'gerenciamento_restrito':
        return ['leitura','edicao_tratamentos','lembretes'];
      case 'acesso_completo':
        return ['leitura','edicao_tratamentos','lembretes','bloquear_paciente_editar'];
      default:
        return ['leitura'];
    }
  }

  String _labelPerm(String p) {
    switch (p) {
      case 'leitura': return 'Leitura';
      case 'edicao_tratamentos': return 'Editar tratamentos';
      case 'lembretes': return 'Gerir lembretes';
      case 'bloquear_paciente_editar': return 'Bloquear paciente';
      default: return p;
    }
  }

  IconData _iconPerm(String p) {
    switch (p) {
      case 'leitura': return Icons.visibility_outlined;
      case 'edicao_tratamentos': return Icons.edit_note_outlined;
      case 'lembretes': return Icons.alarm_outlined;
      case 'bloquear_paciente_editar': return Icons.lock_person_outlined;
      default: return Icons.check_circle_outline;
    }
  }
  // ==============================================

  Future<void> _enviarSolicitacao() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _emailCtrl.text.trim();

    setState(() => _loading = true);
    try {
      final alvo = await _svc.buscarUsuarioPorEmail(email);
      if (alvo == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Usuário não encontrado no AlertaMED.')),
        );
        return;
      }
      final pacienteUid = alvo.id;
      final me = FirebaseAuth.instance.currentUser!.uid;
      if (pacienteUid == me) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Você não pode convidar a si mesmo.')),
        );
        return;
      }

      // cuidador -> paciente (sugerindo nível)
      final scopes = _scopesFromNivel(_nivelSugerido);
      await _svc.solicitarComoCuidador(
        pacienteUid: pacienteUid,
        scopes: scopes,
        meta: {'nivelSugerido': _nivelSugerido},
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Solicitação enviada para $email. Aguarde a aprovação.')),
      );
      _emailCtrl.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao enviar solicitação: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<String> permsAtuais = _scopesFromNivel(_nivelSugerido);

    return Padding(
      padding: const EdgeInsets.only(left: 20,right: 20,top: 15,bottom: 10),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Adicionar Usuário para Compartilhar Tratamento",
              style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textVerde,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Convide um paciente para que você possa acompanhar e ajudar no tratamento.",
              style: TextStyle(fontSize: 14, color: AppColors.textVerde),
            ),
            const SizedBox(height: 16),

            const Text('Nível sugerido ao paciente', style: TextStyle(color: AppColors.textVerde)),
            const SizedBox(height: 8),

            CustomSelectorField<String>(
              selectedValue: _nivelSugerido,
              items: vectorNiveis.map((g) {
                return DropdownMenuItem<String>(
                  value: g[0],
                  child: Text(g[1]),
                );
              }).toList(),
              onChanged: (value) {
                setState(() => _nivelSugerido = value ?? 'visualizacao_basica');
              },
              pad: 0,
            ),

            // ===== Resumo do nível selecionado =====
            const SizedBox(height: 12),
            _NivelResumoCard(
              titulo: _tituloNivel(_nivelSugerido),
              descricao: _descricaoNivel(_nivelSugerido),
              perms: permsAtuais.map((p) => _PermInfo(
                label: _labelPerm(p),
                icon: _iconPerm(p),
              )).toList(),
            ),
            // =======================================

            const SizedBox(height: 24),
            CustomTextField(
              ctrl: _emailCtrl,
              label: RegisterTexts.emailLabel,
              textInputType: TextInputType.emailAddress,
              validador: AuthValidator.validateEmail,
              pad: 0,
            ),
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.botoesVerdes,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: _loading ? null : _enviarSolicitacao,
                child: Text(
                  _loading ? "Enviando..." : "Enviar solicitação",
                  style: const TextStyle(
                    color: AppColors.textBranco, fontWeight: FontWeight.bold, fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ====== UI do resumo do nível ======

class _PermInfo {
  final String label;
  final IconData icon;
  _PermInfo({required this.label, required this.icon});
}

class _NivelResumoCard extends StatelessWidget {
  final String titulo;
  final String descricao;
  final List<_PermInfo> perms;

  const _NivelResumoCard({
    required this.titulo,
    required this.descricao,
    required this.perms,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: Container(
        key: ValueKey(titulo),
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.cardBackgroundVerde,                 // fundo sólido do app
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(.10)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // título
            Row(
              children: [
                const Icon(Icons.verified_user_outlined, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  titulo,
                  style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // descrição
            Text(
              descricao,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),

            // permissões
            if (perms.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: perms.map((p) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(.10),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white.withOpacity(.12)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(p.icon, size: 16, color: Colors.white),
                        const SizedBox(width: 6),
                        Text(
                          p.label,
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
