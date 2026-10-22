import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'domain/config_builder.dart';
import 'domain/profile.dart';
import 'domain/profile_catalog.dart';
import 'domain/routing.dart';
import 'domain/log_event.dart';
import 'services/storage.dart';
import 'services/vpn_engine.dart';

class AppController extends ChangeNotifier {
  AppController({required this.engine, required this.storage});
  final VpnEngine engine;
  final AppStorage storage;
  ProfileCatalog catalog = const ProfileCatalog();
  String? activeTag;
  final Map<String, EndpointCheck> health = {};
  bool checking = false, changingServer = false, catalogReadable = true;
  VpnProfile? get profile => catalog.selected?.profile;
  SavedProfile? get activeEndpoint =>
      catalog.profiles.where((e) => e.tag == activeTag).firstOrNull;
  String get currentProfileName => state == TunnelState.running
      ? activeEndpoint?.profile.name ?? 'Выбор сервера…'
      : profile?.name ?? 'Профиль не добавлен';
  RoutingMode mode = RoutingMode.selected;
  bool diagnostic = false, initialized = false, loadingApps = false;
  TunnelState state = TunnelState.disconnected;
  List<RoutedApp> selected = [], available = [];
  final List<LogEvent> logs = [];
  String? lastError;
  int downloadBps = 0, uploadBps = 0;
  DateTime? connectedAt;
  EndpointCheck? connectionCheck;
  bool verifyingConnection = false;
  bool _probeReady = false;
  int _probeRevision = 0;
  bool get connectionVerified =>
      state == TunnelState.running &&
      connectionCheck?.tag == activeTag &&
      connectionCheck?.available == true &&
      connectionCheck!.fresh;
  StreamSubscription<EngineEvent>? _subscription;
  Timer? _deadline, _logSave, _notifyTimer;
  Future<void> _writes = Future.value();
  bool _userStop = false;
  bool _savingLogs = false, _logsDirty = false, _disposed = false;
  bool get busy =>
      checking ||
      changingServer ||
      state == TunnelState.connecting ||
      state == TunnelState.disconnecting;
  bool get canEdit => catalogReadable && !busy && state != TunnelState.running;

  Future<void> initialize() async {
    try {
      logs.addAll(
        retainLogs(
          (await storage.loadLogs()).map((e) => e.normalizeCoreLevel()),
        ),
      );
    } catch (_) {
      addLog(
        EventLevel.warning,
        'Хранилище',
        'Предыдущий журнал недоступен. Начат новый.',
      );
    }
    try {
      catalog = await storage.loadCatalog();
    } catch (_) {
      catalogReadable = false;
      addLog(
        EventLevel.error,
        'Профиль',
        'Не удалось прочитать или перенести защищённый каталог. Старый профиль сохранён; запись новых профилей заблокирована.',
      );
    }
    try {
      final settings = await storage.loadSettings();
      mode = settings.mode;
      selected = settings.apps;
      diagnostic = settings.diagnostic;
    } catch (_) {
      addLog(
        EventLevel.warning,
        'Настройки',
        'Не удалось прочитать настройки маршрутизации.',
      );
    }
    _subscription = engine.events.listen(_event);
    try {
      await engine.initialize();
    } catch (error) {
      addLog(EventLevel.warning, 'Ядро', _safeError(error));
    }
    initialized = true;
    _probeReady = true;
    unawaited(checkConnection());
    addLog(
      EventLevel.info,
      'Приложение',
      'Sme11_VPN готов. Подключение запускается только вручную.',
    );
    notifyListeners();
  }

