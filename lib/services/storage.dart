import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/profile.dart';
import '../domain/profile_catalog.dart';
import '../domain/routing.dart';
import '../domain/log_event.dart';

class AppStorage {
  AppStorage({FlutterSecureStorage? secure})
    : _secure = secure ?? const FlutterSecureStorage();
  final FlutterSecureStorage _secure;
  Future<ProfileCatalog> loadCatalog() async {
    final value = await _secure.read(key: 'profiles_v2');
    if (value != null) {
      return ProfileCatalog.fromJson(jsonDecode(value) as Map<String, dynamic>);
    }
    final legacy = await loadProfile();
    if (legacy == null) return const ProfileCatalog();
    final entry = SavedProfile.create(legacy);
    final catalog = ProfileCatalog(profiles: [entry], selectedId: entry.id);
    await saveCatalog(catalog);
    return catalog;
  }

  Future<void> saveCatalog(ProfileCatalog catalog) async {
    catalog.validate();
    final value = jsonEncode(catalog.toJson());
    await _secure.write(key: 'profiles_v2', value: value);
    if (await _secure.read(key: 'profiles_v2') != value) {
      throw const FormatException('Не удалось проверить сохранение профилей.');
    }
  }

  Future<VpnProfile?> loadProfile() async {
    final value = await _secure.read(key: 'vless_profile_v1');
    return value == null
        ? null
        : VpnProfile.fromJson(jsonDecode(value) as Map<String, dynamic>);
  }

  Future<void> saveProfile(VpnProfile profile) => _secure.write(
    key: 'vless_profile_v1',
    value: jsonEncode(profile.toJson()),
  );
  Future<({RoutingMode mode, List<RoutedApp> apps, bool diagnostic})>
  loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final list = jsonDecode(prefs.getString('apps_v1') ?? '[]') as List;
    return (
      mode: prefs.getBool('all_apps') == true
          ? RoutingMode.all
          : RoutingMode.selected,
      apps: list
          .map((v) => RoutedApp.fromJson(v as Map<String, dynamic>))
          .toList(),
      diagnostic: prefs.getBool('diagnostic') ?? false,
    );
  }

  Future<void> saveSettings(
    RoutingMode mode,
    List<RoutedApp> apps,
    bool diagnostic,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'apps_v1',
      jsonEncode(apps.map((e) => e.toJson()).toList()),
    );
    await prefs.setBool('all_apps', mode == RoutingMode.all);
    await prefs.setBool('diagnostic', diagnostic);
  }

  Future<File> _logFile() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}events-v1.json');
  }

  Future<List<LogEvent>> loadLogs() async {
    final file = await _logFile();
    if (!await file.exists()) return [];
    final data = jsonDecode(await file.readAsString()) as List;
    return retainLogs(
      data.map(
        (v) =>
            LogEvent.fromJson(v as Map<String, dynamic>).normalizeCoreLevel(),
      ),
    );
  }

  Future<void> saveLogs(List<LogEvent> events) async {
    final file = await _logFile();
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      jsonEncode(retainLogs(events).map((e) => e.toJson()).toList()),
      flush: true,
    );
    await temp.rename(file.path);
  }
}
