import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/transit_repository.dart';
import '../models/transit.dart';
import '../services/location_service.dart';

const _navy = Color(0xFF07182F);
const _panel = Color(0xFF102844);
const _panelLight = Color(0xFF173553);
const _cyan = Color(0xFF5FE3FF);
const _yellow = Color(0xFFFFC83D);
const _muted = Color(0xFFC4D4EE);
const _green = Color(0xFF5DF18C);

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.repository,
    required this.locationService,
    required this.demoMode,
  });

  final TransitRepository repository;
  final LocationService locationService;
  final bool demoMode;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  TransitMode _mode = TransitMode.transilien;
  late TransitLine _line;
  late List<TransitLine> _availableLines;
  TransitSnapshot? _snapshot;
  UserLocation? _location;
  bool _loading = true;
  bool _following = false;
  bool _reverseDirection = false;
  String? _error;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _line = transitLines.firstWhere((line) => line.code == 'L');
    _availableLines = transitLines.where((line) => line.mode == _mode).toList();
    _bootstrap();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
      _refresh(silent: true);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final storedMode = prefs.getString('selected_mode');
    final storedLine = prefs.getString('selected_line');
    if (storedMode != null && storedLine != null) {
      final mode = TransitMode.values
          .where((value) => value.name == storedMode)
          .firstOrNull;
      final line = transitLines
          .where((value) => value.code == storedLine && value.mode == mode)
          .firstOrNull;
      if (mode != null && line != null) {
        _mode = mode;
        _line = line;
      }
    }
    try {
      final remoteLines = await widget.repository.fetchLines(_mode);
      if (remoteLines.isNotEmpty) {
        _availableLines = remoteLines;
        _line =
            remoteLines.where((line) => line.code == storedLine).firstOrNull ??
            remoteLines.where((line) => line.code == _line.code).firstOrNull ??
            remoteLines.first;
      }
    } catch (_) {
      // Le catalogue local garde l’interface utilisable si le proxy est indisponible.
    }
    await _refresh();
    unawaited(_updateLocation());
  }

  Future<void> _updateLocation() async {
    try {
      final value = await widget.locationService.currentLocation();
      if (!mounted || value == null) return;
      setState(() => _location = value);
      await _refresh(silent: true);
    } catch (_) {
      // La localisation est facultative : l’app reste utilisable sans permission.
    }
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final result = await widget.repository.fetchSnapshot(
        line: _line,
        latitude: _location?.latitude,
        longitude: _location?.longitude,
      );
      if (!mounted) return;
      setState(() {
        _snapshot = result;
        _loading = false;
        _error = null;
      });
    } on TransitException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    }
  }

  Future<void> _selectMode(TransitMode mode) async {
    if (_mode == mode) return;
    final localLines = transitLines.where((line) => line.mode == mode).toList();
    final nextLine = localLines.first;
    setState(() {
      _mode = mode;
      _line = nextLine;
      _availableLines = localLines;
      _snapshot = null;
      _following = false;
    });
    try {
      final remoteLines = await widget.repository.fetchLines(mode);
      if (mounted && remoteLines.isNotEmpty) {
        setState(() {
          _availableLines = remoteLines;
          _line = remoteLines.first;
        });
      }
    } catch (_) {
      // La liste locale est un secours volontaire.
    }
    await _saveSelection();
    await _refresh();
  }

  Future<void> _selectLine(TransitLine line) async {
    if (_line == line) return;
    setState(() {
      _line = line;
      _snapshot = null;
      _following = false;
    });
    await _saveSelection();
    await _refresh();
  }

  Future<void> _saveSelection() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_mode', _mode.name);
    await prefs.setString('selected_line', _line.code);
  }

  Departure? get _primaryDeparture {
    final departures = _snapshot?.departures;
    if (departures == null || departures.isEmpty) return null;
    return _reverseDirection && departures.length > 1
        ? departures[1]
        : departures[0];
  }

  @override
  Widget build(BuildContext context) {
    final lineChoices = _availableLines;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: _cyan,
          backgroundColor: _panel,
          onRefresh: _refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Header(demoMode: widget.demoMode),
                          const SizedBox(height: 26),
                          const _StepTitle(
                            number: '1',
                            label: 'Choisir le réseau',
                          ),
                          const SizedBox(height: 12),
                          _ModeSelector(
                            selected: _mode,
                            onSelected: _selectMode,
                          ),
                          const SizedBox(height: 28),
                          const _StepTitle(
                            number: '2',
                            label: 'Choisir la ligne',
                          ),
                          const SizedBox(height: 12),
                          _LineSelector(
                            lines: lineChoices,
                            selected: _line,
                            onSelected: _selectLine,
                          ),
                          const SizedBox(height: 20),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            child: _buildContent(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_loading && _snapshot == null) {
      return const _LoadingCard(key: ValueKey('loading'));
    }
    if (_error != null && _snapshot == null) {
      return _ErrorCard(
        key: const ValueKey('error'),
        message: _error!,
        onRetry: _refresh,
      );
    }
    final departure = _primaryDeparture;
    if (departure == null) return const SizedBox.shrink();
    return Column(
      key: ValueKey('${_mode.name}-${_line.code}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _NextDepartureCard(
          mode: _mode,
          line: _line,
          departure: departure,
          snapshot: _snapshot!,
          located: _location != null,
        ),
        const SizedBox(height: 14),
        _MapCard(departure: departure, onOpen: () => _showMap(departure)),
        if (_snapshot?.alert case final alert?) ...[
          const SizedBox(height: 14),
          _AlertCard(alert: alert, onTap: () => _showTraffic(alert)),
        ],
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: () {
            setState(() => _following = !_following);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  _following
                      ? 'Suivi activé pour ce prochain passage.'
                      : 'Suivi désactivé.',
                ),
              ),
            );
          },
          icon: Icon(
            _following
                ? Icons.notifications_active_rounded
                : Icons.train_rounded,
          ),
          label: Text(
            _following ? 'Passage suivi' : 'Suivre le prochain passage',
          ),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(58),
            backgroundColor: _yellow,
            foregroundColor: _navy,
            textStyle: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () =>
              setState(() => _reverseDirection = !_reverseDirection),
          icon: const Icon(Icons.swap_horiz_rounded),
          label: const Text('Changer de sens'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(54),
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white, width: 1.5),
            textStyle: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
      ],
    );
  }

  void _showMap(Departure departure) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _panel,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Rejoindre ${departure.stopName}',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _location == null
                    ? 'Activez la localisation pour une estimation personnalisée.'
                    : '${departure.walkingMinutes} min à pied depuis votre position.',
                style: const TextStyle(color: _muted),
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset(
                  'assets/images/la_defense_map.png',
                  fit: BoxFit.cover,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTraffic(TrafficAlert alert) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _panel,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                alert.title,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 10),
              Text(
                alert.message,
                style: const TextStyle(color: _muted, fontSize: 16),
              ),
              const SizedBox(height: 18),
              const Text(
                'Source : Île-de-France Mobilités / PRIM',
                style: TextStyle(color: _cyan),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.demoMode});
  final bool demoMode;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.asset(
            'assets/images/app_icon.png',
            width: 52,
            height: 52,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  style: TextStyle(
                    fontSize: 30,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                  children: [
                    TextSpan(text: 'Voie'),
                    TextSpan(
                      text: 'Go',
                      style: TextStyle(color: _cyan),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 5),
              Text(
                'PLUS LOIN ENSEMBLE',
                style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 3,
                  color: _muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        if (demoMode)
          const Tooltip(
            message: 'Données de démonstration — configurez VOIEGO_API_BASE_URL pour PRIM',
            child: Chip(
              avatar: Icon(Icons.science_outlined, size: 16),
              label: Text('Démo'),
              visualDensity: VisualDensity.compact,
            ),
          ),
      ],
    );
  }
}

