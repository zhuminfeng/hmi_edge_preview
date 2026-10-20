# HMI Edge 预览

这是从 `flutter_weighing_new_version/lib` 抽出来的界面预览工程。称重、EtherCAT、固件更新都换成了内存模拟，**没有原生插件**，也**不需要给 Edge 装扩展**。

界面文件仍在 `lib/screens`、`lib/widgets`。改完保存，浏览器会热重载。

## Windows 上用 Edge 看效果

1. 安装 [Flutter SDK](https://docs.flutter.dev/get-started/install/windows)，并确认 `flutter` 已在 PATH 里。
2. 双击 `preview_edge.bat`。
3. Edge 会打开 `http://127.0.0.1:8080`。第一次编译要等一两分钟。

不要直接双击 `web/index.html`。Flutter Web 必须由本地服务提供，`file://` 打不开。

手动命令：

```bat
cd hmi_edge_preview
flutter pub get
flutter run -d web-server --web-port 8080 --web-hostname 127.0.0.1
```

然后在 Edge 地址栏打开 `http://127.0.0.1:8080`。

如果本机 `flutter devices` 里能看到 Edge，也可以：

```bat
flutter run -d edge --web-port 8080
```

## 预览里有什么

- 三个示例子系统：1# 失重秤、包装秤、2# 失重秤
- 重量和流量每 200ms 跳动，启停、去皮、配方、子系统开关都会改内存数据
- 左上角青色条是预览标记，正式工程里没有
- 固件更新页只展示界面，不会下载安装包
- 信号分析导出改为浏览器下载 CSV

## 和设备工程的关系

这里的 `lib` 是一份拷贝。改界面后，把对应 dart 文件拷回 `flutter_weighing_new_version/lib` 即可。不要把本目录的 `lib/services/firmware_update_*.dart`、`lib/main.dart`、`lib/screens/settings/signal_analyzer_screen.dart` 覆盖回设备工程，这三处为了浏览器做了替换。
