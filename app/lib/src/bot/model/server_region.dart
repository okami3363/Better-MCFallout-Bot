import 'package:dart_minecraft/dart_minecraft.dart' as mc;

enum ServerRegion {
  auto('mcfallout.net'),
  defaultRegion('mcfallout.net'),

  /// North America
  na('na.mcfallout.net'),

  /// Japan
  japan('jp.mcfallout.net'),

  denpa('denpa.mcfallout.net'),
  mercy('mercy.mcfallout.net');

  final String host;
  const ServerRegion(this.host);

  String getName() {
    switch (this) {
      case ServerRegion.auto:
        return '自動分配';
      case ServerRegion.defaultRegion:
        return '預設區域';
      case ServerRegion.na:
        return '北美洲';
      case ServerRegion.japan:
        return '日本';
      case ServerRegion.denpa:
        return 'Denpa';
      case ServerRegion.mercy:
        return 'Mercy';
    }
  }

  static Future<String> getBestHost() async {
    try {
      const hosts = [
        'mcfallout.net',
        'na.mcfallout.net',
        'jp.mcfallout.net',
        'mercy.mcfallout.net'
      ];

      final Map<String, int> result = {};

      for (final host in hosts) {
        try {
          // ping 的 timeout 只管連線；對方接受連線卻不回應時要靠外層的
          // timeout 才會結束，否則整個連線流程會卡在這裡。
          final packet = await mc
              .ping(host, timeout: const Duration(seconds: 1))
              .timeout(const Duration(seconds: 3));
          final ping = packet?.ping;
          if (ping != null) {
            result[host] = ping;
          }
        } catch (e) {
          // no-op
        }
      }

      final bestHost =
          result.entries.reduce((a, b) => a.value < b.value ? a : b).key;

      return bestHost;
    } catch (e) {
      return 'mcfallout.net';
    }
  }
}
