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
    required TransitStop stop,
    required TransitDirection direction,
  }) async {
    if (config.demoMode) return _demoSnapshot(line);

    final base = Uri.parse(config.apiBaseUrl);
    final uri = base
        .resolve('/api/v1/snapshot')
        .replace(
          queryParameters: {
            'lineRef': line.lineRef,
            'mode': line.mode.name,
            'stopId': stop.id,
            'routeId': direction.id,
          },
        );

    try {
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        final message = _apiErrorMessage(response.body);
        throw TransitException(
          message ?? 'Le service répond ${response.statusCode}.',
        );
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final departures = (body['departures'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Departure.fromJson)
          .toList();
      return TransitSnapshot(
        departures: departures,
        alert: body['alert'] is Map<String, dynamic>
            ? TrafficAlert.fromJson(body['alert'] as Map<String, dynamic>)
            : null,
        fetchedAt: DateTime.now(),
        isDemo: body['source'] == 'demo',
        locationMatched: body['locationMatched'] as bool? ?? false,
      );
    } on TransitException {
      rethrow;
    } catch (_) {
      throw const TransitException(
        'Impossible de joindre VoieGo. Vérifiez votre connexion puis réessayez.',
      );
    }
  }

  Future<List<TransitStop>> fetchStops(TransitLine line) async {
    if (config.demoMode) {
      return const [TransitStop(id: 'demo:stop', name: 'Arrêt principal')];
    }
    final uri = Uri.parse(config.apiBaseUrl)
        .resolve('/api/v1/stops')
        .replace(queryParameters: {'lineRef': line.lineRef});
    final response = await _get(uri, 'Impossible de charger les arrêts.');
    final stops = (response['stops'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(TransitStop.fromJson)
        .where((stop) => stop.id.isNotEmpty)
        .toList();
    if (stops.isEmpty) {
      throw const TransitException('Aucun arrêt disponible pour cette ligne.');
    }
    return stops;
  }

  Future<List<TransitDirection>> fetchDirections(
    TransitLine line,
    TransitStop stop,
  ) async {
    if (config.demoMode) {
      return const [
        TransitDirection(id: 'demo:route', label: 'Direction terminus'),
      ];
    }
    final uri = Uri.parse(config.apiBaseUrl)
        .resolve('/api/v1/directions')
        .replace(queryParameters: {
          'lineRef': line.lineRef,
          'stopId': stop.id,
        });
    final response = await _get(uri, 'Impossible de charger les directions.');
    final directions = (response['directions'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(TransitDirection.fromJson)
        .where((direction) => direction.id.isNotEmpty)
        .toList();
    if (directions.isEmpty) {
      throw const TransitException('Aucune direction disponible à cet arrêt.');
    }
    return directions;
  }

  Future<List<NearbyStop>> fetchNearbyStops({
    required double latitude,
    required double longitude,
    required int radiusMeters,
  }) async {
    final uri = Uri.parse(config.apiBaseUrl)
        .resolve('/api/v1/nearby')
        .replace(queryParameters: {
          'lat': '$latitude',
          'lon': '$longitude',
          'radius': '$radiusMeters',
        });
    final response = await _get(
      uri,
      'Impossible de charger les arrêts autour de vous.',
    );
    return (response['stops'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(NearbyStop.fromJson)
        .where((stop) => stop.id.isNotEmpty)
        .toList();
  }

  Future<List<TransitJourney>> fetchJourneys({
    required String from,
    required String to,
  }) async {
    if (config.demoMode) {
      final now = DateTime.now();
      return [
        TransitJourney(
          departureAt: now.add(const Duration(minutes: 4)),
          arrivalAt: now.add(const Duration(minutes: 39)),
          durationSeconds: 2100,
          transfers: 1,
          sections: const [
            JourneySection(
              type: 'street_network',
              mode: 'Marche',
              line: null,
              direction: null,
              from: 'Départ',
              to: 'Arrêt de départ',
              durationSeconds: 300,
            ),
            JourneySection(
              type: 'public_transport',
              mode: 'Métro',
              line: '1',
              direction: 'Direction terminus',
              from: 'Arrêt de départ',
              to: 'Arrêt d’arrivée',
              durationSeconds: 1500,
            ),
          ],
        ),
      ];
    }
    final uri = Uri.parse(config.apiBaseUrl)
        .resolve('/api/v1/journeys')
        .replace(queryParameters: {'from': from, 'to': to});
    final response = await _get(uri, 'Impossible de calculer cet itinéraire.');
    final journeys = (response['journeys'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(TransitJourney.fromJson)
        .toList();
    if (journeys.isEmpty) {
      throw const TransitException(
        'Aucun itinéraire en transport en commun n’a été trouvé.',
      );
    }
    return journeys;
  }

  Future<Map<String, dynamic>> _get(Uri uri, String fallbackMessage) async {
    try {
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw TransitException(
          _apiErrorMessage(response.body) ??
              '$fallbackMessage (${response.statusCode})',
        );
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on TransitException {
      rethrow;
    } catch (_) {
      throw TransitException(fallbackMessage);
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
      locationMatched: true,
    );
  }
}

String? _apiErrorMessage(String responseBody) {
  try {
    final body = jsonDecode(responseBody);
    if (body is Map<String, dynamic>) {
      final message = body['error'];
      if (message is String && message.trim().isNotEmpty) return message;
    }
  } catch (_) {
    // Une réponse non JSON utilise le message HTTP générique.
  }
  return null;
}

class TransitException implements Exception {
  const TransitException(this.message);
  final String message;

  @override
  String toString() => message;
}
