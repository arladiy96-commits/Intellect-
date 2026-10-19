import 'package:flutter/material.dart';
import 'core/ai/cloud_ai_engine.dart';
import 'core/ai/llama_native_engine.dart';
import 'core/chat/chat_session_controller.dart';
import 'core/updates/baboon_update_service.dart';
import 'features/chat/chat_screen.dart';
import 'features/home/home_screen.dart';
import 'features/knowledge/knowledge_screen.dart';
import 'features/memory/memory_screen.dart';
import 'features/models/models_hub_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/settings/updates_screen.dart';
import 'features/tools/photo_preview_screen.dart';
import 'features/tools/tools_screen.dart';
import 'ui/baboon_style.dart';

class MyAiApp extends StatelessWidget {
  const MyAiApp({super.key});
  @override Widget build(BuildContext context) => MaterialApp(
    title: 'Бабуин', debugShowCheckedModeBanner: false,
    theme: baboonTheme(), home: const MainShell(),
  );
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final shellKey = GlobalKey<ScaffoldState>();
  final ai = LlamaNativeEngine.instance;
  int index = 0;

  @override void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdatesQuietly());
  }
  Future<void> _checkUpdatesQuietly() async {
    try {
      final release = await BaboonUpdateService().checkAvailable();
      if (!mounted || release == null) { return; }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Доступно обновление Бабуина ${release.tag}'),
        action: SnackBarAction(label: 'Открыть', onPressed: () => _push(const UpdatesScreen())),
      ));
    } catch (_) { /* Offline use is not affected. */ }
  }

  void _go(int value) {
    if (!mounted) { return; }
    setState(() => index = value);
  }
  void _push(Widget screen) => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => screen));
  void _photo() => _push(const PhotoPreviewScreen());
  void _profile() => _push(ProfileScreen(onChat: () => _go(1),
    onSettings: () => _go(4)));

  Future<void> _provider(String choice) async {
    try {
      if (choice == 'models') { _push(const ModelsHubScreen()); return; }
      if (choice == 'local') {
        await ai.setCloudMode(false);
      } else {
        await ai.selectCloudProvider(choice == 'groq'
          ? CloudProvider.groq : CloudProvider.openrouter);
        await ai.setCloudMode(true);
      }
    } catch (e) {
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
    }
  }

  Widget _topChat() => AnimatedBuilder(animation: ai,
    builder: (context, _) => AppBar(
      leading: IconButton(tooltip: 'Главная', icon: const Icon(Icons.arrow_back),
        onPressed: () => _go(0)),
      titleSpacing: 0,
      title: InkWell(onTap: _profile, child: Row(children: [
        const BaboonAvatar(radius: 18),
        const SizedBox(width: 9),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('БАБУИН', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          Text(ai.cloudEnabled ? '${ai.cloudProviderTitle} · ${ai.cloudModel}' : 'Локально · Qwen',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: BaboonColors.muted, fontSize: 10)),
        ])),
      ])),
      actions: [
        PopupMenuButton<String>(
          enabled: !ai.isBusy && !ai.isGenerating,
          tooltip: 'Выбрать модель', onSelected: _provider,
          icon: const Icon(Icons.hub_outlined),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'models', child: Text('Модели и параметры')),
            PopupMenuItem(value: 'local', child: Text('Локальная Qwen')),
            PopupMenuItem(value: 'groq', child: Text('Groq')),
            PopupMenuItem(value: 'openrouter', child: Text('OpenRouter')),
          ],
        ),
      ],
    ));

  Widget _drawerItem(IconData icon, String label, VoidCallback onTap, {bool active = false}) =>
    ListTile(
      dense: true,
      leading: Icon(icon, color: active ? BaboonColors.gold : BaboonColors.text),
      title: Text(label, style: TextStyle(color: active ? BaboonColors.gold : BaboonColors.text,
        fontWeight: active ? FontWeight.bold : FontWeight.normal)),
      selected: active,
      selectedTileColor: BaboonColors.gold.withValues(alpha: .10),
      onTap: () { Navigator.pop(context); onTap(); },
    );

  Widget _drawer() => Drawer(
    backgroundColor: BaboonColors.background,
    child: SafeArea(child: Column(children: [
      const Padding(padding: EdgeInsets.fromLTRB(17, 18, 17, 18),
        child: Row(children: [
          BaboonAvatar(radius: 25), SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('БАБУИН', style: TextStyle(color: BaboonColors.gold,
              fontWeight: FontWeight.bold, fontSize: 20)),
            Text('Умный помощник', style: TextStyle(color: BaboonColors.muted, fontSize: 12)),
          ])),
        ])),
      const Divider(height: 1),
      _drawerItem(Icons.home_outlined, 'Главная', () => _go(0), active: index == 0),
      _drawerItem(Icons.add_comment_outlined, 'Новый чат', () {
        ChatSessionController.instance.newChat();
        _go(1);
      }),
      _drawerItem(Icons.auto_awesome_outlined, 'Инструменты', () => _go(2), active: index == 2),
      _drawerItem(Icons.menu_book_outlined, 'База знаний', () => _go(3), active: index == 3),
      _drawerItem(Icons.download_outlined, 'Загрузки', () => baboonSoon(context,
        'Загрузки', 'Общий менеджер загрузок появится позже.')),
      _drawerItem(Icons.folder_outlined, 'Мои файлы', () => _go(3)),
      _drawerItem(Icons.history_outlined, 'История', () => _go(1)),
      _drawerItem(Icons.memory_outlined, 'Модели', () => _push(const ModelsHubScreen())),
      _drawerItem(Icons.psychology_outlined, 'Память', () => _push(const MemoryScreen())),
      _drawerItem(Icons.settings_outlined, 'Настройки', () => _go(4), active: index == 4),
      const Spacer(),
      const Divider(height: 1),
      _drawerItem(Icons.info_outline, 'О приложении', () => baboonSoon(context,
        'Бабуин', 'Единая система памяти, инструментов и моделей.')),
    ])),
  );

  @override Widget build(BuildContext context) {
    final pages = <Widget>[
      HomeScreen(onChat: () => _go(1), onTools: () => _go(2),
        onKnowledge: () => _go(3), onSettings: () => _go(4),
        onModels: () => _push(const ModelsHubScreen()), onPhoto: _photo),
      const ChatScreen(),
      ToolsScreen(onChat: () => _go(1), onKnowledge: () => _go(3), onPhoto: _photo),
      const KnowledgeScreen(),
      SettingsScreen(onChat: () => _go(1), onOpenSettings: () => _go(4)),
    ];
    return Scaffold(
      key: shellKey,
      drawer: _drawer(),
      appBar: index == 1 ? PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: _topChat(),
      ) : null,
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF030E18),
          border: Border(top: BorderSide(color: BaboonColors.border)),
        ),
        child: SafeArea(top: false, child: BottomNavigationBar(
          backgroundColor: const Color(0xFF030E18),
          type: BottomNavigationBarType.fixed,
          currentIndex: index,
          selectedItemColor: BaboonColors.gold,
          unselectedItemColor: BaboonColors.muted,
          selectedFontSize: 10,
          unselectedFontSize: 10,
          iconSize: 22,
          elevation: 0,
          onTap: _go,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home_rounded), label: 'Главная'),
            BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_outline_rounded),
              activeIcon: Icon(Icons.chat_bubble_rounded), label: 'Чат'),
            BottomNavigationBarItem(icon: Icon(Icons.widgets_outlined),
              activeIcon: Icon(Icons.widgets), label: 'Инструменты'),
            BottomNavigationBarItem(icon: Icon(Icons.menu_book_outlined),
              activeIcon: Icon(Icons.menu_book), label: 'Знания'),
            BottomNavigationBarItem(icon: Icon(Icons.settings_outlined),
              activeIcon: Icon(Icons.settings), label: 'Настройки'),
          ],
        )),
      ),
    );
  }
}
