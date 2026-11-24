import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:saboor_browser/models/browser_palette.dart';
import 'package:saboor_browser/ui/chrome/chrome_widgets.dart';

/// The Cinder logo mark (falls back to a flame icon if the asset is missing).
class CinderMark extends StatelessWidget {
  const CinderMark({super.key, this.size = 56});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/newtab/cinder-mark.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) => Icon(
        Icons.local_fire_department_rounded,
        size: size,
        color: const Color(0xFFFF7A3D),
      ),
    );
  }
}

/// Frosted container used for start-page surfaces so text stays legible on
/// any wallpaper.
class FrostedSurface extends StatelessWidget {
  const FrostedSurface({
    super.key,
    required this.child,
    this.radius = 16,
    this.padding = EdgeInsets.zero,
    this.tint = const Color(0x22FFFFFF),
    this.borderColor = const Color(0x33FFFFFF),
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Color tint;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: tint,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: borderColor),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// The big search field on the new-tab page.
class HomeSearchBar extends StatelessWidget {
  const HomeSearchBar({
    super.key,
    required this.palette,
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.onSubmitted,
    this.engineName,
  });

  final BrowserPalette palette;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final ValueChanged<String> onSubmitted;
  final String? engineName;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: focusNode,
      builder: (context, _) {
        final focused = focusNode.hasFocus;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 54,
          padding: const EdgeInsets.only(left: 20, right: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: focused ? 0.96 : 0.88),
            borderRadius: BorderRadius.circular(27),
            border: Border.all(
              color: focused ? palette.accent : Colors.transparent,
              width: 2,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x40000000),
                blurRadius: 28,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(
                Icons.search_rounded,
                color: Color(0xFF5B5B66),
                size: 24,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  textInputAction: TextInputAction.go,
                  autocorrect: false,
                  enableSuggestions: false,
                  cursorColor: palette.accent,
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: const TextStyle(
                      color: Color(0xFF6E6E7A),
                      fontSize: 16,
                    ),
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isDense: true,
                  ),
                  style: const TextStyle(
                    color: Color(0xFF15141A),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  onSubmitted: onSubmitted,
                ),
              ),
              if (engineName != null)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Text(
                    engineName!,
                    style: const TextStyle(
                      color: Color(0xFF6E6E7A),
                      fontSize: 12,
                    ),
                  ),
                ),
              Material(
                color: palette.accent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => onSubmitted(controller.text),
                  child: const Tooltip(
                    message: 'Search',
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A "top site" shortcut tile.
class SiteTile extends StatefulWidget {
  const SiteTile({
    super.key,
    required this.label,
    required this.host,
    required this.onTap,
    required this.onSecondaryTapDown,
  });

  final String label;
  final String host;
  final VoidCallback onTap;
  final ValueChanged<TapDownDetails> onSecondaryTapDown;

  @override
  State<SiteTile> createState() => _SiteTileState();
}

class _SiteTileState extends State<SiteTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return A11yFocus(
      label: '${widget.label}, top site',
      focusColor: Colors.white,
      radius: 18,
      onActivate: widget.onTap,
      child: Tooltip(
        message: 'Open ${widget.label}',
        waitDuration: const Duration(milliseconds: 600),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            onSecondaryTapDown: widget.onSecondaryTapDown,
            child: SizedBox(
              width: 100,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 130),
                    curve: Curves.easeOutCubic,
                    transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: _hover ? 1 : 0.92),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: _hover ? 0.38 : 0.26,
                          ),
                          blurRadius: _hover ? 22 : 14,
                          offset: Offset(0, _hover ? 10 : 6),
                        ),
                      ],
                    ),
                    child: Center(
                      child: SiteGlyph(host: widget.host, size: 38),
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      shadows: [
                        Shadow(color: Color(0x99000000), blurRadius: 8),
                      ],
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

/// A "jump back in" card for a recently visited page.
class JumpBackCard extends StatefulWidget {
  const JumpBackCard({
    super.key,
    required this.title,
    required this.host,
    required this.onTap,
    required this.onSecondaryTapDown,
  });

  final String title;
  final String host;
  final VoidCallback onTap;
  final ValueChanged<TapDownDetails> onSecondaryTapDown;

  @override
  State<JumpBackCard> createState() => _JumpBackCardState();
}

class _JumpBackCardState extends State<JumpBackCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return A11yFocus(
      label:
          '${widget.title}, ${widget.host.replaceFirst(RegExp(r'^www\.'), '')}, recent page',
      focusColor: Colors.white,
      radius: 14,
      onActivate: widget.onTap,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onSecondaryTapDown: widget.onSecondaryTapDown,
          child: FrostedSurface(
            radius: 14,
            tint: Colors.white.withValues(alpha: _hover ? 0.26 : 0.16),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                SiteGlyph(host: widget.host, size: 30, radius: 9),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.host.replaceFirst(RegExp(r'^www\.'), ''),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 11.5,
                        ),
                      ),
                    ],
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

/// Heading for the private-browsing start page.
class PrivateHero extends StatelessWidget {
  const PrivateHero({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF9B59FF), Color(0xFF5B2BD6)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF9B59FF).withValues(alpha: 0.5),
                blurRadius: 36,
              ),
            ],
          ),
          child: const Icon(
            Icons.visibility_off_rounded,
            color: Colors.white,
            size: 40,
          ),
        ),
        const SizedBox(height: 22),
        const Text(
          'You’re in a Private window',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(
            'Cinder won’t keep your browsing history, searches, cookies, site '
            'data or open tabs from this window once you close it. Files you '
            'download stay on your computer.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 14.5,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(
            'Private browsing doesn’t hide your activity from websites, your '
            'employer, school or internet provider.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 12.5,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}
