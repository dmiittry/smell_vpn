import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_singbox_client/flutter_singbox_client.dart' as sb;

import '../domain/log_event.dart';
import '../domain/routing.dart';
import '../domain/profile_catalog.dart';
import 'core_control.dart';

enum TunnelState { disconnected, connecting, running, disconnecting, failed }

class EngineEvent {
  const EngineEvent({
    this.state,
    this.level = EventLevel.info,
    this.message = '',
    this.downloadBps,
    this.uploadBps,
    this.selectedTag,
    this.checks,
    this.source = 'Ядро',
    this.time,
    this.id,
    this.userInitiated = false,
  });
  final TunnelState? state;
  final EventLevel level;
  final String message;
  final int? downloadBps, uploadBps;
  final String? selectedTag;
  final List<EndpointCheck>? checks;
  final String source;
  final DateTime? time;
  final String? id;
  final bool userInitiated;
}

abstract class VpnEngine {
  Stream<EngineEvent> get events;
  Future<void> initialize();
  Future<void> connect(
    String config,
    RoutingMode mode,
    List<String> packages, {
    Map<String, String> profileNames = const {},
  });
  Future<void> selectEndpoint(String tag);
  Future<List<EndpointCheck>> checkEndpoints(
    String config,
    List<String> tags, {
    bool requireRunning = false,
  });
  Future<void> disconnect();
  Future<List<RoutedApp>> applications();
  Future<void> dispose();
}

abstract class ControlledVpnEngine implements VpnEngine {
  StreamController<EngineEvent> get eventSink;
  bool _checkingOnly = false;
  bool _wasRunning = false;
  late final CoreControl control = CoreControl(
    onSelected: (tag) => emit(EngineEvent(selectedTag: tag)),
    onChecks: (checks) => emit(EngineEvent(checks: checks)),
  );
  void emit(EngineEvent event) {
    if (_checkingOnly || eventSink.isClosed) return;
    if (event.state == TunnelState.running) _wasRunning = true;
    if (_wasRunning &&
        (event.state == TunnelState.failed ||
            event.state == TunnelState.disconnected)) {
      control.close();
      _wasRunning = false;
    }
    eventSink.add(event);
  }

  Future<void> startCore(
    String config,
    RoutingMode mode,
    List<String> packages, {
    required bool probeOnly,
    Map<String, String> profileNames = const {},
  });
  Future<void> stopCore();
  @override
  Future<void> connect(
    String config,
    RoutingMode mode,
    List<String> packages, {
    Map<String, String> profileNames = const {},
  }) async {
    if (control.active) throw StateError('Ядро уже запущено.');
    final controlled = await control.configure(config);
    final generation = control.generation;
    try {
      await startCore(
        controlled,
        mode,
        packages,
        probeOnly: false,
        profileNames: profileNames,
      );
      await control.waitReady().timeout(const Duration(seconds: 12));
      control.startPolling();
    } catch (_) {
      if (generation == control.generation) {
        control.close();
        await stopCore();
      }
      rethrow;
    }
  }

  @override
  Future<void> selectEndpoint(String tag) => control.select(tag);
  @override
  Future<List<EndpointCheck>> checkEndpoints(
    String config,
    List<String> tags, {
    bool requireRunning = false,
  }) async {
    if (requireRunning && (!control.active || !_wasRunning)) {
      throw const FormatException(
        'Работающее ядро VPN недоступно для проверки.',
      );
    }
    if (control.active) return control.check(tags);
    _checkingOnly = true;
    try {
      final controlled = await control.configure(config);
      await startCore(controlled, RoutingMode.all, const [], probeOnly: true);
      await control.waitReady().timeout(const Duration(seconds: 12));
      return await control.check(tags);
    } finally {
      control.close();
      try {
        await stopCore();
      } finally {
        _checkingOnly = false;
      }
    }
  }

  @override
  Future<void> disconnect() async {
    control.close();
    await stopCore();
  }
}

class AndroidVpnEngine extends ControlledVpnEngine {
  final sb.SingboxClient _client = sb.SingboxClient();
  final _events = StreamController<EngineEvent>.broadcast();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  static const _apps = MethodChannel('sme11_vpn/apps');
  bool _initialized = false;
  bool _restoring = false;
  Timer? _diagnosticsTimer;
  bool _readingDiagnostics = false;
  int _stateRevision = 0;
  final Set<String> _seenDiagnostics = {};

