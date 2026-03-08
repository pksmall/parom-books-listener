import 'package:audio_service/audio_service.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:parom_books_listener/services/logger_service.dart';
import 'dart:async';

class AudioPlayerHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  Function()? onTrackCompleted;
  
  // Cache position for synchronous access in broadcastState
  Duration _currentPosition = Duration.zero;
  Duration _currentDuration = Duration.zero;
  PlayerState _playerState = PlayerState.stopped;

  Duration? get duration => _currentDuration;

  /// Get current position directly from the native player (for polling on platforms
  /// where onPositionChanged is unreliable, e.g. Windows).
  Future<Duration> getCurrentPosition() async {
    final pos = await _player.getCurrentPosition();
    if (pos != null) {
      _currentPosition = pos;
    }
    return _currentPosition;
  }

  // Expose streams for UI if needed (mapping audioplayers streams)
  Stream<Duration> get positionStream => _player.onPositionChanged;
  Stream<Duration?> get durationStream => _player.onDurationChanged;
  Stream<PlayerState> get playerStateStream => _player.onPlayerStateChanged;

  // Callbacks for playlist navigation
  Function()? onSkipToNext;
  Function()? onSkipToPrevious;

  // Custom controls for seeking
  static final _seekBackwardControl = MediaControl(
    androidIcon: 'drawable/ic_action_replay_10',
    label: 'Rewind',
    action: MediaAction.rewind,
  );

  static final _seekForwardControl = MediaControl(
    androidIcon: 'drawable/ic_action_forward_10',
    label: 'Fast Forward',
    action: MediaAction.fastForward,
  );

  // Queue for sequential loading
  Future<void>? _loadingFuture;

  AudioPlayerHandler() {
    // Listen to state changes
    _player.onPlayerStateChanged.listen((state) {
      _playerState = state;
      _broadcastState(state);
      if (state == PlayerState.completed) {
        onTrackCompleted?.call();
      }
    });

    // Listen to position changes
    _player.onPositionChanged.listen((position) {
      _currentPosition = position;
      _broadcastState();
    });

    // Listen to duration changes
    _player.onDurationChanged.listen((duration) {
      if (duration != null) {
        _currentDuration = duration;
        // Update media item with new duration
        if (mediaItem.value != null) {
          mediaItem.add(mediaItem.value!.copyWith(duration: duration));
        }
      }
    });
  }

  void _broadcastState([PlayerState? state]) {
    state ??= _playerState;
    final playing = state == PlayerState.playing;
    
    AudioProcessingState processingState;
    switch (state) {
      case PlayerState.stopped:
        processingState = AudioProcessingState.idle;
        break;
      case PlayerState.playing:
      case PlayerState.paused:
        processingState = AudioProcessingState.ready;
        break;
      case PlayerState.completed:
        processingState = AudioProcessingState.completed;
        break;
      case PlayerState.disposed:
        processingState = AudioProcessingState.idle;
        break;
      default:
        processingState = AudioProcessingState.idle;
    }

    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        _seekBackwardControl,
        if (playing) MediaControl.pause else MediaControl.play,
        _seekForwardControl,
        MediaControl.skipToNext,
      ],
      systemActions: {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.fastForward,
        MediaAction.rewind,
      },
      androidCompactActionIndices: const [0, 2, 4], // Prev, Play/Pause, Next
      processingState: processingState,
      playing: playing,
      updatePosition: _currentPosition,
      bufferedPosition: Duration.zero, // audioplayers doesn't provide buffered position easily
      speed: 1.0,
      queueIndex: 0,
    ));
  }

  // Переопределяем действия медиа кнопок
  @override
  Future<void> play() => _player.resume();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    logDebug('AudioPlayerHandler', 'skipToNext called');
    if (onSkipToNext != null) {
      onSkipToNext!();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    logDebug('AudioPlayerHandler', 'skipToPrevious called');
    if (onSkipToPrevious != null) {
      onSkipToPrevious!();
    }
  }

  @override
  Future<void> fastForward() async {
    final currentPosition = await _player.getCurrentPosition() ?? _currentPosition;
    var newPosition = currentPosition + const Duration(seconds: 10);
    if (_currentDuration != Duration.zero && newPosition > _currentDuration) {
      newPosition = _currentDuration;
    }
    await _player.seek(newPosition);
  }

  @override
  Future<void> rewind() async {
    final currentPosition = await _player.getCurrentPosition() ?? _currentPosition;
    var newPosition = currentPosition - const Duration(seconds: 10);
    if (newPosition < Duration.zero) {
      newPosition = Duration.zero;
    }
    await _player.seek(newPosition);
  }

  @override
  Future<void> seekForward(bool begin) => fastForward();

  @override
  Future<void> seekBackward(bool begin) => rewind();

  Future<void> setAudioSource(String url) async {
    // Chain the new request to the end of the previous one to ensure sequential execution
    final previousFuture = _loadingFuture;
    final completer = Completer<void>();
    _loadingFuture = completer.future;

    try {
      if (previousFuture != null) {
        try {
          await previousFuture;
        } catch (e) {
          // Ignore errors from previous load
        }
      }

      logDebug('AudioPlayerHandler', 'Setting audio source: $url');
      
      // Small delay to allow native side to settle
      await Future.delayed(const Duration(milliseconds: 100));
      
      await _player.stop();
      
      // Set source
      await _player.setSource(DeviceFileSource(url));
      
      // Attempt to get duration
      final duration = await _player.getDuration();
      if (duration != null) {
        _currentDuration = duration;
      }
      
      mediaItem.add(MediaItem(
        id: url,
        album: "AudioBook",
        title: url.split('/').last,
        duration: duration ?? Duration.zero,
      ));
    } catch (e) {
      logError("setAudioSource", "Error setting audio source: ", e);
    } finally {
      completer.complete();
    }
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }
}