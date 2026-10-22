package dev.amirzr.singbox.service

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertFalse
import org.junit.Test

class RuntimeDiagnosticsTest {
    @Test fun distinguishesNativeCrashMemoryAndUnknownReason() {
        assertEquals("сбой нативного кода", RuntimeDiagnostics.exitReason(5))
        assertEquals("нехватка памяти", RuntimeDiagnostics.exitReason(3))
        assertEquals("причина не уточнена системой", RuntimeDiagnostics.exitReason(0))
        assertEquals("причина не уточнена системой", RuntimeDiagnostics.exitReason(999))
    }
    @Test fun persistsOnlyRealWarningsAndRedactsAllFreeText() {
        assertNull(CoreLogSummary.from("INFO[0010] dns: exchanged NOERROR example.com"))
        assertNull(CoreLogSummary.from("TRACE[0010] connection upload closed"))
        val summary = CoreLogSummary.from("+0900 2026-10-15T10:00:00 ERROR[0010] dial timeout secret.example:443 vless://test")!!
        assertEquals("error", summary.first)
        assertFalse(summary.second.contains("secret.example"))
        assertFalse(summary.second.contains("vless://"))
    }
}
