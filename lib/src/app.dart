import 'package:flutter/material.dart';

import 'features/agents/agents_screen.dart';
import 'features/chat/chat_screen.dart';
import 'features/models/models_screen.dart';
import 'features/settings/settings_screen.dart';

class MyAiApp extends StatelessWidget {
  const MyAiApp({super.key});

  @override
  Widget build(BuildContext context) {
    const base = Color(0xFF101827);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Мой ИИ',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: base,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF87AFFF),
          brightness: Brightness.dark,
        ),
        appBarTheme: const AppBarTheme(backgroundColor: base, elevation: 0),
      ),
      home: const MainShell(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const _pages = <Widget>[
    ChatScreen(),
    AgentsScreen(),
    ModelsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('МОЙ ИИ')),
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            label: 'Чат',
          ),
          NavigationDestination(
            icon: Icon(Icons.smart_toy_outlined),
            label: 'Агенты',
          ),
          NavigationDestination(icon: Icon(Icons.memory), label: 'Модели'),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: 'Настройки',
          ),
        ],
      ),
    );
  }
}
