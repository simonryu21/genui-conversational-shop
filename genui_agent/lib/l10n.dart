/// 데모 UI 문자열 — 언어별 (헤더 ⚙ 설정 메뉴에서 전환).
///
/// 모델 응답 언어는 BE가 요청의 `lang`으로 시스템 프롬프트를 바꿔 결정하고,
/// 여기는 모델을 거치지 않는 앱 크롬(헤더·힌트·추천 칩·액션 라벨·오류 문구)과
/// 카탈로그 위젯에 내장된 고정 라벨("담기", "세트 합계", "장바구니" 등)을 다룬다.
/// 위젯 트리에는 [AppLocale]로 주입되어 언어가 바뀌면 생성된 서피스도 함께 다시 그려진다.
library;

import 'package:flutter/widgets.dart';

enum AppLanguage {
  ko('ko', '한국어'),
  en('en', 'English');

  const AppLanguage(this.code, this.label);

  /// BE `lang` 필드 값 / --dart-define=DEMO_LANG 값.
  final String code;

  /// 설정 메뉴에 표시되는 이름 (항상 해당 언어로).
  final String label;

  /// 앱·BE 기본 언어 (영어). --dart-define=DEMO_LANG / .env DEMO_LANGUAGE로 바꾼다.
  static const AppLanguage defaultLanguage = AppLanguage.en;

  static AppLanguage fromCode(String? code) {
    for (final l in AppLanguage.values) {
      if (l.code == code?.toLowerCase()) return l;
    }
    return AppLanguage.en; // 기본 언어
  }
}

/// 현재 언어의 [AppStrings]를 하위 트리에 공급한다 (카탈로그 위젯이 `AppStrings.at(context)`로 읽음).
class AppLocale extends InheritedWidget {
  const AppLocale({super.key, required this.strings, required super.child});

  final AppStrings strings;

  static AppStrings? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppLocale>()?.strings;

  @override
  bool updateShouldNotify(AppLocale oldWidget) => strings != oldWidget.strings;
}

class AppStrings {
  const AppStrings._({
    required this.brand,
    required this.title,
    required this.memberName,
    required this.memberGrade,
    required this.expireNote,
    required this.suggestions,
    required this.inputHint,
    required this.settingsTooltip,
    required this.languageMenuTitle,
    required this.offlineMockNote,
    required this.errorPrefix,
    required this.pipelineErrorPrefix,
    required this.serverError,
    required this.backendUnreachable,
    required this.actionAddToCart,
    required this.actionCheckout,
    required this.actionConfirmPayment,
    required this.actionRemoveFromCart,
    required this.actionRefine,
    required this.actionGeneric,
    required this.actionUnknown,
    required this.kindRecommend,
    required this.kindCompare,
    required this.kindCart,
    required this.kindOrder,
    required this.add,
    required this.setTotal,
    required this.priceRow,
    required this.cartTitle,
    required this.removeTooltip,
    required this.removeLabel,
    required this.total,
    required this.balanceAfter,
    required this.hitlPrefix,
    required this.checkout,
    required this.orderTitle,
    required this.orderId,
    required this.itemCountLabel,
    required this.itemCount,
    required this.paidPoints,
    required this.remainingPoints,
  });

  // ── 앱 크롬 ──
  final String brand;
  final String title;
  final String memberName;
  final String memberGrade;
  final String expireNote;
  final List<String> suggestions;
  final String inputHint;
  final String settingsTooltip;
  final String languageMenuTitle;
  final String offlineMockNote;
  final String errorPrefix;
  final String pipelineErrorPrefix;
  final String Function(int status) serverError;
  final String Function(Object error) backendUnreachable;

  // ── 타임라인에 표시되는 UI 액션 라벨 ──
  final String actionAddToCart;
  final String actionCheckout;
  final String actionConfirmPayment;
  final String actionRemoveFromCart;
  final String actionRefine;
  final String actionGeneric;
  final String Function(String? name) actionUnknown;

  // ── 카탈로그 위젯 내장 라벨 (모델이 아니라 FE가 그리는 고정 문구) ──
  final String kindRecommend;
  final String kindCompare;
  final String kindCart;
  final String kindOrder;
  final String add;
  final String setTotal;
  final String priceRow;
  final String cartTitle;
  final String removeTooltip;
  final String Function(String name) removeLabel;
  final String total;
  final String balanceAfter;
  final String hitlPrefix;
  final String checkout;
  final String orderTitle;
  final String orderId;
  final String itemCountLabel;
  final String Function(Object count) itemCount;
  final String paidPoints;
  final String remainingPoints;

  /// 헤더 아바타 이니셜.
  String get memberInitial => memberName.substring(0, 1);

  static AppStrings of(AppLanguage lang) => switch (lang) {
    AppLanguage.ko => ko,
    AppLanguage.en => en,
  };

  /// 위젯 트리의 [AppLocale]에서 현재 언어 문자열을 읽는다 (없으면 기본 언어).
  static AppStrings at(BuildContext context) =>
      AppLocale.maybeOf(context) ?? of(AppLanguage.defaultLanguage);

