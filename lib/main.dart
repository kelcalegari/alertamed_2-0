import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:smartmed/presentation/pages/auth/verificarEmailPage/verificar_email_page.dart';
import 'package:smartmed/presentation/pages/home/home_page.dart';
import 'package:smartmed/presentation/pages/onboarding/onboarding_page.dart';
import 'package:smartmed/presentation/routes/routes.dart';
import 'package:smartmed/providers/user_data_provider.dart';
import 'package:workmanager/workmanager.dart';
import 'core/background/bg_sync.dart';
import 'core/background/carewatch_bg_sync.dart';
import 'core/background/dispatcher.dart';
import 'core/services/notification_service.dart';
import 'firebase_options.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Timezone
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('America/Sao_Paulo'));

  // Env
  await dotenv.load(fileName: ".env");

  // Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Idioma dos e-mails do Firebase (não é crítico se falhar)
  try {
    await FirebaseAuth.instance.setLanguageCode('pt_BR');
  } catch (_) {}

  // Notificações locais
  await NotificationService().init();

  // Workmanager (inicializa o dispatcher global)
  await Workmanager().initialize(bgCallbackDispatcher);

  runApp(const AlertaMedApp());
}

class AlertaMedApp extends StatelessWidget {
  const AlertaMedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'AlertaMED',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('pt', 'BR')],
      locale: const Locale('pt', 'BR'),
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const SplashGate(),
      onGenerateRoute: Routes.generateRoute,
    );
  }
}

/// Decide a tela de acordo com o estado de autenticação em tempo real.
/// - Sem usuário -> Onboarding
/// - Com usuário:
///     - Se email verificado -> Home
///     - Se não verificado -> VerifyEmail
class SplashGate extends StatefulWidget {
  const SplashGate({super.key});
  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  bool _gaveAuthHydrationSomeTime = false;

  @override
  void initState() {
    super.initState();
    // Dá um pequeno tempo pro Firebase hidratar o currentUser do cache local
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _gaveAuthHydrationSomeTime = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        // Enquanto a stream está conectando OU ainda não demos tempo para hidratar
        if (snap.connectionState == ConnectionState.waiting || !_gaveAuthHydrationSomeTime) {
          return const _Splash();
        }

        // Usa o usuário já hidratado do Firebase; não chame reload aqui
        final user = snap.data ?? FirebaseAuth.instance.currentUser;

        if (user == null) {
          // Nenhum usuário logado: mostra onboarding
          return const OnboardingPage();
        }

        // Não chame user.reload() no boot — verificação de e-mail é baseada no cache
        final verified = user.emailVerified;
        if (!verified) {
          return const VerificarEmailPage();
        }

        // Usuário autenticado e verificado:
        // Cria o UsuarioProvider apenas aqui, após o login
        return MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) => UsuarioProvider()..onLogin(),
            ),
          ],
          child: const _HomeAndBootTasks(),
        );
      },
    );
  }
}

/// Responsável por rodar tarefas pós-login (WorkManager, etc.)
class _HomeAndBootTasks extends StatefulWidget {
  const _HomeAndBootTasks();

  @override
  State<_HomeAndBootTasks> createState() => _HomeAndBootTasksState();
}

class _HomeAndBootTasksState extends State<_HomeAndBootTasks> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final uid = FirebaseAuth.instance.currentUser!.uid;

      // Sempre registra a task do paciente
      await BgSync.register(pacienteUid: uid);

      // Se também for cuidador, registra task Carewatch
      try {
        final db = FirebaseFirestore.instance;
        final vincs = await db
            .collection('usuarios').doc(uid)
            .collection('vinculos')
            .where('meuPapel', isEqualTo: 'cuidador')
            .where('status', isEqualTo: 'ativo')
            .limit(1)
            .get(const GetOptions(source: Source.server));
        if (vincs.docs.isNotEmpty) {
          await CarewatchSync.register(cuidadorUid: uid);
        }
      } catch (_) {
        // Se falhar (offline, etc.), apenas ignora
      }
    });
  }

  @override
  Widget build(BuildContext context) => const HomePage();
}

/// Tela de splash simples enquanto inicializa o app
class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
