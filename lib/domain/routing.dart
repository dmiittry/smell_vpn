class RoutedApp {
  const RoutedApp({required this.id, required this.name});
  final String id;
  final String name;
  Map<String, String> toJson() => {'id': id, 'name': name};
  factory RoutedApp.fromJson(Map<String, dynamic> map) =>
      RoutedApp(id: map['id'] as String, name: map['name'] as String);
}

enum RoutingMode { selected, all }
