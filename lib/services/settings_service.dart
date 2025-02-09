// lib/services/settings_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;

class SettingsService {
  static const String _fileName = 'settings.json';
  late String _filePath;

  Future<void> init() async {
    final appDir = Directory.current;
    _filePath = path.join(appDir.path, 'data', _fileName);

    // Создаем директорию, если её нет
    final settingsDir = Directory(path.dirname(_filePath));
    if (!await settingsDir.exists()) {
      await settingsDir.create(recursive: true);
    }

    // Создаем файл с настройками по умолчанию, если его нет
    final file = File(_filePath);
    if (!await file.exists()) {
      await file.writeAsString(jsonEncode(_defaultSettings));
    }
  }

  Map<String, dynamic> get _defaultSettings => {
    'autoSavePlaylist': true,
    'autoSavePosition': true,
    'playlistSaveTimeout': 10,
    'positionSaveTimeout': 5,
  };

  Future<Map<String, dynamic>> loadSettings() async {
    try {
      final file = File(_filePath);
      final contents = await file.readAsString();
      return jsonDecode(contents) as Map<String, dynamic>;
    } catch (e) {
      return _defaultSettings;
    }
  }

  Future<void> saveSettings(Map<String, dynamic> settings) async {
    final file = File(_filePath);
    await file.writeAsString(jsonEncode(settings));
  }
}
