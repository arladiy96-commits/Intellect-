import 'package:flutter/material.dart';

import 'features/agents/agents_screen.dart';
import 'features/chat/chat_screen.dart';
import 'features/models/models_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/settings/updates_screen.dart';
import 'core/updates/baboon_update_service.dart';

class MyAiApp extends StatelessWidget {
  const MyAiApp({super.key});

  @override
  Widget build(BuildContext context) {
    const base = Color(0xFF101827);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Бабуин',
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdatesQuietly());
  }

  Future<void> _checkUpdatesQuietly() async {
    try {
      final release = await BaboonUpdateService().checkAvailable();
      if (!mounted || release == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Доступно обновление Бабуина ${release.tag}'),
          action: SnackBarAction(
            label: 'Открыть',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const UpdatesScreen()),
            ),
          ),
        ),
      );
    } catch (_) {
      // No internet or no stable release should never block offline AI use.
    }
  }

  static const _pages = <Widget>[
    ChatScreen(),
    AgentsScreen(),
    ModelsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('БАБУИН')),
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
