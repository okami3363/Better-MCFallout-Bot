import 'package:better_mcfallout_bot/src/better_mcfallout_bot.dart';
import 'package:flutter/material.dart';

/// 連線對話框：顯示 [connector] 連線的進度。
///
/// 斷線後的重連（[BotConnector.reconnect]）連不上會一直重試，所以多了取消的按鈕；
/// 否則連不上就顯示原因。這裡只負責顯示，連線本身由
/// [BotConnector.keepConnected] 推動。
class ConnectingServer extends StatelessWidget {
  final BotConnector connector;

  const ConnectingServer({Key? key, required this.connector}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 關閉對話框前要先停止連線，否則之後連上時畫面又會被換成狀態頁
    void close() {
      connector.cancel();
      Navigator.pop(context);
    }

    final loginButton = TextButton(
        onPressed: () {
          close();
          showDialog(
              barrierDismissible: false,
              context: context,
              builder: (context) => const MicrosoftOauthDialog());
        },
        child: const Text('重新登入'));

    return AnimatedBuilder(
        animation: connector,
        builder: (context, child) {
          final failed = connector.failures > 0;

          // 不重試時，失敗就停下來顯示原因
          if (failed && !connector.reconnect) {
            return AlertDialog(
              title: const Text('錯誤'),
              content: Text('無法連線到廢土伺服器\n\n${connector.lastError}'),
              actions: [
                if (connector.needsLogin) loginButton,
                const ConfirmButton()
              ],
            );
          }

          final nextAttemptAt = connector.nextAttemptAt;
          final String title;
          if (nextAttemptAt != null) {
            title = '與伺服器斷線，等待重新連線中...';
          } else if (connector.checkingCredentials) {
            title = '正在檢查帳號憑證是否有效...';
          } else if (connector.reconnect) {
            title = '由於與伺服器斷線，正在重新連線中...';
          } else {
            title = '連線廢土伺服器中...';
          }

          return AlertDialog(
            title: Text(title),
            content: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (failed)
                    Text([
                      '已連續失敗 ${connector.failures} 次',
                      '上次失敗原因：${connector.lastError}',
                      if (nextAttemptAt != null)
                        // DateTime.toString() 的格式是 yyyy-MM-dd HH:mm:ss.mmmuuu，只取時分秒
                        '下次重連時間：${nextAttemptAt.toString().substring(11, 19)}'
                    ].join('\n')),
                  if (nextAttemptAt == null) ...[
                    if (failed) const SizedBox(height: 16),
                    const CircularProgressIndicator()
                  ]
                ]),
            actions: connector.reconnect
                ? [
                    if (connector.needsLogin) loginButton,
                    TextButton(onPressed: close, child: const Text('取消'))
                  ]
                : null,
          );
        });
  }
}
