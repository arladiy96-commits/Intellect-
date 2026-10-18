import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Uses only public GitHub Releases. The Android installer always requests consent.
class BaboonUpdateService {
  static const _repo = 'arladiy96-commits/Intellect-';
  static const _channel = MethodChannel('baboon/update');
  static const _api = 'https://api.github.com/repos/$_repo/releases/latest';

  Future<int> installedBuild() async =>
      (await _channel.invokeMethod<int>('buildNumber')) ?? 0;

  Future<UpdateRelease?> checkAvailable() async {
    final body = await _fetchText(_api);
    final data = jsonDecode(body) as Map<String, dynamic>;
    final tag = (data['tag_name'] as String?) ?? '';
    final match = RegExp(r'^v[0-9]+\.[0-9]+\.([0-9]+)$').firstMatch(tag);
    if (match == null) throw const FormatException('Неизвестный формат версии в Releases');
    final build = int.parse(match.group(1)!);
    if (build <= await installedBuild()) return null;

    final assets = (data['assets'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>();
    Map<String, dynamic>? apk;
    Map<String, dynamic>? checksum;
    for (final a in assets) {
      final name = (a['name'] as String?) ?? '';
      if (name == 'baboon-$tag.apk') apk = a;
      if (name == 'baboon-$tag.apk.sha256') checksum = a;
    }
    if (apk == null || checksum == null) {
      throw const FormatException('В релизе отсутствует APK или контрольная сумма');
    }
    final apkUrl = apk['browser_download_url'] as String;
    final checksumUrl = checksum['browser_download_url'] as String;
    const prefix = 'https://github.com/$_repo/releases/download/';
    if (!apkUrl.startsWith(prefix) || !checksumUrl.startsWith(prefix)) {
      throw const FormatException('Неожиданный адрес скачивания');
    }
    final notes = (data['body'] as String? ?? '').trim();
    return UpdateRelease(
      tag: tag,
      buildNumber: build,
      apkUrl: apkUrl,
      checksumUrl: checksumUrl,
      releaseNotes: notes,
    );
  }

  Future<String> download(UpdateRelease release,
      {void Function(double value)? onProgress}) async {
    final checksumContent = await _fetchText(release.checksumUrl);
    final expected = RegExp(r'^[a-fA-F0-9]{64}').firstMatch(checksumContent.trim());
    if (expected == null) throw const FormatException('Неверная контрольная сумма релиза');
    release.expectedSha256 = expected.group(0)!.toLowerCase();

    final cachePath = await _channel.invokeMethod<String>('cachePath');
    if (cachePath == null) throw const FileSystemException('Кэш обновлений недоступен');
    final directory = Directory(cachePath);
    await directory.create(recursive: true);
    final tempFile = File('${directory.path}/baboon-update-${release.buildNumber}.part');
    final destFile = File('${directory.path}/baboon-update-${release.buildNumber}.apk');
    if (await tempFile.exists()) await tempFile.delete();

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(Uri.parse(release.apkUrl));
      request.headers.set(HttpHeaders.userAgentHeader, 'Baboon-Android-Updater');
      final response = await request.close().timeout(const Duration(seconds: 25));
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Ошибка загрузки APK: HTTP ${response.statusCode}');
      }
      final total = response.contentLength;
      var received = 0;
      final sink = tempFile.openWrite();
      try {
        await for (final bytes in response.timeout(const Duration(seconds: 45))) {
          sink.add(bytes);
          received += bytes.length;
          if (total > 0) onProgress?.call((received / total).clamp(0, 1).toDouble());
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (received == 0) throw const FileSystemException('Получен пустой файл APK');
      if (await destFile.exists()) await destFile.delete();
      await tempFile.rename(destFile.path);
      onProgress?.call(1);
      return destFile.path;
    } catch (_) {
      if (await tempFile.exists()) await tempFile.delete();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  Future<String> install(UpdateRelease release) async {
    if (release.expectedSha256 == null) {
      throw StateError('APK ещё не загружен');
    }
    return await _channel.invokeMethod<String>('installVerified', {
          'fileName': 'baboon-update-${release.buildNumber}.apk',
          'sha256': release.expectedSha256,
        }) ??
        'unknown';
  }

  static Future<String> _fetchText(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.userAgentHeader, 'Baboon-Android-Updater');
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final response = await request.close().timeout(const Duration(seconds: 25));
      if (response.statusCode == HttpStatus.notFound) {
        throw const HttpException('Пока нет опубликованной стабильной версии в Releases');
      }
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('GitHub вернул HTTP ${response.statusCode}');
      }
      return await utf8.decoder.bind(response).join().timeout(const Duration(seconds: 30));
    } finally {
      client.close(force: true);
    }
  }
}

class UpdateRelease {
  UpdateRelease({
    required this.tag,
    required this.buildNumber,
    required this.apkUrl,
    required this.checksumUrl,
    required this.releaseNotes,
  });

  final String tag;
  final int buildNumber;
  final String apkUrl;
  final String checksumUrl;
  final String releaseNotes;
  String? expectedSha256;
}
