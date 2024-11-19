import 'package:flutter/foundation.dart';
import 'models/audio_book.dart';

class PlaylistProvider extends ChangeNotifier {
  final List<AudioBook> _playlist = [];
  int _currentIndex = 0;

  List<AudioBook> get playlist => _playlist;
  int get currentIndex => _currentIndex;
  AudioBook? get currentAudioBook =>
      _playlist.isNotEmpty ? _playlist[_currentIndex] : null;

  void addAudioBooks(List<AudioBook> books) {
    _playlist.addAll(books);
    notifyListeners();
  }

  void setCurrentIndex(int index) {
    if (index >= 0 && index < _playlist.length) {
      _currentIndex = index;
      notifyListeners();
    }
  }

  void nextTrack() {
    if (_currentIndex < _playlist.length - 1) {
      _currentIndex++;
      notifyListeners();
    }
  }

  void previousTrack() {
    if (_currentIndex > 0) {
      _currentIndex--;
      notifyListeners();
    }
  }

  void clearPlaylist() {
    _playlist.clear();
    _currentIndex = 0;
    notifyListeners();
  }
}
