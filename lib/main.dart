import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/config/app_config.dart';
import 'src/data/transit_repository.dart';
import 'src/services/push_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();
  final pushNotifications = PushNotificationService();
  await pushNotifications.initialize();
  runApp(
    VoieGoApp(
      repository: TransitRepository(config: config),
      demoMode: config.demoMode,
      pushNotifications: pushNotifications,
    ),
  );
}
