/// 预览工程里的更新设置。不依赖 shared_preferences，只放在内存里。
class FirmwareUpdatePrefs {
  static const _kBaseUrlKey = 'firmware_update_base_url';
  static const _kAutoCheckKey = 'firmware_update_auto_check';
  static const _kSkippedBuildKey = 'firmware_update_skipped_build';
  static const _kInstalledBuildKey = 'firmware_update_installed_build';
  static const _kInstalledVersionKey = 'firmware_update_installed_version';

  static final Map<String, Object> _mem = {
    _kInstalledVersionKey: 'preview',
    _kInstalledBuildKey: 1,
    _kAutoCheckKey: false,
  };

  static Future<String> getBaseUrl() async =>
      _mem[_kBaseUrlKey] as String? ?? '';

  static Future<void> setBaseUrl(String url) async {
    _mem[_kBaseUrlKey] = url.trim();
  }

  static Future<bool> getAutoCheck() async =>
      _mem[_kAutoCheckKey] as bool? ?? false;

  static Future<void> setAutoCheck(bool value) async {
    _mem[_kAutoCheckKey] = value;
  }

  static Future<int> getSkippedBuild() async =>
      _mem[_kSkippedBuildKey] as int? ?? 0;

  static Future<void> setSkippedBuild(int buildNumber) async {
    _mem[_kSkippedBuildKey] = buildNumber;
  }

  static Future<int> getInstalledBuild() async =>
      _mem[_kInstalledBuildKey] as int? ?? 1;

  static Future<void> setInstalledBuild(int buildNumber) async {
    _mem[_kInstalledBuildKey] = buildNumber;
  }

  static Future<String> getInstalledVersion() async =>
      _mem[_kInstalledVersionKey] as String? ?? 'preview';

  static Future<void> setInstalledVersion(String version) async {
    _mem[_kInstalledVersionKey] = version;
  }
}
