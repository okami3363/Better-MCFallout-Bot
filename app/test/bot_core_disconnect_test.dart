// 假的 core 用 sh 實作，Windows 上無法執行
@TestOn('mac-os || linux')

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

    // 沒被結束的話，要等假 core 的 sleep 30 跑完才會有結束代碼
    await bot.process.exitCode.timeout(immediately);
  });

  test('使用者手動斷線時不算連線中斷，不會觸發重連', () async {
    final bot = reachable(account);
    await bot.connect();

    var lost = false;
    bot.connectionLost.then((_) => lost = true);

    bot.disconnect();
    await bot.process.exitCode;
    // 等 core 的輸出讀完、行程結束的處理都跑過
    await Future.delayed(const Duration(milliseconds: 100));

    expect(lost, isFalse);
  });
}
