import 'package:flutter/foundation.dart';
import 'package:parom_books_listener/services/logger_service.dart';
import 'models/audio_book.dart';
import 'services/playlist_service.dart';
import 'services/settings_service.dart';
import 'dart:async';

class PlaylistProvider extends ChangeNotifier {
  final List<AudioBook> _playlist = [];
  int _currentIndex = 0;
  final PlaylistService _playlistService = PlaylistService();
  final SettingsService _settingsService = SettingsService();
  Timer? _saveTimer;
  Timer? _positionSaveTimer;
  bool _isInitialized = false;

  List<AudioBook> get playlist => _playlist;
  int get currentIndex => _currentIndex;
  AudioBook? get currentAudioBook =>
      _playlist.isNotEmpty ? _playlist[_currentIndex] : null;

  Future<void> initialize() async {
    if (_isInitialized) return;

    await _playlistService.init();
    await _settingsService.init();

    // Load saved playlist and current index
    final savedPlaylist = await _playlistService.loadPlaylist();
    final savedIndex = await _playlistService.loadCurrentIndex();

    if (savedPlaylist.isNotEmpty) {
      _playlist.addAll(savedPlaylist);
      _currentIndex = savedIndex.clamp(0, _playlist.length - 1);
      notifyListeners();
    }

    _isInitialized = true;
  }

  void addAudioBooks(List<AudioBook> books) {
    logInfo('addAudioBooks', 'Adding ${books.length} audio books to playlist');
    _playlist.addAll(books);
    notifyListeners();

    // Сохраняем немедленно при добавлении файлов
    _savePlaylistImmediately();
  }

  Future<void> _savePlaylistImmediately() async {
    try {
      final settings = await _settingsService.loadSettings();
      logDebug('_savePlaylistImmediately', 'Immediately saving playlist - autoSave: ${settings['autoSavePlaylist']}');

      if (settings['autoSavePlaylist']) {
        await _playlistService.savePlaylist(_playlist);
        await _playlistService.saveCurrentIndex(_currentIndex);
        logDebug('_savePlaylistImmediately', 'Playlist immediately saved with ${_playlist.length} tracks');
      }
    } catch (e) {
      logError('_savePlaylistImmediately', 'Error in immediate playlist save:', e);
    }
  }

  void setCurrentIndex(int index) {
    if (index >= 0 && index < _playlist.length) {
      // Save current position before switching
      _saveCurrentPositionImmediately();

      _currentIndex = index;
      notifyListeners();
      _scheduleSave();

      // Stop old timer and start new one for the new track
      _positionSaveTimer?.cancel();
      _positionSaveTimer = null;
      _ensurePositionSaveTimer();
    }
  }

  void nextTrack() {
    if (_currentIndex < _playlist.length - 1) {
      // Save current position before switching
      _saveCurrentPositionImmediately();

      _currentIndex++;
      notifyListeners();
      _scheduleSave();

      // Stop old timer and start new one for the new track
      _positionSaveTimer?.cancel();
      _positionSaveTimer = null;
      _ensurePositionSaveTimer();
    }
  }

  bool get hasNextTrack => _currentIndex < _playlist.length - 1;

  void previousTrack() {
    if (_currentIndex > 0) {
      // Save current position before switching
      _saveCurrentPositionImmediately();

      _currentIndex--;
      notifyListeners();
      _scheduleSave();

      // Stop old timer and start new one for the new track
      _positionSaveTimer?.cancel();
      _positionSaveTimer = null;
      _ensurePositionSaveTimer();
    }
  }

  // Methods to control position saving timer based on playback state
  void startPositionSaveTimer() {
    _ensurePositionSaveTimer();
  }

  void stopPositionSaveTimer() {
    _positionSaveTimer?.cancel();
    _positionSaveTimer = null;
    logDebug("stopPositionSaveTimer", "Position save timer stopped");
  }

  Future<void> forceSave() async {
    await _savePlaylist();
    await _saveCurrentPosition();
  }

  void saveCurrentTrackPosition(Duration position) {
    if (_playlist.isNotEmpty && currentAudioBook != null) {
      logDebug('saveCurrentTrackPosition', 'Saving position for track: ${currentAudioBook!.title} to ${position.inMinutes}:${position.inSeconds % 60}');
      currentAudioBook!.position = position; // Update position in memory
      _saveTrackPosition(currentAudioBook!.id, position);
    }
  }

  void clearPlaylist() {
    // Save current position before clearing
    _saveCurrentPositionImmediately();

    // Stop position timer
    _positionSaveTimer?.cancel();
    _positionSaveTimer = null;

    _playlist.clear();
    _currentIndex = 0;
    notifyListeners();
    _scheduleSave();
  }

  void updateCurrentTrackPosition(Duration position) {
    if (_playlist.isNotEmpty && currentAudioBook != null) {
      logDebug('updateCurrentTrackPosition', 'Updating position for track: ${currentAudioBook!.title} to ${position.inMinutes}:${position.inSeconds % 60}');
      currentAudioBook!.position = position;
      // Don't restart timer here - it should be managed by play/pause state
    } else {
      logDebug('updateCurrentTrackPosition', 'Cannot update position: playlist empty or no current track');
    }
  }

