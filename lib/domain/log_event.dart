enum EventLevel { success, info, warning, error, debug }

final _ansiEscape = RegExp(r'\x1B\[[0-9;]*[a-zA-Z]');
final _coreHeader = RegExp(
  r'^(?:(?:[+-]\d{4}|\d{4}-\d{2}-\d{2}[T ][0-9:.]+(?:Z|[+-]\d{2}:?\d{2})?)\s+)*'
  r'(?:\[(TRACE|DEBUG|INFO|WARN|WARNING|ERROR|FATAL|PANIC)\]|'
  r'(TRACE|DEBUG|INFO|WARN|WARNING|ERROR|FATAL|PANIC)(?=\s|\[))',
  caseSensitive: false,
);

/// Текстовый заголовок ядра точнее метаданных Android-адаптера.
/// Слова ERROR/NOERROR внутри сообщения не определяют его уровень.
EventLevel coreLogLevel(String message, {required EventLevel fallback}) {
  final match = _coreHeader.firstMatch(
    message.replaceAll(_ansiEscape, '').trimLeft(),
  );
  return switch ((match?.group(1) ?? match?.group(2))?.toUpperCase()) {
    'TRACE' || 'DEBUG' => EventLevel.debug,
    'INFO' => EventLevel.info,
    'WARN' || 'WARNING' => EventLevel.warning,
    'ERROR' || 'FATAL' || 'PANIC' => EventLevel.error,
    _ => fallback,
  };
}

class LogEvent {
  const LogEvent({
    required this.time,
    required this.level,
    required this.source,
    required this.message,
    this.id,
  });
  final DateTime time;
  final EventLevel level;
  final String source, message;
  final String? id;
  LogEvent normalizeCoreLevel() {
    if (source != 'Ядро') return this;
    final corrected = coreLogLevel(message, fallback: level);
    return corrected == level
        ? this
        : LogEvent(
            time: time,
            level: corrected,
            source: source,
            message: message,
            id: id,
          );
  }

  Map<String, String> toJson() => {
    'time': time.toIso8601String(),
    'level': level.name,
    'source': source,
    'message': message,
    'id': ?id,
  };
  factory LogEvent.fromJson(Map<String, dynamic> data) => LogEvent(
    time: DateTime.parse(data['time'] as String),
    level: EventLevel.values.byName(data['level'] as String),
    source: data['source'] as String,
    message: data['message'] as String,
    id: data['id'] as String?,
  );
  String get exportLine =>
      '${time.toIso8601String()} [${level.name.toUpperCase()}] [$source] $message';
}

/// Независимые квоты: сетевой шум не вытесняет историю остановок и ошибок.
List<LogEvent> retainLogs(Iterable<LogEvent> events) {
  var important = 0, routine = 0, debug = 0;
  return events.where((event) {
    if (event.level == EventLevel.debug) return ++debug <= 300;
    if (event.source != 'Ядро' ||
        event.level == EventLevel.error ||
        event.level == EventLevel.warning ||
        event.level == EventLevel.success) {
      return ++important <= 500;
    }
    return ++routine <= 1000;
  }).toList();
}

String redact(String input, [Iterable<String> secrets = const []]) {
  var value = input.replaceAll(_ansiEscape, '');
  value = value.replaceAll(
    RegExp(r'vless://[^\s]+', caseSensitive: false),
    '[конфигурация скрыта]',
  );
  value = value.replaceAll(
    RegExp(
      r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
    ),
    '[UUID скрыт]',
  );
  value = value.replaceAll(RegExp(r'[A-Za-z0-9_-]{43}=?'), '[ключ скрыт]');
  for (final secret in secrets.where((s) => s.length >= 4)) {
    value = value.replaceAll(secret, '[скрыто]');
  }
  return value.length > 1800 ? '${value.substring(0, 1800)}…' : value;
}

String explainFailure(String raw) {
  final text = raw.toLowerCase();
  if (text.contains('permission') ||
      text.contains('access is denied') ||
      text.contains('operation not permitted')) {
    return 'Нет разрешения на VPN. В Windows запустите приложение от имени администратора.';
  }
  if (text.contains('reality') ||
      text.contains('certificate') ||
      text.contains('handshake')) {
    return 'Ошибка Reality/TLS. Проверьте SNI, публичный ключ, Short ID и время на устройстве.';
  }
  if (text.contains('timeout') || text.contains('deadline')) {
    return 'Сервер не отвечает. Проверьте сеть, адрес и порт сервера.';
  }
  if (text.contains('refused')) {
    return 'Сервер отклонил соединение. Проверьте порт и работу VLESS на сервере.';
  }
  if (text.contains('resolve') || text.contains('dns')) {
    return 'Ошибка разрешения имени. Проверьте адрес сервера и DNS.';
  }
  return 'VPN не удалось запустить. Подробности доступны в журнале ошибок.';
}
