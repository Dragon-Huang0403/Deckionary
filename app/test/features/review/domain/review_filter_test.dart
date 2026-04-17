import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:deckionary/features/review/domain/review_filter.dart';

void main() {
  group('ReviewFilter', () {
    group('isEmpty', () {
      test('default filter is empty', () {
        expect(const ReviewFilter().isEmpty, true);
      });

      test('filter with CEFR level is not empty', () {
        expect(const ReviewFilter(cefrLevels: {'a1'}).isEmpty, false);
      });

      test('filter with ox3000 is not empty', () {
        expect(const ReviewFilter(ox3000: true).isEmpty, false);
      });

      test('filter with ox5000 is not empty', () {
        expect(const ReviewFilter(ox5000: true).isEmpty, false);
      });
    });

    group('JSON round-trip', () {
      test('empty filter survives round-trip', () {
        final filter = const ReviewFilter();
        final restored = ReviewFilter.fromJson(filter.toJson());
        expect(restored.isEmpty, true);
        expect(restored.cefrLevels, isEmpty);
        expect(restored.ox3000, false);
        expect(restored.ox5000, false);
      });

      test('full filter survives round-trip', () {
        final filter = const ReviewFilter(
          cefrLevels: {'a1', 'b2', 'c1'},
          ox3000: true,
          ox5000: true,
        );
        final restored = ReviewFilter.fromJson(filter.toJson());
        expect(restored.cefrLevels, {'a1', 'b2', 'c1'});
        expect(restored.ox3000, true);
        expect(restored.ox5000, true);
      });

      test('fromJson handles missing cefr key gracefully', () {
        final json = jsonEncode({'ox3000': true, 'ox5000': false});
        final filter = ReviewFilter.fromJson(json);
        expect(filter.cefrLevels, isEmpty);
        expect(filter.ox3000, true);
      });

      test('fromJson handles missing boolean keys gracefully', () {
        final json = jsonEncode({
          'cefr': ['a1'],
        });
        final filter = ReviewFilter.fromJson(json);
        expect(filter.cefrLevels, {'a1'});
        expect(filter.ox3000, false);
        expect(filter.ox5000, false);
      });
    });

    group('copyWith', () {
      test('overrides specified fields only', () {
        const original = ReviewFilter(
          cefrLevels: {'a1'},
          ox3000: true,
          ox5000: false,
        );
        final copied = original.copyWith(ox5000: true);
        expect(copied.cefrLevels, {'a1'});
        expect(copied.ox3000, true);
        expect(copied.ox5000, true);
      });

      test('no args returns equivalent filter', () {
        const original = ReviewFilter(cefrLevels: {'b1'}, ox3000: true);
        final copied = original.copyWith();
        expect(copied.cefrLevels, {'b1'});
        expect(copied.ox3000, true);
        expect(copied.ox5000, false);
      });
    });
  });
}
