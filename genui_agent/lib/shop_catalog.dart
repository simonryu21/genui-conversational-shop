/// 복지몰 도메인 전용 GenUI 카탈로그.
///
/// flutter/genui의 [CatalogItem]으로 커스텀 컴포넌트 4종을 정의하고,
/// 기본 카탈로그(BasicCatalogItems: Text, Column, Button, ChoicePicker 등)에
/// 얹어서 하나의 [Catalog]로 합친다. 에이전트가 보내는 A2UI JSON의
/// `component` 이름이 여기 정의된 name과 매칭되어 렌더링된다.
library;

import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

import 'l10n.dart';
import 'shop_data.dart';

const shopCatalogId = 'com.example.welfare-shop';

/// 에이전트(mock LLM)가 UI 생성에 사용하는 카탈로그.
final Catalog shopCatalog = BasicCatalogItems.asCatalog()
    .copyWithout(
      itemsToRemove: [BasicCatalogItems.audioPlayer, BasicCatalogItems.video],
    )
    .copyWith(
      catalogId: shopCatalogId,
      newItems: [
        productGridItem,
        comparisonTableItem,
        cartSummaryItem,
        orderConfirmationItem,
      ],
    );

// ---------------------------------------------------------------------------
// ProductGrid — 추천 상품 카드 그리드 (+ 세트 전체 담기)
// ---------------------------------------------------------------------------

