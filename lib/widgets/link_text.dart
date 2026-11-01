import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// A web link, email address or phone number found in some text.
class FoundLink {
  const FoundLink(this.start, this.end, this.text, this.uri);

  final int start;
  final int end;

  /// As written in the text.
  final String text;

  /// What opening it launches (https:, mailto: or tel:).
  final Uri uri;
}

final _url = RegExp(r'''\b(?:https?://|www\.)[^\s<>"']+''', caseSensitive: false);
final _email = RegExp(r'\b[\w.+-]+@[\w-]+(?:\.[\w-]+)+\b');
final _phone = RegExp(r'(?<![\w/.:-])\+?\(?\d[\d ()-]{6,}\d(?![\w/.:-])');
final _dateLike = RegExp(r'^\d{1,4}[-/.]\d{1,2}[-/.]\d{1,4}$');

/// Finds links in [text], in order and not overlapping. A trailing full stop, comma or
/// bracket is left out of a link, so "see www.x.com." links to www.x.com.
List<FoundLink> findLinks(String text) {
  final found = <FoundLink>[];
  bool overlaps(int s, int e) => found.any((f) => s < f.end && e > f.start);

  for (final m in _url.allMatches(text)) {
    var raw = m.group(0)!;
    while (raw.isNotEmpty && '.,;:!?)]}'.contains(raw[raw.length - 1])) {
      // Keep a closing bracket that has its opening one inside the link (Wikipedia style).
      if (raw.endsWith(')') && '('.allMatches(raw).length >= ')'.allMatches(raw).length) break;
      raw = raw.substring(0, raw.length - 1);
    }
    final uri = Uri.tryParse(raw.toLowerCase().startsWith('www.') ? 'https://$raw' : raw);
    if (uri != null) found.add(FoundLink(m.start, m.start + raw.length, raw, uri));
  }
  for (final m in _email.allMatches(text)) {
    if (overlaps(m.start, m.end)) continue;
    found.add(FoundLink(m.start, m.end, m.group(0)!, Uri(scheme: 'mailto', path: m.group(0)!)));
  }
  for (final m in _phone.allMatches(text)) {
    final raw = m.group(0)!.trim();
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    // Dates like 2026-11-01 and short numbers aren't phone numbers.
    if (digits.length < 8 || digits.length > 15 || _dateLike.hasMatch(raw) || overlaps(m.start, m.end)) continue;
    final dial = (raw.startsWith('+') ? '+' : '') + digits;
    found.add(FoundLink(m.start, m.start + m.group(0)!.length, raw, Uri(scheme: 'tel', path: dial)));
  }
  found.sort((a, b) => a.start.compareTo(b.start));
  return found;
}

Future<void> openLink(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

/// Text with its web links, email addresses and phone numbers underlined and tappable.
class LinkText extends StatefulWidget {
  const LinkText(this.text, {super.key, this.style, this.linkColor});

  final String text;
  final TextStyle? style;

  /// Defaults to a blue that suits the theme.
  final Color? linkColor;

  @override
  State<LinkText> createState() => _LinkTextState();
}

class _LinkTextState extends State<LinkText> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  void _clear() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    _clear();
    final text = widget.text;
    final links = findLinks(text);
    if (links.isEmpty) return Text(text, style: widget.style);
    final linkColor = widget.linkColor ??
        (Theme.of(context).brightness == Brightness.dark ? Colors.lightBlueAccent : const Color(0xFF0D47A1));
    final spans = <InlineSpan>[];
    var at = 0;
    for (final l in links) {
      if (l.start > at) spans.add(TextSpan(text: text.substring(at, l.start)));
      final r = TapGestureRecognizer()..onTap = () => openLink(l.uri);
      _recognizers.add(r);
      spans.add(TextSpan(
        text: l.text,
        recognizer: r,
        mouseCursor: SystemMouseCursors.click,
        style: TextStyle(color: linkColor, decoration: TextDecoration.underline, decorationColor: linkColor),
      ));
      at = l.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return Text.rich(TextSpan(children: spans), style: widget.style);
  }
}
