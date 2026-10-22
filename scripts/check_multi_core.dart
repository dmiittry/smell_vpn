import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sme11_vpn/services/core_control.dart';

/// Интеграционная проверка настоящего локального API, без TUN и чужого сервера.
Future<void> main(List<String> args) async {
  if (args.isEmpty) throw ArgumentError('Укажите путь к sing-box.exe');
  final web = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final requests = web.listen((request) {
    request.response.statusCode = 204;
    unawaited(request.response.close());
  });
  String selected = '';
  final control = CoreControl(
    onSelected: (tag) => selected = tag,
    onChecks: (_) {},
  );
  Process? process;
  final subscriptions = <StreamSubscription>[];
  try {
    final config = await control.configure(
      jsonEncode({
        'log': {'level': 'error'},
        'inbounds': [],
        'outbounds': [
          {
            'type': 'selector',
            'tag': 'proxy',
            'outbounds': ['ep_good', 'ep_bad', 'auto'],
            'default': 'ep_bad',
            'interrupt_exist_connections': true,
          },
          {
            'type': 'urltest',
            'tag': 'auto',
            'outbounds': ['ep_good', 'ep_bad'],
            'url': 'http://127.0.0.1:${web.port}/generate_204',
            'interval': '1s',
            'tolerance': 0,
          },
          {'type': 'direct', 'tag': 'ep_good'},
          {
            'type': 'socks',
            'tag': 'ep_bad',
            'server': '127.0.0.1',
            'server_port': 1,
          },
        ],
        'route': {'final': 'proxy'},
      }),
    );
    process = await Process.start(args.first, [
      'run',
      '-c',
      'stdin',
      '--disable-color',
    ]);
    for (final stream in [process.stdout, process.stderr]) {
      subscriptions.add(stream.transform(utf8.decoder).listen((_) {}));
    }
    process.stdin.write(config);
    await process.stdin.close();
    await control.waitReady().timeout(const Duration(seconds: 12));
    final api = (jsonDecode(config) as Map)['experimental']['clash_api'];
    final http = HttpClient();
    try {
      final response = await (await http.getUrl(
        Uri.parse('http://${api['external_controller']}/version'),
      )).close();
      if (response.statusCode != 401) {
        throw StateError('API доступен без авторизации');
      }
      await response.drain<void>();
    } finally {
      http.close(force: true);
    }
    final checks = await control.check(['ep_good', 'ep_bad']);
    if (!checks[0].available || checks[1].available) {
      throw StateError('Неверные результаты проверки');
    }
    await control.select('ep_good');
    if (selected != 'ep_good') throw StateError('Ручной выбор не подтверждён');
    await control.select('ep_bad');
    if (selected != 'ep_bad') {
      throw StateError('Выбор второго профиля не подтверждён');
    }
    await control.select('auto');
    for (var i = 0; i < 20 && selected != 'ep_good'; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await control.snapshot();
    }
    if (selected != 'ep_good') {
      throw StateError('Автовыбор не исключил недоступный профиль');
    }
    final failureControl = CoreControl(
      onSelected: (_) {},
      onChecks: (_) {},
      checkUrl: 'https://127.0.0.1:1/generate_204',
    );
    try {
      failureControl.restore({
        'port': int.parse(
          (api['external_controller'] as String).split(':').last,
        ),
        'secret': api['secret'],
      });
      final failed = await failureControl.check(['ep_good', 'ep_bad']);
      if (failed.any((e) => e.available)) {
        throw StateError('Отказ HTTPS-пробы отмечен как успех');
      }
    } finally {
      failureControl.close();
    }
    stdout.writeln(
      'OK: авторизация API, HTTPS-пробы, ручной выбор, авто среди доступных, отказ HTTPS-пробы. Тестовые outbounds direct/socks; Reality и TUN проверяются отдельно.',
    );
  } finally {
    control.close();
    process?.kill();
    if (process != null) await process.exitCode;
    for (final sub in subscriptions) {
      await sub.cancel();
    }
    await requests.cancel();
    await web.close(force: true);
  }
}
