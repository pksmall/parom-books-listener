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
  bool _isNavigating = false; // Флаг для предотвращения множественных вызовов

  // Callback for auto-play when positions are loaded
  Function(Duration position)? onAutoPlayRequested;
  bool _shouldAutoPlay = false;

  List<AudioBook> get playlist => _playlist;
  int get currentIndex => _currentIndex;
  AudioBook? get currentAudioBook =>
      _playlist.isNotEmpty && _currentIndex >= 0 && _currentIndex < _playlist.length
          ? _playlist[_currentIndex]
          : null;

  bool get shouldAutoPlay => _shouldAutoPlay;

  void setAutoPlayCallback(Function(Duration position)? callback) {
    onAutoPlayRequested = callback;
  }

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
      logDebug('initialize', 'Loaded playlist with ${_playlist.length} tracks, current index: $_currentIndex');

      // Check if we should auto-play based on saved position
      await _checkAndRequestAutoPlay();

      notifyListeners();
    }

    _isInitialized = true;
  }

  Future<void> _checkAndRequestAutoPlay() async {
    if (currentAudioBook == null) return;

    try {
      // Check if there's a saved position for the current track
      final savedPosition = await loadTrackPosition(currentAudioBook!.id);

      if (savedPosition > Duration.zero) {
        logInfo('_checkAndRequestAutoPlay', 'Found saved position for current track: ${currentAudioBook!.title} at ${savedPosition.inMinutes}:${savedPosition.inSeconds % 60}');

        // Update the current audio book position
        currentAudioBook!.position = savedPosition;

        // Set auto-play flag
        _shouldAutoPlay = true;

        // Trigger auto-play callback if available
        if (onAutoPlayRequested != null) {
          logInfo('_checkAndRequestAutoPlay', 'Requesting auto-play at position: ${savedPosition.inMinutes}:${savedPosition.inSeconds % 60}');
          onAutoPlayRequested!(savedPosition);
        } else {
          logDebug('_checkAndRequestAutoPlay', 'Auto-play callback not set, will auto-play when player is ready');
        }
      } else {
        logDebug('_checkAndRequestAutoPlay', 'No saved position found for current track, no auto-play needed');
      }
    } catch (e) {
      logError('_checkAndRequestAutoPlay', 'Error checking for auto-play:', e);
    }
  }

  // Method to be called when the media player is ready
  Future<void> onPlayerReady() async {
    if (_shouldAutoPlay && currentAudioBook != null) {
      final position = currentAudioBook!.position;
      if (position > Duration.zero) {
        logInfo('onPlayerReady', 'Auto-playing at saved position: ${position.inMinutes}:${position.inSeconds % 60}');

        if (onAutoPlayRequested != null) {
          onAutoPlayRequested!(position);
        }

        _shouldAutoPlay = false; // Reset flag after auto-play
      }
    }
  }

  // Reset auto-play flag
  void resetAutoPlay() {
    _shouldAutoPlay = false;
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
    if (_isNavigating) {
      logDebug('setCurrentIndex', 'Navigation in progress, ignoring request');
      return;
    }

    if (index >= 0 && index < _playlist.length && index != _currentIndex) {
      _isNavigating = true;

      logDebug('setCurrentIndex', 'Changing index from $_currentIndex to $index');

      // Save current position before switching
      _saveCurrentPositionImmediately();

      _currentIndex = index;
      notifyListeners();
      _scheduleSave();

      // Stop old timer and start new one for the new track
      _positionSaveTimer?.cancel();
      _positionSaveTimer = null;
      _ensurePositionSaveTimer();

      _isNavigating = false;
      logDebug('setCurrentIndex', 'Index changed successfully to $_currentIndex');
    } else {
      logDebug('setCurrentIndex', 'Invalid index or same as current: $index (current: $_currentIndex, playlist length: ${_playlist.length})');
    }
  }

  void nextTrack() {
    if (_isNavigating) {
      logDebug('nextTrack', 'Navigation in progress, ignoring request');
      return;
    }

    if (!hasNextTrack) {
      logDebug('nextTrack', 'No next track available (current: $_currentIndex, playlist length: ${_playlist.length})');
      return;
    }

    _isNavigating = true;
    logDebug('nextTrack', 'Moving from track $_currentIndex to ${_currentIndex + 1}');

    // Save current position before switching
    _saveCurrentPositionImmediately();

    _currentIndex++;
    logInfo('nextTrack', 'Moved to next track: $_currentIndex/${_playlist.length}');

    notifyListeners();
    _scheduleSave();

    // Stop old timer and start new one for the new track
    _positionSaveTimer?.cancel();
    _positionSaveTimer = null;
    _ensurePositionSaveTimer();

    _isNavigating = false;
  }

  bool get hasNextTrack => _currentIndex < _playlist.length - 1;

  void previousTrack() {
    if (_isNavigating) {
      logDebug('previousTrack', 'Navigation in progress, ignoring request');
      return;
    }

    if (!hasPreviousTrack) {
      logDebug('previousTrack', 'No previous track available (current: $_currentIndex)');
      return;
    }

    _isNavigating = true;
    logDebug('previousTrack', 'Moving from track $_currentIndex to ${_currentIndex - 1}');

    // Save current position before switching
    _saveCurrentPositionImmediately();

    _currentIndex--;
    logInfo('previousTrack', 'Moved to previous track: $_currentIndex/${_playlist.length}');

    notifyListeners();
    _scheduleSave();

    // Stop old timer and start new one for the new track
    _positionSaveTimer?.cancel();
    _positionSaveTimer = null;
    _ensurePositionSaveTimer();

    _isNavigating = false;
  }

  bool get hasPreviousTrack => _currentIndex > 0;

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

  // Updated clearPlaylist method with complete data clearing
  Future<void> clearPlaylist() async {
    if (_isNavigating) {
      logDebug('clearPlaylist', 'Navigation in progress, deferring clear');
      return;
    }

    try {
      logInfo('clearPlaylist', 'Starting complete playlist and history clear');

      // Stop position timer
      _positionSaveTimer?.cancel();
      _positionSaveTimer = null;

      // Clear in-memory data
      _playlist.clear();
      _currentIndex = 0;
      _shouldAutoPlay = false; // Reset auto-play flag

      // Clear all saved data files (playlist, positions, current index)
      await _playlistService.clearAllData();

      logInfo('clearPlaylist', 'Playlist and all history cleared completely');
      notifyListeners();
    } catch (e) {
      logError('clearPlaylist', 'Error clearing playlist and history:', e);
      // Even if file clearing fails, we still clear the memory
      notifyListeners();
    }
  }

  // Additional method to clear only positions (keep playlist)
  Future<void> clearAllPositions() async {
    try {
      logInfo('clearAllPositions', 'Clearing all track positions');

      // Clear positions in memory
      for (final book in _playlist) {
        book.position = Duration.zero;
      }

      // Clear positions file
      await _playlistService.clearPositionsData();

      _shouldAutoPlay = false; // Reset auto-play flag

      logInfo('clearAllPositions', 'All positions cleared');
      notifyListeners();
    } catch (e) {
      logError('clearAllPositions', 'Error clearing positions:', e);
    }
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
    onAutoPlayRequested = null;
    super.dispose();
  }
}