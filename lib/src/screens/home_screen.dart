import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/transit_repository.dart';
import '../models/transit.dart';

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
    required this.demoMode,
  });

  final TransitRepository repository;
  final bool demoMode;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  TransitMode _mode = TransitMode.transilien;
  late TransitLine _line;
  late List<TransitLine> _availableLines;
  List<TransitStop> _availableStops = const [];
  List<TransitDirection> _availableDirections = const [];
  TransitStop? _stop;
  TransitDirection? _direction;
  TransitSnapshot? _snapshot;
  bool _loading = true;
  bool _following = false;
  String? _error;
  String _lineQuery = '';
  final TextEditingController _lineSearchController = TextEditingController();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _line = transitLines.firstWhere((line) => line.code == 'L');
    _availableLines = transitLines.where((line) => line.mode == _mode).toList();
    _bootstrap();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
      if (_stop != null && _direction != null) _refresh(silent: true);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _lineSearchController.dispose();
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
    await _loadStopsAndDirections();
  }

  Future<void> _refresh({bool silent = false}) async {
    final stop = _stop;
    final direction = _direction;
    if (stop == null || direction == null) return;
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final result = await widget.repository.fetchSnapshot(
        line: _line,
        stop: stop,
        direction: direction,
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

  Future<void> _loadStopsAndDirections() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _snapshot = null;
        _availableStops = const [];
        _availableDirections = const [];
        _stop = null;
        _direction = null;
      });
    }
    try {
      final stops = await widget.repository.fetchStops(_line);
      final stop = stops.first;
      final directions = await widget.repository.fetchDirections(_line, stop);
      if (!mounted) return;
      setState(() {
        _availableStops = stops;
        _stop = stop;
        _availableDirections = directions;
        _direction = directions.first;
      });
      await _refresh();
    } on TransitException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    }
  }

  Future<void> _selectStop(TransitStop stop) async {
    if (_stop?.id == stop.id) return;
    setState(() {
      _stop = stop;
      _direction = null;
      _availableDirections = const [];
      _snapshot = null;
      _loading = true;
      _error = null;
    });
    try {
      final directions = await widget.repository.fetchDirections(_line, stop);
      if (!mounted) return;
      setState(() {
        _availableDirections = directions;
        _direction = directions.first;
      });
      await _refresh();
    } on TransitException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    }
  }

  Future<void> _selectDirection(TransitDirection direction) async {
    if (_direction?.id == direction.id) return;
    setState(() {
      _direction = direction;
      _snapshot = null;
      _following = false;
    });
    await _refresh();
  }

  Future<void> _selectMode(TransitMode mode) async {
    if (_mode == mode) return;
    final localLines = transitLines.where((line) => line.mode == mode).toList();
    final nextLine = localLines.first;
    _lineSearchController.clear();
    setState(() {
      _mode = mode;
      _lineQuery = '';
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
    await _loadStopsAndDirections();
  }

  Future<void> _selectLine(TransitLine line) async {
    if (_line == line) return;
    setState(() {
      _line = line;
      _snapshot = null;
      _following = false;
    });
    await _saveSelection();
    await _loadStopsAndDirections();
  }

  Future<void> _saveSelection() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_mode', _mode.name);
    await prefs.setString('selected_line', _line.code);
  }

  Departure? get _primaryDeparture {
    final departures = _snapshot?.departures;
    if (departures == null || departures.isEmpty) return null;
    return departures[0];
  }

  @override
  Widget build(BuildContext context) {
    final query = _lineQuery.trim().toLowerCase();
    final matchingLines = _availableLines
        .where((line) => line.code.toLowerCase().contains(query))
        .toList();
    final lineChoices = _mode == TransitMode.bus && query.isEmpty
        ? matchingLines.take(30).toList()
        : matchingLines.take(100).toList();
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
                          if (_mode == TransitMode.bus) ...[
                            _BusLineSearch(
                              controller: _lineSearchController,
                              totalLines: _availableLines.length,
                              resultCount: matchingLines.length,
                              onChanged: (value) =>
                                  setState(() => _lineQuery = value),
                            ),
                            const SizedBox(height: 12),
                          ],
                          _LineSelector(
                            lines: lineChoices,
                            selected: _line,
                            onSelected: _selectLine,
                          ),
                          const SizedBox(height: 24),
                          const _StepTitle(
                            number: '3',
                            label: 'Arrêt et direction',
                          ),
                          const SizedBox(height: 12),
                          _StopSelector(
                            key: ValueKey('stops-${_line.lineRef}'),
                            stops: _availableStops,
                            selected: _stop,
                            onSelected: _selectStop,
                          ),
                          const SizedBox(height: 10),
                          _DirectionSelector(
                            key: ValueKey(
                              'directions-${_line.lineRef}-${_stop?.id}',
                            ),
                            directions: _availableDirections,
                            selected: _direction,
                            onSelected: _selectDirection,
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
    if (departure == null) {
      return _NoDepartureCard(line: _line, onRetry: _refresh);
    }
    return Column(
      key: ValueKey('${_mode.name}-${_line.code}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _NextDepartureCard(
          mode: _mode,
          line: _line,
          departure: departure,
          snapshot: _snapshot!,
          nearby: false,
        ),
        const SizedBox(height: 14),
        _MapCard(departure: departure),
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
      ],
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
    if (lines.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'Aucune ligne ne correspond à cette recherche.',
          style: TextStyle(color: _muted),
        ),
      );
    }
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

class _BusLineSearch extends StatelessWidget {
  const _BusLineSearch({
    required this.controller,
    required this.totalLines,
    required this.resultCount,
    required this.onChanged,
  });

  final TextEditingController controller;
  final int totalLines;
  final int resultCount;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: TextInputType.text,
      textInputAction: TextInputAction.search,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      decoration: InputDecoration(
        hintText: 'Rechercher un bus, ex. 256',
        helperText: controller.text.isEmpty
            ? '$totalLines lignes disponibles · saisissez un numéro'
            : '$resultCount résultat${resultCount > 1 ? 's' : ''}',
        prefixIcon: const Icon(Icons.search_rounded, color: _cyan),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Effacer la recherche',
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
                icon: const Icon(Icons.close_rounded),
              ),
        filled: true,
        fillColor: _panel,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFF28496D)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFF28496D)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: _cyan, width: 2),
        ),
      ),
    );
  }
}

