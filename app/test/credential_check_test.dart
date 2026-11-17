import 'dart:convert';

import 'package:better_mcfallout_bot/src/better_mcfallout_bot.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:oauth2/oauth2.dart';

import 'support.dart';

/// Minecraft token 是舊的，但 Microsoft 的 refresh token 還能用的帳號。
final staleAccount = Account(
    uuid: 'uuid',
    username: 'tester',
    minecraftToken: 'old-token',
    credentials: Credentials('old-access-token',
        refreshToken: 'refresh-token',
        tokenEndpoint: Uri.parse('https://login.live.com/oauth20_token.srf')));

/// 假的 Microsoft／Xbox Live／Minecraft 服務：記下收到的請求，依網址回應。
class FakeServices {
  /// 用舊的 Minecraft token 檢查 profile 時回應的狀態碼。
  int profileStatus;

  /// Microsoft 是否拒絕更新憑證（例如 refresh token 也過期了）。
  final bool refreshRejected;

  final List<Request> requests = [];

  FakeServices({required this.profileStatus, this.refreshRejected = false});

  /// 依序被呼叫過的 API。
  List<String> get contacted => requests.map(_endpoint).toList();

  /// 收到過 Minecraft token（Authorization 標頭）的 API。
  Set<String> get sentTokenTo => {
        for (final request in requests)
          if (request.headers.containsKey('Authorization')) _endpoint(request)
      };

  Future<Response> respond(Request request) async {
    requests.add(request);

    switch (_endpoint(request)) {
      case 'api.minecraftservices.com/minecraft/profile':
        // 更新後拿到的新 token 一定有效
        return request.headers['Authorization'] == 'Bearer new-token'
            ? _json({'id': 'uuid', 'name': 'tester'})
            : Response('', profileStatus);
      case 'login.live.com/oauth20_token.srf':
        if (refreshRejected) {
          return _json({'error': 'invalid_grant'}, status: 400);
        }
        return _json({
          'access_token': 'new-access-token',
          'token_type': 'bearer',
          'expires_in': 3600,
          'refresh_token': 'new-refresh-token'
        });
      case 'user.auth.xboxlive.com/user/authenticate':
      case 'xsts.auth.xboxlive.com/xsts/authorize':
        return _json({
          'Token': 'xbox-token',
          'DisplayClaims': {
            'xui': [
              {'uhs': 'user-hash'}
            ]
          }
        });
      case 'api.minecraftservices.com/launcher/login':
        return _json({'access_token': 'new-token'});
      case 'api.minecraftservices.com/entitlements/license':
        return _json({
          'items': [
            {'name': 'product_minecraft', 'source': 'PURCHASE'},
            {'name': 'game_minecraft', 'source': 'PURCHASE'}
          ],
          'signature': 'signature',
          'keyId': '1',
          'requestId': 'request'
        });
      default:
        // 沒有預期會收到的請求：回 500，測試可以從 [contacted] 看出是哪一個
        return Response('unexpected request', 500);
    }
  }

  static String _endpoint(Request request) =>
      '${request.url.host}${request.url.path}';

  static Response _json(Map<String, dynamic> body, {int status = 200}) =>
      Response(jsonEncode(body), status,
          headers: {'content-type': 'application/json'});
}

/// 用假的服務檢查 [staleAccount] 的憑證。
Future<bool> validateWith(FakeServices services) => runWithClient(
    () => MicrosoftOauthHandler.validate(staleAccount),
    () => MockClient(services.respond));

void main() {
  setUpAll(initConfig);
  // 更新成功時會把新的憑證存起來
  tearDown(() => accountStorage.remove(staleAccount.uuid));

  test('Minecraft token 還有效時，不做其他事', () async {
    final services = FakeServices(profileStatus: 200);

    expect(await validateWith(services), isTrue);
    expect(services.contacted, ['api.minecraftservices.com/minecraft/profile']);
  });

  test('Minecraft token 失效（401）時更新憑證，並把新的憑證存起來', () async {
    final services = FakeServices(profileStatus: 401);

    expect(await validateWith(services), isTrue);
    expect(accountStorage.get(staleAccount.uuid)?.minecraftToken, 'new-token');
  });

  test('Minecraft token 失效而且更新也失敗時，回報需要重新登入', () async {
    final services = FakeServices(profileStatus: 401, refreshRejected: true);

    expect(await validateWith(services), isFalse);
    // 確實試過更新，而且在被拒之後就停下來
    expect(services.contacted, [
      'api.minecraftservices.com/minecraft/profile',
      'login.live.com/oauth20_token.srf'
    ]);
  });

  test('更新憑證時，Minecraft token 只送給需要它的 Minecraft API', () async {
    final services = FakeServices(profileStatus: 401);

    await validateWith(services);

    // Xbox Live 的登入與 Minecraft 的登入都不該收到
    expect(services.sentTokenTo, {
      'api.minecraftservices.com/minecraft/profile',
      'api.minecraftservices.com/entitlements/license'
    });
  });

  for (final status in [429, 500, 503]) {
    test('profile 檢查暫時失敗時（$status）不更新憑證，並回報狀態碼', () async {
      final services = FakeServices(profileStatus: status);

      await expectLater(validateWith(services), throwsA('伺服器回應 $status'));
      expect(
          services.contacted, ['api.minecraftservices.com/minecraft/profile']);
    });
  }

  test('檢查被暫時拒絕時，重連隔 30 秒再試，而且不提示重新登入', () async {
    final services = FakeServices(profileStatus: 429);
    final shown = <List>[];
    late final BotConnector connector;
    connector = BotConnector(
        account: staleAccount,
        reconnect: true,
        createBot: reachable,
        wait: (duration) async {
          shown.add([duration, connector.lastError, connector.needsLogin]);
          // 等到下次重試時，服務已經恢復
          services.profileStatus = 200;
        });

    final bot = await runWithClient(
        connector.connect, () => MockClient(services.respond));
    addTearDown(() => bot?.disconnect());

    expect(bot?.connected, isTrue);
    expect(shown, [
      [const Duration(seconds: 30), '無法檢查帳號憑證：伺服器回應 429', false]
    ]);
    // 假的 core 用 sh 實作，Windows 上無法執行
  }, testOn: 'mac-os || linux');

  test('Minecraft token 失效時更新憑證，再用新的 token 連線', () async {
    final services = FakeServices(profileStatus: 401);
    final used = <String>[];
    final connector = BotConnector(
        account: staleAccount,
        createBot: (account) {
          used.add(account.minecraftToken);
          return reachable(account);
        });

    final bot = await runWithClient(
        connector.connect, () => MockClient(services.respond));
    addTearDown(() => bot?.disconnect());

    expect(bot?.connected, isTrue);
    expect(used, ['new-token']);
    // 假的 core 用 sh 實作，Windows 上無法執行
  }, testOn: 'mac-os || linux');
}
