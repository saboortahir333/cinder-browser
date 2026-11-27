import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;

import 'package:saboor_browser/models/browser_palette.dart';
import 'package:saboor_browser/ui/chrome/chrome_widgets.dart'
    show A11yFocus, ChromeColors, glyphColorFor;

/// Height of a tab. The strip bottom-aligns tabs so the selected one sits
/// flush against the toolbar and appears to be part of it.
const double kTabHeight = 40;

/// Width of the concave "shoulder" that blends the selected tab into the
/// toolbar on both sides.
const double kTabFlare = 8;

/// One browser tab.
///
/// Design: the selected tab is cut from the toolbar's own surface (rounded top
/// corners, concave shoulders, a thin accent line on top), so it reads as the
/// open page. Inactive tabs are flat, with a soft hover pill and a hairline
/// separator. Selection never relies on colour alone: the selected tab is also
/// taller-looking (it connects to the toolbar), bolder and has the top line.
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
    this.separator = false,
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

  /// Draw a hairline on the right edge (hidden for selected/hovered tabs).
  final bool separator;
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
    final showClose = !widget.pinned && (selected || _hover);
    final accent = widget.groupColor ?? p.accent;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final fade = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 140);

    final titleColor = widget.sleeping
        ? p.muted.withValues(alpha: 0.7)
        : (selected ? p.ink : p.ink.withValues(alpha: 0.82));

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
      child: Align(
        alignment: Alignment.bottomCenter,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            onTertiaryTapUp: (_) => widget.onMiddleTap?.call(),
            onSecondaryTapDown: widget.onSecondaryTapDown,
            child: SizedBox(
              width: widget.width,
              height: kTabHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Hover pill for inactive tabs.
                  if (!selected)
                    Positioned.fill(
                      child: AnimatedContainer(
                        duration: fade,
                        curve: Curves.easeOutCubic,
                        margin: const EdgeInsets.fromLTRB(1, 5, 1, 7),
                        decoration: BoxDecoration(
                          color: _hover ? p.hover : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
                    ),

                  // Selected tab: cut from the toolbar surface.
                  Positioned(
                    left: -kTabFlare,
                    right: -kTabFlare,
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        duration: fade,
                        opacity: selected ? 1 : 0,
                        child: CustomPaint(
                          painter: _SelectedTabPainter(
                            fill: p.toolbar,
                            edge: p.divider.withValues(alpha: 0.9),
                            accent: accent,
                            flare: kTabFlare,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Hairline between inactive tabs.
                  if (widget.separator && !selected && !_hover)
                    Positioned(
                      right: 0,
                      top: 13,
                      height: 16,
                      width: 1,
                      child: ColoredBox(
                        color: p.divider.withValues(alpha: 0.55),
                      ),
                    ),

                  // Content.
                  Positioned.fill(
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: widget.pinned ? 0 : 11,
                        right: widget.pinned ? 0 : 5,
                        top: 2,
                      ),
                      child: Row(
                        mainAxisAlignment: widget.pinned
                            ? MainAxisAlignment.center
                            : MainAxisAlignment.start,
                        children: [
                          _leading(p, accent),
                          if (!widget.pinned) ...[
                            const SizedBox(width: 8),
                            if (widget.groupName != null &&
                                widget.groupName!.isNotEmpty &&
                                widget.width < 130)
                              // Too narrow for a label: a colour dot keeps
                              // the group visible without crowding the title.
                              Container(
                                width: 8,
                                height: 8,
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(
                                  color: widget.groupColor,
                                  shape: BoxShape.circle,
                                ),
                              )
                            else if (widget.groupName != null &&
                                widget.groupName!.isNotEmpty)
                              GestureDetector(
                                onTap: widget.onGroupTap,
                                child: Container(
                                  margin: const EdgeInsets.only(right: 6),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: widget.groupColor,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 64,
                                    ),
                                    child: Text(
                                      widget.groupName!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      softWrap: false,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        height: 1.2,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            Expanded(
                              child: AnimatedPadding(
                                duration: fade,
                                curve: Curves.easeOutCubic,
                                padding: EdgeInsets.only(
                                  right: showClose ? 24 : 2,
                                ),
                                child: Text(
                                  widget.title.isEmpty
                                      ? 'New tab'
                                      : widget.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.fade,
                                  softWrap: false,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    height: 1.2,
                                    letterSpacing: 0.05,
                                    fontWeight: selected
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    color: titleColor,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // Close button, fades in over the right edge.
                  if (!widget.pinned)
                    Positioned(
                      right: 7,
                      top: 0,
                      bottom: 2,
                      child: Center(
                        child: AnimatedOpacity(
                          duration: fade,
                          opacity: showClose ? 1 : 0,
                          child: AnimatedScale(
                            duration: fade,
                            scale: showClose ? 1 : 0.7,
                            child: IgnorePointer(
                              ignoring: !showClose,
                              child: _CloseButton(
                                palette: p,
                                onPressed: widget.onClose,
                              ),
                            ),
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

  Widget _leading(BrowserPalette p, Color accent) {
    final Widget glyph;
    if (widget.host.isEmpty) {
      glyph = const _FlameGlyph(size: 17);
    } else {
      glyph = _Favicon(host: widget.host, dim: widget.sleeping);
    }
    return SizedBox(
      width: 22,
      height: 22,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.loading)
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                strokeCap: StrokeCap.round,
                color: accent,
              ),
            ),
          glyph,
          if (widget.sleeping)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  color: p.toolbar,
                  shape: BoxShape.circle,
                  border: Border.all(color: p.divider, width: 0.8),
                ),
                child: Icon(Icons.bedtime_rounded, size: 7.5, color: p.muted),
              ),
            ),
        ],
      ),
    );
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
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: _hover ? p.pressed : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.close_rounded,
              size: 13,
              color: _hover ? p.ink : p.ink.withValues(alpha: 0.75),
            ),
          ),
        ),
      ),
    );
  }
}

/// Letter tile standing in for a favicon (Cinder never fetches favicons from a
/// third party), with a soft gradient and hairline so it looks finished.
class _Favicon extends StatelessWidget {
  const _Favicon({required this.host, this.dim = false});

  final String host;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final clean = host.replaceFirst(RegExp(r'^www\.'), '');
    final base = clean.isEmpty ? Colors.grey : glyphColorFor(clean);
    final hsl = HSLColor.fromColor(base);
    final light = hsl
        .withLightness((hsl.lightness + 0.1).clamp(0.0, 1.0))
        .toColor();
    final letter = clean.isEmpty ? '•' : clean.characters.first.toUpperCase();
    return Opacity(
      opacity: dim ? 0.5 : 1,
      child: Container(
        width: 16,
        height: 16,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [light, base],
          ),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.22),
            width: 0.6,
          ),
        ),
        child: Text(
          letter,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// The Cinder flame, used on blank tabs instead of a generic icon.
class _FlameGlyph extends StatelessWidget {
  const _FlameGlyph({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(size, size), painter: _FlamePainter());
}

class _FlamePainter extends CustomPainter {
  // Logo geometry (cinder-mark.svg, 800 x 800 canvas). The flame spans
  // x 240..560, y 210..600.
  static const double _w = 320;
  static const double _h = 390;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.height / _h;
    final dx = (size.width - _w * s) / 2;
    final m = Matrix4.identity()
      ..translateByDouble(dx, 0, 0, 1)
      ..scaleByDouble(s, s, 1, 1)
      ..translateByDouble(-240, -210, 0, 1);

    Path outer(bool left) {
      final k = left ? 1.0 : -1.0;
      double x(double v) => 400 + (v - 400) * k;
      return Path()
        ..moveTo(400, 210)
        ..cubicTo(x(300), 250, x(240), 350, x(260), 460)
        ..cubicTo(x(275), 540, x(335), 590, 400, 600)
        ..cubicTo(x(355), 540, x(340), 470, x(365), 410)
        ..cubicTo(x(380), 370, x(405), 340, 400, 210)
        ..close();
    }

    final inner = Path()
      ..moveTo(400, 270)
      ..cubicTo(345, 320, 320, 390, 340, 450)
      ..cubicTo(352, 490, 375, 520, 400, 535)
      ..cubicTo(425, 520, 448, 490, 460, 450)
      ..cubicTo(480, 390, 455, 320, 400, 270)
      ..close();

    final outerPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
        colors: [Color(0xFF8A1F0F), Color(0xFFD84315), Color(0xFFFF8A3D)],
        stops: [0, 0.45, 1],
      ).createShader(Rect.fromLTWH(240, 210, _w, _h));
    final innerPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
        colors: [Color(0xFFD84315), Color(0xFFFF8F3F), Color(0xFFFFD27A)],
        stops: [0, 0.55, 1],
      ).createShader(Rect.fromLTWH(320, 270, 140, 265));

    canvas.save();
    canvas.transform(m.storage);
    canvas.drawPath(outer(true), outerPaint);
    canvas.drawPath(outer(false), outerPaint);
    canvas.drawPath(inner, innerPaint);
    canvas.drawCircle(
      const Offset(400, 440),
      30,
      Paint()..color = const Color(0xFFFFE9B8),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// The selected tab: a shape with rounded top corners and concave shoulders at
/// the bottom corners, filled with the toolbar colour so it merges with it.
class _SelectedTabPainter extends CustomPainter {
  const _SelectedTabPainter({
    required this.fill,
    required this.edge,
    required this.accent,
    required this.flare,
  });

  final Color fill;
  final Color edge;
  final Color accent;
  final double flare;

  @override
  void paint(Canvas canvas, Size size) {
    const r = 10.0;
    final h = size.height;
    final x0 = flare;
    final x1 = size.width - flare;

    // Body including the concave shoulders, closed along the bottom.
    final body = Path()
      ..moveTo(0, h)
      ..quadraticBezierTo(x0, h, x0, h - flare)
      ..lineTo(x0, r)
      ..quadraticBezierTo(x0, 0, x0 + r, 0)
      ..lineTo(x1 - r, 0)
      ..quadraticBezierTo(x1, 0, x1, r)
      ..lineTo(x1, h - flare)
      ..quadraticBezierTo(x1, h, size.width, h)
      ..close();

    // Soft lift above the strip.
    canvas.drawShadow(body, Colors.black.withValues(alpha: 0.35), 2.5, false);
    canvas.drawPath(body, Paint()..color = fill);

    // Outline on the sides and top only: the bottom must stay open so the tab
    // flows into the toolbar.
    final outline = Path()
      ..moveTo(0, h)
      ..quadraticBezierTo(x0, h, x0, h - flare)
      ..lineTo(x0, r)
      ..quadraticBezierTo(x0, 0, x0 + r, 0)
      ..lineTo(x1 - r, 0)
      ..quadraticBezierTo(x1, 0, x1, r)
      ..lineTo(x1, h - flare)
      ..quadraticBezierTo(x1, h, size.width, h);
    canvas.drawPath(
      outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = edge,
    );

    // Cover the toolbar's top hairline under the tab so the join is seamless.
    canvas.drawRect(
      Rect.fromLTWH(x0 - 0.5, h - 1.5, x1 - x0 + 1, 2.5),
      Paint()..color = fill,
    );

    // Accent line on top.
    final lineRect = Rect.fromLTWH(x0 + r, 0, (x1 - x0) - 2 * r, 2.5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(lineRect, const Radius.circular(2)),
      Paint()
        ..shader = LinearGradient(
          colors: [accent, Color.lerp(accent, Colors.white, 0.35)!],
        ).createShader(lineRect),
    );
  }

  @override
  bool shouldRepaint(covariant _SelectedTabPainter old) =>
      old.fill != fill ||
      old.edge != edge ||
      old.accent != accent ||
      old.flare != flare;
}
