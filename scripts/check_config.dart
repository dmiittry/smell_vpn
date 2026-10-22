import 'dart:convert';
import 'dart:io';

import 'package:sme11_vpn/domain/config_builder.dart';
import 'package:sme11_vpn/domain/profile.dart';
import 'package:sme11_vpn/domain/profile_catalog.dart';
import 'package:sme11_vpn/domain/routing.dart';

void main(List<String> args) {
  // Только синтетический профиль. Никаких пользовательских ключей.
  final profile = VpnProfile(
    name: 'Проверка',
    host: '192.0.2.1',
    port: 443,
    uuid: '00000000-0000-4000-8000-000000000001',
    serverName: 'example.com',
    publicKey: base64Url
        .encode(List.generate(32, (i) => i + 1))
        .replaceAll('=', ''),
  );
  stdout.writeln(
    jsonEncode(
      ConfigBuilder.catalog(
        ProfileCatalog(
          profiles: [
            SavedProfile(id: 'a' * 32, profile: profile),
            SavedProfile(id: 'b' * 32, profile: profile),
          ],
          selectedId: 'a' * 32,
          automatic: args.contains('auto'),
        ),
        windows: !args.contains('android'),
        mode: args.contains('all') ? RoutingMode.all : RoutingMode.selected,
        applications: args.contains('android')
            ? ['com.android.chrome']
            : [r'C:\Program Files\Example\example.exe'],
        probeOnly: args.contains('probe'),
      ),
    ),
  );
}
