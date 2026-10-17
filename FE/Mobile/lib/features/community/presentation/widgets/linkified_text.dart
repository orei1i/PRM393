// lib/features/community/presentation/widgets/linkified_text.dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [uri] outside the app; `false` when nothing could open it.
typedef LinkOpener = Future<bool> Function(Uri uri);

Future<bool> _openExternally(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// Post body with its `http(s)://` and `www.` links underlined and tappable
/// (a pasted video link stays in the text; there is no link mode).
class LinkifiedText extends StatefulWidget {
  const LinkifiedText(this.text, {super.key, this.style, this.opener});

  final String text;
  final TextStyle? style;

  /// Defaults to `url_launcher` (external app / browser).
  final LinkOpener? opener;

  static final _link = RegExp(
    r'''((?:https?:\/\/|www\.)[^\s<>"']+)''',
    caseSensitive: false,
  );

  /// Trailing punctuation that ends a sentence, not the link.
  static String _trimTrailing(String url) {
    var end = url.length;
    while (end > 0 && '.,;:!?)]}'.contains(url[end - 1])) {
      end--;
    }
    return url.substring(0, end);
  }

  /// The links found in [text], in order, as they will be opened.
  static List<Uri> linksIn(String text) => [
        for (final m in _link.allMatches(text))
          if (_uriOf(_trimTrailing(m.group(0)!)) case final uri?) uri,
      ];

  static Uri? _uriOf(String raw) {
    final withScheme =
        raw.toLowerCase().startsWith('www.') ? 'https://$raw' : raw;
    final uri = Uri.tryParse(withScheme);
    if (uri == null || uri.host.isEmpty) return null;
    return uri;
  }

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<LinkifiedText> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  Future<void> _open(Uri uri) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok = await (widget.opener ?? _openExternally)(uri);
    if (!ok) {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
            const SnackBar(content: Text('Không mở được liên kết này.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final text = widget.text;
    final spans = <InlineSpan>[];
    var last = 0;
    final linkStyle = TextStyle(
      color: Theme.of(context).colorScheme.primary,
      decoration: TextDecoration.underline,
    );
    for (final m in LinkifiedText._link.allMatches(text)) {
      final raw = LinkifiedText._trimTrailing(m.group(0)!);
      final uri = LinkifiedText._uriOf(raw);
      if (uri == null) continue;
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      final recognizer = TapGestureRecognizer()..onTap = () => _open(uri);
      _recognizers.add(recognizer);
      spans.add(TextSpan(text: raw, style: linkStyle, recognizer: recognizer));
      last = m.start + raw.length;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(TextSpan(style: widget.style, children: spans));
  }
}
