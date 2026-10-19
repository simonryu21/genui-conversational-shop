// 시나리오 E2E 검증 — 에이전트 스트림 → A2uiTransportAdapter 파싱 →
// SurfaceController 검증 → Surface 렌더링 → UI 액션 피드백 루프까지
// 실제 파이프라인을 그대로 통과하는지 확인한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui_agent/l10n.dart';
import 'package:genui_agent/main.dart';

import 'test_helpers.dart';

void main() {
  testWidgets('캠핑 질의 → ProductGrid 렌더링 → 담기 → CartSummary → 결제 → 주문',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ConciergeApp());
    await selectLanguage(tester, AppLanguage.ko); // 기본 언어는 영어

    // 1. 추천 질의 → ProductGrid 서피스
    await tester.tap(find.text('남은 포인트로 겨울 캠핑 용품 추천해줘'));
    await pumpFor(tester, const Duration(seconds: 25));

    expect(find.text('겨울 캠핑 보온 3종'), findsOneWidget);
    expect(find.text('세트 전체 담기'), findsOneWidget);
    expect(find.textContaining('동계 머미형 침낭'), findsOneWidget);

    // 2. 세트 전체 담기 → CartSummary 서피스
    await tester.tap(find.text('세트 전체 담기'));
    await pumpFor(tester, const Duration(seconds: 25));

    expect(find.text('장바구니'), findsOneWidget);
    expect(find.text('결제 단계로 진행'), findsOneWidget);
    // 합계 174,000P = 89,000 + 58,000 + 27,000
    expect(find.text('174,000P'), findsWidgets);

    // 3. 결제 단계로 진행 → OrderConfirmation 서피스
    await tester.ensureVisible(find.text('결제 단계로 진행'));
    await tester.tap(find.text('결제 단계로 진행'));
    await pumpFor(tester, const Duration(seconds: 25));

    expect(find.text('주문 접수 완료'), findsOneWidget);
    expect(find.textContaining('결제 대기'), findsOneWidget);
    // 잔여 포인트 180,000 - 174,000 = 6,000P (헤더 + 주문 카드)
    expect(find.text('6,000P'), findsWidgets);
  });

  testWidgets('참치캔 질의 → 인터뷰 폼(표준 카탈로그) → 조건 제출 → 추천 카드',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ConciergeApp());
    await selectLanguage(tester, AppLanguage.ko); // 기본 언어는 영어

    await tester.tap(find.text('참치캔 추천해줘'));
    await pumpFor(tester, const Duration(seconds: 25));

    // 표준 ChoicePicker(chips) 렌더링 확인
    expect(find.text('선호하는 브랜드가 있나요?'), findsOneWidget);
    expect(find.text('동원'), findsOneWidget);
    expect(find.text('이 조건으로 좁혀줘'), findsOneWidget);

    // 저염 선택 후 제출 → 저염 추천 카드
    await tester.tap(find.text('저염'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.text('이 조건으로 좁혀줘'));
    await tester.tap(find.text('이 조건으로 좁혀줘'));
    await pumpFor(tester, const Duration(seconds: 25));

    expect(find.text('조건에 맞는 추천'), findsOneWidget);
    expect(find.textContaining('동원 저염 참치'), findsOneWidget);
  });

  testWidgets('비교 질의 → ComparisonTable 렌더링', (tester) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ConciergeApp());
    await selectLanguage(tester, AppLanguage.ko); // 기본 언어는 영어

    await tester.tap(find.text('침낭 두 개 비교해줘'));
    await pumpFor(tester, const Duration(seconds: 25));

    expect(find.text('침낭 비교'), findsOneWidget);
    expect(find.text('내한온도'), findsOneWidget);
    expect(find.text('-15℃'), findsOneWidget);
    expect(find.text('-5℃'), findsOneWidget);
    expect(find.textContaining('💡'), findsOneWidget);
  });

  testWidgets('포인트 질의 → UI 없이 텍스트로만 응답', (tester) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ConciergeApp());
    await selectLanguage(tester, AppLanguage.ko); // 기본 언어는 영어

    await tester.tap(find.text('잔여 포인트 얼마야?'));
    await pumpFor(tester, const Duration(seconds: 15));

    expect(find.textContaining('2027년 3월 31일에'), findsOneWidget);
    // 어떤 GENERATED UI 서피스도 생성되지 않아야 한다.
    expect(find.textContaining('GENERATED UI'), findsNothing);
  });
}