  void _ensurePositionSaveTimer() async {
    final settings = await _settingsService.loadSettings();
    if (!settings['autoSavePosition']) {
      _positionSaveTimer?.cancel();
      _positionSaveTimer = null;
      return;
    }

    // If timer is already running, don't create a new one
    if (_positionSaveTimer != null && _positionSaveTimer!.isActive) {
      return;
    }

    final timeoutSeconds = (settings['positionSaveTimeout'] as int);
    logDebug("_ensurePositionSaveTimer", "Starting periodic position save timer for $timeoutSeconds sec intervals");

    _positionSaveTimer = Timer.periodic(Duration(seconds: timeoutSeconds), (timer) async {
      try {
        await _saveCurrentPosition();
        logDebug("_ensurePositionSaveTimer", "Position saved by periodic timer");
      } catch (e) {
        logError("_ensurePositionSaveTimer", "Error saving position by periodic timer:", e);
      }
    });
  }

  Future<Duration> loadTrackPosition(String trackId) async {
    try {
      final savedPosition = await _playlistService.loadPosition(trackId);
      logDebug('loadTrackPosition', 'PlaylistProvider: Loaded saved position for $trackId: ${savedPosition.inMinutes}:${savedPosition.inSeconds % 60}');
      return savedPosition;
    } catch (e) {
      logError('loadTrackPosition', 'PlaylistProvider: Error loading track position:', e);
      return Duration.zero;
    }
  }

  Future<void> _saveTrackPosition(String trackId, Duration position) async {
    try {
      final settings = await _settingsService.loadSettings();
      if (settings['autoSavePosition']) {
        await _playlistService.savePosition(trackId, position);
      }
    } catch (e) {
      logError('_saveTrackPosition', 'Error saving track position: ', e);
    }
  }

  void _scheduleSave() async {
    final settings = await _settingsService.loadSettings();
    if (!settings['autoSavePlaylist']) return;

    _saveTimer?.cancel();
    _saveTimer = Timer(Duration(seconds: settings['playlistSaveTimeout']), () {
      _savePlaylist();
    });
  }

  void _schedulePositionSave() async {
    final settings = await _settingsService.loadSettings();
    if (!settings['autoSavePosition']) return;

    _positionSaveTimer?.cancel();

    // Минимальный порог 1 секунда
    final timeoutSeconds = (settings['positionSaveTimeout'] as int);

    logDebug("_schedulePositionSave", "Scheduling position save for $timeoutSeconds sec");
    _positionSaveTimer = Timer(Duration(seconds: timeoutSeconds), () async {
      // Сохраняем в фоне
      try {
        await _saveCurrentPosition();
        logDebug("_schedulePositionSave", "Position saved in background");
      } catch (e) {
        logError("_schedulePositionSave", "Error saving position in background: ", e);
      }
    });
  }

  Future<void> _savePlaylist() async {
    try {
      final settings = await _settingsService.loadSettings();
      logDebug('_savePlaylist', 'Settings - autoSavePlaylist: ${settings['autoSavePlaylist']}');

      if (settings['autoSavePlaylist']) {
        logDebug('_savePlaylist', 'Saving playlist with ${_playlist.length} tracks, current index: $_currentIndex');
        await _playlistService.savePlaylist(_playlist);
        await _playlistService.saveCurrentIndex(_currentIndex);
      } else {
        logDebug('_savePlaylist', 'Not saving playlist - autoSave disabled');
      }
    } catch (e) {
      logError('_savePlaylist', 'Error in _savePlaylist: ', e);
    }
  }

  Future<void> _saveCurrentPosition() async {
    try {
      final settings = await _settingsService.loadSettings();
      logDebug('_saveCurrentPosition', 'Settings - autoSavePosition: ${settings['autoSavePosition']}');

      if (settings['autoSavePosition'] && currentAudioBook != null) {
        logDebug('_saveCurrentPosition', 'Saving current position for: ${currentAudioBook!.title}');
        await _playlistService.savePosition(
          currentAudioBook!.id,
          currentAudioBook!.position,
        );
      } else {
        logDebug('_saveCurrentPosition', 'Not saving position - autoSave: ${settings['autoSavePosition']}, currentBook: ${currentAudioBook != null}');
      }
    } catch (e) {
      logError('_saveCurrentPosition', 'Error in _saveCurrentPosition: ' , e);
    }
  }


  Future<void> _saveCurrentPositionImmediately() async {
    try {
      final settings = await _settingsService.loadSettings();
      if (settings['autoSavePosition'] && currentAudioBook != null) {
        logDebug('_saveCurrentPositionImmediately', 'Immediately saving position for: ${currentAudioBook!.title} at ${currentAudioBook!.position.inMinutes}:${currentAudioBook!.position.inSeconds % 60}');
        await _playlistService.savePosition(
          currentAudioBook!.id,
          currentAudioBook!.position,
        );
      }
    } catch (e) {
      logError('_saveCurrentPositionImmediately', 'Error in immediate position save: ', e);
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _positionSaveTimer?.cancel();
    super.dispose();
  }
}
