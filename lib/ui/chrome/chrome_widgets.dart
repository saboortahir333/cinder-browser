import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';

import 'package:saboor_browser/models/browser_palette.dart';

/// Colour roles for the browser chrome, derived from a [BrowserPalette] so
/// every theme (light, dark, private) gets a coherent Firefox-style layering:
///
///   frame (tab strip)  <  toolbar  <  selected tab  /  address field
extension ChromeColors on BrowserPalette {
  /// Tab strip background (the darkest layer).
  Color get frame => raised;

  /// Toolbar background.
  Color get toolbar => chrome;

  /// Selected-tab surface: lifted above the strip.
  Color get tabSelected => isDark
      ? Color.lerp(chrome, Colors.white, 0.04)!
      : Color.lerp(chrome, Colors.white, 0.75)!;

  /// Address-field resting colour.
  Color get field =>
      Color.alphaBlend(ink.withValues(alpha: isDark ? 0.10 : 0.06), chrome);

  Color get hover => ink.withValues(alpha: isDark ? 0.12 : 0.08);
  Color get pressed => ink.withValues(alpha: isDark ? 0.20 : 0.14);
  Color get divider => soft;
  Color get shadow => Colors.black.withValues(alpha: isDark ? 0.45 : 0.14);
}

/// Deterministic colour for a site glyph (no network favicon needed).
Color glyphColorFor(String host) {
  var h = 0;
  for (final c in host.codeUnits) {
    h = (h * 31 + c) & 0x7FFFFFFF;
  }
  const hues = [
    210.0,
    262.0,
    330.0,
    8.0,
    28.0,
    150.0,
    180.0,
    48.0,
    290.0,
    120.0,
  ];
  return HSLColor.fromAHSL(1, hues[h % hues.length], 0.62, 0.46).toColor();
}

/// Letter tile standing in for a favicon. Fetching favicons from a third
/// party would tell that party every site you open, so Cinder never does.
class SiteGlyph extends StatelessWidget {
  const SiteGlyph({super.key, required this.host, this.size = 16, this.radius});

  final String host;
  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final clean = host.replaceFirst(RegExp(r'^www\.'), '');
    final letter = clean.isEmpty ? '•' : clean.characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: clean.isEmpty ? Colors.grey : glyphColorFor(clean),
        borderRadius: BorderRadius.circular(radius ?? size * 0.28),
      ),
      child: Text(
        letter,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.58,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}

/// Square toolbar button with a Firefox-like hover/pressed background.
class ToolbarButton extends StatefulWidget {
  const ToolbarButton({
    super.key,
    required this.palette,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 34,
    this.iconSize = 19,
    this.badge,
    this.active = false,
    this.iconWidget,
    this.semanticLabel,
  });

  final BrowserPalette palette;
  final IconData icon;

  /// Replaces [icon] (e.g. an extension's own image).
  final Widget? iconWidget;

  /// Spoken label; defaults to [tooltip].
  final String? semanticLabel;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;

  /// Small count/dot shown on the corner (e.g. active downloads).
  final String? badge;

  /// Draws the button as "on" (e.g. bookmarked star, open panel).
  final bool active;

  @override
  State<ToolbarButton> createState() => _ToolbarButtonState();
}

