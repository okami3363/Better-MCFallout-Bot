import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:better_mcfallout_bot/src/better_mcfallout_bot.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart';

BotCore? _instance;
final Logger _logger = Logger('bot_core');

/// 啟動 core 行程的方式，測試時用來換成假的 core。
typedef CoreLauncher = Future<Process> Function(Map config);

class BotCore {
  static BotCore? get instance {
    return _instance;
  }

  final ServerRegion region;
  final int port;
  final Account account;
  int reconnectTimes;
  final Duration connectTimeout;
  final CoreLauncher? _startCore;

  late String host;
  late Process process;
  late Stream<IEvent> eventStream;
  late ConnectedEvent connectedData;
  bool connected = false;

  /// core 寫到 stderr 的內容，core 當掉時用來說明原因。
  final StringBuffer _stderr = StringBuffer();
  late Future<void> _stderrDone;

  BotCore.createBot(
      {required this.region,
      required this.port,
      required this.account,
      this.reconnectTimes = 0,
      this.connectTimeout = const Duration(seconds: 20),
      CoreLauncher? startCore})
      : _startCore = startCore {
    _instance = this;
  }

  /// 連線到伺服器。成功回傳 null，失敗回傳原因。
  Future<String?> connect() async {
    if (connected) return null;

    // Not the first time to reconnect
    if (reconnectTimes > 1) {
      await Future.delayed(const Duration(seconds: 15));
    }

    final error = await _connect();
    if (error != null) return error;

    // Successful to reconnect, so reset reconnect times
    reconnectTimes > 0 ? reconnectTimes-- : reconnectTimes = 0;
    return null;
  }

  void disconnect() {
    if (!connected) return;
    _executeAction(const BotAction(action: BotActionType.disconnect));
    process.kill(ProcessSignal.sigkill);
    connected = false;
    _logger.info('The bot was manually disconnected');
  }

  void whenEvent<E extends IEvent>(void Function(E event) callback) {
    late final StreamSubscription subscription;

    subscription = eventStream.listen((event) async {
      if (event is E) {
        callback(event);
      }

      if (event is DisconnectedEvent) {
        await subscription.cancel();
      }
    });
  }

  Stream<E> whenEventStream<E extends IEvent>() {
    final StreamController<E> controller = StreamController<E>();

    whenEvent<E>((event) {
      controller.add(event);
    });

    return controller.stream.asBroadcastStream();
  }

  void runCommand(String command) {
    if (!connected) return;
    _executeAction(BotAction(
        action: BotActionType.command, argument: {'command': command}));
  }

  void updateConfig() {
    if (!connected) return;
    _executeAction(BotAction(
        action: BotActionType.updateConfig,
        argument: {'config': _getConfig()}));
  }

  void attack(BotActionMethod method) {
    if (!connected) return;
    _executeAction(BotAction(action: BotActionType.attack, method: method));
  }

  /// 啟動 core 並等它連上伺服器。成功回傳 null，失敗回傳原因。
  Future<String?> _connect() async {
    if (region == ServerRegion.auto) {
      host = await ServerRegion.getBestHost();
    } else {
      host = region.host;
    }

    try {
      process = await (_startCore ?? _startRealCore)(_getConfig());
    } on ProcessException catch (e) {
      return '無法啟動 core：$e';
    }
    eventStream = _listen();
    _logging();

    final result = Completer<String?>();
    void finish(String? error) {
      if (!result.isCompleted) result.complete(error);
    }

    whenEvent<ConnectedEvent>((event) {
      connected = true;
      connectedData = event;
      _logger.info('Connected to $host:$port');
      finish(null);
    });

    // core 回報的最後一個錯誤，例如被伺服器踢出的原因
    String? lastError;
    whenEvent<ErrorLogEvent>((event) => lastError = event.message);

    // 還沒連上就斷線（例如被踢出）時 core 行程不會自己結束，但也不必再等
    whenEvent<DisconnectedEvent>((event) => finish(lastError ?? event.reason));

    // core 在連上之前就結束（例如當掉）時不必再等，直接回報它留下的錯誤
    process.exitCode.then((code) async {
      await _stderrDone;
      finish(_lastErrorLine(_stderr.toString()) ?? 'core 意外結束（結束代碼 $code）');
    });

    final error = await result.future
        .timeout(connectTimeout, onTimeout: () => lastError ?? '連線逾時');

    // 連線失敗就結束 core，避免它留在背景、之後自己連上伺服器
    if (error != null) process.kill();
    return error;
  }

