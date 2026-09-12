import 'package:geolocator/geolocator.dart';

class UserLocation {
  const UserLocation(this.latitude, this.longitude);
  final double latitude;
  final double longitude;
}

class LocationService {
  Future<UserLocation> requestCurrentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException(
        'Activez la localisation de votre téléphone pour utiliser Autour de moi.',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const LocationException(
        'Autorisez la localisation dans les réglages pour afficher les arrêts proches.',
      );
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 10),
      ),
    );
    return UserLocation(position.latitude, position.longitude);
  }
}

class LocationException implements Exception {
  const LocationException(this.message);
  final String message;
}
