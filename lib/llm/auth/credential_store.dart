import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'chatgpt_sign_in.dart';
import 'pkce.dart';

/// LLM 인증 정보 저장소 (Android Keystore 기반 Secure Storage).
///
/// SQLite에는 절대 저장하지 않습니다. `.db` 파일은 백업/공유될 수 있기 때문입니다.
class LlmCredentialStore {
  LlmCredentialStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _hostIdKey = 'chatgpt_host_id';
  static const _clientIdKey = 'chatgpt_client_id';
  static const _credentialsKey = 'chatgpt_credentials';
  static const _apiKeyKey = 'openai_api_key';

  /// 이 앱 설치를 구분하는 고정 ID. 없으면 만들어서 저장합니다.
  Future<String> hostId() async {
    final existing = await _storage.read(key: _hostIdKey);
    if (existing != null) return existing;
    final created = newUrnUuid();
    await _storage.write(key: _hostIdKey, value: created);
    return created;
  }

  /// 이전에 발급받은 client_id (로그아웃해도 유지 → 재로그인 시 재사용)
  Future<String?> clientId() => _storage.read(key: _clientIdKey);

  Future<ChatGptCredentials?> readChatGpt() async {
    final raw = await _storage.read(key: _credentialsKey);
    if (raw == null) return null;
    try {
      return ChatGptCredentials.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (_) {
      return null; // 형식이 깨졌으면 다시 로그인하게 함
    }
  }

  Future<void> saveChatGpt(ChatGptCredentials credentials) async {
    await _storage.write(key: _clientIdKey, value: credentials.clientId);
    await _storage.write(
      key: _credentialsKey,
      value: jsonEncode(credentials.toJson()),
    );
  }

  /// 로그아웃: 토큰만 삭제 (host id와 client id는 유지)
  Future<void> clearChatGpt() => _storage.delete(key: _credentialsKey);

  Future<String?> readApiKey() => _storage.read(key: _apiKeyKey);

  Future<void> saveApiKey(String key) =>
      _storage.write(key: _apiKeyKey, value: key.trim());

  Future<void> clearApiKey() => _storage.delete(key: _apiKeyKey);
}

/// 저장된 ChatGPT 로그인 정보로 항상 유효한 액세스 토큰을 돌려줍니다.
///
/// OpenAIService의 `token` 자리에 [accessToken]을 넘겨 사용합니다.
class ChatGptSession {
  ChatGptSession({required this.store, required this.signIn});

  final LlmCredentialStore store;
  final ChatGptSignIn signIn;

  Future<String> accessToken() async {
    final current = await store.readChatGpt();
    if (current == null) {
      throw const ChatGptAuthException('ChatGPT 로그인이 필요합니다.');
    }
    if (!current.isExpired) return current.accessToken;

    final refreshed = await signIn.refresh(current);
    await store.saveChatGpt(refreshed);
    return refreshed.accessToken;
  }
}
