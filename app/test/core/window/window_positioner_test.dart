import 'package:flutter_test/flutter_test.dart';
import 'package:deckionary/core/window/window_positioner.dart';

void main() {
  group('ShowOnScreen.fromString', () {
    test('parses mouse', () {
      expect(ShowOnScreen.fromString('mouse'), ShowOnScreen.mouse);
    });

    test('parses activeWindow', () {
      expect(
        ShowOnScreen.fromString('activeWindow'),
        ShowOnScreen.activeWindow,
      );
    });

    test('parses primaryScreen', () {
      expect(
        ShowOnScreen.fromString('primaryScreen'),
        ShowOnScreen.primaryScreen,
      );
    });

    test('unknown value defaults to mouse', () {
      expect(ShowOnScreen.fromString('invalid'), ShowOnScreen.mouse);
      expect(ShowOnScreen.fromString(''), ShowOnScreen.mouse);
    });
  });

  group('computeWindowGeometry', () {
    test('standard 1920x1080 display at origin', () {
      final frame = DisplayFrame(x: 0, y: 0, width: 1920, height: 1080);
      final geom = computeWindowGeometry(frame);

      // Width always 800
      expect(geom.size.width, 800.0);
      // Height = 1080 * 0.7 = 756 (within 400-900 range)
      expect(geom.size.height, 756.0);
      // Centered X: (1920 - 800) / 2 = 560
      expect(geom.position.dx, 560.0);
      // Y: (1080 - 756) * 0.35 = 113.4
      expect(geom.position.dy, closeTo(113.4, 0.01));
    });

    test('tall display clamps height to 900', () {
      final frame = DisplayFrame(x: 0, y: 0, width: 1080, height: 2400);
      final geom = computeWindowGeometry(frame);

      // 2400 * 0.7 = 1680 -> clamped to 900
      expect(geom.size.height, 900.0);
      // Centered X: (1080 - 800) / 2 = 140
      expect(geom.position.dx, 140.0);
      // Y: (2400 - 900) * 0.35 = 525
      expect(geom.position.dy, 525.0);
    });

    test('small display clamps height to 400', () {
      final frame = DisplayFrame(x: 0, y: 0, width: 800, height: 500);
      final geom = computeWindowGeometry(frame);

      // 500 * 0.7 = 350 -> clamped to 400
      expect(geom.size.height, 400.0);
      // Centered X: (800 - 800) / 2 = 0
      expect(geom.position.dx, 0.0);
      // Y: (500 - 400) * 0.35 = 35
      expect(geom.position.dy, 35.0);
    });

    test('second monitor with X offset', () {
      final frame = DisplayFrame(x: 1920, y: 0, width: 1920, height: 1080);
      final geom = computeWindowGeometry(frame);

      // Centered X: 1920 + (1920 - 800) / 2 = 2480
      expect(geom.position.dx, 2480.0);
      expect(geom.size.width, 800.0);
    });

    test('display with menu bar Y offset', () {
      final frame = DisplayFrame(x: 0, y: 25, width: 1920, height: 1055);
      final geom = computeWindowGeometry(frame);

      // Height: 1055 * 0.7 = 738.5
      expect(geom.size.height, 738.5);
      // Y: 25 + (1055 - 738.5) * 0.35 = 25 + 110.775 = 135.775
      expect(geom.position.dy, closeTo(135.775, 0.01));
    });

    test('second monitor below primary (Y offset)', () {
      final frame = DisplayFrame(x: 0, y: 1080, width: 1920, height: 1080);
      final geom = computeWindowGeometry(frame);

      // Y: 1080 + (1080 - 756) * 0.35 = 1080 + 113.4 = 1193.4
      expect(geom.position.dy, closeTo(1193.4, 0.01));
    });
  });

  group('DisplayResolver', () {
    test('mouse mode calls getMouseDisplay only', () async {
      var mouseCalled = false;
      var activeWindowCalled = false;
      var primaryCalled = false;
      final expected = DisplayFrame(x: 0, y: 0, width: 1920, height: 1080);

      final resolver = DisplayResolver(
        getMouseDisplay: () async {
          mouseCalled = true;
          return expected;
        },
        getActiveWindowDisplay: () async {
          activeWindowCalled = true;
          return null;
        },
        getPrimaryDisplay: () async {
          primaryCalled = true;
          return null;
        },
      );

      final result = await resolver.resolve(ShowOnScreen.mouse);
      expect(result, same(expected));
      expect(mouseCalled, isTrue);
      expect(activeWindowCalled, isFalse);
      expect(primaryCalled, isFalse);
    });

    test('activeWindow mode calls getActiveWindowDisplay only', () async {
      var mouseCalled = false;
      var activeWindowCalled = false;
      var primaryCalled = false;
      final expected = DisplayFrame(x: 1920, y: 0, width: 1920, height: 1080);

      final resolver = DisplayResolver(
        getMouseDisplay: () async {
          mouseCalled = true;
          return null;
        },
        getActiveWindowDisplay: () async {
          activeWindowCalled = true;
          return expected;
        },
        getPrimaryDisplay: () async {
          primaryCalled = true;
          return null;
        },
      );

      final result = await resolver.resolve(ShowOnScreen.activeWindow);
      expect(result, same(expected));
      expect(mouseCalled, isFalse);
      expect(activeWindowCalled, isTrue);
      expect(primaryCalled, isFalse);
    });

    test('primaryScreen mode calls getPrimaryDisplay only', () async {
      var mouseCalled = false;
      var activeWindowCalled = false;
      var primaryCalled = false;
      final expected = DisplayFrame(x: 0, y: 0, width: 2560, height: 1440);

      final resolver = DisplayResolver(
        getMouseDisplay: () async {
          mouseCalled = true;
          return null;
        },
        getActiveWindowDisplay: () async {
          activeWindowCalled = true;
          return null;
        },
        getPrimaryDisplay: () async {
          primaryCalled = true;
          return expected;
        },
      );

      final result = await resolver.resolve(ShowOnScreen.primaryScreen);
      expect(result, same(expected));
      expect(mouseCalled, isFalse);
      expect(activeWindowCalled, isFalse);
      expect(primaryCalled, isTrue);
    });

    test('returns null when all callbacks return null', () async {
      final resolver = DisplayResolver(
        getMouseDisplay: () async => null,
        getActiveWindowDisplay: () async => null,
        getPrimaryDisplay: () async => null,
      );

      expect(await resolver.resolve(ShowOnScreen.mouse), isNull);
      expect(await resolver.resolve(ShowOnScreen.activeWindow), isNull);
      expect(await resolver.resolve(ShowOnScreen.primaryScreen), isNull);
    });

    test('falls back to mouse when activeWindow returns null', () async {
      final mouseDisplay =
          DisplayFrame(x: 0, y: 0, width: 1920, height: 1080);
      final resolver = DisplayResolver(
        getMouseDisplay: () async => mouseDisplay,
        getActiveWindowDisplay: () async => null,
        getPrimaryDisplay: () async => null,
      );

      final result = await resolver.resolve(ShowOnScreen.activeWindow);
      expect(result, same(mouseDisplay));
    });

    test('falls back to primary when activeWindow and mouse both null',
        () async {
      final primaryDisplay =
          DisplayFrame(x: 0, y: 0, width: 2560, height: 1440);
      final resolver = DisplayResolver(
        getMouseDisplay: () async => null,
        getActiveWindowDisplay: () async => null,
        getPrimaryDisplay: () async => primaryDisplay,
      );

      final result = await resolver.resolve(ShowOnScreen.activeWindow);
      expect(result, same(primaryDisplay));
    });

    test('falls back to mouse when primaryScreen returns null', () async {
      final mouseDisplay =
          DisplayFrame(x: 0, y: 0, width: 1920, height: 1080);
      final resolver = DisplayResolver(
        getMouseDisplay: () async => mouseDisplay,
        getActiveWindowDisplay: () async => null,
        getPrimaryDisplay: () async => null,
      );

      final result = await resolver.resolve(ShowOnScreen.primaryScreen);
      expect(result, same(mouseDisplay));
    });
  });

  group('end-to-end: resolve then compute', () {
    test('full flow produces valid geometry', () async {
      final display = DisplayFrame(x: 0, y: 0, width: 1920, height: 1080);
      final resolver = DisplayResolver(
        getMouseDisplay: () async => display,
        getActiveWindowDisplay: () async => display,
        getPrimaryDisplay: () async => display,
      );

      for (final mode in ShowOnScreen.values) {
        final frame = await resolver.resolve(mode);
        expect(frame, isNotNull);
        final geom = computeWindowGeometry(frame!);
        // Window fits within display bounds
        expect(geom.position.dx, greaterThanOrEqualTo(display.x));
        expect(geom.position.dy, greaterThanOrEqualTo(display.y));
        expect(
          geom.position.dx + geom.size.width,
          lessThanOrEqualTo(display.x + display.width),
        );
      }
    });
  });
}
