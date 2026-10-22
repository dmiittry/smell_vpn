import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../domain/log_event.dart';
import '../domain/routing.dart';
import '../domain/traffic.dart';
import '../services/vpn_engine.dart';
import 'profile_editor.dart';
import 'servers_page.dart';
import 'page_frame.dart';
import 'theme.dart';

class Sme11App extends StatelessWidget {
  const Sme11App({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Sme11_VPN',
    debugShowCheckedModeBanner: false,
    theme: appTheme(),
    home: AppShell(controller: controller),
  );
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller});
  final AppController controller;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int index = 0;
  Timer? ticker;
  bool foreground = true;
  int seconds = 0;
  AppController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!foreground) return;
      if (++seconds % 60 == 0) unawaited(c.checkConnection());
      if ((c.connectedAt != null || c.health.isNotEmpty) && mounted) {
        setState(() {});
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground && !c.connectionVerified) unawaited(c.checkConnection());
    if (state == AppLifecycleState.resumed && index == 2) c.refreshApps();
  }

  void navigate(int next) {
    setState(() => index = next);
    if (next == 2) c.refreshApps();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final wide = MediaQuery.sizeOf(context).width >= 900;
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              if (wide)
                SizedBox(
                  width: 230,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: panel,
                      border: Border(right: BorderSide(color: line)),
                    ),
                    padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const FittedBox(fit: BoxFit.scaleDown, child: Brand()),
                        const SizedBox(height: 52),
                        for (final (i, icon, text) in [
                          (0, Icons.power_settings_new_rounded, 'Подключение'),
                          (1, Icons.dns_outlined, 'Серверы'),
                          (2, Icons.apps_rounded, 'Приложения'),
                          (3, Icons.receipt_long_rounded, 'Логи'),
                        ])
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Material(
                              color: index == i
                                  ? mint.withValues(alpha: .1)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              child: ListTile(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                leading: Icon(
                                  icon,
                                  color: index == i ? mint : muted,
                                  size: 21,
                                ),
                                title: Text(
                                  text,
                                  style: TextStyle(
                                    color: index == i ? mint : muted,
                                    fontSize: 14,
                                  ),
                                ),
                                onTap: () => navigate(i),
                              ),
                            ),
                          ),
                        const Spacer(),
                        const Text(
                          'VLESS / Reality · 0.3.0',
                          style: TextStyle(
                            color: muted,
                            fontSize: 10,
                            letterSpacing: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        wide ? 36 : 22,
                        22,
                        wide ? 36 : 22,
                        18,
                      ),
                      child: Row(
                        children: [
                          if (!wide)
                            const Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Brand(),
                              ),
                            ),
                          const Spacer(),
                          IconButton(
                            tooltip: 'Добавить профиль',
                            onPressed:
                                c.canEdit && c.catalog.profiles.length < 20
                                ? () => editProfile(context, c, add: true)
                                : null,
                            icon: const Icon(Icons.add_rounded),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: IndexedStack(
                        index: index,
                        children: [
                          ConnectionPage(
                            controller: c,
                            onServers: () => navigate(1),
                            onApps: () => navigate(2),
                            onLogs: () => navigate(3),
                          ),
                          ServersPage(controller: c),
                          ApplicationsPage(controller: c),
                          LogsPage(controller: c),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: index,
                onDestinationSelected: navigate,
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.power_settings_new_rounded),
                    label: 'VPN',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.dns_outlined),
                    label: 'Серверы',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.apps_rounded),
                    label: 'Приложения',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.receipt_long_rounded),
                    label: 'Логи',
                  ),
                ],
              ),
      );
    },
  );
  @override
  void dispose() {
    ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class Brand extends StatelessWidget {
  const Brand({super.key});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: mint,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.shield_outlined, color: canvas, size: 21),
      ),
      const SizedBox(width: 10),
      const Text(
        'Sme11',
        style: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: -.6,
        ),
      ),
      const Text(
        '_VPN',
        style: TextStyle(
          color: mint,
          fontSize: 19,
          fontWeight: FontWeight.w500,
          letterSpacing: -.6,
        ),
      ),
    ],
  );
}

class ConnectionPage extends StatelessWidget {
  const ConnectionPage({
    super.key,
    required this.controller,
    required this.onApps,
    required this.onLogs,
    required this.onServers,
  });
  final AppController controller;
  final VoidCallback onApps, onLogs, onServers;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final running = c.state == TunnelState.running;
    final failed =
        c.state == TunnelState.failed ||
        (running && c.connectionCheck?.available == false);
    final color = failed
        ? failure
        : c.connectionVerified
        ? success
        : muted;
    final title = switch (c.state) {
      TunnelState.connecting => 'Подключение…',
      TunnelState.disconnecting => 'Отключение…',
      TunnelState.failed => 'Ошибка подключения',
      TunnelState.disconnected => 'Нажмите для подключения',
      TunnelState.running =>
        failed
            ? 'Проверка не пройдена'
            : c.connectionVerified
            ? 'Подключено'
            : 'Проверка соединения…',
    };
    final error = c.state == TunnelState.failed
        ? c.lastError ?? 'Не удалось запустить VPN. Подробности в логах.'
        : failed
        ? c.connectionCheck?.error ?? 'Сервер не отвечает.'
        : null;

