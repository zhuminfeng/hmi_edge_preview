import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart'; // 👈 引入本地化文件
import '../../providers/app_state.dart';
import 'liw_dashboard.dart'; // 引入核心看板组件

class LiwDetailScreen extends StatelessWidget {
  // final int subsystemId;
  final String subsystemName;

  const LiwDetailScreen({
    super.key,
    // required this.subsystemId,
    this.subsystemName = '',
  });

  @override
  Widget build(BuildContext context) {
    // 提取公共主题颜色
    final colorScheme = Theme.of(context).colorScheme;
    final state = AppStateProvider.of(context);
    final l = AppLocalizations.of(context)!; // 👈 获取本地化实例

    return Scaffold(
      backgroundColor: colorScheme.surface, // 统一背景色
      appBar: AppBar(
        // 如果没有传名字，兜底显示子系统 ID，并支持中英文切换
        title: Text(
          subsystemName.isNotEmpty
              ? subsystemName
              : l.liwSystemIdFallback(state.activeSubsystemId), // 👈 替换硬编码
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      // 🚀 核心优雅实现：主体内容 100% 引用 Dashboard 组件
      body: const SafeArea(child: LiwDashboard()), // 👈 可以顺手加个 const 优化性能
    );
  }
}
