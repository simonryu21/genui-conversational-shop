// 설정(⚙) 메뉴의 언어 전환 — 기본은 영어. 한국어 선택 시 앱 크롬(추천 칩·힌트·헤더)이
// 즉시 바뀌고, 영어 추천 칩도 scripted 에이전트의 같은 시나리오로 라우팅되는지 확인한다.
// (모델 응답 언어는 remote/BE 경로에서 시스템 프롬프트로 결정 — 여기서는 다루지 않음)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui_agent/l10n.dart';
import 'package:genui_agent/main.dart';

import 'test_helpers.dart';

void main() {
  testWidgets('기본 언어는 영어 — 영어 추천 칩이 scripted 시나리오로 라우팅', (tester) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ConciergeApp());
    await tester.pump();

    expect(find.text(AppStrings.en.title), findsOneWidget);
    expect(find.text(AppStrings.ko.title), findsNothing);
    for (final s in AppStrings.en.suggestions) {
      expect(find.text(s), findsOneWidget);
    }
    expect(find.text(AppStrings.en.inputHint), findsOneWidget);

    // 영어 칩 → 비교 시나리오 (mock 본문은 한국어)
    await tester.tap(find.text('Compare the two sleeping bags'));
    await pumpFor(tester, const Duration(seconds: 25));
    expect(find.text('침낭 비교'), findsOneWidget); // 모델(mock)이 준 제목
    // FE 내장 라벨은 영어
    expect(find.text(AppStrings.en.add), findsWidgets);
    expect(find.text(AppStrings.en.priceRow), findsOneWidget);
    expect(find.text(AppStrings.ko.add), findsNothing);
    expect(find.textContaining(AppStrings.en.memberName), findsOneWidget);
  });

  testWidgets('⚙ 메뉴에서 한국어 선택 → 추천 칩·힌트·헤더가 한국어로 전환', (tester) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ConciergeApp());
    await tester.pump();

    await tester.tap(find.byKey(const Key('settings-menu')));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.en.languageMenuTitle), findsOneWidget);

    await tester.tap(find.text(AppLanguage.ko.label));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.ko.title), findsOneWidget);
    expect(find.text(AppStrings.en.title), findsNothing);
    for (final s in AppStrings.ko.suggestions) {
      expect(find.text(s), findsOneWidget);
    }
    expect(find.text(AppStrings.ko.inputHint), findsOneWidget);
  });

  test('AppLanguage.fromCode — 대소문자 무시, 미지원 코드는 기본 언어(en)', () {
    expect(AppLanguage.defaultLanguage, AppLanguage.en);
    expect(AppLanguage.fromCode('KO'), AppLanguage.ko);
    expect(AppLanguage.fromCode('en'), AppLanguage.en);
    expect(AppLanguage.fromCode('fr'), AppLanguage.en);
    expect(AppLanguage.fromCode(null), AppLanguage.en);
  });
}
