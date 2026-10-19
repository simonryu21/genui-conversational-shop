// 위젯 테스트 공용 헬퍼.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui_agent/l10n.dart';

/// 가짜 시계로 [total]만큼 프레임을 진행 (scripted 에이전트의 스트리밍 딜레이 소화).
Future<void> pumpFor(WidgetTester tester, Duration total) async {
  const step = Duration(milliseconds: 100);
  var elapsed = Duration.zero;
  while (elapsed < total) {
    await tester.pump(step);
    elapsed += step;
  }
}

/// 헤더 ⚙ 메뉴에서 [lang]을 선택한다 (앱 기본 언어는 영어 — 한국어 시나리오 테스트 전에 호출).
Future<void> selectLanguage(WidgetTester tester, AppLanguage lang) async {
  await tester.tap(find.byKey(const Key('settings-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(lang.label));
  await tester.pumpAndSettle();
}
