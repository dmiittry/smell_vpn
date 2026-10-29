import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sme11_vpn/app_controller.dart';
import 'package:sme11_vpn/domain/profile.dart';
import 'package:sme11_vpn/domain/profile_catalog.dart';
import 'package:sme11_vpn/services/storage.dart';
import 'package:sme11_vpn/services/vpn_engine.dart';

import 'catalog_test.dart' show SecureMemory;
import 'domain_test.dart' as fixtures;
import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppController c;
  late MemoryStorage storage;
  late FakeEngine engine;
  setUp(() async {
    storage = MemoryStorage();
    engine = FakeEngine();
    c = AppController(engine: engine, storage: storage);
    await c.saveProfile(VpnProfile.fromUri(fixtures.link));
    await c.saveProfile(
      VpnProfile.fromUri(fixtures.link.replaceFirst('#Test', '#Second')),
    );
  });
  tearDown(() async {
    c.dispose();
    await engine.dispose();
  });

  test(
    'Удаление выбранного сервера выбирает оставшийся и сохраняется',
    () async {
      final removed = c.catalog.selected!;
      final other = c.catalog.profiles.last;
      c.health[removed.tag] = EndpointCheck(
        tag: removed.tag,
        time: DateTime.now(),
        delayMs: 20,
      );
      await c.deleteServer(removed.id);
      expect(c.catalog.selectedId, other.id);
      expect(c.catalog.profiles, hasLength(1));
      expect(c.health.containsKey(removed.tag), isFalse);
      expect((await storage.loadCatalog()).selectedId, other.id);
    },
  );

  test('Удаление невыбранного сервера сохраняет выбор и автовыбор', () async {
    await c.chooseServer(automatic: true);
    final selected = c.catalog.selectedId;
    await c.deleteServer(c.catalog.profiles.last.id);
    expect(c.catalog.selectedId, selected);
    expect(c.catalog.automatic, isTrue);
  });

  test(
    'Последний сервер оставляет валидный пустой каталог без автовыбора',
    () async {
      await c.chooseServer(automatic: true);
      await c.deleteServer(c.catalog.profiles.last.id);
      await c.deleteServer(c.catalog.selectedId!);
      expect(c.catalog.profiles, isEmpty);
      expect(c.catalog.selectedId, isNull);
      expect(c.catalog.automatic, isFalse);
      c.catalog.validate();
      expect((await storage.loadCatalog()).profiles, isEmpty);
    },
  );

  test(
    'Ошибка записи не удаляет профиль, выбор и результат проверки',
    () async {
      final before = c.catalog;
      final entry = c.catalog.selected!;
      c.health[entry.tag] = EndpointCheck(
        tag: entry.tag,
        time: DateTime.now(),
        delayMs: 20,
      );
      storage.failSave = true;
      await expectLater(c.deleteServer(entry.id), throwsFormatException);
      expect(c.catalog, same(before));
      expect(c.health[entry.tag], isNotNull);
      expect(c.updatingCatalog, isFalse);
      expect(storage.catalog, same(before));
    },
  );

  test(
    'Удаление запрещено при работающем VPN и во время других операций',
    () async {
      final id = c.catalog.selectedId!;
      for (final state in [
        TunnelState.running,
        TunnelState.connecting,
        TunnelState.disconnecting,
      ]) {
        c.state = state;
        await expectLater(c.deleteServer(id), throwsStateError);
      }
      c.state = TunnelState.disconnected;
      c.checking = true;
      await expectLater(c.deleteServer(id), throwsStateError);
      c.checking = false;
      c.catalogReadable = false;
      await expectLater(c.deleteServer(id), throwsStateError);
      expect(c.catalog.profiles, hasLength(2));
    },
  );

  test('Пустой каталог не восстанавливает удалённый старый профиль после перезапуска', () async {
    final secure = SecureMemory();
    final persistent = AppStorage(secure: secure);
    await persistent.saveProfile(VpnProfile.fromUri(fixtures.link));
    final migrated = await persistent.loadCatalog();
    c.catalog = migrated;
    final local = AppController(engine: engine, storage: persistent)
      ..catalog = migrated;
    await local.deleteServer(migrated.selectedId!);
    expect((await AppStorage(secure: secure).loadCatalog()).profiles, isEmpty);
    expect(secure.values['vless_profile_v1'], isNotNull);
    local.dispose();
  });

  test('Удаление блокирует параллельную запись и подключение до завершения сохранения', () async {
    final slow = _SlowStorage()..catalog = c.catalog;
    final local = AppController(engine: engine, storage: slow)
      ..catalog = c.catalog;
    final deleting = local.deleteServer(local.catalog.selectedId!);
    expect(local.busy, isTrue);
    await expectLater(
      local.deleteServer(local.catalog.profiles.last.id),
      throwsStateError,
    );
    await expectLater(
      local.saveProfile(VpnProfile.fromUri(fixtures.link)),
      throwsStateError,
    );
    slow.release.complete();
    await deleting;
    expect(local.busy, isFalse);
    local.dispose();
  });
}

class _SlowStorage extends MemoryStorage {
  final release = Completer<void>();
  @override
  Future<void> saveCatalog(ProfileCatalog value) async {
    await release.future;
    await super.saveCatalog(value);
  }
}
