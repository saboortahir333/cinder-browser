import 'package:flutter/material.dart';

class BrowserPalette {
  const BrowserPalette({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.tag,
    required this.accent,
    required this.chrome,
    required this.raised,
    required this.soft,
    required this.ink,
    required this.muted,
  });

  final String id;
  final String name;
  final String subtitle;
  final String tag;
  final Color accent;
  final Color chrome;
  final Color raised;
  final Color soft;
  final Color ink;
  final Color muted;

  /// True for dark themes (decided by the toolbar colour's luminance).
  bool get isDark => chrome.computeLuminance() < 0.35;
}


const List<BrowserPalette> kPalettes = <BrowserPalette>[
  // Firefox-inspired neutrals first: these are the defaults.
  BrowserPalette(
    id: 'cinder',
    name: 'Cinder Light',
    subtitle: 'Clean neutral light theme with a crisp blue accent.',
    tag: '☀️ Default',
    accent: Color(0xFF0060DF),
    chrome: Color(0xFFF9F9FB),
    raised: Color(0xFFE9E9EE),
    soft: Color(0xFFCFCFD8),
    ink: Color(0xFF15141A),
    muted: Color(0xFF5B5B66),
  ),
  BrowserPalette(
    id: 'cinder-dark',
    name: 'Cinder Dark',
    subtitle: 'Easy on the eyes: deep graphite with a bright cyan accent.',
    tag: '🌙 Dark',
    accent: Color(0xFF00B3F4),
    chrome: Color(0xFF2B2A33),
    raised: Color(0xFF1C1B22),
    soft: Color(0xFF52525E),
    ink: Color(0xFFFBFBFE),
    muted: Color(0xFFA8A8B3),
  ),
  BrowserPalette(
    id: 'ember',
    name: 'Ember',
    subtitle: 'Cinder’s signature: warm charcoal lit by an ember glow.',
    tag: '🔥 Signature',
    accent: Color(0xFFFF7A3D),
    chrome: Color(0xFF241B17),
    raised: Color(0xFF17120F),
    soft: Color(0xFF45342B),
    ink: Color(0xFFFFF4EC),
    muted: Color(0xFFB8A194),
  ),
  BrowserPalette(
    id: 'midnight',
    name: 'Midnight',
    subtitle: 'Deep navy for long night sessions.',
    tag: '🌌 Dark',
    accent: Color(0xFF7C9BFF),
    chrome: Color(0xFF151C30),
    raised: Color(0xFF0D1220),
    soft: Color(0xFF2E3855),
    ink: Color(0xFFEAF0FF),
    muted: Color(0xFF93A0C4),
  ),
  BrowserPalette(
    id: 'sky',
    name: 'Clear Sky',
    subtitle: 'Fresh azure tones for clean, high-clarity browsing.',
    tag: '⚡ 60 Hz Clear',
    accent: Color(0xFF2878D0),
    chrome: Color(0xFFF0F6FC),
    raised: Color(0xFFDDEAF6),
    soft: Color(0xFFC4D8EA),
    ink: Color(0xFF172B3C),
    muted: Color(0xFF4A5F70),
  ),
  BrowserPalette(
    id: 'coral',
    name: 'Coral Coast',
    subtitle: 'Warm terracotta & peach hues for evening focus.',
    tag: '🌅 Alpha 12 Hz',
    accent: Color(0xFFD94F45),
    chrome: Color(0xFFFFF4EF),
    raised: Color(0xFFF8DFD6),
    soft: Color(0xFFEBC8BE),
    ink: Color(0xFF39231F),
    muted: Color(0xFF795851),
  ),
  BrowserPalette(
    id: 'citrus',
    name: 'Citrus Grove',
    subtitle: 'Vibrant botanical greens inspired by fresh nature.',
    tag: '🍃 Beta 14 Hz',
    accent: Color(0xFF658D23),
    chrome: Color(0xFFF5F8EB),
    raised: Color(0xFFE4EDCF),
    soft: Color(0xFFCFDDB1),
    ink: Color(0xFF26331A),
    muted: Color(0xFF55613F),
  ),
  BrowserPalette(
    id: 'orchid',
    name: 'Orchid Hour',
    subtitle: 'Deep lavender palette for immersive night reading.',
    tag: '🌙 Theta 6 Hz',
    accent: Color(0xFF8053B5),
    chrome: Color(0xFFF8F3FC),
    raised: Color(0xFFEADDF4),
    soft: Color(0xFFD9C5E9),
    ink: Color(0xFF30243D),
    muted: Color(0xFF6F5B7D),
  ),
  BrowserPalette(
    id: 'sunrise',
    name: 'Apricot Sunrise',
    subtitle: 'Soft amber gradients for warm visual comfort.',
    tag: '☀️ Gamma 32 Hz',
    accent: Color(0xFFCE762D),
    chrome: Color(0xFFFFF7E9),
    raised: Color(0xFFF6E5C8),
    soft: Color(0xFFE8D0A8),
    ink: Color(0xFF392A19),
    muted: Color(0xFF77654C),
  ),
  BrowserPalette(
    id: 'lagoon',
    name: 'Blue Lagoon',
    subtitle: 'Deep oceanic cyan palette for tranquil research.',
    tag: '🌊 Deep Focus',
    accent: Color(0xFF168D91),
    chrome: Color(0xFFECF8F7),
    raised: Color(0xFFD1ECE9),
    soft: Color(0xFFB7DDDA),
    ink: Color(0xFF163333),
    muted: Color(0xFF3C5E5D),
  ),
  kHighContrastDarkPalette,
  kHighContrastLightPalette,
];

