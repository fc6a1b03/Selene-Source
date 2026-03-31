enum AdminSourceValidationEventType {
  start,
  sourceResult,
  sourceError,
  complete,
}

enum AdminSourceValidationStatus {
  validating,
  valid,
  noResults,
  invalid,
}

class AdminSourceValidationEvent {
  const AdminSourceValidationEvent({
    required this.type,
    this.totalSources,
    this.completedSources,
    this.sourceKey,
    this.status,
  });

  factory AdminSourceValidationEvent.fromJson(Map<String, dynamic> json) {
    final String typeValue = json['type'] as String? ?? 'complete';
    final AdminSourceValidationEventType type = switch (typeValue) {
      'start' => AdminSourceValidationEventType.start,
      'source_result' => AdminSourceValidationEventType.sourceResult,
      'source_error' => AdminSourceValidationEventType.sourceError,
      _ => AdminSourceValidationEventType.complete,
    };

    final String? rawStatus = json['status'] as String?;
    final AdminSourceValidationStatus? status = switch (rawStatus) {
      'valid' => AdminSourceValidationStatus.valid,
      'no_results' => AdminSourceValidationStatus.noResults,
      'invalid' => AdminSourceValidationStatus.invalid,
      'validating' => AdminSourceValidationStatus.validating,
      _ => null,
    };

    return AdminSourceValidationEvent(
      type: type,
      totalSources: json['totalSources'] as int?,
      completedSources: json['completedSources'] as int?,
      sourceKey: json['source'] as String?,
      status: status,
    );
  }

  final AdminSourceValidationEventType type;
  final int? totalSources;
  final int? completedSources;
  final String? sourceKey;
  final AdminSourceValidationStatus? status;
}

class AdminSourceValidationItem {
  const AdminSourceValidationItem({
    required this.key,
    required this.name,
    required this.status,
  });

  final String key;
  final String name;
  final AdminSourceValidationStatus status;

  AdminSourceValidationItem copyWith({
    String? key,
    String? name,
    AdminSourceValidationStatus? status,
  }) {
    return AdminSourceValidationItem(
      key: key ?? this.key,
      name: name ?? this.name,
      status: status ?? this.status,
    );
  }
}
