import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../domain/profile.dart';
import '../domain/profile_catalog.dart';
import 'theme.dart';

Future<void> editProfile(
  BuildContext context,
  AppController controller, {
  SavedProfile? entry,
  bool add = false,
}) => showDialog<void>(
  context: context,
  builder: (_) => ProfileEditor(
    controller: controller,
    entry: entry ?? (add ? null : controller.catalog.selected),
  ),
);

class ProfileEditor extends StatefulWidget {
  const ProfileEditor({super.key, required this.controller, this.entry});
  final AppController controller;
  final SavedProfile? entry;
  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  final fields = <String, TextEditingController>{
    for (final key in [
      'name',
      'host',
      'port',
      'uuid',
      'serverName',
      'publicKey',
      'shortId',
    ])
      key: TextEditingController(),
  };
  String fingerprint = 'chrome';
  bool vision = true, visible = false, saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    fields['name']!.text = 'Мой сервер';
    fields['port']!.text = '443';
    if (widget.entry != null) fill(widget.entry!.profile);
  }

  void fill(VpnProfile profile) {
    final data = profile.toJson();
    for (final entry in fields.entries) {
      entry.value.text = '${data[entry.key]}';
    }
    fingerprint = profile.fingerprint;
    vision = profile.flow.isNotEmpty;
  }

  Future<void> paste() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final profile = VpnProfile.fromUri(data?.text ?? '');
      if (!mounted) return;
      setState(() {
        fill(profile);
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(
        () => error = e is FormatException
            ? e.message
            : 'Не удалось прочитать буфер обмена.',
      );
    }
  }

  Future<void> save() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      String value(String key) => fields[key]!.text.trim();
      final profile = VpnProfile(
        name: value('name'),
        host: value('host'),
        port: int.tryParse(value('port')) ?? 0,
        uuid: value('uuid'),
        serverName: value('serverName'),
        publicKey: value('publicKey'),
        shortId: value('shortId'),
        fingerprint: fingerprint,
        flow: vision ? 'xtls-rprx-vision' : '',
      );
      await widget.controller.saveProfile(profile, id: widget.entry?.id);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e is FormatException
              ? e.message
              : 'Не удалось сохранить профиль в защищённом хранилище.';
          saving = false;
        });
      }
    }
  }

  Widget field(
    String key,
    String label, {
    bool secret = false,
    String? hint,
    bool numeric = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextField(
      controller: fields[key],
      enabled: !saving,
      obscureText: secret && !visible,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: numeric ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(labelText: label, hintText: hint),
    ),
  );
  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: panel,
    insetPadding: const EdgeInsets.all(16),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 540),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Профиль сервера',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  onPressed: saving ? null : () => Navigator.of(context).pop(),
                  tooltip: 'Закрыть',
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'VLESS / Reality · TCP',
                style: TextStyle(color: mint),
              ),
            ),
            const SizedBox(height: 20),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: saving ? null : paste,
                        icon: const Icon(Icons.content_paste_rounded, size: 19),
                        label: const Text('Вставить из буфера обмена'),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Text(
                        'или заполните параметры вручную',
                        style: TextStyle(color: muted),
                      ),
                    ),
                    if (error != null) ...[
                      ErrorNotice(error!),
                      const SizedBox(height: 18),
                    ],
                    field('name', 'Название профиля'),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: field(
                            'host',
                            'Адрес сервера',
                            hint: 'vpn.example.com',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: field('port', 'Порт', numeric: true)),
                      ],
                    ),
                    field('uuid', 'UUID пользователя', secret: true),
                    field(
                      'serverName',
                      'SNI / Server name',
                      hint: 'Домен из настройки Reality',
                    ),
                    field('publicKey', 'Публичный ключ Reality', secret: true),
                    field(
                      'shortId',
                      'Short ID',
                      secret: true,
                      hint: 'Может быть пустым, если сервер разрешает',
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: fingerprint,
                      key: ValueKey(fingerprint),
                      decoration: const InputDecoration(
                        labelText: 'TLS fingerprint',
                      ),
                      items: VpnProfile.fingerprints
                          .map(
                            (e) => DropdownMenuItem(value: e, child: Text(e)),
                          )
                          .toList(),
                      onChanged: saving
                          ? null
                          : (v) => setState(() => fingerprint = v!),
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('XTLS Vision'),
                      subtitle: const Text(
                        'Должен совпадать с flow на сервере',
                      ),
                      value: vision,
                      onChanged: saving
                          ? null
                          : (v) => setState(() => vision = v),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Показать UUID и ключи'),
                      value: visible,
                      onChanged: saving
                          ? null
                          : (v) => setState(() => visible = v!),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: saving ? null : save,
                child: Text(saving ? 'Сохранение…' : 'Сохранить профиль'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  @override
  void dispose() {
    for (final controller in fields.values) {
      controller.dispose();
    }
    super.dispose();
  }
}
