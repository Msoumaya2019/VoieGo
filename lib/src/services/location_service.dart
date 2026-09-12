import 'package:geolocator/geolocator.dart';

class UserLocation {
  const UserLocation(this.latitude, this.longitude);
  final double latitude;
  final double longitude;
}

class LocationService {
  Future<UserLocation?> currentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 8),
      ),
    );
    return UserLocation(position.latitude, position.longitude);
  }
}
