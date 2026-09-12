import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/transit.dart';

class TransitRepository {
  TransitRepository({required this.config, http.Client? client})
    : _client = client ?? http.Client();

  final AppConfig config;
  final http.Client _client;

  Future<List<TransitLine>> fetchLines(TransitMode mode) async {
    if (config.demoMode) {
      return transitLines.where((line) => line.mode == mode).toList();
    }
    final uri = Uri.parse(config.apiBaseUrl)
        .resolve('/api/v1/lines')
        .replace(queryParameters: {'mode': mode.name});
    try {
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw TransitException('Le catalogue répond ${response.statusCode}.');
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final lines = (body['lines'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((item) => TransitLine.fromJson(item, mode))
          .where((line) => line.lineRef.isNotEmpty)
          .toList();
      if (lines.isEmpty) {
        throw const TransitException('Aucune ligne disponible pour ce réseau.');
      }
      return lines;
    } on TransitException {
      rethrow;
    } catch (_) {
      throw const TransitException(
        'Impossible de charger le catalogue des lignes.',
      );
    }
  }

  Future<TransitSnapshot> fetchSnapshot({
    required TransitLine line,
    double? latitude,
    double? longitude,
  }) async {
    if (config.demoMode) return _demoSnapshot(line);

    final base = Uri.parse(config.apiBaseUrl);
    final uri = base
        .resolve('/api/v1/snapshot')
        .replace(
          queryParameters: {
            'lineRef': line.lineRef,
            'mode': line.mode.name,
            if (latitude != null) 'lat': '$latitude',
            if (longitude != null) 'lon': '$longitude',
          },
        );

    try {
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw TransitException('Le service répond ${response.statusCode}.');
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final departures = (body['departures'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Departure.fromJson)
          .toList();
      if (departures.isEmpty) {
        throw const TransitException(
          'Aucun passage disponible pour cette ligne.',
        );
      }
      return TransitSnapshot(
        departures: departures,
        alert: body['alert'] is Map<String, dynamic>
            ? TrafficAlert.fromJson(body['alert'] as Map<String, dynamic>)
            : null,
        fetchedAt: DateTime.now(),
        isDemo: body['source'] == 'demo',
      );
    } on TransitException {
      rethrow;
    } catch (_) {
      throw const TransitException(
        'Impossible de joindre VoieGo. Vérifiez votre connexion puis réessayez.',
      );
    }
  }

  TransitSnapshot _demoSnapshot(TransitLine line) {
    final now = DateTime.now();
    final transilien = line.mode == TransitMode.transilien;
    return TransitSnapshot(
      departures: [
        Departure(
          destination: line.code == 'L'
              ? 'Versailles Rive Droite'
              : 'Prochain terminus',
          stopName: transilien ? 'La Défense' : 'Arrêt le plus proche',
          expectedAt: now.add(const Duration(minutes: 3, seconds: 40)),
          walkingMinutes: 4,
          confidence: 'confiance élevée',
        ),
        Departure(
          destination: line.code == 'L'
              ? 'Saint-Nom-la-Bretèche'
              : 'Prochain terminus',
          stopName: transilien ? 'La Défense' : 'Arrêt le plus proche',
          expectedAt: now.add(const Duration(minutes: 11)),
          walkingMinutes: 4,
          confidence: 'prévision',
        ),
      ],
      alert: line.code == 'L'
          ? const TrafficAlert(
              title: 'Perturbation sur la ligne L',
              message: 'Trafic ralenti entre Saint-Cloud et Versailles. Prévoir +5 à +10 min.',
            )
          : null,
      fetchedAt: now,
      isDemo: true,
    );
  }
}

class TransitException implements Exception {
  const TransitException(this.message);
  final String message;

  @override
  String toString() => message;
}
