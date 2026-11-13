// 假的 core 用 sh 實作，Windows 上無法執行
@TestOn('mac-os || linux')

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  setUpAll(initConfig);

  test('core 回報 connected 時連線成功', () async {
    final bot = createBot(fakeCore([connected, hang]));
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

    expect(await bot.connect().timeout(immediately),
        "TypeError: Cannot read properties of undefined (reading 'overworld')");
  });

  test('core 沒留下任何錯誤就結束時，回報它的結束代碼', () async {
    final bot = createBot(fakeCore(['exit 3']));

    expect(await bot.connect(), 'core 意外結束（結束代碼 3）');
  });

  test('core 回報錯誤後就結束時，回報該錯誤而不是結束代碼', () async {
    // core 建立 bot 失敗時會用事件回報錯誤，然後以代碼 0 結束
    final bot = createBot(fakeCore([
      emit('error', {'message': 'Error while creating the bot: boom'}),
      'exit 0',
    ]));

    expect(await bot.connect().timeout(immediately),
        'Error while creating the bot: boom');
  });

  test('被伺服器踢出時，立刻回報伺服器給的原因', () async {
    // core 被踢出後行程不會自己結束
    final bot = createBot(fakeCore([
      emit('info', {'message': 'Bot created'}),
      emit('error', {'message': '被伺服器踢出：您已被伺服器封鎖'}),
      emit('disconnected', {'reason': 'disconnect.quitting'}),
      hang,
    ]));

    expect(await bot.connect().timeout(immediately), contains('您已被伺服器封鎖'));
  });

  test('core 在事件之間印出非 JSON 內容時，仍立刻回報它回報的錯誤', () async {
    // mineflayer 會先把錯誤堆疊印到 stdout，才輪到 core 的 JSON 事件
    final bot = createBot(fakeCore([
      "cat <<'EOF'",
      'Error: connect ECONNREFUSED 127.0.0.1:25565',
      '    at TCPConnectWrap.afterConnect [as oncomplete] (node:net:1595:16) {',
      '  errno: -61,',
      "  code: 'ECONNREFUSED'",
      '}',
      jsonEncode({
        'event': 'error',
        'data': {'message': 'connect ECONNREFUSED 127.0.0.1:25565'}
      }),
      jsonEncode({
        'event': 'disconnected',
        'data': {'reason': 'socketClosed'}
      }),
      'EOF',
      hang,
    ]));

    expect(await bot.connect().timeout(immediately),
        'connect ECONNREFUSED 127.0.0.1:25565');
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
    final bot = createBot(fakeCore([hang]),
        connectTimeout: const Duration(milliseconds: 300));

    await bot.connect();

    // 沒被結束的話，要等假 core 的 sleep 30 跑完才會有結束代碼
    await bot.process.exitCode.timeout(immediately);
  });

  test('core 無法啟動時，回報啟動失敗的原因', () async {
    final bot = createBot((config) => throw const ProcessException(
        'yarn', ['build'], 'No such file or directory', 2));

    expect(await bot.connect(), contains('No such file or directory'));
  });

  test('啟動 core 時發生其他例外，也回報原因而不是丟出例外', () async {
    final bot = createBot(
        (config) => throw Exception('Failed to find core executable'));

    expect(await bot.connect(), contains('Failed to find core executable'));
  });
}
