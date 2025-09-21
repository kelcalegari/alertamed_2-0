import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../themes/app_colors.dart';
import '../service/vinculo_service.dart';
import '../../../shared/widgets/custom_seletor_field.dart';
import 'package:provider/provider.dart';             // +++
import '../../../../providers/user_data_provider.dart';
/// Util: traduz identificador de nível para título amigável
String traduzNivel(String nivel) {
  switch (nivel) {
    case 'visualizacao_basica':
      return 'Visualização básica';
    case 'gerenciamento_restrito':
      return 'Gerenciamento restrito';
    case 'acesso_completo':
      return 'Acesso completo (bloqueia paciente)';
    default:
      return nivel;
  }
}

/// Util: descrição curta por nível (aparece no convite)
String descricaoNivel(String nivel) {
  switch (nivel) {
    case 'visualizacao_basica':
      return 'Apenas leitura de informações essenciais do paciente.';
    case 'gerenciamento_restrito':
      return 'Pode editar tratamentos, sem bloquear ações do paciente.';
    case 'acesso_completo':
      return 'Edição total + pode bloquear alterações do paciente.';
    default:
      return '';
  }
}

/// Label legível para cada permissão
String _labelPerm(String p) {
  switch (p) {
    case 'leitura':
      return 'Leitura';
    case 'edicao_tratamentos':
      return 'Editar tratamentos';
    case 'lembretes':
      return 'Gerir lembretes';
    case 'bloquear_paciente_editar':
      return 'Bloquear paciente';
    default:
      return p;
  }
}

/// Ícone sugestivo por permissão
IconData _iconPerm(String p) {
  switch (p) {
    case 'leitura':
      return Icons.visibility_outlined;
    case 'edicao_tratamentos':
      return Icons.edit_note_outlined;
    case 'lembretes':
      return Icons.alarm_outlined;
    case 'bloquear_paciente_editar':
      return Icons.lock_person_outlined;
    default:
      return Icons.check_circle_outline;
  }
}

