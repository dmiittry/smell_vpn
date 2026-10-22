import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sme11_vpn/app_controller.dart';
import 'package:sme11_vpn/domain/config_builder.dart';
import 'package:sme11_vpn/domain/profile.dart';
import 'package:sme11_vpn/domain/profile_catalog.dart';
import 'package:sme11_vpn/domain/routing.dart';
import 'package:sme11_vpn/domain/traffic.dart';
import 'package:sme11_vpn/services/storage.dart';
import 'package:sme11_vpn/services/vpn_engine.dart';

import 'domain_test.dart' as fixtures;
import 'support.dart';

class SecureMemory extends FlutterSecureStorage {
  final values = <String, String>{};
  bool rejectWrites = false;
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];
  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (!rejectWrites && value != null) values[key] = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final profile = VpnProfile.fromUri(fixtures.link);
  test(
    'Миграция сохраняет старый профиль и создаёт проверенный каталог',
    () async {
      final secure = SecureMemory()
        ..values['vless_profile_v1'] = jsonEncode(profile.toJson());
      final storage = AppStorage(secure: secure);
      final catalog = await storage.loadCatalog();
      expect(catalog.selected!.profile.uuid, profile.uuid);
      expect(catalog.automatic, false);
      expect(secure.values.containsKey('vless_profile_v1'), true);
      expect((await storage.loadCatalog()).selectedId, catalog.selectedId);
    },
  );
  test('Неуспешная запись миграции не выдаётся за успех', () async {
    final secure = SecureMemory()
      ..values['vless_profile_v1'] = jsonEncode(profile.toJson())
      ..rejectWrites = true;
    await expectLater(
      AppStorage(secure: secure).loadCatalog(),
      throwsFormatException,
    );
    expect(secure.values['vless_profile_v1'], isNotNull);
  });
  test('Повреждённый новый каталог не перезаписывается старым', () async {
    final secure = SecureMemory()
      ..values['vless_profile_v1'] = jsonEncode(profile.toJson())
      ..values['profiles_v2'] = '{broken';
    await expectLater(
      AppStorage(secure: secure).loadCatalog(),
      throwsFormatException,
    );
    expect(secure.values['profiles_v2'], '{broken');
  });
  test(
    'Два inbound с одним UUID имеют независимые теги; routing всегда proxy',
    () {
      final a = SavedProfile.create(profile), b = SavedProfile.create(profile);
      expect(a.tag, isNot(b.tag));
      final catalog = ProfileCatalog(
        profiles: [a, b],
        selectedId: a.id,
        automatic: true,
      );
      final config = ConfigBuilder.catalog(
        catalog,
        windows: true,
        mode: RoutingMode.selected,
        applications: [r'C:\Browser.exe'],
      );
      final outbounds = config['outbounds'] as List;
      expect(outbounds.first['default'], 'auto');
      expect(outbounds[1]['outbounds'], [a.tag, b.tag]);
      expect(outbounds[1]['outbounds'], isNot(contains('direct')));
      final rules = config['route']['rules'] as List;
      expect(
        rules.singleWhere((r) => r['process_path'] != null)['outbound'],
        'proxy',
      );
      final probe = ConfigBuilder.catalog(
        catalog,
        windows: false,
        mode: RoutingMode.selected,
        applications: [],
        probeOnly: true,
      );
      expect(probe['inbounds'], isEmpty);
    },
  );
  test('Ошибка сохранения выбора возвращает прежний сервер ядра', () async {
    final a = SavedProfile.create(profile), b = SavedProfile.create(profile);
    final storage = MemoryStorage()
      ..catalog = ProfileCatalog(profiles: [a, b], selectedId: a.id);
    final engine = FakeEngine();
    final c = AppController(engine: engine, storage: storage);
    await c.initialize();
    engine.stream.add(const EngineEvent(state: TunnelState.running));
    await Future<void>.delayed(Duration.zero);
    storage.failSave = true;
    await expectLater(
      c.chooseServer(id: b.id, automatic: false),
      throwsFormatException,
    );
    expect(c.catalog.selectedId, a.id);
    expect(engine.selectedTag, a.tag);
    expect(c.changingServer, false);
    c.dispose();
    await engine.dispose();
  });
  test(
    'Офлайн-проверка не включает VPN и не меняет режим приложений',
    () async {
      final a = SavedProfile.create(profile);
      final storage = MemoryStorage()
        ..catalog = ProfileCatalog(profiles: [a], selectedId: a.id);
      final engine = FakeEngine();
      final c = AppController(engine: engine, storage: storage);
      await c.initialize();
      await c.checkServers();
      expect(c.state, TunnelState.disconnected);
      expect(c.mode, RoutingMode.selected);
      expect(c.selected, isEmpty);
      expect(c.health[a.tag]!.available, true);
      c.dispose();
      await engine.dispose();
    },
  );
  test('Скорость конвертируется из байт/с в биты/с', () {
    expect(trafficSpeed(0), '0 кбит/с');
    expect(trafficSpeed(-5), '0 кбит/с');
    expect(trafficSpeed(105000), '840 кбит/с');
    expect(trafficSpeed(1250000), '10.0 Мбит/с');
  });
}
