import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../core/database/database_provider.dart';
import '../../../dictionary/domain/search_service.dart';
import '../../../dictionary/providers/search_provider.dart';

class LookupSheetController extends ChangeNotifier {
  final DictionaryDatabase db;

  String query = '';
  List<SearchResult> results = [];
  int? selectedEntryIndex;
  DictEntry? selectedEntry;
  bool isLoading = false;
  bool shouldDismiss = false;

  final List<String> _history = [];
  Timer? _debounce;

  LookupSheetController(this.db);

  /// Debounced search — call from onChanged.
  void search(String text) {
    query = text;
    selectedEntryIndex = null;
    selectedEntry = null;
    notifyListeners();

    _debounce?.cancel();
    if (text.isEmpty) {
      results = [];
      notifyListeners();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _runSearch(text);
    });
  }

  /// Immediate search — call from word tap or onSubmitted.
  void commitSearch(String word) {
    // Push current query to history if non-empty and different
    if (query.isNotEmpty && query != word) {
      _history.add(query);
      if (_history.length > 50) _history.removeAt(0);
    }
    query = word;
    selectedEntryIndex = null;
    selectedEntry = null;
    notifyListeners();
    _debounce?.cancel();
    _runSearch(word);
  }

  Future<void> _runSearch(String text) async {
    isLoading = true;
    notifyListeners();

    final searchResults = await searchEntries(db, text);
    // Guard: query may have changed while awaiting
    if (query != text) return;

    results = searchResults;
    isLoading = false;

    // Auto-select if single result
    if (results.length == 1) {
      selectedEntryIndex = 0;
      selectedEntry = results.first.entry;
    }
    notifyListeners();
  }

  /// Select an entry from the results list.
  void selectEntry(int index, DictEntry entry) {
    selectedEntryIndex = index;
    selectedEntry = entry;
    notifyListeners();
  }

  bool canGoBack() {
    // Can go back if viewing an entry (return to list) or history has items
    return selectedEntryIndex != null || _history.isNotEmpty;
  }

  void goBack() {
    // If viewing a selected entry with multiple results, go back to list
    if (selectedEntryIndex != null && results.length > 1) {
      selectedEntryIndex = null;
      selectedEntry = null;
      notifyListeners();
      return;
    }

    // If history has items, pop and search
    if (_history.isNotEmpty) {
      final prev = _history.removeLast();
      query = prev;
      selectedEntryIndex = null;
      selectedEntry = null;
      notifyListeners();
      _debounce?.cancel();
      _runSearch(prev);
      return;
    }

    // Nothing to go back to — signal dismiss
    shouldDismiss = true;
    notifyListeners();
  }

  void clear() {
    _debounce?.cancel();
    query = '';
    results = [];
    selectedEntryIndex = null;
    selectedEntry = null;
    isLoading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
