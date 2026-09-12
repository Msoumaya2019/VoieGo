class AppConfig {
  const AppConfig({required this.apiBaseUrl});

  factory AppConfig.fromEnvironment() {
    return const AppConfig(
      apiBaseUrl: String.fromEnvironment('VOIEGO_API_BASE_URL'),
    );
  }

  final String apiBaseUrl;

  bool get demoMode => apiBaseUrl.trim().isEmpty;
}
