// lib/background/dispatcher.dart
import 'dart:math';

import 'package:workmanager/workmanager.dart';

import 'bg_sync.dart';
import 'carewatch_bg_sync.dart';



/// Dispatcher global chamado pelo Workmanager em segundo plano.
/// Precisa ser top-level e com @pragma('vm:entry-point').
@pragma('vm:entry-point')
void bgCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final map = Map<String, dynamic>.from(inputData ?? {});

    if (task == BgSync.taskName) {
      return await BgSync.runPeriodicTask(task, map);
    }
    if (task == CarewatchSync.taskName) {
      return await CarewatchSync.runPeriodicTask(task, map);
    }
    return false;
  });
}
