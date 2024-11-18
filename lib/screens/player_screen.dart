import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

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

    // Слушаем изменение позиции воспроизведения
    _audioPlayer.positionStream.listen((pos) {
      setState(() {
        position = pos;
      });
    });

    // Слушаем изменение длительности
    _audioPlayer.durationStream.listen((dur) {
      setState(() {
        duration = dur;
      });
    });
  }

  Future<void> _loadAudio() async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/test.mp3');

      if (!await file.exists()) {
        final byteData = await rootBundle.load('assets/test.mp3');
        await file.writeAsBytes(byteData.buffer.asUint8List());
      }

      await _audioPlayer.setFilePath(file.path);

      _audioPlayer.playerStateStream.listen((state) {
        if (mounted) {
          setState(() {
            isPlaying = state.playing;
          });
        }
      }, onError: (error) {
        setState(() {
          errorMessage = error.toString();
        });
      });

      setState(() {
        isLoading = false;
      });

    } catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = e.toString();
      });
      print('Error loading audio: $e');
    }
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '--:--';
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return '$twoDigitMinutes:$twoDigitSeconds';
  }

  @override
  Widget build(BuildContext context) {
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
                  // Название файла
                  Text(
                    'test.mp3',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 20),

                  // Ползунок и время
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

                  // Кнопки управления
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Перемотка назад на 10 секунд
                      IconButton(
                        icon: Icon(Icons.replay_10),
                        iconSize: 32,
                        onPressed: () async {
                          final newPosition = position - Duration(seconds: 10);
                          await _audioPlayer.seek(newPosition);
                        },
                      ),

                      SizedBox(width: 20),

                      // Кнопка play/pause
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

                      // Перемотка вперед на 10 секунд
                      IconButton(
                        icon: Icon(Icons.forward_10),
                        iconSize: 32,
                        onPressed: () async {
                          final newPosition = position + Duration(seconds: 10);
                          await _audioPlayer.seek(newPosition);
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
