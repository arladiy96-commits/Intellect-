import 'package:flutter/material.dart';
import '../../ui/baboon_style.dart';

/// Design-preview page; actual PDF reader will be a separate future module.
class TextbookPreviewScreen extends StatelessWidget {
  const TextbookPreviewScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Просмотр учебника'), actions: [
      IconButton(icon: const Icon(Icons.more_horiz), onPressed: () => baboonSoon(
        context, 'Просмотр PDF', 'Полноценный PDF-ридер добавим позже.')),
    ]),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: const [
        Icon(Icons.menu_book_outlined, size: 19, color: BaboonColors.gold),
        SizedBox(width: 8),
        Expanded(child: Text('Математика · 2 класс · образец',
          style: TextStyle(fontWeight: FontWeight.bold))),
      ]),
      const SizedBox(height: 10),
      ClipRRect(borderRadius: BorderRadius.circular(12),
        child: Image.asset('assets/images/textbook_demo.jpg', fit: BoxFit.fitWidth)),
      const SizedBox(height: 12),
      const Text('Образец экрана из референса. Точные страницы станут доступны '
        'после добавления поддержки PDF и индексации учебников.',
        style: TextStyle(color: BaboonColors.muted)),
    ]),
  );
}
