import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../llm/auth/chatgpt_sign_in.dart';
import '../llm/auth/credential_store.dart';
import '../llm/llm_service.dart';
import '../llm/openai_service.dart';

/// [개발용] "Sign in with ChatGPT"가 Android에서 동작하는지 확인하는 화면.
///
/// 확인 순서 (각 단계 결과가 화면 아래 로그에 남음):
///   1. 로그인  → 폰 브라우저 로그인 → 앱이 콜백을 받는지 → 토큰 발급
///   2. 모델 목록 → 토큰으로 API에 접근되는지 + 사용 가능한 모델 확인
///   3. 테스트 호출 → 실제 AI 응답이 오는지 (구독 사용량으로)
///   4. 토큰 갱신 → refresh token 형식이 맞는지 (문서에 명시되지 않은 부분)
///
/// 검증이 끝나면 이 화면은 설정 화면의 "ChatGPT 연결"로 대체됩니다.
class SiwcSpikePage extends StatefulWidget {
  const SiwcSpikePage({super.key});

  @override
  State<SiwcSpikePage> createState() => _SiwcSpikePageState();
}

class _SiwcSpikePageState extends State<SiwcSpikePage> {
  final _store = LlmCredentialStore();
  final _logs = <String>[];
  ChatGptCredentials? _credentials;
  List<_ModelOption> _models = [];
  String? _selectedModel;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final saved = await _store.readChatGpt();
    if (!mounted) return;
    setState(() => _credentials = saved);
    _log(saved == null
        ? '저장된 로그인 없음'
        : '저장된 로그인: ${saved.email ?? '(이메일 없음)'}, 만료 ${saved.expiresAt}');
  }

  void _log(String message) {
    debugPrint('[SIWC] $message');
    if (!mounted) return;
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final time = '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
    setState(() => _logs.insert(0, '[$time] $message'));
  }

  Future<ChatGptSignIn> _signInClient() async => ChatGptSignIn(
        hostId: await _store.hostId(),
        clientId: await _store.clientId(),
        openBrowser: (url) =>
            launchUrl(url, mode: LaunchMode.externalApplication),
      );

  /// 단계 실행 공통 처리: 중복 실행 방지 + 오류를 로그로
  Future<void> _run(String step, Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    _log('▶ $step 시작');
    try {
      await action();
    } on ChatGptAuthException catch (e) {
      _log('✗ $step 실패 (인증): ${e.message}');
    } on LLMException catch (e) {
      _log('✗ $step 실패 (AI): ${e.message} [code=${e.code}, http=${e.statusCode}]');
    } catch (e) {
      _log('✗ $step 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signIn() => _run('로그인', () async {
        final client = await _signInClient();
        _log('브라우저를 엽니다. 로그인 후 이 앱으로 돌아오세요. (${client.redirectUri})');
        final credentials = await client.signIn();
        await _store.saveChatGpt(credentials);
        setState(() => _credentials = credentials);
        _log('✓ 로그인 성공: ${credentials.email}\n  scopes: ${credentials.scopes.join(' ')}');
      });

  Future<void> _loadModels() => _run('모델 목록', () async {
        final token = await _session().accessToken();
        final response = await http.get(
          Uri.parse('https://api.openai.com/v1/models'),
          headers: {'Authorization': 'Bearer $token'},
        );
        if (response.statusCode != 200) {
          throw LLMException(response.body, statusCode: response.statusCode);
        }
        final data = (jsonDecode(response.body) as Map<String, Object?>)['data']
            as List<Object?>;
        final models = data
            .whereType<Map<String, Object?>>()
            .where((m) => m['visibility'] == null || m['visibility'] == 'list')
            .map((m) => _ModelOption(
                  slug: (m['slug'] ?? m['id']) as String,
                  name: (m['display_name'] ?? m['slug'] ?? m['id']) as String,
                ))
            .toList();
        setState(() {
          _models = models;
          _selectedModel = models.isEmpty ? null : models.first.slug;
        });
        _log('✓ 모델 ${models.length}개: ${models.map((m) => m.slug).join(', ')}');
      });

  Future<void> _testCall() => _run('테스트 호출', () async {
        final model = _selectedModel;
        if (model == null) throw StateError('먼저 모델 목록을 불러오세요.');
        final service = OpenAIService(token: _session().accessToken, model: model);
        final answer = await service.complete(
          instructions: '당신은 피트니스 코치입니다. 한국어로 두 문장 이내로 답하세요.',
          input: '지난 7일간 체중 70.0kg → 69.2kg, 평균 단백질 118g, 근력운동 3일. 한 줄 평가해줘.',
        );
        _log('✓ AI 응답 ($model):\n$answer');
      });

  Future<void> _refresh() => _run('토큰 갱신', () async {
        final current = _credentials;
        if (current == null) throw StateError('먼저 로그인하세요.');
        final refreshed = await (await _signInClient()).refresh(current);
        await _store.saveChatGpt(refreshed);
        setState(() => _credentials = refreshed);
        _log('✓ 갱신 성공, 새 만료 ${refreshed.expiresAt}');
      });

  Future<void> _signOut() => _run('로그아웃', () async {
        await _store.clearChatGpt();
        setState(() {
          _credentials = null;
          _models = [];
          _selectedModel = null;
        });
        _log('✓ 토큰 삭제 (host id / client id는 유지)');
      });

  ChatGptSession _session() =>
      ChatGptSession(store: _store, signIn: _signInClientSync());

  // ChatGptSession은 갱신할 때만 signIn 객체를 쓰므로 client_id는 저장소 값으로 충분
  ChatGptSignIn _signInClientSync() => ChatGptSignIn(
        hostId: _credentials?.hostId ?? '',
        clientId: _credentials?.clientId,
        openBrowser: (url) =>
            launchUrl(url, mode: LaunchMode.externalApplication),
      );

  @override
  Widget build(BuildContext context) {
    final signedIn = _credentials != null;
    return Scaffold(
      appBar: AppBar(title: const Text('ChatGPT 로그인 검증 (개발용)')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                signedIn ? '로그인됨: ${_credentials!.email ?? '-'}' : '로그인 안 됨',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed: _busy ? null : _signIn,
                    child: const Text('1. 로그인'),
                  ),
                  OutlinedButton(
                    onPressed: _busy || !signedIn ? null : _loadModels,
                    child: const Text('2. 모델 목록'),
                  ),
                  OutlinedButton(
                    onPressed: _busy || _selectedModel == null ? null : _testCall,
                    child: const Text('3. 테스트 호출'),
                  ),
                  OutlinedButton(
                    onPressed: _busy || !signedIn ? null : _refresh,
                    child: const Text('4. 토큰 갱신'),
                  ),
                  TextButton(
                    onPressed: _busy || !signedIn ? null : _signOut,
                    child: const Text('로그아웃'),
                  ),
                ],
              ),
              if (_models.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButton<String>(
                  isExpanded: true,
                  value: _selectedModel,
                  items: [
                    for (final m in _models)
                      DropdownMenuItem(value: m.slug, child: Text(m.name)),
                  ],
                  onChanged: (v) => setState(() => _selectedModel = v),
                ),
              ],
              if (_busy) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
              const Divider(height: 32),
              Expanded(
                child: ListView.builder(
                  itemCount: _logs.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SelectableText(
                      _logs[i],
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModelOption {
  const _ModelOption({required this.slug, required this.name});
  final String slug;
  final String name;
}
