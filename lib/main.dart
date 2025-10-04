import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:smartmed/presentation/routes/routes.dart';
import 'package:smartmed/providers/user_data_provider.dart';
import 'package:workmanager/workmanager.dart';
import 'core/services/bg_sync.dart';
import 'core/services/notification_service.dart';
import 'firebase_options.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('America/Sao_Paulo'));

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // (Opcional) idioma dos e-mails do Firebase
  try {
    await FirebaseAuth.instance.setLanguageCode('pt_BR');
  } catch (_) {}

  await NotificationService().init();

  await Workmanager().initialize(
    bgCallbackDispatcher,
    isInDebugMode: false, // true para testes (logs)
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
    // Define a rota inicial:
    // - não logado -> onboarding
    // - logado e verificado -> home
    // - logado e NÃO verificado -> verifyEmail
    final user = FirebaseAuth.instance.currentUser;
    final String initial;
    if (user == null) {
      initial = Routes.onboarding;
    } else {
      initial = (user.emailVerified == true) ? Routes.home : Routes.verifyEmail;
    }

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
      initialRoute: initial,
      onGenerateRoute: Routes.generateRoute,
    );
  }
}
