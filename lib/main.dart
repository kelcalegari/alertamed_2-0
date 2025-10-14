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

  // Workmanager (apenas inicializa o dispatcher global)
  await Workmanager().initialize(
    bgCallbackDispatcher
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UsuarioProvider()),
      ],
      child: const AlertaMedApp(),
    ),
  );
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
      // Em vez de initialRoute estático, usamos uma gate que escuta o auth.
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
    // Dá um respiro de ~500ms para o Firebase hidratar o currentUser do storage
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _gaveAuthHydrationSomeTime = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        // Enquanto a stream está conectando OU ainda não demos tempo para hidratar, mostra splash
        if (snap.connectionState == ConnectionState.waiting || !_gaveAuthHydrationSomeTime) {
          return const _Splash();
        }

        // Usa o usuário já hidratado do Firebase; não chame reload aqui
        final user = snap.data ?? FirebaseAuth.instance.currentUser;

        if (user == null) {
          return const OnboardingPage();
        }

        // NÃO chame user.reload() no boot — verificação de e-mail é baseada no cache.
        final verified = user.emailVerified;
        if (!verified) {
          return const VerificarEmailPage();
        }

        // Pos-frame para registrar tasks; não depende de rede para decidir a navegação
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          final uid = user.uid;
          await BgSync.register(pacienteUid: uid);
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
          } catch (_) {/* ignore: offline etc. */}
        });

        return const HomePage();
      },
    );
  }
}



class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
