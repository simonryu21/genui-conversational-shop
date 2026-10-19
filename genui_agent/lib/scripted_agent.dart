/// 시나리오 기반 mock 쇼핑 에이전트.
///
/// 실제 서비스라면 이 자리에 LLM(예: Gemini, Claude)이 위치하며, 시스템
/// 프롬프트([PromptBuilder]가 카탈로그 스키마로부터 생성)를 받아 A2UI JSON을
/// 스트리밍한다. 이 프로토타입은 데모 재현성을 위해 질의를 규칙 기반으로
/// 라우팅하고, **실제 LLM과 동일한 출력 형식**(텍스트 + ```json 블록의
/// A2UI v0.9 메시지)을 청크 단위로 스트리밍한다. 파싱·검증·렌더링은 전부
/// flutter/genui SDK가 수행하므로, LLM으로 교체해도 이후 파이프라인은 동일하다.
library;

import 'dart:convert';

import 'package:genui/genui.dart';

import 'agent/shopping_agent.dart';
import 'shop_catalog.dart';
import 'shop_data.dart';

typedef ChunkEmitter = void Function(String chunk);

class ScriptedShoppingAgent extends ShoppingAgent {
  ScriptedShoppingAgent({required this.emitChunk});

  /// LLM 스트리밍 출력에 해당하는 콜백 (A2uiTransportAdapter.addChunk로 연결).
  final ChunkEmitter emitChunk;

  int _surfaceSeq = 0;
  int _orderSeq = 0;
  final List<Product> _cart = [];
  int _points = member.points;

  @override
  int get points => _points;

  String get _newSurfaceId => 'shop-${++_surfaceSeq}';

  // -------------------------------------------------------------------------
  // 요청 라우팅
  // -------------------------------------------------------------------------

  @override
  Future<void> handle(ChatMessage message) async {
    // UI 액션(버튼 클릭 등)이 오면 액션 이름으로 라우팅한다.
    for (final part in message.parts) {
      if (part.isUiInteractionPart) {
        final raw =
            jsonDecode(part.asUiInteractionPart!.interaction)
                as Map<String, dynamic>;
        final action = (raw['action'] as Map?)?.cast<String, dynamic>();
        if (action != null) {
          await _handleAction(
            action['name'] as String? ?? '',
            (action['context'] as Map?)?.cast<String, dynamic>() ?? const {},
          );
          return;
        }
      }
    }

    final text = message.parts
        .whereType<TextPart>()
        .map((p) => p.text)
        .join(' ')
        .trim();
    await _handleText(text);
  }

  // 라우팅 키워드는 한/영 모두 인식한다 (영어 모드의 추천 칩도 같은 시나리오로 연결).
  // 응답 본문은 한국어 mock 데이터 그대로 — 영어 응답은 실제 LLM(remote) 경로에서만 제공된다.
  Future<void> _handleText(String text) async {
    if (RegExp(r'비교|compare', caseSensitive: false).hasMatch(text)) {
      await _respondComparison();
    } else if (RegExp(r'캠핑|아웃도어|텐트|등산|camping|outdoor|tent|hiking',
            caseSensitive: false)
        .hasMatch(text)) {
      await _respondCampingSet();
    } else if (RegExp(r'참치|간식|뭐가 좋|골라|tuna|snack', caseSensitive: false)
        .hasMatch(text)) {
      await _respondTunaInterview();
    } else if (RegExp(r'포인트|잔여|잔액|얼마|points?|balance',
            caseSensitive: false)
        .hasMatch(text)) {
      await _respondPointsTextOnly();
    } else {
      await _respondFallback();
    }
  }

  Future<void> _handleAction(
    String name,
    Map<String, dynamic> context,
  ) async {
    switch (name) {
      case 'addToCart':
        final ids = (context['productIds'] as List? ?? const []).cast<String>();
        await _respondCart(ids);
      case 'checkout':
        await _respondOrderConfirmation();
      case 'refineTuna':
        // ChoicePicker 값은 단일 문자열 또는 리스트(['저염'])로 올 수 있다.
        await _respondTunaResult(
          brand: _asSingleValue(context['brand']),
          type: _asSingleValue(context['type']),
        );
      default:
        await _emitText('처리할 수 없는 액션이에요: $name');
    }
  }

