import 'package:flutter/material.dart';
import 'package:weighing_system_elinux/weighing_system_elinux.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/app_state.dart';

enum _SlaveRole { weighing, digitalIo, servo, unknown }

_SlaveRole _detectSlaveRole(int vendorId, int productCode) {
  if (vendorId == 0x00001071 && productCode == 0x00000001) {
    return _SlaveRole.weighing;
  }
  if (vendorId == 0x00000b95 && productCode == 0x00002201) {
    return _SlaveRole.weighing;
  }
  if (vendorId == 0x00000b95 && productCode == 0x00001101) {
    return _SlaveRole.digitalIo;
  }
  if (vendorId == 0x00100000 && productCode == 0x000c0112) {
    return _SlaveRole.servo;
  }
  return _SlaveRole.unknown;
}

class HardwareConfigScreen extends StatefulWidget {
  const HardwareConfigScreen({super.key});

  @override
  State<HardwareConfigScreen> createState() => _HardwareConfigScreenState();
}

class _HardwareConfigScreenState extends State<HardwareConfigScreen> {
  final WeighingPlatform _platform = WeighingPlatform.instance;

  bool _loading = true;
  bool _scanning = false;
  bool _saving = false;
  bool _dirty = false;

  List<EthercatSlaveInfo> _configuredOutput = [];
  List<EthercatSlaveInfo> _configuredInput = [];
  List<EthercatSlaveInfo> _scanned = [];

  @override
  void initState() {
    super.initState();
    _loadAndAutoScan();
  }

  Future<void> _loadAndAutoScan() async {
    setState(() => _loading = true);
    final cfg = await _platform.getEthercatHardwareConfig();
    if (!mounted) return;

    setState(() {
      _configuredOutput = List<EthercatSlaveInfo>.from(
        cfg['outputSlaves'] ?? const [],
      );
      _configuredInput = List<EthercatSlaveInfo>.from(
        cfg['inputSlaves'] ?? const [],
      );
      _loading = false;
    });

    await _scan(autoPrompt: true);
    if (mounted) {
      AppStateProvider.of(context).clearNewHardwareCount();
    }
  }

  String _keyOf(EthercatSlaveInfo s) {
    return '${s.position}-${s.vendorId}-${s.productCode}';
  }

  Set<String> _configuredKeys() {
    return {..._configuredOutput.map(_keyOf), ..._configuredInput.map(_keyOf)};
  }

  List<EthercatSlaveInfo> _newScannedDevices() {
    final configured = _configuredKeys();
    return _scanned.where((s) => !configured.contains(_keyOf(s))).toList();
  }

  Future<void> _scan({required bool autoPrompt}) async {
    setState(() => _scanning = true);
    final slaves = await _platform.scanEthercatSlaves();
    if (!mounted) return;

    setState(() {
      _scanned = slaves;
      _scanning = false;
    });

    if (!autoPrompt) return;

    final newDevices = _newScannedDevices();
    if (newDevices.isEmpty || !mounted) return;

    final l = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('发现新硬件'),
        content: Text('检测到 ${newDevices.length} 个未保存设备，是否加入配置并立即保存？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.save),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      _addAllNewScannedDevices();
      await _save();
    }
  }

  void _addDevice(EthercatSlaveInfo slave) {
    final role = _detectSlaveRole(slave.vendorId, slave.productCode);
    final target = role == _SlaveRole.weighing
        ? _configuredInput
        : _configuredOutput;
    if (target.any((e) => _keyOf(e) == _keyOf(slave))) return;

    setState(() {
      target.add(slave);
      _dirty = true;
    });
  }

  void _addAllNewScannedDevices() {
    final newDevices = _newScannedDevices();
    if (newDevices.isEmpty) return;

    setState(() {
      for (final s in newDevices) {
        final role = _detectSlaveRole(s.vendorId, s.productCode);
        final target = role == _SlaveRole.weighing
            ? _configuredInput
            : _configuredOutput;
        if (!target.any((e) => _keyOf(e) == _keyOf(s))) {
          target.add(s);
        }
      }
      _dirty = true;
    });
  }

  void _removeConfigured(EthercatSlaveInfo slave, {required bool isInput}) {
    setState(() {
      if (isInput) {
        _configuredInput.removeWhere((e) => _keyOf(e) == _keyOf(slave));
      } else {
        _configuredOutput.removeWhere((e) => _keyOf(e) == _keyOf(slave));
      }
      _dirty = true;
    });
  }

