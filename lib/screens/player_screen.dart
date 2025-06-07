import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audio_service/audio_service.dart';
import '../playlist_provider.dart';
import '../widgets/app_menu.dart';
import '../audio_handler.dart';
import '../services/playlist_service.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  _PlayerScreenState createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final AudioPlayerHandler _audioHandler;
  bool isPlaying = false;
  bool isLoading = true;
  String? errorMessage;
  Duration? duration;
  Duration position = Duration.zero;


  @override
  void initState() {
    super.initState();
    _audioHandler = context.read<AudioPlayerHandler>();

    // Set up track completion callback
    _audioHandler.onTrackCompleted = _onTrackCompleted;

    _loadAudio();

    // Подписываемся на обновления состояния плеера
    _audioHandler.playbackState.listen((state) {
      if (mounted) {
        final wasPlaying = isPlaying;
        setState(() {
          isPlaying = state.playing;
          isLoading = state.processingState == AudioProcessingState.loading;
        });

        // Save position when pausing
        if (wasPlaying && !state.playing && !isLoading) {
          _saveCurrentPosition();
        }
      }
    });

    // Подписываемся на обновления метаданных трека
    _audioHandler.mediaItem.listen((mediaItem) {
      if (mounted && mediaItem != null) {
        setState(() {
          duration = mediaItem.duration;
        });
      }
    });

    // Используем геттер positionStream вместо прямого доступа к _player
    _audioHandler.positionStream.listen((pos) {
      if (mounted) {
        setState(() {
          position = pos;
        });

        // Update position in playlist provider
        Provider.of<PlaylistProvider>(context, listen: false)
            .updateCurrentTrackPosition(pos);
      }
    });
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '--:--';
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return '$twoDigitMinutes:$twoDigitSeconds';
  }

  void _onTrackCompleted() {
    if (!mounted) return;

    final playlistProvider = Provider.of<PlaylistProvider>(context, listen: false);

    // Automatically move to next track if available
    if (playlistProvider.hasNextTrack) {
      playlistProvider.nextTrack();
      _loadAudio();
    } else {
      // If it's the last track, stop playing
      setState(() {
        isPlaying = false;
      });
    }
  }

  Future<void> _loadAudio() async {
    try {
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
        });

        return;
      }

      print('Loading audio for: ${currentBook.title}');

      // Load saved position for this track
      final savedPosition = await _loadTrackPosition(currentBook.id);

      await _audioHandler.setAudioSource(currentBook.audioUrl);
      final duration = _audioHandler.duration;

      if (duration != null) {
        setState(() {
          this.duration = duration;
          position = savedPosition; // Use loaded saved position
        });

        // Seek to saved position if it exists
        if (savedPosition > Duration.zero) {
          print('Seeking to saved position: ${savedPosition.inMinutes}:${savedPosition.inSeconds % 60}');
          await _audioHandler.seek(savedPosition);
        } else {
          // If no saved position, save initial zero position
          print('No saved position found, saving initial zero position');
          playlistProvider.updateCurrentTrackPosition(Duration.zero);
        }
      } else {
        print('Warning: Duration is null');
      }

      setState(() {
        isLoading = false;
        isPlaying = false; // Initially set to false
      });
    } catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = e.toString();
      });
      print('Error loading audio: $e');
    }
  }

  Future<Duration> _loadTrackPosition(String trackId) async {
    try {
      final playlistProvider = Provider.of<PlaylistProvider>(context, listen: false);
      return await playlistProvider.loadTrackPosition(trackId);
    } catch (e) {
      print('Error loading track position: $e');
      return Duration.zero;
    }
  }
  void _saveCurrentPosition() {
    print('PlayerScreen: Saving current position: ${position.inMinutes}:${position.inSeconds % 60}');
    final playlistProvider = Provider.of<PlaylistProvider>(context, listen: false);
    playlistProvider.updateCurrentTrackPosition(position);
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
          // Верхняя часть с плеером
          Container(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                if (isLoading)
                  CircularProgressIndicator()
                else if (errorMessage != null)
                  Text('Error: $errorMessage')
                else
                  Consumer<PlaylistProvider>(
                    builder: (context, playlistProvider, child) {
                      final currentBook = playlistProvider.currentAudioBook;
                      return Column(
                        children: [
                          Text(
                            currentBook?.title ?? 'No file selected',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_formatDuration(position)),
                              Expanded(
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    thumbShape: RoundSliderThumbShape(enabledThumbRadius: 8),
                                    trackHeight: 2,
                                  ),
                                  child: Slider(
                                    value: min(
                                      max(0, position.inSeconds.toDouble()),
                                      duration?.inSeconds.toDouble() ?? 1,
                                    ),
                                    min: 0,
                                    max: max(duration?.inSeconds.toDouble() ?? 1, 1),
                                    onChanged: (value) {
                                      if (duration != null) {
                                        setState(() {
                                          position = Duration(seconds: value.toInt());
                                        });
                                      }
                                    },
                                    onChangeEnd: (value) async {
                                      if (duration != null) {
                                        final newPosition = Duration(seconds: value.toInt());
                                        await _audioHandler.seek(newPosition);
                                        _saveCurrentPosition();
                                      }
                                    },
                                  ),
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
                                onPressed: () {
                                  Provider.of<PlaylistProvider>(context, listen: false).previousTrack();
                                  _loadAudio();
                                },
                              ),
                              IconButton(
                                icon: Icon(Icons.replay_10),
                                iconSize: 32,
                                onPressed: () async {
                                  _audioHandler.skipToPrevious();
                                  _saveCurrentPosition();
                                },
                              ),
                              IconButton(
                                icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                                iconSize: 48,
                                onPressed: () async {
                                  if (isPlaying) {
                                    await _audioHandler.pause();
                                  } else {
                                    await _audioHandler.play();
                                  }
                                },
                              ),
                              IconButton(
                                icon: Icon(Icons.forward_10),
                                iconSize: 32,
                                onPressed: () async {
                                  _audioHandler.skipToNext();
                                  _saveCurrentPosition();
                                },
                              ),
                              IconButton(
                                icon: Icon(Icons.skip_next),
                                iconSize: 32,
                                onPressed: () {
                                  Provider.of<PlaylistProvider>(context, listen: false).nextTrack();
                                  _loadAudio();
                                },
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

          // Нижняя часть со списком треков
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
                        playlistProvider.setCurrentIndex(index);
                        _loadAudio();
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
    // Save current position before disposing
    _saveCurrentPosition();
    final playlistProvider = Provider.of<PlaylistProvider>(context, listen: false);
    playlistProvider.forceSave();

    // Clear the callback to prevent memory leaks
    _audioHandler.onTrackCompleted = null;
    super.dispose();
  }
}
