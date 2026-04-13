import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../dictionary/presentation/widgets/dictionary_search_bar.dart';
import '../../../dictionary/presentation/widgets/entry_card.dart';
import '../../../dictionary/presentation/widgets/entry_options_list.dart';
import 'lookup_sheet_controller.dart';

class LookupSheet extends ConsumerStatefulWidget {
  final LookupSheetController controller;
  final bool autofocusSearch;

  const LookupSheet({
    super.key,
    required this.controller,
    this.autofocusSearch = false,
  });

  @override
  ConsumerState<LookupSheet> createState() => _LookupSheetState();
}

class _LookupSheetState extends ConsumerState<LookupSheet> {
  late final TextEditingController _textController;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.controller.query);
    widget.controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (!mounted) return;
    // Keep text field in sync when controller changes query (e.g. word tap, goBack)
    if (_textController.text != widget.controller.query) {
      _textController.text = widget.controller.query;
      _textController.selection = TextSelection.fromPosition(
        TextPosition(offset: widget.controller.query.length),
      );
    }
    // Handle dismiss signal
    if (widget.controller.shouldDismiss) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !ctrl.canGoBack(),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ctrl.goBack();
      },
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 8),
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Search bar
          DictionarySearchBar(
            controller: _textController,
            focusNode: _focusNode,
            onChanged: ctrl.search,
            onSubmitted: ctrl.commitSearch,
            canGoBack: ctrl.canGoBack(),
            onBack: ctrl.goBack,
            onClear: () {
              _textController.clear();
              ctrl.clear();
              _focusNode.requestFocus();
            },
            isOverlay: true,
            autofocus: widget.autofocusSearch,
          ),
          // Content
          Expanded(child: _buildContent(ctrl, cs)),
        ],
      ),
    );
  }

  Widget _buildContent(LookupSheetController ctrl, ColorScheme cs) {
    if (ctrl.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (ctrl.selectedEntry != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
        child: EntryCard(
          entry: ctrl.selectedEntry!,
          onWordTap: (word) => ctrl.commitSearch(word),
        ),
      );
    }

    if (ctrl.results.isNotEmpty) {
      return EntryOptionsList(
        results: ctrl.results,
        highlightedIndex: -1,
        onSelect: ctrl.selectEntry,
      );
    }

    if (ctrl.query.isNotEmpty) {
      return Center(
        child: Text(
          'No results for "${ctrl.query}"',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }

    return Center(
      child: Text(
        'Search for a word',
        style: TextStyle(color: cs.onSurfaceVariant),
      ),
    );
  }
}
