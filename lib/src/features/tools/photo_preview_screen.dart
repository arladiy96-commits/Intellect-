import 'package:flutter/material.dart';
import '../../ui/baboon_style.dart';

/// Approved visual reference only. OCR is not yet implemented in this version.
class PhotoPreviewScreen extends StatelessWidget {
  const PhotoPreviewScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Распознавание фото')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      ClipRRect(borderRadius: BorderRadius.circular(13),
        child: AspectRatio(aspectRatio: 1.25,
          child: Image.asset('assets/images/photo_demo.jpg', fit: BoxFit.cover))),
      const SizedBox(height: 13),
      const BaboonPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Распознанный текст', style: TextStyle(fontWeight: FontWeight.w700)),
        SizedBox(height: 10),
        Text('2. Вычисли:\n37 + 28 =\n64 - 27 =\n53 + 19 =',
          style: TextStyle(color: BaboonColors.muted, height: 1.45)),
      ])),
      const SizedBox(height: 12),
      const Text('Это макет из утверждённого референса. '
        'Настоящее OCR-распознавание и загрузку фотографий добавим позднее.',
        style: TextStyle(color: BaboonColors.muted)),
      const SizedBox(height: 15),
      FilledButton(onPressed: () => baboonSoon(context, 'OCR фотографий',
        'Модуль распознавания будет подключён в следующем этапе.'),
        child: const Text('Использовать в чате')),
    ]),
  );
}
