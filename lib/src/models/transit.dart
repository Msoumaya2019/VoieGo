import 'dart:ui';

enum TransitMode { bus, metro, rer, transilien, tramway }

extension TransitModeLabel on TransitMode {
  String get label => switch (this) {
    TransitMode.bus => 'Bus',
    TransitMode.metro => 'Métro',
    TransitMode.rer => 'RER',
    TransitMode.transilien => 'Transilien',
    TransitMode.tramway => 'Tramway',
  };

  String get iconLabel => switch (this) {
    TransitMode.bus => 'BUS',
    TransitMode.metro => 'M',
    TransitMode.rer => 'R',
    TransitMode.transilien => 'TR',
    TransitMode.tramway => 'T',
  };
}

class TransitLine {
  const TransitLine({
    required this.code,
    required this.mode,
    required this.lineRef,
    required this.color,
    required this.textColor,
  });

  final String code;
  final TransitMode mode;
  final String lineRef;
  final Color color;
  final Color textColor;

  factory TransitLine.fromJson(Map<String, dynamic> json, TransitMode mode) {
    return TransitLine(
      code: json['code'] as String? ?? '?',
      mode: mode,
      lineRef: json['lineRef'] as String? ?? '',
      color: _hexColor(json['color'] as String?, const Color(0xFF2A6FBB)),
      textColor: _hexColor(
        json['textColor'] as String?,
        const Color(0xFFFFFFFF),
      ),
    );
  }
}

class TransitStop {
  const TransitStop({required this.id, required this.name});

  factory TransitStop.fromJson(Map<String, dynamic> json) {
    return TransitStop(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Arrêt sans nom',
    );
  }

  final String id;
  final String name;
}

class TransitDirection {
  const TransitDirection({required this.id, required this.label});

  factory TransitDirection.fromJson(Map<String, dynamic> json) {
    return TransitDirection(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? 'Direction inconnue',
    );
  }

  final String id;
  final String label;
}

class NearbyStop {
  const NearbyStop({
    required this.id,
    required this.name,
    required this.distanceMeters,
  });

