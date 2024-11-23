import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audio_service/audio_service.dart';
import '../playlist_provider.dart';
import '../widgets/app_menu.dart';
import '../audio_handler.dart';

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
    _loadAudio();

    // Подписываемся на обновления состояния плеера
    _audioHandler.playbackState.listen((state) {
      if (mounted) {
        setState(() {
          isPlaying = state.playing;
          isLoading = state.processingState == AudioProcessingState.loading;
        });
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

      await _audioHandler.setAudioSource(currentBook.audioUrl);

      final duration = _audioHandler.duration;
      print('Loaded audio duration: $duration');

      if (duration != null) {
        setState(() {
          this.duration = duration;
          position = Duration.zero; // Сбрасываем позицию
        });
      } else {
        print('Warning: Duration is null');
      }

      setState(() {
        isLoading = false;
        isPlaying = false;
      });

    } catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = e.toString();
      });
      print('Error loading audio: $e');
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
                                        await _audioHandler.seek(Duration(seconds: value.toInt()));
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
                                onPressed: () => _audioHandler.skipToPrevious(),
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
                                onPressed: () => _audioHandler.skipToNext(),
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
    super.dispose();
  }
}
