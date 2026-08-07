import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../showcase_theme.dart';

/// A dark panel holding Dart source, with a button that copies it.
///
/// Every chart on this page is shown next to the code that produced it, and
/// this is that code. The text is never abridged or prettied up for display:
/// what is on screen is what lands on the clipboard, and what lands on the
/// clipboard compiles.
class CodeBlock extends StatelessWidget {
  const CodeBlock({required this.source, this.label, super.key});

  /// The Dart to show, verbatim.
  final String source;

  /// An optional quiet label above the code, naming what it builds.
  final String? label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ShowcaseColors.codeBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    label ?? 'dart',
                    style: ShowcaseText.caption.copyWith(
                      color: ShowcaseColors.codeComment,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _CopyButton(source: source),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Text.rich(
                TextSpan(children: highlightDart(source)),
                style: ShowcaseText.code.copyWith(
                  color: ShowcaseColors.codeText,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.source});

  final String source;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  Timer? _revert;
  bool _justCopied = false;

  @override
  void dispose() {
    // Owned rather than fired and forgotten, so leaving the page while the
    // button still says "Copied" does not leave a timer running behind it.
    _revert?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      key: const ValueKey<String>('copy-code-button'),
      onPressed: _copy,
      style: TextButton.styleFrom(
        foregroundColor: _justCopied
            ? ShowcaseColors.codeString
            : ShowcaseColors.codeComment,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Icon(
        _justCopied ? Icons.check_rounded : Icons.copy_rounded,
        size: 15,
      ),
      label: Text(
        _justCopied ? 'Copied' : 'Copy',
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.source));
    if (!mounted) return;
    setState(() => _justCopied = true);
    _revert?.cancel();
    _revert = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _justCopied = false);
    });
  }
}

/// Splits Dart source into coloured spans.
///
/// Deliberately shallow: comments, strings, a handful of keywords, anything
/// named `Woven...`, and numbers. It never has to be a parser, because the only
/// source it is ever given is source this app generated.
List<TextSpan> highlightDart(String source) {
  final List<TextSpan> spans = <TextSpan>[];
  int plainFrom = 0;

  void emitPlain(int until) {
    if (until > plainFrom) {
      spans.add(TextSpan(text: source.substring(plainFrom, until)));
    }
  }

  for (final RegExpMatch match in _token.allMatches(source)) {
    emitPlain(match.start);
    final Color color = switch (match) {
      _ when match.namedGroup('comment') != null => ShowcaseColors.codeComment,
      _ when match.namedGroup('str') != null => ShowcaseColors.codeString,
      _ when match.namedGroup('keyword') != null => ShowcaseColors.codeKeyword,
      _ when match.namedGroup('type') != null => ShowcaseColors.codeType,
      _ => ShowcaseColors.codeNumber,
    };
    spans.add(
      TextSpan(
        text: match[0],
        style: TextStyle(color: color),
      ),
    );
    plainFrom = match.end;
  }
  emitPlain(source.length);

  return spans;
}

final RegExp _token = RegExp(
  r'(?<comment>//[^\n]*)'
  r"|(?<str>'(?:[^'\\\n]|\\.)*')"
  r'|\b(?<keyword>const|final|true|false|null|import|for|in|void|return)\b'
  r'|\b(?<type>Woven[A-Za-z]*)\b'
  r'|(?<number>-?\d+(?:\.\d+)?)',
);