class _ToolbarButtonState extends State<ToolbarButton> {
  bool _hover = false;
  bool _down = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final enabled = widget.onPressed != null;
    final bg = !enabled
        ? Colors.transparent
        : _down
        ? p.pressed
        : (_hover || widget.active)
        ? p.hover
        : Colors.transparent;
    final fg = enabled ? p.ink : p.ink.withValues(alpha: 0.35);
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel ?? widget.tooltip,
      value: widget.badge,
      toggled: widget.active ? true : null,
      excludeSemantics: true,
      onTap: widget.onPressed,
      child: Tooltip(
        message: widget.tooltip,
        waitDuration: const Duration(milliseconds: 500),
        child: FocusableActionDetector(
          enabled: enabled,
          mouseCursor: enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onShowFocusHighlight: (v) => setState(() => _focus = v),
          onShowHoverHighlight: (v) => setState(() => _hover = v),
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onPressed?.call();
                return null;
              },
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: enabled ? (_) => setState(() => _down = true) : null,
            onTapUp: enabled ? (_) => setState(() => _down = false) : null,
            onTapCancel: () => setState(() => _down = false),
            onTap: widget.onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 90),
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(6),
                border: _focus ? Border.all(color: p.accent, width: 2) : null,
              ),
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  widget.iconWidget ??
                      Icon(
                        widget.icon,
                        size: widget.iconSize,
                        color: widget.active ? p.accent : fg,
                      ),
                  if (widget.badge != null)
                    Positioned(
                      right: 2,
                      top: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: p.accent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          widget.badge!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Makes any custom-drawn control usable without a mouse and by Narrator:
/// it takes keyboard focus (Tab / arrows), activates on Enter or Space, shows
/// a clear focus ring, and exposes one spoken label with optional actions.
class A11yFocus extends StatefulWidget {
  const A11yFocus({
    super.key,
    required this.child,
    required this.label,
    required this.onActivate,
    required this.focusColor,
    this.hint,
    this.selected,
    this.radius = 8,
    this.onDelete,
    this.customActions = const {},
    this.focusNode,
  });

  final Widget child;
  final String label;
  final String? hint;
  final bool? selected;
  final VoidCallback onActivate;
  final Color focusColor;
  final double radius;

  /// Pressing Delete (e.g. close a tab).
  final VoidCallback? onDelete;

  /// Extra Narrator actions (shown in its actions menu).
  final Map<CustomSemanticsAction, VoidCallback> customActions;
  final FocusNode? focusNode;

  @override
  State<A11yFocus> createState() => _A11yFocusState();
}

class _A11yFocusState extends State<A11yFocus> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      selected: widget.selected,
      label: widget.label,
      hint: widget.hint,
      onTap: widget.onActivate,
      customSemanticsActions: widget.customActions,
      excludeSemantics: true,
      child: FocusableActionDetector(
        focusNode: widget.focusNode,
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        shortcuts: {
          const SingleActivator(LogicalKeyboardKey.enter):
              const ActivateIntent(),
          const SingleActivator(LogicalKeyboardKey.space):
              const ActivateIntent(),
          if (widget.onDelete != null)
            const SingleActivator(LogicalKeyboardKey.delete):
                const _DeleteIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onActivate();
              return null;
            },
          ),
          _DeleteIntent: CallbackAction<_DeleteIntent>(
            onInvoke: (_) {
              widget.onDelete?.call();
              return null;
            },
          ),
        },
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            border: _focused
                ? Border.all(color: widget.focusColor, width: 2)
                : null,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class _DeleteIntent extends Intent {
  const _DeleteIntent();
}

/// One browser tab in the strip.
class TabChip extends StatefulWidget {
  const TabChip({
    super.key,
    required this.palette,
    required this.width,
    required this.title,
    required this.host,
    required this.selected,
    required this.onTap,
    required this.onClose,
    this.pinned = false,
    this.loading = false,
    this.sleeping = false,
    this.groupColor,
    this.groupName,
    this.onGroupTap,
    this.onSecondaryTapDown,
    this.onMiddleTap,
  });

  final BrowserPalette palette;
  final double width;
  final String title;
  final String host;
  final bool selected;
  final bool pinned;
  final bool loading;
  final bool sleeping;
  final Color? groupColor;
  final String? groupName;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final VoidCallback? onGroupTap;
  final ValueChanged<TapDownDetails>? onSecondaryTapDown;
  final VoidCallback? onMiddleTap;

  @override
  State<TabChip> createState() => _TabChipState();
}

