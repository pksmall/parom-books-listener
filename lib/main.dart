import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/library_screen.dart';
import 'playlist_provider.dart';
import 'audio_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final audioHandler = await AudioService.init(
    builder: () => AudioPlayerHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.myapp.audio',
      androidNotificationChannelName: 'Audio Service',
      androidNotificationOngoing: true,
    ),
  );

  final playlistProvider = PlaylistProvider();
  await playlistProvider.initialize();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: playlistProvider),
        Provider.value(value: audioHandler),
      ],
      child: const AudioBookApp(),
    ),
  );
}

class AudioBookApp extends StatelessWidget {
  const AudioBookApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AudioBook Player',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: LibraryScreen(),
    );
  }
}