  String? _asSingleValue(Object? v) {
    if (v is String) return v;
    if (v is List && v.isNotEmpty) return v.first?.toString();
    return null;
  }

  // -------------------------------------------------------------------------
  // 시나리오 1 — "남은 포인트로 겨울 캠핑 용품 추천해줘" → 추천 카드 그리드
  // -------------------------------------------------------------------------

  Future<void> _respondCampingSet() async {
    await _emitTrace([
      'get_member_points(김민수) → 180,000P (소멸 D-11)',
      'get_purchase_history(cat=아웃도어) → 작년 11월 LED 캠핑 랜턴',
      'search_products(cat=캠핑, price≤180,000, stock=IN) → 후보 23종',
    ]);
    await _emitText(
      '겨울 캠핑 기준으로, 작년에 랜턴을 구매하신 이력을 참고해 '
      '**보온 중심 3종 세트**를 구성했어요. 세트 합계가 잔여 포인트 안에 '
      '들어오도록 맞췄습니다.',
    );

    final sid = _newSurfaceId;
    await _emitSurface(sid, [
      {
        'id': 'root',
        'component': 'ProductGrid',
        'title': '겨울 캠핑 보온 3종',
        'products': [
          for (final p in campingSet)
            {
              'productId': p.id,
              'emoji': p.emoji,
              'name': p.name,
              'price': p.price,
              'reason': p.reason,
            },
        ],
        'showTotal': true,
        'addAllLabel': '세트 전체 담기',
      },
    ]);
  }

  // -------------------------------------------------------------------------
  // 시나리오 2 — "침낭 두 개 비교해줘" → 비교표
  // -------------------------------------------------------------------------

  Future<void> _respondComparison() async {
    final a = campingSet[0];
    final b = sleepingBagB;
    final specKeys = a.specs.keys.toList();

    await _emitTrace([
      'search_products(kw=침낭) → 2종 선별',
      'get_specs(${a.id}, ${b.id}) → 스펙 4항목',
    ]);
    await _emitText(
      '많이 비교되는 침낭 두 가지를 표로 정리했어요. '
      '**동계 위주라면 왼쪽, 3계절 가성비라면 오른쪽**이 좋아요.',
    );

    final sid = _newSurfaceId;
    await _emitSurface(sid, [
      {
        'id': 'root',
        'component': 'ComparisonTable',
        'title': '침낭 비교',
        'products': [
          for (final p in [a, b])
            {
              'productId': p.id,
              'emoji': p.emoji,
              'name': p.name,
              'price': p.price,
            },
        ],
        'rows': [
          for (final k in specKeys)
            {
              'label': k,
              'values': [a.specs[k] ?? '-', b.specs[k] ?? '-'],
            },
        ],
        'recommendation':
            '겨울 캠핑이 주 목적이고 잔여 포인트가 충분하므로 -15℃ 동계 침낭을 추천해요. '
            '차액 37,000P는 블랭킷과 조합하면 딱 맞습니다.',
      },
    ]);
  }

  // -------------------------------------------------------------------------
  // 시나리오 3 — "참치캔 추천해줘" → 인터뷰형 폼 (표준 카탈로그 컴포넌트만 사용)
  // -------------------------------------------------------------------------

