import 'dart:io';
import 'package:path/path.dart' as path;
import '../models/audio_book.dart';

class FileUtils {
  static bool isAudioFile(String filePath) {
    final extension = path.extension(filePath).toLowerCase();
    return ['.mp3', '.m4a', '.wav', '.aac'].contains(extension);
  }

  static Future<List<AudioBook>> scanDirectory(String directoryPath) async {
    List<AudioBook> audioBooks = [];
    try {
      final directory = Directory(directoryPath);
      await for (var entity in directory.list(recursive: true)) {
        if (entity is File && isAudioFile(entity.path)) {
          final audioBook = await AudioBook.fromFile(entity.path);
          audioBooks.add(audioBook);
        }
      }
    } catch (e) {
      print('Error scanning directory: $e');
    }
    return audioBooks;
  }
}
