import 'package:flutter/services.dart';
import 'package:selene/models/admin_data_migration.dart';

class NativeFileAccessService {
  const NativeFileAccessService();

  static const MethodChannel _channel =
      MethodChannel('selene.native_file_access/channel');

  Future<NativePickedFile?> pickImportFile() async {
    try {
      final dynamic rawResult = await _channel.invokeMethod<dynamic>(
        'pickImportFile',
      );
      if (rawResult == null) {
        return null;
      }

      final Map<dynamic, dynamic> result = rawResult as Map<dynamic, dynamic>;
      final Uint8List bytes = result['bytes'] as Uint8List? ?? Uint8List(0);
      final String name = result['name'] as String? ?? 'backup.dat';
      return NativePickedFile(name: name, bytes: bytes);
    } on MissingPluginException {
      throw Exception('当前平台暂不支持原生文件选择');
    }
  }

  Future<bool> saveExportFile({
    required Uint8List bytes,
    required String suggestedName,
  }) async {
    try {
      final dynamic rawResult = await _channel.invokeMethod<dynamic>(
        'saveExportFile',
        <String, dynamic>{
          'bytes': bytes,
          'suggestedName': suggestedName,
        },
      );
      if (rawResult == null) {
        return false;
      }
      return true;
    } on MissingPluginException {
      throw Exception('当前平台暂不支持原生文件保存');
    }
  }
}
