import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;

enum LogLevel {
  debug(0, 'DEBUG'),
  info(1, 'INFO'),
  warning(2, 'WARN'),
  error(3, 'ERROR');

  const LogLevel(this.value, this.name);
  final int value;
  final String name;
}

class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String tag;
  final String message;
  final String? stackTrace;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    this.stackTrace,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'level': level.name,
    'tag': tag,
    'message': message,
    'stackTrace': stackTrace,
  };

  factory LogEntry.fromJson(Map<String, dynamic> json) => LogEntry(
    timestamp: DateTime.parse(json['timestamp']),
    level: LogLevel.values.firstWhere((l) => l.name == json['level']),
    tag: json['tag'],
    message: json['message'],
    stackTrace: json['stackTrace'],
  );

  String get formattedMessage {
    final timeStr = '${timestamp.hour.toString().padLeft(2, '0')}:'
                   '${timestamp.minute.toString().padLeft(2, '0')}:'
                   '${timestamp.second.toString().padLeft(2, '0')}.'
                   '${timestamp.millisecond.toString().padLeft(3, '0')}';
    return '[$timeStr] [${level.name}] [$tag] $message';
  }
}

class LoggerService {
  static const String _logFileName = 'app.log';
  static const String _oldLogFileName = 'app_old.log';
  static const int _maxLogFileSize = 5 * 1024 * 1024; // 5MB
  static const int _maxLogEntries = 1000;

  static LoggerService? _instance;
  static LoggerService get instance => _instance ??= LoggerService._();

  LoggerService._();

  late String _logFilePath;
  late String _oldLogFilePath;
  final List<LogEntry> _memoryLogs = [];
  bool _initialized = false;
  LogLevel _minLogLevel = LogLevel.info;
  bool _enableFileLogging = true;
  bool _enableConsoleLogging = true;

  Future<void> init({
    LogLevel minLogLevel = LogLevel.info,
    bool enableFileLogging = true,
    bool enableConsoleLogging = true,
  }) async {
    if (_initialized) return;

    _minLogLevel = minLogLevel;
    _enableFileLogging = enableFileLogging;
    _enableConsoleLogging = enableConsoleLogging;

    try {
      final appDir = Directory.current;
      final dataDir = path.join(appDir.path, 'data', 'logs');

      _logFilePath = path.join(dataDir, _logFileName);
      _oldLogFilePath = path.join(dataDir, _oldLogFileName);

      // Create directory if it doesn't exist
      final dir = Directory(path.dirname(_logFilePath));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // Rotate logs if needed
      await _rotateLogsIfNeeded();

      _initialized = true;

      info('Logger', 'Logger service initialized');
      info('Logger', 'Log file: $_logFilePath');
      info('Logger', 'Min log level: ${_minLogLevel.name}');
      info('Logger', 'File logging: $_enableFileLogging');
      info('Logger', 'Console logging: $_enableConsoleLogging');

    } catch (e) {
      error('init', 'Error initializing logger: ', e);
      rethrow;
    }
  }

  void updateSettings({
    LogLevel? minLogLevel,
    bool? enableFileLogging,
    bool? enableConsoleLogging,
  }) {
    if (minLogLevel != null) _minLogLevel = minLogLevel;
    if (enableFileLogging != null) _enableFileLogging = enableFileLogging;
    if (enableConsoleLogging != null) _enableConsoleLogging = enableConsoleLogging;

    info('Logger', 'Settings updated - Level: ${_minLogLevel.name}, File: $_enableFileLogging, Console: $_enableConsoleLogging');
  }

  void debug(String tag, String message, [Object? error]) {
    _log(LogLevel.debug, tag, message, error);
  }

  void info(String tag, String message, [Object? error]) {
    _log(LogLevel.info, tag, message, error);
  }

  void warning(String tag, String message, [Object? error]) {
    _log(LogLevel.warning, tag, message, error);
  }

  void error(String tag, String message, [Object? error]) {
    _log(LogLevel.error, tag, message, error);
  }

  void _log(LogLevel level, String tag, String message, [Object? error]) {
    if (!_initialized && level != LogLevel.error) return;
    if (level.value < _minLogLevel.value) return;

    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      tag: tag,
      message: message,
      stackTrace: error?.toString(),
    );

    // Add to memory logs
    _memoryLogs.add(entry);
    if (_memoryLogs.length > _maxLogEntries) {
      _memoryLogs.removeAt(0);
    }

    // Console logging
    if (_enableConsoleLogging) {
      print(entry.formattedMessage);
      if (entry.stackTrace != null) {
        print('Stack trace: ${entry.stackTrace}');
      }
    }

