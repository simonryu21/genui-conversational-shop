/// 원격 에이전트 — shop_backend(POST /api/chat, SSE)와 통신하는 [ShoppingAgent].
///
/// 서버가 보내는 chunk 페이로드는 mock(ScriptedShoppingAgent)과 동일 계약
/// (마크다운 텍스트 + ```json 펜스의 A2UI 메시지)이라, 받은 그대로 emitChunk로
/// 넘기면 이후 파이프라인(A2uiTransportAdapter → SurfaceController)은 그대로 동작한다.
library;

import 'dart:convert';

import 'package:genui/genui.dart';
import 'package:http/http.dart' as http;

import '../l10n.dart';
import 'platform_io.dart' if (dart.library.js_interop) 'platform_web.dart';
import 'shopping_agent.dart';
import 'sse_parser.dart';

typedef ChunkEmitter = void Function(String chunk);

class RemoteShoppingAgent extends ShoppingAgent {
  RemoteShoppingAgent({required this.emitChunk, required this.baseUrl})
      : _sessionId =
            's-${DateTime.now().millisecondsSinceEpoch}-${Object().hashCode}';

  final ChunkEmitter emitChunk;
  final String baseUrl;
  final String _sessionId;

  int _points = 0;

  AppStrings get _s => AppStrings.of(language);

  @override
  int get points => _points;

  /// 화면 진입 시 서버에서 현재 포인트를 조회 (실패해도 앱은 계속 동작).
  @override
  Future<void> refreshPoints() async {
    final client = createStreamingClient();
    try {
      final resp = await client
          .get(Uri.parse('$baseUrl/api/member'))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data =
            jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        _points = (data['points'] as num?)?.toInt() ?? _points;
      }
    } catch (_) {
      // BE 미기동 등 — 첫 턴의 done 이벤트에서 어차피 갱신됨
    } finally {
      client.close();
    }
  }

  @override
  Future<void> handle(ChatMessage message) async {
    final body = jsonEncode({
      'session_id': _sessionId,
      'message': _serialize(message),
      // 설정 메뉴의 언어 — BE가 시스템 프롬프트(응답 언어)와 안내 문구를 이 값으로 고른다
      'lang': language.code,
    });

    final client = createStreamingClient();
    try {
      final request = http.Request('POST', Uri.parse('$baseUrl/api/chat'))
        ..headers['Content-Type'] = 'application/json; charset=utf-8'
        ..body = body;
      final response = await client.send(request);
      if (response.statusCode != 200) {
        emitChunk(_s.serverError(response.statusCode));
        return;
      }

      final parser = SseParser();
      await for (final text
          in response.stream.transform(const Utf8Decoder())) {
        for (final event in parser.addChunk(text)) {
          switch (event.event) {
            case 'chunk':
              emitChunk(event.data);
            case 'error':
              emitChunk('\n\n⚠️ ${event.data}\n');
            case 'done':
              final data = jsonDecode(event.data) as Map<String, dynamic>;
              _points = (data['points'] as num?)?.toInt() ?? _points;
          }
        }
      }
    } catch (e) {
      emitChunk(_s.backendUnreachable(e));
    } finally {
      client.close();
    }
  }

  /// ChatMessage → BE 요청 JSON (§8 계약).
  Map<String, dynamic> _serialize(ChatMessage message) {
    for (final part in message.parts) {
      if (part.isUiInteractionPart) {
        return {
          'type': 'ui_action',
          'interaction': part.asUiInteractionPart!.interaction,
        };
      }
    }
    final text = message.parts
        .whereType<TextPart>()
        .map((p) => p.text)
        .join(' ')
        .trim();
    return {'type': 'text', 'text': text};
  }
}
