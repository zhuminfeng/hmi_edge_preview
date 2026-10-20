import 'firmware_update_prefs.dart';

class FirmwareUpdateInfo {
  final String version;
  final int buildNumber;
  final String url;
  final String sha256;
  final String releaseNotes;
  final bool mandatory;

  const FirmwareUpdateInfo({
    required this.version,
    required this.buildNumber,
    required this.url,
    required this.sha256,
    required this.releaseNotes,
    required this.mandatory,
  });

  factory FirmwareUpdateInfo.fromJson(Map<String, dynamic> json) {
    return FirmwareUpdateInfo(
      version: (json['version'] as String?) ?? '0.0.0',
      buildNumber: (json['buildNumber'] as num?)?.toInt() ?? 0,
      url: (json['url'] as String?) ?? '',
      sha256: (json['sha256'] as String?)?.toLowerCase() ?? '',
      releaseNotes: (json['releaseNotes'] as String?) ?? '',
      mandatory: (json['mandatory'] as bool?) ?? false,
    );
  }
}

enum FirmwareUpdateStage {
  idle,
  checking,
  downloading,
  verifying,
  applying,
  done,
  error,
}

class FirmwareUpdateProgress {
  final FirmwareUpdateStage stage;
  final double progress;
  final String? message;

  const FirmwareUpdateProgress(this.stage, {this.progress = 0, this.message});
}

class InstalledVersion {
  final int buildNumber;
  final String version;
  const InstalledVersion(this.buildNumber, this.version);

  @override
  String toString() => 'InstalledVersion(build=$buildNumber, version=$version)';
}

/// Web 预览不下载、不部署固件。接口保留，避免设置页编译失败。
class FirmwareUpdateService {
  FirmwareUpdateService({required this.baseUrl});

  final String baseUrl;

  Future<FirmwareUpdateInfo> fetchLatest() async {
    return const FirmwareUpdateInfo(
      version: 'preview',
      buildNumber: 1,
      url: '',
      sha256: '',
      releaseNotes: '浏览器预览不连接更新服务器。',
      mandatory: false,
    );
  }

  Future<InstalledVersion> readInstalled() async {
    return InstalledVersion(
      await FirmwareUpdatePrefs.getInstalledBuild(),
      await FirmwareUpdatePrefs.getInstalledVersion(),
    );
  }

  Future<bool> isNewer(FirmwareUpdateInfo info) async => false;

  Future<String> downloadAndVerify(
    FirmwareUpdateInfo info, {
    void Function(double progress)? onProgress,
  }) async {
    throw UnsupportedError('浏览器预览不能下载固件包');
  }

  Future<void> applyUpdate(String archivePath, FirmwareUpdateInfo info) async {
    throw UnsupportedError('浏览器预览不能部署固件');
  }

  void dispose() {}
}
