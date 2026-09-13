import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class PushNotificationService extends ChangeNotifier {
  bool _available = false;
  bool _enabled = false;
  bool _busy = false;
  String? _token;
  String? _error;
  RemoteMessage? _latestMessage;
  int _messageSequence = 0;
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _messageSubscription;

  bool get available => _available;
  bool get enabled => _enabled;
  bool get busy => _busy;
  String? get token => _token;
  String? get error => _error;
  RemoteMessage? get latestMessage => _latestMessage;
  int get messageSequence => _messageSequence;

  Future<void> initialize() async {
    if (!Platform.isAndroid) return;
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(
        firebaseMessagingBackgroundHandler,
      );
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.getNotificationSettings();
      _available = true;
      _enabled = _isAuthorized(settings.authorizationStatus);
      if (_enabled) _token = await messaging.getToken();
      _tokenSubscription = messaging.onTokenRefresh.listen((value) {
        _token = value;
        notifyListeners();
      });
      _messageSubscription = FirebaseMessaging.onMessage.listen((message) {
        _latestMessage = message;
        _messageSequence += 1;
        notifyListeners();
      });
    } catch (error) {
      _error = 'Firebase n’a pas pu être initialisé : $error';
    }
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    if (!_available || _busy) return;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final messaging = FirebaseMessaging.instance;
      if (value) {
        await messaging.setAutoInitEnabled(true);
        final settings = await messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        _enabled = _isAuthorized(settings.authorizationStatus);
        if (_enabled) {
          _token = await messaging.getToken();
        } else {
          _error = 'Autorisation de notifications refusée sur cet appareil.';
        }
      } else {
        await messaging.setAutoInitEnabled(false);
        await messaging.deleteToken();
        _enabled = false;
        _token = null;
      }
    } catch (error) {
      _error = 'Impossible de modifier les notifications : $error';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  bool _isAuthorized(AuthorizationStatus status) {
    return status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional;
  }

  @override
  void dispose() {
    _tokenSubscription?.cancel();
    _messageSubscription?.cancel();
    super.dispose();
  }
}
