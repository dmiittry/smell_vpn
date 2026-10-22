import 'dart:convert';

/// Поддерживаем намеренно только VLESS + Reality поверх TCP.
class VpnProfile {
  const VpnProfile({
    required this.name,
    required this.host,
    required this.port,
    required this.uuid,
    required this.serverName,
    required this.publicKey,
    this.shortId = '',
    this.fingerprint = 'chrome',
    this.flow = 'xtls-rprx-vision',
  });

  final String name,
      host,
      uuid,
      serverName,
      publicKey,
      shortId,
      fingerprint,
      flow;
  final int port;

  static const fingerprints = [
    'chrome',
    'firefox',
    'safari',
    'edge',
    'ios',
    'android',
    'random',
    'randomized',
  ];
  static bool validHost(String value) =>
      value.isNotEmpty &&
      !RegExp(r'[\s/@?#]').hasMatch(value) &&
      value.length <= 253;

  void validate() {
    if (name.trim().isEmpty || name.length > 80) {
      throw const FormatException(
        'Название должно содержать от 1 до 80 символов.',
      );
    }
    if (!validHost(host)) {
      throw const FormatException(
        'Укажите адрес сервера без протокола и пути.',
      );
    }
    if (port < 1 || port > 65535) {
      throw const FormatException('Порт должен быть от 1 до 65535.');
    }
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(uuid)) {
      throw const FormatException('Некорректный UUID пользователя.');
    }
    if (!validHost(serverName) || serverName.contains(':')) {
      throw const FormatException(
        'Укажите домен SNI, настроенный на сервере Reality.',
      );
    }
    try {
      if (base64Url.decode(base64Url.normalize(publicKey)).length != 32 ||
          !RegExp(r'^[A-Za-z0-9_-]{43}=?$').hasMatch(publicKey)) {
        throw const FormatException();
      }
    } catch (_) {
      throw const FormatException(
        'Публичный ключ Reality должен быть ключом X25519 (32 байта, base64url).',
      );
    }
    if (!RegExp(r'^(?:[0-9a-fA-F]{2}){0,8}$').hasMatch(shortId)) {
      throw const FormatException(
        'Short ID: от 0 до 16 шестнадцатеричных символов, длина чётная.',
      );
    }
    if (!fingerprints.contains(fingerprint)) {
      throw const FormatException('Неподдерживаемый fingerprint.');
    }
    if (flow != '' && flow != 'xtls-rprx-vision') {
      throw const FormatException(
        'Поддерживается flow xtls-rprx-vision или пустой.',
      );
    }
  }

  factory VpnProfile.fromUri(String text) {
    if (text.trim().contains('\n') || text.trim().contains('\r')) {
      throw const FormatException(
        'Вставьте одну конфигурацию, без переносов строк.',
      );
    }
    if (text.length > 8192) {
      throw const FormatException('Конфигурация слишком длинная.');
    }
    final uri = Uri.tryParse(text.trim());
    if (uri == null ||
        uri.scheme != 'vless' ||
        uri.host.isEmpty ||
        !uri.hasPort) {
      throw const FormatException(
        'Вставьте одну конфигурацию vless:// из буфера.',
      );
    }
    final q = uri.queryParameters;
    if (q['security'] != 'reality') {
      throw const FormatException(
        'Поддерживается только VLESS с security=reality.',
      );
    }
    if (!['tcp', 'raw'].contains(q['type'] ?? 'tcp')) {
      throw const FormatException(
        'В этой версии поддерживается Reality поверх TCP (type=tcp/raw).',
      );
    }
    if ((q['encryption'] ?? 'none') != 'none') {
      throw const FormatException('VLESS encryption должен быть none.');
    }
    const supported = {
      'security',
      'type',
      'encryption',
      'sni',
      'serverName',
      'pbk',
      'sid',
      'fp',
      'flow',
      'spx',
      'headerType',
    };
    if (q.keys.any((key) => !supported.contains(key)) ||
        ((q['headerType'] ?? 'none') != 'none') ||
        uri.queryParametersAll.values.any((values) => values.length != 1)) {
      throw const FormatException(
        'Конфигурация содержит неподдерживаемые или повторяющиеся параметры. Используйте ручной ввод.',
      );
    }
    final profile = VpnProfile(
      name: uri.fragment.isEmpty
          ? 'Мой сервер'
          : Uri.decodeComponent(uri.fragment),
      host: uri.host,
      port: uri.port,
      uuid: Uri.decodeComponent(uri.userInfo),
      serverName: q['sni'] ?? q['serverName'] ?? '',
      publicKey: q['pbk'] ?? '',
      shortId: q['sid'] ?? '',
      fingerprint: q['fp'] ?? 'chrome',
      flow: q['flow'] ?? '',
    );
    profile.validate();
    return profile;
  }

  Map<String, Object> toJson() => {
    'name': name,
    'host': host,
    'port': port,
    'uuid': uuid,
    'serverName': serverName,
    'publicKey': publicKey,
    'shortId': shortId,
    'fingerprint': fingerprint,
    'flow': flow,
  };

  factory VpnProfile.fromJson(Map<String, dynamic> map) {
    final profile = VpnProfile(
      name: map['name'] as String,
      host: map['host'] as String,
      port: map['port'] as int,
      uuid: map['uuid'] as String,
      serverName: map['serverName'] as String,
      publicKey: map['publicKey'] as String,
      shortId: map['shortId'] as String,
      fingerprint: map['fingerprint'] as String,
      flow: map['flow'] as String,
    );
    profile.validate();
    return profile;
  }
}