final CatalogItem productGridItem = CatalogItem(
  name: 'ProductGrid',
  dataSchema: S.object(
    description:
        '추천 상품 카드 그리드. 각 카드에 추천 근거를 표기하고, '
        '개별 담기 또는 세트 전체 담기 액션을 제공한다.',
    properties: {
      'title': S.string(description: '그리드 상단 제목'),
      'products': S.list(
        description: '표시할 상품 목록',
        items: S.object(
          properties: {
            'productId': S.string(),
            'emoji': S.string(),
            'name': S.string(),
            'price': S.integer(description: '복지포인트 가격'),
            'reason': S.string(description: '추천 근거'),
          },
          required: ['productId', 'name', 'price'],
        ),
      ),
      'showTotal': S.boolean(description: '합계 행 표시 여부'),
      'addAllLabel': S.string(description: '세트 전체 담기 버튼 라벨(없으면 버튼 숨김)'),
    },
    required: ['products'],
  ),
  exampleData: [
    () => '''
      [
        {
          "id": "root",
          "component": "ProductGrid",
          "title": "겨울 캠핑 보온 3종",
          "products": [
            {"productId": "p1", "emoji": "🛏️", "name": "동계 침낭",
             "price": 89000, "reason": "보온 우선"}
          ],
          "showTotal": true,
          "addAllLabel": "세트 전체 담기"
        }
      ]
    ''',
  ],
  widgetBuilder: (itemContext) {
    final data = itemContext.data as Map<String, dynamic>;
    final title = data['title'] as String?;
    final products = (data['products'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    final showTotal = data['showTotal'] as bool? ?? false;
    final addAllLabel = data['addAllLabel'] as String?;
    final total = products.fold<num>(
      0,
      (s, p) => s + (p['price'] as num? ?? 0),
    );

    return _GenUiFrame(
      kind: (s) => s.kindRecommend,
      title: title,
      child: Builder(
        builder: (context) {
          final s = AppStrings.at(context);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final p in products)
                    _ProductCard(
                      data: p,
                      onAdd: () => itemContext.dispatchEvent(
                        UserActionEvent(
                          name: 'addToCart',
                          sourceComponentId: itemContext.id,
                          context: {
                            'productIds': [p['productId']],
                          },
                        ),
                      ),
                    ),
                ],
              ),
              if (showTotal || addAllLabel != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (showTotal)
                      Text.rich(
                        TextSpan(
                          text: s.setTotal,
                          children: [
                            TextSpan(
                              text: formatPoints(total),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const Spacer(),
                    if (addAllLabel != null)
                      FilledButton(
                        onPressed: () => itemContext.dispatchEvent(
                          UserActionEvent(
                            name: 'addToCart',
                            sourceComponentId: itemContext.id,
                            context: {
                              'productIds': [
                                for (final p in products) p['productId'],
                              ],
                            },
                          ),
                        ),
                        child: Text(addAllLabel),
                      ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  },
);

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.data, required this.onAdd});

  final Map<String, dynamic> data;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reason = data['reason'] as String?;

    return Container(
      width: 190,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
        color: theme.colorScheme.surface,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 56,
            width: double.infinity,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primaryContainer.withValues(alpha: .5),
                  theme.colorScheme.surface,
                ],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              data['emoji'] as String? ?? '🛍️',
              style: const TextStyle(fontSize: 26),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            data['name'] as String,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            formatPoints(data['price'] as num),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (reason != null) ...[
            const SizedBox(height: 6),
            Text(
              '✓ $reason',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              onPressed: onAdd,
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              child: Text(AppStrings.at(context).add),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ComparisonTable — 상품 비교표
// ---------------------------------------------------------------------------

final CatalogItem comparisonTableItem = CatalogItem(
  name: 'ComparisonTable',
  dataSchema: S.object(
    description:
        '두 개 이상의 상품을 스펙 행 단위로 비교하는 표. '
        '각 상품 열 하단에 담기 버튼을 제공한다.',
    properties: {
      'title': S.string(),
      'products': S.list(
        items: S.object(
          properties: {
            'productId': S.string(),
            'emoji': S.string(),
            'name': S.string(),
            'price': S.integer(),
          },
          required: ['productId', 'name', 'price'],
        ),
      ),
      'rows': S.list(
        description: '비교 항목 행. values는 products와 같은 순서.',
        items: S.object(
          properties: {
            'label': S.string(),
            'values': S.list(items: S.string()),
          },
          required: ['label', 'values'],
        ),
      ),
      'recommendation': S.string(description: '에이전트의 종합 추천 코멘트'),
    },
    required: ['products', 'rows'],
  ),
  widgetBuilder: (itemContext) {
    final data = itemContext.data as Map<String, dynamic>;
    final products = (data['products'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    final rows = (data['rows'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    final recommendation = data['recommendation'] as String?;

    return _GenUiFrame(
      kind: (s) => s.kindCompare,
      title: data['title'] as String?,
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          final s = AppStrings.at(context);
          TableRow buildRow(
            String label,
            List<Widget> cells, {
            bool head = false,
          }) {
            return TableRow(
              decoration: head
                  ? BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: .5),
                    )
                  : null,
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ...cells.map(
                  (c) => Padding(padding: const EdgeInsets.all(8), child: c),
                ),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Table(
                border: TableBorder.all(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                columnWidths: const {0: IntrinsicColumnWidth()},
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  buildRow('', [
                    for (final p in products)
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            p['emoji'] as String? ?? '🛍️',
                            style: const TextStyle(fontSize: 22),
                          ),
                          Text(
                            p['name'] as String,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                  ], head: true),
                  buildRow(s.priceRow, [
                    for (final p in products)
                      Text(
                        formatPoints(p['price'] as num),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ]),
                  for (final r in rows)
                    buildRow(r['label'] as String, [
                      for (final v in (r['values'] as List).cast<String>())
                        Text(v, textAlign: TextAlign.center),
                    ]),
                  buildRow('', [
                    for (final p in products)
                      Center(
                        child: OutlinedButton(
                          onPressed: () => itemContext.dispatchEvent(
                            UserActionEvent(
                              name: 'addToCart',
                              sourceComponentId: itemContext.id,
                              context: {
                                'productIds': [p['productId']],
                              },
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          child: Text(s.add),
                        ),
                      ),
                  ]),
                ],
              ),
              if (recommendation != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.tertiaryContainer.withValues(
                      alpha: .4,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '💡 $recommendation',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  },
);

// ---------------------------------------------------------------------------
// CartSummary — 장바구니 초안 + HITL 안내
// ---------------------------------------------------------------------------

final CatalogItem cartSummaryItem = CatalogItem(
  name: 'CartSummary',
  dataSchema: S.object(
    description:
        '장바구니 초안. 담긴 품목·합계·차감 후 잔여 포인트를 보여주고 '
        '결제 단계 진행 액션을 제공한다.',
    properties: {
      'items': S.list(
        items: S.object(
          properties: {
            'productId': S.string(description: '있으면 항목별 삭제 버튼 활성화'),
            'name': S.string(),
            'price': S.integer(),
          },
          required: ['name', 'price'],
        ),
      ),
      'total': S.integer(),
      'balanceBefore': S.integer(),
      'balanceAfter': S.integer(),
      'note': S.string(description: 'HITL(승인·실결제) 안내 문구'),
    },
    required: ['items', 'total', 'balanceAfter'],
  ),
  widgetBuilder: (itemContext) {
    final data = itemContext.data as Map<String, dynamic>;
    final items = (data['items'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    final note = data['note'] as String?;

    return _GenUiFrame(
      kind: (s) => s.kindCart,
      titleOf: (s) => s.cartTitle,
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          final s = AppStrings.at(context);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final it in items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(child: Text(it['name'] as String)),
                      Text(
                        formatPoints(it['price'] as num),
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      // productId가 있을 때만 항목별 삭제 버튼 (mock 데이터 하위호환)
                      if (it['productId'] != null) ...[
                        const SizedBox(width: 4),
                        IconButton(
                          onPressed: () => itemContext.dispatchEvent(
                            UserActionEvent(
                              name: 'removeFromCart',
                              sourceComponentId: itemContext.id,
                              context: {
                                'productIds': [it['productId']],
                                'label': s.removeLabel(it['name'] as String),
                              },
                            ),
                          ),
                          icon: const Icon(Icons.close, size: 16),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          tooltip: s.removeTooltip,
                        ),
                      ],
                    ],
                  ),
                ),
              const Divider(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s.total,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    formatPoints(data['total'] as num),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s.balanceAfter,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  Text(
                    formatPoints(data['balanceAfter'] as num),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              if (note != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBF3E3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFEEDFBC)),
                  ),
                  child: Text(
                    '${s.hitlPrefix}$note',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF7A5A1E),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () => itemContext.dispatchEvent(
                    UserActionEvent(
                      name: 'checkout',
                      sourceComponentId: itemContext.id,
                      context: {'total': data['total']},
                    ),
                  ),
                  icon: const Icon(Icons.shopping_cart_checkout, size: 18),
                  label: Text(s.checkout),
                ),
              ),
            ],
          );
        },
      ),
    );
  },
);

// ---------------------------------------------------------------------------
// OrderConfirmation — 주문 접수(승인 대기) 확인
// ---------------------------------------------------------------------------

final CatalogItem orderConfirmationItem = CatalogItem(
  name: 'OrderConfirmation',
  dataSchema: S.object(
    description: '주문 접수 확인 카드. 주문번호·금액·상태를 보여준다.',
    properties: {
      'orderId': S.string(),
      'itemCount': S.integer(),
      'total': S.integer(),
      'balanceAfter': S.integer(),
      'status': S.string(description: '예: 결제 대기 (기존 몰 결제창으로 연결)'),
    },
    required: ['orderId', 'total', 'status'],
  ),
  widgetBuilder: (itemContext) {
    final data = itemContext.data as Map<String, dynamic>;
    return _GenUiFrame(
      kind: (s) => s.kindOrder,
      titleOf: (s) => s.orderTitle,
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          final s = AppStrings.at(context);
          Widget row(String k, String v, {bool strong = false}) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    k,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  v,
                  style: strong
                      ? const TextStyle(fontWeight: FontWeight.w700)
                      : null,
                ),
              ],
            ),
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.verified, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    data['status'] as String,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              row(s.orderId, data['orderId'] as String, strong: true),
              if (data['itemCount'] != null)
                row(s.itemCountLabel, s.itemCount(data['itemCount']!)),
              row(
                s.paidPoints,
                formatPoints(data['total'] as num),
                strong: true,
              ),
              if (data['balanceAfter'] != null)
                row(
                  s.remainingPoints,
                  formatPoints(data['balanceAfter'] as num),
                ),
            ],
          );
        },
      ),
    );
  },
);

// ---------------------------------------------------------------------------
// 공통 프레임 — 모든 커스텀 컴포넌트에 "GENERATED UI" 라벨을 달아
// 어느 부분이 에이전트가 생성한 UI인지 명확히 보여준다.
// ---------------------------------------------------------------------------

class _GenUiFrame extends StatelessWidget {
  const _GenUiFrame({
    required this.kind,
    this.title,
    this.titleOf,
    required this.child,
  });

  /// 라벨은 현재 언어로 — 모델이 준 title이 있으면 그대로, 없으면 [titleOf]로 FE 고정 제목.
  final String Function(AppStrings s) kind;
  final String? title;
  final String Function(AppStrings s)? titleOf;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = AppStrings.at(context);
    final title = this.title ?? titleOf?.call(s);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          left: BorderSide(color: theme.colorScheme.primary, width: 4),
          top: BorderSide(color: theme.colorScheme.outlineVariant),
          right: BorderSide(color: theme.colorScheme.outlineVariant),
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                kind(s),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              if (title != null) ...[
                const SizedBox(width: 10),
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
