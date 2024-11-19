import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import 'player_screen.dart';
import '../models/audio_book.dart';
import '../playlist_provider.dart';
import 'package:provider/provider.dart';
import '../widgets/app_menu.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  Future<void> _scanDirectory(BuildContext context) async {
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

      if (selectedDirectory == null) return;

      List<AudioBook> audioBooks = [];
      Directory directory = Directory(selectedDirectory);

      await for (var entity in directory.list(recursive: true)) {
        if (entity is File) {
          String ext = path.extension(entity.path).toLowerCase();
          if (ext == '.mp3') {
            String fileName = path.basename(entity.path);
            audioBooks.add(
              AudioBook(
                id: entity.path,
                title: fileName,
                author: 'Unknown',
                coverUrl: '',
                audioUrl: entity.path,
                duration: Duration.zero,
              ),
            );
          }
        }
      }

      if (audioBooks.isNotEmpty) {
        Provider.of<PlaylistProvider>(context, listen: false)
            .addAudioBooks(audioBooks);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added ${audioBooks.length} audio files'),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error scanning directory: $e'),
        ),
      );
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
                ],
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: playlistProvider.playlist.length,
                  itemBuilder: (context, index) {
                    final audioBook = playlistProvider.playlist[index];
                    return ListTile(
                      title: Text(audioBook.title),
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
