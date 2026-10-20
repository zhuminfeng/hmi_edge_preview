import 'package:flutter/material.dart';
import 'package:weighing_system_elinux/weighing_system_elinux.dart';
import 'app_settings_screen.dart';

class SiloSequenceConfigScreen extends StatefulWidget {
  final int subsystemId;

  const SiloSequenceConfigScreen({super.key, required this.subsystemId});

  @override
  State<SiloSequenceConfigScreen> createState() =>
      _SiloSequenceConfigScreenState();
}

class _SiloSequenceConfigScreenState extends State<SiloSequenceConfigScreen> {
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  bool _enabled = false;
  List<SiloStep> _steps = const [];
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final config = await WeighingPlatform.instance
          .getFillingSiloSequenceConfig(widget.subsystemId);
      if (!mounted) return;
      setState(() {
        _enabled = config.enabled;
        _steps = List<SiloStep>.from(config.steps)
          ..sort((a, b) => a.order.compareTo(b.order));
        _loading = false;
        _dirty = false;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error.toString();
      });
    }
  }

  Future<bool> _save() async {
    setState(() => _saving = true);
    final config = SiloSequenceConfig(
      subsystemId: widget.subsystemId,
      enabled: _enabled,
      steps: [
        for (var i = 0; i < _steps.length; i++)
          SiloStep(
            siloIndex: _steps[i].siloIndex,
            order: i,
            targetValue: _steps[i].targetValue,
            materialName: _steps[i].materialName,
            materialId: _steps[i].materialId,
            enabled: _steps[i].enabled,
          ),
      ],
    );
    try {
      final ok = await WeighingPlatform.instance.setFillingSiloSequenceConfig(
        widget.subsystemId,
        config,
      );
      if (!mounted) return false;
      if (ok) {
        setState(() => _dirty = false);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? '料仓顺序配置已保存' : '料仓顺序配置保存失败'),
          backgroundColor: ok ? Colors.green : Colors.red,
        ),
      );
      return ok;
    } catch (error) {
      if (!mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('料仓顺序配置保存失败: $error')));
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmDiscardOrSave() async {
    if (!_dirty || _saving) return true;

    final choice = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('提示'),
        content: const Text('当前修改尚未保存，是否保存后再返回？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('否'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('是'),
          ),
        ],
      ),
    );

    if (choice == null) return false;
    if (!choice) return true;
    return await _save();
  }

  Future<void> _editStep({SiloStep? current, int? index}) async {
    List<int> siloIndices;
    try {
      siloIndices = await WeighingPlatform.instance
          .getFillingSiloProcessIndices(widget.subsystemId);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('加载已配置料仓失败: $error')));
      return;
    }

    if (siloIndices.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先在“料仓配置”中添加料仓')));
      return;
    }

    var selectedSiloIndex = current?.siloIndex;
    if (selectedSiloIndex != null && !siloIndices.contains(selectedSiloIndex)) {
      siloIndices = [...siloIndices, selectedSiloIndex]..sort();
    }
    selectedSiloIndex ??= siloIndices.first;
    final targetController = TextEditingController(
      text: current?.targetValue.toString() ?? '0',
    );
    final materialNameController = TextEditingController(
      text: current?.materialName ?? '',
    );
    final materialIdController = TextEditingController(
      text: current?.materialId ?? '',
    );
    var enabled = current?.enabled ?? true;

    final result = await showDialog<SiloStep>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(current == null ? '添加料仓步骤' : '编辑料仓步骤'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownMenu<int>(
                    initialSelection: selectedSiloIndex,
                    expandedInsets: EdgeInsets.zero,
                    label: const Text('料仓编号'),
                    enableFilter: true,
                    enableSearch: true,
                    dropdownMenuEntries: siloIndices
                        .map(
                          (siloIndex) => DropdownMenuEntry<int>(
                            value: siloIndex,
                            label: '料仓 $siloIndex',
                          ),
                        )
                        .toList(),
                    onSelected: (value) => setDialogState(() {
                      selectedSiloIndex = value;
                    }),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: targetController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: '目标值 (kg)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: materialNameController,
                    decoration: const InputDecoration(
                      labelText: '物料名称',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: materialIdController,
                    decoration: const InputDecoration(
                      labelText: '物料 ID',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用该步骤'),
                    value: enabled,
                    onChanged: (value) => setDialogState(() => enabled = value),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final targetValue = double.tryParse(targetController.text);
                  if (selectedSiloIndex == null ||
                      targetValue == null ||
                      targetValue < 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('请选择料仓并输入有效目标值')),
                    );
                    return;
                  }
                  Navigator.of(dialogContext).pop(
                    SiloStep(
                      siloIndex: selectedSiloIndex!,
                      order: index ?? _steps.length,
                      targetValue: targetValue,
                      materialName: materialNameController.text.trim(),
                      materialId: materialIdController.text.trim(),
                      enabled: enabled,
                    ),
                  );
                },
                child: const Text('确定'),
              ),
            ],
          ),
        );
      },
    );

    if (result == null) return;
    setState(() {
      final list = List<SiloStep>.from(_steps);
      if (index == null) {
        list.add(result);
      } else {
        list[index] = result;
      }
      _steps = list;
      _dirty = true;
    });
  }

  void _moveStep(int index, int offset) {
    final target = index + offset;
    if (target < 0 || target >= _steps.length) return;
    setState(() {
      final list = List<SiloStep>.from(_steps);
      final step = list.removeAt(index);
      list.insert(target, step);
      _steps = list;
      _dirty = true;
    });
  }

  void _removeStep(int index) {
    setState(() {
      final list = List<SiloStep>.from(_steps);
      list.removeAt(index);
      _steps = list;
      _dirty = true;
    });
  }

  double get _totalTarget => _steps
      .where((step) => step.enabled)
      .fold(0.0, (sum, step) => sum + step.targetValue);

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('配方料仓步骤')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                const Text('无法加载配方料仓步骤'),
                const SizedBox(height: 8),
                Text(_loadError!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _loading = true;
                      _loadError = null;
                    });
                    _load();
                  },
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return WillPopScope(
      onWillPop: _confirmDiscardOrSave,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('配方料仓步骤'),
          actions: [
            IconButton(
              onPressed: _saving ? null : () async => await _save(),
              icon: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _editStep(),
          icon: const Icon(Icons.add),
          label: const Text('添加步骤'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: SwitchListTile(
                title: const Text('启用配方料仓步骤'),
                subtitle: const Text('按配方顺序依次执行各料仓步骤'),
                value: _enabled,
                onChanged: (value) => setState(() {
                  _enabled = value;
                  _dirty = true;
                }),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('步骤数量: ${_steps.length}'),
                    const SizedBox(height: 4),
                    Text('启用步骤总目标值: ${_totalTarget.toStringAsFixed(3)} kg'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_steps.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    '暂无配方料仓步骤，请点击右下角按钮添加。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ),
              )
            else
              ..._steps.asMap().entries.map((entry) {
                final index = entry.key;
                final step = entry.value;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    title: Text('顺序 ${index + 1} · 料仓 ${step.siloIndex}'),
                    subtitle: Text(
                      '物料: ${step.materialName.isEmpty ? '未命名' : step.materialName}${step.materialId.isEmpty ? '' : ' (${step.materialId})'}\n目标值: ${step.targetValue.toStringAsFixed(3)} kg · ${step.enabled ? '启用' : '停用'}',
                    ),
                    leading: CircleAvatar(child: Text('${index + 1}')),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          onPressed: index == 0
                              ? null
                              : () => _moveStep(index, -1),
                          icon: const Icon(Icons.arrow_upward),
                          tooltip: '上移',
                        ),
                        IconButton(
                          onPressed: index == _steps.length - 1
                              ? null
                              : () => _moveStep(index, 1),
                          icon: const Icon(Icons.arrow_downward),
                          tooltip: '下移',
                        ),
                        IconButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AppSettingsScreen(
                                subsystemId: widget.subsystemId,
                                appType: 1,
                                siloIndex: step.siloIndex,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.tune),
                          tooltip: '料仓参数',
                        ),
                        IconButton(
                          onPressed: () =>
                              _editStep(current: step, index: index),
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: '编辑',
                        ),
                        IconButton(
                          onPressed: () => _removeStep(index),
                          icon: const Icon(Icons.delete_outline),
                          color: Colors.red,
                          tooltip: '删除',
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
