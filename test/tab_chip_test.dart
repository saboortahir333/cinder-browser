import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saboor_browser/models/browser_palette.dart';
import 'package:saboor_browser/ui/chrome/tab_chip.dart';

Widget _host(Widget tab, {double width = 190}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(width: width, height: 46, child: tab),
    ),
  ),
);

TabChip _chip({
  bool selected = false,
  bool pinned = false,
  bool loading = false,
  bool sleeping = false,
  String title = 'Example page',
  String host = 'example.com',
  String? groupName,
  VoidCallback? onTap,
  VoidCallback? onClose,
  double width = 190,
}) => TabChip(
  palette: kPalettes.first,
  width: width,
  title: title,
  host: host,
  selected: selected,
  pinned: pinned,
  loading: loading,
  sleeping: sleeping,
  groupName: groupName,
  groupColor: groupName == null ? null : Colors.blue,
  onTap: onTap ?? () {},
  onClose: onClose ?? () {},
);

void main() {
  testWidgets('tapping the tab selects it', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(_chip(onTap: () => taps++)));
    await tester.tap(find.text('Example page'));
    expect(taps, 1);
  });

  testWidgets('the selected tab shows a working close button', (tester) async {
    var closed = 0;
    await tester.pumpWidget(
      _host(_chip(selected: true, onClose: () => closed++)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close tab'));
    expect(closed, 1);
  });

  testWidgets('an inactive tab shows its close button only on hover', (
    tester,
  ) async {
    var closed = 0;
    await tester.pumpWidget(_host(_chip(onClose: () => closed++)));
    await tester.pumpAndSettle();

    // Not hovered: the (invisible) button must not react.
    await tester.tap(find.byTooltip('Close tab'), warnIfMissed: false);
    expect(closed, 0);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Example page')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close tab'));
    expect(closed, 1);
  });

  testWidgets('a pinned tab is compact: no title and no close button', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_chip(pinned: true, width: 42), width: 42));
    await tester.pumpAndSettle();
    expect(find.text('Example page'), findsNothing);
    expect(find.byTooltip('Close tab'), findsNothing);
  });

  testWidgets('a blank tab is titled "New tab"', (tester) async {
    await tester.pumpWidget(_host(_chip(title: '', host: '')));
    expect(find.text('New tab'), findsOneWidget);
  });

  testWidgets('a group label is shown on the tab', (tester) async {
    await tester.pumpWidget(_host(_chip(groupName: 'Work')));
    expect(find.text('Work'), findsOneWidget);
  });

  testWidgets('state is announced to screen readers', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(_chip(selected: true, loading: true, sleeping: true)),
    );
    expect(
      find.bySemanticsLabel(RegExp('Example page.*loading.*sleeping.*tab')),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('narrow and wide tabs never overflow', (tester) async {
    // 88 px is the strip's minimum width for a normal tab; pinned tabs are 42.
    for (final w in [88.0, 96.0, 140.0, 240.0]) {
      await tester.pumpWidget(
        _host(
          _chip(
            selected: true,
            loading: true,
            sleeping: true,
            groupName: 'Quarterly planning',
            title: 'A very long page title that has to be cut off cleanly',
            width: w,
          ),
          width: w,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'width $w');
    }
  });

  testWidgets('animations are skipped when the system disables them', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: _host(_chip(selected: true)),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