  Future<void> _editAlias(
    EthercatSlaveInfo slave, {
    required bool isInput,
  }) async {
    final l = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: slave.userAlias);

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑硬件别名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '别名',
            hintText: '例如：主秤1 / IO-1',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.confirm),
          ),
        ],
      ),
    );

    if (saved != true || !mounted) return;

    final nextAlias = controller.text.trim();
    setState(() {
      final list = isInput ? _configuredInput : _configuredOutput;
      final idx = list.indexWhere((e) => _keyOf(e) == _keyOf(slave));
      if (idx >= 0) {
        list[idx] = list[idx].copyWith(userAlias: nextAlias);
        _dirty = true;
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    final ok = await _platform.saveEthercatHardwareConfig(
      _configuredOutput,
      _configuredInput,
    );

    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) {
        _dirty = false;
      }
    });

    final l = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '硬件配置已保存' : l.saveHardwareConfigFailed),
        backgroundColor: ok
            ? Colors.green
            : Theme.of(context).colorScheme.error,
      ),
    );
  }

  Future<bool> _confirmDiscardOrSave() async {
    if (!_dirty) return true;

    final l = AppLocalizations.of(context)!;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('还有未保存的硬件配置'),
        content: const Text('是否保存后再返回？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: Text('放弃保存'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: Text(l.save),
          ),
        ],
      ),
    );

    if (choice == 'save') {
      await _save();
      return !_dirty;
    }
    return choice == 'discard';
  }

  Widget _buildConfiguredSection({
    required String title,
    required List<EthercatSlaveInfo> slaves,
    required bool isInput,
  }) {
    if (slaves.isEmpty) {
      return Card(
        child: ListTile(title: Text(title), subtitle: const Text('暂无配置')),
      );
    }

    return Card(
      child: Column(
        children: [
          ListTile(
            title: Text(title),
            subtitle: Text('已配置 ${slaves.length} 个设备'),
          ),
          const Divider(height: 1),
          for (final s in slaves) ...[
            ListTile(
              leading: Icon(isInput ? Icons.scale : Icons.memory),
              title: Text(
                s.userAlias.isEmpty ? s.description : s.userAlias,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                'Pos ${s.position}  VID 0x${s.vendorId.toRadixString(16).padLeft(8, '0')}  '
                'PID 0x${s.productCode.toRadixString(16).padLeft(8, '0')}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '编辑别名',
                    onPressed: () => _editAlias(s, isInput: isInput),
                    icon: const Icon(Icons.edit),
                  ),
                  IconButton(
                    tooltip: '删除硬件',
                    onPressed: () => _removeConfigured(s, isInput: isInput),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final newDevices = _newScannedDevices();

    return WillPopScope(
      onWillPop: _confirmDiscardOrSave,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('硬件配置'),
          leading: BackButton(
            onPressed: () async {
              final ok = await _confirmDiscardOrSave();
              if (ok && context.mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
          actions: [
            IconButton(
              tooltip: '扫描设备',
              onPressed: _scanning ? null : () => _scan(autoPrompt: false),
              icon: _scanning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.radar),
            ),
            TextButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(l.save),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: () => _scan(autoPrompt: false),
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.info_outline),
                        title: const Text('设备发现说明'),
                        subtitle: const Text(
                          '开机后会自动扫描一次；若发现新设备会提示是否保存。运行中新增设备可手动扫描后添加并保存。',
                        ),
                      ),
                    ),
                    _buildConfiguredSection(
                      title: '已配置称重设备 (Input)',
                      slaves: _configuredInput,
                      isInput: true,
                    ),
                    _buildConfiguredSection(
                      title: '已配置输出设备 (Output)',
                      slaves: _configuredOutput,
                      isInput: false,
                    ),
                    Card(
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.radar),
                            title: const Text('扫描到的当前设备'),
                            subtitle: Text(
                              '共 ${_scanned.length} 个，新增 ${newDevices.length} 个',
                            ),
                            trailing: TextButton.icon(
                              onPressed: newDevices.isEmpty
                                  ? null
                                  : _addAllNewScannedDevices,
                              icon: const Icon(Icons.playlist_add),
                              label: const Text('添加全部新增'),
                            ),
                          ),
                          const Divider(height: 1),
                          if (_scanned.isEmpty)
                            const ListTile(subtitle: Text('暂无扫描结果，请点击右上角扫描')),
                          for (final s in _scanned) ...[
                            Builder(
                              builder: (ctx) {
                                final already = _configuredKeys().contains(
                                  _keyOf(s),
                                );
                                return ListTile(
                                  leading: Icon(
                                    already
                                        ? Icons.check_circle
                                        : Icons.new_releases,
                                    color: already
                                        ? Colors.green
                                        : Theme.of(ctx).colorScheme.primary,
                                  ),
                                  title: Text(
                                    s.userAlias.isEmpty
                                        ? s.description
                                        : s.userAlias,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    'Pos ${s.position}  VID 0x${s.vendorId.toRadixString(16).padLeft(8, '0')}  '
                                    'PID 0x${s.productCode.toRadixString(16).padLeft(8, '0')}',
                                  ),
                                  trailing: already
                                      ? const Text('已配置')
                                      : TextButton(
                                          onPressed: () => _addDevice(s),
                                          child: const Text('添加'),
                                        ),
                                );
                              },
                            ),
                            const Divider(height: 1),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
