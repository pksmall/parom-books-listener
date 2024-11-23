import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:just_audio/just_audio.dart';
import 'dart:io';
import '../models/loading_progress.dart';
import 'player_screen.dart';
import '../models/audio_book.dart';
import '../playlist_provider.dart';
import 'package:provider/provider.dart';
import '../widgets/app_menu.dart';


class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return '$twoDigitMinutes:$twoDigitSeconds';
  }

  int? extractNumber(String fileName) {
    final regex = RegExp(r'(\d+)');
    final match = regex.firstMatch(fileName);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }

  // Функция сравнения для сортировки
  int compareFiles(AudioBook a, AudioBook b) {
    final numA = extractNumber(a.title);
    final numB = extractNumber(b.title);

    if (numA != null && numB != null) {
      return numA.compareTo(numB);
    }
    return a.title.compareTo(b.title);
  }

  Future<Duration?> _getAudioDuration(String filePath) async {
    try {
      final player = AudioPlayer();
      await player.setFilePath(filePath);
      final duration = player.duration;
      await player.dispose();
      return duration;
    } catch (e) {
      print('Error getting duration: $e');
      return null;
    }
  }

  void _clearLibrary(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Clear Library'),
          content: Text('Are you sure you want to clear the library?'),
          actions: [
            TextButton(
              child: Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: Text('Clear'),
              onPressed: () {
                Provider.of<PlaylistProvider>(context, listen: false).clearPlaylist();
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Library cleared')),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _scanDirectory(BuildContext context) async {
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
      if (selectedDirectory == null) return;

      // Показываем диалог прогресса
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Scanning files...'),
            content: LoadingProgressModel(),
          );
        },
      );

      List<AudioBook> audioBooks = [];
      Directory directory = Directory(selectedDirectory);

      // Подсчет общего количества MP3 файлов
      int totalFiles = 0;
      await for (var entity in directory.list(recursive: true)) {
        if (entity is File && path.extension(entity.path).toLowerCase() == '.mp3') {
          totalFiles++;
        }
      }

      LoadingProgress.totalFiles = totalFiles;
      int processedFiles = 0;

      await for (var entity in directory.list(recursive: true)) {
        if (entity is File) {
          String ext = path.extension(entity.path).toLowerCase();
          if (ext == '.mp3') {
            String relativePath = path.relative(entity.path, from: selectedDirectory);
            List<String> pathComponents = path.split(relativePath);
            pathComponents.last = pathComponents.last.replaceAll(ext, '');
            String title = pathComponents.join(' - ');

            LoadingProgress.currentFileName = title;
            LoadingProgress.processedFiles = processedFiles;

            final duration = await _getAudioDuration(entity.path) ?? Duration.zero;
            audioBooks.add(
              AudioBook(
                id: entity.path,
                title: title,
                author: 'Unknown',
                coverUrl: '',
                audioUrl: entity.path,
                duration: duration,
              ),
            );
            processedFiles++;
          }
        }
      }

      // Сортируем аудиокниги
      audioBooks.sort(compareFiles);

      // Закрываем диалог прогресса
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      // Добавляем книги только если есть что добавлять
      if (audioBooks.isNotEmpty && context.mounted) {
        Provider.of<PlaylistProvider>(context, listen: false)
            .addAudioBooks(audioBooks);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added ${audioBooks.length} audio files'),
          ),
        );
      }

    } catch (e) {
      // Закрываем диалог прогресса в случае ошибки
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error scanning directory: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Library'),
        actions: [
          AppMenu(),
        ],
      ),
      body: Consumer<PlaylistProvider>(
        builder: (context, playlistProvider, child) {
          return Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: () => _scanDirectory(context),
                    child: Text('Add Files'),
                  ),
                  ElevatedButton(
                    onPressed: playlistProvider.playlist.isEmpty
                        ? null
                        : () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => PlayerScreen(),
                              ),
                            );
                          },
                    child: Text('Open Player'),
                  ),
                  ElevatedButton(
                    onPressed: playlistProvider.playlist.isEmpty
                        ? null
                        : () => _clearLibrary(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    child: Text('Clear Library'),
                  ),
                ],
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: playlistProvider.playlist.length,
                  itemBuilder: (context, index) {
                    final audioBook = playlistProvider.playlist[index];
                    return ListTile(
                      title: Text(audioBook.title),
                      trailing: Text(_formatDuration(audioBook.duration)),
                      onTap: () {
                        playlistProvider.setCurrentIndex(index);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => PlayerScreen(),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
