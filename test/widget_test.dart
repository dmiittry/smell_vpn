import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sme11_vpn/app_controller.dart';
import 'package:sme11_vpn/ui/app.dart';
import 'package:sme11_vpn/domain/profile.dart';
import 'package:sme11_vpn/domain/routing.dart';
import 'package:sme11_vpn/services/vpn_engine.dart';
import 'package:sme11_vpn/ui/theme.dart';

import 'support.dart';
import 'domain_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('Roboto');
    for (final path in [
      'Roboto-Regular.ttf',
      'Roboto-Medium.ttf',
      'Roboto-Bold.ttf',
    ]) {
      loader.addFont(rootBundle.load('assets/fonts/$path'));
    }
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  testWidgets('Цвет, реальный результат пинга и текст ошибки на главной', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final engine = PendingCheckEngine();
    final c = AppController(engine: engine, storage: MemoryStorage());
    await c.initialize();
    await c.saveProfile(
      VpnProfile.fromUri(fixtures.link.replaceFirst('#Test', '#Reality · 443')),
    );
    await c.configure(routingMode: RoutingMode.all);
    await tester.pumpWidget(Sme11App(controller: c));
    await c.connect();
    engine.stream.add(EngineEvent(selectedTag: c.catalog.selected!.tag));
    engine.stream.add(const EngineEvent(state: TunnelState.running));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(find.text('Проверка соединения…'), findsOneWidget);
    expect(find.text('Подключено'), findsNothing);
    final power = find.descendant(
      of: find.byType(ConnectionPage),
      matching: find.byIcon(Icons.power_settings_new_rounded),
    );
    expect(tester.widget<Icon>(power).color, muted);
    engine.finish(0);
    await tester.pumpAndSettle();
    expect(find.text('Подключено'), findsOneWidget);
    expect(find.text('42 мс'), findsOneWidget);
    expect(tester.widget<Icon>(power).color, success);
    if (const bool.fromEnvironment('CAPTURE_PREVIEWS')) {
      await expectLater(
        find.byType(AppShell),
        matchesGoldenFile('../docs/screenshots/home_connected.png'),
      );
    }
    final next = c.checkConnection();
    engine.finish(1, error: 'Сервер не отвечает. Проверьте сеть и профиль.');
    await next;
    await tester.pumpAndSettle();
    expect(find.text('Проверка не пройдена'), findsOneWidget);
    expect(
      find.text('Сервер не отвечает. Проверьте сеть и профиль.'),
      findsOneWidget,
    );
    expect(find.text('42 мс'), findsNothing);
    expect(tester.widget<Icon>(power).color, failure);
    if (const bool.fromEnvironment('CAPTURE_PREVIEWS')) {
      await expectLater(
        find.byType(AppShell),
        matchesGoldenFile('../docs/screenshots/home_error.png'),
      );
    }
    // Неуспешная проверка не мешает пользователю остановить живой туннель.
    await tester.tap(power);
    await tester.pumpAndSettle();
    expect(c.state, TunnelState.disconnected);
    expect(find.text('Нажмите для подключения'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await engine.dispose();
  });
  for (final size in [
    const Size(390, 844),
    const Size(1180, 820),
    const Size(320, 720),
  ]) {
    testWidgets('Навигация и форма профиля без переполнения ${size.width}', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final engine = FakeEngine();
      final c = AppController(engine: engine, storage: MemoryStorage());
      c.initialized = true;
      await tester.pumpWidget(Sme11App(controller: c));
      expect(find.text('Нажмите для подключения'), findsOneWidget);
      expect(find.text('Свобода подключения'), findsNothing);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('CAPTURE_PREVIEWS')) {
        await expectLater(
          find.byType(AppShell),
          matchesGoldenFile(
            '../docs/screenshots/home_${size.width.toInt()}.png',
          ),
        );
      }
      await tester.ensureVisible(find.text('Добавить сервер'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Добавить сервер'));
      await tester.pumpAndSettle();
      expect(find.text('Профиль сервера'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Закрыть'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Серверы').last);
      await tester.pumpAndSettle();
      expect(find.text('Проверить серверы'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await c.saveProfile(
        VpnProfile.fromUri(fixtures.link.replaceFirst('#Test', '#Inbound-443')),
      );
      await c.saveProfile(
        VpnProfile.fromUri(
          fixtures.link
              .replaceFirst(':443?', ':8443?')
              .replaceFirst('#Test', '#Inbound-8443'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Выбрать').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Выбрать').last);
      await tester.pumpAndSettle();
      expect(c.catalog.selectedId, c.catalog.profiles.last.id);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('CAPTURE_PREVIEWS')) {
        await expectLater(
          find.byType(AppShell),
          matchesGoldenFile(
            '../docs/screenshots/servers_${size.width.toInt()}.png',
          ),
        );
      }
      await tester.tap(find.text('Приложения').last);
      await tester.pumpAndSettle();
      expect(find.text('Маршрутизация'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('CAPTURE_PREVIEWS')) {
        await expectLater(
          find.byType(AppShell),
          matchesGoldenFile(
            '../docs/screenshots/apps_${size.width.toInt()}.png',
          ),
        );
      }
      await tester.tap(find.text('Логи').last);
      await tester.pumpAndSettle();
      expect(find.text('Журнал'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('CAPTURE_PREVIEWS')) {
        await expectLater(
          find.byType(AppShell),
          matchesGoldenFile(
            '../docs/screenshots/logs_${size.width.toInt()}.png',
          ),
        );
      }
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await engine.dispose();
    });
  }
}
