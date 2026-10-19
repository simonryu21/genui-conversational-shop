/// 에이전트 공통 인터페이스 — scripted(mock)와 remote(LLM/BE)가 모두 구현한다.
///
/// `chat_session.dart`는 구체 타입 대신 이 인터페이스에 의존한다.
library;

import 'package:genui/genui.dart';

import '../l10n.dart';

abstract class ShoppingAgent {
  /// 사용자 입력(텍스트 또는 UI 액션)을 처리하고, 응답을 emitChunk 콜백으로 스트리밍한다.
  Future<void> handle(ChatMessage message);

  /// 헤더에 표시할 잔여 복지포인트.
  int get points;

  /// 데모 언어 — 설정 메뉴에서 바뀌면 다음 턴부터 적용 (remote는 BE 요청의 `lang`으로 전달).
  AppLanguage language = AppLanguage.defaultLanguage;

  /// 데이터 소스에서 최신 포인트를 조회해 [points]를 갱신한다.
  /// 화면 진입 시 호출 — 조회 전 0P로 보이는 문제 방지. (mock은 즉시 반환)
  Future<void> refreshPoints() async {}
}
