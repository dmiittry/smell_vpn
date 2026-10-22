package dev.amirzr.singbox.service

/** Публичный мост без типов libbox в сигнатуре приложения. */
object RuntimeConnection {
    fun currentControl(): Map<String, Any>? = SingboxVPNService.instance?.controlConnection()
}
