import 'dart:convert';

/// Messages that web content may send to the browser chrome.
///
/// Everything a page posts through `window.chrome.webview.postMessage` is
/// attacker-controlled, so the chrome side accepts exactly one message type,
/// from exactly the pages it injected into, with strict shapes and sizes.
/// Add a new type here (and to the tests) before using it anywhere.
class PageContextMessage {
  const PageContextMessage({
    required this.x,
    required this.y,
    required this.link,
    required this.image,
    required this.selection,
    required this.editable,
  });

  final double x;
  final double y;
  final String link;
  final String image;
  final String selection;
  final bool editable;
}

class PageMessages {
  PageMessages._();

  static const int maxRawLength = 16 * 1024;
  static const int maxUrl = 4096;
  static const int maxSelection = 500;

  /// Only ordinary web pages carry our injected scripts. The browser's own
  /// pages (about:, extension origins, devtools) never get a context channel.
  static bool isTrustedSender(String tabUrl) {
    final u = Uri.tryParse(tabUrl);
    if (u == null) return false;
    if (u.scheme != 'http' && u.scheme != 'https') return false;
    return u.host.isNotEmpty && !u.host.endsWith('.cinder.local');
  }

  /// Returns null for anything that is not a well-formed context-menu message.
  static PageContextMessage? parseContext(dynamic raw, {required String senderUrl}) {
    if (!isTrustedSender(senderUrl)) return null;
    dynamic message = raw;
    if (message is String) {
      if (message.length > maxRawLength) return null;
      try {
        message = jsonDecode(message);
      } catch (_) {
        return null;
      }
    }
    if (message is! Map) return null;
    if (message['cinderContext'] != true) return null;
    final x = message['x'];
    final y = message['y'];
    if (x is! num || y is! num || !x.isFinite || !y.isFinite) return null;
    String text(Object? v, int max) {
      if (v is! String) return '';
      return v.length > max ? v.substring(0, max) : v;
    }

    return PageContextMessage(
      x: x.toDouble(),
      y: y.toDouble(),
      link: _webUrlOrEmpty(text(message['link'], maxUrl)),
      image: _webUrlOrEmpty(text(message['image'], maxUrl)),
      selection: text(message['selection'], maxSelection),
      editable: message['editable'] == true,
    );
  }

  /// Links and images from a page may only be http(s) or data images; a page
  /// cannot smuggle javascript:, file: or custom schemes into a menu action.
  static String _webUrlOrEmpty(String s) {
    if (s.isEmpty) return '';
    final u = Uri.tryParse(s);
    if (u == null) return '';
    if (u.scheme == 'http' || u.scheme == 'https') return s;
    return '';
  }
}
