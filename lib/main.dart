import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:weighing_system_elinux/weighing_system_elinux.dart';
import 'l10n/app_localizations.dart';
import 'screens/home_screen.dart';
import 'providers/app_state.dart';
import 'widgets/firmware_update_checker.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  registerWebPreviewPlatform();
  runApp(const WeighingApp());
}

class WeighingApp extends StatefulWidget {
  const WeighingApp({super.key});

  @override
  State<WeighingApp> createState() => _WeighingAppState();
}

class _WeighingAppState extends State<WeighingApp> {
  Locale _locale = const Locale('zh');
  late final AppState _appState;

  @override
  void initState() {
    super.initState();
    _appState = AppState(); // 👈 新增：只在应用启动时创建一次
  }

  @override
  void dispose() {
    _appState.dispose(); // 👈 新增：随应用销毁时清理资源
    super.dispose();
  }

  void _changeLocale(Locale locale) {
    setState(() => _locale = locale);
  }

  @override
  Widget build(BuildContext context) {
    return AppStateProvider(
      notifier: _appState, // 👈 传入已创建的 AppState 实例
      onLocaleChange: _changeLocale,
      child: MaterialApp(
        title: 'Weighing System',
        debugShowCheckedModeBanner: false,
        locale: _locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(
          colorSchemeSeed: Colors.blue,
          useMaterial3: true,
          brightness: Brightness.light,
        ),
        darkTheme: ThemeData(
          colorSchemeSeed: Colors.blue,
          useMaterial3: true,
          brightness: Brightness.dark,
        ),
        builder: (context, child) {
          return Banner(
            message: 'EDGE 预览',
            location: BannerLocation.topStart,
            color: Colors.teal,
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const FirmwareUpdateChecker(child: HomeScreen()),
      ),
    );
  }
}