  String _safeError(Object error) =>
      error is FormatException ? error.message : '$error';
  void _event(EngineEvent event) {
    if (event.selectedTag != null && event.selectedTag != activeTag) {
      activeTag = event.selectedTag;
      _invalidateProbe();
      unawaited(checkConnection());
      if (activeEndpoint != null) {
        addLog(
          EventLevel.info,
          'Серверы',
          'Ядро выбрало: ${activeEndpoint!.profile.name}.',
        );
      }
    }
    if (event.checks != null) {
      for (final result in event.checks!) {
        final previous = health[result.tag];
        if (previous == null || !result.time.isBefore(previous.time)) {
          health[result.tag] = result;
        }
      }
    }
    if (event.message.isNotEmpty) {
      // Fault/state-события авторитетны; обычные строки могут приходить
      // с неверными метаданными уровня от libbox-адаптера.
      final level = event.state == null
          ? coreLogLevel(event.message, fallback: event.level)
          : event.level;
      if (level != EventLevel.debug || diagnostic) {
        addLog(
          level,
          event.source,
          event.message,
          time: event.time,
          id: event.id,
        );
      }
      if (event.state == TunnelState.failed) {
        lastError = explainFailure(event.message);
      }
    }
    if (event.downloadBps != null) {
      downloadBps = event.downloadBps!;
      uploadBps = event.uploadBps!;
    }
    if (event.state != null) {
      final previous = state;
      if (event.userInitiated && previous != TunnelState.failed) {
        _userStop = true;
        lastError = null;
      }
      if (event.state == TunnelState.disconnected &&
          previous == TunnelState.failed) {
        // Сохраняем причину ошибки после штатного освобождения ресурсов ядром.
      } else if (event.state == TunnelState.disconnected &&
          (previous == TunnelState.running ||
              previous == TunnelState.connecting ||
              previous == TunnelState.disconnecting) &&
          !_userStop) {
        state = TunnelState.failed;
        lastError ??= 'VPN-сервис остановлен. Причина не установлена; проверьте события Android в журнале.';
        addLog(EventLevel.error, 'Подключение', lastError!);
      } else {
        state = event.state!;
      }
      if (state == TunnelState.running && previous != TunnelState.running) {
        _deadline?.cancel();
        connectedAt = DateTime.now();
        lastError = null;
        _invalidateProbe();
        unawaited(checkConnection());
        addLog(
          EventLevel.success,
          'Подключение',
          'Туннель запущен. ${mode == RoutingMode.all ? 'Все приложения' : '${selected.length} приложений'} через VPN.',
        );
      }
      if (state == TunnelState.disconnected || state == TunnelState.failed) {
        _probeReady = false;
        _invalidateProbe();
        _deadline?.cancel();
        connectedAt = null;
        downloadBps = 0;
        uploadBps = 0;
        activeTag = null;
      }
    }
    _scheduleNotify();
  }

  void _invalidateProbe() {
    _probeRevision++;
    connectionCheck = null;
    verifyingConnection = false;
  }

  /// Проверяем текущий сервер через уже запущенное ядро. Результат относится
  /// только к этой сессии и этому серверу; старые пробы не меняют статус.
  Future<void> checkConnection() async {
    if (_disposed ||
        !_probeReady ||
        verifyingConnection ||
        checking ||
        state != TunnelState.running ||
        activeEndpoint == null) {
      return;
    }
    final tag = activeTag!;
    final revision = _probeRevision;
    verifyingConnection = true;
    _scheduleNotify();
    EndpointCheck result;
    try {
      final config = ConfigBuilder.catalog(
        catalog,
        windows: Platform.isWindows,
        mode: mode,
        applications: selected.map((e) => e.id).toList(),
      );
      final results = await engine.checkEndpoints(jsonEncode(config), [
        tag,
      ], requireRunning: true);
      result = results.firstWhere((e) => e.tag == tag);
      if (result.error != null) {
        result = EndpointCheck(
          tag: tag,
          time: result.time,
          error: redact(result.error!, _secrets),
        );
      }
    } catch (_) {
      result = EndpointCheck(
        tag: tag,
        time: DateTime.now(),
        error:
            'Не удалось проверить соединение. Проверьте сеть, сервер и логи.',
      );
    }
    if (_disposed ||
        revision != _probeRevision ||
        state != TunnelState.running ||
        activeTag != tag) {
      return;
    }
    verifyingConnection = false;
    connectionCheck = result;
    health[tag] = result;
    addLog(
      result.available ? EventLevel.success : EventLevel.error,
      'Проверка',
      result.available
          ? 'Соединение через сервер подтверждено: ${result.delayMs} мс (HTTPS).'
          : result.error ?? 'HTTPS-проверка не пройдена.',
    );
    notifyListeners();
  }

  Iterable<String> get _secrets => catalog.profiles.expand(
    (e) => [
      e.profile.uuid,
      e.profile.publicKey,
      e.profile.shortId,
      e.profile.host,
      e.profile.serverName,
    ],
  );
  void addLog(
    EventLevel level,
    String source,
    String message, {
    DateTime? time,
    String? id,
  }) {
    if (id != null && logs.any((e) => e.id == id)) return;
    final safeMessage = redact(message, _secrets);
    final now = time ?? DateTime.now();
    if (source == 'Ядро' &&
        (level == EventLevel.info || level == EventLevel.debug) &&
        logs.isNotEmpty &&
        logs.first.message == safeMessage &&
        logs.first.source == source &&
        logs.first.level == level &&
        now.difference(logs.first.time).inMilliseconds.abs() < 100) {
      return;
    }
    final event = LogEvent(
      time: now,
      level: level,
      source: source,
      message: safeMessage,
      id: id,
    );
    logs.insert(0, event);
    if (time != null) logs.sort((a, b) => b.time.compareTo(a.time));
    final retained = retainLogs(logs);
    logs
      ..clear()
      ..addAll(retained);
    if (level == EventLevel.error ||
        level == EventLevel.warning ||
        source == 'Подключение') {
      _logSave?.cancel();
      _logSave = null;
      _persistLogs();
    } else {
      _logSave ??= Timer(const Duration(milliseconds: 600), () {
        _logSave = null;
        _persistLogs();
      });
    }
    _scheduleNotify();
  }

