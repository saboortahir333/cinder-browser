import 'dart:io';

/// What to do with one network request.
sealed class RequestDecision {
  const RequestDecision();
}

class AllowRequest extends RequestDecision {
  const AllowRequest();
}

/// Cancel the request (trackers, ads).
class BlockRequest extends RequestDecision {
  const BlockRequest(this.reason);
  final String reason;
}

/// Re-issue the page load over HTTPS.
class UpgradeRequest extends RequestDecision {
  const UpgradeRequest(this.httpsUrl);
  final String httpsUrl;
}

/// Replace a page load with a warning page.
class WarnRequest extends RequestDecision {
  const WarnRequest(this.kind, this.host);
  final String kind; // 'malware'
  final String host;
}

typedef AdMatcher = bool Function(String url, String sourceUrl, String type);

/// Pure decision logic (no I/O) so it can be unit tested and fuzzed.
class RequestPolicy {
  RequestPolicy({
    this.httpsOnly = true,
    this.blockTrackers = true,
    this.blockMalware = true,
    AdMatcher? matcher,
    Set<String>? malwareHosts,
  })  : _matcher = matcher,
        malwareHosts = malwareHosts ?? <String>{};

  bool httpsOnly;
  bool blockTrackers;
  bool blockMalware;
  AdMatcher? _matcher;
  Set<String> malwareHosts;

  /// Sites where the user turned shields off.
  final Set<String> shieldsOff = {};

  /// Hosts the user chose to open over plain HTTP (this run only).
  final Set<String> insecureOk = {};

  /// Hosts we upgraded recently, so a failed load can offer a fallback.
  final Set<String> upgraded = {};

  set matcher(AdMatcher? m) => _matcher = m;

  static bool isLocalHost(String host) {
    final h = host.toLowerCase();
    if (h == 'localhost' || h.endsWith('.localhost') || h.endsWith('.local') || h.endsWith('.test')) {
      return true;
    }
    final ip = InternetAddress.tryParse(h);
    if (ip == null) return !h.contains('.'); // single-label intranet names
    return ip.isLoopback || ip.isLinkLocal || _isPrivate(ip);
  }

  static bool _isPrivate(InternetAddress ip) {
    final b = ip.rawAddress;
    if (ip.type == InternetAddressType.IPv4) {
      return b[0] == 10 ||
          (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
          (b[0] == 192 && b[1] == 168);
    }
    return b.isNotEmpty && (b[0] & 0xFE) == 0xFC; // fc00::/7
  }

  /// Hosts the browser itself serves: never filtered.
  static bool _isInternal(String host) => host.endsWith('.cinder.local');

  RequestDecision decide({
    required String url,
    required String documentUrl,
    required String resourceType,
  }) {
    final u = Uri.tryParse(url);
    if (u == null || u.host.isEmpty) return const AllowRequest();
    final scheme = u.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return const AllowRequest();
    final host = u.host.toLowerCase();
    if (_isInternal(host)) return const AllowRequest();
    final isDoc = resourceType.toLowerCase() == 'document';
    final docHost = Uri.tryParse(documentUrl)?.host.toLowerCase() ?? '';
    final shieldsDown = shieldsOff.contains(isDoc ? host : docHost);

    if (isDoc && blockMalware && !shieldsDown && _isMalware(host)) {
      return WarnRequest('malware', host);
    }

    if (isDoc &&
        httpsOnly &&
        scheme == 'http' &&
        !isLocalHost(host) &&
        !insecureOk.contains(host)) {
      upgraded.add(host);
      final https = u.replace(scheme: 'https', port: u.hasPort && u.port != 80 ? u.port : null);
      return UpgradeRequest(https.toString());
    }

    // Only sub-resources are blocked: the page the user asked for always
    // loads, which keeps sign-in flows and ordinary sites working.
    if (!isDoc && blockTrackers && !shieldsDown && !isLocalHost(host)) {
      final m = _matcher;
      if (m != null && m(url, documentUrl, resourceType)) {
        return const BlockRequest('tracker');
      }
    }
    return const AllowRequest();
  }

  bool _isMalware(String host) {
    var h = host;
    // Match the host and its parent domains (a.b.evil.com -> b.evil.com).
    while (true) {
      if (malwareHosts.contains(h)) return true;
      final i = h.indexOf('.');
      if (i < 0 || h.indexOf('.', i + 1) < 0) return false;
      h = h.substring(i + 1);
    }
  }
}
