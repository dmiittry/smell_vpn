import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sme11_vpn/app_controller.dart';
import 'package:sme11_vpn/domain/profile.dart';
import 'package:sme11_vpn/domain/profile_catalog.dart';
import 'package:sme11_vpn/services/core_control.dart';
import 'package:sme11_vpn/services/vpn_engine.dart';

import 'support.dart';
import 'domain_test.dart' as fixtures;

class ResultsEngine extends FakeEngine {
  bool allFailed = false;
  @override
  Future<List<EndpointCheck>> checkEndpoints(
    String config,
    List<String> tags, {
    bool requireRunning = false,
  }) async => [
    for (var i = 0; i < tags.length; i++)
      EndpointCheck(
        tag: tags[i],
        time: DateTime.now(),
        delayMs: i == 1 && !allFailed ? 40 : null,
        error: i == 1 && !allFailed ? null : 'Нет ответа',
      ),
  ];
}

void main() {
  test(
    'Автовыбор выбирает свежий рабочий Japan New, а не первый Japan',
    () async {
      final engine = ResultsEngine();
      final c = AppController(engine: engine, storage: MemoryStorage());
      await c.saveProfile(
        VpnProfile.fromUri(fixtures.link.replaceFirst('#Test', '#Japan')),
      );
      await c.saveProfile(
        VpnProfile.fromUri(fixtures.link.replaceFirst('#Test', '#Japan-New')),
      );
      final old = c.catalog.profiles.first;
      c.health[old.tag] = EndpointCheck(
        tag: old.tag,
        time: DateTime.now(),
        delayMs: 1,
      );
      await c.chooseServer(automatic: true);
      expect(c.catalog.selectedId, c.catalog.profiles.last.id);
      expect(c.catalog.automatic, isTrue);
      expect(c.health[old.tag]!.available, isFalse);
      c.dispose();
      await engine.dispose();
    },
  );
  test(
    'Если все недоступны, автовыбор не включается и выбор сохраняется',
    () async {
      final engine = ResultsEngine()..allFailed = true;
      final c = AppController(engine: engine, storage: MemoryStorage());
      await c.saveProfile(VpnProfile.fromUri(fixtures.link));
      final before = c.catalog;
      await expectLater(c.chooseServer(automatic: true), throwsFormatException);
      expect(c.catalog, same(before));
      expect(c.catalog.automatic, isFalse);
      c.dispose();
      await engine.dispose();
    },
  );
  test(
    'Выключение авто сохраняет фактический сервер вместо старого выбора',
    () async {
      final engine = FakeEngine();
      final c = AppController(engine: engine, storage: MemoryStorage());
      await c.saveProfile(VpnProfile.fromUri(fixtures.link));
      await c.saveProfile(
        VpnProfile.fromUri(fixtures.link.replaceFirst('#Test', '#New')),
      );
      c.catalog = ProfileCatalog(
        profiles: c.catalog.profiles,
        selectedId: c.catalog.profiles.first.id,
        automatic: true,
      );
      c.state = TunnelState.running;
      c.activeTag = c.catalog.profiles.last.tag;
      await c.chooseServer(automatic: false);
      expect(c.catalog.selectedId, c.catalog.profiles.last.id);
      expect(engine.selectedTag, c.activeTag);
      c.dispose();
      await engine.dispose();
    },
  );

  for (final allFailed in [false, true]) {
    test(
      'Core API: свежая проверка перед авто, allFailed=$allFailed',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        var selected = 'ep_new';
        var auto = 'ep_old';
        final calls = <String>[];
        final subscription = server.listen((request) async {
          final path = request.uri.path;
          calls.add('${request.method} $path');
          Object result = {};
          if (path == '/proxies/auto') {
            result = {
              'all': ['ep_old', 'ep_new'],
              'now': auto,
            };
          } else if (path.endsWith('/delay') && path.startsWith('/proxies/')) {
            result = {'delay': path.contains('ep_new') && !allFailed ? 35 : 0};
          } else if (path == '/group/auto/delay') {
            auto = 'ep_new';
            result = {'ep_new': 35};
          } else if (path == '/proxies/proxy' && request.method == 'PUT') {
            selected =
                (jsonDecode(await utf8.decoder.bind(request).join())
                        as Map)['name']
                    as String;
          } else if (path == '/proxies/proxy') {
            result = {'now': selected};
          } else if (path == '/proxies') {
            result = {
              'proxies': {
                'proxy': {'now': selected},
                'auto': {'now': auto},
                'ep_old': {
                  'history': [
                    {'time': DateTime.now().toIso8601String(), 'delay': 0},
                  ],
                },
              },
            };
          }
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(result));
          await request.response.close();
        });
        final checks = <EndpointCheck>[];
        final control = CoreControl(
          onSelected: (_) {},
          onChecks: checks.addAll,
        );
        control.restore({'port': server.port, 'secret': 's' * 32});
        try {
          if (allFailed) {
            await expectLater(control.select('auto'), throwsFormatException);
            expect(selected, 'ep_new');
            expect(calls.any((e) => e.startsWith('PUT')), isFalse);
          } else {
            await control.select('auto');
            expect(selected, 'auto');
            expect(auto, 'ep_new');
            expect(
              calls.indexOf('GET /group/auto/delay'),
              lessThan(calls.indexOf('PUT /proxies/proxy')),
            );
            expect(
              checks.last.available,
              isFalse,
            ); // нулевая история не является успехом
          }
        } finally {
          control.close();
          await subscription.cancel();
          await server.close(force: true);
        }
      },
    );
  }
}