  Future<bool> _readDiagnostics() async {
    final data = await _apps.invokeMapMethod<String, dynamic>(
      'runtimeDiagnostics',
    );
    for (final raw in (data?['events'] as List? ?? const [])) {
      final entry = Map<String, dynamic>.from(raw as Map);
      final id = entry['id'] as String;
      if (!_seenDiagnostics.add(id)) continue;
      emit(
        EngineEvent(
          source: 'Android',
          id: id,
          time: DateTime.fromMillisecondsSinceEpoch(entry['time'] as int),
          level: entry['level'] == 'error'
              ? EventLevel.error
              : entry['level'] == 'warning'
              ? EventLevel.warning
              : EventLevel.info,
          message: entry['message'] as String,
        ),
      );
    }
    return data?['userStop'] == true;
  }

  Future<void> _nativeState(sb.ServiceState state) async {
    final revision = ++_stateRevision;
    var userStop = false;
    if (state == sb.ServiceState.stopped) {
      try {
        userStop = await _readDiagnostics();
      } catch (_) {
        /* Канал может быть закрыт с Activity. */
      }
    }
    if (revision != _stateRevision || _events.isClosed) return;
    emit(
      EngineEvent(
        state: switch (state) {
          sb.ServiceState.started => TunnelState.running,
          sb.ServiceState.starting => TunnelState.connecting,
          sb.ServiceState.stopping => TunnelState.disconnecting,
          sb.ServiceState.stopped => TunnelState.disconnected,
        },
        userInitiated: userStop,
      ),
    );
    if (state == sb.ServiceState.started && !control.active) {
      await _restoreControl();
    }
  }

