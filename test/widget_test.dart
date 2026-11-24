import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter_test/flutter_test.dart';
import 'package:saboor_browser/main.dart';
import 'package:saboor_browser/models/browser_palette.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  const palette = BrowserPalette(
    id: 'test',
    name: 'Test palette',
    subtitle: 'Test subtitle',
    tag: 'Test tag',
    accent: Color(0xFF2878D0),
    chrome: Color(0xFFF0F6FC),
    raised: Color(0xFFDDEAF6),
    soft: Color(0xFFC4D8EA),
    ink: Color(0xFF172B3C),
    muted: Color(0xFF586F82),
  );

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('browser shell shows its new-tab page', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: BrowserShell(palette: palette, onPaletteSelected: _ignorePalette),
      ),
    );
    await tester.pump();
    await tester.pump();

    // The start page greets by time of day, so accept any of the variants.
    const greetings = {'Good morning', 'Good afternoon', 'Good evening'};
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Text && greetings.contains(widget.data),
      ),
      findsOneWidget,
    );
    expect(find.text('Top sites'), findsOneWidget);
    expect(find.byTooltip('New tab'), findsOneWidget);
    expect(find.byTooltip('Appearance settings'), findsOneWidget);
  });

  testWidgets('new-tab button adds an independent tab', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: BrowserShell(palette: palette, onPaletteSelected: _ignorePalette),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('New tab'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('New tab'), findsNWidgets(2));
  });

  testWidgets('tab context menu can duplicate a tab', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: BrowserShell(palette: palette, onPaletteSelected: _ignorePalette),
      ),
    );
    await tester.pump();

    await tester.tap(
      find.text('New tab').first,
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(find.text('Duplicate tab'), findsOneWidget);
    await tester.tap(find.text('Duplicate tab'));
    await tester.pumpAndSettle();

    expect(find.text('New tab'), findsNWidgets(2));
  });

  testWidgets('new-tab shortcut context menu offers page actions', (
    tester,
  ) async {
    // The start page is taller than the default 800x600 test surface.
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: BrowserShell(palette: palette, onPaletteSelected: _ignorePalette),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Wikipedia'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    expect(find.text('Open in new tab'), findsOneWidget);
    expect(find.text('Add bookmark'), findsOneWidget);
  });

  testWidgets('home page background opens its context menu', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: BrowserShell(palette: palette, onPaletteSelected: _ignorePalette),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Top sites'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    expect(find.text('New tab'), findsWidgets);
    expect(find.text('Add shortcut'), findsOneWidget);
    await tester.tap(find.text('Add shortcut'));
    await tester.pumpAndSettle();
    expect(find.text('Add Shortcut'), findsOneWidget);
  });

  testWidgets('chrome never makes unverifiable TLS/PQC claims', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: BrowserShell(palette: palette, onPaletteSelected: _ignorePalette),
      ),
    );
    await tester.pump();

    expect(find.text('WebView2 TLS'), findsNothing);
    expect(find.text('Hybrid PQC'), findsNothing);
    expect(find.text('Standard TLS'), findsNothing);
  });
}

void _ignorePalette(BrowserPalette _) {}
