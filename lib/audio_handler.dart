import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

class AudioPlayerHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  Function()? onTrackCompleted;

  Duration? get duration => _player.duration;

  Stream<Duration> get positionStream => _player.positionStream;

  AudioPlayerHandler() {
    _player.playbackEventStream.listen((PlaybackEvent event) {
      _broadcastState();
    });

    _player.positionStream.listen((position) {
      _broadcastState();
    });

    _player.playerStateStream.listen((playerState) {
      _broadcastState();

      // Check if track completed and call callback
      if (playerState.processingState == ProcessingState.completed) {
        onTrackCompleted?.call();
      }
    });
  }

  void _broadcastState() {
    final playing = _player.playing;
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: 0,
    ));
  }

  // Переопределяем действия медиа кнопок
  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  // Переопределяем действия next/previous для перемотки на 10 секунд
  @override
  Future<void> skipToNext() async {
    final position = _player.position;
    final newPosition = position + const Duration(seconds: 10);
    await _player.seek(newPosition);
  }

  @override
  Future<void> skipToPrevious() async {
    final position = _player.position;
    final newPosition = position - const Duration(seconds: 10);
    await _player.seek(newPosition);
  }

  Future<void> setAudioSource(String url) async {
    try {
      await _player.setFilePath(url);
      await Future.delayed(Duration(milliseconds: 500)); // Даем время на загрузку
      final duration = _player.duration ?? Duration.zero;

      mediaItem.add(MediaItem(
        id: url,
        album: "AudioBook",
        title: url.split('/').last,
        duration: duration,
      ));
    } catch (e) {
      print("Error setting audio source: $e");
    }
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> dispose() async {
    await _player.dispose();
  }
}
