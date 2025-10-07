import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:parom_books_listener/screens/library_screen.dart';
import 'package:provider/provider.dart';
import 'package:parom_books_listener/services/logger_service.dart';
import 'package:parom_books_listener/playlist_provider.dart';
import 'package:parom_books_listener/audio_handler.dart';
import 'package:parom_books_listener/screens/player_screen.dart';
import 'package:parom_books_listener/services/playlist_service.dart';

Future<void> main() async{
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize logger service
  await LoggerService.instance.init(
    minLogLevel: LogLevel.debug,
    enableFileLogging: true,
    enableConsoleLogging: true,
  );

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
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PlaylistProvider()),
      ],
      child: MaterialApp(
        title: 'Parom Books Listener',
        theme: ThemeData(
          primarySwatch: Colors.blue,
        ),
        home: StartupScreen(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

class StartupScreen extends StatefulWidget {
  @override
  _StartupScreenState createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  bool _isLoading = true;
  bool _shouldShowPlayer = false;

  @override
  void initState() {
    super.initState();
    _checkStartupConditions();
  }

  Future<void> _checkStartupConditions() async {
    try {
      logInfo('StartupScreen', 'Checking startup conditions...');

      final playlistProvider = Provider.of<PlaylistProvider>(context, listen: false);

      // Initialize the playlist provider
      await playlistProvider.initialize();

      // Check if we have a playlist and saved positions
      final shouldShowPlayer = await _shouldOpenPlayerDirectly();

      setState(() {
        _shouldShowPlayer = shouldShowPlayer;
        _isLoading = false;
      });

      // Navigate to appropriate screen after a brief delay
      await Future.delayed(Duration(milliseconds: 500));

      if (mounted) {
        // Всегда сначала переходим к LibraryScreen
        logDebug('StartupScreen', 'Navigating to main screen');
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => LibraryScreen()),
        );

        // Если нужно показать плеер, открываем его поверх LibraryScreen
        if (_shouldShowPlayer) {
          // Используем addPostFrameCallback для выполнения навигации после построения LibraryScreen
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              logDebug('StartupScreen', 'Auto-opening player screen');
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => PlayerScreen()),
              );
            }
          });
        }
      }

    } catch (e) {
      logError('StartupScreen', 'Error during startup check:', e);

      // On error, go to main screen
      setState(() {
        _isLoading = false;
        _shouldShowPlayer = false;
      });

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => LibraryScreen()),
        );
      }
    }
  }

  Future<bool> _shouldOpenPlayerDirectly() async {
    try {
      final playlistService = PlaylistService();
      await playlistService.init();

      // Check if playlist exists and has items
      final playlist = await playlistService.loadPlaylist();
      if (playlist.isEmpty) {
        logDebug('_shouldOpenPlayerDirectly', 'No playlist found');
        return false;
      }

      // Check if current index is valid
      final currentIndex = await playlistService.loadCurrentIndex();
      if (currentIndex < 0 || currentIndex >= playlist.length) {
        logDebug('_shouldOpenPlayerDirectly', 'Invalid current index');
        return false;
      }

      // Check if there's a saved position for the current track
      final currentTrack = playlist[currentIndex];
      final savedPosition = await playlistService.loadPosition(currentTrack.id);

      if (savedPosition > Duration.zero) {
        logInfo('_shouldOpenPlayerDirectly',
            'Found playlist with ${playlist.length} tracks, current track: ${currentTrack.title}, saved position: ${savedPosition.inMinutes}:${savedPosition.inSeconds % 60}');
        return true;
      }

      // If no saved position but we have a playlist, we can still show the player
      // depending on your preference. For now, let's show it if we have a playlist
      logInfo('_shouldOpenPlayerDirectly',
          'Found playlist with ${playlist.length} tracks but no saved position');
      return true; // Change to false if you only want to show player when there's a saved position

    } catch (e) {
      logError('_shouldOpenPlayerDirectly', 'Error checking startup conditions:', e);
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).primaryColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // App logo or icon
            Icon(
              Icons.headphones,
              size: 80,
              color: Colors.white,
            ),
            SizedBox(height: 20),

            // App title
            Text(
              'Parom Books Listener',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 40),

            if (_isLoading) ...[
              // Loading indicator
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
              SizedBox(height: 20),
              Text(
                'Loading...',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white70,
                ),
              ),
            ] else ...[
              // Status indicator
              Icon(
                _shouldShowPlayer ? Icons.play_circle_filled : Icons.folder_open,
                size: 48,
                color: Colors.white70,
              ),
              SizedBox(height: 10),
              Text(
                _shouldShowPlayer
                    ? 'Opening Audio Player...'
                    : 'Opening File Browser...',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white70,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
