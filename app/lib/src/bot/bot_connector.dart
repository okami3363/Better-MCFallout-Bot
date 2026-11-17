import 'dart:async';

import 'package:better_mcfallout_bot/src/better_mcfallout_bot.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

final Logger _logger = Logger('bot_connector');

/// 檢查帳號憑證是否有效，測試時用來換成假的檢查。
typedef CredentialCheck = Future<bool> Function(Account account);

/// 建立要連線的 bot，測試時用來換成假的 core。
typedef BotFactory = BotCore Function(Account account);

/// 讓機器人連上廢土伺服器，並在斷線後連回去。
class BotConnector extends ChangeNotifier {
  /// 連線失敗後，隔多久再試一次。
  static const retryInterval = Duration(seconds: 30);

  /// 連續失敗 [slowAfterFailures] 次後，改成隔這麼久才試一次。
  static const slowRetryInterval = Duration(minutes: 15);
  static const slowAfterFailures = 10;

  final Account account;

  /// 這是斷線後的重連：連不上會一直重試，直到連上或被取消。
  bool reconnect;

  final CredentialCheck _validate;

  /// 檢查帳號憑證最多等多久。
  final Duration validateTimeout;
  final BotFactory _createBot;
  final Future<void> Function(Duration) _wait;

  /// 已連續失敗的次數。
  int failures = 0;

  /// 上次失敗的原因。
  String? lastError;

  /// 帳號憑證過期且更新失敗：要使用者重新登入才連得上。
  bool needsLogin = false;

  /// 下次重試的時間；不是在等待重試時為 null。
  DateTime? nextAttemptAt;

  /// 這次連線還在檢查帳號憑證，尚未開始連到伺服器。
  bool checkingCredentials = true;

  final _cancelled = Completer<void>();

  /// 最近一次連線用的 bot：取消時要一併結束。
  BotCore? _bot;

  BotConnector(
      {required this.account,
      this.reconnect = false,
      CredentialCheck validate = MicrosoftOauthHandler.validate,
      this.validateTimeout = const Duration(seconds: 15),
      BotFactory createBot = _createRealBot,
      Future<void> Function(Duration) wait = _delay})
      : _validate = validate,
        _createBot = createBot,
        _wait = wait;

  /// 連上伺服器並保持連線：斷線後就重連（若啟用「自動重新連線」），
  /// 直到連線失敗、被取消，或斷線後不重連為止。
  ///
  /// 這段流程刻意不靠畫面推動：視窗被遮住、最小化或螢幕關閉時 Flutter 會停止
  /// 更新畫面，由畫面元件啟動的重連會跟著停住。畫面只透過這裡的通知顯示進度。
  ///
  /// 連線要維持 [stableAfter] 這麼久才算真的連上了。
  Future<void> keepConnected(
      {required void Function() onConnecting,
      required void Function(BotCore bot) onConnected,
      required void Function(String reason) onDisconnected,
      Duration stableAfter = retryInterval}) async {
    while (true) {
      onConnecting();
      final bot = await connect();
      // 連線失敗（不是重連時）或被取消
      if (bot == null) return;

      if (appConfig.botAction == BotActionType.attack) {
        bot.attack(BotActionMethod.start);
      }
      onConnected(bot);
      final connectedAt = DateTime.now();

      final reason = await bot.connectionLost;
      _logger.info('The bot has disconnected: $reason');
      if (!appConfig.autoReconnect) return onDisconnected(reason);

      reconnect = true;
      if (DateTime.now().difference(connectedAt) < stableAfter) {
        // 連上沒多久又斷線（例如一進伺服器就被踢）也算一次失敗，
        // 否則會毫無間隔地一直重連。
        failures++;
        lastError = '連上後隨即斷線：$reason';
      } else {
        failures = 0;
        lastError = null;
      }
    }
  }

  /// 連線到伺服器。成功回傳已連線的 bot；失敗（不是重連時）或被取消回傳 null。
  Future<BotCore?> connect() async {
    while (true) {
      // 之前失敗過，就先等一下再試
      if (failures > 0) {
        final interval =
            failures < slowAfterFailures ? retryInterval : slowRetryInterval;
        nextAttemptAt = DateTime.now().add(interval);
        notifyListeners();
        await Future.any([_wait(interval), _cancelled.future]);
        if (_cancelled.isCompleted) return null;
      }

      BotCore? bot;
      try {
        bot = await _attempt();
      } catch (e) {
        // 不限定例外型別：任何失敗都要算一次，不能讓重試停下來
        failures++;
        lastError = '$e';
      }

      if (_cancelled.isCompleted) {
        // [cancel] 已經結束了這次連線的 bot。這裡是保險：取消正好發生在 bot
        // 建立的當下時 [cancel] 還碰不到它，連上之後也不能留著。
        bot?.disconnect();
        return null;
      }
      if (bot != null) return bot;
      if (!reconnect) {
        notifyListeners();
        return null;
      }
    }
  }

  /// 帳號目前存著的憑證：檢查憑證時可能已經把它更新過了。
  Account get _latestAccount => accountStorage.get(account.uuid) ?? account;

  /// 停止連線：不再重試，[connect] 回傳 null。進行中的那一次連線也一併中止，
  /// core 不會留著繼續連線（各階段怎麼中止見 [BotCore.disconnect]）。
  void cancel() {
    if (_cancelled.isCompleted) return;
    _cancelled.complete();
    _bot?.disconnect();
  }

  /// 嘗試連線一次，失敗時丟出原因。
  Future<BotCore> _attempt() async {
    nextAttemptAt = null;
    checkingCredentials = true;
    notifyListeners();

    try {
      needsLogin = !await _validate(_latestAccount)
          .timeout(validateTimeout, onTimeout: () => throw '逾時');
    } catch (e) {
      needsLogin = false;
      throw '無法檢查帳號憑證：$e';
    }
    if (needsLogin) throw '帳號憑證已過期且更新失敗，持續發生時請重新登入';
    // 已經取消就不必啟動 core
    if (_cancelled.isCompleted) throw '已取消';

    checkingCredentials = false;
    notifyListeners();

    final bot = _bot = _createBot(_latestAccount);
    final error = await bot.connect();
    if (error != null) throw error;
    return bot;
  }

  static BotCore _createRealBot(Account account) => BotCore.createBot(
      region: appConfig.region, port: 25565, account: account);

  static Future<void> _delay(Duration duration) => Future.delayed(duration);
}
