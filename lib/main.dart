import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/config/app_config.dart';
import 'src/data/transit_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();
  runApp(
    VoieGoApp(
      repository: TransitRepository(config: config),
      demoMode: config.demoMode,
    ),
  );
}
