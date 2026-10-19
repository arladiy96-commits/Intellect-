import 'package:flutter/material.dart';

/// Palette and reusable elements taken from the approved Baboon concept.
abstract final class BaboonColors {
  static const background = Color(0xFF020A11);
  static const surface = Color(0xFF0C1B29);
  static const surfaceLight = Color(0xFF122638);
  static const gold = Color(0xFFF0C17B);
  static const goldDark = Color(0xFFBA813B);
  static const text = Color(0xFFF2F5FA);
  static const muted = Color(0xFF9FB0C1);
  static const border = Color(0xFF20384B);
  static const blue = Color(0xFF244C80);
}

ThemeData baboonTheme() {
  final colors = ColorScheme.fromSeed(
    seedColor: BaboonColors.gold,
    brightness: Brightness.dark,
    surface: BaboonColors.background,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colors,
    scaffoldBackgroundColor: BaboonColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: BaboonColors.background,
      foregroundColor: BaboonColors.text,
      elevation: 0,
    ),
    textTheme: const TextTheme(
      titleLarge: TextStyle(color: BaboonColors.text, fontWeight: FontWeight.w700),
      titleMedium: TextStyle(color: BaboonColors.text, fontWeight: FontWeight.w700),
      bodyMedium: TextStyle(color: BaboonColors.text),
      bodySmall: TextStyle(color: BaboonColors.muted),
    ),
    dividerColor: BaboonColors.border,
    cardColor: BaboonColors.surface,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: BaboonColors.surface,
      hintStyle: const TextStyle(color: BaboonColors.muted),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: BaboonColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: BaboonColors.gold),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(11)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: BaboonColors.surface,
      selectedColor: BaboonColors.gold,
      labelStyle: const TextStyle(color: BaboonColors.text, fontSize: 12),
      secondaryLabelStyle: const TextStyle(color: Colors.black),
      side: const BorderSide(color: BaboonColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: BaboonColors.gold,
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}

class BaboonPanel extends StatelessWidget {
  const BaboonPanel({super.key, required this.child, this.padding = const EdgeInsets.all(13), this.onTap});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [BaboonColors.surfaceLight, BaboonColors.surface],
          ),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: BaboonColors.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class BaboonAvatar extends StatelessWidget {
  const BaboonAvatar({super.key, this.radius = 18});
  final double radius;
  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: radius,
    backgroundColor: BaboonColors.goldDark,
    child: CircleAvatar(
      radius: radius - 1.5,
      backgroundImage: const AssetImage('assets/images/baboon_avatar.png'),
    ),
  );
}

class BaboonTitle extends StatelessWidget {
  const BaboonTitle(this.title, {super.key, this.subtitle});
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
      if (subtitle != null) Text(subtitle!, style: const TextStyle(color: BaboonColors.muted, fontSize: 12)),
    ],
  );
}

class BaboonFeatureTile extends StatelessWidget {
  const BaboonFeatureTile({super.key, required this.icon, required this.title,
    required this.subtitle, required this.color, this.onTap, this.soon = false});
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;
  final bool soon;
  @override
  Widget build(BuildContext context) => BaboonPanel(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
    onTap: onTap,
    child: Row(children: [
      Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: .22), borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, size: 22, color: color),
      ),
      const SizedBox(width: 9),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
        Text(soon ? 'Скоро · $subtitle' : subtitle,
          maxLines: 2, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10, color: BaboonColors.muted)),
      ])),
    ]),
  );
}

void baboonSoon(BuildContext context, String title, String explanation) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: BaboonColors.surface,
    builder: (context) => SafeArea(child: Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 30),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.construction_outlined, color: BaboonColors.gold, size: 40),
        const SizedBox(height: 12),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(explanation, textAlign: TextAlign.center,
          style: const TextStyle(color: BaboonColors.muted)),
        const SizedBox(height: 18),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Понятно')),
      ]),
    )),
  );
}
