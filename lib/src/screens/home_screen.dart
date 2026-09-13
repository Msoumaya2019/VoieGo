import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/transit_repository.dart';
import '../models/transit.dart';
import '../services/location_service.dart';
import '../services/push_notification_service.dart';

const _navy = Color(0xFF07182F);
const _cyan = Color(0xFF5FE3FF);
const _yellow = Color(0xFFFFC83D);
const _green = Color(0xFF5DF18C);

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.repository,
    required this.locationService,
    required this.demoMode,
    required this.darkMode,
    required this.onDarkModeChanged,
    required this.pushNotifications,
  });

  final TransitRepository repository;
  final LocationService locationService;
  final bool demoMode;
  final bool darkMode;
  final ValueChanged<bool> onDarkModeChanged;
  final PushNotificationService pushNotifications;

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
  String? _error;
  String _lineQuery = '';
  final TextEditingController _lineSearchController = TextEditingController();
  Timer? _ticker;
  int _selectedTab = 0;
  List<FavoriteJourney> _favorites = const [];
  List<NearbyStop> _nearbyStops = const [];
  bool _nearbyLoading = false;
  String? _nearbyError;
  bool _autoRefresh = true;
  int _refreshIntervalSeconds = 30;
  int _nearbyRadiusMeters = 1000;
  int _lastPushMessageSequence = 0;

  @override
  void initState() {
    super.initState();
    _line = transitLines.firstWhere((line) => line.code == 'L');
    _availableLines = transitLines.where((line) => line.mode == _mode).toList();
    _bootstrap();
    _restartTicker();
    widget.pushNotifications.addListener(_handlePushNotificationChange);
  }

  void _handlePushNotificationChange() {
    if (!mounted) return;
    setState(() {});
    final service = widget.pushNotifications;
    if (service.messageSequence <= _lastPushMessageSequence) return;
    _lastPushMessageSequence = service.messageSequence;
    final notification = service.latestMessage?.notification;
    final title = notification?.title ?? 'Nouvelle information VoieGo';
    final body = notification?.body;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(body == null ? title : '$title\n$body')),
      );
    });
  }

  void _restartTicker() {
    _ticker?.cancel();
    if (!_autoRefresh) return;
    _ticker = Timer.periodic(Duration(seconds: _refreshIntervalSeconds), (_) {
      if (mounted) setState(() {});
      if (_stop != null && _direction != null) _refresh(silent: true);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _lineSearchController.dispose();
    widget.pushNotifications.removeListener(_handlePushNotificationChange);
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final storedMode = prefs.getString('selected_mode');
    final storedLine = prefs.getString('selected_line');
    _autoRefresh = prefs.getBool('auto_refresh') ?? true;
    _refreshIntervalSeconds = prefs.getInt('refresh_interval') ?? 30;
    _nearbyRadiusMeters = prefs.getInt('nearby_radius') ?? 1000;
    final storedFavorites = prefs.getStringList('favorites') ?? const [];
    _favorites = storedFavorites
        .map((value) {
          try {
            return FavoriteJourney.fromJson(
              jsonDecode(value) as Map<String, dynamic>,
            );
          } catch (_) {
            return null;
          }
        })
        .whereType<FavoriteJourney>()
        .toList();
    _restartTicker();
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
    });
    await _refresh();
  }

  Future<void> _selectMode(TransitMode mode) async {
    if (_mode == mode) return;
    final localLines = transitLines.where((line) => line.mode == mode).toList();
    final nextLine = localLines.firstOrNull;
    _lineSearchController.clear();
    setState(() {
      _mode = mode;
      _lineQuery = '';
      if (nextLine != null) _line = nextLine;
      _availableLines = localLines;
      _snapshot = null;
      _loading = true;
      _error = null;
    });
    try {
      final remoteLines = await widget.repository.fetchLines(mode);
      if (mounted && remoteLines.isNotEmpty) {
        setState(() {
          _availableLines = remoteLines;
          _line = remoteLines.first;
        });
      }
    } on TransitException catch (error) {
      if (localLines.isEmpty && mounted) {
        setState(() {
          _loading = false;
          _error = error.message;
        });
        return;
      }
    }
    await _saveSelection();
    await _loadStopsAndDirections();
  }

  Future<void> _selectLine(TransitLine line) async {
    if (_line == line) return;
    setState(() {
      _line = line;
      _snapshot = null;
    });
    await _saveSelection();
    await _loadStopsAndDirections();
  }

  Future<void> _saveSelection() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_mode', _mode.name);
    await prefs.setString('selected_line', _line.code);
  }

  FavoriteJourney? get _currentFavorite {
    final stop = _stop;
    final direction = _direction;
    if (stop == null || direction == null) return null;
    final key = '${_line.lineRef}|${stop.id}|${direction.id}';
    return _favorites.where((favorite) => favorite.key == key).firstOrNull;
  }

  Future<void> _toggleFavorite() async {
    final stop = _stop;
    final direction = _direction;
    if (stop == null || direction == null) return;
    final favorite = FavoriteJourney(
      line: _line,
      stop: stop,
      direction: direction,
    );
    setState(() {
      final exists = _favorites.any((item) => item.key == favorite.key);
      _favorites = exists
          ? _favorites.where((item) => item.key != favorite.key).toList()
          : [..._favorites, favorite];
    });
    await _saveFavorites();
  }

  Future<void> _saveFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'favorites',
      _favorites.map((item) => jsonEncode(item.toJson())).toList(),
    );
  }

  Future<void> _openFavorite(FavoriteJourney favorite) async {
    setState(() {
      _selectedTab = 0;
      _mode = favorite.line.mode;
      _line = favorite.line;
      _stop = favorite.stop;
      _direction = favorite.direction;
      _snapshot = null;
      _loading = true;
      _error = null;
      _lineQuery = '';
      _lineSearchController.clear();
    });
    try {
      final results = await Future.wait([
        widget.repository.fetchLines(favorite.line.mode),
        widget.repository.fetchStops(favorite.line),
        widget.repository.fetchDirections(favorite.line, favorite.stop),
      ]);
      if (!mounted) return;
      final lines = results[0] as List<TransitLine>;
      final stops = results[1] as List<TransitStop>;
      final directions = results[2] as List<TransitDirection>;
      setState(() {
        _availableLines = lines;
        _line = lines.where((item) => item.lineRef == favorite.line.lineRef).firstOrNull ?? favorite.line;
        _availableStops = stops;
        _stop = stops.where((item) => item.id == favorite.stop.id).firstOrNull ?? favorite.stop;
        _availableDirections = directions;
        _direction = directions.where((item) => item.id == favorite.direction.id).firstOrNull ?? favorite.direction;
      });
      await _saveSelection();
      await _refresh();
    } on TransitException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    }
  }

  Future<void> _loadNearbyStops() async {
    setState(() {
      _nearbyLoading = true;
      _nearbyError = null;
    });
    try {
      final location = await widget.locationService.requestCurrentLocation();
      final stops = await widget.repository.fetchNearbyStops(
        latitude: location.latitude,
        longitude: location.longitude,
        radiusMeters: _nearbyRadiusMeters,
      );
      if (!mounted) return;
      setState(() {
        _nearbyStops = stops;
        _nearbyLoading = false;
      });
    } on LocationException catch (error) {
      if (!mounted) return;
      setState(() {
        _nearbyLoading = false;
        _nearbyError = error.message;
      });
    } on TransitException catch (error) {
      if (!mounted) return;
      setState(() {
        _nearbyLoading = false;
        _nearbyError = error.message;
      });
    }
  }

  Future<void> _updateSettings({
    bool? autoRefresh,
    int? refreshInterval,
    int? nearbyRadius,
  }) async {
    setState(() {
      if (autoRefresh != null) _autoRefresh = autoRefresh;
      if (refreshInterval != null) _refreshIntervalSeconds = refreshInterval;
      if (nearbyRadius != null) _nearbyRadiusMeters = nearbyRadius;
    });
    _restartTicker();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_refresh', _autoRefresh);
    await prefs.setInt('refresh_interval', _refreshIntervalSeconds);
    await prefs.setInt('nearby_radius', _nearbyRadiusMeters);
  }

  Future<void> _clearFavorites() async {
    setState(() => _favorites = const []);
    await _saveFavorites();
  }

  Future<void> _setPushNotifications(bool value) async {
    await widget.pushNotifications.setEnabled(value);
    if (!mounted) return;
    setState(() {});
    final error = widget.pushNotifications.error;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
    }
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
      body: switch (_selectedTab) {
        0 => SafeArea(
        child: RefreshIndicator(
          color: _cyan,
          backgroundColor: Theme.of(context).colorScheme.surface,
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
        1 => _FavoritesTab(
          favorites: _favorites,
          onOpen: _openFavorite,
          onRemove: (favorite) async {
            setState(() {
              _favorites = _favorites
                  .where((item) => item.key != favorite.key)
                  .toList();
            });
            await _saveFavorites();
          },
        ),
        2 => _NearbyTab(
          stops: _nearbyStops,
          loading: _nearbyLoading,
          error: _nearbyError,
          radiusMeters: _nearbyRadiusMeters,
          onLoad: _loadNearbyStops,
        ),
        _ => _SettingsTab(
          darkMode: widget.darkMode,
          autoRefresh: _autoRefresh,
          refreshIntervalSeconds: _refreshIntervalSeconds,
          nearbyRadiusMeters: _nearbyRadiusMeters,
          favoritesCount: _favorites.length,
          pushNotificationsAvailable: widget.pushNotifications.available,
          pushNotificationsEnabled: widget.pushNotifications.enabled,
          pushNotificationsBusy: widget.pushNotifications.busy,
          pushNotificationToken: widget.pushNotifications.token,
          onDarkModeChanged: widget.onDarkModeChanged,
          onPushNotificationsChanged: _setPushNotifications,
          onAutoRefreshChanged: (value) =>
              _updateSettings(autoRefresh: value),
          onRefreshIntervalChanged: (value) =>
              _updateSettings(refreshInterval: value),
          onNearbyRadiusChanged: (value) =>
              _updateSettings(nearbyRadius: value),
          onClearFavorites: _clearFavorites,
        ),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) => setState(() => _selectedTab = index),
        backgroundColor: Theme.of(context).colorScheme.surface,
        indicatorColor: _cyan,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.schedule_rounded),
            selectedIcon: Icon(Icons.schedule_rounded, color: _navy),
            label: 'Horaires',
          ),
          NavigationDestination(
            icon: Icon(Icons.star_border_rounded),
            selectedIcon: Icon(Icons.star_rounded, color: _navy),
            label: 'Favoris',
          ),
          NavigationDestination(
            icon: Icon(Icons.near_me_outlined),
            selectedIcon: Icon(Icons.near_me_rounded, color: _navy),
            label: 'Autour',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded, color: _navy),
            label: 'Réglages',
          ),
        ],
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
    final isFavorite = _currentFavorite != null;
    final departures = _snapshot?.departures ?? const <Departure>[];
    final followingDeparture = departures.length > 1 ? departures[1] : null;
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
        if (_snapshot?.alert case final alert?) ...[
          const SizedBox(height: 14),
          _AlertCard(alert: alert, onTap: () => _showTraffic(alert)),
        ],
        if (followingDeparture != null) ...[
          const SizedBox(height: 12),
          _FollowingDepartureCard(departure: followingDeparture),
        ],
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _toggleFavorite,
          icon: Icon(
            isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
          ),
          label: Text(
            isFavorite ? 'Retirer des favoris' : 'Ajouter aux favoris',
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
      backgroundColor: Theme.of(context).colorScheme.surface,
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
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 16,
                ),
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
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  style: TextStyle(
                    fontSize: 30,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  children: const [
                    TextSpan(text: 'Voie'),
                    TextSpan(
                      text: 'Go',
                      style: TextStyle(color: _cyan),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'PLUS LOIN ENSEMBLE',
                style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 3,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
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
    return SizedBox(
      height: 58,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: TransitMode.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final mode = TransitMode.values[index];
          final active = mode == selected;
          return Semantics(
            selected: active,
            button: true,
            label: 'Réseau ${mode.label}',
            child: InkWell(
              onTap: () => onSelected(mode),
              borderRadius: BorderRadius.circular(16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                constraints: const BoxConstraints(minWidth: 86),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: active
                      ? const Color(0xFFEAE7FF)
                      : Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: active
                        ? Colors.white
                        : Theme.of(context).colorScheme.outline,
                    width: active ? 2 : 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      mode.iconLabel,
                      style: TextStyle(
                        color: active ? _navy : _cyan,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      mode.label,
                      style: TextStyle(
                        color: active
                            ? _navy
                            : Theme.of(context).colorScheme.onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
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
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'Aucune ligne ne correspond à cette recherche.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
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
                  width: line.mode == TransitMode.bus ? 54 : 42,
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
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        line.code,
                        maxLines: 1,
                        style: TextStyle(
                          color: line.textColor,
                          fontSize: line.code.length >= 4 ? 17 : 21,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
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
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
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
        fillColor: Theme.of(context).colorScheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
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
        context,
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
        context,
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
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Text(
        label,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

InputDecoration _selectorDecoration(
  BuildContext context, {
  required String label,
  required IconData icon,
}) {
  return InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, color: _cyan),
    filled: true,
    fillColor: Theme.of(context).colorScheme.surface,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
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
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
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
                  Icon(
                    Icons.location_on_rounded,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                       nearby
                           ? '${departure.stopName} — à ${departure.walkingMinutes} min à pied'
                           : '${departure.stopName} — arrêt sélectionné',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                snapshot.isDemo
                    ? 'Aperçu avec données de démonstration'
                    : 'Mis à jour il y a moins d’une minute · ${departure.confidence}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FollowingDepartureCard extends StatelessWidget {
  const _FollowingDepartureCard({required this.departure});

  final Departure departure;

  @override
  Widget build(BuildContext context) {
    final minutes = departure.minutesFrom(DateTime.now());
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule_rounded, color: _cyan, size: 22),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              'Le suivant est à $minutes min · vers ${departure.destination}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
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
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
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
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
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

class _FavoritesTab extends StatelessWidget {
  const _FavoritesTab({
    required this.favorites,
    required this.onOpen,
    required this.onRemove,
  });

  final List<FavoriteJourney> favorites;
  final ValueChanged<FavoriteJourney> onOpen;
  final ValueChanged<FavoriteJourney> onRemove;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 36),
            children: [
              const _TabHeader(
                icon: Icons.star_rounded,
                title: 'Favoris',
                subtitle: 'Vos arrêts et directions en accès direct',
              ),
              const SizedBox(height: 22),
              if (favorites.isEmpty)
                const _EmptyTabCard(
                  icon: Icons.star_border_rounded,
                  message:
                      'Ajoutez un arrêt et sa direction depuis l’onglet Horaires.',
                )
              else
                ...favorites.map(
                  (favorite) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Material(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        onTap: () => onOpen(favorite),
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                width: 54,
                                height: 48,
                                padding: const EdgeInsets.all(4),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: favorite.line.color,
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                child: FittedBox(
                                  child: Text(
                                    favorite.line.code,
                                    style: TextStyle(
                                      color: favorite.line.textColor,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 13),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      favorite.stop.name,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      favorite.direction.label,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Retirer des favoris',
                                onPressed: () => onRemove(favorite),
                                icon: const Icon(
                                  Icons.star_rounded,
                                  color: _yellow,
                                ),
                              ),
                            ],
                          ),
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
}

class _NearbyTab extends StatelessWidget {
  const _NearbyTab({
    required this.stops,
    required this.loading,
    required this.error,
    required this.radiusMeters,
    required this.onLoad,
  });

  final List<NearbyStop> stops;
  final bool loading;
  final String? error;
  final int radiusMeters;
  final VoidCallback onLoad;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 36),
            children: [
              const _TabHeader(
                icon: Icons.near_me_rounded,
                title: 'Autour de moi',
                subtitle: 'Les arrêts les plus proches, à votre demande',
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: loading ? null : onLoad,
                icon: loading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location_rounded),
                label: Text(
                  loading
                      ? 'Recherche en cours…'
                      : 'Trouver les arrêts dans un rayon de $radiusMeters m',
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  backgroundColor: _cyan,
                  foregroundColor: _navy,
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 14),
                _EmptyTabCard(
                  icon: Icons.location_off_rounded,
                  message: error!,
                ),
              ],
              if (!loading && error == null && stops.isEmpty) ...[
                const SizedBox(height: 14),
                const _EmptyTabCard(
                  icon: Icons.location_searching_rounded,
                  message:
                      'La localisation reste désactivée tant que vous n’appuyez pas sur le bouton.',
                ),
              ],
              if (stops.isNotEmpty) ...[
                const SizedBox(height: 20),
                ...stops.map(
                  (stop) => ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    tileColor: Theme.of(context).colorScheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    leading: CircleAvatar(
                      backgroundColor:
                          Theme.of(context).colorScheme.surfaceContainerHigh,
                      child: const Icon(
                        Icons.directions_transit_rounded,
                        color: _cyan,
                      ),
                    ),
                    title: Text(
                      stop.name,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    trailing: Text(
                      stop.distanceMeters < 1000
                          ? '${stop.distanceMeters} m'
                          : '${(stop.distanceMeters / 1000).toStringAsFixed(1)} km',
                      style: const TextStyle(color: _cyan),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab({
    required this.darkMode,
    required this.autoRefresh,
    required this.refreshIntervalSeconds,
    required this.nearbyRadiusMeters,
    required this.favoritesCount,
    required this.pushNotificationsAvailable,
    required this.pushNotificationsEnabled,
    required this.pushNotificationsBusy,
    required this.pushNotificationToken,
    required this.onDarkModeChanged,
    required this.onPushNotificationsChanged,
    required this.onAutoRefreshChanged,
    required this.onRefreshIntervalChanged,
    required this.onNearbyRadiusChanged,
    required this.onClearFavorites,
  });

  final bool darkMode;
  final bool autoRefresh;
  final int refreshIntervalSeconds;
  final int nearbyRadiusMeters;
  final int favoritesCount;
  final bool pushNotificationsAvailable;
  final bool pushNotificationsEnabled;
  final bool pushNotificationsBusy;
  final String? pushNotificationToken;
  final ValueChanged<bool> onDarkModeChanged;
  final ValueChanged<bool> onPushNotificationsChanged;
  final ValueChanged<bool> onAutoRefreshChanged;
  final ValueChanged<int> onRefreshIntervalChanged;
  final ValueChanged<int> onNearbyRadiusChanged;
  final VoidCallback onClearFavorites;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 36),
            children: [
              const _TabHeader(
                icon: Icons.settings_rounded,
                title: 'Réglages',
                subtitle: 'Personnalisez le fonctionnement de VoieGo',
              ),
              const SizedBox(height: 22),
              SwitchListTile(
                value: darkMode,
                onChanged: onDarkModeChanged,
                tileColor: Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                secondary: Icon(
                  darkMode ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                  color: _cyan,
                ),
                title: Text(darkMode ? 'Mode sombre' : 'Mode jour'),
                subtitle: const Text('Changer l’apparence de l’application'),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                value: autoRefresh,
                onChanged: onAutoRefreshChanged,
                tileColor: Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                title: const Text('Actualisation automatique'),
                subtitle: const Text('Mettre à jour les horaires en arrière-plan'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: refreshIntervalSeconds,
                decoration: _selectorDecoration(
                  context,
                  label: 'Fréquence d’actualisation',
                  icon: Icons.refresh_rounded,
                ),
                items: const [30, 60, 120]
                    .map(
                      (seconds) => DropdownMenuItem(
                        value: seconds,
                        child: Text('$seconds secondes'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) onRefreshIntervalChanged(value);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: nearbyRadiusMeters,
                decoration: _selectorDecoration(
                  context,
                  label: 'Rayon autour de moi',
                  icon: Icons.radar_rounded,
                ),
                items: const [500, 1000, 2000, 3000]
                    .map(
                      (meters) => DropdownMenuItem(
                        value: meters,
                        child: Text('$meters mètres'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) onNearbyRadiusChanged(value);
                },
              ),
              const SizedBox(height: 12),
              ListTile(
                tileColor: Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                leading: const Icon(Icons.delete_outline_rounded, color: _yellow),
                title: const Text('Effacer les favoris'),
                subtitle: Text('$favoritesCount favori${favoritesCount > 1 ? 's' : ''} enregistré${favoritesCount > 1 ? 's' : ''}'),
                enabled: favoritesCount > 0,
                onTap: favoritesCount > 0 ? onClearFavorites : null,
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                value: pushNotificationsEnabled,
                onChanged: pushNotificationsAvailable &&
                        !pushNotificationsBusy
                    ? onPushNotificationsChanged
                    : null,
                tileColor: Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                secondary: const Icon(
                  Icons.notifications_active_outlined,
                  color: _cyan,
                ),
                title: const Text('Notifications push'),
                subtitle: Text(
                  pushNotificationsBusy
                      ? 'Activation en cours…'
                      : pushNotificationsAvailable
                          ? 'Alertes reçues via Firebase sur cet appareil Android.'
                          : 'Disponible actuellement dans la version Android.',
                ),
              ),
              if (pushNotificationsEnabled && pushNotificationToken != null) ...[
                const SizedBox(height: 8),
                ListTile(
                  tileColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  leading: const Icon(Icons.key_rounded, color: _cyan),
                  title: const Text('Identifiant de test Firebase'),
                  subtitle: Text(
                    '${pushNotificationToken!.substring(0, 18)}…',
                  ),
                  trailing: IconButton(
                    tooltip: 'Copier l’identifiant',
                    icon: const Icon(Icons.copy_rounded),
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: pushNotificationToken!),
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Identifiant Firebase copié.'),
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 12),
              ListTile(
                tileColor: Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                leading: const Icon(Icons.shield_outlined, color: _cyan),
                title: const Text('Confidentialité'),
                subtitle: const Text(
                  'La position est utilisée uniquement à la demande et les favoris restent sur l’appareil.',
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                tileColor: Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                leading: const Icon(Icons.info_outline_rounded, color: _cyan),
                title: const Text('VoieGo 1.1.0'),
                subtitle: const Text(
                  'Données : Île-de-France Mobilités / PRIM',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabHeader extends StatelessWidget {
  const _TabHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 25,
          backgroundColor: _cyan,
          child: Icon(icon, color: _navy),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyTabCard extends StatelessWidget {
  const _EmptyTabCard({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(icon, color: _cyan, size: 42),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
        ],
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
        color: Theme.of(context).colorScheme.surface,
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
        color: Theme.of(context).colorScheme.surface,
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
