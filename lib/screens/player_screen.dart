import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audio_service/audio_service.dart';
import '../playlist_provider.dart';
import '../services/logger_service.dart';
import '../widgets/app_menu.dart';
import '../audio_handler.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  _PlayerScreenState createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with WidgetsBindingObserver {
  Duration position = Duration.zero;
  Duration? duration;
  bool isPlaying = false;
  bool isLoading = false;
  String? errorMessage;
  bool _isOperationInProgress = false;
  bool _isDisposed = false;

  Timer? _positionPollingTimer;
  Timer? _stateDebounceTimer;

  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<PlaybackState>? _playerStateSubscription;

  AudioPlayerHandler get _audioHandler => Provider.of<AudioPlayerHandler>(context, listen: false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeAudioHandler();
  }

  Future<void> _initializeAudioHandler() async {
    if (_isDisposed) return;

    try {
      await _setupStreamListeners();
      await _loadAudio();
      logDebug('_initializeAudioHandler', 'Audio handler initialized successfully');
    } catch (e) {
      logError('_initializeAudioHandler', 'Failed to init audio handler', e);
      if (mounted && !_isDisposed) {
        setState(() {
          errorMessage = 'Failed to init audio handler: $e';
          _isOperationInProgress = false;
        });
      }
    }
  }

  Future<void> _setupStreamListeners() async {
    if (_isDisposed) return;

    try {
      // NOTE: We do NOT subscribe to positionStream because
      // audioplayers' onPositionChanged is unreliable on Windows
      // (events sent from non-platform thread). Instead, we poll
      // getCurrentPosition() in _startPositionPolling().

      _durationSubscription = _audioHandler.durationStream.listen(
            (newDuration) {
          if (!_isDisposed && mounted && newDuration != null) {
            setState(() => duration = newDuration);
          }
        },
        onError: (error) => logError('_setupStreamListeners', 'Duration stream error (ignored)', error),
      );

      _playerStateSubscription = _audioHandler.playbackState.listen(
            (playbackState) {
          if (!_isDisposed && mounted) {
            try {
              if (playbackState.processingState == AudioProcessingState.completed) {
                _handleTrackCompletion();
              }

              final newLoading = playbackState.processingState == AudioProcessingState.loading ||
                  playbackState.processingState == AudioProcessingState.buffering;

              if (isLoading != newLoading) {
                setState(() {
                  isLoading = newLoading;
                  if (!newLoading) _isOperationInProgress = false;
                });
              }

              final newPlaying = playbackState.playing;
              if (isPlaying != newPlaying) {
                if (!_isDisposed && mounted) {
                  try {
                    setState(() => isPlaying = newPlaying);
                    if (newPlaying) {
                      _startPositionPolling();
                    } else {
                      _stopPositionPolling();
                    }
                  } catch (e) {
                    logError('_setupStreamListeners', 'Playing update error', e);
                  }
                }
              }
            } catch (e) {
              logError('_setupStreamListeners', 'Player state update error', e);
            }
          }
        },
        onError: (error) => logError('_setupStreamListeners', 'Player state stream error (ignored)', error),
      );
    } catch (e) {
      logError('_setupStreamListeners', 'Error setting up listeners', e);
    }
  }

  // Track completion is now handled by PlaylistProvider via AudioHandler callbacks
  void _handleTrackCompletion() {
    // UI update if needed, but logic is in Provider
  }

  Future<void> _loadAudio({bool shouldAutoplay = false}) async {
    if (_isDisposed) return;

    try {
      _isOperationInProgress = true;
      setState(() {
        isLoading = true;
        errorMessage = null;
      });

      final playlistProvider = Provider.of<PlaylistProvider>(context, listen: false);
      final currentBook = playlistProvider.currentAudioBook;

      if (currentBook == null) {
        setState(() {
          errorMessage = 'No audio file selected';
          isLoading = false;
          _isOperationInProgress = false;
        });
        return;
      }

      logInfo('_loadAudio', 'Loading audio: ${currentBook.title}, shouldAutoplay: $shouldAutoplay');

      final savedPosition = await _loadTrackPosition(currentBook.id);

      await _audioHandler.setAudioSource(currentBook.audioUrl);

      Duration? audioDuration = _audioHandler.duration;
      if (audioDuration == null) {
        for (int i = 0; i < 10 && audioDuration == null && !_isDisposed; i++) {
          await Future.delayed(const Duration(milliseconds: 100));
          audioDuration = _audioHandler.duration;
        }
      }

      if (audioDuration != null) {
        setState(() {
          duration = audioDuration;
          position = savedPosition;
          isLoading = false;
        });

        if (savedPosition > Duration.zero && savedPosition < audioDuration) {
          await _audioHandler.seek(savedPosition);
          logInfo('_loadAudio', 'Seeked to saved position: ${savedPosition.inMinutes}:${savedPosition.inSeconds % 60}');
        }

        if (shouldAutoplay) {
          await _audioHandler.play();
          logInfo('_loadAudio', 'Started auto-play');
        }
      } else {
        setState(() {
          errorMessage = 'Failed to get audio duration';
          isLoading = false;
        });
      }

      setState(() => _isOperationInProgress = false);
    } catch (e) {
      logError('_loadAudio', 'Error loading audio', e);
      if (mounted && !_isDisposed) {
        setState(() {
          errorMessage = 'Error loading audio: $e';
          isLoading = false;
          _isOperationInProgress = false;
        });
      }
    } finally {
      if (mounted && !_isDisposed) {
        setState(() => _isOperationInProgress = false);
      }
    }
  }

  Future<Duration> _loadTrackPosition(String trackId) async {
    try {
      final playlistProvider = Provider.of<PlaylistProvider>(context, listen: false);
      return await playlistProvider.loadTrackPosition(trackId);
    } catch (e) {
      logError('_loadTrackPosition', 'Error loading track position', e);
      return Duration.zero;
    }
  }

  void _saveCurrentPosition() {
    if (_isDisposed) return;
    try {
      final playlistProvider = Provider.of<PlaylistProvider>(context, listen: false);
      playlistProvider.updateCurrentTrackPosition(position);
    } catch (e) {
      logError('_saveCurrentPosition', 'Error saving current position', e);
    }
  }

  Future<void> _skipBackward() async {
    if (_isOperationInProgress || _isDisposed) return;
    // Immediately update UI position
    final newPos = position - const Duration(seconds: 10);
    setState(() {
      position = newPos < Duration.zero ? Duration.zero : newPos;
    });
    await _audioHandler.rewind();
    _saveCurrentPosition();
  }

  Future<void> _skipForward() async {
    if (_isOperationInProgress || _isDisposed) return;
    // Immediately update UI position
    final maxDur = duration ?? position;
    final newPos = position + const Duration(seconds: 10);
    setState(() {
      position = newPos > maxDur ? maxDur : newPos;
    });
    await _audioHandler.fastForward();
    _saveCurrentPosition();
  }

  void _goToPreviousTrack() {
    if (_isOperationInProgress || _isDisposed) return;
    final playlistProvider = Provider.of<PlaylistProvider>(context, listen: false);
    if (playlistProvider.hasPreviousTrack) {
      playlistProvider.previousTrack();
    }
  }

  void _goToNextTrack() {
    if (_isOperationInProgress || _isDisposed) return;
    final playlistProvider = Provider.of<PlaylistProvider>(context, listen: false);
    if (playlistProvider.hasNextTrack) {
      playlistProvider.nextTrack();
    }
  }

  Future<void> _togglePlayPause() async {
    if (_isOperationInProgress || _isDisposed) return;
    try {
      if (isPlaying) {
        await _audioHandler.pause();
      } else {
        await _audioHandler.play();
      }
    } catch (e) {
      logError('_togglePlayPause', 'Error toggling play/pause', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Audio error: $e')),
        );
      }
    }
  }

  String _formatDuration(Duration? d) {
    if (d == null) return '--:--';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _saveCurrentPosition();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audio Player'),
        actions: const [AppMenu()],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (isLoading)
                  const CircularProgressIndicator()
                else if (errorMessage != null)
                  Column(
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 8),
                      Text(
                        'Error: $errorMessage',
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: () => _loadAudio(),
                        child: const Text('Retry'),
                      ),
                    ],
                  )
                else
                  Consumer<PlaylistProvider>(
                    builder: (context, playlistProvider, child) {
                      final currentBook = playlistProvider.currentAudioBook;
                      return Column(
                        children: [
                          Text(
                            currentBook?.title ?? 'No audio selected',
                            style: Theme.of(context).textTheme.titleLarge,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_formatDuration(position)),
                              Expanded(
                                child: Slider(
                                  value: position.inSeconds.toDouble().clamp(
                                    0,
                                    duration?.inSeconds.toDouble() ?? 1,
                                  ),
                                  min: 0,
                                  max: max(duration?.inSeconds.toDouble() ?? 1, 1),
                                  onChanged: (value) {
                                    if (duration != null && !_isOperationInProgress && !_isDisposed) {
                                      setState(() {
                                        position = Duration(seconds: value.toInt());
                                      });
                                    }
                                  },
                                  onChangeEnd: (value) async {
                                    if (duration != null && !_isOperationInProgress && !_isDisposed) {
                                      final newPos = Duration(seconds: value.toInt());
                                      await _audioHandler.seek(newPos);
                                      _saveCurrentPosition();
                                    }
                                  },
                                ),
                              ),
                              Text(_formatDuration(duration)),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.skip_previous),
                                iconSize: 32,
                                onPressed: (playlistProvider.hasPreviousTrack && !_isOperationInProgress && !_isDisposed)
                                    ? _goToPreviousTrack
                                    : null,
                              ),
                              IconButton(
                                icon: const Icon(Icons.replay_10),
                                iconSize: 32,
                                onPressed: (!_isOperationInProgress && !_isDisposed) ? _skipBackward : null,
                              ),
                              IconButton(
                                icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                                iconSize: 48,
                                onPressed: (!_isOperationInProgress && !_isDisposed) ? _togglePlayPause : null,
                              ),
                              IconButton(
                                icon: const Icon(Icons.forward_10),
                                iconSize: 32,
                                onPressed: (!_isOperationInProgress && !_isDisposed) ? _skipForward : null,
                              ),
                              IconButton(
                                icon: const Icon(Icons.skip_next),
                                iconSize: 32,
                                onPressed: (playlistProvider.hasNextTrack && !_isOperationInProgress && !_isDisposed)
                                    ? _goToNextTrack
                                    : null,
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
          Expanded(
            child: Consumer<PlaylistProvider>(
              builder: (context, playlistProvider, child) {
                return ListView.builder(
                  itemCount: playlistProvider.playlist.length,
                  itemBuilder: (context, index) {
                    final audioBook = playlistProvider.playlist[index];
                    final isCurrentTrack = index == playlistProvider.currentIndex;

                    return ListTile(
                      title: Text(
                        audioBook.title,
                        style: TextStyle(
                          fontWeight: isCurrentTrack ? FontWeight.bold : FontWeight.normal,
                          color: isCurrentTrack ? Theme.of(context).primaryColor : null,
                        ),
                      ),
                      trailing: Text(_formatDuration(audioBook.duration)),
                      leading: isCurrentTrack
                          ? const Icon(Icons.play_arrow, color: Colors.blue)
                          : null,
                      onTap: () {
                        if (!_isOperationInProgress && !_isDisposed) {
                          playlistProvider.setCurrentIndex(index);
                          // Audio loading is handled by setCurrentIndex
                        }
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);

    _stopPositionPolling();
    _stateDebounceTimer?.cancel();

    _saveCurrentPosition();

    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playerStateSubscription?.cancel();

    try {
      final playlistProvider = Provider.of<PlaylistProvider>(context, listen: false);
      playlistProvider.forceSave();
    } catch (e) {
      logError('dispose', 'Error force saving playlist', e);
    }

    super.dispose();
  }

  void _startPositionPolling() {
    _stopPositionPolling();
    _positionPollingTimer = Timer.periodic(const Duration(milliseconds: 200), (_) async {
      if (_isDisposed || !mounted) {
        _stopPositionPolling();
        return;
      }
      try {
        final newPosition = await _audioHandler.getCurrentPosition();
        if (!_isDisposed && mounted && newPosition != position) {
          setState(() => position = newPosition);
          _saveCurrentPosition();
        }
      } catch (e) {
        logError('_startPositionPolling', 'Position polling error', e);
      }
    });
  }

  void _stopPositionPolling() {
    _positionPollingTimer?.cancel();
    _positionPollingTimer = null;
  }
}
