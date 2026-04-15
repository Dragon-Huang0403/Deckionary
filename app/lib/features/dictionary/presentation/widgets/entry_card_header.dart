import 'package:flutter/material.dart';

class CefrBadge extends StatelessWidget {
  final String level;
  const CefrBadge(this.level, {super.key});

  static const _colors = {
    'a1': Colors.green,
    'a2': Colors.lightGreen,
    'b1': Colors.orange,
    'b2': Colors.deepOrange,
    'c1': Colors.purple,
    'c2': Colors.deepPurple,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _colors[level] ?? Colors.grey,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        level.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class OxBadge extends StatelessWidget {
  final String label;
  final ColorScheme cs;
  const OxBadge(this.label, this.cs, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: cs.primary,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class EntryCardHeader extends StatelessWidget {
  final String headword;
  final String pos;
  final String cefrLevel;
  final bool ox3000;
  final bool ox5000;

  const EntryCardHeader({
    super.key,
    required this.headword,
    required this.pos,
    required this.cefrLevel,
    required this.ox3000,
    required this.ox5000,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        Text(
          headword,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: cs.primary,
          ),
        ),
        if (pos.isNotEmpty)
          Text(
            pos,
            style: TextStyle(
              fontSize: 14,
              fontStyle: FontStyle.italic,
              color: cs.onSurfaceVariant,
            ),
          ),
        if (cefrLevel.isNotEmpty) CefrBadge(cefrLevel),
        if (ox3000) OxBadge('Oxford 3000', cs),
        if (ox5000 && !ox3000) OxBadge('Oxford 5000', cs),
      ],
    );
  }
}
