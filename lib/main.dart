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
  await Workmanager().initialize(bgCallbackDispatcher);

  runApp(
    MultiProvider(
      providers: [
        // lazy: true evita criar antes da primeira leitura
        ChangeNotifierProvider(
          create: (_) => UsuarioProvider(),
          lazy: true,
        ),
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
      home: const SplashGate(),
      onGenerateRoute: Routes.generateRoute,
    );
  }
}

/// Gate de autenticação:
/// - Sem usuário -> Onboarding
/// - Com usuário e email verificado -> Home (+ dispara onLogin do provider)
/// - Com usuário e sem verificação -> VerificarEmail
class SplashGate extends StatefulWidget {
  const SplashGate({super.key});
  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  bool _gaveAuthHydrationSomeTime = false;
  bool _ranProviderLoginOnce = false; // evita chamadas repetidas

  @override
  void initState() {
    super.initState();
    // Dá um respiro maior para o Firebase hidratar o currentUser do storage
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _gaveAuthHydrationSomeTime = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting || !_gaveAuthHydrationSomeTime) {
          return const _Splash();
        }

        // Usa o usuário já hidratado do Firebase; não chame reload aqui
        final user = snap.data ?? FirebaseAuth.instance.currentUser;

        if (user == null) {
          _ranProviderLoginOnce = false; // reset
          return const OnboardingPage();
        }

        final verified = user.emailVerified;
        if (!verified) {
          _ranProviderLoginOnce = false; // reset
          return const VerificarEmailPage();
        }

        // Dispara onLogin do provider UMA vez (ele já registra BgSync/Carewatch e carrega dados)
        if (!_ranProviderLoginOnce) {
          _ranProviderLoginOnce = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            context.read<UsuarioProvider>().onLogin();
          });
        }

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
