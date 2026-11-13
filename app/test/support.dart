// 測試共用：用 shell script 假裝是 core。
// sh 在 Windows 上無法執行，用到的測試檔要加上 @TestOn('mac-os || linux')。
import 'dart:convert';
import 'dart:io';

import 'package:better_mcfallout_bot/src/better_mcfallout_bot.dart';
import 'package:oauth2/oauth2.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// BotCore 會讀取 app 的設定，測試開始前要先初始化。
Future<void> initConfig() async {
  SharedPreferences.setMockInitialValues({});
  await ConfigHelper.init();
}

/// 用 shell script 假裝是 core：印出 JSON 事件、寫 stderr、結束或卡住。
CoreLauncher fakeCore(List<String> script) =>
    (config) => Process.start('sh', ['-c', script.join('\n')]);

/// core 從 stdout 印出的一行事件。
String emit(String event, Map<String, dynamic> data) =>
    "echo '${jsonEncode({'event': event, 'data': data})}'";

/// core 連上伺服器時印出的事件。
final connected = emit('connected', {
  'host': 'mcfallout.net',
  'port': 25565,
  'game_version': '1.19.2',
  'start_at': 0
});

/// 行程不結束也不再輸出，模擬卡住的 core。
const hang = 'exec sleep 30';

/// 「立刻回報」的上限：遠短於預設的 20 秒逾時。
const immediately = Duration(seconds: 5);

final account = Account(
    uuid: 'uuid',
    username: 'tester',
    minecraftToken: 'token',
    credentials: Credentials('access-token'));

BotCore createBot(CoreLauncher startCore,
        {Duration connectTimeout = const Duration(seconds: 20)}) =>
    BotCore.createBot(
        region: ServerRegion.defaultRegion,
        port: 25565,
        account: account,
        startCore: startCore,
        connectTimeout: connectTimeout);

/// 假的憑證檢查：帳號憑證有效。
Future<bool> valid(Account account) async => true;

/// 連得上伺服器的假 core。
BotCore reachable(Account account) => createBot(fakeCore([connected, hang]));

/// 連不上伺服器的假 core。
BotCore unreachable(Account account) => createBot(fakeCore([
      emit('error', {'message': 'connect ECONNREFUSED 127.0.0.1:25565'}),
      emit('disconnected', {'reason': 'socketClosed'}),
      hang,
    ]));

/// 連上伺服器後馬上斷線的假 core。
BotCore dropped(Account account) => createBot(fakeCore([
      connected,
      emit('disconnected', {'reason': 'socketClosed'}),
      hang,
    ]));

/// 每次連線依序使用下一個假 core。
BotFactory inOrder(List<BotFactory> cores) {
  var next = 0;
  return (account) => cores[next++](account);
}
