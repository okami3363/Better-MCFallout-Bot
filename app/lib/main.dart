import 'dart:io';

import 'package:better_mcfallout_bot/src/better_mcfallout_bot.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await logging();
  Logger.root.info('App starting');
  await windowManager.ensureInitialized();
  await ConfigHelper.init();

  runApp(const App());
}

/// 把紀錄寫到本機的紀錄檔。不會送出任何錯誤回報，要查問題只能看這份檔案，
/// 所以沒被接住的錯誤也要記進來。
Future<void> logging() async {
  final baseDir = await getApplicationSupportDirectory();
  final time = DateTime.now();
  final logFile = File(join(baseDir.path, 'logs',
      '${time.year}-${time.month}-${time.day}-${time.hour}-${time.minute}-${time.second}.log'));
  Logger.root.onRecord.listen((record) {
    if (kDebugMode) {
      print(record.toString());
    }

    String log = '[${record.time}] ${record.level.name}: ${record.message}';
    if (record.stackTrace != null) {
      log += '\n${record.stackTrace}';
    }

    try {
      if (!logFile.existsSync()) {
        logFile.createSync(recursive: true);
      }
      logFile.writeAsStringSync('$log\n', mode: FileMode.append);
    } catch (_) {
      // 寫不進去（例如磁碟滿了）就放棄這一筆。不限定例外型別：這裡丟出的例外
      // 會被下面的 onError 接住、又回來寫紀錄，沒完沒了，app 會卡住。
    }
  });

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    Logger.root.severe(details.exceptionAsString(), null, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    Logger.root.severe('$error', null, stackTrace);
    // 回傳 false，讓系統照常把錯誤與堆疊印到 console
    return false;
  };
}
