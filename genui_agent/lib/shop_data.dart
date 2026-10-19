/// 복지몰 mock 데이터 — 실제 서비스라면 상품 검색 API·회원 원장에서 조회한다.
library;

class Product {
  const Product({
    required this.id,
    required this.emoji,
    required this.name,
    required this.price,
    required this.reason,
    this.specs = const {},
  });

  final String id;
  final String emoji;
  final String name;
  final int price;

  /// 추천 근거 (에이전트가 카드에 함께 노출)
  final String reason;

  /// 비교표에 쓰는 상세 스펙
  final Map<String, String> specs;
}

class Member {
  const Member({required this.name, required this.grade, required this.points});
  final String name;
  final String grade;
  final int points;
}

const member = Member(name: '김민수', grade: '책임', points: 180000);

/// ---- 캠핑 추천 세트 ----
const campingSet = [
  Product(
    id: 'sleeping_bag_a',
    emoji: '🛏️',
    name: '동계 머미형 침낭 (-15℃)',
    price: 89000,
    reason: '작년 11월 랜턴 구매 이력 → 동계 캠핑 보온 우선',
    specs: {
      '충전재': '구스다운 800FP',
      '내한온도': '-15℃',
      '무게': '1.4kg',
      '재구매율': '92%',
    },
  ),
  Product(
    id: 'camp_chair',
    emoji: '🪑',
    name: '폴딩 캠핑 체어 2P 세트',
    price: 58000,
    reason: '재구매율 상위 · 수납 크기 45cm',
  ),
  Product(
    id: 'down_blanket',
    emoji: '🧣',
    name: '경량 구스다운 블랭킷',
    price: 27000,
    reason: '잔여 포인트 소진에 최적 · 침낭과 레이어링',
  ),
];

/// ---- 비교 시나리오용 침낭 2종 ----
const sleepingBagB = Product(
  id: 'sleeping_bag_b',
  emoji: '🛌',
  name: '3계절 사각 침낭 (-5℃)',
  price: 52000,
  reason: '가성비 우선 · 봄가을 겸용',
  specs: {
    '충전재': '덕다운 600FP',
    '내한온도': '-5℃',
    '무게': '1.9kg',
    '재구매율': '81%',
  },
);

/// ---- 참치캔 (인터뷰형 좁히기) ----
const tunaProducts = [
  Product(
    id: 'tuna_dongwon_light',
    emoji: '🐟',
    name: '동원 라이트스탠다드 살코기 150g×10',
    price: 21900,
    reason: '재구매율 1위 · 단가 2,190P/캔',
  ),
  Product(
    id: 'tuna_dongwon_lowsalt',
    emoji: '🐟',
    name: '동원 저염 참치 135g×8',
    price: 19800,
    reason: '저염 옵션 중 최저 단가',
  ),
  Product(
    id: 'tuna_sajo_light',
    emoji: '🐠',
    name: '사조 살코기 참치 150g×10',
    price: 19900,
    reason: '살코기 옵션 중 최저가',
  ),
  Product(
    id: 'tuna_ottogi_pepper',
    emoji: '🌶️',
    name: '오뚜기 고추참치 150g×8',
    price: 17600,
    reason: '고추참치 카테고리 판매 1위',
  ),
];

Product? findProduct(String id) {
  for (final p in [...campingSet, sleepingBagB, ...tunaProducts]) {
    if (p.id == id) return p;
  }
  return null;
}

String formatPoints(num v) {
  final s = v.toInt().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    buf.write(s[i]);
    final left = s.length - 1 - i;
    if (left > 0 && left % 3 == 0) buf.write(',');
  }
  return '${buf}P';
}
