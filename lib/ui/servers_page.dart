import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../domain/profile_catalog.dart';
import '../services/vpn_engine.dart';
import 'page_frame.dart';
import 'profile_editor.dart';
import 'theme.dart';

class ServersPage extends StatefulWidget {
  const ServersPage({super.key, required this.controller});
  final AppController controller;
  @override
  State<ServersPage> createState() => _ServersPageState();
}

class _ServersPageState extends State<ServersPage> {
  AppController get c => widget.controller;
  String? error;

  Future<void> choose({String? id, required bool automatic}) async {
    if (c.state == TunnelState.running) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Переключить сервер?'),
          content: const Text(
            'Открытые соединения могут прерваться. Приложения установят их заново через выбранный сервер.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Переключить'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    if (!mounted) return;
    setState(() => error = null);
    try {
      await c.chooseServer(id: id, automatic: automatic);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Сервер не удалось выбрать. Подробности в логах.',
        );
      }
    }
  }

  String healthText(SavedProfile entry) {
    if (c.checking) return 'Проверяем…';
    final result = c.health[entry.tag];
    if (result == null) return 'Не проверен';
    final age = DateTime.now()
        .difference(result.time)
        .inSeconds
        .clamp(0, 999999);
    final value = result.available
        ? 'HTTPS доступен · ${result.delayMs} мс'
        : result.error ?? 'HTTPS-проверка не пройдена';
    return '$value · ${age < 60 ? '$age с' : '${age ~/ 60} мин'} назад${result.fresh ? '' : ' · обновите'}';
  }

  Widget server(SavedProfile entry) {
    final selected = !c.catalog.automatic && entry.id == c.catalog.selectedId;
    final active = c.state == TunnelState.running && entry.tag == c.activeTag;
    final result = c.health[entry.tag];
    final color = result == null || !result.fresh
        ? muted
        : result.available
        ? success
        : failure;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  active ? Icons.bolt_rounded : Icons.dns_outlined,
                  color: active ? mint : muted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    entry.profile.name,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: c.canEdit
                      ? () => editProfile(context, c, entry: entry)
                      : null,
                  tooltip: 'Изменить профиль',
                  icon: const Icon(Icons.edit_outlined, size: 19),
                ),
              ],
            ),
            Text(
              '${entry.profile.host}:${entry.profile.port}',
              style: const TextStyle(color: muted),
            ),
            const SizedBox(height: 12),
            Text(
              healthText(entry),
              style: TextStyle(color: color, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (active) const StatusPill('АКТИВНЫЙ'),
                if (selected) const StatusPill('ВЫБРАН', color: muted),
                OutlinedButton.icon(
                  onPressed: c.busy || selected
                      ? null
                      : () => choose(id: entry.id, automatic: false),
                  icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                  label: Text(
                    c.state == TunnelState.running ? 'Переключить' : 'Выбрать',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    children: [
      Text('Серверы', style: Theme.of(context).textTheme.headlineLarge),
      const SizedBox(height: 24),
      if (error != null) ...[ErrorNotice(error!), const SizedBox(height: 16)],
      if (!c.catalogReadable) ...[
        const ErrorNotice(
          'Каталог не удалось прочитать. Запись заблокирована, чтобы сохранить ваши профили. Подробности в логах.',
        ),
        const SizedBox(height: 16),
      ],
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          FilledButton.icon(
            onPressed: c.canEdit && c.catalog.profiles.length < 20
                ? () => editProfile(context, c, add: true)
                : null,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Добавить профиль'),
          ),
          OutlinedButton.icon(
            onPressed: !c.busy && c.catalog.profiles.isNotEmpty
                ? c.checkServers
                : null,
            icon: const Icon(Icons.network_check_rounded),
            label: Text(c.checking ? 'Проверяем…' : 'Проверить серверы'),
          ),
        ],
      ),
      const SizedBox(height: 18),
      Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Автовыбор по задержке'),
              value: c.catalog.automatic,
              onChanged: c.busy || c.catalog.profiles.isEmpty
                  ? null
                  : (value) => choose(automatic: value),
            ),
            const Text(
              'Проверка раз в минуту. При сбое ядро выбирает доступный профиль. Меньшая задержка не гарантирует большую скорость; переключение может прервать соединения.',
              style: TextStyle(color: muted, fontSize: 13),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      if (c.catalog.profiles.isEmpty)
        const Text(
          'Добавьте первый профиль из буфера обмена или вручную.',
          style: TextStyle(color: muted),
        ),
      for (final entry in c.catalog.profiles) server(entry),
      const SizedBox(height: 12),
      const Text(
        'HTTPS-проба идёт через конкретный профиль к gstatic.com и расходует немного трафика. Результат показывает доступность в момент проверки. При отказе всех профилей VPN-трафик не переводится напрямую.',
        style: TextStyle(color: muted, fontSize: 12),
      ),
      if (Platform.isAndroid) ...[
        const SizedBox(height: 18),
        TextButton.icon(
          icon: const Icon(Icons.notifications_outlined),
          label: const Text('Уведомление VPN и скорость'),
          onPressed: () async {
            try {
              await const MethodChannel('sme11_vpn/apps')
                  .invokeMethod<void>('notificationSettings');
            } catch (_) {
              if (mounted) {
                setState(
                  () => error =
                      'Не удалось открыть настройки уведомлений Android.',
                );
              }
            }
          },
        ),
      ],
    ],
  );
}
