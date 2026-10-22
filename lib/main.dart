import 'dart:io';

import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'services/storage.dart';
import 'services/vpn_engine.dart';
import 'ui/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = AppController(
    engine: Platform.isAndroid ? AndroidVpnEngine() : WindowsVpnEngine(),
    storage: AppStorage(),
  );
  runApp(Sme11App(controller: controller));
  controller.initialize();
}
