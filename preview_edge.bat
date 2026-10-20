@echo off
setlocal
cd /d "%~dp0"

where flutter >nul 2>&1
if errorlevel 1 (
  echo 未找到 Flutter SDK。请先安装 Flutter 并把 flutter\bin 加到 PATH。
  echo 本预览工程不需要任何原生插件，也不需要浏览器扩展。
  pause
  exit /b 1
)

echo 正在获取依赖...
call flutter pub get
if errorlevel 1 (
  echo flutter pub get 失败。
  pause
  exit /b 1
)

echo 启动本地预览服务，并在 Edge 中打开 http://127.0.0.1:8080
start "" msedge http://127.0.0.1:8080
call flutter run -d web-server --web-port 8080 --web-hostname 127.0.0.1