  @override
  StreamController<EngineEvent> get eventSink => _events;
  @override
  Stream<EngineEvent> get events => _events.stream;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    await _client.initialize();
    _subscriptions.add(
      _client.serviceStateStream.listen(
        (state) => unawaited(_nativeState(state)),
        onError: _streamError,
      ),
    );
    _subscriptions.add(
      _client.faultStream.listen((error) {
        emit(
          EngineEvent(
            state: TunnelState.failed,
            level: EventLevel.error,
            message: error,
          ),
        );
      }, onError: _streamError),
    );
    _subscriptions.add(
      _client.coreLogStream.listen((entries) {
        for (final entry in entries) {
          emit(
            EngineEvent(
              level: switch (entry.level) {
                sb.LogLevel.error ||
                sb.LogLevel.fatal ||
                sb.LogLevel.panic => EventLevel.error,
                sb.LogLevel.warn => EventLevel.warning,
                sb.LogLevel.debug || sb.LogLevel.trace => EventLevel.debug,
                sb.LogLevel.info => EventLevel.info,
              },
              message: entry.message,
            ),
          );
        }
      }, onError: _streamError),
    );
    _subscriptions.add(
      _client.trafficStatsStream.listen((stats) {
        emit(
          EngineEvent(
            downloadBps: stats.downlinkBps,
            uploadBps: stats.uplinkBps,
          ),
        );
      }, onError: _streamError),
    );
    _initialized = true;
    try {
      await _readDiagnostics();
    } catch (_) {
      emit(
        const EngineEvent(
          level: EventLevel.warning,
          source: 'Android',
          message: 'Служебный журнал Android недоступен. Причина остановки может отсутствовать.',
        ),
      );
    }
    _diagnosticsTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_readingDiagnostics) return;
      _readingDiagnostics = true;
      try {
        await _readDiagnostics();
      } catch (_) {
        /* Повторим чтение при следующем опросе. */
      } finally {
        _readingDiagnostics = false;
      }
    });
    final state = await _client.getServiceState();
    if (state == sb.ServiceState.started) {
      await _restoreControl();
      emit(const EngineEvent(state: TunnelState.running));
    }
    emit(
      EngineEvent(
        message: 'Ядро sing-box ${await _client.getCoreVersion()} готово.',
      ),
    );
  }

  Future<void> _restoreControl() async {
    if (_restoring || control.active) return;
    _restoring = true;
    try {
      final connection = await _apps.invokeMapMethod<String, dynamic>(
        'currentControl',
      );
      if (connection != null) {
        control.restore(connection);
        await control.waitReady().timeout(const Duration(seconds: 12));
        control.startPolling();
      }
    } catch (_) {
      control.close();
      emit(
        const EngineEvent(
          level: EventLevel.warning,
          message: 'Не удалось восстановить управление сервером. Отключите и заново включите VPN.',
        ),
      );
    } finally {
      _restoring = false;
    }
  }

  void _streamError(Object error) => emit(
    EngineEvent(level: EventLevel.error, message: 'Ошибка канала ядра: $error'),
  );

  @override
  Future<void> startCore(
    String config,
    RoutingMode mode,
    List<String> packages, {
    required bool probeOnly,
    Map<String, String> profileNames = const {},
  }) async {
    final generation = control.generation;
    await initialize();
    if (await _client.getServiceState() != sb.ServiceState.stopped) {
      throw StateError('Сервис ядра уже занят. Сначала отключите VPN.');
    }
    if (!probeOnly && mode == RoutingMode.selected) {
      final missing =
          await _apps.invokeListMethod<String>('validateApps', packages) ?? [];
      if (packages.isEmpty || missing.isNotEmpty) {
        throw const FormatException(
          'Некоторые выбранные приложения удалены. Обновите список приложений.',
        );
      }
    }
    await _client.checkConfig(config);
    if (!probeOnly && !await _client.requestVPNPermission()) {
      throw const FormatException('Разрешение на VPN отклонено.');
    }
    if (!probeOnly) {
      final granted = await _apps.invokeMethod<bool>('requestNotifications');
      if (granted != true) {
        emit(
          const EngineEvent(
            level: EventLevel.warning,
            message: 'Уведомления отключены. Разрешите их в настройках Android для показа скорости.',
          ),
        );
      }
    }
    if (!control.active || generation != control.generation) {
      throw StateError('Запуск VPN отменён.');
    }
    await _client.connect(
      sb.SessionOptions(
        config: config,
        networkMode: probeOnly ? sb.NetworkMode.proxy : sb.NetworkMode.vpn,
        perAppProxy: !probeOnly && mode == RoutingMode.selected
            ? sb.PerAppProxyOptions(
                mode: sb.PerAppProxyMode.include,
                // Непустой системный allowlist даже при удалении выбранных пакетов.
                packages: {...packages, 'com.sme11.sme11_vpn'}.toList(),
              )
            : null,
        notification: sb.NotificationConfig(
          title: probeOnly ? 'Sme11_VPN · Проверка серверов' : 'Sme11_VPN',
          channelName: 'Sme11_VPN',
          profileNames: profileNames,
          showTrafficStats: !probeOnly,
          showStopButton: true,
          stopButtonLabel: 'Отключить',
        ),
      ),
    );
  }

  @override
  Future<void> stopCore() => _client.disconnect();
  @override
  Future<List<RoutedApp>> applications() async {
    final values = await _apps.invokeListMethod<dynamic>('listApps') ?? [];
    return values
        .map((v) => RoutedApp.fromJson(Map<String, dynamic>.from(v as Map)))
        .toList();
  }

  @override
  Future<void> dispose() async {
    _diagnosticsTimer?.cancel();
    _stateRevision++;
    control.close();
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    await _client.dispose();
    await _events.close();
  }
}

class WindowsVpnEngine extends ControlledVpnEngine {
  WindowsVpnEngine({String? executable})
    : executable =
          executable ??
          '${File(Platform.resolvedExecutable).parent.path}\\core\\sing-box.exe';
  final String executable;
  final _events = StreamController<EngineEvent>.broadcast();
  Process? _process;
  final List<StreamSubscription<String>> _subscriptions = [];
  Completer<void>? _ready;
  bool _stopping = false;
  static const _lifecycle = MethodChannel('sme11_vpn/lifecycle');
  @override
  StreamController<EngineEvent> get eventSink => _events;
  @override
  Stream<EngineEvent> get events => _events.stream;
  @override
  Future<void> initialize() async {
    if (!await File(executable).exists()) {
      throw const FileSystemException(
        'Не найден core/sing-box.exe. Выполните scripts/prepare_windows.ps1 перед сборкой Windows.',
      );
    }
    final version = await Process.run(executable, ['version']);
    if (version.exitCode != 0) {
      throw const FormatException('Не удалось запустить ядро sing-box.');
    }
    emit(EngineEvent(message: (version.stdout as String).split('\n').first));
  }