/// Used for every private window, regardless of the saved theme (like the
/// purple private theme in other major browsers).
const BrowserPalette kPrivatePalette = BrowserPalette(
  id: 'private',
  name: 'Private',
  subtitle: 'Private browsing theme.',
  tag: '🕶 Private',
  accent: Color(0xFFB67BFF),
  chrome: Color(0xFF2B1B4D),
  raised: Color(0xFF1B0E36),
  soft: Color(0xFF4A3478),
  ink: Color(0xFFF6F0FF),
  muted: Color(0xFFB9A8DA),
);

/// Windows "High contrast black"-style theme: pure black surfaces, white text
/// and a bright accent, with strong borders. Chosen automatically when the OS
/// high-contrast mode is on.
const BrowserPalette kHighContrastDarkPalette = BrowserPalette(
  id: 'high-contrast',
  name: 'High contrast (dark)',
  subtitle: 'Maximum contrast: black surfaces, white text, bright accents.',
  tag: '◐ Accessibility',
  accent: Color(0xFF1AEBFF),
  chrome: Color(0xFF000000),
  raised: Color(0xFF101010),
  soft: Color(0xFFFFFFFF),
  ink: Color(0xFFFFFFFF),
  muted: Color(0xFFE6E6E6),
);

/// Windows "High contrast white"-style theme.
const BrowserPalette kHighContrastLightPalette = BrowserPalette(
  id: 'high-contrast-light',
  name: 'High contrast (light)',
  subtitle: 'Maximum contrast: white surfaces, black text, deep accents.',
  tag: '◑ Accessibility',
  accent: Color(0xFF37006E),
  chrome: Color(0xFFFFFFFF),
  raised: Color(0xFFEFEFEF),
  soft: Color(0xFF000000),
  ink: Color(0xFF000000),
  muted: Color(0xFF1A1A1A),
);

/// Picks the theme for the current accessibility state.
BrowserPalette effectivePalette(
  BrowserPalette chosen, {
  required bool isPrivate,
  required bool highContrast,
  required Brightness platformBrightness,
}) {
  if (highContrast) {
    return platformBrightness == Brightness.light
        ? kHighContrastLightPalette
        : kHighContrastDarkPalette;
  }
  return isPrivate ? kPrivatePalette : chosen;
}

/// WCAG 2.x contrast ratio between two opaque colours.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
