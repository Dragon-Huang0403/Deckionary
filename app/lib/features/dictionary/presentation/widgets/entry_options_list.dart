import 'package:flutter/material.dart';
import '../../providers/search_provider.dart';

class EntryOptionsList extends StatelessWidget {
  final List<DictEntry> entries;
  final void Function(int index, DictEntry entry) onSelect;

  const EntryOptionsList({
    super.key,
    required this.entries,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final e = entries[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text(
              e.headword,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            subtitle: e.pos.isNotEmpty
                ? Text(
                    e.pos,
                    style: TextStyle(
                      color: cs.primary,
                      fontStyle: FontStyle.italic,
                    ),
                  )
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (e.cefrLevel.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      e.cefrLevel.toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ),
                if (e.ox3000) ...[
                  const SizedBox(width: 6),
                  Text(
                    '3K',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: cs.tertiary,
                    ),
                  ),
                ],
                if (e.ox5000 && !e.ox3000) ...[
                  const SizedBox(width: 6),
                  Text(
                    '5K',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: cs.tertiary,
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, color: cs.onSurfaceVariant, size: 20),
              ],
            ),
            onTap: () => onSelect(index, e),
          ),
        );
      },
    );
  }
}
