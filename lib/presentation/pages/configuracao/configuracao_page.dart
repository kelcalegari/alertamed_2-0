import 'package:smartmed/presentation/pages/configuracao/widgets/adicionar_usuario_widget.dart';
import 'package:smartmed/presentation/pages/configuracao/widgets/horario_padrao_widget.dart';
import 'package:smartmed/presentation/pages/configuracao/widgets/info_medica_widget.dart';
import 'package:smartmed/presentation/pages/configuracao/widgets/modo_silencioso_widget.dart';
import 'package:smartmed/presentation/pages/configuracao/widgets/usuario_compartilhado_card.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../providers/user_data_provider.dart';
import '../../routes/routes.dart';
import '../../shared/widgets/custom_seletor_field.dart';
import '../../shared/widgets/custom_text_field.dart';
import '../../themes/app_colors.dart';
import '../auth/cadastro/cadastro_texts.dart';
import '../auth/utils/auth_validator.dart';

class ConfiguracaoPage extends StatefulWidget {
  const ConfiguracaoPage({super.key});

  @override
  State<ConfiguracaoPage> createState() => _ConfiguracaoPageState();
}

class _ConfiguracaoPageState extends State<ConfiguracaoPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  int _currentIndex = 0;
  bool _showHint = true;
  late Animation<Offset> _offsetAnimation;
  late AnimationController _animationController;
  bool _isInit = true;
  final _nameCtrl = TextEditingController();
  final _birthCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordAtualCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  String? _selectedGender;

  List<Widget> get _pages => [
    _buildCard(showHint: _showHint, child: _buildEditarPerfil()),
    _buildCard(child: const HorariosPadraoEditor()),
    _buildCard(child: const InfoMedicaWidget()),
    _buildCard(child: const AdicionarUsuarioWidget()),
    _buildCard(child: const ListaUsuariosCompartilhados()),
  ];

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _offsetAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, -0.2),
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showHint = false;
        });
        _animationController.stop();
      }
    });
  }

  void _onVerticalDrag(DragEndDetails details) {
    if (details.primaryVelocity == null) return;

    if (details.primaryVelocity! < 0 && _currentIndex < _pages.length - 1) {
      setState(() => _currentIndex++);
    } else if (details.primaryVelocity! > 0 && _currentIndex > 0) {
      setState(() => _currentIndex--);
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _nameCtrl.dispose();
    _birthCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isInit) {
      UsuarioProvider usuarioProvider = Provider.of<UsuarioProvider>(
        context,
        listen: false,
      );
      Map<String, dynamic> dados = usuarioProvider.dadosUsuario;

      _nameCtrl.text = dados['nome'] ?? '';
      _birthCtrl.text =
          dados['dataNascimento'] != null
              ? DateFormat(
                'dd/MM/yyyy',
              ).format((dados['dataNascimento'] as Timestamp).toDate())
              : '';
      _emailCtrl.text = dados['email'] ?? '';
      _selectedGender = dados['sexo'];

      _isInit = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Text(
                    "Configuração",
                    style: TextStyle(
                      color: AppColors.textBranco,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: Icon(
                        Icons.arrow_back_ios_new,
                        color: AppColors.textBranco,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: GestureDetector(
                  onVerticalDragEnd: _onVerticalDrag,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: AppColors.cardBackgroundBranco,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: _pages[_currentIndex],
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

  Widget _buildCard({bool showHint = false, required Widget child}) {
    return Column(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeInOut,
          child:
              showHint
                  ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: SlideTransition(
                      position: _offsetAnimation,
                      child: Column(
                        children: const [
                          Icon(
                            Icons.keyboard_arrow_up,
                            size: 28,
                            color: AppColors.textVerde,
                          ),
                          SizedBox(height: 4),
                          Text(
                            "Deslize para cima",
                            style: TextStyle(
                              color: AppColors.textVerde,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  : const SizedBox.shrink(),
        ),
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: AppColors.cardBackgroundBranco,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SingleChildScrollView(child: child),
          ),
        ),
      ],
    );
  }

  Widget _buildEditarPerfil() {
    Future<bool> reautenticarUsuario(String email, String senhaAtual) async {
      try {
        User? user = FirebaseAuth.instance.currentUser;
        AuthCredential cred = EmailAuthProvider.credential(
          email: email,
          password: senhaAtual,
        );
        await user!.reauthenticateWithCredential(cred);
        return true;
      } catch (e) {
        return false;
      }
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                const Text(
                  "Perfil",
                  style: TextStyle(
                    color: AppColors.textVerde,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.start,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: Icon(Icons.logout, color: AppColors.textVerde),
                      onPressed: () async {
                        await FirebaseAuth.instance.signOut();
                        context.read<UsuarioProvider>().clearState();
                        if (!mounted) return;
                        Navigator.pushNamed(context, Routes.onboarding);
                      },
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 20),
            CustomTextField(
              ctrl: _nameCtrl,
              label: RegisterTexts.nameLabel,
              validador:
                  (value) =>
                      value == null || value.isEmpty
                          ? RegisterTexts.nameRequired
                          : null,
              textInputType: TextInputType.name,
            ),
            const SizedBox(height: 16),
            CustomTextField(
              ctrl: _birthCtrl,
              label: RegisterTexts.birthLabel,
              textInputType: TextInputType.datetime,
              validador:
                  (value) =>
                      value == null || value.isEmpty
                          ? RegisterTexts.birthRequired
                          : null,
            ),
            const SizedBox(height: 16),
            CustomSelectorField<String>(
              selectedValue: _selectedGender,
              items:
                  RegisterTexts.vectorGender
                      .map(
                        (g) => DropdownMenuItem(
                          value: g,
                          child: Text(g), // sem style aqui
                        ),
                      )
                      .toList(),
              onChanged: (value) => setState(() => _selectedGender = value),
              label: RegisterTexts.genderLabel,
              hint: RegisterTexts.genderHint,
              icon: Icons.person,
              validador:
                  (value) =>
                      value == null ? RegisterTexts.genderRequired : null,
            ),
            const SizedBox(height: 16),
            CustomTextField(
              ctrl: _emailCtrl,
              label: RegisterTexts.emailLabel,
              textInputType: TextInputType.emailAddress,
              validador: AuthValidator.validateEmail,
            ),
            const SizedBox(height: 16),
            CustomTextField(
              ctrl: _passwordAtualCtrl,
              label: "Senha Atual",
              textInputType: TextInputType.visiblePassword,
              isPassword: true,
              validador: AuthValidator.validatePassword,
            ),
            SizedBox(height: 16),
            CustomTextField(
              ctrl: _passwordCtrl,
              label: "Senha Nova",
              textInputType: TextInputType.visiblePassword,
              isPassword: true,
              validador: (value) {
                if (value == null || value.isEmpty) return null; // permite vazio (não altera senha)
                return AuthValidator.validatePassword(value);
              },
            ),
            const SizedBox(height: 16),
            CustomTextField(
              ctrl: _confirmPasswordCtrl,
              label: "Repita a senha nova",
              textInputType: TextInputType.visiblePassword,
              isPassword: true,
              validador: (value) {
                if (value == null || value.isEmpty) return null;
                return AuthValidator.validatePassword(value);
              },
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
                onPressed: () async {
                  if (!_formKey.currentState!.validate()) return;
                  User? user = FirebaseAuth.instance.currentUser;
                  if (user == null) return;

                  // Reautenticar
                  bool reautenticado = await reautenticarUsuario(
                    user.email!,
                    _passwordAtualCtrl.text,
                  );
                  if (!reautenticado) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Senha atual incorreta!')),
                    );
                    return;
                  }

                  // Se nova senha for preenchida, validar se confirmação bate
                  if (_passwordCtrl.text.isNotEmpty) {
                    if (_passwordCtrl.text != _confirmPasswordCtrl.text) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('A nova senha e a confirmação não coincidem!')),
                      );
                      return;
                    }
                  }

                  try {
                    // Atualizar dados no Firestore
                    DocumentReference<Map<String, dynamic>> userDoc = FirebaseFirestore.instance.collection('usuarios').doc(user.uid);
                    UsuarioProvider usuarioProvider = Provider.of<UsuarioProvider>(context, listen: false);
                    await userDoc.update({
                      'nome': _nameCtrl.text,
                      'sexo': _selectedGender,
                      'dataNascimento': DateFormat('dd/MM/yyyy').parse(_birthCtrl.text),
                      'email': _emailCtrl.text,
                    });

                    // Atualizar email se mudou
                    if (user.email?.toLowerCase().trim() != _emailCtrl.text.toLowerCase().trim()) {
                      await user.verifyBeforeUpdateEmail(_emailCtrl.text);
                    }

                    // Atualizar senha só se nova senha válida e preenchida
                    if (_passwordCtrl.text.isNotEmpty) {
                      await user.updatePassword(_passwordCtrl.text);
                    }
                    usuarioProvider.fetchData();

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Dados atualizados com sucesso!')),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Erro ao atualizar dados: $e')),
                    );
                  }
                },
                child: const Text(
                  "Salvar",
                  style: TextStyle(color: AppColors.textBranco),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

}
