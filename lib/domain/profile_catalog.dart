import 'dart:math';

import 'profile.dart';

class SavedProfile {
  const SavedProfile({required this.id, required this.profile});
  final String id;
  final VpnProfile profile;
  String get tag => 'ep_$id';
  factory SavedProfile.create(VpnProfile profile) => SavedProfile(
    id: List.generate(
      16,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join(),
    profile: profile,
  );
  Map<String, Object> toJson() => {'id': id, 'profile': profile.toJson()};
  factory SavedProfile.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) {
      throw const FormatException('Некорректный идентификатор профиля.');
    }
    return SavedProfile(
      id: id,
      profile: VpnProfile.fromJson(json['profile'] as Map<String, dynamic>),
    );
  }
}

class ProfileCatalog {
  const ProfileCatalog({
    this.profiles = const [],
    this.selectedId,
    this.automatic = false,
  });
  final List<SavedProfile> profiles;
  final String? selectedId;
  final bool automatic;
  SavedProfile? get selected =>
      profiles.where((e) => e.id == selectedId).firstOrNull;
  void validate() {
    if (profiles.length > 20 ||
        profiles.map((e) => e.id).toSet().length != profiles.length ||
        (profiles.isNotEmpty && selected == null) ||
        (profiles.isEmpty && (selectedId != null || automatic))) {
      throw const FormatException('Некорректный каталог профилей.');
    }
    for (final entry in profiles) {
      SavedProfile.fromJson(entry.toJson());
    }
  }

  Map<String, Object?> toJson() => {
    'version': 2,
    'profiles': profiles.map((e) => e.toJson()).toList(),
    'selectedId': selectedId,
    'automatic': automatic,
  };
  factory ProfileCatalog.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 2) {
      throw const FormatException('Неизвестная версия каталога.');
    }
    final result = ProfileCatalog(
      profiles: (json['profiles'] as List)
          .map((e) => SavedProfile.fromJson(e as Map<String, dynamic>))
          .toList(),
      selectedId: json['selectedId'] as String?,
      automatic: json['automatic'] as bool,
    );
    result.validate();
    return result;
  }
}

class EndpointCheck {
  const EndpointCheck({
    required this.tag,
    required this.time,
    this.delayMs,
    this.error,
  });
  final String tag;
  final DateTime time;
  final int? delayMs;
  final String? error;
  bool get available => delayMs != null && error == null;
  bool get fresh =>
      DateTime.now().difference(time) < const Duration(seconds: 90);
}
