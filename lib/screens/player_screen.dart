import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:just_audio/just_audio.dart';
import '../playlist_provider.dart';

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

    // Добавляем слушатель состояния плеера
    _audioPlayer.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          isPlaying = state.playing;
        });
      }
    });
  }


  String _formatDuration(Duration? duration) {
    if (duration == null) {
      return '--:--';
    }
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
    final currentBook = Provider.of<PlaylistProvider>(context).currentAudioBook;

    return Scaffold(
      appBar: AppBar(
        title: Text('Audio Player'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              CircularProgressIndicator()
            else if (errorMessage != null)
              Text('Error: $errorMessage')
            else
              Column(
                children: [
                  // Обновляем отображение названия файла
                  Text(
                    currentBook?.title ?? 'No file selected',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 20),

                  // Остальной код без изменений
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        Slider(
                          value: position.inSeconds.toDouble(),
                          min: 0,
                          max: duration?.inSeconds.toDouble() ?? 0,
                          onChanged: (value) async {
                            final position = Duration(seconds: value.toInt());
                            await _audioPlayer.seek(position);
                          },
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_formatDuration(position)),
                              Text(_formatDuration(duration)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 20),

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

                      SizedBox(width: 20),

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

                      SizedBox(width: 20),

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

                  SizedBox(height: 20),
                  Text(
                    isPlaying ? 'Playing' : 'Paused',
                    style: TextStyle(fontSize: 16),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }
}