/// Bloco visual com título, descrição e permissões do nível
class _NivelInfo extends StatelessWidget {
  final String nivel;
  final List<String> perms;
  const _NivelInfo({
    Key? key,                  // <--- adicionado
    required this.nivel,
    required this.perms,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey(nivel), // para animar troca
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            traduzNivel(nivel),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          if (descricaoNivel(nivel).isNotEmpty)
            Text(
              descricaoNivel(nivel),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          const SizedBox(height: 8),
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
                    Icon(_iconPerm(p), size: 16, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(
                      _labelPerm(p),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

/// Util: chip de status com semântica de cor
class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip(this.status);

  @override
  Widget build(BuildContext context) {
    late final Color bg;
    late final Color fg;
    switch (status) {
      case 'ativo':
        bg = Colors.green.withOpacity(.15);
        fg = Colors.green.shade700;
        break;
      case 'pendente':
        bg = Colors.amber.withOpacity(.15);
        fg = Colors.amber.shade800;
        break;
      case 'revogado':
      case 'inativo':
        bg = Colors.red.withOpacity(.15);
        fg = Colors.red.shade700;
        break;
      default:
        bg = Colors.blueGrey.withOpacity(.15);
        fg = Colors.blueGrey.shade700;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status[0].toUpperCase() + status.substring(1),
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

/// CARD MODERNO para cada vínculo
class UsuarioCompartilhadoCard extends StatelessWidget {
  final String nome;
  final String subtitulo; // "Sou cuidador" | "Sou paciente"
  final String status;
  final String nivel;                 // +++ NOVO
  final List<String> perms;           // +++ NOVO
  final VoidCallback onRemove;

  const UsuarioCompartilhadoCard({
    super.key,
    required this.nome,
    required this.subtitulo,
    required this.status,
    required this.nivel,              // +++ NOVO
    required this.perms,              // +++ NOVO
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isAtivo = status == 'ativo';




    return Container(
      margin: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        // “glass”

        border: Border.all(color: Colors.white.withOpacity(.10)),
        color: AppColors.cardBackgroundVerde,

      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16 + 6 + 10, 14, 12, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // avatar com leve vidro
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.white.withOpacity(.08),
                border: Border.all(
                  color: Colors.white.withOpacity(.12),
                ),
              ),
              child: const Icon(Icons.person_outline,
                  color: Colors.white, size: 26),
            ),
            const SizedBox(width: 12),

            // textos
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // primeira linha: nome + menu
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          nome,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Ações',
                        icon: const Icon(Icons.more_horiz,
                            color: Colors.white),
                        onSelected: (v) {
                          if (v == 'remover') onRemove();
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'remover',
                            child: Row(
                              children: [
                                Icon(Icons.link_off, size: 18),
                                SizedBox(width: 8),
                                Text('Remover vínculo'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // linha de badges: papel, status, nível
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _Pill(text: subtitulo, icon: Icons.badge_outlined),
                      _StatusChip(status),
                      _Pill(
                        text: traduzNivel(nivel),
                        icon: Icons.verified_user_outlined,
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // descrição curta
                  Text(
                    isAtivo
                        ? 'Acesso concedido e em uso'
                        : 'Acesso não ativo',
                    style: TextStyle(
                      color: Colors.white.withOpacity(.75),
                      fontSize: 12,
                    ),
                  ),

                  // linha de permissões — apenas ícones compactos (com tooltip)
                  if (perms.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      children: perms.map((p) {
                        return Tooltip(
                          message: _labelPerm(p),
                          child: Icon(
                            _iconPerm(p),
                            size: 18,
                            color: Colors.white.withOpacity(.95),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

}
class _Pill extends StatelessWidget {
  final String text;
  final IconData? icon;
  const _Pill({required this.text, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, size: 14, color: Colors.white.withOpacity(.95)),
          if (icon != null) const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}


class ListaUsuariosCompartilhados extends StatefulWidget {
  const ListaUsuariosCompartilhados({super.key});

  @override
  State<ListaUsuariosCompartilhados> createState() => _ListaUsuariosCompartilhadosState();
}

class _ListaUsuariosCompartilhadosState extends State<ListaUsuariosCompartilhados> {
  final _svc = VinculoService();

  /// Mantém o nível escolhido para cada solicitação (por solicId)
  final Map<String, String> _nivelSelecionado = {};

  Future<String> _nomePorUid(String uid) async {
    final snap = await FirebaseFirestore.instance
        .collection('usuarios_publicos')
        .doc(uid)
        .get();
    if (snap.exists) {
      return (snap.data()?['displayName'] as String?) ?? 'Usuário';
    }
    return 'Usuário';
  }

  List<String> _scopesFromNivel(String nivel) {
    switch (nivel) {
      case 'gerenciamento_restrito':
        return ['leitura', 'edicao_tratamentos'];
      case 'acesso_completo':
        return ['leitura', 'edicao_tratamentos', 'lembretes', 'bloquear_paciente_editar'];
      default:
        return ['leitura'];
    }
  }

  String _nivelFromScopes(List<String> scopes) {
    final s = scopes.toSet();
    if (s.contains('bloquear_paciente_editar')) return 'acesso_completo';
    if (s.contains('edicao_tratamentos')) return 'gerenciamento_restrito';
    return 'visualizacao_basica';
  }

  Future<void> _aprovarComNivel(String solicId, String nivel) async {
    final scopes = _scopesFromNivel(nivel);
    try {
      await _svc.aprovarSolicitacao(solicId, scopesAprovados: scopes, nivel: nivel);
      if (mounted) {
        await context.read<UsuarioProvider>().refreshVinculos();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Convite aceito!')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao aceitar: $e')));
    }
  }

  void _revogar(String otherUid) async {
    try {
      await _svc.revogarVinculo(otherUid);
      if (mounted) {
        await context.read<UsuarioProvider>().refreshVinculos();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Convite aceito! Vínculos atualizados.')),
        );
      }

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao revogar: $e')),
      );
    }
  }

  Future<void> _negar(String solicId) async {
    try {
      await _svc.atualizarStatusSolicitacao(solicId, 'negado');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Convite negado.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao negar: $e')),
      );
    }
  }

  Widget _secaoVinculos(
      String titulo,
      List<QueryDocumentSnapshot<Map<String, dynamic>>> lista,
      ) {
    if (lista.isEmpty) return const SizedBox.shrink();
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: Future.wait(lista.map((d) async {
        final otherUid = d.id;
        final nome = await _nomePorUid(otherUid);
        final List<String> scopes = List<String>.from(d['scopes'] ?? const <String>[]);
        final String nivelDoc   = (d['nivel'] as String?) ?? '';
        final String nivelEfetivo = nivelDoc.isNotEmpty ? nivelDoc : _nivelFromScopes(scopes);
        final List<String> permsEfetivas = scopes.isNotEmpty ? scopes : _scopesFromNivel(nivelEfetivo);

        return {
          'otherUid': otherUid,
          'nome': nome,
          'roleDoOutro': d['roleDoOutro'] as String? ?? '',
          'status': d['status'] as String? ?? 'ativo',
          'nivel': nivelEfetivo,             // +++ NOVO
          'perms': permsEfetivas,            // +++ NOVO
        };
      })),
      builder: (context, fSnap) {
        if (!fSnap.hasData) return const SizedBox.shrink();
        final itens = fSnap.data!;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textVerde,
                ),
              ),
              const SizedBox(height: 8),
              ...itens.map((it) => UsuarioCompartilhadoCard(
                nome: it['nome'],
                subtitulo: it['roleDoOutro'] == 'paciente' ? 'Sou cuidador' : 'Sou paciente',
                status: it['status'],
                nivel: it['nivel'],            // +++ NOVO
                perms: List<String>.from(it['perms'] ?? const <String>[]), // +++ NOVO
                onRemove: () => _revogar(it['otherUid']),
              )),
            ],
          ),
        );
      },
    );
  }

  Widget _conviteCard({
    required String solicId,
    required String nomeCuidador,
    required String nivelSugerido,
    required List<String> scopesSug,
  }) {
    final nivelAtual = _nivelSelecionado[solicId] ?? nivelSugerido;
    final permsAtuais = _scopesFromNivel(nivelAtual);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: AppColors.cardBackgroundVerde.withOpacity(.95),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.12),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ícone
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(.12)),
            ),
            child: const Icon(Icons.person_add_alt_1, color: Colors.white),
          ),
          const SizedBox(width: 12),

          // conteúdo
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // header
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Convite de $nomeCuidador',
                        style: const TextStyle(
                          color: AppColors.textBranco,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const _StatusChip('pendente'),
                  ],
                ),
                const SizedBox(height: 6),

                // linha apenas informativa do sugerido
                if (scopesSug.isNotEmpty || nivelSugerido.isNotEmpty)
                  Row(
                    children: [
                      const Icon(Icons.tips_and_updates, size: 16, color: Colors.white70),
                      const SizedBox(width: 6),
                      Text(
                        'Nível sugerido: ${traduzNivel(nivelSugerido)}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),

                const SizedBox(height: 12),

                // seletor de nível (teu component)
                CustomSelectorField<String>(
                  selectedValue: nivelAtual,
                  items: const [
                    DropdownMenuItem<String>(
                      value: 'visualizacao_basica',
                      child: Text('Visualização básica'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'gerenciamento_restrito',
                      child: Text('Gerenciamento restrito'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'acesso_completo',
                      child: Text('Acesso completo (bloqueia paciente)'),
                    ),
                  ],
                  onChanged: (v) {
                    setState(() {
                      _nivelSelecionado[solicId] = v ?? nivelAtual;
                    });
                  },
                  label: 'Nível a conceder',
                  hint: 'Selecione o nível',
                  pad: 0,
                  backgroundColor: Colors.white.withOpacity(.10),
                  textColor: Colors.white,
                  dropdownColor: AppColors.cardBackgroundVerde,
                ),

                const SizedBox(height: 10),

                // bloco explicativo que muda conforme seleção
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: _NivelInfo(
                    key: ValueKey('info_$nivelAtual'),
                    nivel: nivelAtual,
                    perms: permsAtuais,
                  ),
                ),

                const SizedBox(height: 12),

                // ações
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(color: Colors.white.withOpacity(.5)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => _negar(solicId),
                        icon: const Icon(Icons.close),
                        label: const Text('Negar'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: AppColors.textVerde,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => _aprovarComNivel(
                          solicId,
                          _nivelSelecionado[solicId] ?? nivelSugerido,
                        ),
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Aceitar'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  Widget _secaoConvitesPendentes() {
    return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      stream: _svc.streamSolicitacoesPendentes(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final pendentes = snap.data ?? [];
        if (pendentes.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Convites pendentes (para você aceitar)',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textVerde),
              ),
              const SizedBox(height: 8),
              ...pendentes.map((doc) {
                final data = doc.data();
                final solicId = doc.id;
                final cuidadorId = data['cuidadorId'] as String? ?? '';
                final scopesSug = List<String>.from(data['scopesSugeridos'] ?? const <String>[]);
                final nivelSugerido = _nivelFromScopes(scopesSug);

                return FutureBuilder<String>(
                  future: _nomePorUid(cuidadorId),
                  builder: (context, nameSnap) {
                    final nomeCuidador = nameSnap.data ?? 'Cuidador';
                    return _conviteCard(
                      solicId: solicId,
                      nomeCuidador: nomeCuidador,
                      nivelSugerido: nivelSugerido,
                      scopesSug: scopesSug,
                    );
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      stream: _svc.streamVinculos(),
      builder: (context, snap) {
        final carregandoVinculos = snap.connectionState == ConnectionState.waiting;
        final docs = snap.data ?? [];

        final comoPaciente = docs.where((d) => d['meuPapel'] == 'paciente').toList();
        final comoCuidador = docs.where((d) => d['meuPapel'] == 'cuidador').toList();

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _secaoConvitesPendentes(),

              if (carregandoVinculos)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (docs.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.cardBackgroundVerde.withOpacity(.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.cardBackgroundVerde.withOpacity(.15)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.link_off, color: AppColors.textVerde, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            "Nenhum vínculo no momento.\nConvide um cuidador ou associe um paciente para começar.",
                            style: TextStyle(color: AppColors.textVerde.withOpacity(.9)),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                  _secaoVinculos('Meus pacientes', comoCuidador),
                  _secaoVinculos('Meus cuidadores', comoPaciente),
                ],
            ],
          ),
        );
      },
    );
  }
}
