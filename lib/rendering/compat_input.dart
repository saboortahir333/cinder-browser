import 'package:flutter/services.dart';

/// CDP modifier bit mask: Alt=1, Ctrl=2, Meta=4, Shift=8.
int cdpModifiers({
  required bool alt,
  required bool ctrl,
  required bool meta,
  required bool shift,
}) => (alt ? 1 : 0) | (ctrl ? 2 : 0) | (meta ? 4 : 0) | (shift ? 8 : 0);

/// Current modifier state from the hardware keyboard.
int currentCdpModifiers() {
  final kb = HardwareKeyboard.instance;
  return cdpModifiers(
    alt: kb.isAltPressed,
    ctrl: kb.isControlPressed,
    meta: kb.isMetaPressed,
    shift: kb.isShiftPressed,
  );
}

/// The pressed button for a Flutter `buttons` bit field, as CDP names it.
/// Flutter and CDP use the same bit order (primary/secondary/middle/back/
/// forward = 1/2/4/8/16), so the mask itself needs no translation.
String cdpButtonName(int buttons) {
  if (buttons & 1 != 0) return 'left';
  if (buttons & 4 != 0) return 'middle';
  if (buttons & 2 != 0) return 'right';
  if (buttons & 8 != 0) return 'back';
  if (buttons & 16 != 0) return 'forward';
  return 'none';
}

/// What to do with one keyboard event.
sealed class KeyForward {
  const KeyForward();
}

/// Send these `Input.dispatchKeyEvent` parameter maps, in order.
class KeySend extends KeyForward {
  const KeySend(this.events);
  final List<Map<String, dynamic>> events;
}

/// Paste: the caller reads the clipboard and inserts the text.
class KeyPaste extends KeyForward {
  const KeyPaste();
}

/// Not for the page (an app shortcut, a bare modifier key, ...).
class KeyIgnore extends KeyForward {
  const KeyIgnore();
}

const Map<String, String> _editCommands = {
  'a': 'selectAll',
  'c': 'copy',
  'x': 'cut',
  'z': 'undo',
  'y': 'redo',
};

final Map<LogicalKeyboardKey, (String, int)> _specialKeys = {
  LogicalKeyboardKey.backspace: ('Backspace', 8),
  LogicalKeyboardKey.tab: ('Tab', 9),
  LogicalKeyboardKey.enter: ('Enter', 13),
  LogicalKeyboardKey.numpadEnter: ('Enter', 13),
  LogicalKeyboardKey.escape: ('Escape', 27),
  LogicalKeyboardKey.space: (' ', 32),
  LogicalKeyboardKey.pageUp: ('PageUp', 33),
  LogicalKeyboardKey.pageDown: ('PageDown', 34),
  LogicalKeyboardKey.end: ('End', 35),
  LogicalKeyboardKey.home: ('Home', 36),
  LogicalKeyboardKey.arrowLeft: ('ArrowLeft', 37),
  LogicalKeyboardKey.arrowUp: ('ArrowUp', 38),
  LogicalKeyboardKey.arrowRight: ('ArrowRight', 39),
  LogicalKeyboardKey.arrowDown: ('ArrowDown', 40),
  LogicalKeyboardKey.insert: ('Insert', 45),
  LogicalKeyboardKey.delete: ('Delete', 46),
  LogicalKeyboardKey.f1: ('F1', 112),
  LogicalKeyboardKey.f2: ('F2', 113),
  LogicalKeyboardKey.f3: ('F3', 114),
  LogicalKeyboardKey.f4: ('F4', 115),
  LogicalKeyboardKey.f6: ('F6', 117),
  LogicalKeyboardKey.f7: ('F7', 118),
  LogicalKeyboardKey.f8: ('F8', 119),
  LogicalKeyboardKey.f9: ('F9', 120),
  LogicalKeyboardKey.f10: ('F10', 121),
};

/// Keys the browser chrome owns; never sent to the page.
final Set<LogicalKeyboardKey> _appKeys = {
  LogicalKeyboardKey.f5,
  LogicalKeyboardKey.f11,
  LogicalKeyboardKey.f12,
};

final Set<LogicalKeyboardKey> _modifierKeys = {
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
  LogicalKeyboardKey.capsLock,
  LogicalKeyboardKey.numLock,
  LogicalKeyboardKey.scrollLock,
};

const Map<String, int> _punctuationVk = {
  ';': 186,
  ':': 186,
  '=': 187,
  '+': 187,
  ',': 188,
  '<': 188,
  '-': 189,
  '_': 189,
  '.': 190,
  '>': 190,
  '/': 191,
  '?': 191,
  '`': 192,
  '~': 192,
  '[': 219,
  '{': 219,
  '\\': 220,
  '|': 220,
  ']': 221,
  '}': 221,
  "'": 222,
  '"': 222,
};

/// Windows virtual-key code for a key whose label is [label] (0 if unknown).
int virtualKeyFor(LogicalKeyboardKey key, String label) {
  final special = _specialKeys[key];
  if (special != null) return special.$2;
  if (label.length == 1) {
    final c = label.toUpperCase().codeUnitAt(0);
    if ((c >= 0x41 && c <= 0x5a) || (c >= 0x30 && c <= 0x39)) return c;
    return _punctuationVk[label] ?? 0;
  }
  return 0;
}

bool _printable(String? s) {
  if (s == null || s.isEmpty) return false;
  final c = s.codeUnitAt(0);
  return c >= 0x20 && c != 0x7f;
}

/// Translates a Flutter key event into what should be sent to the page.
KeyForward forwardKey(KeyEvent event, {required int modifiers}) {
  final key = event.logicalKey;
  if (_modifierKeys.contains(key) || _appKeys.contains(key)) {
    return const KeyIgnore();
  }

  final isUp = event is KeyUpEvent;
  final hasCtrlOrMeta = modifiers & 6 != 0;
  final label = key.keyLabel.toLowerCase();

  if (hasCtrlOrMeta) {
    // Only the editing shortcuts belong to the page; everything else
    // (Ctrl+T, Ctrl+L, Ctrl+W, ...) is the browser's own.
    if (label == 'v') return isUp ? const KeyIgnore() : const KeyPaste();
    final command = _editCommands[label];
    if (command == null || isUp) return const KeyIgnore();
    return KeySend([
      {
        'type': 'rawKeyDown',
        'modifiers': modifiers,
        'windowsVirtualKeyCode': virtualKeyFor(key, label),
        'key': label,
        'code': _codeOf(event),
        'commands': [command],
      },
    ]);
  }

  final special = _specialKeys[key];
  final character = event.character;
  final keyName = special?.$1 ?? (_printable(character) ? character! : label);
  final vk = virtualKeyFor(key, special == null ? label : '');

  final base = <String, dynamic>{
    'modifiers': modifiers,
    'key': keyName,
    'code': _codeOf(event),
    'windowsVirtualKeyCode': vk,
    'nativeVirtualKeyCode': vk,
  };

  if (isUp) {
    return KeySend([
      {...base, 'type': 'keyUp'},
    ]);
  }

  final repeat = event is KeyRepeatEvent;
  // Enter must carry '\r' for forms and textareas to react.
  final text =
      key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter
      ? '\r'
      : (_printable(character) ? character : null);

  return KeySend([
    {
      ...base,
      'type': text != null ? 'keyDown' : 'rawKeyDown',
      'text': ?text,
      'unmodifiedText': ?text,
      if (repeat) 'autoRepeat': true,
    },
  ]);
}

String _codeOf(KeyEvent e) =>
    (e.physicalKey.debugName ?? '').replaceAll(' ', '');
