package dev.amirzr.singbox.service

/** Без адресов, UUID, ключей и произвольных текстов ядра для независимого журнала. */
internal object CoreLogSummary {
    private val ansi = Regex("\\u001B\\[[0-9;]*[a-zA-Z]")
    private val header = Regex(
        "^(?:(?:[+-]\\d{4}|\\d{4}-\\d{2}-\\d{2}[T ][0-9:.]+(?:Z|[+-]\\d{2}:?\\d{2})?)\\s+)*" +
        "(?:\\[(TRACE|DEBUG|INFO|WARN|WARNING|ERROR|FATAL|PANIC)\\]|" +
        "(TRACE|DEBUG|INFO|WARN|WARNING|ERROR|FATAL|PANIC)(?=\\s|\\[))", RegexOption.IGNORE_CASE)

    fun from(message: String): Pair<String, String>? {
        val text = message.replace(ansi, "").trimStart()
        val match = header.find(text) ?: return null
        val level = match.groupValues.drop(1).firstOrNull { it.isNotEmpty() }?.uppercase()
        if (level !in setOf("WARN", "WARNING", "ERROR", "FATAL", "PANIC")) return null
        val lower = text.lowercase()
        val reason = when {
            level == "FATAL" || level == "PANIC" -> "Критическая ошибка ядра."
            "timeout" in lower || "deadline" in lower -> "Ядро: тайм-аут сетевой операции."
            "reality" in lower || "handshake" in lower || "certificate" in lower -> "Ядро: ошибка Reality/TLS."
            "unreachable" in lower || "no route" in lower -> "Ядро: сеть или маршрут недоступны."
            "reset by peer" in lower || "refused" in lower -> "Ядро: удалённая сторона сбросила или отклонила соединение."
            "dns" in lower || "resolve" in lower -> "Ядро: ошибка разрешения имени."
            else -> "Ядро сообщило предупреждение или ошибку."
        }
        return (if (level == "WARN" || level == "WARNING") "warning" else "error") to
            "$reason Это событие само по себе не подтверждает остановку VPN-сервиса."
    }
}
