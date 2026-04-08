import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Text where words are tappable (tap to look up) and selectable.
/// Words show a subtle dotted underline to hint they're tappable.
class TappableText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final void Function(String word) onWordTap;

  const TappableText({
    super.key,
    required this.text,
    this.style,
    required this.onWordTap,
  });

  @override
  Widget build(BuildContext context) {
    final defaultStyle = style ?? DefaultTextStyle.of(context).style;
    final regex = RegExp(r"([a-zA-Z'-]+)|([^a-zA-Z'-]+)");
    final matches = regex.allMatches(text);

    final spans = <InlineSpan>[];
    for (final m in matches) {
      final word = m.group(1);
      final other = m.group(2);

      if (word != null && word.length > 1) {
        spans.add(TextSpan(
          text: word,
          style: defaultStyle,
          recognizer: TapGestureRecognizer()
            ..onTap = () => onWordTap(_cleanWord(word)),
        ));
      } else {
        spans.add(TextSpan(text: word ?? other ?? '', style: defaultStyle));
      }
    }

    return Text.rich(TextSpan(children: spans));
  }

  String _cleanWord(String word) {
    var w = word.toLowerCase().trim();
    if (w.endsWith("'s")) w = w.substring(0, w.length - 2);
    w = w.replaceAll(RegExp(r'^[^a-z]+|[^a-z]+$'), '');
    return w;
  }
}