class _TabChipState extends State<TabChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final selected = widget.selected;
    final bg = selected
        ? p.tabSelected
        : (_hover ? p.hover : Colors.transparent);
    final showClose = !widget.pinned && (selected || _hover);
    final titleColor = widget.sleeping
        ? p.muted.withValues(alpha: 0.65)
        : (selected ? p.ink : p.ink.withValues(alpha: 0.78));

    final spoken = [
      widget.title.isEmpty ? 'New tab' : widget.title,
      if (widget.pinned) 'pinned',
      if (widget.loading) 'loading',
      if (widget.sleeping) 'sleeping',
      if (widget.groupName != null && widget.groupName!.isNotEmpty)
        'group ${widget.groupName}',
    ].join(', ');
    return A11yFocus(
      label: '$spoken, tab',
      hint: widget.selected ? null : 'Press Enter to switch to this tab',
      selected: widget.selected,
      focusColor: p.accent,
      onActivate: widget.onTap,
      onDelete: widget.pinned ? null : widget.onClose,
      customActions: {
        if (!widget.pinned)
          const CustomSemanticsAction(label: 'Close tab'): widget.onClose,
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onTertiaryTapUp: (_) => widget.onMiddleTap?.call(),
          onSecondaryTapDown: widget.onSecondaryTapDown,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            width: widget.width,
            height: 34,
            margin: const EdgeInsets.symmetric(vertical: 5),
            padding: EdgeInsets.only(
              left: widget.pinned ? 0 : 10,
              right: widget.pinned ? 0 : 4,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: p.shadow,
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            foregroundDecoration: widget.groupColor == null
                ? null
                : _UnderlineDecoration(widget.groupColor!),
            child: Row(
              mainAxisAlignment: widget.pinned
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                _leading(p),
                if (!widget.pinned) ...[
                  const SizedBox(width: 8),
                  if (widget.groupName != null && widget.groupName!.isNotEmpty)
                    GestureDetector(
                      onTap: widget.onGroupTap,
                      child: Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: widget.groupColor,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          widget.groupName!,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: titleColor,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 100),
                      opacity: showClose ? 1 : 0,
                      child: IgnorePointer(
                        ignoring: !showClose,
                        child: _CloseButton(
                          palette: p,
                          onPressed: widget.onClose,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _leading(BrowserPalette p) {
    if (widget.loading) {
      return SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 1.8, color: p.accent),
      );
    }
    if (widget.sleeping) {
      return Icon(Icons.bedtime_outlined, size: 15, color: p.muted);
    }
    if (widget.host.isEmpty) {
      return Icon(Icons.add_box_outlined, size: 15, color: p.muted);
    }
    return SiteGlyph(host: widget.host, size: 16);
  }
}

class _CloseButton extends StatefulWidget {
  const _CloseButton({required this.palette, required this.onPressed});

  final BrowserPalette palette;
  final VoidCallback onPressed;

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Tooltip(
        message: 'Close tab',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: Container(
            decoration: BoxDecoration(
              color: _hover ? p.pressed : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(Icons.close_rounded, size: 14, color: p.ink),
          ),
        ),
      ),
    );
  }
}

/// A thin coloured line under a grouped tab.
class _UnderlineDecoration extends Decoration {
  const _UnderlineDecoration(this.color);

  final Color color;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _UnderlinePainter(color);
}

class _UnderlinePainter extends BoxPainter {
  _UnderlinePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          offset.dx + 8,
          offset.dy + size.height - 3,
          size.width - 16,
          3,
        ),
        const Radius.circular(2),
      ),
      Paint()..color = color,
    );
  }
}

/// The address-bar shell: a rounded field that gains an accent ring on focus.
class UrlBarFrame extends StatelessWidget {
  const UrlBarFrame({
    super.key,
    required this.palette,
    required this.focused,
    required this.child,
    this.height = 36,
  });

  final BrowserPalette palette;
  final bool focused;
  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      height: height,
      decoration: BoxDecoration(
        color: focused ? p.toolbar : p.field,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: focused ? p.accent : Colors.transparent,
          width: 2,
        ),
        boxShadow: focused
            ? [
                BoxShadow(
                  color: p.shadow,
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}

/// Slim bookmark chip used on the bookmarks toolbar.
class BookmarkChip extends StatefulWidget {
  const BookmarkChip({
    super.key,
    required this.palette,
    required this.title,
    required this.host,
    required this.onTap,
    this.onSecondaryTapDown,
  });

  final BrowserPalette palette;
  final String title;
  final String host;
  final VoidCallback onTap;
  final ValueChanged<TapDownDetails>? onSecondaryTapDown;

  @override
  State<BookmarkChip> createState() => _BookmarkChipState();
}

class _BookmarkChipState extends State<BookmarkChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return A11yFocus(
      label: '${widget.title}, bookmark',
      focusColor: p.accent,
      radius: 6,
      onActivate: widget.onTap,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onSecondaryTapDown: widget.onSecondaryTapDown,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            constraints: const BoxConstraints(maxWidth: 170),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _hover ? p.hover : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SiteGlyph(host: widget.host, size: 14),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.ink, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
