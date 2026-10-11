import 'dart:convert';

import 'package:fitmind/llm/llm_service.dart';
import 'package:fitmind/llm/openai_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// SSE 이벤트 하나를 줄 목록으로
List<String> sse(Map<String, Object?> data) => [
      'event: ${data['type']}',
      'data: ${jsonEncode(data)}',
      '',
    ];

Stream<String> lines(List<List<String>> events) =>
    Stream.fromIterable(events.expand((e) => e));

void main() {
  group('collectResponseText', () {
    test('delta를 이어 붙이고 completed에서 끝난다', () async {
      final text = await collectResponseText(lines([
        sse({'type': 'response.created'}),
        sse({'type': 'response.output_text.delta', 'delta': '체중이 '}),
        sse({'type': 'response.output_text.delta', 'delta': '0.8kg 감소했습니다.'}),
        sse({'type': 'response.completed'}),
      ]));

      expect(text, '체중이 0.8kg 감소했습니다.');
    });

    test('completed 없이 끊기면 실패로 처리한다', () async {
      await expectLater(
        collectResponseText(lines([
          sse({'type': 'response.output_text.delta', 'delta': '중간까지만'}),
        ])),
        throwsA(isA<LLMException>()
            .having((e) => e.code, 'code', 'stream_interrupted')),
      );
    });

    test('스트림 도중 사용량 초과는 isUsageLimit으로 구분된다', () async {
      await expectLater(
        collectResponseText(lines([
          sse({'type': 'response.output_text.delta', 'delta': '앞부분'}),
          sse({
            'type': 'response.failed',
            'response': {
              'error': {
                'code': 'subscription_sharing_usage_limit_exceeded',
                'message': 'usage limit reached',
              },
            },
          }),
        ])),
        throwsA(isA<LLMException>().having((e) => e.isUsageLimit, 'isUsageLimit', isTrue)),
      );
    });

    test('마지막 이벤트 뒤 빈 줄이 없어도 completed를 인식한다', () async {
      final text = await collectResponseText(Stream.fromIterable([
        'data: ${jsonEncode({'type': 'response.output_text.delta', 'delta': 'ok'})}',
        '',
        'data: ${jsonEncode({'type': 'response.completed'})}',
      ]));
      expect(text, 'ok');
    });
  });

  group('OpenAIService', () {
    test('Bearer 토큰과 필수 옵션(store=false, stream=true)으로 요청한다', () async {
      late http.BaseRequest captured;
      late Map<String, Object?> body;

      final client = MockClient.streaming((request, bodyStream) async {
        captured = request;
        body = jsonDecode(await bodyStream.bytesToString()) as Map<String, Object?>;
        final events = [
          ...sse({'type': 'response.output_text.delta', 'delta': '분석 결과'}),
          ...sse({'type': 'response.completed'}),
        ].join('\n');
        return http.StreamedResponse(Stream.value(utf8.encode(events)), 200);
      });

      final service = OpenAIService(
        token: () async => 'test-token',
        model: 'test-model',
        client: client,
      );
      final result = await service.complete(instructions: '지시', input: '입력');

      expect(result, '분석 결과');
      expect(captured.headers['Authorization'], 'Bearer test-token');
      expect(body['model'], 'test-model');
      expect(body['store'], false);
      expect(body['stream'], true);
    });

    test('401은 isAuthError로 구분된다', () async {
      final client = MockClient.streaming((request, bodyStream) async {
        final error = jsonEncode({
          'error': {'message': 'Invalid token', 'code': 'invalid_token'},
        });
        return http.StreamedResponse(Stream.value(utf8.encode(error)), 401);
      });

      final service = OpenAIService(
        token: () async => 'expired',
        model: 'test-model',
        client: client,
      );

      await expectLater(
        service.complete(instructions: '', input: ''),
        throwsA(isA<LLMException>().having((e) => e.isAuthError, 'isAuthError', isTrue)),
      );
    });
  });
}
