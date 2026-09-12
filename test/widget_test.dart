import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voiego/src/app.dart';
import 'package:voiego/src/config/app_config.dart';
import 'package:voiego/src/data/transit_repository.dart';
import 'package:voiego/src/services/location_service.dart';

void main() {
  testWidgets('VoieGo affiche le parcours principal', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      VoieGoApp(
        repository: TransitRepository(config: const AppConfig(apiBaseUrl: '')),
        locationService: LocationService(),
        demoMode: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('VoieGo'), findsOneWidget);
    expect(find.text('Choisir le réseau'), findsOneWidget);
    expect(find.text('Choisir la ligne'), findsOneWidget);
    expect(find.text('3 min'), findsOneWidget);
    expect(find.text('Suivre le prochain passage'), findsOneWidget);
  });
}
