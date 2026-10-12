import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'pkce.dart';

/// OpenAI "Sign in with ChatGPT" (오픈소스·로컬 앱용 구독 사용량 연동).
///
/// 공식 문서: https://developers.openai.com/siwc/token-sharing-open-source
///
/// 흐름:
///   1. 앱이 기기 안(127.0.0.1)에 작은 HTTP 서버를 띄움
///   2. 시스템 브라우저로 OpenAI 로그인 페이지를 엶
///   3. 로그인/동의가 끝나면 브라우저가 127.0.0.1의 앱 서버로 돌아옴 (code 전달)
///   4. 앱이 code를 토큰으로 교환 → 이 토큰으로 /v1/responses 호출
///
/// ⚠️ 공식 문서의 예시는 데스크톱 앱뿐이라 Android에서 동작하는지는 실기기로 확인해야 합니다.
///    (lib/dev/siwc_spike_page.dart가 그 확인용 화면)
class ChatGptSignIn {
  ChatGptSignIn({
    required this.hostId,
    required this.openBrowser,
    this.clientId,
    this.appName = 'FitMind',
    this.port = 1455,
    this.waitForForeground,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  static const authorizeUrl = 'https://auth.openai.com/api/accounts/authorize';
  static const tokenUrl = 'https://auth.openai.com/api/accounts/oauth/token';
  static const issuer = 'https://auth.openai.com';
  static const resource = 'https://api.openai.com/v1';
  static const callbackPath = '/auth/callback';

  /// 신원 + 구독 사용량 권한
  static const scopes =
      'openid profile email offline_access resource.invoke chatgpt.tokens.use.direct';

  /// 이 권한이 없으면 구독 사용량으로 AI를 호출할 수 없음
  static const planUsageScope = 'chatgpt.tokens.use.direct';

  /// 최초 등록 때만 쓰는 고정값 (저장하거나 토큰 교환에 쓰면 안 됨)
  static const _registrationClientId = 'dynamic_agent_client';

  /// 이 기기(앱 설치)를 구분하는 고정 ID. 한 번 만들면 계속 같은 값을 써야 함.
  final String hostId;

  /// 이전 로그인에서 발급받은 client_id. 처음이면 null.
  final String? clientId;

  final String appName;

  /// 루프백 포트. 최초 등록 이후에는 포트만 바뀌어도 됨.
  final int port;

  /// 시스템 브라우저로 URL을 여는 함수 (url_launcher를 주입)
  final Future<bool> Function(Uri url) openBrowser;

  /// 콜백을 받은 뒤 토큰 교환 직전에 기다릴 작업.
  ///
  /// Android 15+는 백그라운드 앱의 외부 네트워크를 막습니다. 콜백(127.0.0.1)은
  /// 기기 내부라 받아지지만, 브라우저가 앞에 있는 동안 토큰 요청은 DNS 단계에서
  /// 실패합니다 (실기기에서 확인). 그래서 앱이 다시 앞으로 올 때까지 기다립니다.
  final Future<void> Function()? waitForForeground;

  final http.Client _http;

  String get redirectUri => 'http://127.0.0.1:$port$callbackPath';

  /// 로그인 전체를 수행합니다. 사용자가 브라우저에서 완료할 때까지 기다립니다.
  Future<ChatGptCredentials> signIn({
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final state = randomUrlSafeString(16);
    final nonce = randomUrlSafeString(16);
    final verifier = randomUrlSafeString(32);

    // 브라우저를 열기 전에 서버부터 띄워야 콜백을 놓치지 않음
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    try {
      final params = <String, String>{
        'response_type': 'code',
        'client_id': clientId ?? _registrationClientId,
        'redirect_uri': redirectUri,
        'scope': scopes,
        'resource': resource,
        'state': state,
        'nonce': nonce,
        'code_challenge': pkceChallengeS256(verifier),
        'code_challenge_method': 'S256',
        'ext_agent_host_id': hostId,
        if (clientId == null) 'agent_name_hint': appName,
      };
      final url = Uri.parse('$authorizeUrl?${_encodeQuery(params)}');

      if (!await openBrowser(url)) {
        throw const ChatGptAuthException('브라우저를 열 수 없습니다.');
      }

      final callback = await _waitForCallback(server).timeout(
        timeout,
        onTimeout: () =>
            throw const ChatGptAuthException('로그인 시간이 초과되었습니다.'),
      );

      // 다른 요청이 끼어들지 않았는지 확인 (CSRF 방지)
      if (callback['state'] != state) {
        throw const ChatGptAuthException('로그인 응답이 올바르지 않습니다 (state 불일치).');
      }
      final error = callback['error'];
      if (error != null) {
        throw ChatGptAuthException(
          error == 'access_denied' ? '로그인/권한 동의가 취소되었습니다.' : '로그인 실패: $error',
        );
      }
      final code = callback['code'];
      if (code == null) {
        throw const ChatGptAuthException('로그인 응답에 code가 없습니다.');
      }

      // 최초 등록이면 콜백으로 client_id가 옴. 재로그인인데 다른 값이 오면 거부.
      final returnedClientId = callback['client_id'];
      final effectiveClientId = clientId ?? returnedClientId;
      if (effectiveClientId == null) {
        throw const ChatGptAuthException('client_id를 받지 못했습니다.');
      }
      if (clientId != null &&
          returnedClientId != null &&
          returnedClientId != clientId) {
        throw const ChatGptAuthException('client_id가 일치하지 않습니다.');
      }

      await waitForForeground?.call();

      final tokens = await _postToken({
        'grant_type': 'authorization_code',
        'client_id': effectiveClientId,
        'code': code,
        'code_verifier': verifier,
        'redirect_uri': redirectUri,
        'resource': resource,
      });

      final credentials = ChatGptCredentials.fromTokenResponse(
        tokens,
        clientId: effectiveClientId,
        hostId: hostId,
        fallbackScope: callback['scope'],
      );
      credentials.verifyIdToken(expectedNonce: nonce);

      if (!credentials.scopes.contains(planUsageScope)) {
        throw const ChatGptAuthException(
          '구독 사용량 권한이 부여되지 않았습니다. (Go/Plus/Pro 플랜이 필요합니다)',
        );
      }
      return credentials;
    } finally {
      await server.close(force: true);
    }
  }

  /// 저장된 refresh token으로 새 액세스 토큰을 받습니다.
  ///
  /// ⚠️ 공식 문서에 갱신 요청 형식이 명시되어 있지 않아 표준 OAuth 형식
  ///    (grant_type=refresh_token)으로 구현했습니다. 실기기 검증 대상입니다.
  Future<ChatGptCredentials> refresh(ChatGptCredentials current) async {
    final tokens = await _postToken({
      'grant_type': 'refresh_token',
      'client_id': current.clientId,
      'refresh_token': current.refreshToken,
      'resource': resource,
    });
    return ChatGptCredentials.fromTokenResponse(
      tokens,
      clientId: current.clientId,
      hostId: current.hostId,
      // 갱신 응답에 없는 값은 기존 값 유지
      previous: current,
    );
  }

  Future<Map<String, String>> _waitForCallback(HttpServer server) async {
    await for (final request in server) {
      if (request.uri.path != callbackPath) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        continue;
      }
      final params = request.uri.queryParameters;
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        ..write(_callbackPage(success: params['error'] == null));
      await request.response.close();
      return params;
    }
    throw const ChatGptAuthException('로그인 응답을 받기 전에 서버가 종료되었습니다.');
  }

  Future<Map<String, Object?>> _postToken(Map<String, String> form) async {
    final response = await _http.post(Uri.parse(tokenUrl), body: form);
    final Map<String, Object?> json;
    try {
      json = jsonDecode(response.body) as Map<String, Object?>;
    } catch (_) {
      throw ChatGptAuthException('토큰 응답을 해석할 수 없습니다 (HTTP ${response.statusCode}).');
    }
    if (response.statusCode != 200) {
      final error = json['error'];
      throw ChatGptAuthException(
        error == 'invalid_grant'
            ? '로그인이 만료되었습니다. 다시 로그인하세요.'
            : '토큰 발급 실패: $error ${json['error_description'] ?? ''}',
        code: error is String ? error : null,
      );
    }
    return json;
  }

  static String _encodeQuery(Map<String, String> params) => params.entries
      .map((e) =>
          '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeComponent(e.value)}')
      .join('&');

  static String _callbackPage({required bool success}) => '''
<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>FitMind</title></head>
<body style="font-family: sans-serif; text-align: center; padding: 48px 16px;">
<h2>${success ? '로그인 완료' : '로그인 실패'}</h2>
<p>FitMind 앱으로 돌아가세요.</p>
</body></html>''';
}

/// 로그인 결과 (Secure Storage에 저장할 값들).
class ChatGptCredentials {
  const ChatGptCredentials({
    required this.clientId,
    required this.hostId,
    required this.accessToken,
    required this.refreshToken,
    required this.idToken,
    required this.expiresAt,
    required this.scopes,
  });

  final String clientId;
  final String hostId;
  final String accessToken;
  final String refreshToken;
  final String idToken;
  final DateTime expiresAt;
  final Set<String> scopes;

  /// 만료 1분 전부터는 만료된 것으로 간주 (요청 도중 만료 방지)
  bool get isExpired =>
      DateTime.now().isAfter(expiresAt.subtract(const Duration(minutes: 1)));

  factory ChatGptCredentials.fromTokenResponse(
    Map<String, Object?> json, {
    required String clientId,
    required String hostId,
    String? fallbackScope,
    ChatGptCredentials? previous,
  }) {
    final accessToken = json['access_token'] as String?;
    if (accessToken == null) {
      throw const ChatGptAuthException('토큰 응답에 access_token이 없습니다.');
    }
    final scopeText = (json['scope'] as String?) ?? fallbackScope;
    final expiresIn = (json['expires_in'] as num?)?.toInt() ?? 3600;

    return ChatGptCredentials(
      clientId: clientId,
      hostId: hostId,
      accessToken: accessToken,
      // refresh token은 갱신할 때마다 바뀜(rotating) → 새 값이 있으면 교체
      refreshToken: (json['refresh_token'] as String?) ??
          previous?.refreshToken ??
          (throw const ChatGptAuthException('refresh_token이 없습니다.')),
      idToken: (json['id_token'] as String?) ?? previous?.idToken ?? '',
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
      scopes: scopeText != null
          ? scopeText.split(RegExp(r'[ +]')).where((s) => s.isNotEmpty).toSet()
          : (previous?.scopes ?? const {}),
    );
  }

  /// ID 토큰의 내용(claims) 검증: 발급자, 대상, 만료, nonce.
  ///
  /// 서명 검증은 생략합니다. 이 토큰은 앱이 TLS(HTTPS)로 OpenAI 토큰 엔드포인트에서
  /// 직접 받은 것이라, OpenID Connect 규격(Core 3.1.3.7)상 TLS 검증으로 서명 검증을
  /// 대신할 수 있습니다. (공식 문서는 JWKS 서명 검증을 권장 → 추후 보강 검토)
  void verifyIdToken({required String expectedNonce}) {
    final claims = decodeJwtClaims(idToken);
    if (claims['iss'] != ChatGptSignIn.issuer) {
      throw const ChatGptAuthException('ID 토큰 발급자가 올바르지 않습니다.');
    }
    final aud = claims['aud'];
    final audiences = aud is List ? aud : [aud];
    if (!audiences.contains(clientId)) {
      throw const ChatGptAuthException('ID 토큰 대상(aud)이 올바르지 않습니다.');
    }
    final exp = (claims['exp'] as num?)?.toInt();
    if (exp == null ||
        DateTime.fromMillisecondsSinceEpoch(exp * 1000).isBefore(DateTime.now())) {
      throw const ChatGptAuthException('ID 토큰이 만료되었습니다.');
    }
    if (claims['nonce'] != expectedNonce) {
      throw const ChatGptAuthException('ID 토큰 nonce가 일치하지 않습니다.');
    }
  }

  /// 로그인한 계정 이메일 (ID 토큰에 있을 때)
  String? get email {
    try {
      return decodeJwtClaims(idToken)['email'] as String?;
    } catch (_) {
      return null;
    }
  }

  Map<String, Object?> toJson() => {
        'client_id': clientId,
        'host_id': hostId,
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'id_token': idToken,
        'expires_at': expiresAt.toIso8601String(),
        'scopes': scopes.join(' '),
      };

  factory ChatGptCredentials.fromJson(Map<String, Object?> json) =>
      ChatGptCredentials(
        clientId: json['client_id'] as String,
        hostId: json['host_id'] as String,
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
        idToken: json['id_token'] as String,
        expiresAt: DateTime.parse(json['expires_at'] as String),
        scopes: (json['scopes'] as String)
            .split(' ')
            .where((s) => s.isNotEmpty)
            .toSet(),
      );
}

/// JWT의 가운데 부분(payload)을 디코딩합니다. (서명은 확인하지 않음)
Map<String, Object?> decodeJwtClaims(String jwt) {
  final parts = jwt.split('.');
  if (parts.length != 3) {
    throw const ChatGptAuthException('ID 토큰 형식이 올바르지 않습니다.');
  }
  final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
  return jsonDecode(payload) as Map<String, Object?>;
}

class ChatGptAuthException implements Exception {
  const ChatGptAuthException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => 'ChatGptAuthException($code): $message';
}
