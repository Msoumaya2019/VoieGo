import 'package:flutter_test/flutter_test.dart';
import 'package:voiego/src/models/transit.dart';

void main() {
  test('Departure.fromJson normalise la réponse du proxy', () {
    final departure = Departure.fromJson({
      'destination': 'Versailles Rive Droite',
      'stopName': 'La Défense',
      'expectedAt': '2026-09-12T14:30:00+02:00',
      'walkingMinutes': 4,
      'confidence': 'confiance élevée',
    });

    expect(departure.destination, 'Versailles Rive Droite');
    expect(departure.stopName, 'La Défense');
    expect(departure.walkingMinutes, 4);
    expect(departure.expectedAt.isUtc, isFalse);
  });

  test('minutesFrom ne renvoie jamais une valeur négative', () {
    final now = DateTime(2026, 9, 12, 14, 30);
    final departure = Departure(
      destination: 'Paris',
      stopName: 'La Défense',
      expectedAt: now.subtract(const Duration(minutes: 2)),
      walkingMinutes: 4,
      confidence: 'temps réel',
    );
    expect(departure.minutesFrom(now), 0);
  });
}
