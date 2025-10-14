import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tzData;

import '../../main.dart';
import '../../presentation/pages/home/service/alterar_lembrete.dart';
import '../../providers/user_data_provider.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tzData.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('America/Sao_Paulo'));

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidInit);
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onActionReceived,
    );

    final androidImpl =
        _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
    await androidImpl?.requestNotificationsPermission();
  }

  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDateTime,
    required String idLembrete,
    required String idUsuario,
  }) async {
    const tomarAction = AndroidNotificationAction(
      'TOMAR_LEMBRETE',
      'Tomar',
      showsUserInterface: true,
      cancelNotification: true,
    );

    const pularAction = AndroidNotificationAction(
      'PULAR_LEMBRETE',
      'Pular',
      showsUserInterface: true,
      cancelNotification: true,
    );

    const adiarAction = AndroidNotificationAction(
      'ADIAR_LEMBRETE',
      'Adiar',
      showsUserInterface: true,
      cancelNotification: true,
    );
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(scheduledDateTime, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'alertamed_high', // <-- NOVO canal
          'AlertaMED (Alto)',
          channelDescription: 'Lembretes críticos de medicação',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          category: AndroidNotificationCategory.reminder,
          ticker: 'Lembrete de medicação',
          fullScreenIntent: true, // <-- se quiser heads-up forte
          actions: [tomarAction, adiarAction, pularAction],
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: '$idLembrete|$idUsuario',
      matchDateTimeComponents: null,
    );
  }

  Future<void> cancelNotification(int id) async => _plugin.cancel(id);

  Future<List<PendingNotificationRequest>> listScheduled() async =>
      _plugin.pendingNotificationRequests();

  /// Cancela **todas** as notificações locais agendadas/exibidas pelo app.
  Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint('Erro ao cancelar todas notificações: $e');
    }
  }

  /// Exibe imediatamente um alerta para o CUIDADOR (sem ações).
  /// payload: "carewatch|<pacienteUid>|<lembreteId>"
  Future<void> showNowCarewatch({
    required int id,
    required String title,
    required String body,
    required String pacienteUid,
    required String lembreteId,
  }) async {
    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'carewatch_alerts',
          'Alertas do Cuidador',
          channelDescription: 'Atrasos de medicação dos pacientes sob cuidado',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          fullScreenIntent: true,
          category: AndroidNotificationCategory.reminder,
          ticker: 'Atraso de medicação',
        ),
      ),
      payload: 'carewatch|$pacienteUid|$lembreteId',
    );
  }

  /// Agenda um alerta simples para o cuidador (fallback de segurança).
  Future<void> scheduleCarewatchOneShot({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    required String pacienteUid,
    required String lembreteId,
  }) async {
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(when, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'carewatch_alerts',
          'Alertas do Cuidador',
          channelDescription: 'Atrasos de medicação dos pacientes sob cuidado',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          category: AndroidNotificationCategory.reminder,
          ticker: 'Atraso de medicação',
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: 'carewatch|$pacienteUid|$lembreteId',
      matchDateTimeComponents: null,
    );
  }
  // Dentro da classe NotificationService
  Future<void> showInstant({
    required int id,
    required String title,
    required String body,
    String? payload, // ex.: "$idLembrete|$idUsuario" ou "carewatch|..."
    bool highPriority = true,
    bool fullScreen = false,
    List<AndroidNotificationAction>? actions, // opcional
    String channelId = 'alertamed_high',
    String channelName = 'AlertaMED (Alto)',
    String channelDescription = 'Alertas e lembretes imediatos',
  }) async {
    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: highPriority ? Importance.max : Importance.defaultImportance,
      priority: highPriority ? Priority.high : Priority.defaultPriority,
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.reminder,
      ticker: 'Notificação imediata',
      fullScreenIntent: fullScreen, // heads-up mais agressivo se true
      actions: actions ?? const <AndroidNotificationAction>[],
    );

    final details = NotificationDetails(android: androidDetails);

    await _plugin.show(
      id,
      title,
      body,
      details,
      payload: payload,
    );
  }

}

void _onActionReceived(NotificationResponse response) async {
  final payload = response.payload; // Formato: "idLembrete|idUsuario"
  if (payload == null) return;
  final parts = payload.split('|');
  if (parts.length != 2) return;

  final idLembrete = parts[0];
  final idUsuario = parts[1];

  final context =
      navigatorKey.currentContext; // Precisa de um GlobalKey<NavigatorState>
  if (context == null) return;
  final usuarioProvider = context.read<UsuarioProvider>();
  final lembreteService = LembreteService();

  switch (response.actionId) {
    case 'TOMAR_LEMBRETE':
      await lembreteService.marcarComoTomado(
        context: context,
        idLembrete: idLembrete,
        idUsuario: idUsuario,
      );
      await usuarioProvider.fetchData();
      break;
    case 'PULAR_LEMBRETE':
      await lembreteService.pularLembrete(
        context: context,
        idLembrete: idLembrete,
      );
      await usuarioProvider.fetchData();
      break;
    case 'ADIAR_LEMBRETE':
      final novaHora = DateTime.now().add(Duration(minutes: 10)); // adiar 10min
      await lembreteService.adiarLembrete(
        context: context,
        idLembrete: idLembrete,
        novaDataHora: novaHora,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Lembrete adiado para ${novaHora.hour.toString().padLeft(2, '0')}:${novaHora.minute.toString().padLeft(2, '0')} ',
          ),
          duration: Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(16),
        ),
      );
      await usuarioProvider.fetchData();
      break;
  }
}
