import 'dart:async';
import 'package:flutter/material.dart';
import 'package:weighing_system_elinux/weighing_system_elinux.dart';
import '../../l10n/app_localizations.dart';

enum CalType { none, zero, span, step }

// 🚀 引入逐步法特定的子流程枚举
enum StepSubState {
  idle, // 初始
  weightLoaded, // 测试砝码在台上，按下了“开始”
  removeWaiting, // 要求移除测试砝码
  substituteWaiting, // 已移除，等待灌装替代物料
  stepNextLoad, // 替代物填满，继续往上叠加砝码
}

class CalibrationScreen extends StatefulWidget {
  final int? subsystemId;
  final int? scaleId;

  const CalibrationScreen({super.key, this.subsystemId, this.scaleId});

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  int _scaleId = 0;
  int _linearMode = 0;

  ScaleParams _currentParams = const ScaleParams();
  static const _unitOptions = ['g', 'kg', 'lb', 't', 'ton'];

  StreamSubscription? _calSubscription;
  StreamSubscription? _weightSubscription; // 🚀 新增：重量流订阅
  final List<TextEditingController> _loadControllers = List.generate(
    4,
    (_) => TextEditingController(),
  );

  String _calStatus = '';
  bool _loading = true;
  bool _loadFailed = false;
  bool _isCalError = false;

  double _liveWeight = 0.0; // 🚀 新增：实时重量
  bool _isStable = false; // 🚀 新增：实时稳定标识

  CalType _activeType = CalType.none;
  int _calBackendState = 0; // 0=空闲, 1=采样期, 2=完成, 3=动态完成, 4=失败, 6=单步稳了等待加下一砝码
  bool _wasDynamic = false;

  // 🚀 核心计数：记录当前已经成功完成的测试点数量
  int _completedSpanSteps = 0;
  bool _isStepWaitingHandled = false;

  StepSubState _stepSubState = StepSubState.idle;

  final TextEditingController _stepWeightController = TextEditingController(
    text: '10.0',
  );

  @override
  void initState() {
    super.initState();
    _loadScaleContext();

    // 🚀 新增：监听高频实时重量流，用于给操作员提供加替料的视觉反馈
    _weightSubscription = WeighingPlatform.instance.weightStream.listen((data) {
      if (!mounted) return;
      if (data.scaleId == _scaleId) {
        setState(() {
          // 这里通常显示毛重（Gross Weight）
          _liveWeight = data.grossWeight;
          _isStable = data.isStable;
        });
      }
    });

    _calSubscription = WeighingPlatform.instance.calibrationEvents.listen((
      event,
    ) {
      if (!mounted) return;
      final int scaleId = event['scaleId'];
      final int state = event['state'];
      final String msg = event['message'] ?? '';

      // if (_calBackendState != state) {
      //   debugPrint('=========================================');
      //   debugPrint(
      //     '[CalEvent] 收到校正事件! scaleId: $scaleId | scaleId期望: $_scaleId',
      //   );
      //   debugPrint('[CalEvent] state值: $state | message: "$msg"');
      //   debugPrint('=========================================');
      // }

      if (scaleId != _scaleId) return;

      final l = AppLocalizations.of(context)!;

      setState(() {
        _calBackendState = state;
        if (state == 1) {
          if (_activeType == CalType.span) {
            int totalPoints = _linearMode + 1;
            if (_completedSpanSteps == 0) {
              _calStatus = l.spanCalAcquiringFirst;
            } else if (_completedSpanSteps < totalPoints) {
              _calStatus = l.spanCalStepCompleted(
                _completedSpanSteps,
                _completedSpanSteps + 1,
              );
            }
          } else if (_activeType == CalType.step) {
            if (_stepSubState == StepSubState.idle) {
              _calStatus = l.stepCalAcquiringFirst;
            }
          } else {
            _calStatus = msg.isNotEmpty ? msg : l.calInProgressDefault;
          }
          _wasDynamic = false;
        } else if (state == 6) {
          int totalPoints = _linearMode + 1;
          if (!_isStepWaitingHandled && _completedSpanSteps < totalPoints) {
            _completedSpanSteps++;
            _isStepWaitingHandled = true;
          }
          if (_completedSpanSteps < totalPoints) {
            double nextLoad =
                double.tryParse(_loadControllers[_completedSpanSteps].text) ??
                0.0;
            _calStatus = l.spanCalStepSuccessNext(
              _completedSpanSteps,
              _completedSpanSteps + 1,
              nextLoad.toStringAsFixed(2),
            );
          }
        } else if (state == 2) {
          if (_activeType == CalType.span) {
            _completedSpanSteps = _linearMode + 1;
            _calStatus = _wasDynamic
                ? l.calDynamicCompletedMsg
                : l.calSpanSuccessSave;
          } else if (_activeType == CalType.step) {
            if (_stepSubState == StepSubState.idle ||
                _stepSubState == StepSubState.stepNextLoad) {
              if (!_isStepWaitingHandled) {
                _completedSpanSteps++;
                _isStepWaitingHandled = true;
              }
              _stepSubState = StepSubState.weightLoaded;
              _calStatus = l.stepCalStepSuccess(_stepWeightController.text);
            }
          } else {
            _calStatus = _wasDynamic
                ? l.calDynamicCompletedMsg
                : l.calZeroSuccessSave;
          }
          _isCalError = false;
        } else if (state == 3) {
          _wasDynamic = true;
          if (_activeType == CalType.span) {
            _completedSpanSteps = _linearMode + 1;
            _calStatus = l.spanCalDynamicWarning;
          } else {
            _calStatus = l.calDynamicAcceptPrompt;
          }
          _isCalError = true;
        } else if (state == 4) {
          _calStatus = l.calFailedMsg(msg);
          _isCalError = true;
          _activeType = CalType.none;
          _calBackendState = 0;
        }
      });
    });
  }

