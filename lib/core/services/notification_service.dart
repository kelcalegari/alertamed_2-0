
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

    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
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
          'alertamed_channel',
          'AlertaMED',
          channelDescription: 'Canal para lembretes de medicação',
          importance: Importance.max,
          priority: Priority.high,
          actions: [tomarAction, pularAction, adiarAction],
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: '$idLembrete|$idUsuario',
      matchDateTimeComponents: null
    );
  }


  Future<void> cancelNotification(int id) async => _plugin.cancel(id);

  Future<List<PendingNotificationRequest>> listScheduled() async =>
      _plugin.pendingNotificationRequests();
}
void _onActionReceived(NotificationResponse response) async {
  final payload = response.payload; // Formato: "idLembrete|idUsuario"
  if (payload == null) return;
  final parts = payload.split('|');
  if (parts.length != 2) return;

  final idLembrete = parts[0];
  final idUsuario = parts[1];

  final context = navigatorKey.currentContext; // Precisa de um GlobalKey<NavigatorState>
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
        idUsuario: idUsuario,
      );
      await usuarioProvider.fetchData();
      break;
    case 'ADIAR_LEMBRETE':
      final novaHora = DateTime.now().add(Duration(minutes: 10)); // adiar 10min
      await lembreteService.adiarLembrete(
        context: context,
        idLembrete: idLembrete,
        idUsuario: idUsuario,
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

