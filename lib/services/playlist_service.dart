import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import '../services/logger_service.dart';
import '../models/audio_book.dart';

class PlaylistService {
  static const String _playlistFileName = 'playlist.json';
  static const String _positionsFileName = 'positions.json';
  static const String _currentIndexFileName = 'current_index.json';
  late String _playlistFilePath;
  late String _positionsFilePath;
  late String _currentIndexFilePath;

  Future<void> init() async {
    try {
      final appDir = Directory.current;
      final dataDir = path.join(appDir.path, 'data');

      _playlistFilePath = path.join(dataDir, _playlistFileName);
      _positionsFilePath = path.join(dataDir, _positionsFileName);
      _currentIndexFilePath = path.join(dataDir, _currentIndexFileName);

      logDebug('init', 'PlaylistService init - Data directory: ', dataDir);
      logDebug('init', 'PlaylistService init - Playlist file: ', _playlistFilePath);
      logDebug('init', 'PlaylistService init - Positions file: ', _positionsFilePath);
      logDebug('init', 'PlaylistService init - Current index file: ', _currentIndexFilePath);

      // Create directory if it doesn't exist
      final dir = Directory(path.dirname(_playlistFilePath));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
        logDebug('init', 'PlaylistService init - Created data directory: ', dir.path);
      } else {
        logDebug('init', 'PlaylistService init - Data directory already exists');
      }
    } catch (e) {
      logError('init', 'Error in PlaylistService.init(): ', e);
      rethrow;
    }
  }

  Future<void> savePlaylist(List<AudioBook> playlist) async {
    try {
      logDebug('savePlaylist', 'Saving playlist with ${playlist.length} tracks');

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
      logDebug('savePlaylist', 'Successfully saved playlist to file: ', _playlistFilePath);
    } catch (e) {
      logError('savePlaylist', 'Error saving playlist: ', e);
      logError('savePlaylist', 'Playlist file path: ', _playlistFilePath);
    }
  }

  Future<List<AudioBook>> loadPlaylist() async {
    try {
      logDebug('loadPlaylist', 'Loading playlist from: $_playlistFilePath');

      final file = File(_playlistFilePath);
      if (!await file.exists()) {
        logDebug('loadPlaylist', 'Playlist file does not exist');
        return [];
      }

      final contents = await file.readAsString();
      logDebug('loadPlaylist', 'Playlist file contents length: ${contents.length}');

      if (contents.trim().isEmpty) {
        logDebug('loadPlaylist', 'Playlist file is empty');
        return [];
      }

      final List<dynamic> playlistData = jsonDecode(contents);
      logDebug('loadPlaylist', 'Decoded playlist data: ${playlistData.length} items');

      final audioBooks = playlistData.map((data) {
        logDebug('loadPlaylist', 'Loading track: ${data['title']} with position: ${data['position'] ?? 0}ms');
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

      logDebug('loadPlaylist', 'Successfully loaded ${audioBooks.length} tracks from playlist');
      return audioBooks;
    } catch (e) {
      logError('loadPlaylist', 'Error loading playlist: ', e);
      logError('loadPlaylist', 'Playlist file path: ', _playlistFilePath);
      return [];
    }
  }

  Future<void> saveCurrentIndex(int index) async {
    try {
      logDebug('saveCurrentIndex', 'Saving current index: $index');
      final file = File(_currentIndexFilePath);
      await file.writeAsString(jsonEncode({'currentIndex': index}));
      logDebug('saveCurrentIndex', 'Successfully saved current index to file: $_currentIndexFilePath');
    } catch (e) {
      logDebug('saveCurrentIndex', 'Error saving current index: $e');
    }
  }

  Future<int> loadCurrentIndex() async {
    try {
      logDebug('loadCurrentIndex', 'Loading current index from: $_currentIndexFilePath');

      final file = File(_currentIndexFilePath);
      if (!await file.exists()) {
        logDebug('loadCurrentIndex', 'Current index file does not exist, returning 0');
        return 0;
      }

      final contents = await file.readAsString();
      if (contents.trim().isEmpty) {
        logDebug('loadCurrentIndex', 'Current index file is empty, returning 0');
        return 0;
      }

      final data = jsonDecode(contents);
      final index = data['currentIndex'] ?? 0;
      logDebug('loadCurrentIndex', 'Successfully loaded current index: $index');
      return index;
    } catch (e) {
      logError('loadCurrentIndex', 'Error loading current index: ', e);
      return 0;
    }
  }

  Future<void> savePosition(String trackId, Duration position) async {
    try {
      logDebug('savePosition', 'Saving position for track: $trackId, position: ${position.inMinutes}:${position.inSeconds % 60}');

      Map<String, dynamic> positions = {};

      // Load existing positions
      final file = File(_positionsFilePath);
      if (await file.exists()) {
        final contents = await file.readAsString();
        if (contents.trim().isNotEmpty) {
          positions = jsonDecode(contents);
        }
        logDebug('savePosition', 'Loaded existing positions: ${positions.keys.length} tracks');
      } else {
        logDebug('savePosition', 'Positions file does not exist, creating new one');
      }

      // Update position for this track
      positions[trackId] = position.inMilliseconds;
      logDebug('savePosition', 'Updated position for $trackId: ${position.inMilliseconds}ms');

      // Save back to file
      await file.writeAsString(jsonEncode(positions));
      logDebug('savePosition', 'Successfully saved positions to file: $_positionsFilePath');
    } catch (e) {
      logError('savePosition', 'Error saving position: ', e);
      logError('savePosition', 'Positions file path: ', _positionsFilePath);
    }
  }

  Future<Duration> loadPosition(String trackId) async {
    try {
      logDebug('loadPosition', 'Loading position for track: ', trackId);

      final file = File(_positionsFilePath);
      if (!await file.exists()) {
        logDebug('loadPosition','Positions file does not exist');
        return Duration.zero;
      }

      final contents = await file.readAsString();
      if (contents.trim().isEmpty) {
        logDebug('loadPosition', 'Positions file is empty');
        return Duration.zero;
      }

      final Map<String, dynamic> positions = jsonDecode(contents);
      logDebug('loadPosition', 'Loaded positions for ${positions.keys.length} tracks');

      final positionMs = positions[trackId];
      if (positionMs != null) {
        final position = Duration(milliseconds: positionMs);
        logDebug('loadPosition', 'Found saved position for $trackId: ${position.inMinutes}:${position.inSeconds % 60}');
        return position;
      } else {
        logDebug('loadPosition', 'No saved position found for $trackId');
        return Duration.zero;
      }
    } catch (e) {
      logError('loadPosition','Error loading position: ', e);
      return Duration.zero;
    }
  }

  // New methods for complete data clearing
  Future<void> clearAllData() async {
    try {
      logDebug('clearAllData', 'Clearing all saved data...');

      await _deleteFile(_playlistFilePath, 'playlist');
      await _deleteFile(_positionsFilePath, 'positions');
      await _deleteFile(_currentIndexFilePath, 'current index');

      logDebug('clearAllData', 'All saved data cleared successfully');
    } catch (e) {
      logError('clearAllData', 'Error clearing all data: ', e);
      rethrow;
    }
  }

  Future<void> clearPlaylistData() async {
    try {
      logDebug('clearPlaylistData', 'Clearing playlist data...');

      await _deleteFile(_playlistFilePath, 'playlist');
      await _deleteFile(_currentIndexFilePath, 'current index');

      logDebug('clearPlaylistData', 'Playlist data cleared successfully');
    } catch (e) {
      logError('clearPlaylistData', 'Error clearing playlist data: ', e);
      rethrow;
    }
  }

  Future<void> clearPositionsData() async {
    try {
      logDebug('clearPositionsData', 'Clearing positions data...');

      await _deleteFile(_positionsFilePath, 'positions');

      logDebug('clearPositionsData', 'Positions data cleared successfully');
    } catch (e) {
      logError('clearPositionsData', 'Error clearing positions data: ', e);
      rethrow;
    }
  }

  Future<void> _deleteFile(String filePath, String fileDescription) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        logDebug('_deleteFile', 'Deleted $fileDescription file: $filePath');
      } else {
        logError('_deleteFile', '$fileDescription file does not exist: $filePath');
      }
    } catch (e) {
      logError('_deleteFile', 'Error deleting $fileDescription file: ', e);
      rethrow;
    }
  }

  // Method to check if any saved data exists
  Future<bool> hasSavedData() async {
    try {
      final playlistExists = await File(_playlistFilePath).exists();
      final positionsExists = await File(_positionsFilePath).exists();
      final indexExists = await File(_currentIndexFilePath).exists();

      return playlistExists || positionsExists || indexExists;
    } catch (e) {
      logError('hasSavedData', 'Error checking for saved data: ', e);
      return false;
    }
  }
}