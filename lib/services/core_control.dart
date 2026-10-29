import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../domain/config_builder.dart';
import '../domain/profile_catalog.dart';

/// Локальный API ядра: отдельный случайный порт и токен на каждый запуск.
class CoreControl {
  CoreControl({
    required this.onSelected,
    required this.onChecks,
    this.checkUrl = ConfigBuilder.checkUrl,
  });
  final String checkUrl;
  final void Function(String) onSelected;
  final void Function(List<EndpointCheck>) onChecks;
  HttpClient? _http;
  int _port = 0;
  String _secret = '', _lastTag = '';
  final Map<String, DateTime> _history = {};
  Timer? _poll;
  bool _polling = false;
  int generation = 0;
  bool get active => _http != null;
  void restore(Map<String, dynamic> connection) {
    final port = connection['port'] as int;
    final secret = connection['secret'] as String;
    if (port < 1 || port > 65535 || secret.length < 32) {
      throw const FormatException('Некорректный канал управления ядром.');
    }
    close();
    _port = port;
    _secret = secret;
    _http = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  }

  Future<String> configure(String config) async {
    close();
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _port = socket.port;
    await socket.close();
    _secret = base64Url.encode(
      List.generate(32, (_) => Random.secure().nextInt(256)),
    );
    _http = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    final json = jsonDecode(config) as Map<String, dynamic>;
    json['experimental'] = {
      'clash_api': {
        'external_controller': '127.0.0.1:$_port',
        'secret': _secret,
        'access_control_allow_origin': ['http://127.0.0.1'],
        'access_control_allow_private_network': false,
      },
    };
    return jsonEncode(json);
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, Object>? body,
    Duration responseTimeout = const Duration(seconds: 8),
  }) async {
    final client = _http;
    if (client == null) throw StateError('Ядро отключено.');
    final uri = Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: _port,
      path: path,
      queryParameters: query,
    );
    final request = await client
        .openUrl(method, uri)
        .timeout(const Duration(seconds: 4));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_secret');
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close().timeout(responseTimeout);
    final text = await utf8.decoder
        .bind(response)
        .join()
        .timeout(const Duration(seconds: 8));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const FormatException('Проверка или команда ядра не выполнена.');
    }
    return text.isEmpty ? {} : jsonDecode(text) as Map<String, dynamic>;
  }

  Future<void> waitReady() async {
    for (var i = 0; i < 40; i++) {
      try {
        await _request('GET', '/version');
        return;
      } catch (_) {
        if (!active) rethrow;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw const FormatException(
      'Локальный канал управления ядром не отвечает.',
    );
  }

  Future<void> select(String tag) async {
    final revision = generation;
    void ensureCurrent() {
      if (generation != revision || !active) {
        throw StateError('Сессия VPN изменилась.');
      }
    }

    if (tag == 'auto') {
      // Сначала обновляем историю каждого профиля, включая удаление старого
      // удачного пинга после отказа. До проверки рабочий выбор не меняется.
      final group = await _request('GET', '/proxies/auto');
      ensureCurrent();
      final tags = (group['all'] as List).cast<String>();
      final results = await check(tags);
      ensureCurrent();
      final available = results
          .where((e) => e.available)
          .map((e) => e.tag)
          .toSet();
      if (available.isEmpty) {
        throw const FormatException(
          'Нет доступных серверов. Автовыбор не включён; предыдущий выбор сохранён.',
        );
      }
      // Проверки отдельных outbound обновляют историю, но сами по себе
      // не пересчитывают выбор URLTest. Запрашиваем пересчёт всей группы.
      await _request(
        'GET',
        '/group/auto/delay',
        query: {'timeout': '5000', 'url': checkUrl},
        responseTimeout: const Duration(seconds: 30),
      );
      ensureCurrent();
      final refreshed = await _request('GET', '/proxies/auto');
      ensureCurrent();
      if (!available.contains(refreshed['now'])) {
        throw const FormatException(
          'Ядро не подтвердило доступный сервер. Предыдущий выбор сохранён. Повторите проверку.',
        );
      }
    }
    ensureCurrent();
    await _request('PUT', '/proxies/proxy', body: {'name': tag});
    ensureCurrent();
    final selected = await _request('GET', '/proxies/proxy');
    if (selected['now'] != tag) {
      throw const FormatException('Ядро не подтвердило выбор сервера.');
    }
    await snapshot();
  }

  Future<List<EndpointCheck>> check(List<String> tags) async {
    final revision = generation;
    final results = <EndpointCheck>[];
    // Не более двух HTTPS-проб одновременно.
    for (var i = 0; i < tags.length; i += 2) {
      if (revision != generation || !active) {
        throw StateError('Сессия VPN изменилась.');
      }
      final batch = await Future.wait(
        tags.skip(i).take(2).map((tag) async {
          try {
            final data = await _request(
              'GET',
              '/proxies/$tag/delay',
              query: {'timeout': '5000', 'url': checkUrl},
            );
            final delay = (data['delay'] as num?)?.toInt();
            if (delay == null || delay <= 0) throw const FormatException();
            return EndpointCheck(
              tag: tag,
              time: DateTime.now(),
              delayMs: delay,
            );
          } catch (_) {
            return EndpointCheck(
              tag: tag,
              time: DateTime.now(),
              error: 'HTTPS-проверка не пройдена. Проверьте профиль, сеть и сервер.',
            );
          }
        }),
      );
      if (revision != generation || !active) {
        throw StateError('Сессия VPN изменилась.');
      }
      results.addAll(batch);
      onChecks(batch);
    }
    return results;
  }

  Future<void> snapshot() async {
    final root = await _request('GET', '/proxies');
    final proxies = root['proxies'] as Map<String, dynamic>;
    var tag = (proxies['proxy'] as Map?)?['now'] as String? ?? '';
    if (tag == 'auto') tag = (proxies['auto'] as Map?)?['now'] as String? ?? '';
    if (tag != _lastTag) {
      _lastTag = tag;
      onSelected(tag);
    }
    final checks = <EndpointCheck>[];
    for (final entry in proxies.entries.where((e) => e.key.startsWith('ep_'))) {
      final history = (entry.value as Map)['history'] as List? ?? const [];
      if (history.isEmpty) {
        if (_history.remove(entry.key) != null) {
          checks.add(
            EndpointCheck(
              tag: entry.key,
              time: DateTime.now(),
              error: 'Последняя проверка ядра не пройдена.',
            ),
          );
        }
        continue;
      }
      final last = history.last as Map;
      final time = DateTime.tryParse('${last['time']}');
      final delay = (last['delay'] as num?)?.toInt();
      if (time != null && delay != null && _history[entry.key] != time) {
        _history[entry.key] = time;
        checks.add(
          delay > 0
              ? EndpointCheck(tag: entry.key, time: time, delayMs: delay)
              : EndpointCheck(
                  tag: entry.key,
                  time: time,
                  error: 'Последняя проверка ядра не пройдена.',
                ),
        );
      }
    }
    if (checks.isNotEmpty) onChecks(checks);
  }

  void startPolling() {
    _poll = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_polling || !active) return;
      _polling = true;
      try {
        await snapshot();
      } catch (_) {
        /* Состояние сервиса поступает отдельно. */
      } finally {
        _polling = false;
      }
    });
    unawaited(snapshot().catchError((Object _) {}));
  }

  void close() {
    generation++;
    _poll?.cancel();
    _poll = null;
    _http?.close(force: true);
    _http = null;
    _lastTag = '';
    _history.clear();
    _secret = '';
  }
}
