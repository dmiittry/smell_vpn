package dev.amirzr.singbox.service

import org.junit.Assert.assertEquals
import org.junit.Test

class TrafficFormatTest {
    @Test fun countersAreBytesAndNotificationShowsBits() {
        assertEquals("0 кбит/с", ServiceNotificationHelper.formatBps(0))
        assertEquals("0 кбит/с", ServiceNotificationHelper.formatBps(-1))
        assertEquals("840 кбит/с", ServiceNotificationHelper.formatBps(105000))
        assertEquals("10.0 Мбит/с", ServiceNotificationHelper.formatBps(1250000))
    }
}
