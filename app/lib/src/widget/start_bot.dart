import 'package:better_mcfallout_bot/src/better_mcfallout_bot.dart';
import 'package:flutter/material.dart';

/// 啟動機器人，畫面跟著連線的進度換：連線中是對話框，連上後是狀態頁。
///
/// 畫面只負責顯示；連線與重連由 [BotConnector.keepConnected] 推動，
/// 視窗看不到時也會繼續。
void startBot(Account account) {
  final navigator = NavigationService.navigatorKey.currentState!;
  final connector = BotConnector(account: account);
  Route? shown;

  // 換成新的畫面。上一個畫面可能已經被使用者關掉，要先確認它還在。
  void show(Route route) {
    final previous = shown;
    if (previous != null && previous.isActive) navigator.removeRoute(previous);
    navigator.push(shown = route);
  }

  connector.keepConnected(
      onConnecting: () => show(DialogRoute(
          context: navigator.context,
          barrierDismissible: false,
          builder: (context) => ConnectingServer(connector: connector))),
      onConnected: (bot) => show(
          MaterialPageRoute(builder: (context) => BotStatusPage(bot: bot))),
      onDisconnected: (reason) => show(DialogRoute(
          context: navigator.context,
          builder: (context) => AlertDialog(
                title: const Text('錯誤'),
                content:
                    Text('已與伺服器斷線，由於未啟用重新自動連線功能，因此將不會自動重新連線。\n斷線原因：$reason'),
                actions: const [ConfirmButton()],
              ))));
}
