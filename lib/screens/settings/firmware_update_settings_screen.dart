import 'package:flutter/material.dart';

import '../../services/firmware_update_prefs.dart';
import '../../widgets/firmware_update_checker.dart';

/// 固件/应用版本更新设置页：配置更新服务器地址、是否自动检查、手动检查更新。
class FirmwareUpdateSettingsScreen extends StatefulWidget {
  const FirmwareUpdateSettingsScreen({super.key});

  @override
  State<FirmwareUpdateSettingsScreen> createState() =>
      _FirmwareUpdateSettingsScreenState();
}

class _FirmwareUpdateSettingsScreenState
    extends State<FirmwareUpdateSettingsScreen> {
  final _urlController = TextEditingController();
  bool _autoCheck = true;
  bool _loading = true;
  bool _checking = false;
  String _currentVersion = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final url = await FirmwareUpdatePrefs.getBaseUrl();
    final autoCheck = await FirmwareUpdatePrefs.getAutoCheck();
    if (!mounted) return;
    setState(() {
      _urlController.text = url;
      _autoCheck = autoCheck;
      _currentVersion = 'preview (build 1)';
      _loading = false;
    });
  }

  Future<void> _saveUrl() async {
    await FirmwareUpdatePrefs.setBaseUrl(_urlController.text);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已保存')));
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('版本更新')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(title: const Text('当前版本'), subtitle: Text(_currentVersion)),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: '更新服务器地址',
                hintText: '例如 https://update.example.com',
                border: OutlineInputBorder(),
              ),
              onEditingComplete: _saveUrl,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: _saveUrl, child: const Text('保存地址')),
          ),
          SwitchListTile(
            title: const Text('启动时自动检查更新'),
            value: _autoCheck,
            onChanged: (v) async {
              setState(() => _autoCheck = v);
              await FirmwareUpdatePrefs.setAutoCheck(v);
            },
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _checking
                ? null
                : () async {
                    setState(() => _checking = true);
                    await manualCheckForUpdate(context);
                    if (mounted) setState(() => _checking = false);
                  },
            icon: _checking
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.system_update),
            label: const Text('检查更新'),
          ),
        ],
      ),
    );
  }
}