  void _persistLogs() {
    _logsDirty = true;
    if (_savingLogs) return;
    _savingLogs = true;
    _writes = () async {
      try {
        while (_logsDirty) {
          _logsDirty = false;
          await storage.saveLogs(List<LogEvent>.of(logs));
        }
      } catch (_) {
        lastError ??= 'Не удалось сохранить журнал на устройстве.';
        _scheduleNotify();
      } finally {
        _savingLogs = false;
      }
    }();
  }

  Future<void> flushLogs() {
    _logSave?.cancel();
    _logSave = null;
    _persistLogs();
    return _writes;
  }

  void _scheduleNotify() {
    if (_disposed) return;
    _notifyTimer ??= Timer(const Duration(milliseconds: 100), () {
      _notifyTimer = null;
      notifyListeners();
    });
  }

  Future<void> saveProfile(VpnProfile value, {String? id}) async {
    if (!canEdit) throw StateError('Сначала отключите VPN.');
    value.validate();
    if (id != null && !catalog.profiles.any((e) => e.id == id)) {
      throw const FormatException('Профиль не найден.');
    }
    final entry = id == null
        ? SavedProfile.create(value)
        : SavedProfile(id: id, profile: value);
    final entries = id == null
        ? [...catalog.profiles, entry]
        : catalog.profiles.map((e) => e.id == id ? entry : e).toList();
    final next = ProfileCatalog(
      profiles: entries,
      selectedId: catalog.selectedId ?? entry.id,
      automatic: catalog.automatic,
    );
    await storage.saveCatalog(next);
    catalog = next;
    health.remove(entry.tag);
    addLog(
      EventLevel.success,
      'Профиль',
      'Профиль VLESS/Reality сохранён в защищённом хранилище.',
    );
    notifyListeners();
  }

  Future<void> chooseServer({String? id, required bool automatic}) async {
    if (busy || !catalogReadable) {
      throw StateError('Дождитесь завершения текущей операции.');
    }
    final previous = catalog;
    final next = ProfileCatalog(
      profiles: catalog.profiles,
      selectedId: id ?? catalog.selectedId,
      automatic: automatic,
    );
    next.validate();
    if (next.selected == null) throw const FormatException('Добавьте сервер.');
    changingServer = true;
    notifyListeners();
    try {
      if (state == TunnelState.running) {
        await engine.selectEndpoint(automatic ? 'auto' : next.selected!.tag);
      }
      await storage.saveCatalog(next);
      catalog = next;
      addLog(
        EventLevel.success,
        'Серверы',
        automatic
            ? 'Автоматический выбор по задержке включён.'
            : 'Ручной выбор: ${next.selected!.profile.name}.',
      );
    } catch (error) {
      if (state == TunnelState.running && previous.selected != null) {
        try {
          await engine.selectEndpoint(
            previous.automatic ? 'auto' : previous.selected!.tag,
          );
        } catch (_) {
          addLog(
            EventLevel.warning,
            'Серверы',
            'Не удалось восстановить предыдущий выбор ядра. Проверьте активный сервер.',
          );
        }
      }
      addLog(EventLevel.error, 'Серверы', _safeError(error));
      rethrow;
    } finally {
      changingServer = false;
      notifyListeners();
    }
  }

