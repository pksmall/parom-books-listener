import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'),
      ),
      body: ListView(
        children: [
          // Здесь будут настройки приложения
          ListTile(
            title: Text('Theme'),
            trailing: Icon(Icons.brightness_4),
            onTap: () {
              // TODO: Реализовать настройку темы
            },
          ),
          // Добавьте другие настройки по необходимости
        ],
      ),
    );
  }
}
