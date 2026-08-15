import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AiServiceConfiguration {
  const AiServiceConfiguration({
    required this.backendUrl,
    required this.accessToken,
  });

  final String backendUrl;
  final String accessToken;

  bool get isConfigured =>
      backendUrl.trim().isNotEmpty && accessToken.trim().isNotEmpty;
}

abstract interface class AiServiceSettings {
  Future<AiServiceConfiguration> load();

  Future<void> save(AiServiceConfiguration configuration);
}

class SecureAiServiceSettings implements AiServiceSettings {
  SecureAiServiceSettings([this._secureStorage = const FlutterSecureStorage()]);

  static const _backendUrlKey = 'recall_ai_backend_url';
  static const _accessTokenKey = 'recall_ai_backend_access_token';

  final FlutterSecureStorage _secureStorage;

  @override
  Future<AiServiceConfiguration> load() async {
    final preferences = await SharedPreferences.getInstance();
    return AiServiceConfiguration(
      backendUrl: preferences.getString(_backendUrlKey) ?? '',
      accessToken: await _secureStorage.read(key: _accessTokenKey) ?? '',
    );
  }

  @override
  Future<void> save(AiServiceConfiguration configuration) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _backendUrlKey,
      configuration.backendUrl.trim(),
    );
    await _secureStorage.write(
      key: _accessTokenKey,
      value: configuration.accessToken.trim(),
    );
  }
}

class MemoryAiServiceSettings implements AiServiceSettings {
  MemoryAiServiceSettings([
    this.configuration = const AiServiceConfiguration(
      backendUrl: '',
      accessToken: '',
    ),
  ]);

  AiServiceConfiguration configuration;

  @override
  Future<AiServiceConfiguration> load() async => configuration;

  @override
  Future<void> save(AiServiceConfiguration value) async {
    configuration = value;
  }
}