  @override
  Future<void> startCore(
    String config,
    RoutingMode mode,
    List<String> packages, {
    required bool probeOnly,
    Map<String, String> profileNames = const {},
  }) async {
    if (_process != null) throw StateError('Ядро уже запущено.');
    final generation = control.generation;
    await initialize();
    // Секреты передаются через stdin, не попадают в файлы и аргументы процесса.
    final check = await Process.start(executable, ['check', '-c', 'stdin']);
    final output = check.stdout.transform(utf8.decoder).join();
    final error = check.stderr.transform(utf8.decoder).join();
    try {
      check.stdin.write(config);
      await check.stdin.close();
      if (await check.exitCode.timeout(const Duration(seconds: 15)) != 0) {
        throw FormatException(
          'Конфигурация отклонена ядром: ${await error} ${await output}',
        );
      }
    } finally {
      check.kill();
    }
    if (!control.active || generation != control.generation) {
      throw StateError('Запуск VPN отменён.');
    }
    _stopping = false;
    _ready = Completer<void>();
    final ready = _ready!.future;
    // Обработчик нужен сразу: процесс может завершиться до ответа native-канала.
    unawaited(
      ready.then<void>((_) {}, onError: (Object error, StackTrace stack) {}),
    );
    final process = await Process.start(executable, [
      'run',
      '-c',
      'stdin',
      '--disable-color',
    ]);
    if (!control.active || generation != control.generation) {
      process.kill();
      await process.exitCode;
      throw StateError('Запуск VPN отменён.');
    }
    _process = process;
    unawaited(
      process.exitCode.then((code) {
        if (_process != process) return;
        _process = null;
        if (!(_ready?.isCompleted ?? true)) {
          _ready!.completeError(StateError('Ядро остановлено, код $code.'));
        }
        emit(
          EngineEvent(
            state: _stopping ? TunnelState.disconnected : TunnelState.failed,
            level: _stopping ? EventLevel.info : EventLevel.error,
            message: _stopping ? '' : 'Неожиданная остановка ядра, код $code.',
          ),
        );
      }),
    );
    // Native Job Object завершает ядро при закрытии или аварии Flutter-процесса.
    try {
      final attached = await _lifecycle.invokeMethod<bool>(
        'attachProcess',
        process.pid,
      );
      if (attached != true) {
        throw StateError('Не удалось привязать жизненный цикл ядра.');
      }
      for (final stream in [process.stdout, process.stderr]) {
        _subscriptions.add(
          stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen(_line),
        );
      }
      process.stdin.write(config);
      await process.stdin.close();
      await ready.timeout(const Duration(seconds: 25));
    } catch (_) {
      await disconnect();
      rethrow;
    }
  }

  void _line(String line) {
    final level = coreLogLevel(line, fallback: EventLevel.info);
    emit(EngineEvent(level: level, message: line));
    if (line.contains('sing-box started')) {
      if (!(_ready?.isCompleted ?? true)) _ready!.complete();
      emit(const EngineEvent(state: TunnelState.running));
    }
  }

  @override
  Future<void> stopCore() async {
    _stopping = true;
    final process = _process;
    if (process != null) {
      process.kill();
      await process.exitCode.timeout(const Duration(seconds: 8));
      _process = null;
    }
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    emit(const EngineEvent(state: TunnelState.disconnected));
  }

  @override
  Future<List<RoutedApp>> applications() async {
    // Только чтение запущенных программ. Выбор любого установленного .exe доступен отдельно.
    final result = await Process.run(
      'powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r"[Console]::OutputEncoding = [Text.Encoding]::UTF8; @(Get-Process | Where-Object { $_.Path -and $_.Path.EndsWith('.exe') } | Select-Object -Unique @{Name='id';Expression={$_.Path}}, @{Name='name';Expression={$_.ProcessName}}) | ConvertTo-Json -Compress",
      ],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) {
      throw const FormatException(
        'Не удалось получить список процессов. Добавьте программу через выбор EXE.',
      );
    }
    final raw = (result.stdout as String).trim();
    if (raw.isEmpty) return [];
    final data = jsonDecode(raw);
    final list = data is List ? data : [data];
    return list
        .map((v) => RoutedApp.fromJson(Map<String, dynamic>.from(v as Map)))
        .where(
          (app) =>
              !app.id.toLowerCase().endsWith('sing-box.exe') &&
              !app.id.toLowerCase().endsWith('sme11_vpn.exe'),
        )
        .toList();
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    await _events.close();
  }
}