  Future<void> checkServers() async {
    if (busy || !catalogReadable || catalog.selected == null) return;
    checking = true;
    notifyListeners();
    addLog(
      EventLevel.info,
      'Серверы',
      'HTTPS-проверка профилей через VLESS/Reality…',
    );
    try {
      final config = ConfigBuilder.catalog(
        catalog,
        windows: Platform.isWindows,
        mode: mode,
        applications: selected.map((e) => e.id).toList(),
        probeOnly: state != TunnelState.running,
      );
      final results = await engine.checkEndpoints(
        jsonEncode(config),
        catalog.profiles.map((e) => e.tag).toList(),
      );
      for (final result in results) {
        health[result.tag] = result;
        final entry = catalog.profiles
            .where((e) => e.tag == result.tag)
            .firstOrNull;
        addLog(
          result.available ? EventLevel.success : EventLevel.warning,
          'Серверы',
          '${entry?.profile.name ?? 'Сервер'}: ${result.available ? '${result.delayMs} мс' : result.error}',
        );
      }
    } catch (error) {
      addLog(EventLevel.error, 'Серверы', _safeError(error));
    } finally {
      checking = false;
      notifyListeners();
    }
  }

  Future<void> configure({
    RoutingMode? routingMode,
    List<RoutedApp>? apps,
    bool? debug,
  }) async {
    if (!canEdit) throw StateError('Сначала отключите VPN.');
    final nextMode = routingMode ?? mode, nextApps = apps ?? selected;
    final nextDebug = debug ?? diagnostic;
    await storage.saveSettings(nextMode, nextApps, nextDebug);
    mode = nextMode;
    selected = nextApps;
    diagnostic = nextDebug;
    addLog(
      EventLevel.info,
      'Маршрутизация',
      mode == RoutingMode.all
          ? 'Режим: все приложения через VPN.'
          : 'Выбрано приложений: ${selected.length}. Остальные — напрямую.',
    );
    notifyListeners();
  }

  Future<void> refreshApps() async {
    if (loadingApps) return;
    loadingApps = true;
    notifyListeners();
    try {
      final apps = await engine.applications();
      final byId = {
        for (final app in [...selected, ...apps]) app.id: app,
      };
      available = byId.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } catch (error) {
      addLog(EventLevel.error, 'Приложения', _safeError(error));
      lastError = _safeError(error);
    } finally {
      loadingApps = false;
      notifyListeners();
    }
  }

  Future<void> connect() async {
    if (!initialized || !canEdit) return;
    lastError = null;
    try {
      if (profile == null) {
        throw const FormatException('Добавьте профиль VLESS/Reality.');
      }
      final config = ConfigBuilder.catalog(
        catalog,
        windows: Platform.isWindows,
        mode: mode,
        applications: selected.map((e) => e.id).toList(),
        diagnostic: diagnostic,
      );
      _userStop = false;
      _probeReady = false;
      _invalidateProbe();
      state = TunnelState.connecting;
      notifyListeners();
      addLog(
        EventLevel.info,
        'Подключение',
        'Проверка конфигурации и запуск туннеля…',
      );
      _deadline = Timer(const Duration(seconds: 35), () async {
        if (state != TunnelState.connecting) return;
        lastError = 'Время запуска VPN истекло. Проверьте разрешения и журнал.';
        state = TunnelState.failed;
        addLog(EventLevel.error, 'Подключение', lastError!);
        try {
          await engine.disconnect();
        } catch (_) {
          /* Причина запуска уже записана. */
        }
        notifyListeners();
      });
      await engine.connect(
        jsonEncode(config),
        mode,
        selected.map((e) => e.id).toList(),
        profileNames: {
          for (final entry in catalog.profiles) entry.tag: entry.profile.name,
        },
      );
      _probeReady = true;
      unawaited(checkConnection());
    } catch (error) {
      _deadline?.cancel();
      _probeReady = false;
      _invalidateProbe();
      state = TunnelState.failed;
      lastError = error is FormatException
          ? redact(error.message, _secrets)
          : explainFailure('$error');
      addLog(EventLevel.error, 'Подключение', _safeError(error));
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    if (busy) return;
    _userStop = true;
    _probeReady = false;
    _invalidateProbe();
    _deadline?.cancel();
    state = TunnelState.disconnecting;
    notifyListeners();
    try {
      await engine.disconnect();
      state = TunnelState.disconnected;
      connectedAt = null;
      downloadBps = 0;
      uploadBps = 0;
      activeTag = null;
      addLog(EventLevel.success, 'Подключение', 'VPN отключён пользователем.');
    } catch (error) {
      state = TunnelState.failed;
      lastError =
          'Не удалось остановить VPN. Проверьте системные настройки VPN.';
      addLog(EventLevel.error, 'Подключение', _safeError(error));
    }
    notifyListeners();
  }

  String exportLogs(Iterable<LogEvent> entries) =>
      entries.map((e) => e.exportLine).join('\n');
  @override
  void dispose() {
    _disposed = true;
    _invalidateProbe();
    _deadline?.cancel();
    _logSave?.cancel();
    _persistLogs();
    _notifyTimer?.cancel();
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
