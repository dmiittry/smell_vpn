import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sme11_vpn/domain/profile.dart';
import 'package:sme11_vpn/domain/config_builder.dart';
import 'package:sme11_vpn/domain/routing.dart';
import 'package:sme11_vpn/domain/log_event.dart';

String get key =>
    base64Url.encode(List.generate(32, (i) => i + 1)).replaceAll('=', '');
String get link =>
    'vless://00000000-0000-4000-8000-000000000001@vpn.example.com:443?security=reality&type=tcp&sni=example.com&pbk=$key&sid=aabb&flow=xtls-rprx-vision#Test';

void main() {
  test('Заголовок ядра исправляет ошибочный уровень Android-адаптера', () {
    const samples = {
      'TRACE[0014] outbound/vless[proxy]: XtlsPadding 64 142 0':
          EventLevel.debug,
      'DEBUG[0013] router: match[0] => sniff': EventLevel.debug,
      'INFO[0012] dns: exchanged example.com NOERROR': EventLevel.info,
      'WARN[0001] connection slow': EventLevel.warning,
      'ERROR[0001] dial: timeout': EventLevel.error,
      '[FATAL] service stopped': EventLevel.error,
      'PANIC[0001] runtime error': EventLevel.error,
      '\x1b[31mINFO\x1b[0m[0014] ready': EventLevel.info,
      '+0900 2026-10-06 19:59:20 INFO[0014] ready': EventLevel.info,
    };
    for (final entry in samples.entries) {
      expect(coreLogLevel(entry.key, fallback: EventLevel.error), entry.value);
    }
  });
  test('Уровень не определяется словом ERROR внутри обычного сообщения', () {
    expect(
      coreLogLevel(
        'INFO[0012] dns: NOERROR, ERROR is just text',
        fallback: EventLevel.error,
      ),
      EventLevel.info,
    );
    expect(
      coreLogLevel('service fault', fallback: EventLevel.error),
      EventLevel.error,
    );
    expect(
      coreLogLevel('outbound: ERROR in payload', fallback: EventLevel.info),
      EventLevel.info,
    );
  });
  test(
    'Импорт VLESS/Reality сохраняет параметры и проходит JSON roundtrip',
    () {
      final p = VpnProfile.fromUri(link);
      expect(p.publicKey, key);
      expect(p.shortId, 'aabb');
      expect(p.flow, 'xtls-rprx-vision');
      expect(VpnProfile.fromJson(p.toJson()).toJson(), p.toJson());
    },
  );
  test('Чужие протоколы, TLS без Reality и неподдерживаемые транспорты отклоняются', () {
    for (final invalid in [
      link.replaceFirst('vless:', 'vmess:'),
      link.replaceFirst('security=reality', 'security=tls'),
      link.replaceFirst('type=tcp', 'type=ws'),
      link.replaceFirst('sid=aabb', 'sid=abc'),
      link.replaceFirst(key, 'wrong'),
      '$link\nvless://something',
      link.replaceFirst('type=tcp', 'type=tcp&type=raw'),
      link.replaceFirst('type=tcp', 'type=tcp&mux=true'),
    ]) {
      expect(
        () => VpnProfile.fromUri(invalid),
        throwsFormatException,
        reason: 'Некорректная конфигурация должна отклоняться',
      );
    }
  });
  test('Пустой выбор никогда не превращается в VPN для всех приложений', () {
    expect(
      () => ConfigBuilder.build(
        VpnProfile.fromUri(link),
        windows: false,
        mode: RoutingMode.selected,
        applications: [],
      ),
      throwsFormatException,
    );
  });
  test('Windows направляет выбранные EXE в proxy, остальные в direct', () {
    final config = ConfigBuilder.build(
      VpnProfile.fromUri(link),
      windows: true,
      mode: RoutingMode.selected,
      applications: [r'C:\Example\browser.exe'],
    );
    final route = config['route'] as Map;
    expect(route['final'], 'direct');
    final rules = route['rules'] as List;
    expect(rules.last['process_path'], [r'C:\Example\browser.exe']);
    expect(rules.last['outbound'], 'proxy');
    expect((config['dns'] as Map)['final'], 'dns-direct');
  });
  test('Режим всех приложений и Android используют proxy по умолчанию', () {
    for (final windows in [false, true]) {
      final c = ConfigBuilder.build(
        VpnProfile.fromUri(link),
        windows: windows,
        mode: RoutingMode.all,
        applications: [],
      );
      expect((c['route'] as Map)['final'], 'proxy');
      expect((c['dns'] as Map)['final'], 'dns-proxy');
      expect(
        ((c['outbounds'] as List).first as Map)['tls']['reality']['enabled'],
        true,
      );
    }
  });
  test(
    'Логи скрывают UUID, VLESS-ссылку, публичный ключ и известные секреты',
    () {
      final result = redact(
        'UUID 00000000-0000-4000-8000-000000000001 $key $link secret123',
        ['secret123'],
      );
      expect(result, isNot(contains('00000000-0000')));
      expect(result, isNot(contains(key)));
      expect(result, isNot(contains('vless://')));
      expect(result, isNot(contains('secret123')));
    },
  );
}
