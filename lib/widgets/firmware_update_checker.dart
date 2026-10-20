import 'dart:async';

import 'package:flutter/material.dart';

import '../services/firmware_update_prefs.dart';
import '../services/firmware_update_service.dart';

/// 应用启动时自动检查更新；发现新版本后弹窗提示用户确认，
/// 用户确认后展示下载/校验/部署进度，全程可见、可失败重试。
class FirmwareUpdateChecker extends StatefulWidget {
  const FirmwareUpdateChecker({super.key, required this.child});

  final Widget child;

  @override
  State<FirmwareUpdateChecker> createState() => _FirmwareUpdateCheckerState();
}

class _FirmwareUpdateCheckerState extends State<FirmwareUpdateChecker> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoCheck());
  }

  Future<void> _autoCheck() async {
    final autoCheck = await FirmwareUpdatePrefs.getAutoCheck();
    if (!autoCheck) return;
    final baseUrl = await FirmwareUpdatePrefs.getBaseUrl();
    if (baseUrl.isEmpty) return; // 尚未配置更新服务器地址，跳过静默检查

    // Buildroot 设备刚起来时网络常常还没就绪，做几次退避重试。
    const delays = <Duration>[
      Duration(seconds: 5),
      Duration(seconds: 10),
      Duration(seconds: 20),
    ];

    for (var attempt = 0; attempt <= delays.length; attempt++) {
      if (!mounted) return;

      final service = FirmwareUpdateService(baseUrl: baseUrl);
      try {
        final info = await service.fetchLatest();
        final newer = await service.isNewer(info);
        if (!newer) return; // 已是最新，安静结束

        final skipped = await FirmwareUpdatePrefs.getSkippedBuild();
        if (info.buildNumber > 0 && info.buildNumber == skipped) {
          return; // 用户已选择忽略该版本
        }
        if (!mounted) return;
        await showUpdateDialog(context, service, info);
        return;
      } catch (e, st) {
        // 不要静默吞掉异常，否则冷启动网络未就绪时无法排查。
        debugPrint('[firmware_check] attempt=$attempt failed: $e');
        debugPrintStack(stackTrace: st);
        if (attempt >= delays.length) return;
        await Future.delayed(delays[attempt]);
      } finally {
        service.dispose();
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 展示“发现新版本”对话框，并在用户确认后驱动下载/校验/部署流程。
Future<void> showUpdateDialog(
  BuildContext context,
  FirmwareUpdateService service,
  FirmwareUpdateInfo info,
) async {
  final proceed = await showDialog<bool>(
    context: context,
    barrierDismissible: !info.mandatory,
    builder:
        (ctx) => AlertDialog(
          title: const Text('发现新版本'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('新版本: ${info.version}'),
                if (info.releaseNotes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(info.releaseNotes),
                ],
              ],
            ),
          ),
          actions: [
            if (!info.mandatory)
              TextButton(
                onPressed: () async {
                  await FirmwareUpdatePrefs.setSkippedBuild(info.buildNumber);
                  if (ctx.mounted) Navigator.pop(ctx, false);
                },
                child: const Text('忽略此版本'),
              ),
            if (!info.mandatory)
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('稍后'),
              ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('立即更新'),
            ),
          ],
        ),
  );

  if (proceed != true || !context.mounted) return;
  await _runUpdateFlow(context, service, info);
}

Future<void> _runUpdateFlow(
  BuildContext context,
  FirmwareUpdateService service,
  FirmwareUpdateInfo info,
) async {
  final progressNotifier = ValueNotifier<FirmwareUpdateProgress>(
    const FirmwareUpdateProgress(FirmwareUpdateStage.downloading),
  );

  unawaited(
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => ValueListenableBuilder<FirmwareUpdateProgress>(
            valueListenable: progressNotifier,
            builder:
                (ctx, p, _) => AlertDialog(
                  title: const Text('正在更新'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_stageLabel(p.stage)),
                      const SizedBox(height: 12),
                      if (p.stage == FirmwareUpdateStage.downloading)
                        LinearProgressIndicator(
                          value: p.progress > 0 ? p.progress : null,
                        )
                      else if (p.stage != FirmwareUpdateStage.done &&
                          p.stage != FirmwareUpdateStage.error)
                        const LinearProgressIndicator(),
                      if (p.stage == FirmwareUpdateStage.error &&
                          p.message != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          p.message!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ],
                    ],
                  ),
                  actions: [
                    if (p.stage == FirmwareUpdateStage.error ||
                        p.stage == FirmwareUpdateStage.done)
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('关闭'),
                      ),
                  ],
                ),
          ),
    ),
  );

  try {
    progressNotifier.value = const FirmwareUpdateProgress(
      FirmwareUpdateStage.downloading,
    );
    final path = await service.downloadAndVerify(
      info,
      onProgress: (p) {
        progressNotifier.value = FirmwareUpdateProgress(
          FirmwareUpdateStage.downloading,
          progress: p,
        );
      },
    );

    progressNotifier.value = const FirmwareUpdateProgress(
      FirmwareUpdateStage.applying,
    );
    await service.applyUpdate(path, info);

    progressNotifier.value = const FirmwareUpdateProgress(
      FirmwareUpdateStage.done,
      message: '更新完成，应用即将重启',
    );
  } catch (e) {
    progressNotifier.value = FirmwareUpdateProgress(
      FirmwareUpdateStage.error,
      message: e.toString(),
    );
  }
}

String _stageLabel(FirmwareUpdateStage stage) {
  switch (stage) {
    case FirmwareUpdateStage.checking:
      return '正在检查更新...';
    case FirmwareUpdateStage.downloading:
      return '正在下载更新包...';
    case FirmwareUpdateStage.verifying:
      return '正在校验更新包...';
    case FirmwareUpdateStage.applying:
      return '正在部署并重启服务...';
    case FirmwareUpdateStage.done:
      return '更新完成';
    case FirmwareUpdateStage.error:
      return '更新失败';
    case FirmwareUpdateStage.idle:
      return '';
  }
}

/// 供设置页“检查更新”按钮使用的手动检查入口，成功/失败都会明确提示用户。
Future<void> manualCheckForUpdate(BuildContext context) async {
  final baseUrl = await FirmwareUpdatePrefs.getBaseUrl();
  if (baseUrl.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先在下方填写更新服务器地址')));
    }
    return;
  }
  final service = FirmwareUpdateService(baseUrl: baseUrl);
  try {
    final info = await service.fetchLatest();
    final newer = await service.isNewer(info);
    if (!context.mounted) return;
    if (!newer) {
      // 不再依赖 PackageInfo，改用 readInstalled()，保证提示里显示的版本号准确。
      final installed = await service.readInstalled();
      if (!context.mounted) return;
      final label = installed.version.isNotEmpty ? installed.version : '未知版本';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('当前已是最新版本 ($label)')));
      return;
    }
    await showUpdateDialog(context, service, info);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('检查更新失败: $e')));
    }
  } finally {
    service.dispose();
  }
}