  factory NearbyStop.fromJson(Map<String, dynamic> json) {
    return NearbyStop(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Arrêt sans nom',
      distanceMeters: (json['distanceMeters'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String name;
  final int distanceMeters;
}

class TransitJourney {
  const TransitJourney({
    required this.departureAt,
    required this.arrivalAt,
    required this.durationSeconds,
    required this.transfers,
    required this.sections,
  });

  factory TransitJourney.fromJson(Map<String, dynamic> json) {
    return TransitJourney(
      departureAt: DateTime.parse(json['departureAt'] as String).toLocal(),
      arrivalAt: DateTime.parse(json['arrivalAt'] as String).toLocal(),
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
      transfers: (json['transfers'] as num?)?.toInt() ?? 0,
      sections: (json['sections'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(JourneySection.fromJson)
          .toList(),
    );
  }

  final DateTime departureAt;
  final DateTime arrivalAt;
  final int durationSeconds;
  final int transfers;
  final List<JourneySection> sections;

  int get durationMinutes => (durationSeconds / 60).ceil();
}

class JourneySection {
  const JourneySection({
    required this.type,
    required this.mode,
    required this.line,
    required this.direction,
    required this.from,
    required this.to,
    required this.durationSeconds,
  });

  factory JourneySection.fromJson(Map<String, dynamic> json) {
    return JourneySection(
      type: json['type'] as String? ?? 'transfer',
      mode: json['mode'] as String? ?? 'Marche',
      line: json['line'] as String?,
      direction: json['direction'] as String?,
      from: json['from'] as String? ?? '',
      to: json['to'] as String? ?? '',
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
    );
  }

  final String type;
  final String mode;
  final String? line;
  final String? direction;
  final String from;
  final String to;
  final int durationSeconds;

  int get durationMinutes => (durationSeconds / 60).ceil();
}

class FavoriteJourney {
  const FavoriteJourney({
    required this.line,
    required this.stop,
    required this.direction,
  });

  factory FavoriteJourney.fromJson(Map<String, dynamic> json) {
    final modeName = json['mode'] as String? ?? '';
    final mode = TransitMode.values.firstWhere(
      (value) => value.name == modeName,
      orElse: () => TransitMode.bus,
    );
    return FavoriteJourney(
      line: TransitLine(
        code: json['lineCode'] as String? ?? '?',
        mode: mode,
        lineRef: json['lineRef'] as String? ?? '',
        color: Color((json['lineColor'] as num?)?.toInt() ?? 0xFF2A6FBB),
        textColor: Color(
          (json['lineTextColor'] as num?)?.toInt() ?? 0xFFFFFFFF,
        ),
      ),
      stop: TransitStop(
        id: json['stopId'] as String? ?? '',
        name: json['stopName'] as String? ?? 'Arrêt sans nom',
      ),
      direction: TransitDirection(
        id: json['directionId'] as String? ?? '',
        label: json['directionLabel'] as String? ?? 'Direction inconnue',
      ),
    );
  }

  final TransitLine line;
  final TransitStop stop;
  final TransitDirection direction;

  String get key => '${line.lineRef}|${stop.id}|${direction.id}';

  Map<String, dynamic> toJson() => {
    'mode': line.mode.name,
    'lineCode': line.code,
    'lineRef': line.lineRef,
    'lineColor': line.color.toARGB32(),
    'lineTextColor': line.textColor.toARGB32(),
    'stopId': stop.id,
    'stopName': stop.name,
    'directionId': direction.id,
    'directionLabel': direction.label,
  };
}

Color _hexColor(String? value, Color fallback) {
  final normalized = value?.replaceFirst('#', '');
  if (normalized == null || normalized.length != 6) return fallback;
  final parsed = int.tryParse(normalized, radix: 16);
  return parsed == null ? fallback : Color(0xFF000000 | parsed);
}

class Departure {
  const Departure({
    required this.destination,
    required this.stopName,
    required this.expectedAt,
    required this.walkingMinutes,
    required this.confidence,
    this.vehicleJourneyName,
  });

  factory Departure.fromJson(Map<String, dynamic> json) {
    return Departure(
      destination: json['destination'] as String? ?? 'Destination inconnue',
      stopName: json['stopName'] as String? ?? 'Arrêt à proximité',
      expectedAt: DateTime.parse(json['expectedAt'] as String).toLocal(),
      walkingMinutes: (json['walkingMinutes'] as num?)?.toInt() ?? 0,
      confidence: json['confidence'] as String? ?? 'temps réel',
      vehicleJourneyName: json['vehicleJourneyName'] as String?,
    );
  }

  final String destination;
  final String stopName;
  final DateTime expectedAt;
  final int walkingMinutes;
  final String confidence;
  final String? vehicleJourneyName;

  int minutesFrom(DateTime now) {
    final value = expectedAt.difference(now).inMinutes;
    return value < 0 ? 0 : value;
  }
}

class TrafficAlert {
  const TrafficAlert({required this.title, required this.message});

  factory TrafficAlert.fromJson(Map<String, dynamic> json) {
    return TrafficAlert(
      title: json['title'] as String? ?? 'Information trafic',
      message: json['message'] as String? ?? '',
    );
  }

  final String title;
  final String message;
}

class TransitSnapshot {
  const TransitSnapshot({
    required this.departures,
    required this.alert,
    required this.fetchedAt,
    required this.isDemo,
    required this.locationMatched,
  });

  final List<Departure> departures;
  final TrafficAlert? alert;
  final DateTime fetchedAt;
  final bool isDemo;
  final bool locationMatched;
}

const transitLines = <TransitLine>[
  TransitLine(
    code: 'H',
    mode: TransitMode.transilien,
    lineRef: 'STIF:Line::C01736:',
    color: Color(0xFF765640),
    textColor: Color(0xFFFFFFFF),
  ),
  TransitLine(
    code: 'J',
    mode: TransitMode.transilien,
    lineRef: 'STIF:Line::C01739:',
    color: Color(0xFFFFCE2E),
    textColor: Color(0xFF101828),
  ),
  TransitLine(
    code: 'K',
    mode: TransitMode.transilien,
    lineRef: 'STIF:Line::C01738:',
    color: Color(0xFF8A8F2A),
    textColor: Color(0xFFFFFFFF),
  ),
  TransitLine(
    code: 'L',
    mode: TransitMode.transilien,
    lineRef: 'STIF:Line::C01740:',
    color: Color(0xFFB7AEFF),
    textColor: Color(0xFF07182F),
  ),
  TransitLine(
    code: 'N',
    mode: TransitMode.transilien,
    lineRef: 'STIF:Line::C01741:',
    color: Color(0xFF00A9A9),
    textColor: Color(0xFFFFFFFF),
  ),
  TransitLine(
    code: 'P',
    mode: TransitMode.transilien,
    lineRef: 'STIF:Line::C01742:',
    color: Color(0xFFFF9E2C),
    textColor: Color(0xFF101828),
  ),
  TransitLine(
    code: 'R',
    mode: TransitMode.transilien,
    lineRef: 'STIF:Line::C01743:',
    color: Color(0xFFE978B4),
    textColor: Color(0xFF101828),
  ),
  TransitLine(
    code: 'U',
    mode: TransitMode.transilien,
    lineRef: 'STIF:Line::C01744:',
    color: Color(0xFFD50045),
    textColor: Color(0xFFFFFFFF),
  ),
  TransitLine(
    code: 'A',
    mode: TransitMode.rer,
    lineRef: 'STIF:Line::C01742:',
    color: Color(0xFFE2231A),
    textColor: Color(0xFFFFFFFF),
  ),
  TransitLine(
    code: 'B',
    mode: TransitMode.rer,
    lineRef: 'STIF:Line::C01743:',
    color: Color(0xFF4B92DB),
    textColor: Color(0xFFFFFFFF),
  ),
  TransitLine(
    code: '1',
    mode: TransitMode.metro,
    lineRef: 'STIF:Line::C01371:',
    color: Color(0xFFFFCE00),
    textColor: Color(0xFF101828),
  ),
  TransitLine(
    code: '4',
    mode: TransitMode.metro,
    lineRef: 'STIF:Line::C01374:',
    color: Color(0xFFBE418D),
    textColor: Color(0xFFFFFFFF),
  ),
  TransitLine(
    code: '42',
    mode: TransitMode.bus,
    lineRef: 'STIF:Line::C01234:',
    color: Color(0xFF2A6FBB),
    textColor: Color(0xFFFFFFFF),
  ),
  TransitLine(
    code: '73',
    mode: TransitMode.bus,
    lineRef: 'STIF:Line::C01235:',
    color: Color(0xFF35A852),
    textColor: Color(0xFFFFFFFF),
  ),
];
