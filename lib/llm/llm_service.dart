/// 앱이 LLM을 사용하는 유일한 통로.
///
/// 화면이나 분석 로직은 이 인터페이스만 알고, 어떤 회사의 어떤 API를 쓰는지는 모릅니다.
/// V1 구현체는 [OpenAIService] 하나이며, 다른 Provider는 이 인터페이스를
/// 구현하는 클래스를 추가하는 것으로 확장합니다.
abstract interface class LLMService {
  /// [instructions](시스템 지시)와 [input](사용자 입력)을 보내고 응답 텍스트 전체를 받습니다.
  ///
  /// 실패하면 [LLMException]을 던집니다.
  Future<String> complete({required String instructions, required String input});
}

/// LLM 호출 실패.
class LLMException implements Exception {
  const LLMException(this.message, {this.code, this.statusCode});

  /// 사용자에게 보여줄 수 있는 설명
  final String message;

  /// API가 준 오류 코드 (예: `subscription_sharing_usage_limit_exceeded`)
  final String? code;

  /// HTTP 상태 코드 (스트림 도중 실패한 경우 null)
  final int? statusCode;

  /// ChatGPT 구독 사용량을 다 쓴 경우
  bool get isUsageLimit =>
      code == 'subscription_sharing_usage_limit_exceeded' ||
      code == 'subscription_sharing_usage_unavailable';

  /// 인증이 만료되었거나 잘못된 경우 (다시 로그인 / Key 확인 필요)
  bool get isAuthError => statusCode == 401;

  @override
  String toString() => 'LLMException($code, $statusCode): $message';
}
