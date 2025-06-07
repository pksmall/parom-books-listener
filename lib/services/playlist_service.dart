import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import '../models/audio_book.dart';

class PlaylistService {
  static const String _playlistFileName = 'playlist.json';
  static const String _positionsFileName = 'positions.json';
  late String _playlistFilePath;
  late String _positionsFilePath;

  Future<void> init() async {
    try {
      final appDir = Directory.current;
      final dataDir = path.join(appDir.path, 'data');

      _playlistFilePath = path.join(dataDir, _playlistFileName);
      _positionsFilePath = path.join(dataDir, _positionsFileName);

      print('PlaylistService init - Data directory: $dataDir');
      print('PlaylistService init - Playlist file: $_playlistFilePath');
      print('PlaylistService init - Positions file: $_positionsFilePath');

      // Create directory if it doesn't exist
      final dir = Directory(path.dirname(_playlistFilePath));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
        print('PlaylistService init - Created data directory: ${dir.path}');
      } else {
        print('PlaylistService init - Data directory already exists');
      }
    } catch (e) {
      print('Error in PlaylistService.init(): $e');
      rethrow;
    }
  }

  Future<void> savePlaylist(List<AudioBook> playlist) async {
    try {
      print('Saving playlist with ${playlist.length} tracks');

      final playlistData = playlist.map((book) => {
        'id': book.id,
        'title': book.title,
        'author': book.author,
        'coverUrl': book.coverUrl,
        'audioUrl': book.audioUrl,
        'duration': book.duration.inMilliseconds,
        'position': book.position.inMilliseconds,
      }).toList();

      final file = File(_playlistFilePath);
      await file.writeAsString(jsonEncode(playlistData));
      print('Successfully saved playlist to file: $_playlistFilePath');
    } catch (e) {
      print('Error saving playlist: $e');
      print('Playlist file path: $_playlistFilePath');
    }
  }

  Future<List<AudioBook>> loadPlaylist() async {
    try {
      print('Loading playlist from: $_playlistFilePath');

      final file = File(_playlistFilePath);
      if (!await file.exists()) {
        print('Playlist file does not exist');
        return [];
      }

      final contents = await file.readAsString();
      print('Playlist file contents length: ${contents.length}');

      if (contents.trim().isEmpty) {
        print('Playlist file is empty');
        return [];
      }

      final List<dynamic> playlistData = jsonDecode(contents);
      print('Decoded playlist data: ${playlistData.length} items');

      final audioBooks = playlistData.map((data) {
        print('Loading track: ${data['title']} with position: ${data['position'] ?? 0}ms');
        return AudioBook(
          id: data['id'],
          title: data['title'],
          author: data['author'],
          coverUrl: data['coverUrl'],
          audioUrl: data['audioUrl'],
          duration: Duration(milliseconds: data['duration']),
          position: Duration(milliseconds: data['position'] ?? 0),
        );
      }).toList();

      print('Successfully loaded ${audioBooks.length} tracks from playlist');
      return audioBooks;
    } catch (e) {
      print('Error loading playlist: $e');
      print('Playlist file path: $_playlistFilePath');
      return [];
    }
  }

  Future<void> savePosition(String trackId, Duration position) async {
    try {
      print('Saving position for track: $trackId, position: ${position.inMinutes}:${position.inSeconds % 60}');

      Map<String, dynamic> positions = {};

      // Load existing positions
      final file = File(_positionsFilePath);
      if (await file.exists()) {
        final contents = await file.readAsString();
        positions = jsonDecode(contents);
        print('Loaded existing positions: ${positions.keys.length} tracks');
      } else {
        print('Positions file does not exist, creating new one');
      }

      // Update position for this track
      positions[trackId] = position.inMilliseconds;
      print('Updated position for $trackId: ${position.inMilliseconds}ms');

      // Save back to file
      await file.writeAsString(jsonEncode(positions));
      print('Successfully saved positions to file: $_positionsFilePath');
    } catch (e) {
      print('Error saving position: $e');
      print('Positions file path: $_positionsFilePath');
    }
  }

  Future<Duration> loadPosition(String trackId) async {
    try {
      print('Loading position for track: $trackId');

      final file = File(_positionsFilePath);
      if (!await file.exists()) {
        print('Positions file does not exist, returning zero position');
        return Duration.zero;
      }

      final contents = await file.readAsString();
      final Map<String, dynamic> positions = jsonDecode(contents);

      final milliseconds = positions[trackId] ?? 0;
      final position = Duration(milliseconds: milliseconds);

      print('Loaded position for $trackId: ${position.inMinutes}:${position.inSeconds % 60}');
      return position;
    } catch (e) {
      print('Error loading position: $e');
      return Duration.zero;
    }
  }

  Future<void> saveCurrentIndex(int index) async {
    try {
      final appDir = Directory.current;
      final dataDir = path.join(appDir.path, 'data');
      final indexFile = File(path.join(dataDir, 'current_index.json'));

      print('Saving current index: $index to ${indexFile.path}');

      // Убедимся, что директория существует
      final dir = Directory(dataDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      await indexFile.writeAsString(jsonEncode({'currentIndex': index}));
      print('Successfully saved current index: $index');
    } catch (e) {
      print('Error saving current index: $e');
    }
  }

  Future<int> loadCurrentIndex() async {
    try {
      final appDir = Directory.current;
      final dataDir = path.join(appDir.path, 'data');
      final indexFile = File(path.join(dataDir, 'current_index.json'));

      print('Loading current index from: ${indexFile.path}');

      if (!await indexFile.exists()) {
        print('Current index file does not exist, returning 0');
        return 0;
      }

      final contents = await indexFile.readAsString();
      final data = jsonDecode(contents);
      final index = data['currentIndex'] ?? 0;

      print('Loaded current index: $index');
      return index;
    } catch (e) {
      print('Error loading current index: $e');
      return 0;
    }
  }
}