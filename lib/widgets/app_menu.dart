import 'package:flutter/material.dart';
import '../screens/settings_screen.dart';


class AppMenu extends StatelessWidget {
  const AppMenu({super.key});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert),
      onSelected: (value) {
        switch (value) {
          case 'settings':
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => SettingsScreen(),
              ),
            );
            break;
          case 'save_library':
          // Показываем сообщение о сохранении
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Library saved successfully'),
                duration: Duration(seconds: 2),
              ),
            );
            break;
        }
      },
      itemBuilder: (BuildContext context) => [
        PopupMenuItem<String>(
          value: 'settings',
          child: Row(
            children: [
              Icon(Icons.settings, color: Colors.grey[700]),
              SizedBox(width: 8),
              Text('Settings'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'save_library',
          child: Row(
            children: [
              Icon(Icons.save, color: Colors.grey[700]),
              SizedBox(width: 8),
              Text('Save Library'),
            ],
          ),
        ),
      ],
    );
  }
}
