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

    test('state가 다른 콜백은 거절하고 진짜 콜백을 계속 기다린다', () async {
      final exchangedCodes = <String>[];
      late Uri authorizeUrl;
      int? forgedStatus;

      Future<int> hitCallback(Map<String, String> params) async {
        final client = HttpClient();
        final request = await client.getUrl(
            Uri.parse('http://127.0.0.1:$port/auth/callback')
                .replace(queryParameters: params));
        final response = await request.close();
        await response.drain<void>();
        client.close();
        return response.statusCode;
      }

      final signIn = ChatGptSignIn(
        hostId: 'urn:uuid:host',
        port: port,
        httpClient: MockClient((request) async {
          exchangedCodes.add(Uri.splitQueryString(request.body)['code']!);
          return http.Response(
            jsonEncode({
              'access_token': 'access-1',
              'refresh_token': 'refresh-1',
              'scope': ChatGptSignIn.scopes,
              'id_token': fakeJwt({
                'iss': ChatGptSignIn.issuer,
                'aud': 'issued-client',
                'exp': inOneHour(),
                'nonce': authorizeUrl.queryParameters['nonce'],
              }),
            }),
            200,
          );
        }),
        openBrowser: (url) async {
          authorizeUrl = url;
          unawaited(Future<void>.delayed(const Duration(milliseconds: 50), () async {
            // 다른 앱이 먼저 끼어든 상황
            forgedStatus = await hitCallback({'code': 'forged-code', 'state': 'forged'});
            await hitCallback({
              'code': 'real-code',
              'state': url.queryParameters['state']!,
              'client_id': 'issued-client',
            });
          }));
          return true;
        },
      );

      final credentials = await signIn.signIn();
      expect(forgedStatus, HttpStatus.badRequest);
      expect(exchangedCodes, ['real-code']);
      expect(credentials.accessToken, 'access-1');
    });

    test('앱이 앞으로 올 때까지 토큰 교환을 미룬다', () async {
      final foreground = Completer<void>();
      final callbackReceived = Completer<void>();
      var tokenRequested = false;
      late Uri authorizeUrl;

      final signIn = ChatGptSignIn(
        hostId: 'urn:uuid:host',
        port: port,
        waitForForeground: () {
          callbackReceived.complete();
          return foreground.future;
        },
        httpClient: MockClient((_) async {
          tokenRequested = true;
          return http.Response(
            jsonEncode({
              'access_token': 'access-1',
              'refresh_token': 'refresh-1',
              'scope': ChatGptSignIn.scopes,
              'id_token': fakeJwt({
                'iss': ChatGptSignIn.issuer,
                'aud': 'issued-client',
                'exp': inOneHour(),
                'nonce': authorizeUrl.queryParameters['nonce'],
              }),
            }),
            200,
          );
        }),
        openBrowser: fakeBrowser(
          onOpen: (url) => authorizeUrl = url,
          callbackParams: (url) => {
            'code': 'auth-code',
            'state': url.queryParameters['state']!,
            'client_id': 'issued-client',
          },
        ),
      );

      final result = signIn.signIn();
      await callbackReceived.future;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(tokenRequested, isFalse);

      foreground.complete();
      expect((await result).accessToken, 'access-1');
      expect(tokenRequested, isTrue);
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

  group('ChatGptSignIn.refresh', () {
    final current = ChatGptCredentials(
      clientId: 'client-1',
      hostId: 'urn:uuid:host',
      accessToken: 'old-access',
      refreshToken: 'old-refresh',
      idToken: '',
      expiresAt: DateTime.now(),
      scopes: ChatGptSignIn.scopes.split(' ').toSet(),
    );

    ChatGptSignIn signInWith(Map<String, Object?> tokenResponse) => ChatGptSignIn(
          hostId: 'urn:uuid:host',
          clientId: 'client-1',
          openBrowser: (_) async => true,
          httpClient: MockClient(
              (_) async => http.Response(jsonEncode(tokenResponse), 200)),
        );

    test('새 토큰으로 교체하고, scope가 없으면 기존 권한을 유지한다', () async {
      final refreshed = await signInWith({
        'access_token': 'new-access',
        'refresh_token': 'new-refresh',
        'expires_in': 3600,
      }).refresh(current);

      expect(refreshed.accessToken, 'new-access');
      expect(refreshed.refreshToken, 'new-refresh');
      expect(refreshed.scopes, contains(ChatGptSignIn.planUsageScope));
    });

    test('구독 사용량 권한이 빠지면 실패한다', () async {
      await expectLater(
        signInWith({
          'access_token': 'new-access',
          'refresh_token': 'new-refresh',
          'scope': 'openid profile email offline_access',
        }).refresh(current),
        throwsA(isA<ChatGptAuthException>().having(
            (e) => e.code, 'code', ChatGptSignIn.planUsageRevokedCode)),
      );
    });
  });
}
