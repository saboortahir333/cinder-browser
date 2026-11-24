import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saboor_browser/models/browser_palette.dart';

void main() {
  final all = [...kPalettes, kPrivatePalette];
  for (final p in all) {
    test('${p.id}: text and accents meet WCAG AA', () {
      expect(contrastRatio(p.ink, p.chrome), greaterThanOrEqualTo(7), reason: 'body text on toolbar');
      expect(contrastRatio(p.ink, p.raised), greaterThanOrEqualTo(4.5), reason: 'text on tab strip');
      expect(contrastRatio(p.muted, p.chrome), greaterThanOrEqualTo(4.5), reason: 'secondary text');
      expect(contrastRatio(p.muted, p.raised), greaterThanOrEqualTo(4.5), reason: 'secondary text on strip');
      expect(contrastRatio(p.accent, p.chrome), greaterThanOrEqualTo(3), reason: 'focus ring / accent vs surface');
    });
  }

  test('high contrast mode overrides theme and private theme', () {
    expect(
      effectivePalette(kPalettes.first, isPrivate: true, highContrast: true, platformBrightness: Brightness.dark).id,
      'high-contrast',
    );
    expect(
      effectivePalette(kPalettes.first, isPrivate: false, highContrast: true, platformBrightness: Brightness.light).id,
      'high-contrast-light',
    );
    expect(
      effectivePalette(kPalettes.first, isPrivate: true, highContrast: false, platformBrightness: Brightness.light).id,
      'private',
    );
  });
}
