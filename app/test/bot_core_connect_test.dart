// 假的 core 用 sh 實作，Windows 上無法執行
@TestOn('mac-os || linux')

import 'dart:convert';
import 'dart:io';

import 'package:better_mcfallout_bot/src/better_mcfallout_bot.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oauth2/oauth2.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 用 shell script 假裝是 core：印出 JSON 事件、寫 stderr、結束或卡住。
CoreLauncher fakeCore(List<String> script) =>
    (config) => Process.start('sh', ['-c', script.join('\n')]);

/// core 從 stdout 印出的一行事件。
String emit(String event, Map<String, dynamic> data) =>
    "echo '${jsonEncode({'event': event, 'data': data})}'";

/// 行程不結束也不再輸出，模擬卡住的 core。
const hang = 'exec sleep 30';

BotCore createBot(CoreLauncher startCore,
        {Duration connectTimeout = const Duration(seconds: 20)}) =>
    BotCore.createBot(
        region: ServerRegion.defaultRegion,
        port: 25565,
        account: Account(
            uuid: 'uuid',
            username: 'tester',
            minecraftToken: 'token',
            credentials: Credentials('access-token')),
        startCore: startCore,
        connectTimeout: connectTimeout);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await ConfigHelper.init();
  });

  test('core 回報 connected 時連線成功', () async {
    final bot = createBot(fakeCore([
      emit('connected', {
        'host': 'mcfallout.net',
        'port': 25565,
        'game_version': '1.19.2',
        'start_at': 0
      }),
      hang,
    ]));
    addTearDown(bot.disconnect);

    expect(await bot.connect(), isNull);
    expect(bot.connected, isTrue);
  });

  test('core 在連線成功前當掉時，立刻回報 core 最後的錯誤訊息', () async {
    // 與實際當掉時 Node 印出的內容同形：無關的警告、原始碼片段、錯誤、堆疊
    final bot = createBot(fakeCore([
      emit('info', {'message': 'Bot created'}),
      'echo "(node:1) [DEP0040] DeprecationWarning: The punycode module is deprecated." >&2',
      'echo "/core/node_modules/mineflayer/lib/plugins/game.js:46" >&2',
      'echo "        const { minY, height } = bot.registry.dimensionsByName[bot.game.dimension]" >&2',
      'echo "" >&2',
      "echo \"TypeError: Cannot read properties of undefined (reading 'overworld')\" >&2",
      'echo "    at handleRespawnPacketData (game.js:46:63)" >&2',
      'echo "" >&2',
      'echo "Node.js v21.5.0" >&2',
      'exit 1',
    ]));

    final stopwatch = Stopwatch()..start();
    final error = await bot.connect();

    expect(error,
        "TypeError: Cannot read properties of undefined (reading 'overworld')");
    // 不等 20 秒逾時
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
  });

  test('core 沒留下任何錯誤就結束時，回報它的結束代碼', () async {
    final bot = createBot(fakeCore(['exit 3']));

    expect(await bot.connect(), 'core 意外結束（結束代碼 3）');
  });

  test('被伺服器踢出時，立刻回報伺服器給的原因', () async {
    // core 被踢出後行程不會自己結束
    final bot = createBot(fakeCore([
      emit('info', {'message': 'Bot created'}),
      emit('error', {'message': 'The bot was kicked by server: 您已被伺服器封鎖'}),
      emit('disconnected', {'reason': 'disconnect.quitting'}),
      hang,
    ]));

    final stopwatch = Stopwatch()..start();
    final error = await bot.connect();

    expect(error, contains('您已被伺服器封鎖'));
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
  });

  test('core 回報錯誤後沒有下文時，逾時後回報該錯誤', () async {
    final bot = createBot(
        fakeCore([
          emit('error', {'message': 'connect ECONNREFUSED 127.0.0.1:25565'}),
          hang,
        ]),
        connectTimeout: const Duration(milliseconds: 300));

    expect(await bot.connect(), 'connect ECONNREFUSED 127.0.0.1:25565');
  });

  test('既沒連上也沒有任何錯誤時，回報連線逾時', () async {
    final bot = createBot(fakeCore([hang]),
        connectTimeout: const Duration(milliseconds: 300));

    expect(await bot.connect(), '連線逾時');
  });

  test('連線失敗後會結束 core 行程，不讓它留在背景', () async {
    late Process core;
    final bot = createBot(
        (config) async => core = await Process.start('sh', ['-c', hang]),
        connectTimeout: const Duration(milliseconds: 300));

    await bot.connect();

    // 沒被結束的話，要等假 core 的 sleep 30 跑完才會有結束代碼
    await core.exitCode.timeout(const Duration(seconds: 5));
  });

  test('core 無法啟動時，回報啟動失敗的原因', () async {
    final bot = createBot((config) => throw const ProcessException(
        'yarn', ['build'], 'No such file or directory', 2));

    expect(await bot.connect(), contains('No such file or directory'));
  });
}
