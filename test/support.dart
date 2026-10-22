import 'dart:async';

import 'package:sme11_vpn/services/vpn_engine.dart';
import 'package:sme11_vpn/services/storage.dart';
import 'package:sme11_vpn/domain/profile.dart';
import 'package:sme11_vpn/domain/routing.dart';
import 'package:sme11_vpn/domain/log_event.dart';
import 'package:sme11_vpn/domain/profile_catalog.dart';

class MemoryStorage extends AppStorage {
  ProfileCatalog catalog = const ProfileCatalog();
  bool failSave = false;
  @override
  Future<ProfileCatalog> loadCatalog() async => catalog;
  @override
  Future<void> saveCatalog(ProfileCatalog value) async {
    if (failSave) throw const FormatException('Не удалось сохранить каталог.');
    catalog = value;
  }

  VpnProfile? profile;
  int logWrites = 0;
  @override
  Future<VpnProfile?> loadProfile() async => profile;
  @override
  Future<void> saveProfile(VpnProfile profile) async {
    this.profile = profile;
  }

  @override
  Future<({RoutingMode mode, List<RoutedApp> apps, bool diagnostic})>
  loadSettings() async =>
      (mode: RoutingMode.selected, apps: <RoutedApp>[], diagnostic: false);
  @override
  Future<void> saveSettings(
    RoutingMode mode,
    List<RoutedApp> apps,
    bool diagnostic,
  ) async {}
  @override
  Future<List<LogEvent>> loadLogs() async => [];
  @override
  Future<void> saveLogs(List<LogEvent> events) async {
    logWrites++;
  }
}

class FakeEngine implements VpnEngine {
  final stream = StreamController<EngineEvent>.broadcast();
  int connects = 0;
  String? selectedTag, lastConfig;
  @override
  Future<void> selectEndpoint(String tag) async {
    selectedTag = tag;
    stream.add(EngineEvent(selectedTag: tag));
  }

  @override
  Future<List<EndpointCheck>> checkEndpoints(
    String config,
    List<String> tags, {
    bool requireRunning = false,
  }) async => tags
      .map((tag) => EndpointCheck(tag: tag, time: DateTime.now(), delayMs: 35))
      .toList();
  @override
  Stream<EngineEvent> get events => stream.stream;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> connect(
    String config,
    RoutingMode mode,
    List<String> packages, {
    Map<String, String> profileNames = const {},
  }) async {
    connects++;
    lastConfig = config;
  }

  @override
  Future<void> disconnect() async {
    stream.add(const EngineEvent(state: TunnelState.disconnected));
  }

  @override
  Future<List<RoutedApp>> applications() async => [
    const RoutedApp(id: 'com.example.browser', name: 'Браузер'),
  ];
  @override
  Future<void> dispose() async {
    await stream.close();
  }
}

class PendingCheckEngine extends FakeEngine {
  final pending = <({String tag, Completer<List<EndpointCheck>> result})>[];
  @override
  Future<List<EndpointCheck>> checkEndpoints(
    String config,
    List<String> tags, {
    bool requireRunning = false,
  }) {
    final result = Completer<List<EndpointCheck>>();
    pending.add((tag: tags.single, result: result));
    return result.future;
  }

  void finish(int index, {String? error}) {
    final check = pending[index];
    check.result.complete([
      EndpointCheck(
        tag: check.tag,
        time: DateTime.now(),
        delayMs: error == null ? 42 : null,
        error: error,
      ),
    ]);
  }
}
