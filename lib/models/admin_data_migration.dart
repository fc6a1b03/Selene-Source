import 'dart:typed_data';

class NativePickedFile {
  const NativePickedFile({
    required this.name,
    required this.bytes,
  });

  final String name;
  final Uint8List bytes;
}

class DataMigrationExportPayload {
  const DataMigrationExportPayload({
    required this.fileName,
    required this.bytes,
  });

  final String fileName;
  final Uint8List bytes;
}

class DataMigrationImportResult {
  const DataMigrationImportResult({
    required this.message,
    required this.importedUsers,
    required this.timestamp,
    required this.serverVersion,
  });

  factory DataMigrationImportResult.fromJson(Map<String, dynamic> json) {
    return DataMigrationImportResult(
      message: json['message'] as String? ?? '',
      importedUsers: json['importedUsers'] as int? ?? 0,
      timestamp: json['timestamp'] as String? ?? '',
      serverVersion: json['serverVersion'] as String? ?? '',
    );
  }

  final String message;
  final int importedUsers;
  final String timestamp;
  final String serverVersion;
}
