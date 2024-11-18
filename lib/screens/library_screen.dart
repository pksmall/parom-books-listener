import 'package:flutter/material.dart';
import 'player_screen.dart'; // Импортируем экран плеера

class LibraryScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Library'),
      ),
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => PlayerScreen()),
            );
          },
          child: Text('Open Player'),
        ),
      ),
    );
  }
}
