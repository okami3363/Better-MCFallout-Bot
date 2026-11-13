// 假的 core 用 sh 實作，Windows 上無法執行
@TestOn('mac-os || linux')

import 'dart:async';
import 'dart:io';

import 'package:better_mcfallout_bot/src/better_mcfallout_bot.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

// 這裡完全沒有畫面：保持連線的流程不能靠畫面推動，視窗看不到時才不會停住。

/// 用假的憑證檢查與假 core 連線，重試之間不必真的等。
BotConnector connectingWith(BotFactory createBot) => BotConnector(
    account: account,
    validate: valid,
    createBot: createBot,
    wait: (duration) async {});

void main() {
  setUpAll(initConfig);

  test('斷線後自己重連，連不上就一直重試，直到連回去', () async {
    final progress = <String>[];
    final reconnected = Completer<BotCore>();
    final connector =
        connectingWith(inOrder([dropped, unreachable, reachable]));
    connector.keepConnected(
        onConnecting: () => progress.add(connector.reconnect ? '重連中' : '連線中'),
        onConnected: (bot) {
          progress.add('已連線');
          if (progress.where((step) => step == '已連線').length == 2) {
            reconnected.complete(bot);
          }
        },
        onDisconnected: (reason) => progress.add('不重連：$reason'));

    final bot = await reconnected.future.timeout(immediately);
    addTearDown(bot.disconnect);

    expect(progress, ['連線中', '已連線', '重連中', '已連線']);
  });

  test('連上沒多久又斷線也算一次失敗，要等 30 秒才重連', () async {
    final waits = <Duration>[];
    final reasons = <String?>[];
    final bots = <BotCore>[];
    final stayed = Completer<void>();
    late final BotConnector connector;
    connector = BotConnector(
        account: account,
        validate: valid,
        // 伺服器一讓機器人進去就踢掉，第三次才留得住
        createBot: inOrder([dropped, dropped, reachable]),
        wait: (duration) async {
          waits.add(duration);
          reasons.add(connector.lastError);
        });
    connector.keepConnected(
        onConnecting: () {},
        onConnected: (bot) {
          bots.add(bot);
          if (bots.length == 3) stayed.complete();
        },
        onDisconnected: (reason) {});

    await stayed.future.timeout(immediately);
    addTearDown(bots.last.disconnect);

    expect(waits, [const Duration(seconds: 30), const Duration(seconds: 30)]);
    expect(reasons, ['連上後隨即斷線：socketClosed', '連上後隨即斷線：socketClosed']);
  });

  test('連線維持夠久之後才斷線，立刻重連，不必等', () async {
    final waits = <Duration>[];
    final bots = <BotCore>[];
    final reconnected = Completer<void>();
    BotConnector(
            account: account, validate: valid, createBot: inOrder([dropped, reachable]), wait: (duration) async => waits.add(duration))
        .keepConnected(
            onConnecting: () {},
            onConnected: (bot) {
              bots.add(bot);
              if (bots.length == 2) reconnected.complete();
            },
            onDisconnected: (reason) {},
            // 每一次連線都算維持夠久
            stableAfter: Duration.zero);

    await reconnected.future.timeout(immediately);
    addTearDown(bots.last.disconnect);

    expect(waits, isEmpty);
  });

  test('未啟用自動重新連線時，斷線後不重連，只通知斷線原因', () async {
    appConfig.autoReconnect = false;
    addTearDown(() => appConfig.autoReconnect = true);

    final progress = <String>[];
    final connector = connectingWith(inOrder([dropped, reachable]));
    await connector
        .keepConnected(
            onConnecting: () =>
                progress.add(connector.reconnect ? '重連中' : '連線中'),
            onConnected: (bot) => progress.add('已連線'),
            onDisconnected: (reason) => progress.add('不重連：$reason'))
        .timeout(immediately);

    expect(progress, ['連線中', '已連線', '不重連：socketClosed']);
  });

  test('連上之後依設定開始自動攻擊，重連之後也一樣', () async {
    appConfig.botAction = BotActionType.attack;
    addTearDown(() => appConfig.botAction = BotActionType.afk);

    final dir = Directory.systemTemp.createTempSync('bot_keep_connected_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final received = File('${dir.path}/actions');

    // 假 core 連上後把收到的第一個動作記下來；第一個 core 接著就斷線
    final record = [
      connected,
      'read -r action',
      'echo "\$action" >> ${received.path}'
    ];
    final bots = <BotCore>[];
    addTearDown(() => bots.last.disconnect());
    connectingWith(inOrder([
      (account) => createBot(fakeCore([
            ...record,
            emit('disconnected', {'reason': 'socketClosed'}),
            hang
          ])),
      (account) => createBot(fakeCore([...record, hang])),
    ])).keepConnected(
        onConnecting: () {},
        onConnected: bots.add,
        onDisconnected: (reason) {});

    Future<List<String>> actions() async {
      while (!received.existsSync() || received.readAsLinesSync().length < 2) {
        await Future.delayed(const Duration(milliseconds: 20));
      }
      return received.readAsLinesSync();
    }

    expect(await actions().timeout(immediately), [
      '{"action":"attack","method":"start","argument":null}',
      '{"action":"attack","method":"start","argument":null}',
    ]);
  });
}
