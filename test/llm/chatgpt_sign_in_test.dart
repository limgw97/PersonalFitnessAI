import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fitmind/llm/auth/chatgpt_sign_in.dart';
import 'package:fitmind/llm/auth/pkce.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 서명 없는 테스트용 JWT
String fakeJwt(Map<String, Object?> claims) {
  String part(Map<String, Object?> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${part({'alg': 'none'})}.${part(claims)}.sig';
}

int inOneHour() =>
    DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;

void main() {
  group('PKCE', () {
    test('RFC 7636 예시값과 같은 challenge를 만든다', () {
      expect(
        pkceChallengeS256('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
      );
    });

    test('verifier는 43자 이상의 URL-safe 문자열', () {
      final v = randomUrlSafeString();
      expect(v.length, greaterThanOrEqualTo(43));
      expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(v), isTrue);
    });

    test('urn:uuid v4 형식', () {
      expect(
        RegExp(r'^urn:uuid:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
            .hasMatch(newUrnUuid()),
        isTrue,
      );
    });
  });

  group('ChatGptCredentials', () {
    test('JSON 저장/복원', () {
      final original = ChatGptCredentials(
        clientId: 'client-1',
        hostId: 'urn:uuid:test',
        accessToken: 'at',
        refreshToken: 'rt',
        idToken: fakeJwt({'email': 'me@example.com'}),
        expiresAt: DateTime(2026, 10, 11, 12),
        scopes: {'openid', ChatGptSignIn.planUsageScope},
      );

      final restored = ChatGptCredentials.fromJson(original.toJson());
      expect(restored.clientId, 'client-1');
      expect(restored.refreshToken, 'rt');
      expect(restored.expiresAt, DateTime(2026, 10, 11, 12));
      expect(restored.scopes, original.scopes);
      expect(restored.email, 'me@example.com');
    });

    test('nonce가 다른 ID 토큰은 거부한다', () {
      final credentials = ChatGptCredentials(
        clientId: 'client-1',
        hostId: 'h',
        accessToken: 'at',
        refreshToken: 'rt',
        idToken: fakeJwt({
          'iss': ChatGptSignIn.issuer,
          'aud': 'client-1',
          'exp': inOneHour(),
          'nonce': 'other',
        }),
        expiresAt: DateTime.now(),
        scopes: const {},
      );

      expect(
        () => credentials.verifyIdToken(expectedNonce: 'expected'),
        throwsA(isA<ChatGptAuthException>()),
      );
    });
  });

  group('ChatGptSignIn.signIn (브라우저·OpenAI를 흉내낸 전체 흐름)', () {
    const port = 14555; // 실제 1455와 겹치지 않게

    /// 브라우저 역할: 로그인 URL을 받으면 잠시 후 앱의 콜백 주소로 돌아옴
    Future<bool> Function(Uri) fakeBrowser({
      required void Function(Uri url) onOpen,
      required Map<String, String> Function(Uri url) callbackParams,
    }) {
      return (url) async {
        onOpen(url);
        unawaited(Future<void>.delayed(const Duration(milliseconds: 50), () async {
          final client = HttpClient();
          final callback = Uri.parse('http://127.0.0.1:$port/auth/callback')
              .replace(queryParameters: callbackParams(url));
          final request = await client.getUrl(callback);
          final response = await request.close();
          await response.drain<void>();
          client.close();
        }));
        return true;
      };
    }

    test('최초 로그인: 등록 → 콜백 → 토큰 교환까지 성공', () async {
      late Uri authorizeUrl;
      late Map<String, String> tokenForm;

      final tokenServer = MockClient((request) async {
        tokenForm = Uri.splitQueryString(request.body);
        final nonce = authorizeUrl.queryParameters['nonce'];
        return http.Response(
          jsonEncode({
            'access_token': 'access-1',
            'refresh_token': 'refresh-1',
            'expires_in': 3600,
            'scope': ChatGptSignIn.scopes,
            'id_token': fakeJwt({
              'iss': ChatGptSignIn.issuer,
              'aud': 'issued-client',
              'exp': inOneHour(),
              'nonce': nonce,
              'email': 'me@example.com',
            }),
          }),
          200,
        );
      });

      final signIn = ChatGptSignIn(
        hostId: 'urn:uuid:host',
        port: port,
        httpClient: tokenServer,
        openBrowser: fakeBrowser(
          onOpen: (url) => authorizeUrl = url,
          callbackParams: (url) => {
            'code': 'auth-code',
            'state': url.queryParameters['state']!,
            'client_id': 'issued-client',
          },
        ),
      );

      final credentials = await signIn.signIn();

      // 로그인 요청 파라미터
      final q = authorizeUrl.queryParameters;
      expect(q['client_id'], 'dynamic_agent_client');
      expect(q['agent_name_hint'], 'FitMind');
      expect(q['ext_agent_host_id'], 'urn:uuid:host');
      expect(q['redirect_uri'], 'http://127.0.0.1:$port/auth/callback');
      expect(q['code_challenge_method'], 'S256');
      expect(q['scope'], ChatGptSignIn.scopes);

      // 토큰 교환: 발급받은 client_id와 PKCE verifier 사용
      expect(tokenForm['grant_type'], 'authorization_code');
      expect(tokenForm['client_id'], 'issued-client');
      expect(tokenForm['code'], 'auth-code');
      expect(pkceChallengeS256(tokenForm['code_verifier']!), q['code_challenge']);

      expect(credentials.accessToken, 'access-1');
      expect(credentials.clientId, 'issued-client');
      expect(credentials.email, 'me@example.com');
    });

    test('state가 다르면 토큰을 교환하지 않고 실패한다', () async {
      var tokenRequested = false;
      final signIn = ChatGptSignIn(
        hostId: 'urn:uuid:host',
        port: port,
        httpClient: MockClient((_) async {
          tokenRequested = true;
          return http.Response('{}', 200);
        }),
        openBrowser: fakeBrowser(
          onOpen: (_) {},
          callbackParams: (_) => {'code': 'c', 'state': 'forged'},
        ),
      );

      await expectLater(signIn.signIn(), throwsA(isA<ChatGptAuthException>()));
      expect(tokenRequested, isFalse);
    });

    test('사용자가 동의를 취소하면 실패한다', () async {
      final signIn = ChatGptSignIn(
        hostId: 'urn:uuid:host',
        port: port,
        httpClient: MockClient((_) async => http.Response('{}', 200)),
        openBrowser: fakeBrowser(
          onOpen: (_) {},
          callbackParams: (url) => {
            'error': 'access_denied',
            'state': url.queryParameters['state']!,
          },
        ),
      );

      await expectLater(
        signIn.signIn(),
        throwsA(isA<ChatGptAuthException>()
            .having((e) => e.message, 'message', contains('취소'))),
      );
    });
  });
}
