
enum DownloadStatus { queued, downloading, paused, completed, failed, cancelled }

class DownloadItem {
  final String id;
  final String url;
  final String filename;
  final String mimeType;
  int totalBytes;
  int downloadedBytes;
  DownloadStatus status;
  String localPath;
  DateTime startedAt;
  DateTime? completedAt;
  String? errorMessage;
  bool isPqcVerified;

  double speedBytesPerSec = 0.0;
  DateTime _lastSpeedCalcTime = DateTime.now();
  int _lastSpeedCalcBytes = 0;

  DownloadItem({
    required this.id,
    required this.url,
    required this.filename,
    this.mimeType = '',
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    this.status = DownloadStatus.queued,
    this.localPath = '',
    DateTime? startedAt,
    this.completedAt,
    this.errorMessage,
    this.isPqcVerified = false,
  }) : startedAt = startedAt ?? DateTime.now();

  double get progress =>
      totalBytes > 0 ? (downloadedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;

  void updateSpeed(int currentBytes) {
    final now = DateTime.now();
    final elapsedSec = now.difference(_lastSpeedCalcTime).inMilliseconds / 1000.0;
    if (elapsedSec >= 0.4) {
      final deltaBytes = currentBytes - _lastSpeedCalcBytes;
      speedBytesPerSec = (deltaBytes / elapsedSec).clamp(0.0, double.infinity);
      _lastSpeedCalcTime = now;
      _lastSpeedCalcBytes = currentBytes;
    }
  }

  void resetSpeedTracking() {
    _lastSpeedCalcBytes = 0;
    _lastSpeedCalcTime = DateTime.now();
  }

  Map<String, dynamic> toSupabaseMap() {
    return {
      'id': id,
      'url': url,
      'filename': filename,
      'mime_type': mimeType,
      'total_bytes': totalBytes,
      'downloaded_bytes': downloadedBytes,
      'status': status.name,
      'local_path': localPath,
      'started_at': startedAt.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'error_message': errorMessage,
      'is_pqc_verified': isPqcVerified,
    };
  }

  factory DownloadItem.fromSupabaseMap(Map<String, dynamic> map) {
    return DownloadItem(
      id: map['id']?.toString() ?? '',
      url: map['url']?.toString() ?? '',
      filename: map['filename']?.toString() ?? 'download',
      mimeType: map['mime_type']?.toString() ?? '',
      totalBytes: (map['total_bytes'] as num?)?.toInt() ?? 0,
      downloadedBytes: (map['downloaded_bytes'] as num?)?.toInt() ?? 0,
      status: DownloadStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => DownloadStatus.queued,
      ),
      localPath: map['local_path']?.toString() ?? '',
      startedAt: map['started_at'] != null
          ? DateTime.tryParse(map['started_at'].toString())
          : null,
      completedAt: map['completed_at'] != null
          ? DateTime.tryParse(map['completed_at'].toString())
          : null,
      errorMessage: map['error_message']?.toString(),
      isPqcVerified: map['is_pqc_verified'] == true,
    );
  }
}