  Future<void> _respondTunaInterview() async {
    await _emitTrace(['search_products(kw=참치캔) → 후보 32종 (너무 많음)']);
    await _emitText(
      '참치캔이 **32종**이나 있어요. 전부 나열하는 대신, '
      '두 가지만 여쭤보고 좁혀드릴게요.',
    );

    final sid = _newSurfaceId;
    await _emitSurface(sid, [
      {
        'id': 'root',
        'component': 'Column',
        'children': ['brandPicker', 'typePicker', 'submitBtn'],
      },
      {
        'id': 'brandPicker',
        'component': 'ChoicePicker',
        'label': '선호하는 브랜드가 있나요?',
        'displayStyle': 'chips',
        'variant': 'mutuallyExclusive',
        'options': [
          {'label': '동원', 'value': '동원'},
          {'label': '사조', 'value': '사조'},
          {'label': '오뚜기', 'value': '오뚜기'},
          {'label': '상관없음', 'value': 'any'},
        ],
        'value': {'path': '/tuna/brand'},
      },
      {
        'id': 'typePicker',
        'component': 'ChoicePicker',
        'label': '어떤 타입을 찾으세요?',
        'displayStyle': 'chips',
        'variant': 'mutuallyExclusive',
        'options': [
          {'label': '살코기(기본)', 'value': '살코기'},
          {'label': '저염', 'value': '저염'},
          {'label': '고추참치', 'value': '고추'},
        ],
        'value': {'path': '/tuna/type'},
      },
      {
        'id': 'submitBtn',
        'component': 'Button',
        'child': 'submitLabel',
        'variant': 'primary',
        'action': {
          'event': {
            'name': 'refineTuna',
            'context': {
              'brand': {'path': '/tuna/brand'},
              'type': {'path': '/tuna/type'},
            },
          },
        },
      },
      {
        'id': 'submitLabel',
        'component': 'Text',
        'text': '이 조건으로 좁혀줘',
      },
    ]);

    // 선택 전 기본값을 데이터 모델에 시딩해 두면 바로 제출해도 안전하다.
    await _emitJson({
      'version': 'v0.9',
      'updateDataModel': {
        'surfaceId': sid,
        'path': '/tuna',
        'value': {'brand': 'any', 'type': '살코기'},
      },
    });
  }

  Future<void> _respondTunaResult({String? brand, String? type}) async {
    final effectiveBrand = (brand == null || brand == 'any') ? null : brand;

    Product pick;
    if (effectiveBrand == '사조') {
      pick = tunaProducts[2];
    } else if (effectiveBrand == '오뚜기' || type == '고추') {
      pick = tunaProducts[3];
    } else if (type == '저염') {
      pick = tunaProducts[1];
    } else {
      pick = tunaProducts[0]; // 재구매율 1위
    }

    final conds = [
      if (effectiveBrand != null) '브랜드 $effectiveBrand',
      if (type != null) '타입 $type',
    ];
    await _emitTrace([
      'filter_products(${conds.isEmpty ? '조건 없음 → 재구매율순' : conds.join(', ')}) → 32종 → 1종',
    ]);
    await _emitText(
      conds.isEmpty
          ? '조건을 안 주셨으니 **재구매율 1위** 기준으로 골랐어요.'
          : '좋아요 — **${conds.join(' · ')}** 조건으로 좁혔어요. 이게 제일 잘 맞아요.',
    );

    final sid = _newSurfaceId;
    await _emitSurface(sid, [
      {
        'id': 'root',
        'component': 'ProductGrid',
        'title': '조건에 맞는 추천',
        'products': [
          {
            'productId': pick.id,
            'emoji': pick.emoji,
            'name': pick.name,
            'price': pick.price,
            'reason': pick.reason,
          },
        ],
        'showTotal': false,
      },
    ]);
  }

  // -------------------------------------------------------------------------
  // 액션 — 담기 → 장바구니 초안 / 결제 → 주문 접수
  // -------------------------------------------------------------------------

  Future<void> _respondCart(List<String> productIds) async {
    for (final id in productIds) {
      final p = findProduct(id);
      if (p != null && !_cart.any((c) => c.id == p.id)) _cart.add(p);
    }
    final total = _cart.fold<int>(0, (s, p) => s + p.price);

    await _emitTrace([
      'create_cart_draft(items=${_cart.length}) → DRAFT',
      'check_balance(180,000P - ${formatPoints(total)}) → OK',
    ]);
    await _emitText(
      '장바구니 **초안**을 만들었어요. 결제 확정 전까지 포인트는 차감되지 않습니다.',
    );

    final sid = _newSurfaceId;
    await _emitSurface(sid, [
      {
        'id': 'root',
        'component': 'CartSummary',
        'items': [
          for (final p in _cart) {'name': p.name, 'price': p.price},
        ],
        'total': total,
        'balanceBefore': _points,
        'balanceAfter': _points - total,
        'note': '실제 결제는 기존 몰 결제창에서 본인 확인 후 진행됩니다. '
            '에이전트는 초안까지만 작성합니다.',
      },
    ]);
  }

