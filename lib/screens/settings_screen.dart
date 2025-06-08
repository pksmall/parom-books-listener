import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import '../services/settings_service.dart';
import '../services/logger_service.dart';
import '../screens/logs_screen.dart';

class SettingsItem {
  final String title;
  final IconData icon;

  SettingsItem({required this.title, required this.icon});
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final List<SettingsItem> menuItems = [
    SettingsItem(title: 'Themes', icon: Icons.palette),
    SettingsItem(title: 'Audio', icon: Icons.audio_file),
    SettingsItem(title: 'Other Settings', icon: Icons.settings),
  ];
  final _settingsService = SettingsService();

  // Добавляем состояния для аудио настроек
  bool autoSavePlaylist = true;
  bool autoSavePosition = true;
  int playlistSaveTimeout = 10;
  int positionSaveTimeout = 5;

  // Добавляем состояния для настроек логирования
  bool enableFileLogging = true;
  bool enableConsoleLogging = true;
  LogLevel minLogLevel = LogLevel.info;

  int selectedIndex = 0;
  ThemeMode selectedTheme = ThemeMode.system;
  bool useCustomBackground = false;
  String? backgroundImagePath;

  @override
  void initState() {
    super.initState();
    _initSettings();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Settings'),
        // Если хотите убрать тень от AppBar
        elevation: 0,
      ),
      body: Row(
        children: [
          // Левая панель с меню
          Container(
            width: 200,
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(
                  color: Theme.of(context).dividerColor,
                ),
              ),
            ),
            child: ListView.builder(
              itemCount: menuItems.length,
              itemBuilder: (context, index) {
                return ListTile(
                  selected: selectedIndex == index,
                  leading: Icon(menuItems[index].icon),
                  title: Text(menuItems[index].title),
                  onTap: () {
                    setState(() {
                      selectedIndex = index;
                    });
                  },
                );
              },
            ),
          ),
          // Правая панель с формами
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: _buildSettingsForm(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsForm() {
    switch (selectedIndex) {
      case 0:
        return _buildThemeSettings();
      case 1:
        return _buildAudioSettings();
      case 2:
        return _buildLoggingSettings();
      case 3:
        return const Center(child: Text('Other Settings'));
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildLoggingSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Logging Settings',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),

        // Enable file logging
        SwitchListTile(
          title: const Text('Enable file logging'),
          subtitle: const Text('Save logs to file for debugging'),
          value: enableFileLogging,
          onChanged: (bool value) {
            setState(() {
              enableFileLogging = value;
            });
            _saveLoggingSettings();
          },
        ),

        // Enable console logging
        SwitchListTile(
          title: const Text('Enable console logging'),
          subtitle: const Text('Print logs to console (debug mode)'),
          value: enableConsoleLogging,
          onChanged: (bool value) {
            setState(() {
              enableConsoleLogging = value;
            });
            _saveLoggingSettings();
          },
        ),

        const SizedBox(height: 20),

        // Minimum log level
        const Text('Minimum log level:'),
        const SizedBox(height: 8),
        SegmentedButton<LogLevel>(
          segments: LogLevel.values.map((level) => ButtonSegment(
            value: level,
            label: Text(level.name.toUpperCase()),
          )).toList(),
          selected: {minLogLevel},
          onSelectionChanged: (Set<LogLevel> selection) {
            setState(() {
              minLogLevel = selection.first;
            });
            _saveLoggingSettings();
          },
        ),

        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildThemeSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Theme Settings',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(
              value: ThemeMode.system,
              label: Text('System'),
            ),
            ButtonSegment(
              value: ThemeMode.light,
              label: Text('Light'),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              label: Text('Dark'),
            ),
          ],
          selected: {selectedTheme},
          onSelectionChanged: (Set<ThemeMode> selection) {
            setState(() {
              selectedTheme = selection.first;
            });
          },
        ),
        const SizedBox(height: 20),
        SwitchListTile(
          title: const Text('Use Custom Background'),
          value: useCustomBackground,
          onChanged: (bool value) {
            setState(() {
              useCustomBackground = value;
            });
          },
        ),
        if (useCustomBackground) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              if (backgroundImagePath != null)
                Container(
                  width: 100,
                  height: 60,
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image: AssetImage(backgroundImagePath!),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _pickImage,
                child: const Text('Choose Image'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildAudioSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Audio Settings',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),

        // Автосохранение списка файлов
        SwitchListTile(
          title: const Text('Auto-save playlist'),
          value: autoSavePlaylist,
          onChanged: (bool value) {
            setState(() {
              autoSavePlaylist = value;
            });
            _saveSettings();
          },
        ),

        // Автосохранение позиции
        SwitchListTile(
          title: const Text('Auto-save playback position'),
          value: autoSavePosition,
          onChanged: (bool value) {
            setState(() {
              autoSavePosition = value;
            });
            _saveSettings();
          },
        ),

        const SizedBox(height: 20),

        // Таймаут сохранения списка
        Row(
          children: [
            const Expanded(
              child: Text('Playlist save timeout (seconds):'),
            ),
            SizedBox(
              width: 80,
              child: TextField(
                controller: TextEditingController(
                  text: playlistSaveTimeout.toString(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  if (value.isNotEmpty) {
                    setState(() {
                      playlistSaveTimeout = int.parse(value);
                    });
                    _saveSettings();
                  }
                },
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        // Таймаут сохранения позиции
        Row(
          children: [
            const Expanded(
              child: Text('Position save timeout (seconds):'),
            ),
            SizedBox(
              width: 80,
              child: TextField(
                controller: TextEditingController(
                  text: positionSaveTimeout.toString(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  if (value.isNotEmpty) {
                    setState(() {
                      positionSaveTimeout = int.parse(value);
                    });
                    _saveSettings();
                  }
                },
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        // Дополнительная информация
        const Text(
          'Note: Changes are saved automatically',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  Future<void> _initSettings() async {
    await _settingsService.init();
    final settings = await _settingsService.loadSettings();
    setState(() {
      autoSavePlaylist = settings['autoSavePlaylist'] ?? true;
      autoSavePosition = settings['autoSavePosition'] ?? true;
      playlistSaveTimeout = settings['playlistSaveTimeout'] ?? 10;
      positionSaveTimeout = settings['positionSaveTimeout'] ?? 5;

      enableFileLogging = settings['enableFileLogging'] ?? true;
      enableConsoleLogging = settings['enableConsoleLogging'] ?? true;

      // Parse log level from string
      final logLevelStr = settings['minLogLevel'] ?? 'INFO';
      minLogLevel = LogLevel.values.firstWhere(
            (level) => level.name == logLevelStr,
        orElse: () => LogLevel.info,
      );
    });
  }

  Future<void> _saveSettings() async {
    await _settingsService.saveSettings({
      'autoSavePlaylist': autoSavePlaylist,
      'autoSavePosition': autoSavePosition,
      'playlistSaveTimeout': playlistSaveTimeout,
      'positionSaveTimeout': positionSaveTimeout,
      'enableFileLogging': enableFileLogging,
      'enableConsoleLogging': enableConsoleLogging,
      'minLogLevel': minLogLevel.name,
    });
  }

  Future<void> _saveLoggingSettings() async {
    // Update logger settings immediately
    LoggerService.instance.updateSettings(
      minLogLevel: minLogLevel,
      enableFileLogging: enableFileLogging,
      enableConsoleLogging: enableConsoleLogging,
    );

    // Save to settings file
    await _saveSettings();
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      setState(() {
        backgroundImagePath = image.path;
      });
    }
  }
}
