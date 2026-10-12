import 'dart:convert';

import 'package:http/http.dart' as http;

import 'llm_service.dart';

/// 요청할 때마다 유효한 Bearer 토큰을 돌려주는 함수.
///
/// - API Key 방식: 저장된 Key를 그대로 반환
/// - ChatGPT 로그인 방식: 액세스 토큰 반환 (만료 직전이면 갱신 후 반환)
///
/// 둘 다 같은 엔드포인트에 같은 형식으로 들어가므로 OpenAIService는 하나로 충분합니다.
typedef BearerTokenProvider = Future<String> Function();

/// OpenAI Responses API(`POST /v1/responses`) 구현체.
class OpenAIService implements LLMService {
  OpenAIService({
    required this._token,
    required this.model,
    http.Client? client,
    Uri? endpoint,
  })  : _client = client ?? http.Client(),
        _endpoint = endpoint ?? Uri.parse('https://api.openai.com/v1/responses');

  final BearerTokenProvider _token;
  final http.Client _client;
  final Uri _endpoint;

  /// 사용할 모델 이름 (계정마다 사용 가능한 모델이 다르므로 설정에서 받음)
  final String model;

  @override
  Future<String> complete({
    required String instructions,
    required String input,
  }) async {
    final request = http.Request('POST', _endpoint)
      ..headers['Authorization'] = 'Bearer ${await _token()}'
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({
        'model': model,
        'instructions': instructions,
        'input': input,
        // ChatGPT 로그인 방식은 둘 다 필수. API Key 방식에서도 문제없음.
        // store: false → OpenAI 쪽에 응답을 저장하지 않음 (결과는 앱 DB에만 저장)
        'store': false,
        'stream': true,
      });

    final http.StreamedResponse response;
    try {
      response = await _client.send(request);
    } catch (e) {
      throw LLMException('네트워크 오류로 AI에 연결하지 못했습니다. ($e)');
    }

    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw _errorFromBody(body, response.statusCode);
    }

    final lines =
        response.stream.transform(utf8.decoder).transform(const LineSplitter());
    return collectResponseText(lines);
  }

  LLMException _errorFromBody(String body, int statusCode) {
    try {
      final json = jsonDecode(body) as Map<String, Object?>;
      final error = json['error'] as Map<String, Object?>?;
      return LLMException(
        (error?['message'] as String?) ?? 'AI 요청이 실패했습니다.',
        code: error?['code'] as String?,
        statusCode: statusCode,
      );
    } catch (_) {
      return LLMException('AI 요청이 실패했습니다 (HTTP $statusCode).',
          statusCode: statusCode);
    }
  }
}

/// Responses API 스트림(SSE)을 읽어 최종 텍스트를 만듭니다.
///
/// SSE 형식: 빈 줄로 구분된 이벤트마다 `event: ...`, `data: {...}` 줄이 옵니다.
/// - `response.output_text.delta`: 텍스트 조각 → 이어 붙임
/// - `response.completed`: 성공 (이게 와야만 성공으로 인정)
/// - `response.failed` / `response.incomplete` / `error`: 실패
///
/// 사용량 초과 같은 오류는 스트림이 시작된 뒤에 올 수도 있어서
/// HTTP 200이어도 끝까지 읽어야 성공 여부를 알 수 있습니다.
Future<String> collectResponseText(Stream<String> lines) async {
  final text = StringBuffer();
  final dataLines = <String>[];

  // 이벤트 하나를 처리. 완료되면 true.
  bool dispatch() {
    if (dataLines.isEmpty) return false;
    final data = dataLines.join('\n');
    dataLines.clear();
    if (data == '[DONE]') return false;

    final event = jsonDecode(data) as Map<String, Object?>;
    switch (event['type']) {
      case 'response.output_text.delta':
        text.write(event['delta'] as String? ?? '');
        return false;
      case 'response.completed':
        return true;
      case 'response.failed':
        final response = event['response'] as Map<String, Object?>?;
        final error = response?['error'] as Map<String, Object?>?;
        throw LLMException(
          (error?['message'] as String?) ?? 'AI 응답 생성에 실패했습니다.',
          code: error?['code'] as String?,
        );
      case 'response.incomplete':
        throw const LLMException(
          'AI 응답이 중간에 끊겼습니다 (길이 제한 등).',
          code: 'incomplete',
        );
      case 'error':
        final nested = event['error'] as Map<String, Object?>?;
        throw LLMException(
          (event['message'] as String?) ??
              (nested?['message'] as String?) ??
              'AI 요청 중 오류가 발생했습니다.',
          code: (event['code'] as String?) ?? (nested?['code'] as String?),
        );
      default:
        return false; // 그 외 이벤트(created, in_progress 등)는 무시
    }
  }

  await for (final line in lines) {
    if (line.isEmpty) {
      if (dispatch()) return text.toString();
    } else if (line.startsWith('data:')) {
      dataLines.add(line.substring(5).trimLeft());
    }
    // 'event:', 'id:', ':' (주석) 줄은 data의 type으로 충분하므로 무시
  }

  // 마지막 이벤트 뒤에 빈 줄 없이 스트림이 끝난 경우
  if (dispatch()) return text.toString();

  throw const LLMException(
    'AI 응답이 완료되기 전에 연결이 끊겼습니다.',
    code: 'stream_interrupted',
  );
}
