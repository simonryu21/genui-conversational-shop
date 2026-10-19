/// GenUI 파이프라인 배선.
///
/// 흐름:  사용자 입력 → [ScriptedShoppingAgent] (mock LLM)
///        → 텍스트/A2UI JSON 청크 스트림 → [A2uiTransportAdapter] (파싱)
///        → [SurfaceController] (검증·상태 관리) → [Surface] 위젯 렌더링
///        → 버튼 클릭 등 UI 액션 → onSubmit → 다시 에이전트로.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:genui/genui.dart';

import 'agent/agent_factory.dart';
import 'agent/shopping_agent.dart';
import 'l10n.dart';
import 'shop_catalog.dart';

/// 채팅 타임라인의 한 항목.
class ChatEntry {
  ChatEntry.user(this.text)
      : isUser = true,
        surfaceId = null,
        isAction = false;

  ChatEntry.userAction(this.text)
      : isUser = true,
        surfaceId = null,
        isAction = true;

  ChatEntry.agentText(this.text)
      : isUser = false,
        surfaceId = null,
        isAction = false;

  ChatEntry.surface(this.surfaceId)
      : isUser = false,
        text = null,
        isAction = false;

  String? text;
  final String? surfaceId;
  final bool isUser;
  final bool isAction;
}

class ShoppingChatSession extends ChangeNotifier {
  ShoppingChatSession() {
    surfaceController = SurfaceController(catalogs: [shopCatalog]);
    _transport = A2uiTransportAdapter();
    _agent = createAgent(emitChunk: _transport.addChunk);

    // 진입 시 서버에서 잔여 포인트 조회 (조회 전 0P로 보이는 문제 방지)
    _agent.refreshPoints().then((_) => notifyListeners());

    _messageSub = _transport.incomingMessages.listen(
      surfaceController.handleMessage,
      onError: _onPipelineError,
    );
    _textSub = _transport.incomingText.listen(
      _appendAgentText,
      onError: _onPipelineError,
    );
    _surfaceSub = surfaceController.surfaceUpdates.listen(_onSurfaceUpdate);
    _submitSub = surfaceController.onSubmit.listen(_onUiSubmit);
  }

  late final SurfaceController surfaceController;
  late final A2uiTransportAdapter _transport;
  late final ShoppingAgent _agent;

  late final StreamSubscription<Object?> _messageSub;
  late final StreamSubscription<String> _textSub;
  late final StreamSubscription<SurfaceUpdate> _surfaceSub;
  late final StreamSubscription<ChatMessage> _submitSub;

  final List<ChatEntry> entries = [];
  bool isProcessing = false;
  ChatEntry? _currentAgentBubble;

  int get remainingPoints => _agent.points;

  /// 데모 언어 (헤더 ⚙ 설정 메뉴). 앱 크롬 문자열과 BE 요청의 `lang`이 함께 바뀐다.
  AppLanguage get language => _agent.language;
  AppStrings get strings => AppStrings.of(language);
  bool get isOfflineMock => agentMode == 'scripted';

  void setLanguage(AppLanguage lang) {
    if (lang == _agent.language) return;
    _agent.language = lang;
    notifyListeners();
  }

  Future<void> sendText(String text) async {
    if (text.trim().isEmpty || isProcessing) return;
    entries.add(ChatEntry.user(text));
    await _run(ChatMessage.user(text));
  }

  /// UI 액션(onSubmit)을 에이전트에 전달하고, 타임라인에도 흔적을 남긴다.
  Future<void> _onUiSubmit(ChatMessage message) async {
    if (isProcessing) return;
    entries.add(ChatEntry.userAction(_describeInteraction(message)));
    await _run(message);
  }

  Future<void> _run(ChatMessage message) async {
    _currentAgentBubble = null;
    isProcessing = true;
    notifyListeners();
    try {
      await _agent.handle(message);
    } catch (e) {
      entries.add(ChatEntry.agentText('${strings.errorPrefix}$e'));
    } finally {
      isProcessing = false;
      notifyListeners();
    }
  }

  void _appendAgentText(String chunk) {
    if (_currentAgentBubble == null) {
      _currentAgentBubble = ChatEntry.agentText('');
      entries.add(_currentAgentBubble!);
    }
    _currentAgentBubble!.text = (_currentAgentBubble!.text ?? '') + chunk;
    notifyListeners();
  }

  void _onSurfaceUpdate(SurfaceUpdate update) {
    if (update is SurfaceAdded) {
      final exists = entries.any((e) => e.surfaceId == update.surfaceId);
      if (!exists) {
        entries.add(ChatEntry.surface(update.surfaceId));
        // 서피스 뒤에 새 말풍선이 오도록 리셋.
        _currentAgentBubble = null;
        notifyListeners();
      }
    }
  }

  void _onPipelineError(Object error) {
    entries.add(ChatEntry.agentText('${strings.pipelineErrorPrefix}$error'));
    notifyListeners();
  }

  String _describeInteraction(ChatMessage message) {
    final s = strings;
    for (final part in message.parts) {
      if (part.isUiInteractionPart) {
        try {
          final raw = jsonDecode(part.asUiInteractionPart!.interaction)
              as Map<String, dynamic>;
          final action = (raw['action'] as Map?)?.cast<String, dynamic>();
          final name = action?['name'] as String?;
          // LLM이 즉석 정의한 커스텀 액션은 context.label(프롬프트 규약)로 표시
          final label = (action?['context'] as Map?)?['label'] as String?;
          return switch (name) {
            'addToCart' => s.actionAddToCart,
            'checkout' => s.actionCheckout,
            'confirmPayment' => s.actionConfirmPayment,
            'removeFromCart' => label != null ? '🗑 $label' : s.actionRemoveFromCart,
            'refineTuna' => s.actionRefine,
            _ => label != null ? '🖱 $label' : s.actionUnknown(name),
          };
        } catch (_) {
          return s.actionGeneric;
        }
      }
    }
    return s.actionGeneric;
  }

  @override
  void dispose() {
    _messageSub.cancel();
    _textSub.cancel();
    _surfaceSub.cancel();
    _submitSub.cancel();
    surfaceController.dispose();
    _transport.dispose();
    super.dispose();
  }
}
