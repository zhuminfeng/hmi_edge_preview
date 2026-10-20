import 'package:flutter/material.dart';
import '../providers/app_state.dart';
import '../../l10n/app_localizations.dart';
import 'settings/app_settings_screen.dart';

/// 物料配方管理界面
/// appType: 0 = 失重秤(LIW), 1 = 罐装秤(Filling)
class MaterialRecipeScreen extends StatefulWidget {
  final int appType;
  final int subsystemId;

  const MaterialRecipeScreen({
    super.key,
    required this.appType,
    required this.subsystemId,
  });

  @override
  State<MaterialRecipeScreen> createState() => _MaterialRecipeScreenState();
}

class _MaterialRecipeScreenState extends State<MaterialRecipeScreen> {
  List<Map<String, dynamic>> _recipes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRecipes();
  }

  Future<void> _loadRecipes() async {
    final state = AppStateProvider.read(context);
    final l = AppLocalizations.of(context)!; // 引入 l10n
    setState(() => _loading = true);
    try {
      final list = await state.getAllMaterialRecipes(widget.appType);
      setState(() {
        _recipes = list;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.loadRecipeFailedError(e.toString()))), // 替换
        );
      }
    }
  }

  Future<void> _openRecipeEditor({String? recipeName}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AppSettingsScreen(
          subsystemId: widget.subsystemId,
          appType: widget.appType,
          initialRecipeName: recipeName,
          forceConfirmOnBack: recipeName == null,
        ),
      ),
    );
    if (mounted) await _loadRecipes();
  }

  Future<void> _loadRecipe(Map<String, dynamic> recipe) async {
    final l = AppLocalizations.of(context)!;
    final recipeName = recipe['name'] as String? ?? l.unnamedRecipe;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.loadRecipeTitle),
        content: Text(l.loadRecipeConfirmMsg(recipeName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.confirmLoad),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final state = AppStateProvider.read(context);
    try {
      final ok = await state.loadMaterialRecipe(
        widget.subsystemId,
        recipe['recipeId'] as int,
        recipeName,
        widget.appType,
      );

      if (mounted) {
        if (ok) {
          setState(() {});
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ok ? l.recipeLoadedSuccess(recipeName) : l.loadFailed,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.loadFailedError(e.toString()))),
        );
      }
    }
  }

  Future<void> _editRecipe(Map<String, dynamic> recipe) async {
    final recipeName = recipe['name'] as String? ?? '未命名';
    final state = AppStateProvider.read(context);
    final ok = await state.loadMaterialRecipe(
      widget.subsystemId,
      recipe['recipeId'] as int,
      recipeName,
      widget.appType,
    );
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('加载配方「${recipeName}」失败，无法编辑')));
      return;
    }
    await _openRecipeEditor(recipeName: recipeName);
  }

  Future<void> _showRecipeActions(Map<String, dynamic> recipe) async {
    final recipeName = recipe['name'] as String? ?? '未命名';
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(recipeName)),
            ListTile(
              leading: const Icon(Icons.download_rounded),
              title: const Text('加载配方'),
              onTap: () => Navigator.pop(context, 'load'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑配方'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'load') {
      await _loadRecipe(recipe);
    } else if (action == 'edit') {
      await _editRecipe(recipe);
    }
  }

  Future<void> _deleteRecipe(Map<String, dynamic> recipe) async {
    final l = AppLocalizations.of(context)!;
    final recipeName = recipe['name'] as String? ?? l.unnamedRecipe;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.deleteRecipeTitle),
        content: Text(l.deleteRecipeConfirmMsg(recipeName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.delete),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final state = AppStateProvider.read(context);
    try {
      final ok = await state.deleteMaterialRecipe(
        recipe['recipeId'] as int,
        widget.appType,
      );
      if (ok) {
        if (state.getActiveRecipeName(widget.subsystemId) == recipeName) {
          state.setActiveRecipeName(widget.subsystemId, null);
        }

        await _loadRecipes();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l.recipeDeletedSuccess)));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.deleteFailedError(e.toString()))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final title = widget.appType == 0
        ? l.liwMaterialRecipe
        : l.fillingMaterialRecipe;
    final state = AppStateProvider.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l.refresh,
            onPressed: _loadRecipes,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openRecipeEditor,
        icon: const Icon(Icons.add),
        label: const Text('新增配方'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _recipes.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.folder_open, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    '暂无配方\n点击右下角按钮新增配方',
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(color: Colors.grey),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _recipes.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final recipe = _recipes[index];
                final createdAt = recipe['createdAt'] as String? ?? '';

                // 判断当前配方是否是处于活跃（使用中）状态
                final isActive =
                    state.getActiveRecipeName(widget.subsystemId) ==
                    recipe['name'];

                return ListTile(
                  tileColor: isActive ? Colors.blue.withOpacity(0.05) : null,
                  leading: CircleAvatar(
                    backgroundColor: isActive
                        ? Colors.blue
                        : (widget.appType == 0
                              ? Colors.blue.shade200
                              : Colors.green.shade200),
                    child: isActive
                        ? const Icon(Icons.check, color: Colors.white, size: 20)
                        : Text(
                            '${recipe['recipeId']}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => _showRecipeActions(recipe),
                          borderRadius: BorderRadius.circular(4),
                          child: Text(
                            recipe['name'] as String? ?? l.unnamedRecipe,
                            style: TextStyle(
                              fontWeight: isActive
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isActive ? Colors.blue.shade700 : null,
                            ),
                          ),
                        ),
                      ),
                      if (isActive)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            l.currentlyInUse,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.blue,
                            ),
                          ),
                        ),
                    ],
                  ),
                  subtitle: Text(l.createdAtTime(createdAt)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isActive)
                        TextButton.icon(
                          onPressed: () => _loadRecipe(recipe),
                          icon: const Icon(
                            Icons.download_rounded,
                            color: Colors.blue,
                          ),
                          label: Text(
                            l.loadBtn,
                            style: const TextStyle(color: Colors.blue),
                          ),
                        ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: '编辑配方',
                        onPressed: () => _editRecipe(recipe),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                        tooltip: l.delete,
                        onPressed: () => _deleteRecipe(recipe),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
