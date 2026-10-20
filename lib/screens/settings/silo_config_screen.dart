import 'package:flutter/material.dart';
import 'package:weighing_system_elinux/weighing_system_elinux.dart';

import 'app_settings_screen.dart';

class SiloConfigScreen extends StatefulWidget {
  final int subsystemId;

  const SiloConfigScreen({super.key, required this.subsystemId});

  @override
  State<SiloConfigScreen> createState() => _SiloConfigScreenState();
}

class _SiloConfigScreenState extends State<SiloConfigScreen> {
  List<int> _siloIndices = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSilos();
  }

  Future<void> _loadSilos() async {
    setState(() => _loading = true);
    try {
      final indices = await WeighingPlatform.instance
          .getFillingSiloProcessIndices(widget.subsystemId);
      if (!mounted) return;
      setState(() {
        _siloIndices = indices;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('加载料仓配置失败: $error')));
    }
  }

  Future<void> _openSiloEditor({int? siloIndex}) async {
    var selectedIndex = siloIndex;
    if (selectedIndex == null) {
      final controller = TextEditingController();
      selectedIndex = await showDialog<int>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('添加料仓'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '料仓编号',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final value = int.tryParse(controller.text);
                if (value == null || value < 0) return;
                Navigator.pop(dialogContext, value);
              },
              child: const Text('下一步'),
            ),
          ],
        ),
      );
    }

    if (selectedIndex == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AppSettingsScreen(
          subsystemId: widget.subsystemId,
          appType: 1,
          siloIndex: selectedIndex,
        ),
      ),
    );
    if (mounted) await _loadSilos();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('料仓配置'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadSilos,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openSiloEditor(),
        icon: const Icon(Icons.add),
        label: const Text('添加料仓'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _siloIndices.isEmpty
          ? Center(
              child: Text(
                '暂无已配置料仓',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _siloIndices.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final siloIndex = _siloIndices[index];
                return ListTile(
                  leading: CircleAvatar(child: Text('$siloIndex')),
                  title: Text('料仓 $siloIndex'),
                  subtitle: const Text('独立工艺参数'),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _openSiloEditor(siloIndex: siloIndex),
                );
              },
            ),
    );
  }
}