  static final ko = AppStrings._(
    brand: 'GENUI · SHOPPING ASSISTANT',
    title: 'GenUI 쇼핑 어시스턴트',
    memberName: '김민수',
    memberGrade: '책임',
    expireNote: "'27/3/31 일부 소멸",
    suggestions: const [
      '남은 포인트로 겨울 캠핑 용품 추천해줘',
      '침낭 두 개 비교해줘',
      '참치캔 추천해줘',
      '잔여 포인트 얼마야?',
    ],
    inputHint: '예: 남은 포인트로 캠핑 용품 추천해줘',
    settingsTooltip: '설정',
    languageMenuTitle: '언어 / Language',
    offlineMockNote: '오프라인 mock 응답은 한국어로만 제공됩니다.',
    errorPrefix: '오류가 발생했어요: ',
    pipelineErrorPrefix: 'A2UI 파이프라인 오류: ',
    serverError: (status) => '\n⚠️ **서버 오류** (HTTP $status)\n',
    backendUnreachable: (e) =>
        '\n\n⚠️ **백엔드 연결 실패**: $e\n\n'
        '서버가 켜져 있는지 확인하세요 (`shop_backend/run_server.bat`, 포트 8010).\n',
    actionAddToCart: '🛒 담기 선택',
    actionCheckout: '💳 결제 단계로 진행',
    actionConfirmPayment: '✅ 결제 확정',
    actionRemoveFromCart: '🗑 장바구니에서 삭제',
    actionRefine: '☑️ 조건 제출',
    actionGeneric: '🖱 UI 액션',
    actionUnknown: (name) => '🖱 UI 액션: $name',
    kindRecommend: 'GENERATED UI · 추천',
    kindCompare: 'GENERATED UI · 비교',
    kindCart: 'GENERATED UI · 장바구니 초안',
    kindOrder: 'GENERATED UI · 주문',
    add: '담기',
    setTotal: '세트 합계  ',
    priceRow: '가격',
    cartTitle: '장바구니',
    removeTooltip: '삭제',
    removeLabel: (name) => '"$name" 장바구니에서 삭제',
    total: '합계',
    balanceAfter: '차감 후 잔여 포인트',
    hitlPrefix: 'ⓘ HITL  ',
    checkout: '결제 단계로 진행',
    orderTitle: '주문 접수 완료',
    orderId: '주문번호',
    itemCountLabel: '품목 수',
    itemCount: (n) => '$n개',
    paidPoints: '결제 포인트',
    remainingPoints: '잔여 포인트',
  );

  static final en = AppStrings._(
    brand: 'GENUI · SHOPPING ASSISTANT',
    title: 'Shopping Assistant',
    memberName: 'Minsu Kim',
    memberGrade: 'Manager',
    expireNote: "exp. 3/31/'27",
    suggestions: const [
      'Recommend winter camping gear with my remaining points',
      'Compare the two sleeping bags',
      'Recommend canned tuna',
      'How many points do I have left?',
    ],
    inputHint: 'e.g. Recommend camping gear with my remaining points',
    settingsTooltip: 'Settings',
    languageMenuTitle: 'Language / 언어',
    offlineMockNote: 'Offline mock replies are available in Korean only.',
    errorPrefix: 'Something went wrong: ',
    pipelineErrorPrefix: 'A2UI pipeline error: ',
    serverError: (status) => '\n⚠️ **Server error** (HTTP $status)\n',
    backendUnreachable: (e) =>
        '\n\n⚠️ **Could not reach the backend**: $e\n\n'
        'Make sure the server is running (`shop_backend/run_server.sh`, port 8010).\n',
    actionAddToCart: '🛒 Add to cart',
    actionCheckout: '💳 Proceed to checkout',
    actionConfirmPayment: '✅ Confirm payment',
    actionRemoveFromCart: '🗑 Remove from cart',
    actionRefine: '☑️ Submit filters',
    actionGeneric: '🖱 UI action',
    actionUnknown: (name) => '🖱 UI action: $name',
    kindRecommend: 'GENERATED UI · RECOMMENDATION',
    kindCompare: 'GENERATED UI · COMPARISON',
    kindCart: 'GENERATED UI · CART DRAFT',
    kindOrder: 'GENERATED UI · ORDER',
    add: 'Add',
    setTotal: 'Set total  ',
    priceRow: 'Price',
    cartTitle: 'Cart',
    removeTooltip: 'Remove',
    removeLabel: (name) => 'Remove "$name" from cart',
    total: 'Total',
    balanceAfter: 'Points left after payment',
    hitlPrefix: 'ⓘ HITL  ',
    checkout: 'Proceed to checkout',
    orderTitle: 'Order received',
    orderId: 'Order no.',
    itemCountLabel: 'Items',
    itemCount: (n) => '$n item(s)',
    paidPoints: 'Points to pay',
    remainingPoints: 'Points remaining',
  );
}