class _StepTitle extends StatelessWidget {
  const _StepTitle({required this.number, required this.label});
  final String number;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 21,
          backgroundColor: _cyan,
          child: Text(
            number,
            style: const TextStyle(
              color: _navy,
              fontWeight: FontWeight.w900,
              fontSize: 20,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(label, style: Theme.of(context).textTheme.headlineMedium),
      ],
    );
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.selected, required this.onSelected});
  final TransitMode selected;
  final ValueChanged<TransitMode> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - 24) / 4;
        return Row(
          children: TransitMode.values.indexed.map((entry) {
            final (index, mode) = entry;
            final active = mode == selected;
            return Padding(
              padding: EdgeInsets.only(right: index == 3 ? 0 : 8),
              child: SizedBox(
                width: itemWidth,
                child: Semantics(
                  selected: active,
                  button: true,
                  label: 'Réseau ${mode.label}',
                  child: InkWell(
                    onTap: () => onSelected(mode),
                    borderRadius: BorderRadius.circular(16),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      height: 56,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: active ? const Color(0xFFEAE7FF) : _panel,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: active
                              ? Colors.white
                              : const Color(0xFF28496D),
                          width: active ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            radius: 12,
                            backgroundColor: active
                                ? _navy
                                : Colors.transparent,
                            child: Text(
                              mode.iconLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                mode.label,
                                style: TextStyle(
                                  color: active ? _navy : Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _LineSelector extends StatelessWidget {
  const _LineSelector({
    required this.lines,
    required this.selected,
    required this.onSelected,
  });
  final List<TransitLine> lines;
  final TransitLine selected;
  final ValueChanged<TransitLine> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: lines.map((line) {
          final active = line == selected;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Semantics(
              selected: active,
              button: true,
              label: 'Ligne ${line.code}',
              child: InkWell(
                onTap: () => onSelected(line),
                borderRadius: BorderRadius.circular(16),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 42,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: line.color,
                    borderRadius: BorderRadius.circular(14),
                    border: active
                        ? Border.all(color: Colors.white, width: 3)
                        : null,
                    boxShadow: active
                        ? [
                            BoxShadow(
                              color: line.color.withValues(alpha: .45),
                              blurRadius: 16,
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    line.code,
                    style: TextStyle(
                      color: line.textColor,
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _NextDepartureCard extends StatelessWidget {
  const _NextDepartureCard({
    required this.mode,
    required this.line,
    required this.departure,
    required this.snapshot,
    required this.located,
  });

  final TransitMode mode;
  final TransitLine line;
  final Departure departure;
  final TransitSnapshot snapshot;
  final bool located;

  @override
  Widget build(BuildContext context) {
    final minutes = departure.minutesFrom(DateTime.now());
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF1C4265)),
      ),
      child: Stack(
        children: [
          Positioned(
            right: 6,
            top: 70,
            child: Icon(
              Icons.train_rounded,
              size: 96,
              color: line.color.withValues(alpha: .17),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Text(
                          '${mode.label} ligne ',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: line.color,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            line.code,
                            style: TextStyle(
                              color: line.textColor,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.circle, size: 11, color: _green),
                  const SizedBox(width: 6),
                  const Text(
                    'Temps réel',
                    style: TextStyle(
                      color: _green,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const Text(
                'Le prochain est à',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                '$minutes min',
                style: const TextStyle(
                  color: _yellow,
                  fontSize: 70,
                  height: .95,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Vers ${departure.destination}  →',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.location_on_rounded, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      located
                          ? '${departure.stopName} — à ${departure.walkingMinutes} min à pied'
                          : '${departure.stopName} — activez votre position',
                      style: const TextStyle(color: _muted, fontSize: 15),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _RouteTimeline(destination: departure.destination),
              const SizedBox(height: 14),
              Text(
                snapshot.isDemo
                    ? 'Aperçu avec données de démonstration'
                    : 'Mis à jour il y a moins d’une minute · ${departure.confidence}',
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RouteTimeline extends StatelessWidget {
  const _RouteTimeline({required this.destination});
  final String destination;

  @override
  Widget build(BuildContext context) {
    const labels = ['La Défense', 'Puteaux', 'Suresnes', 'Versailles'];
    return Column(
      children: [
        Row(
          children: List.generate(labels.length * 2 - 1, (index) {
            if (index.isOdd) {
              return const Expanded(
                child: Divider(color: Color(0xFFBDB4FF), thickness: 3),
              );
            }
            final point = index ~/ 2;
            return Container(
              width: point == 0 ? 32 : 16,
              height: point == 0 ? 32 : 16,
              decoration: BoxDecoration(
                color: point == 0 ? const Color(0xFFBDB4FF) : _panel,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
              ),
              child: point == 0
                  ? const Icon(Icons.train_rounded, size: 17, color: _navy)
                  : null,
            );
          }),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: labels
              .map(
                (label) => Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11, color: _muted),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _MapCard extends StatelessWidget {
  const _MapCard({required this.departure, required this.onOpen});
  final Departure departure;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          SizedBox(
            width: double.infinity,
            height: 190,
            child: Image.asset(
              'assets/images/la_defense_map.png',
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            top: 14,
            left: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.directions_walk_rounded, color: _navy),
                  const SizedBox(width: 7),
                  Text(
                    '${departure.walkingMinutes} min\nà pied',
                    style: const TextStyle(
                      color: _navy,
                      fontWeight: FontWeight.w900,
                      height: 1.05,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: FilledButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.navigation_rounded),
              label: const Text('Voir sur la carte'),
              style: FilledButton.styleFrom(
                backgroundColor: _navy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert, required this.onTap});
  final TrafficAlert alert;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _panelLight,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFFF8B3D),
                size: 36,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      alert.title,
                      style: const TextStyle(
                        color: _yellow,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      alert.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _muted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard({super.key});
  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 260,
      child: Center(child: CircularProgressIndicator(color: _cyan)),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 44, color: _cyan),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Réessayer')),
        ],
      ),
    );
  }
}
