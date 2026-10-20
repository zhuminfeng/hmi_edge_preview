class SiloStep {
  final int siloIndex;
  final int order;
  final double targetValue;
  final String materialName;
  final String materialId;
  final bool enabled;

  const SiloStep({
    required this.siloIndex,
    required this.order,
    required this.targetValue,
    this.materialName = '',
    this.materialId = '',
    this.enabled = true,
  });

  Map<String, dynamic> toMap() => {
        'silo_index': siloIndex,
        'order': order,
        'target_value': targetValue,
        'material_name': materialName,
        'material_id': materialId,
        'enabled': enabled,
      };

  factory SiloStep.fromMap(Map m) => SiloStep(
        siloIndex: m['silo_index'] as int? ?? -1,
        order: m['order'] as int? ?? 0,
        targetValue: (m['target_value'] ?? 0.0).toDouble(),
        materialName: m['material_name'] as String? ?? '',
        materialId: m['material_id'] as String? ?? '',
        enabled: m['enabled'] as bool? ?? true,
      );
}

class SiloSequenceConfig {
  final int subsystemId;
  final bool enabled;
  final List<SiloStep> steps;

  const SiloSequenceConfig({
    required this.subsystemId,
    this.enabled = false,
    this.steps = const [],
  });

  Map<String, dynamic> toMap() => {
        'subsystem_id': subsystemId,
        'enabled': enabled,
        'steps': steps.map((e) => e.toMap()).toList(),
      };

  factory SiloSequenceConfig.fromMap(Map m) => SiloSequenceConfig(
        subsystemId: m['subsystem_id'] as int? ?? 0,
        enabled: m['enabled'] as bool? ?? false,
        steps: (m['steps'] as List?)
                ?.map((e) => SiloStep.fromMap(e as Map))
                .toList() ??
            [],
      );
}