    Future<void> toggle() async {
      if (running) {
        await c.disconnect();
      } else if (c.profile == null) {
        await editProfile(context, c, add: true);
      } else if (c.mode == RoutingMode.selected && c.selected.isEmpty) {
        onApps();
      } else {
        await c.connect();
      }
    }

    return LayoutBuilder(
      builder: (context, bounds) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 520,
                minHeight: (bounds.maxHeight - 36).clamp(0, double.infinity),
              ),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton(
                      onPressed: c.profile == null
                          ? (c.canEdit
                                ? () => editProfile(context, c, add: true)
                                : null)
                          : onServers,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 18,
                        ),
                        side: const BorderSide(color: muted),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.dns_outlined,
                            color: muted,
                            size: 21,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              c.profile == null
                                  ? 'Добавить сервер'
                                  : '${c.catalog.automatic ? 'Авто · ' : ''}${c.currentProfileName}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            c.profile == null
                                ? Icons.add_rounded
                                : Icons.expand_more_rounded,
                            color: muted,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 36),
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Semantics(
                              label: running ? 'Отключить VPN' : 'Включить VPN',
                              button: true,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    if (failed || c.connectionVerified)
                                      BoxShadow(
                                        color: color.withValues(alpha: .16),
                                        blurRadius: 48,
                                        spreadRadius: 6,
                                      ),
                                  ],
                                ),
                                child: Material(
                                  color: const Color(0xFFF5F7FA),
                                  shape: const CircleBorder(),
                                  clipBehavior: Clip.antiAlias,
                                  child: InkWell(
                                    customBorder: const CircleBorder(),
                                    onTap: c.busy || !c.initialized
                                        ? null
                                        : toggle,
                                    child: SizedBox(
                                      width: 184,
                                      height: 184,
                                      child: c.busy
                                          ? const Center(
                                              child: SizedBox(
                                                width: 40,
                                                height: 40,
                                                child:
                                                    CircularProgressIndicator(
                                                      color: muted,
                                                    ),
                                              ),
                                            )
                                          : Icon(
                                              Icons.power_settings_new_rounded,
                                              size: 88,
                                              color: color,
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 28),
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                title,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w500,
                                  color: failed || c.connectionVerified
                                      ? color
                                      : Colors.white,
                                ),
                              ),
                            ),
                            if (running) ...[
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.network_ping_rounded,
                                    size: 21,
                                    color: color,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    c.connectionVerified
                                        ? '${c.connectionCheck!.delayMs} мс'
                                        : failed
                                        ? 'Пинг недоступен'
                                        : 'Пинг: проверяем…',
                                    style: TextStyle(
                                      fontSize: 17,
                                      color: color,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Обновить пинг (HTTPS)',
                                    onPressed: c.verifyingConnection || c.busy
                                        ? null
                                        : c.checkConnection,
                                    icon: const Icon(
                                      Icons.refresh_rounded,
                                      size: 19,
                                    ),
                                    color: muted,
                                  ),
                                ],
                              ),
                            ],
                            if (error != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                error,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: failure),
                              ),
                              TextButton.icon(
                                onPressed: onLogs,
                                icon: const Icon(
                                  Icons.receipt_long_outlined,
                                  size: 18,
                                ),
                                label: const Text('Открыть логи'),
                              ),
                            ],
                            if (c.profile == null) ...[
                              const SizedBox(height: 10),
                              const Text(
                                'Из буфера обмена или вручную',
                                style: TextStyle(color: muted),
                                textAlign: TextAlign.center,
                              ),
                            ],
                            const SizedBox(height: 36),
                          ],
                        ),
                      ),
                    ),
                    if (running && !Platform.isWindows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          '↓ ${trafficSpeed(c.downloadBps)}     ↑ ${trafficSpeed(c.uploadBps)}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: muted),
                        ),
                      ),
                    TextButton.icon(
                      onPressed: onApps,
                      icon: const Icon(
                        Icons.alt_route_rounded,
                        size: 18,
                        color: muted,
                      ),
                      label: Text(
                        c.mode == RoutingMode.all
                            ? 'Все приложения'
                            : 'Через VPN: ${c.selected.length} приложений',
                        style: const TextStyle(color: muted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class ApplicationsPage extends StatefulWidget {
  const ApplicationsPage({super.key, required this.controller});
  final AppController controller;
  @override
  State<ApplicationsPage> createState() => _ApplicationsPageState();
}

class _ApplicationsPageState extends State<ApplicationsPage> {
  String query = '';
  bool saving = false;
  String? error;
  AppController get c => widget.controller;
  Future<void> configure({RoutingMode? mode, List<RoutedApp>? apps}) async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await c.configure(routingMode: mode, apps: apps);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Не удалось сохранить выбор приложений.');
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> addExe() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['exe'],
        dialogTitle: 'Выберите приложение для VPN',
      );
      if (result == null) return;
      final file = result.files.single;
      if (file.path == null || !file.path!.toLowerCase().endsWith('.exe')) {
        return;
      }
      final app = RoutedApp(
        id: file.path!,
        name: file.name.replaceAll(RegExp(r'\.exe$', caseSensitive: false), ''),
      );
      if (!c.selected.any((e) => e.id.toLowerCase() == app.id.toLowerCase())) {
        await configure(apps: [...c.selected, app]);
      }
      await c.refreshApps();
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Не удалось открыть файл приложения.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final apps = c.available
        .where(
          (e) =>
              '${e.name} ${e.id}'.toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
    return PageFrame(
      children: [
        Text('Маршрутизация', style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 8),
        const Text(
          'Решите, какие приложения используют VPN.',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 28),
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Режим подключения',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              SegmentedButton<RoutingMode>(
                segments: const [
                  ButtonSegment(
                    value: RoutingMode.selected,
                    label: Text('Выбранные'),
                    icon: Icon(Icons.checklist_rounded, size: 18),
                  ),
                  ButtonSegment(
                    value: RoutingMode.all,
                    label: Text('Все'),
                    icon: Icon(Icons.public_rounded, size: 18),
                  ),
                ],
                selected: {c.mode},
                onSelectionChanged: c.canEdit && !saving
                    ? (set) => configure(mode: set.first)
                    : null,
              ),
              const SizedBox(height: 14),
              Text(
                c.mode == RoutingMode.selected
                    ? 'Только выбранные приложения через VPN. Остальные — напрямую.'
                    : 'Все приложения будут использовать VPN.',
                style: const TextStyle(color: muted),
              ),
              if (!c.canEdit)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Чтобы изменить маршрут, сначала отключите VPN.',
                    style: TextStyle(color: amber),
                  ),
                ),
              if (Platform.isWindows)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'В Windows правила применяются к EXE. Добавьте вспомогательные процессы приложения, если они используют сеть. DNS в режиме выбора остаётся системным.',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (error != null) ...[ErrorNotice(error!), const SizedBox(height: 16)],
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StatusPill('ВЫБРАНО: ${c.selected.length}'),
            OutlinedButton.icon(
              onPressed: c.loadingApps ? null : c.refreshApps,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Обновить'),
            ),
            if (Platform.isWindows)
              OutlinedButton.icon(
                onPressed: c.canEdit && !saving ? addExe : null,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Добавить EXE'),
              ),
          ],
        ),
        const SizedBox(height: 18),
        TextField(
          onChanged: (value) => setState(() => query = value),
          decoration: const InputDecoration(
            hintText: 'Найти приложение',
            prefixIcon: Icon(Icons.search_rounded),
          ),
        ),
        const SizedBox(height: 18),
        if (c.loadingApps) const LinearProgressIndicator(minHeight: 2),
        if (apps.isEmpty && !c.loadingApps)
          Surface(
            child: SizedBox(
              width: double.infinity,
              child: Column(
                children: [
                  const Icon(Icons.apps_rounded, size: 36, color: muted),
                  const SizedBox(height: 14),
                  Text(
                    query.isNotEmpty
                        ? 'Ничего не найдено'
                        : 'Обновите список приложений',
                  ),
                  const SizedBox(height: 6),
                  Text(
                    Platform.isWindows
                        ? 'Показываются запущенные программы. Любую другую можно добавить через EXE.'
                        : 'Здесь появятся установленные приложения с иконкой запуска.',
                    style: const TextStyle(color: muted),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        if (apps.isNotEmpty)
          Surface(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                for (final app in apps)
                  SwitchListTile(
                    secondary: AppAvatar(app.name),
                    title: Text(app.name),
                    subtitle: Text(
                      app.id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: muted, fontSize: 11),
                    ),
                    value: c.selected.any((e) => e.id == app.id),
                    onChanged:
                        c.canEdit && !saving && c.mode == RoutingMode.selected
                        ? (value) => configure(
                            apps: value
                                ? [...c.selected, app]
                                : c.selected
                                      .where((e) => e.id != app.id)
                                      .toList(),
                          )
                        : null,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class AppAvatar extends StatelessWidget {
  const AppAvatar(this.name, {super.key});
  final String name;
  @override
  Widget build(BuildContext context) => Container(
    width: 42,
    height: 42,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: mint.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      name.isEmpty ? '?' : name.characters.first.toUpperCase(),
      style: const TextStyle(
        color: mint,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class LogsPage extends StatefulWidget {
  const LogsPage({super.key, required this.controller});
  final AppController controller;
  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  EventLevel? filter;
  String query = '';
  bool newestFirst = true;
  AppController get c => widget.controller;
  static const labels = {
    EventLevel.success: 'Успешные',
    EventLevel.info: 'События',
    EventLevel.warning: 'Предупреждения',
    EventLevel.error: 'Ошибки',
    EventLevel.debug: 'Диагностика',
  };
  static const colors = {
    EventLevel.success: success,
    EventLevel.info: muted,
    EventLevel.warning: amber,
    EventLevel.error: failure,
    EventLevel.debug: Color(0xFFA6ACFF),
  };
  List<LogEvent> get visible {
    final events = c.logs
        .where(
          (e) =>
              (filter == null || e.level == filter) &&
              '${e.message} ${e.source}'.toLowerCase().contains(
                query.toLowerCase(),
              ),
        )
        .toList();
    return newestFirst ? events : events.reversed.toList();
  }

  Future<void> export() async {
    try {
      await c.flushLogs();
      final text = c.exportLogs(visible);
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Экспорт журнала',
        fileName: 'Sme11_VPN_logs.txt',
        type: FileType.custom,
        allowedExtensions: ['txt'],
        bytes: Uint8List.fromList(utf8.encode(text)),
      );
      if (path != null && Platform.isWindows) {
        await File(path).writeAsString(text);
      }
      if (mounted && path != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Журнал сохранён.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Не удалось сохранить журнал. Можно скопировать его.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final events = visible;
    return PageFrame(
      children: [
        Text('Журнал', style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 8),
        const Text(
          'События, ошибки и причины остановки — в одном месте.',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 26),
        Surface(
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.bug_report_outlined, color: amber),
            title: const Text('Подробная диагностика'),
            subtitle: Text(
              c.canEdit
                  ? 'Больше деталей ядра со следующего подключения'
                  : 'Для изменения сначала отключите VPN',
            ),
            value: c.diagnostic,
            onChanged: c.canEdit
                ? (v) async {
                    try {
                      await c.configure(debug: v);
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Настройка не сохранена.'),
                          ),
                        );
                      }
                    }
                  }
                : null,
          ),
        ),
        const SizedBox(height: 20),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text('Все · ${c.logs.length}'),
                  selected: filter == null,
                  onSelected: (_) => setState(() => filter = null),
                ),
              ),
              for (final level in EventLevel.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(
                      '${labels[level]} · ${c.logs.where((e) => e.level == level).length}',
                    ),
                    selected: filter == level,
                    onSelected: (_) => setState(() => filter = level),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          onChanged: (value) => setState(() => query = value),
          decoration: const InputDecoration(
            hintText: 'Поиск в журнале',
            prefixIcon: Icon(Icons.search_rounded),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton.icon(
              onPressed: () => setState(() => newestFirst = !newestFirst),
              icon: const Icon(Icons.swap_vert_rounded, size: 18),
              label: Text(newestFirst ? 'Сначала новые' : 'Сначала старые'),
            ),
            TextButton.icon(
              onPressed: events.isEmpty ? null : export,
              icon: const Icon(Icons.ios_share_rounded, size: 18),
              label: const Text('Экспорт'),
            ),
            IconButton(
              onPressed: events.isEmpty
                  ? null
                  : () async {
                      await Clipboard.setData(
                        ClipboardData(text: c.exportLogs(events)),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Отфильтрованные логи скопированы.'),
                          ),
                        );
                      }
                    },
              icon: const Icon(Icons.copy_all_outlined),
              tooltip: 'Скопировать отфильтрованные логи',
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (events.isEmpty)
          const Surface(
            child: SizedBox(
              width: double.infinity,
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Событий с такими фильтрами пока нет.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted),
                ),
              ),
            ),
          ),
        for (final event in events)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Surface(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        labels[event.level]!,
                        style: TextStyle(
                          color: colors[event.level],
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        event.source,
                        style: const TextStyle(fontSize: 11, color: muted),
                      ),
                      Text(
                        '${event.time.day.toString().padLeft(2, '0')}.${event.time.month.toString().padLeft(2, '0')} ${event.time.hour.toString().padLeft(2, '0')}:${event.time.minute.toString().padLeft(2, '0')}:${event.time.second.toString().padLeft(2, '0')}',
                        style: const TextStyle(color: muted, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    event.message,
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 14),
        const Text(
          'Храним отдельно 500 важных событий, 1000 сетевых записей и 300 подробных. UUID и ключи скрываются перед записью. Журнал может содержать адреса посещённых сайтов.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
      ],
    );
  }
}
