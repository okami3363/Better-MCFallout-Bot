// 假的 core 用 sh 實作，Windows 上無法執行
@TestOn('mac-os || linux')

import 'dart:async';

import 'package:better_mcfallout_bot/src/better_mcfallout_bot.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  setUpAll(initConfig);

  test('core 在已連線的狀態下當掉時視為連線中斷，原因是它留下的錯誤', () async {
    // core 當掉時來不及回報 disconnected，只會在 stderr 留下錯誤
    final bot = createBot(fakeCore([
      connected,
      'echo "TypeError: boom" >&2',
      'exit 1',
    ]));
    expect(await bot.connect(), isNull);

    expect(await bot.connectionLost.timeout(immediately), 'TypeError: boom');
    expect(bot.connected, isFalse);
  });

  test('core 在已連線的狀態下沒留下錯誤就結束時，原因是結束代碼，不是先前回報過的錯誤', () async {
    final bot = createBot(fakeCore([
      connected,
      // 連上之後回報過的錯誤，和這次結束無關
      emit('error', {'message': '先前的錯誤'}),
      'exit 3',
    ]));
    expect(await bot.connect(), isNull);

    expect(await bot.connectionLost.timeout(immediately), 'core 意外結束（結束代碼 3）');
  });

  test('core 回報斷線時視為連線中斷，就算才剛連上', () async {
    // 一連上就斷線：就算還沒有人開始等，也不能漏掉這次斷線
    final bot = dropped(account);
    expect(await bot.connect(), isNull);

    expect(await bot.connectionLost.timeout(immediately), 'socketClosed');
    expect(bot.connected, isFalse);
  });

  test('連線中斷後會結束 core 行程，不讓它留在背景', () async {
    // core 回報斷線後行程不會自己結束
    final bot = dropped(account);
    await bot.connect();
    await bot.connectionLost;

    await coreEnded(bot);
  });

  test('使用者手動斷線時不算連線中斷，不會觸發重連', () async {
    final bot = reachable(account);
    await bot.connect();

    var lost = false;
    bot.connectionLost.then((_) => lost = true);

    bot.disconnect();
    await coreEnded(bot);
    // 等 core 的輸出讀完、行程結束的處理都跑過
    await Future.delayed(const Duration(milliseconds: 100));

    expect(lost, isFalse);
  });

  test('連線途中斷線時立刻結束 core，不等它連上或逾時', () async {
    final started = Completer<void>();
    // 一直連不上的 core：沒被中止的話，要等 20 秒才逾時
    final bot = createBot(announcing(started, fakeCore([hang])));

    final result = bot.connect();
    await started.future;
    bot.disconnect();

    expect(await result.timeout(immediately), '已中止連線');
    await coreEnded(bot);
  });

  test('BotCore.instance 在連線途中就指向這個 bot，關閉 app 時才結束得了它的 core', () async {
    final started = Completer<void>();
    final bot = createBot(announcing(started, fakeCore([hang])));

    bot.connect();
    await started.future;
    // 使用者確認關閉視窗時，App 呼叫的就是這一行（app.dart）
    BotCore.instance?.disconnect();

    await coreEnded(bot);
  });

  test('斷線之後才讀到 core 回報連上的話不算連上，core 結束時也不算連線中斷', () async {
    final bot = createBot((config) async {
      // core 一啟動就連上了，但 bot 要到斷線之後才讀得到它的回報
      final process = await fakeCore([connected])(config);
      await process.exitCode;
      return process;
    });
    var lost = false;
    bot.connectionLost.then((_) => lost = true);

    final result = bot.connect();
    bot.disconnect();

    expect(await result.timeout(immediately), '已中止連線');
    // 等 core 的輸出讀完、行程結束的處理都跑過
    await Future.delayed(const Duration(milliseconds: 100));

    expect(lost, isFalse);
  });

  test('還沒開始啟動 core 就斷線的話，不會啟動 core', () async {
    var launched = false;
    final bot = createBot((config) {
      launched = true;
      return fakeCore([connected, hang])(config);
    });

    // 例如還在挑選伺服器區域時就被取消
    bot.disconnect();

    expect(await bot.connect().timeout(immediately), '已中止連線');
    expect(launched, isFalse);
  });

  test('core 還沒啟動完成就斷線時，core 一啟動就被結束，不會留在背景', () async {
    final ready = Completer<void>();
    final bot = createBot((config) async {
      // core 還在啟動
      await ready.future;
      // 放著不管的話，它一啟動就會連上伺服器
      return fakeCore([connected, hang])(config);
    });

    final result = bot.connect();
    bot.disconnect();
    ready.complete();

    expect(await result.timeout(immediately), '已中止連線');
    await coreEnded(bot);
  });
}
