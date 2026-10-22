import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sme11_vpn/app_controller.dart';
import 'package:sme11_vpn/domain/profile.dart';
import 'package:sme11_vpn/domain/profile_catalog.dart';
import 'package:sme11_vpn/domain/routing.dart';
import 'package:sme11_vpn/services/vpn_engine.dart';

import 'domain_test.dart' as fixtures;
import 'support.dart';

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  late PendingCheckEngine engine;
  late AppController c;
  setUp(() async {
    engine = PendingCheckEngine();
    c = AppController(engine: engine, storage: MemoryStorage());
    await c.initialize();
    await c.saveProfile(VpnProfile.fromUri(fixtures.link));
    await c.configure(routingMode: RoutingMode.all);
    await c.connect();
    engine.stream.add(EngineEvent(selectedTag: c.catalog.selected!.tag));
    engine.stream.add(const EngineEvent(state: TunnelState.running));
    await flush();
  });
  tearDown(() async {
    c.dispose();
    // Завершаем ожидающие операции после dispose: они не должны обновлять UI.
    for (final item in engine.pending) {
      if (!item.result.isCompleted) item.result.complete([]);
    }
    await flush();
    await engine.dispose();
  });

  test('Запуск TUN не является успехом до завершения HTTPS-пробы', () async {
    expect(c.state, TunnelState.running);
    expect(c.verifyingConnection, isTrue);
    expect(c.connectionVerified, isFalse);
    expect(c.connectionCheck, isNull);
    // Повторный запрос во время проверки не создаёт ещё одну пробу.
    await c.checkConnection();
    expect(engine.pending, hasLength(1));
    engine.finish(0);
    await flush();
    expect(c.connectionVerified, isTrue);
    expect(c.connectionCheck!.delayMs, 42);
  });

  test('Ошибка пробы видна отдельно от работающего VPN-сервиса', () async {
    engine.finish(0, error: 'HTTPS: сервер не отвечает.');
    await flush();
    expect(c.state, TunnelState.running);
    expect(c.connectionVerified, isFalse);
    expect(c.connectionCheck!.error, contains('не отвечает'));
    expect(c.logs.first.source, 'Проверка');
    expect(c.logs.first.level.name, 'error');
    final retry = c.checkConnection();
    engine.finish(1);
    await retry;
    expect(c.connectionVerified, isTrue);
  });

  test(
    'Ответ от предыдущего сервера не окрашивает новый сервер зелёным',
    () async {
      final other = SavedProfile.create(
        VpnProfile.fromUri(fixtures.link.replaceFirst('#Test', '#Second')),
      );
      c.catalog = ProfileCatalog(
        profiles: [...c.catalog.profiles, other],
        selectedId: other.id,
      );
      engine.stream.add(EngineEvent(selectedTag: other.tag));
      await flush();
      expect(engine.pending, hasLength(2));
      engine.finish(0);
      await flush();
      expect(c.connectionVerified, isFalse);
      expect(c.verifyingConnection, isTrue);
      engine.finish(1);
      await flush();
      expect(c.connectionVerified, isTrue);
      expect(c.connectionCheck!.tag, other.tag);
    },
  );

  test(
    'Ответ пробы после отключения не восстанавливает зелёный статус',
    () async {
      await c.disconnect();
      engine.finish(0);
      await flush();
      expect(c.state, TunnelState.disconnected);
      expect(c.connectionCheck, isNull);
      expect(c.connectionVerified, isFalse);
      expect(c.verifyingConnection, isFalse);
    },
  );

  test('Устаревший пинг не подтверждает текущее соединение', () async {
    engine.pending[0].result.complete([
      EndpointCheck(
        tag: c.activeTag!,
        time: DateTime.now().subtract(const Duration(minutes: 2)),
        delayMs: 20,
      ),
    ]);
    await flush();
    expect(c.connectionVerified, isFalse);
  });

  test(
    'Проверка живого туннеля не запускает временный сервис после остановки',
    () async {
      final stopped = _StoppedCore();
      await expectLater(
        stopped.checkEndpoints('{}', ['ep_test'], requireRunning: true),
        throwsFormatException,
      );
      expect(stopped.starts, 0);
      await stopped.dispose();
    },
  );
}

class _StoppedCore extends ControlledVpnEngine {
  int starts = 0;
  @override
  final eventSink = StreamController<EngineEvent>.broadcast();
  @override
  Stream<EngineEvent> get events => eventSink.stream;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> startCore(
    String config,
    RoutingMode mode,
    List<String> packages, {
    required bool probeOnly,
    Map<String, String> profileNames = const {},
  }) async {
    starts++;
  }

  @override
  Future<void> stopCore() async {}
  @override
  Future<List<RoutedApp>> applications() async => [];
  @override
  Future<void> dispose() => eventSink.close();
}
