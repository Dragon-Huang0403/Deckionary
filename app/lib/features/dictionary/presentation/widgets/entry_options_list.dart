import 'package:flutter/material.dart';
import '../../providers/search_provider.dart';
import 'entry_card_header.dart';

class EntryOptionsList extends StatefulWidget {
  final List<SearchResult> results;
  final int highlightedIndex;
  final void Function(int index, DictEntry entry) onSelect;

  const EntryOptionsList({
    super.key,
    required this.results,
    required this.highlightedIndex,
    required this.onSelect,
  });

  @override
  State<EntryOptionsList> createState() => _EntryOptionsListState();
}

class _EntryOptionsListState extends State<EntryOptionsList> {
  final _scrollController = ScrollController();
  static const _estimatedItemHeight = 80.0;

  @override
  void didUpdateWidget(EntryOptionsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.highlightedIndex != oldWidget.highlightedIndex) {
      _scrollToHighlighted();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToHighlighted() {
    if (!_scrollController.hasClients) return;
    final targetTop = widget.highlightedIndex * _estimatedItemHeight;
    final targetBottom = targetTop + _estimatedItemHeight;
    final viewport = _scrollController.position;
    if (targetTop < viewport.pixels) {
      _scrollController.animateTo(
        targetTop,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    } else if (targetBottom > viewport.pixels + viewport.viewportDimension) {
      _scrollController.animateTo(
        targetBottom - viewport.viewportDimension,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: widget.results.length,
      itemBuilder: (context, index) {
        final r = widget.results[index];
        final e = r.entry;
        final isFts = r.source != SearchMatchSource.headword;
        final isHighlighted = index == widget.highlightedIndex;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          color: isHighlighted ? cs.primaryContainer : null,
          child: ListTile(
            title: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              children: [
                Text(
                  e.headword,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: isHighlighted ? cs.onPrimaryContainer : null,
                  ),
                ),
                if (e.cefrLevel.isNotEmpty) CefrBadge(e.cefrLevel),
                if (e.ox3000) OxBadge('3K', cs),
                if (e.ox5000 && !e.ox3000) OxBadge('5K', cs),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (e.pos.isNotEmpty)
                  Text(
                    e.pos,
                    style: TextStyle(
                      color: isHighlighted ? cs.onPrimaryContainer : cs.primary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                if (isFts && r.snippet.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: r.source == SearchMatchSource.definition
                              ? cs.primaryContainer
                              : cs.tertiaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          r.source == SearchMatchSource.definition
                              ? 'def'
                              : 'ex',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: r.source == SearchMatchSource.definition
                                ? cs.onPrimaryContainer
                                : cs.onTertiaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          r.snippet,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: isHighlighted
                                ? cs.onPrimaryContainer
                                : cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            trailing: Icon(
              Icons.chevron_right,
              color: cs.onSurfaceVariant,
              size: 20,
            ),
            onTap: () => widget.onSelect(index, e),
          ),
        );
      },
    );
  }
}
