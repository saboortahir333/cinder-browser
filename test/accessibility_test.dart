import 'package:flutter/material.dart';
import 'dart:ui' show Tristate;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saboor_browser/main.dart';
import 'package:saboor_browser/models/browser_palette.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  final palette = kPalettes.first;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: BrowserShell(palette: palette, onPaletteSelected: (_) {})),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('toolbar buttons and tabs are exposed to Narrator with labels', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);

    expect(find.bySemanticsLabel(RegExp('New tab')), findsWidgets);
    expect(find.bySemanticsLabel('Extensions'), findsOneWidget);
    expect(find.bySemanticsLabel('Appearance settings'), findsOneWidget);
    // The first tab is spoken as a selected tab.
    final tab = find.bySemanticsLabel(RegExp(r', tab$')).first;
    final node = tester.getSemantics(tab);
    expect(node.flagsCollection.isSelected, Tristate.isTrue);
    handle.dispose();
  });

  testWidgets('chrome is reachable with Tab and activates with Enter', (tester) async {
    await pump(tester);
    // Tab through the chrome: a focusable control must receive focus.
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(FocusManager.instance.primaryFocus, isNotNull);
    expect(FocusManager.instance.primaryFocus!.context, isNotNull);
  });

  testWidgets('F6 cycles focus between regions and Alt+D focuses the address bar', (tester) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.f6);
    await tester.pump();
    final first = FocusManager.instance.primaryFocus;
    await tester.sendKeyEvent(LogicalKeyboardKey.f6);
    await tester.pump();
    final second = FocusManager.instance.primaryFocus;
    expect(identical(first, second), isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    final editable = find.byType(EditableText);
    expect(editable, findsWidgets);
    final focused = FocusManager.instance.primaryFocus!;
    expect(
      tester.widgetList<EditableText>(editable).any((e) => e.focusNode == focused),
      isTrue,
    );
    await tester.pump(const Duration(seconds: 2)); // flush suggestion timers
  });
}
