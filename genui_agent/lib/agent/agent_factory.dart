/// 에이전트 선택 — 빌드 플래그로 remote(기본) / scripted(오프라인 mock) 전환.
///
/// 실행 예:
///   flutter run -d chrome                                     # remote (localhost:8010)
///   flutter run -d chrome --dart-define=AGENT_MODE=scripted   # 오프라인 mock
///   flutter run -d chrome --dart-define=BE_URL=http://host:8010
///   flutter run -d chrome --dart-define=DEMO_LANG=ko              # 시작 언어 (기본 en, ⚙ 메뉴로 전환)
///
/// `flutter test`(VM)에서는 AGENT_MODE 미지정 시 자동으로 scripted —
/// 기존 위젯 테스트 4개가 BE 없이 계속 동작한다.
library;

import '../l10n.dart';
import '../scripted_agent.dart';
import 'platform_io.dart' if (dart.library.js_interop) 'platform_web.dart';
import 'remote_agent.dart';
import 'shopping_agent.dart';

const String _rawMode = String.fromEnvironment('AGENT_MODE');
const String backendUrl =
    String.fromEnvironment('BE_URL', defaultValue: 'http://localhost:8010');
const String _rawLang = String.fromEnvironment('DEMO_LANG', defaultValue: 'en');

/// 앱 시작 시 언어 (설정 메뉴에서 런타임 전환 가능).
final AppLanguage defaultLanguage = AppLanguage.fromCode(_rawLang);

String get agentMode {
  if (_rawMode.isNotEmpty) return _rawMode;
  return isFlutterTest ? 'scripted' : 'remote';
}

ShoppingAgent createAgent({required void Function(String) emitChunk}) {
  final ShoppingAgent agent = agentMode == 'scripted'
      ? ScriptedShoppingAgent(emitChunk: emitChunk)
      : RemoteShoppingAgent(emitChunk: emitChunk, baseUrl: backendUrl);
  return agent..language = defaultLanguage;
}