  /// 從 core 的 stderr 找出最後一行錯誤（例如 `TypeError: ...`），
  /// 略過堆疊與無關的警告。
  static String? _lastErrorLine(String stderr) {
    final errors =
        RegExp(r'^\w*Error\b.*$', multiLine: true).allMatches(stderr);
    return errors.isEmpty ? null : errors.last.group(0)!.trim();
  }

  Future<Process> _startRealCore(Map config) async {
    if (kDebugMode) {
      /// Run the core in debug mode (without compiling to the executable)
      final workingDirectory = join(dirname(Directory.current.path), 'core');
      await Process.run('yarn', ['build'],
          workingDirectory: workingDirectory);
      return Process.start('node', ['dist/index.js', json.encode(config)],
          workingDirectory: workingDirectory);
    } else {
      return Process.start(_getExecutablePath(), [json.encode(config)]);
    }
  }

  Stream<IEvent> _listen() {
    late final StreamController<IEvent> controller;

    final stdout = process.stdout.listen((data) {
      final text = utf8.decode(data);
      try {
        final List<String> jsonList = LineSplitter.split(text).toList();

        for (final String json in jsonList) {
          if (json.isEmpty) return;
          final RawEvent event = RawEvent.fromJson(json);

          final handledEvent = _eventHandler(event);
          if (handledEvent != null) {
            controller.add(handledEvent);
          }
        }
      } catch (e) {
        if (text.contains('ECONNRESET')) {
          controller.add(DisconnectedEvent.create(text));
          return;
        }

        _logger.warning('Failed to parse event: $e ($text)');
      }
    });

    controller = StreamController<IEvent>(
      onCancel: () => stdout.cancel(),
      onResume: () => stdout.resume(),
      onPause: () => stdout.pause(),
    );

    _stderrDone = process.stderr.listen((data) {
      final String error = utf8.decode(data);
      _stderr.write(error);
      _logger.severe(error, null, StackTrace.current);
    }).asFuture();

    return controller.stream.asBroadcastStream();
  }

  IEvent? _eventHandler(RawEvent event) {
    switch (event.event) {
      case EventType.connected:
        connected = true;
        return ConnectedEvent(event);
      case EventType.disconnected:
        connected = false;
        return DisconnectedEvent(event);
      case EventType.info:
        return InfoLogEvent(event);
      case EventType.warn:
        return WarnLogEvent(event);
      case EventType.error:
        return ErrorLogEvent(event);
      case EventType.gameMessage:
        return GameMessageEvent(event);
      case EventType.status:
        return StatusEvent(event);
      default:
        _logger.warning('Unknown event: ${event.event}');
        return null;
    }
  }

  void _executeAction(BotAction action) {
    process.stdin.writeln(json.encode(action.toMap()));
  }

  void _logging() {
    whenEvent<InfoLogEvent>((event) {
      _logger.info(event.message);
    });

    whenEvent<WarnLogEvent>((event) {
      _logger.warning(event.message);
    });

    whenEvent<ErrorLogEvent>((event) {
      _logger.severe(event.message);
    });
  }

  Map _getConfig() => {
        'host': host,
        'port': port,
        'username': account.username,
        'token': account.minecraftToken,
        'uuid': account.uuid,
        'auto_eat': appConfig.autoEat,
        'auto_throw': appConfig.autoThrow,
        'warp_publicity': appConfig.warpPublicity,
        'trade_publicity': appConfig.tradePublicity,
        'allow_tpa': appConfig.allowTpa,
        'attack_interval_ticks': appConfig.attackIntervalTicks,
      };

  String _getExecutablePath() {
    final String file;
    if (Platform.isWindows) {
      file = 'better-mcfallout-bot-core.exe';
    } else {
      file = 'better-mcfallout-bot-core';
    }

    final basePath = join('flutter_assets', 'assets', file);

    if (Platform.isWindows || Platform.isLinux) {
      return join(dirname(Platform.resolvedExecutable), 'data', basePath);
    } else if (Platform.isMacOS) {
      return join(dirname(dirname(Platform.resolvedExecutable)), 'Frameworks',
          'App.framework', 'Versions', 'A', 'Resources', basePath);
    } else {
      throw Exception(
          'Failed to find core executable, unsupported platform: ${Platform.operatingSystem}');
    }
  }
}
