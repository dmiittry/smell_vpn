import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sme11_vpn/app_controller.dart';
import 'package:sme11_vpn/domain/log_event.dart';
import 'package:sme11_vpn/services/vpn_engine.dart';

import 'support.dart';

void main() {
  test(
    'Освобождение сервиса после ошибки запуска не скрывает её причину',
    () async {
      final engine = FakeEngine();
      final c = AppController(engine: engine, storage: MemoryStorage());
      await c.initialize();
      engine.stream.add(
        const EngineEvent(
          state: TunnelState.failed,
          level: EventLevel.error,
          message: 'Service start timeout',
        ),
      );
      engine.stream.add(
        const EngineEvent(state: TunnelState.disconnected, userInitiated: true),
      );
      await Future<void>.delayed(Duration.zero);
      expect(c.state, TunnelState.failed);
      expect(c.lastError, contains('не отвечает'));
      c.dispose();
      await engine.dispose();
    },
  );
  test('Сетевой поток не вытесняет остановку, ошибку и событие Android', () {
    final time = DateTime(2026, 10, 15);
    final events = [
      for (var i = 0; i < 5000; i++)
        LogEvent(
          time: time,
          level: i.isEven ? EventLevel.debug : EventLevel.info,
          source: 'Ядро',
          message: 'Сетевое событие $i',
        ),
      LogEvent(
        time: time,
        level: EventLevel.error,
        source: 'Ядро',
        message: 'ERROR core failed',
      ),
      LogEvent(
        time: time,
        level: EventLevel.info,
        source: 'Android',
        message: 'onDestroy',
      ),
      LogEvent(
        time: time,
        level: EventLevel.error,
        source: 'Подключение',
        message: 'VPN остановлен',
      ),
    ];
    final retained = retainLogs(events);
    expect(retained.where((e) => e.level == EventLevel.debug), hasLength(300));
    expect(
      retained.where((e) => e.source == 'Ядро' && e.level == EventLevel.info),
      hasLength(1000),
    );
    expect(
      retained.map((e) => e.message),
      containsAll(['ERROR core failed', 'onDestroy', 'VPN остановлен']),
    );
  });

  test(
    'Повторный импорт служебного журнала сохраняет исходное время без дублей',
    () async {
      final engine = FakeEngine();
      final c = AppController(engine: engine, storage: MemoryStorage());
      await c.initialize();
      final time = DateTime(2026, 10, 14);
      final entry = LogEvent(
        time: time,
        level: EventLevel.warning,
        source: 'Android',
        message: 'Процесс завершён',
        id: 'exit_test',
      );
      final restored = LogEvent.fromJson(entry.toJson());
      for (var i = 0; i < 3; i++) {
        engine.stream.add(
          EngineEvent(
            level: restored.level,
            source: restored.source,
            message: restored.message,
            id: restored.id,
            time: restored.time,
          ),
        );
      }
      await Future<void>.delayed(Duration.zero);
      expect(c.logs.where((e) => e.id == 'exit_test'), hasLength(1));
      expect(c.logs.last.time, time);
      c.dispose();
      await engine.dispose();
    },
  );

  test('Отключение из уведомления не считается аварией', () async {
    final engine = FakeEngine();
    final c = AppController(engine: engine, storage: MemoryStorage());
    await c.initialize();
    engine.stream.add(const EngineEvent(state: TunnelState.running));
    engine.stream.add(const EngineEvent(state: TunnelState.disconnecting));
    engine.stream.add(
      const EngineEvent(state: TunnelState.disconnected, userInitiated: true),
    );
    await Future<void>.delayed(Duration.zero);
    expect(c.state, TunnelState.disconnected);
    expect(c.lastError, isNull);
    expect(c.logs.where((e) => e.level == EventLevel.error), isEmpty);
    c.dispose();
    await engine.dispose();
  });

  test('При выключенной диагностике TRACE не попадает в журнал', () async {
    final engine = FakeEngine();
    final c = AppController(engine: engine, storage: MemoryStorage());
    await c.initialize();
    engine.stream.add(
      const EngineEvent(
        message: 'TRACE[0014] XtlsPadding',
        level: EventLevel.error,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(c.logs.any((e) => e.message.contains('XtlsPadding')), isFalse);
    expect(c.lastError, isNull);
    c.dispose();
    await engine.dispose();
  });

  test(
    'Медленный диск не создаёт неограниченную очередь снимков журнала',
    () async {
      final engine = FakeEngine();
      final storage = _SlowStorage();
      final c = AppController(engine: engine, storage: storage);
      await c.initialize();
      for (var i = 0; i < 150; i++) {
        c.addLog(EventLevel.error, 'Тест', 'Ошибка $i');
      }
      expect(storage.logWrites, 1);
      storage.gate.complete();
      await c.flushLogs();
      expect(storage.logWrites, 2);
      expect(storage.saved.first.message, 'Ошибка 149');
      c.dispose();
      await engine.dispose();
    },
  );
}

class _SlowStorage extends MemoryStorage {
  final gate = Completer<void>();
  List<LogEvent> saved = [];
  @override
  Future<void> saveLogs(List<LogEvent> events) async {
    logWrites++;
    await gate.future;
    saved = events;
  }
}
