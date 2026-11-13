// 假的 core 用 sh 實作，Windows 上無法執行
@TestOn('mac-os || linux')

import 'dart:async';
import 'dart:io';

import 'package:better_mcfallout_bot/src/better_mcfallout_bot.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// 等到 [connector] 的狀態符合 [condition]。
Future<void> until(BotConnector connector, bool Function() condition) {
  final reached = Completer<void>();
  void check() {
    if (condition() && !reached.isCompleted) reached.complete();
  }

  connector.addListener(check);
  check();
  return reached.future.timeout(immediately);
}

void main() {
  setUpAll(initConfig);

  test('帳號憑證有效且伺服器連得上時，回傳已連線的 bot', () async {
    final connector =
        BotConnector(account: account, validate: valid, createBot: reachable);

    final bot = await connector.connect();
    addTearDown(() => bot?.disconnect());

    expect(bot?.connected, isTrue);
  });

  test('連不上伺服器時不回傳 bot，並記下失敗的原因', () async {
    final connector =
        BotConnector(account: account, validate: valid, createBot: unreachable);

    expect(await connector.connect(), isNull);
    expect(connector.failures, 1);
    expect(connector.lastError, 'connect ECONNREFUSED 127.0.0.1:25565');
  });

  test('畫面可以分辨目前是在檢查帳號憑證，還是在連線', () async {
    final checked = Completer<bool>();
    final connector = BotConnector(
        account: account,
        validate: (account) => checked.future,
        createBot: reachable);

    final result = connector.connect();
    expect(connector.checkingCredentials, isTrue);

    checked.complete(true);
    await until(connector, () => !connector.checkingCredentials);

    final bot = await result;
    addTearDown(() => bot?.disconnect());
  });

  test('連線失敗時會通知畫面，讓它顯示失敗的原因', () async {
    final connector =
        BotConnector(account: account, validate: valid, createBot: unreachable);
    String? shown;
    connector.addListener(() => shown = connector.lastError);

    await connector.connect();

    expect(shown, 'connect ECONNREFUSED 127.0.0.1:25565');
  });

  test('重連時立刻先試一次，連不上就每 30 秒再試，直到連上', () async {
    final waits = <Duration>[];
    final connector = BotConnector(
        account: account,
        reconnect: true,
        validate: valid,
        createBot: inOrder([unreachable, unreachable, reachable]),
        wait: (duration) async => waits.add(duration));

    final bot = await connector.connect();
    addTearDown(() => bot?.disconnect());

    expect(bot?.connected, isTrue);
    expect(waits, [const Duration(seconds: 30), const Duration(seconds: 30)]);
  });

  test('連續失敗 10 次後，改成每 15 分鐘試一次，而且不會停', () async {
    final waits = <Duration>[];
    final connector = BotConnector(
        account: account,
        reconnect: true,
        validate: valid,
        createBot: inOrder([...List.filled(12, unreachable), reachable]),
        wait: (duration) async => waits.add(duration));

    final bot = await connector.connect();
    addTearDown(() => bot?.disconnect());

    expect(bot?.connected, isTrue);
    expect(waits, [
      ...List.filled(9, const Duration(seconds: 30)),
      ...List.filled(3, const Duration(minutes: 15)),
    ]);
  });

  /// 第一次檢查帳號憑證的結果是 [firstCheck]，之後都有效。回傳等待重試時
  /// 畫面看得到的失敗原因，以及是否提示重新登入。
  Future<List> shownAfterFirstCheck(Future<bool> Function() firstCheck,
      {Duration validateTimeout = const Duration(seconds: 15)}) async {
    var checks = 0;
    final shown = <List>[];
    late final BotConnector connector;
    connector = BotConnector(
        account: account,
        reconnect: true,
        validate: (account) => checks++ == 0 ? firstCheck() : valid(account),
        validateTimeout: validateTimeout,
        createBot: reachable,
        wait: (duration) async =>
            shown.add([connector.lastError, connector.needsLogin]));

    final bot = await connector.connect();
    addTearDown(() => bot?.disconnect());

    expect(bot?.connected, isTrue);
    // 只失敗一次就連上了
    return shown.single;
  }

  test('檢查帳號憑證時網路不通，算一次失敗並繼續重試', () async {
    final shown = await shownAfterFirstCheck(
        () async => throw const SocketException('Failed host lookup'));

    expect(shown, ['無法檢查帳號憑證：SocketException: Failed host lookup', false]);
  });

  test('帳號憑證過期且更新失敗時，算一次失敗並繼續重試，同時提示要重新登入', () async {
    final shown = await shownAfterFirstCheck(() async => false);

    expect(shown, ['帳號憑證已過期且更新失敗，持續發生時請重新登入', true]);
  });

  test('檢查帳號憑證一直沒有回應時，逾時後算一次失敗並繼續重試', () async {
    final shown = await shownAfterFirstCheck(() => Completer<bool>().future,
        validateTimeout: const Duration(milliseconds: 100));

    expect(shown, ['無法檢查帳號憑證：逾時', false]);
  });

  test('帳號憑證更新之後，檢查與連線都改用更新後的憑證', () async {
    addTearDown(() => accountStorage.remove(account.uuid));
    final checked = <String>[];
    final used = <String>[];
    BotFactory recording(BotFactory core) => (account) {
          used.add(account.minecraftToken);
          return core(account);
        };
    final connector = BotConnector(
        account: account,
        reconnect: true,
        validate: (account) async {
          checked.add(account.minecraftToken);
          // 檢查時發現憑證過期並更新成功：新的憑證會存起來
          await accountStorage.add(Account(
              uuid: account.uuid,
              username: account.username,
              minecraftToken: 'refreshed-token',
              credentials: account.credentials));
          return true;
        },
        createBot: inOrder([recording(unreachable), recording(reachable)]),
        wait: (duration) async {});

    final bot = await connector.connect();
    addTearDown(() => bot?.disconnect());

    expect(used, ['refreshed-token', 'refreshed-token']);
    expect(checked, ['token', 'refreshed-token']);
  });

  test('等待下次重試時，可以知道已連續失敗幾次、原因與下次重試的時間', () async {
    final connector = BotConnector(
        account: account,
        reconnect: true,
        validate: valid,
        createBot: unreachable,
        // 一直等不到下次重試
        wait: (duration) => Completer<void>().future);

    connector.connect();
    await until(connector, () => connector.nextAttemptAt != null);

    expect(connector.failures, 1);
    expect(connector.lastError, 'connect ECONNREFUSED 127.0.0.1:25565');
    expect(connector.nextAttemptAt!.difference(DateTime.now()).inSeconds,
        closeTo(30, 1));
  });

  test('等待結束、開始重試時，不再有下次重試的時間', () async {
    final elapsed = Completer<void>();
    var checks = 0;
    final connector = BotConnector(
        account: account,
        reconnect: true,
        // 第二次檢查卡住，讓重試停在進行中
        validate: (account) =>
            checks++ == 0 ? valid(account) : Completer<bool>().future,
        createBot: unreachable,
        wait: (duration) => elapsed.future);

    connector.connect();
    await until(connector, () => connector.nextAttemptAt != null);

    elapsed.complete();
    await until(connector, () => connector.nextAttemptAt == null);

    expect(connector.failures, 1);
  });

  test('等待重試時取消，就不再重試', () async {
    var attempts = 0;
    final connector = BotConnector(
        account: account,
        reconnect: true,
        validate: valid,
        createBot: (account) {
          attempts++;
          return unreachable(account);
        },
        // 一直等不到下次重試
        wait: (duration) => Completer<void>().future);

    final result = connector.connect();
    await until(connector, () => connector.nextAttemptAt != null);

    connector.cancel();

    expect(await result.timeout(immediately), isNull);
    expect(attempts, 1);
  });

  test('連線進行中取消時，就算之後連上了也不會留著', () async {
    late final BotConnector connector;
    late final BotCore bot;
    connector = BotConnector(
        account: account,
        reconnect: true,
        validate: valid,
        createBot: (account) {
          // 使用者在 core 連線時按下取消
          connector.cancel();
          return bot = reachable(account);
        });

    expect(await connector.connect().timeout(immediately), isNull);
    expect(bot.connected, isFalse);
    // 沒被結束的話，要等假 core 的 sleep 30 跑完才會有結束代碼
    await bot.process.exitCode.timeout(immediately);
  });

  test('檢查帳號憑證時取消，就不會再啟動 core', () async {
    final checked = Completer<bool>();
    var cores = 0;
    final connector = BotConnector(
        account: account,
        reconnect: true,
        validate: (account) => checked.future,
        createBot: (account) {
          cores++;
          return reachable(account);
        });

    final result = connector.connect();
    connector.cancel();
    checked.complete(true);

    expect(await result.timeout(immediately), isNull);
    expect(cores, 0);
  });
}
