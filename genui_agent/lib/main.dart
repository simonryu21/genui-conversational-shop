import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:genui/genui.dart';
import 'package:logging/logging.dart';

import 'chat_session.dart';
import 'l10n.dart';
import 'shop_data.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen(
    (r) => debugPrint('[${r.level.name}] ${r.loggerName}: ${r.message}'),
  );
  runApp(const ConciergeApp());
}

class ConciergeApp extends StatelessWidget {
  const ConciergeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GenUI Shopping Assistant',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7A5CC9)),
        scaffoldBackgroundColor: const Color(0xFFF2F4F8),
        useMaterial3: true,
      ),
      home: const ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final ShoppingChatSession _session;
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _session = ShoppingChatSession();
    _session.addListener(_autoScroll);
  }

  void _autoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send([String? preset]) async {
    final text = preset ?? _input.text;
    _input.clear();
    await _session.sendText(text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Container(
            color: const Color(0xFFFBFCFE),
            child: ListenableBuilder(
              listenable: _session,
              builder: (context, _) {
                final s = _session.strings;
                return AppLocale(
                  strings: s,
                  child: Column(
                    children: [
                      _Header(
                        points: _session.remainingPoints,
                        strings: s,
                        language: _session.language,
                        offlineMock: _session.isOfflineMock,
                        onLanguageSelected: _session.setLanguage,
                      ),
                      Expanded(
                        child: ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(28, 20, 28, 8),
                          itemCount: _session.entries.length,
                          itemBuilder: (context, i) =>
                              _EntryView(_session.entries[i], _session),
                        ),
                      ),
                      if (_session.isProcessing)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 6),
                          child: SizedBox(
                            width: 130,
                            child: LinearProgressIndicator(minHeight: 3),
                          ),
                        ),
                      _SuggestionBar(
                        suggestions: s.suggestions,
                        enabled: !_session.isProcessing,
                        onTap: (text) => _send(text),
                      ),
                      _InputBar(
                        controller: _input,
                        hint: s.inputHint,
                        enabled: !_session.isProcessing,
                        onSend: _send,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _session.removeListener(_autoScroll);
    _session.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.points,
    required this.strings,
    required this.language,
    required this.offlineMock,
    required this.onLanguageSelected,
  });

  final int points;
  final AppStrings strings;
  final AppLanguage language;
  final bool offlineMock;
  final ValueChanged<AppLanguage> onLanguageSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          // 브랜드 라벨(3)보다 회원 pill 슬롯(4)을 넉넉히 — 영어처럼 긴 문자열도 overflow 없이 말줄임
          Flexible(
            flex: 3,
            child: Text(
              strings.brand,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Text(
            strings.title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            flex: 4,
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Text(
                        strings.memberInitial,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '${strings.memberName} ${strings.memberGrade}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      formatPoints(points),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        strings.expireNote,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFFC94D57),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _SettingsMenu(
            strings: strings,
            language: language,
            offlineMock: offlineMock,
            onLanguageSelected: onLanguageSelected,
          ),
        ],
      ),
    );
  }
}

/// 헤더 ⚙ 설정 메뉴 — 데모 언어 선택. 선택 즉시 앱 크롬이 바뀌고,
/// 다음 턴부터 BE 요청의 `lang`으로 전달되어 모델 응답 언어도 바뀐다.
class _SettingsMenu extends StatelessWidget {
  const _SettingsMenu({
    required this.strings,
    required this.language,
    required this.offlineMock,
    required this.onLanguageSelected,
  });

  final AppStrings strings;
  final AppLanguage language;
  final bool offlineMock;
  final ValueChanged<AppLanguage> onLanguageSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<AppLanguage>(
      key: const Key('settings-menu'),
      tooltip: strings.settingsTooltip,
      icon: const Icon(Icons.settings_outlined),
      onSelected: onLanguageSelected,
      itemBuilder: (context) => [
        PopupMenuItem<AppLanguage>(
          enabled: false,
          height: 32,
          child: Text(
            strings.languageMenuTitle,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final lang in AppLanguage.values)
          CheckedPopupMenuItem<AppLanguage>(
            value: lang,
            checked: lang == language,
            child: Text(lang.label),
          ),
        if (offlineMock) ...[
          const PopupMenuDivider(),
          PopupMenuItem<AppLanguage>(
            enabled: false,
            height: 32,
            child: Text(
              strings.offlineMockNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _EntryView extends StatelessWidget {
  const _EntryView(this.entry, this.session);

  final ChatEntry entry;
  final ShoppingChatSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 에이전트가 생성한 GenUI 서피스 — flutter/genui의 Surface 위젯이 렌더링.
    if (entry.surfaceId != null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 14, right: 60),
          constraints: const BoxConstraints(maxWidth: 700),
          child: Surface(
            surfaceContext: session.surfaceController.contextFor(
              entry.surfaceId!,
            ),
          ),
        ),
      );
    }

    if (entry.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 14, left: 120),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: entry.isAction
                ? theme.colorScheme.surfaceContainerHighest
                : theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            entry.text ?? '',
            style: TextStyle(
              color: entry.isAction
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.onPrimary,
              fontSize: entry.isAction ? 13 : 15,
            ),
          ),
        ),
      );
    }

    // 에이전트 텍스트 (마크다운)
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14, right: 120),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(4),
        ),
        child: MarkdownBody(data: entry.text ?? ''),
      ),
    );
  }
}

class _SuggestionBar extends StatelessWidget {
  const _SuggestionBar({
    required this.suggestions,
    required this.enabled,
    required this.onTap,
  });

  final List<String> suggestions;
  final bool enabled;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final s in suggestions)
            ActionChip(
              label: Text(s, style: const TextStyle(fontSize: 12.5)),
              onPressed: enabled ? () => onTap(s) : null,
            ),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.hint,
    required this.enabled,
    required this.onSend,
  });

  final TextEditingController controller;
  final String hint;
  final bool enabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
      color: theme.colorScheme.surface,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              decoration: InputDecoration(
                hintText: hint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 10),
          IconButton.filled(
            onPressed: enabled ? onSend : null,
            icon: const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}
