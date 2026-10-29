import 'profile.dart';
import 'routing.dart';
import 'profile_catalog.dart';

class ConfigBuilder {
  static const checkUrl = 'https://www.gstatic.com/generate_204';
  static Map<String, dynamic> catalog(
    ProfileCatalog catalog, {
    required bool windows,
    required RoutingMode mode,
    required List<String> applications,
    bool diagnostic = false,
    bool probeOnly = false,
  }) {
    catalog.validate();
    if (catalog.selected == null) {
      throw const FormatException('Добавьте сервер.');
    }
    final config = build(
      catalog.selected!.profile,
      windows: windows,
      mode: probeOnly ? RoutingMode.all : mode,
      applications: applications,
      diagnostic: diagnostic,
    );
    final tags = [
      if (catalog.automatic) catalog.selected!.tag,
      ...catalog.profiles
          .where((e) => !catalog.automatic || e.id != catalog.selectedId)
          .map((e) => e.tag),
    ];
    config['outbounds'] = [
      {
        'type': 'selector',
        'tag': 'proxy',
        'outbounds': [...tags, 'auto'],
        'default': catalog.automatic && !probeOnly
            ? 'auto'
            : catalog.selected!.tag,
        'interrupt_exist_connections': true,
      },
      {
        'type': 'urltest',
        'tag': 'auto',
        'outbounds': tags,
        'url': checkUrl,
        'interval': '1m',
        'tolerance': 100,
        'interrupt_exist_connections': true,
      },
      for (final entry in catalog.profiles)
        {
          ...(build(
                        entry.profile,
                        windows: windows,
                        mode: RoutingMode.all,
                        applications: const [],
                      )['outbounds']
                      as List)
                  .first
              as Map<String, dynamic>,
          'tag': entry.tag,
        },
      {'type': 'direct', 'tag': 'direct'},
    ];
    if (probeOnly) config['inbounds'] = <Object>[];
    return config;
  }

  static Map<String, dynamic> build(
    VpnProfile profile, {
    required bool windows,
    required RoutingMode mode,
    required List<String> applications,
    bool diagnostic = false,
  }) {
    profile.validate();
    if (mode == RoutingMode.selected && applications.isEmpty) {
      throw const FormatException('Выберите хотя бы одно приложение для VPN.');
    }
    final outbound = <String, dynamic>{
      'type': 'vless',
      'tag': 'proxy',
      'server': profile.host,
      'server_port': profile.port,
      'uuid': profile.uuid,
      if (profile.flow.isNotEmpty) 'flow': profile.flow,
      'tls': {
        'enabled': true,
        'server_name': profile.serverName,
        'utls': {'enabled': true, 'fingerprint': profile.fingerprint},
        'reality': {
          'enabled': true,
          'public_key': profile.publicKey,
          'short_id': profile.shortId,
        },
      },
      'domain_resolver': 'dns-direct',
    };
    return {
      'log': {
        'level': diagnostic ? 'debug' : 'info',
        'timestamp': true,
        'disabled': false,
      },
      'dns': {
        'servers': [
          {'type': 'local', 'tag': 'dns-direct'},
          {
            'type': 'https',
            'tag': 'dns-proxy',
            'server': '1.1.1.1',
            'server_port': 443,
            'path': '/dns-query',
            'detour': 'proxy',
          },
        ],
        // Windows DNS Client является отдельным системным процессом.
        // В режиме выбора приложений сохраняем системное разрешение имён.
        'final': windows && mode == RoutingMode.selected
            ? 'dns-direct'
            : 'dns-proxy',
        'strategy': 'prefer_ipv4',
      },
      'inbounds': [
        {
          'type': 'tun',
          'tag': 'tun-in',
          'interface_name': 'Sme11VPN',
          'address': ['172.19.0.1/30', 'fdfe:dcba:9876::1/126'],
          'mtu': 1500,
          'auto_route': true,
          'strict_route': false,
          'stack': 'mixed',
        },
      ],
      'outbounds': [
        outbound,
        {'type': 'direct', 'tag': 'direct'},
      ],
      'route': {
        'auto_detect_interface': true,
        'default_domain_resolver': 'dns-direct',
        'rules': [
          {'action': 'sniff'},
          {'protocol': 'dns', 'action': 'hijack-dns'},
          if (windows && mode == RoutingMode.selected)
            {
              'process_path': applications,
              'action': 'route',
              'outbound': 'proxy',
            },
        ],
        'final': windows && mode == RoutingMode.selected ? 'direct' : 'proxy',
      },
    };
  }
}
