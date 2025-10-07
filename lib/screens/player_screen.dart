import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:just_audio/just_audio.dart';
import '../playlist_provider.dart';
import '../services/logger_service.dart';
import '../widgets/app_menu.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  _PlayerScreenState createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with WidgetsBindingObserver {
  AudioPlayer? _audioPlayer;
  Duration position = Duration.zero;
  Duration? duration;
  bool isPlaying = false;
  bool isLoading = false;
  String? errorMessage;
  bool _isOperationInProgress = false;
  bool _isDisposed = false;

  // Debouncing для предотвращения частых обновлений
  Timer? _positionDebounceTimer;
  Timer? _stateDebounceTimer;

  // Stream subscriptions
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeAudioPlayer();
  }

  Future<void> _initializeAudioPlayer() async {
    if (_isDisposed) return;

    try {
      // Простая инициализация AudioPlayer без дополнительных параметров
      _audioPlayer = AudioPlayer();

      if (Platform.isWindows) {
        // Задержка для Windows для стабильности
        await Future.delayed(Duration(milliseconds: 500));
      }

      await _setupStreamListeners();
      await _loadAudio();

      logDebug('_initializeAudioPlayer', 'Audio player initialized successfully');
    } catch (e) {
      logError('_initializeAudioPlayer', 'Failed to initialize audio player', e);
      if (mounted && !_isDisposed) {
        setState(() {
          errorMessage = 'Failed to initialize audio player: $e';
          _isOperationInProgress = false;
        });
      }
    }
  }

  Future<void> _setupStreamListeners() async {
    if (_audioPlayer == null || _isDisposed) return;

    try {
      // Position stream with debouncing
      _positionSubscription = _audioPlayer!.positionStream.listen(
            (newPosition) {
          if (!_isDisposed && mounted) {
            _positionDebounceTimer?.cancel();
            _positionDebounceTimer = Timer(Duration(milliseconds: 100), () {
              if (!_isDisposed && mounted) {
                try {
                  setState(() {
                    position = newPosition;
                  });
                  _saveCurrentPosition();
                } catch (e) {
                  logError('_setupStreamListeners', 'Position update error', e);
                }
              }
            });
          }
        },
        onError: (error) {
          logError('_setupStreamListeners', 'Position stream error (ignored)', error);
        },
      );

      // Duration stream
      _durationSubscription = _audioPlayer!.durationStream.listen(
            (newDuration) {
          if (!_isDisposed && mounted && newDuration != null) {
            setState(() {
              duration = newDuration;
            });
          }
        },
        onError: (error) {
          logError('_setupStreamListeners', 'Duration stream error (ignored)', error);
        },
      );

      // Playing stream
      _playingSubscription = _audioPlayer!.playingStream.listen(
            (playing) {
          if (!_isDisposed && mounted) {
            _stateDebounceTimer?.cancel();
            _stateDebounceTimer = Timer(Duration(milliseconds: 50), () {
              if (!_isDisposed && mounted) {
                try {
                  setState(() {
                    isPlaying = playing;
                  });
                } catch (e) {
                  logError('_setupStreamListeners', 'Playing update error', e);
                }
              }
            });
          }
        },
        onError: (error) {
          logError('_setupStreamListeners', 'Playing stream error (ignored)', error);
        },
      );

      // Player state stream
      _playerStateSubscription = _audioPlayer!.playerStateStream.listen(
            (playerState) {
          if (!_isDisposed && mounted) {
            try {
              // Handle track completion
              if (playerState.processingState == ProcessingState.completed) {
                _handleTrackCompletion();
              }

              // Handle loading state
              final newLoading = playerState.processingState == ProcessingState.loading ||
                  playerState.processingState == ProcessingState.buffering;

              if (isLoading != newLoading) {
                setState(() {
                  isLoading = newLoading;
                  // Разблокируем операции после загрузки
                  if (!newLoading) {
                    _isOperationInProgress = false;
                  }
                });
              }
            } catch (e) {
              logError('_setupStreamListeners', 'Player state update error', e);
            }
          }
        },
        onError: (error) {
          logError('_setupStreamListeners', 'Player state stream error (ignored)', error);
        },
      );

    } catch (e) {
      logError('_setupStreamListeners', 'Error setting up stream listeners', e);
    }
  }

  void _handleTrackCompletion() async {
    if (_isDisposed || _isOperationInProgress) return;

    try {
      logInfo('_handleTrackCompletion', 'Track completed, checking for next track');

      final playlistProvider = Provider.of<PlaylistProvider>(context, listen: false);

      if (playlistProvider.hasNextTrack) {
        logInfo('_handleTrackCompletion', 'Moving to next track');
        playlistProvider.nextTrack();
        await _loadAudio(shouldAutoplay: true);
      } else {
        logInfo('_handleTrackCompletion', 'Reached end of playlist, stopping');
        if (mounted && !_isDisposed) {
          setState(() {
            isPlaying = false;
            _isOperationInProgress = false;
          });
        }
      }
    } catch (e) {
      logError('_handleTrackCompletion', 'Error handling track completion', e);
      if (mounted && !_isDisposed) {
        setState(() {
          _isOperationInProgress = false;
        });
      }
    }
  }

  Future<void> _loadAudio({bool shouldAutoplay = false}) async {
    if (_isDisposed || _audioPlayer == null) return;

    try {
      _isOperationInProgress = true;

      // Stop current playback with error handling
      try {
        await _audioPlayer!.stop();
      } catch (e) {
        logError('_loadAudio', 'Error stopping audio player (ignored)', e);
      }

      if (mounted && !_isDisposed) {
        setState(() {
          isLoading = true;
          errorMessage = null;
        });
      }

      final playlistProvider = Provider.of<PlaylistProvider>(context, listen: false);
      final currentBook = playlistProvider.currentAudioBook;

      if (currentBook == null) {
        if (mounted && !_isDisposed) {
          setState(() {
            errorMessage = 'No audio file selected';
            isLoading = false;
            _isOperationInProgress = false;
          });
        }
        return;
      }

      logInfo('_loadAudio', 'Loading audio: ${currentBook.title}, shouldAutoplay: $shouldAutoplay');

      // Load saved position
      final savedPosition = await _loadTrackPosition(currentBook.id);

      // Stabilization delay for Windows
      if (Platform.isWindows) {
        await Future.delayed(Duration(milliseconds: 200));
      }

      try {
        // Set audio source with Windows-specific handling
        await _audioPlayer!.setAudioSource(
          AudioSource.uri(Uri.parse(currentBook.audioUrl)),
          preload: true,
        );

      } catch (e) {
        if (mounted && !_isDisposed) {
          setState(() {
            errorMessage = 'Failed to load audio: ${e.toString()}';
            isLoading = false;
            _isOperationInProgress = false;
          });
        }
        logError('_loadAudio', 'Error setting audio source', e);
        return;
      }

      // Wait for duration to be available
      Duration? audioDuration = _audioPlayer!.duration;
      if (audioDuration == null) {
        for (int i = 0; i < 10 && audioDuration == null && !_isDisposed; i++) {
          await Future.delayed(Duration(milliseconds: 100));
          audioDuration = _audioPlayer!.duration;
        }
      }

      if (mounted && !_isDisposed) {
        if (audioDuration != null) {
          setState(() {
            duration = audioDuration;
            position = savedPosition;
            isLoading = false;
          });

          // Seek to saved position if valid
          if (savedPosition > Duration.zero && savedPosition < audioDuration) {
            try {
              await _audioPlayer!.seek(savedPosition);
              logInfo('_loadAudio', 'Seeked to saved position: ${savedPosition.inMinutes}:${savedPosition.inSeconds % 60}');
            } catch (e) {
              logError('_loadAudio', 'Error seeking to saved position (ignored)', e);
            }
          }

          // Auto-play if requested
          if (shouldAutoplay) {
            try {
              await _audioPlayer!.play();
              logInfo('_loadAudio', 'Started auto-play');
            } catch (e) {
              logError('_loadAudio', 'Error starting auto-play (ignored)', e);
            }
          }
        } else {
          setState(() {
            errorMessage = 'Failed to get audio duration';
            isLoading = false;
          });
        }

        // Разблокируем операции после завершения загрузки
        setState(() {
          _isOperationInProgress = false;
        });
      }

      logInfo('_loadAudio', 'Audio loaded successfully');

    } catch (e) {
      logError('_loadAudio', 'Error loading audio', e);
      if (mounted && !_isDisposed) {
        setState(() {
          errorMessage = 'Error loading audio: ${e.toString()}';
          isLoading = false;
          _isOperationInProgress = false;
        });
      }
    } finally {
      // Гарантированно разблокируем операции
      if (mounted && !_isDisposed) {
        setState(() {
          _isOperationInProgress = false;
        });
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
    if (_isOperationInProgress || _audioPlayer == null || _isDisposed) return;

    try {
      final newPosition = Duration(seconds: (position.inSeconds - 10).clamp(0, duration?.inSeconds ?? 0));
      await _audioPlayer!.seek(newPosition);
      _saveCurrentPosition();
    } catch (e) {
      logError('_skipBackward', 'Error skipping backward (ignored)', e);
    }
  }

  Future<void> _skipForward() async {
    if (_isOperationInProgress || _audioPlayer == null || _isDisposed) return;

    try {
      final newPosition = Duration(seconds: (position.inSeconds + 10).clamp(0, duration?.inSeconds ?? 0));
      await _audioPlayer!.seek(newPosition);
      _saveCurrentPosition();
    } catch (e) {
      logError('_skipForward', 'Error skipping forward (ignored)', e);
    }
  }

  void _goToPreviousTrack() {
    if (_isOperationInProgress || _isDisposed) return;

    try {
      final playlistProvider = Provider.of<PlaylistProvider>(context, listen: false);

      if (playlistProvider.hasPreviousTrack) {
        final wasPlaying = isPlaying;
        playlistProvider.previousTrack();
        _loadAudio(shouldAutoplay: wasPlaying);
      }
    } catch (e) {
      logError('_goToPreviousTrack', 'Error going to previous track', e);
    }
  }

  void _goToNextTrack() {
    if (_isOperationInProgress || _isDisposed) return;

    try {
      final playlistProvider = Provider.of<PlaylistProvider>(context, listen: false);

      if (playlistProvider.hasNextTrack) {
        final wasPlaying = isPlaying;
        playlistProvider.nextTrack();
        _loadAudio(shouldAutoplay: wasPlaying);
      }
    } catch (e) {
      logError('_goToNextTrack', 'Error going to next track', e);
    }
  }

  Future<void> _togglePlayPause() async {
    if (_isOperationInProgress || _audioPlayer == null || _isDisposed) return;

    try {
      if (isPlaying) {
        await _audioPlayer!.pause();
      } else {
        await _audioPlayer!.play();
      }
    } catch (e) {
      logError('_togglePlayPause', 'Error toggling play/pause', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Audio error: ${e.toString()}')),
        );
      }
    }
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '--:--';
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes);
    final seconds = twoDigits(duration.inSeconds % 60);
    return '$minutes:$seconds';
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
        title: Text('Audio Player'),
        actions: [
          AppMenu(),
        ],
      ),
      body: Column(
        children: [
          // Top section with player
          Container(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                if (isLoading)
                  CircularProgressIndicator()
                else if (errorMessage != null)
                  Column(
                    children: [
                      Icon(Icons.error_outline, size: 48, color: Colors.red),
                      SizedBox(height: 8),
                      Text(
                        'Error: $errorMessage',
                        style: TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: () => _loadAudio(),
                        child: Text('Retry'),
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
                          SizedBox(height: 20),
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
                                    if (duration != null && !_isOperationInProgress && !_isDisposed && _audioPlayer != null) {
                                      try {
                                        final newPosition = Duration(seconds: value.toInt());
                                        await _audioPlayer!.seek(newPosition);
                                        _saveCurrentPosition();
                                      } catch (e) {
                                        logError('Slider', 'Error seeking (ignored)', e);
                                      }
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
                                icon: Icon(Icons.skip_previous),
                                iconSize: 32,
                                onPressed: (playlistProvider.hasPreviousTrack && !_isOperationInProgress && !_isDisposed)
                                    ? _goToPreviousTrack : null,
                              ),
                              IconButton(
                                icon: Icon(Icons.replay_10),
                                iconSize: 32,
                                onPressed: (!_isOperationInProgress && !_isDisposed) ? _skipBackward : null,
                              ),
                              IconButton(
                                icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                                iconSize: 48,
                                onPressed: (!_isOperationInProgress && !_isDisposed) ? _togglePlayPause : null,
                              ),
                              IconButton(
                                icon: Icon(Icons.forward_10),
                                iconSize: 32,
                                onPressed: (!_isOperationInProgress && !_isDisposed) ? _skipForward : null,
                              ),
                              IconButton(
                                icon: Icon(Icons.skip_next),
                                iconSize: 32,
                                onPressed: (playlistProvider.hasNextTrack && !_isOperationInProgress && !_isDisposed)
                                    ? _goToNextTrack : null,
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

          // Bottom section with track list
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
                          ? Icon(Icons.play_arrow, color: Theme.of(context).primaryColor)
                          : null,
                      onTap: () {
                        if (!_isOperationInProgress && !_isDisposed) {
                          try {
                            final wasPlaying = isPlaying;
                            playlistProvider.setCurrentIndex(index);
                            _loadAudio(shouldAutoplay: wasPlaying);
                          } catch (e) {
                            logError('Track tap', 'Error switching track', e);
                          }
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

    // Cancel timers
    _positionDebounceTimer?.cancel();
    _stateDebounceTimer?.cancel();

    // Save current position before disposing
    _saveCurrentPosition();

    // Cancel stream subscriptions
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playingSubscription?.cancel();
    _playerStateSubscription?.cancel();

    // Dispose audio player with error handling
    if (_audioPlayer != null) {
      try {
        _audioPlayer!.dispose();
      } catch (e) {
        logError('dispose', 'Error disposing audio player (ignored)', e);
      }
    }

    try {
      final playlistProvider = Provider.of<PlaylistProvider>(context, listen: false);
      playlistProvider.forceSave();
    } catch (e) {
      logError('dispose', 'Error force saving playlist', e);
    }

    super.dispose();
  }
}
