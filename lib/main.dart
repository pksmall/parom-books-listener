import 'package:flutter/material.dart';
import 'screens/library_screen.dart';

void main() {
  runApp(AudioBookApp());
}

class AudioBookApp extends StatelessWidget {
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
