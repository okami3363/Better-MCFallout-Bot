import 'dart:ffi';

import 'package:better_mcfallout_bot/src/better_mcfallout_bot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 檔名要和 core 的 `yarn pkg:macos` 產生的一致：pkg 同時打包兩種 CPU 時，
  // 會在檔名後面加上 -arm64 與 -x64
  test('macOS 上依 CPU 選用對應的 core：Apple Silicon 用 arm64，Intel 用 x64', () {
    expect(BotCore.macosCoreFileName(Abi.macosArm64),
        'better-mcfallout-bot-core-arm64');
    expect(BotCore.macosCoreFileName(Abi.macosX64),
        'better-mcfallout-bot-core-x64');
  });
}