    // File logging
    if (_enableFileLogging && _initialized) {
      _writeToFile(entry);
    }
  }

  Future<void> _writeToFile(LogEntry entry) async {
    try {
      final file = File(_logFilePath);
      final logLine = '${entry.formattedMessage}\n';

      if (entry.stackTrace != null) {
        final stackLine = 'Stack trace: ${entry.stackTrace}\n';
        await file.writeAsString(logLine + stackLine, mode: FileMode.append);
      } else {
        await file.writeAsString(logLine, mode: FileMode.append);
      }

      // Check if rotation is needed
      await _rotateLogsIfNeeded();
    } catch (e) {
      if (_enableConsoleLogging) {
        error('_writeToFile', 'Error writing to log file: ', e);
      }
    }
  }

  Future<void> _rotateLogsIfNeeded() async {
    try {
      final file = File(_logFilePath);
      if (!await file.exists()) return;

      final stat = await file.stat();
      if (stat.size > _maxLogFileSize) {
        final oldFile = File(_oldLogFilePath);
        if (await oldFile.exists()) {
          await oldFile.delete();
        }
        await file.rename(_oldLogFilePath);

        info('Logger', 'Log file rotated due to size limit');
      }
    } catch (e) {
      if (_enableConsoleLogging) {
        error('_rotateLogsIfNeeded', 'Error rotating log files: ', e);
      }
    }
  }

  List<LogEntry> getMemoryLogs() => List.unmodifiable(_memoryLogs);

  Future<List<LogEntry>> getFileLogs({int? maxEntries}) async {
    if (!_initialized) return [];

    try {
      final logs = <LogEntry>[];

      // Read current log file
      final file = File(_logFilePath);
      if (await file.exists()) {
        await _readLogFile(file, logs, maxEntries);
      }

      // Read old log file if needed and space available
      if ((maxEntries == null || logs.length < maxEntries)) {
        final oldFile = File(_oldLogFilePath);
        if (await oldFile.exists()) {
          final remainingEntries = maxEntries != null ? maxEntries - logs.length : null;
          await _readLogFile(oldFile, logs, remainingEntries);
        }
      }

      // Sort by timestamp (newest first)
      logs.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      if (maxEntries != null && logs.length > maxEntries) {
        return logs.take(maxEntries).toList();
      }

      return logs;
    } catch (e) {
      error('Logger', 'Error reading log files', e);
      return [];
    }
  }

  Future<void> _readLogFile(File file, List<LogEntry> logs, int? maxEntries) async {
    try {
      final lines = await file.readAsLines();
      final pattern = RegExp(r'^\[(\d{2}:\d{2}:\d{2}\.\d{3})\] \[(\w+)\] \[([^\]]+)\] (.+)$');

      for (int i = lines.length - 1; i >= 0 && (maxEntries == null || logs.length < maxEntries); i--) {
        final line = lines[i];
        final match = pattern.firstMatch(line);

        if (match != null) {
          try {
            final timeStr = match.group(1)!;
            final levelStr = match.group(2)!;
            final tag = match.group(3)!;
            final message = match.group(4)!;

            // Parse time (assuming today's date)
            final now = DateTime.now();
            final timeParts = timeStr.split(':');
            final secondsParts = timeParts[2].split('.');

            final timestamp = DateTime(
                now.year, now.month, now.day,
                int.parse(timeParts[0]),
                int.parse(timeParts[1]),
                int.parse(secondsParts[0]),
                int.parse(secondsParts[1])
            );

            final level = LogLevel.values.firstWhere(
                  (l) => l.name == levelStr,
              orElse: () => LogLevel.info,
            );

            logs.add(LogEntry(
              timestamp: timestamp,
              level: level,
              tag: tag,
              message: message,
            ));
          } catch (e) {
            // Skip malformed log entries
            continue;
          }
        }
      }
    } catch (e) {
      error('Logger', 'Error parsing log file', e);
    }
  }

  Future<String> exportLogs() async {
    try {
      final logs = await getFileLogs();
      final exportData = {
        'exportTime': DateTime.now().toIso8601String(),
        'appVersion': '1.0.0', // You can get this from package info
        'totalEntries': logs.length,
        'logs': logs.map((log) => log.toJson()).toList(),
      };

      return jsonEncode(exportData);
    } catch (e) {
      error('Logger', 'Error exporting logs', e);
      rethrow;
    }
  }

  Future<void> clearLogs() async {
    try {
      _memoryLogs.clear();

      final file = File(_logFilePath);
      if (await file.exists()) {
        await file.delete();
      }

      final oldFile = File(_oldLogFilePath);
      if (await oldFile.exists()) {
        await oldFile.delete();
      }

      info('Logger', 'All logs cleared');
    } catch (e) {
      error('Logger', 'Error clearing logs', e);
    }
  }
}

// Convenience methods for global logging
void logDebug(String tag, String message, [Object? error]) {
  LoggerService.instance.debug(tag, message, error);
}

void logInfo(String tag, String message, [Object? error]) {
  LoggerService.instance.info(tag, message, error);
}

void logWarning(String tag, String message, [Object? error]) {
  LoggerService.instance.warning(tag, message, error);
}

void logError(String tag, String message, [Object? error]) {
  LoggerService.instance.error(tag, message, error);
}