class _StopSelector extends StatelessWidget {
  const _StopSelector({
    super.key,
    required this.stops,
    required this.selected,
    required this.onSelected,
  });

  final List<TransitStop> stops;
  final TransitStop? selected;
  final ValueChanged<TransitStop> onSelected;

  @override
  Widget build(BuildContext context) {
    if (stops.isEmpty) return const _SelectorPlaceholder('Chargement des arrêts…');
    return DropdownButtonFormField<TransitStop>(
      initialValue: selected,
      isExpanded: true,
      menuMaxHeight: 420,
      decoration: _selectorDecoration(
        label: 'Arrêt',
        icon: Icons.location_on_outlined,
      ),
      items: stops
          .map(
            (stop) => DropdownMenuItem(
              value: stop,
              child: Text(stop.name, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) onSelected(value);
      },
    );
  }
}

class _DirectionSelector extends StatelessWidget {
  const _DirectionSelector({
    super.key,
    required this.directions,
    required this.selected,
    required this.onSelected,
  });

  final List<TransitDirection> directions;
  final TransitDirection? selected;
  final ValueChanged<TransitDirection> onSelected;

  @override
  Widget build(BuildContext context) {
    if (directions.isEmpty) {
      return const _SelectorPlaceholder('Chargement des directions…');
    }
    return DropdownButtonFormField<TransitDirection>(
      initialValue: selected,
      isExpanded: true,
      menuMaxHeight: 320,
      decoration: _selectorDecoration(
        label: 'Direction',
        icon: Icons.alt_route_rounded,
      ),
      items: directions
          .map(
            (direction) => DropdownMenuItem(
              value: direction,
              child: Text(direction.label, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) onSelected(value);
      },
    );
  }
}

class _SelectorPlaceholder extends StatelessWidget {
  const _SelectorPlaceholder(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF28496D)),
      ),
      child: Text(label, style: const TextStyle(color: _muted)),
    );
  }
}

InputDecoration _selectorDecoration({
  required String label,
  required IconData icon,
}) {
  return InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, color: _cyan),
    filled: true,
    fillColor: _panel,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: Color(0xFF28496D)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: _cyan, width: 2),
    ),
  );
}

class _NextDepartureCard extends StatelessWidget {
  const _NextDepartureCard({
    required this.mode,
    required this.line,
    required this.departure,
    required this.snapshot,
    required this.nearby,
  });

  final TransitMode mode;
  final TransitLine line;
  final Departure departure;
  final TransitSnapshot snapshot;
  final bool nearby;

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
                       nearby
                           ? '${departure.stopName} — à ${departure.walkingMinutes} min à pied'
                           : '${departure.stopName} — arrêt sélectionné',
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
  const _MapCard({required this.departure});
  final Departure departure;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _panelLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const Icon(Icons.route_rounded, color: _cyan, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  departure.stopName,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Arrêt de référence de la ligne · aucune localisation requise',
                  style: TextStyle(color: _muted),
                ),
              ],
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

class _NoDepartureCard extends StatelessWidget {
  const _NoDepartureCard({required this.line, required this.onRetry});

  final TransitLine line;
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
          Icon(Icons.schedule_rounded, size: 44, color: line.color),
          const SizedBox(height: 12),
          const Text(
            'Aucun passage annoncé actuellement pour cet arrêt et cette direction.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Actualiser'),
          ),
        ],
      ),
    );
  }
}
