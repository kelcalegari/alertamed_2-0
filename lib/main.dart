import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:smartmed/presentation/pages/basePagina/splash_page.dart';
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

  // Idioma dos e-mails do Firebase (ok se falhar)
  try {
    await FirebaseAuth.instance.setLanguageCode('pt_BR');
  } catch (_) {}

  // Notificações locais
  await NotificationService().init();

  // Workmanager (dispatcher global)
  await Workmanager().initialize(bgCallbackDispatcher);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UsuarioProvider(), lazy: true),
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

      // ✅ Use só a SplashPage; ela decide e navega.
      home: const OnboardingPage(),

      onGenerateRoute: Routes.generateRoute,
    );
  }
}
