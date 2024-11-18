import 'dart:io';
import 'package:path/path.dart' as path;

class AudioBook {
  final String id;
  final String title;
  final String author;
  final String coverUrl;
  final String audioUrl;
  final Duration duration;
  Duration position;

  AudioBook({
    required this.id,
    required this.title,
    required this.author,
    required this.coverUrl,
    required this.audioUrl,
    required this.duration,
    this.position = Duration.zero,
  });

  // Добавьте фабричный метод для создания из файла
  static Future<AudioBook> fromFile(String filePath) async {
    final file = File(filePath);
    final fileName = path.basename(filePath);

    return AudioBook(
      id: filePath,
      title: fileName,
      author: 'Unknown',
      coverUrl: '',
      audioUrl: filePath,
      duration: Duration.zero,
    );
  }
}
