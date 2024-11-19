import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:just_audio/just_audio.dart';
import '../playlist_provider.dart';
import '../widgets/app_menu.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  _PlayerScreenState createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool isPlaying = false;
  bool isLoading = true;
  String? errorMessage;
  Duration? duration;
  Duration position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _loadAudio();

    _audioPlayer.positionStream.listen((pos) {
      setState(() {
        position = pos;
      });
    });

    _audioPlayer.durationStream.listen((dur) {
      setState(() {
        duration = dur;
      });
    });

    _audioPlayer.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          isPlaying = state.playing;
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
    final wasPlaying = isPlaying;

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

      await _audioPlayer.setFilePath(currentBook.audioUrl);

      // Восстанавливаем состояние воспроизведения
      if (wasPlaying) {
        await _audioPlayer.play();
      }

      _audioPlayer.processingStateStream.listen((state) {
        if (state == ProcessingState.completed) {
          final playlistProvider = Provider.of<PlaylistProvider>(context, listen: false);
          playlistProvider.nextTrack();
          _loadAudio();
        }
      });

      setState(() {
        isLoading = false;
        isPlaying = wasPlaying;
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
                                child: Slider(
                                  value: position.inSeconds.toDouble(),
                                  min: 0,
                                  max: duration?.inSeconds.toDouble() ?? 0,
                                  onChanged: (value) async {
                                    final position = Duration(seconds: value.toInt());
                                    await _audioPlayer.seek(position);
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
                                onPressed: () {
                                  Provider.of<PlaylistProvider>(context, listen: false).previousTrack();
                                  _loadAudio();
                                },
                              ),
                              IconButton(
                                icon: Icon(Icons.replay_10),
                                iconSize: 32,
                                onPressed: () async {
                                  final newPosition = position - Duration(seconds: 10);
                                  await _audioPlayer.seek(newPosition);
                                },
                              ),
                              ElevatedButton(
                                onPressed: () async {
                                  try {
                                    if (isPlaying) {
                                      await _audioPlayer.pause();
                                    } else {
                                      await _audioPlayer.play();
                                    }
                                  } catch (e) {
                                    print('Error playing audio: $e');
                                  }
                                },
                                child: Icon(
                                  isPlaying ? Icons.pause : Icons.play_arrow,
                                  size: 32,
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.forward_10),
                                iconSize: 32,
                                onPressed: () async {
                                  final newPosition = position + Duration(seconds: 10);
                                  await _audioPlayer.seek(newPosition);
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
    _audioPlayer.dispose();
    super.dispose();
  }
}
