/// OAuth 로그인에 쓰는 난수/해시 도우미.
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

final Random _random = Random.secure();

List<int> _randomBytes(int length) =>
    List<int>.generate(length, (_) => _random.nextInt(256));

String _base64UrlNoPadding(List<int> bytes) =>
    base64UrlEncode(bytes).replaceAll('=', '');

/// URL에 그대로 넣을 수 있는 난수 문자열 (state, nonce, PKCE verifier용).
///
/// 32바이트 → 43자. PKCE verifier 규격(43~128자)을 만족합니다.
String randomUrlSafeString([int byteLength = 32]) =>
    _base64UrlNoPadding(_randomBytes(byteLength));

/// PKCE code_challenge (S256): verifier의 SHA-256을 base64url(패딩 없음)로.
String pkceChallengeS256(String verifier) =>
    _base64UrlNoPadding(sha256.convert(ascii.encode(verifier)).bytes);

/// `urn:uuid:` 형식의 랜덤 UUID(v4). 기기 식별자(ext_agent_host_id)용.
String newUrnUuid() {
  final b = _randomBytes(16);
  b[6] = (b[6] & 0x0f) | 0x40; // version 4
  b[8] = (b[8] & 0x3f) | 0x80; // variant
  final hex = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return 'urn:uuid:${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
