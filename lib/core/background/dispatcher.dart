// lib/background/dispatcher.dart
import 'dart:math';

import 'package:workmanager/workmanager.dart';

import '../services/notification_service.dart';
import 'bg_sync.dart';
import 'carewatch_bg_sync.dart';



/// Dispatcher global chamado pelo Workmanager em segundo plano.
/// Precisa ser top-level e com @pragma('vm:entry-point').
@pragma('vm:entry-point')
void bgCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final map = Map<String, dynamic>.from(inputData ?? {});
    await NotificationService().showInstant(
      id: 9000 + Random().nextInt(1000),
      title: 'BG Task',
      body: 'Executou: $task',
      payload: 'bg|$task',
    );
    if (task == BgSync.taskName) {
      return await BgSync.runPeriodicTask(task, map);
    }
    if (task == CarewatchSync.taskName) {
      return await CarewatchSync.runPeriodicTask(task, map);
    }
    return false;
  });
}