  Future<void> _respondOrderConfirmation() async {
    final total = _cart.fold<int>(0, (s, p) => s + p.price);
    final count = _cart.length;
    _points -= total;
    final orderId =
        'WF-2026-${(++_orderSeq + 1040).toString().padLeft(4, '0')}';
    _cart.clear();

    await _emitTrace([
      'submit_order(draft) → $orderId',
      'ledger.append(주문접수, -${formatPoints(total)}) → 원장 기록',
    ]);
    await _emitText('주문을 접수했어요. 결제창으로 연결해 확정만 남았습니다.');

    final sid = _newSurfaceId;
    await _emitSurface(sid, [
      {
        'id': 'root',
        'component': 'OrderConfirmation',
        'orderId': orderId,
        'itemCount': count,
        'total': total,
        'balanceAfter': _points,
        'status': '결제 대기 — 기존 몰 결제창에서 확정됩니다',
      },
    ]);
  }

  // -------------------------------------------------------------------------
  // 텍스트만으로 충분한 질의 — 에이전트가 UI를 만들지 "않기로" 판단하는 케이스
  // -------------------------------------------------------------------------

  Future<void> _respondPointsTextOnly() async {
    await _emitTrace(['get_member_points(김민수) → 원장 조회']);
    await _emitText(
      '현재 잔여 복지포인트는 **${formatPoints(_points)}**예요. '
      '이 중 120,000P가 **2027년 3월 31일에 소멸**됩니다. '
      '소멸 전에 쓰실 만한 상품을 추천해드릴까요? '
      '_(단순 조회는 이렇게 텍스트로만 답해요 — UI가 필요한 질의에서만 화면을 생성합니다.)_',
    );
  }

  Future<void> _respondFallback() async {
    await _emitText(
      '프로토타입이라 준비된 시나리오만 시연돼요. 이렇게 물어보세요:\n\n'
      '1. **"남은 포인트로 겨울 캠핑 용품 추천해줘"** → 추천 카드 그리드\n'
      '2. **"침낭 두 개 비교해줘"** → 비교표\n'
      '3. **"참치캔 추천해줘"** → 인터뷰형 좁히기 폼\n'
      '4. **"잔여 포인트 얼마야?"** → 텍스트 응답 (UI 없음)\n\n'
      '카드의 **담기 → 결제 단계로 진행** 버튼을 누르면 장바구니·주문 UI로 이어집니다.',
    );
  }

  // -------------------------------------------------------------------------
  // 스트리밍 에뮬레이션 — 실제 LLM 출력과 동일하게 청크 단위로 내보낸다.
  // -------------------------------------------------------------------------

  Future<void> _emitText(String text) async {
    // 단어 단위로 잘라 타이핑되듯 스트리밍한다.
    final words = text.split(' ');
    for (var i = 0; i < words.length; i++) {
      emitChunk(i == 0 ? words[i] : ' ${words[i]}');
      await Future<void>.delayed(const Duration(milliseconds: 18));
    }
    emitChunk('\n\n');
  }

  /// 도구 호출 흔적(tool trace)을 모노스페이스 라인으로 표시.
  Future<void> _emitTrace(List<String> lines) async {
    for (final line in lines) {
      emitChunk('▸ `$line`  \n');
      await Future<void>.delayed(const Duration(milliseconds: 220));
    }
    emitChunk('\n');
  }

  /// createSurface + updateComponents를 A2UI v0.9 JSON 블록으로 스트리밍.
  Future<void> _emitSurface(
    String surfaceId,
    List<Map<String, Object?>> components,
  ) async {
    await _emitJson({
      'version': 'v0.9',
      'createSurface': {
        'surfaceId': surfaceId,
        'catalogId': shopCatalogId,
        'sendDataModel': true,
      },
    });
    await _emitJson({
      'version': 'v0.9',
      'updateComponents': {
        'surfaceId': surfaceId,
        'components': components,
      },
    });
  }

  Future<void> _emitJson(Map<String, Object?> message) async {
    final s = jsonEncode(message);
    emitChunk('\n```json\n');
    // LLM 토큰 스트림처럼 JSON도 조각내서 보낸다 — 파서가 버퍼링해 재조립한다.
    for (var i = 0; i < s.length; i += 64) {
      emitChunk(s.substring(i, i + 64 > s.length ? s.length : i + 64));
      await Future<void>.delayed(const Duration(milliseconds: 8));
    }
    emitChunk('\n```\n');
  }
}
