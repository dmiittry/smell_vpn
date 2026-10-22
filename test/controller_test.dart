import 'package:flutter_test/flutter_test.dart';
import 'package:sme11_vpn/app_controller.dart';
import 'package:sme11_vpn/domain/profile.dart';
import 'package:sme11_vpn/domain/routing.dart';
import 'package:sme11_vpn/domain/log_event.dart';
import 'package:sme11_vpn/services/vpn_engine.dart';

import 'domain_test.dart' as fixtures;
import 'support.dart';

void main() {
  test(
    'Обычные логи Android не показывают ложную ошибку подключения',
    () async {
      final engine = FakeEngine();
      final c = AppController(engine: engine, storage: MemoryStorage());
      await c.initialize();
      engine.stream.add(const EngineEvent(state: TunnelState.running));
      for (final message in [
        'INFO[0013] dns: exchanged example.com NOERROR',
        'DEBUG[0013] router: match[0] => sniff',
        'TRACE[0014] outbound/vless[proxy]: XtlsPadding 64 142 0',
      ]) {
        engine.stream.add(
          EngineEvent(level: EventLevel.error, message: message),
        );
      }
      await Future<void>.delayed(Duration.zero);
      expect(c.state, TunnelState.running);
      expect(c.lastError, isNull);
      expect(c.logs.where((e) => e.level == EventLevel.error), isEmpty);

      engine.stream.add(
        const EngineEvent(
          level: EventLevel.info,
          message: 'ERROR[0015] dial: timeout',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(c.logs.first.level, EventLevel.error);
      expect(c.lastError, isNull);
      expect(c.state, TunnelState.running);

      engine.stream.add(
        const EngineEvent(
          state: TunnelState.failed,
          level: EventLevel.error,
          message: 'service fault',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(c.state, TunnelState.failed);
      expect(c.logs.first.level, EventLevel.error);
      c.dispose();
      await engine.dispose();
    },
  );
  test(
    'Сохранённый журнал исправляется без потери записей и времени',
    () async {
      final engine = FakeEngine();
      final time = DateTime(2026, 10, 6, 19, 59, 20);
      final storage = _PreviousLogs([
        LogEvent(
          time: time,
          level: EventLevel.error,
          source: 'Ядро',
          message: 'TRACE[0014] outbound/vless[proxy]: XtlsPadding 64 142 0',
        ),
        LogEvent(
          time: time,
          level: EventLevel.error,
          source: 'Ядро',
          message: 'ERROR[0015] dial: timeout',
        ),
        LogEvent(
          time: time,
          level: EventLevel.error,
          source: 'Подключение',
          message: 'INFO is not a core log header here',
        ),
      ]);
      final c = AppController(engine: engine, storage: storage);
      await c.initialize();
      final restored = c.logs.where((e) => e.time == time).toList();
      expect(restored, hasLength(3));
      expect(restored[0].level, EventLevel.debug);
      expect(restored[1].level, EventLevel.error);
      expect(restored[2].level, EventLevel.error);
      c.dispose();
      await engine.dispose();
    },
  );
  testWidgets(
    'Непрерывные логи сохраняются периодически, а не только после паузы',
    (tester) async {
      final engine = FakeEngine(), storage = MemoryStorage();
      final c = AppController(engine: engine, storage: storage);
      await c.initialize();
      for (var i = 0; i < 20; i++) {
        c.addLog(EventLevel.debug, 'Тест', 'Событие $i');
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(storage.logWrites, greaterThanOrEqualTo(2));
      c.dispose();
      await engine.dispose();
    },
  );
  test(
    'Нет фиктивного подключения; авария ядра сохраняет ошибку после stopped',
    () async {
      final engine = FakeEngine();
      final c = AppController(engine: engine, storage: MemoryStorage());
      await c.initialize();
      await c.saveProfile(VpnProfile.fromUri(fixtures.link));
      await c.configure(
        apps: [const RoutedApp(id: 'com.example.browser', name: 'Browser')],
      );
      await c.connect();
      expect(c.state, TunnelState.connecting);
      expect(engine.connects, 1);
      engine.stream.add(const EngineEvent(state: TunnelState.running));
      await Future<void>.delayed(Duration.zero);
      expect(c.state, TunnelState.running);
      engine.stream.add(
        const EngineEvent(
          state: TunnelState.failed,
          level: EventLevel.error,
          message: 'reality handshake failed',
        ),
      );
      engine.stream.add(const EngineEvent(state: TunnelState.disconnected));
      await Future<void>.delayed(Duration.zero);
      expect(c.state, TunnelState.failed);
      expect(c.lastError, contains('Reality'));
      expect(c.logs.any((e) => e.level == EventLevel.error), true);
      c.dispose();
      await engine.dispose();
    },
  );
  test('Без профиля или выбранных приложений ядро не запускается', () async {
    final engine = FakeEngine();
    final c = AppController(engine: engine, storage: MemoryStorage());
    await c.initialize();
    await c.connect();
    expect(engine.connects, 0);
    await c.saveProfile(VpnProfile.fromUri(fixtures.link));
    await c.connect();
    expect(engine.connects, 0);
    expect(c.lastError, contains('приложение'));
    c.dispose();
    await engine.dispose();
  });
  test('Внешняя остановка через stopping сохраняется как ошибка', () async {
    final engine = FakeEngine();
    final c = AppController(engine: engine, storage: MemoryStorage());
    await c.initialize();
    engine.stream.add(const EngineEvent(state: TunnelState.running));
    engine.stream.add(const EngineEvent(state: TunnelState.disconnecting));
    engine.stream.add(const EngineEvent(state: TunnelState.disconnected));
    await Future<void>.delayed(Duration.zero);
    expect(c.state, TunnelState.failed);
    expect(c.lastError, contains('остановлен'));
    expect(c.logs.first.level, EventLevel.error);

    // Явное отключение пользователем не считается аварией.
    engine.stream.add(const EngineEvent(state: TunnelState.running));
    await Future<void>.delayed(Duration.zero);
    await c.disconnect();
    await Future<void>.delayed(Duration.zero);
    expect(c.state, TunnelState.disconnected);
    expect(c.lastError, isNull);
    c.dispose();
    await engine.dispose();
  });
}

class _PreviousLogs extends MemoryStorage {
  _PreviousLogs(this.previous);
  final List<LogEvent> previous;
  @override
  Future<List<LogEvent>> loadLogs() async => previous;
}