  @override
  void dispose() {
    _weightSubscription?.cancel(); // 🚀 新增：记得销毁
    _calSubscription?.cancel();
    for (var c in _loadControllers) c.dispose();
    _stepWeightController.dispose();
    super.dispose();
  }

  Future<void> _acceptDynamic(bool accept) async {
    final l = AppLocalizations.of(context)!;
    try {
      await WeighingPlatform.instance.acceptDynamicCalibration(
        _scaleId,
        accept,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCalError = true;
        _calStatus = l.opFailedMsg(e.toString());
      });
    }
  }

  Future<void> _loadScaleContext() async {
    _loadFailed = false;
    try {
      _scaleId = await _resolveScaleId();
      _currentParams = await WeighingPlatform.instance.getScaleParams(_scaleId);
    } catch (_) {
      _loadFailed = true;
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<int> _resolveScaleId() async {
    if (widget.scaleId != null) return widget.scaleId!;
    if (widget.subsystemId == null) return 0;
    final mappings = await WeighingPlatform.instance.getSubsystemMappings();
    final idx = mappings.indexWhere((m) => m.subsystemId == widget.subsystemId);
    if (idx >= 0) return mappings[idx].scaleId;
    throw StateError('Unable to locate scale configuration.');
  }

  // ==========================================
  // 校正触发逻辑
  // ==========================================

  Future<void> _doZeroCal() async {
    final l = AppLocalizations.of(context)!;
    setState(() {
      _activeType = CalType.zero;
      _calBackendState = 1;
      _isCalError = false;
      _calStatus = l.calZeroInProgressMsg;
    });
    try {
      await WeighingPlatform.instance.triggerCalZero(_scaleId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCalError = true;
        _calStatus = '${l.calZeroFailed}$e';
        _activeType = CalType.none;
      });
    }
  }

  Future<void> _doSpanCal() async {
    final l = AppLocalizations.of(context)!;
    List<double> loads = [];
    int numPoints = _linearMode + 1;

    for (int i = 0; i < numPoints; i++) {
      final v = double.tryParse(_loadControllers[i].text);
      if (v == null || v <= 0) {
        setState(() {
          _isCalError = true;
          _calStatus = '${l.invalidTestLoad} ${i + 1}';
        });
        return;
      }
      loads.add(v);
    }

    setState(() {
      _activeType = CalType.span;
      _calBackendState = 1;
      _isCalError = false;
      _completedSpanSteps = 0;
      _isStepWaitingHandled = false;
      _calStatus = l.spanCalAcquiringStatic(1);
    });

    try {
      // 🚀 触发量程计算命令：只发此命令，绝不额外跨击下一指令
      await WeighingPlatform.instance.triggerCalSpan(
        _scaleId,
        _linearMode,
        loads,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCalError = true;
        _calStatus = '${l.calSpanFailed}$e';
        _activeType = CalType.none;
      });
    }
  }

  Future<void> _doStepCal() async {
    final l = AppLocalizations.of(context)!;
    final w = double.tryParse(_stepWeightController.text);
    if (w == null || w <= 0) {
      setState(() {
        _isCalError = true;
        _calStatus = l.invalidStepWeight;
      });
      return;
    }
    setState(() {
      _activeType = CalType.step;
      _calBackendState = 1;
      _isCalError = false;
      _calStatus = l.calStepStarted;
    });
    try {
      await WeighingPlatform.instance.triggerStepCalibration(_scaleId, w);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCalError = true;
        _calStatus = '${l.calStepFailed}$e';
        _activeType = CalType.none;
      });
    }
  }

  // ==========================================
  // 确认加码、保存、中止逻辑 (全局共享)
  // ==========================================

  Future<void> _addLoadCal() async {
    final l = AppLocalizations.of(context)!;
    if (_activeType == CalType.span) {
      setState(() {
        _calBackendState = 1;
        _isStepWaitingHandled = false;
        _calStatus = l.spanCalAcquiringStatic(_completedSpanSteps + 1);
      });
    }
    try {
      await WeighingPlatform.instance.triggerCalibrationAddLoad(_scaleId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCalError = true;
        _calStatus = l.opFailedMsg(e.toString());
      });
    }
  }

  Future<void> _saveCal() async {
    final l = AppLocalizations.of(context)!;
    setState(() {
      _calStatus = l.savingDataMsg;
    });
    try {
      await WeighingPlatform.instance.updateScaleParams(
        _scaleId,
        _currentParams,
      );
      final ok = await WeighingPlatform.instance.triggerSaveCalibration(
        _scaleId,
      );

      if (!mounted) return;
      setState(() {
        _isCalError = !ok;
        _calStatus = ok ? l.calSavedSuccess : l.calSaveFailed;
        _activeType = CalType.none;
        _calBackendState = 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCalError = true;
        _calStatus = '${l.saveFailed}$e';
        _activeType = CalType.none;
      });
    }
  }

  Future<void> _abortCal() async {
    final l = AppLocalizations.of(context)!;
    await WeighingPlatform.instance.triggerAbortCalibration(_scaleId);
    if (!mounted) return;
    setState(() {
      _isCalError = false;
      _calStatus = l.calAbortedMsg;
      _activeType = CalType.none;
      _calBackendState = 0;
    });
  }

  String _getStepInstructionText(AppLocalizations l) {
    switch (_stepSubState) {
      case StepSubState.weightLoaded:
        return l.stepInstRemovePrepared;
      case StepSubState.removeWaiting:
        return l.stepInstRemoveWait;
      case StepSubState.substituteWaiting:
        return l.stepInstSubstituteWait;
      case StepSubState.stepNextLoad:
        return l.stepInstNextLoad;
      default:
        return l.stepInstIdle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(l.calibration)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadFailed) {
      return Scaffold(
        appBar: AppBar(title: Text(l.calibration)),
        body: Center(child: Text(l.loadScaleSettingsFailed)),
      );
    }

    final linearModeLabels = [
      l.linearDisabled,
      l.linear3Point,
      l.linear4Point,
      l.linear5Point,
    ];
    int numPoints = _linearMode + 1;

    return Scaffold(
      appBar: AppBar(title: Text(l.calibration)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // =======================================================
          // 🚀 新增：工业仪表级别的实时重量大屏显示
          // =======================================================
          Card(
            color: Colors.black87,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.liveGrossWeight,
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          // 稳定符号（如果稳定显示一个圆圈或静止标志）
                          Icon(
                            _isStable ? Icons.circle : Icons.change_history,
                            color: _isStable
                                ? Colors.greenAccent
                                : Colors.orange,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _liveWeight.toStringAsFixed(2), // 保留两位小数，根据实际精度可调
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 48, // 超大号字体
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Courier', // 最好用等宽数字字体
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Text(
                    _unitOptions[_currentParams.calibrationUnit],
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 32),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // === 状态提示框 ===
          if (_calStatus.isNotEmpty)
            Card(
              color: _isCalError ? Colors.red.shade50 : Colors.green.shade50,
              child: ListTile(
                leading: Icon(
                  _isCalError ? Icons.error : Icons.info,
                  color: _isCalError ? Colors.red : Colors.green,
                ),
                title: Text(
                  _calStatus,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          const SizedBox(height: 16),

          // === 标定单位设置 ===
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: DropdownButtonFormField<int>(
                value: _currentParams.calibrationUnit,
                decoration: InputDecoration(
                  labelText: l.calUnitLabel,
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: List.generate(
                  _unitOptions.length,
                  (i) =>
                      DropdownMenuItem(value: i, child: Text(_unitOptions[i])),
                ),
                onChanged: _activeType != CalType.none
                    ? null
                    : (v) => setState(() {
                        _currentParams = _currentParams.copyWith(
                          calibrationUnit: v!,
                        );
                      }),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // =======================================================
          // 🚀 零点校正专属区域 (Zero Calibration)
          // =======================================================
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.calZero,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(l.clearScalePressStartMsg),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (_activeType == CalType.none ||
                          (_activeType == CalType.zero &&
                              (_calBackendState == 0 || _calBackendState == 4)))
                        ElevatedButton.icon(
                          icon: const Icon(Icons.play_arrow),
                          label: Text(l.calStart),
                          onPressed: _doZeroCal,
                        ),

                      if (_activeType == CalType.zero &&
                          _calBackendState == 3) ...[
                        ElevatedButton.icon(
                          icon: const Icon(Icons.check),
                          label: Text(l.yesBtn),
                          onPressed: () => _acceptDynamic(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.close),
                          label: Text(l.noBtn),
                          onPressed: () => _acceptDynamic(false),
                        ),
                      ],

                      if (_activeType == CalType.zero && _calBackendState == 2)
                        ElevatedButton.icon(
                          icon: const Icon(Icons.save),
                          label: Text(l.saveAndComplete),
                          onPressed: _saveCal,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),

                      if (_activeType == CalType.zero &&
                          (_calBackendState == 1 ||
                              _calBackendState == 2 ||
                              _calBackendState == 3))
                        OutlinedButton.icon(
                          icon: const Icon(Icons.cancel),
                          label: Text(l.cancel),
                          onPressed: _abortCal,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // =======================================================
          // 🚀 量程校正专属区域 (Span Calibration)
          // =======================================================
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.calSpan,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l.spanCalInst,
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 12),

                  DropdownButtonFormField<int>(
                    value: _linearMode,
                    decoration: InputDecoration(
                      labelText: l.linearCalibration,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: List.generate(
                      4,
                      (i) => DropdownMenuItem(
                        value: i,
                        child: Text(linearModeLabels[i]),
                      ),
                    ),
                    onChanged: _activeType != CalType.none
                        ? null
                        : (v) => setState(() => _linearMode = v!),
                  ),
                  const SizedBox(height: 12),

                  for (int i = 0; i < numPoints; i++) ...[
                    Builder(
                      builder: (ctx) {
                        // 🚀 已标定的阶段其对应载荷文本框全部转灰并锁死为不可改
                        bool isAdjusted = false;
                        if (_activeType == CalType.span) {
                          if (_calBackendState == 2 || _calBackendState == 3) {
                            isAdjusted = true;
                          } else {
                            isAdjusted = i < _completedSpanSteps;
                          }
                        }
                        return TextFormField(
                          controller: _loadControllers[i],
                          decoration: InputDecoration(
                            labelText: l.testLoadKg(i + 1),
                            border: const OutlineInputBorder(),
                            isDense: true,
                            filled: isAdjusted,
                            fillColor: isAdjusted ? Colors.grey.shade300 : null,
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          readOnly: _activeType != CalType.none,
                          style: TextStyle(
                            color: isAdjusted ? Colors.grey.shade600 : null,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                  ],

                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // 1. 【开始】按钮：仅处于空闲或无任务状态才可激活触发
                      if (_activeType == CalType.none ||
                          (_activeType == CalType.span &&
                              (_calBackendState == 0 || _calBackendState == 4)))
                        ElevatedButton.icon(
                          icon: const Icon(Icons.play_arrow),
                          label: Text(l.calStart),
                          onPressed: _doSpanCal,
                        ),

                      // Builder(
                      //   builder: (ctx) {
                      //     final bool isSpan = (_activeType == CalType.span);
                      //     final bool isState6 = (_calBackendState == 6);
                      //     final bool isStepLess =
                      //         (_completedSpanSteps < (_linearMode + 1));
                      //     final bool finalResult =
                      //         (isSpan && isState6 && isStepLess);

                      //     // 如果当前正在做量程标定，输出所有的条件实时判定
                      //     if (isSpan) {
                      //       debugPrint(
                      //         '-----------------------------------------',
                      //       );
                      //       debugPrint('[UI Check继续按钮] 当前是否全满足: $finalResult');
                      //       debugPrint(
                      //         ' ├─ 1. _activeType == CalType.span : $isSpan',
                      //       );
                      //       debugPrint(
                      //         ' ├─ 2. _calBackendState == 6       : $isState6 (当前值: $_calBackendState)',
                      //       );
                      //       debugPrint(
                      //         ' └─ 3. _completedSpanSteps < (${_linearMode + 1}) : $isStepLess (当前步骤: $_completedSpanSteps | _linearMode: $_linearMode)',
                      //       );
                      //       debugPrint(
                      //         '-----------------------------------------',
                      //       );
                      //     }
                      //     return const SizedBox.shrink();
                      //   },
                      // ),
                      // 2. 🚀 修复版【继续】按钮：
                      //    将判断表达式改成 < (_linearMode + 1)，确保不管测2个点还是5个点都不会再被吞掉！
                      if (_activeType == CalType.span &&
                          _calBackendState == 6 &&
                          _completedSpanSteps < (_linearMode + 1))
                        ElevatedButton.icon(
                          icon: const Icon(Icons.skip_next),
                          label: Text(l.continueBtn),
                          onPressed: _addLoadCal,
                        ),

                      // 3. 【保存 / 完成】按钮：全部正常结束 (State 2)
                      if (_activeType == CalType.span && _calBackendState == 2)
                        ElevatedButton.icon(
                          icon: const Icon(Icons.save),
                          label: Text(l.saveAndComplete),
                          onPressed: _saveCal,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),

                      // 4. 【保存 (接受动态)】按钮：最终载荷存在轻度颤抖动点通过 (State 3)
                      if (_activeType == CalType.span && _calBackendState == 3)
                        ElevatedButton.icon(
                          icon: const Icon(Icons.save),
                          label: Text(l.saveAcceptDynamic),
                          onPressed: () async {
                            await _acceptDynamic(true);
                            await _saveCal();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                          ),
                        ),

                      // 5. 【取消】按钮：量程运行或采样等待阶段随时可取消放弃
                      if (_activeType == CalType.span &&
                          (_calBackendState == 1 ||
                              _calBackendState == 6 ||
                              _calBackendState == 2 ||
                              _calBackendState == 3))
                        OutlinedButton.icon(
                          icon: const Icon(Icons.cancel),
                          label: Text(l.cancel),
                          onPressed: _abortCal,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // =======================================================
          // 🚀 阶跃校正专属区域 (符合逐步替代法 12 步计量要求)
          // =======================================================
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.calStep,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _stepWeightController,
                    decoration: InputDecoration(
                      labelText: l.testWeightKg,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    readOnly:
                        _activeType != CalType.none &&
                        _activeType != CalType.step,
                  ),
                  const SizedBox(height: 12),

                  // 🚀 新增：严格按照逐步法标准反馈阶段化的指导文字
                  if (_activeType == CalType.step)
                    Container(
                      padding: const EdgeInsets.all(8),
                      color: Colors.blue.shade50,
                      child: Text(
                        _getStepInstructionText(l), // 根据子状态抛出提示
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),

                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // 1. 对应规程步骤2-3：放入砝码，点击“开始”
                      if (_activeType == CalType.none ||
                          (_activeType == CalType.step &&
                              _calBackendState == 0))
                        ElevatedButton.icon(
                          icon: const Icon(Icons.play_arrow),
                          label: Text(l.startStepCal),
                          onPressed: _doStepCal,
                        ),

                      // 2. 对应规程步骤4-5：完成一阶标定后，按“继续”转入“移除准备”
                      if (_activeType == CalType.step &&
                          _calBackendState == 2 &&
                          _stepSubState == StepSubState.weightLoaded)
                        ElevatedButton.icon(
                          icon: const Icon(Icons.arrow_forward),
                          label: Text(l.continuePrepareRemove),
                          onPressed: () {
                            setState(() {
                              _stepSubState = StepSubState.removeWaiting;
                              _calStatus = l.stepInstRemoveWait;
                            });
                          },
                        ),

                      // 3. 对应规程步骤5：操作员搬走砝码后按“移除_确定”
                      if (_activeType == CalType.step &&
                          _stepSubState == StepSubState.removeWaiting)
                        ElevatedButton.icon(
                          icon: const Icon(Icons.done_all),
                          label: Text(l.removeConfirm),
                          onPressed: () async {
                            // 🚀 调用触发 C++ 底层的 StepRemoveConfirm()
                            await WeighingPlatform.instance
                                .triggerStepRemoveConfirm(_scaleId);
                            setState(() {
                              _stepSubState = StepSubState.substituteWaiting;
                              _calStatus = l.stepInstSubstituteWait;
                            });
                          },
                        ),

                      // 4. 对应规程步骤6-7：灌装替料完成，按“添加_确定”
                      if (_activeType == CalType.step &&
                          _stepSubState == StepSubState.substituteWaiting)
                        ElevatedButton.icon(
                          icon: const Icon(Icons.add_shopping_cart),
                          label: Text(l.addConfirm),
                          onPressed: () async {
                            double subWeight =
                                double.tryParse(_stepWeightController.text) ??
                                0.0;
                            // 🚀 调用触发 C++ 底层的 StepSubstituteConfirm(weight)
                            await WeighingPlatform.instance
                                .triggerStepSubstituteConfirm(
                                  _scaleId,
                                  subWeight,
                                );
                            setState(() {
                              _stepSubState = StepSubState.stepNextLoad;
                              _calStatus = l.stepInstNextLoad;
                            });
                          },
                        ),

                      // 5. 对应规程步骤8-9：在此叠加物理砝码，按“开始”推进高阶线性
                      if (_activeType == CalType.step &&
                          _stepSubState == StepSubState.stepNextLoad)
                        ElevatedButton.icon(
                          icon: const Icon(Icons.refresh),
                          label: Text(l.startNextStep),
                          onPressed: () {
                            setState(() {
                              _calBackendState = 1;
                              _isStepWaitingHandled = false; // 解锁下一阶计数
                              // 🚀 严格对齐第9步标准：更改为“正在标定线性”
                              _calStatus = l.calibratingLinearMsg;
                            });
                            // 通知底层抓取新阶跃载荷
                            WeighingPlatform.instance.triggerCalibrationAddLoad(
                              _scaleId,
                            );
                          },
                        ),

                      // 6. 对应规程步骤11：随时可按【完成】收工并保存全部阶跃调整值
                      if (_activeType == CalType.step &&
                          (_calBackendState == 2 || _calBackendState == 3))
                        ElevatedButton.icon(
                          icon: const Icon(Icons.save),
                          label: Text(l.completeAndSave),
                          onPressed: _saveCal,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),

                      // 7. 对应规程步骤12：任何阶段点击“取消”均可中止
                      if (_activeType == CalType.step && _calBackendState != 0)
                        OutlinedButton.icon(
                          icon: const Icon(Icons.cancel),
                          label: Text(l.cancelAbort),
                          onPressed: _abortCal,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
