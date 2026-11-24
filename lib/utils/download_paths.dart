import 'dart:io';

/// Path helpers for the download manager.
///
/// These live outside the UI layer so the naming rules can be unit tested
/// without building a widget tree.

/// Characters Windows rejects in a file name, plus the ASCII control range.
final RegExp _illegalNameCharacters = RegExp(r'[<>:"/\\|?*\x00-\x1F]');

/// Windows also rejects names that end with a dot or a space.
final RegExp _trailingDotsOrSpaces = RegExp(r'[. ]+$');

/// Derives the file name a download should be saved as, based on its [url].
///
/// The last path segment is used, percent-decoded, with characters Windows
/// forbids in file names replaced by underscores. Addresses without a usable
/// final segment (directories, bare hosts, dot-only segments) fall back to a
/// timestamped `download_<milliseconds>` name.
String downloadFilenameFromUrl(String url) {
  var candidate = '';
  try {
    final uri = Uri.tryParse(url);
    if (uri != null && !uri.path.endsWith('/') && uri.pathSegments.isNotEmpty) {
      // [Uri.pathSegments] is already percent-decoded.
      candidate = uri.pathSegments.last;
    }
  } on FormatException {
    // Malformed percent-escapes fall through to the timestamped name.
  }

  candidate = candidate
      .replaceAll(_illegalNameCharacters, '_')
      .replaceAll(_trailingDotsOrSpaces, '')
      .trim();

  if (candidate.isEmpty) {
    return 'download_${DateTime.now().millisecondsSinceEpoch}';
  }
  return candidate;
}

/// Returns [fileName] unchanged, or with a ` (1)`, ` (2)`, … counter inserted
/// before its extension when [folder] already holds that name.
///
/// This covers the overwrite confirmation that a save dialog would normally
/// provide: a queued download must never silently destroy an existing file.
String uniqueDownloadFilename(String folder, String fileName) {
  final separator = Platform.pathSeparator;
  final extension = _extensionOf(fileName);
  final stem = fileName.substring(0, fileName.length - extension.length);

  var candidate = fileName;
  for (var attempt = 1;
      attempt <= 999 && File('$folder$separator$candidate').existsSync();
      attempt++) {
    candidate = '$stem ($attempt)$extension';
  }
  return candidate;
}

/// Returns the `.ext` suffix of [fileName], or `''` when it has none. A leading
/// dot marks a hidden file rather than an extension.
String _extensionOf(String fileName) {
  final dot = fileName.lastIndexOf('.');
  return dot <= 0 ? '' : fileName.substring(dot);
}
