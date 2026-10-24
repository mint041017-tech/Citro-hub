import 'dart:convert';
import 'dart:io';

import 'package:citro/overlays/update_dialog.dart';
import 'package:citro/services/updater.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _manifestUri = 'https://obs.chimu-claw.xyz/APK/update.json';
const _listingUri = 'https://obs.chimu-claw.xyz/?prefix=APK/&max-keys=1000';
const _apkUri = 'https://obs.chimu-claw.xyz/APK/Citro-v1.7.11-release.apk';

const _listingXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<ListBucketResult>
  <Contents>
    <Key>APK/Citro-v1.7.9-release.apk</Key>
    <LastModified>2026-10-22T10:00:00.000Z</LastModified>
    <Size>100</Size>
  </Contents>
  <Contents>
    <Key>APK/Citro-v1.7.10-release.apk</Key>
    <LastModified>2026-10-23T19:26:56.203Z</LastModified>
    <Size>200</Size>
  </Contents>
  <Contents>
    <Key>APK/Citro-v1.7.10-debug.apk</Key>
    <LastModified>2026-10-23T20:00:00.000Z</LastModified>
    <Size>999</Size>
  </Contents>
</ListBucketResult>''';

void main() {
  group('UpdateInfo', () {
    test('parses manifest, resolves relative APK URL and computes code', () {
      final info = UpdateInfo.fromJson({
        'version': '1.7.11',
        'url': 'Citro-v1.7.11-release.apk',
        'size': 77265134,
        'notes': ['新增应用内更新', '修复若干问题'],
        'publishedAt': '2026-10-24',
      }, baseUri: Uri.parse(_manifestUri));

      expect(info.url.toString(), _apkUri);
      expect(info.versionCode, 1711);
      expect(info.notes, ['新增应用内更新', '修复若干问题']);
      expect(info.publishedAt, '2026-10-24');
      expect(info.force, isFalse);
      expect(
        info.isNewerThan(
          const InstalledVersion(version: '1.7.10', versionCode: 1710),
        ),
        isTrue,
      );
      expect(
        info.isNewerThan(
          const InstalledVersion(version: '1.7.11', versionCode: 1711),
        ),
        isFalse,
      );
    });

    test('accepts explicit versionCode, newline notes and mandatory flag', () {
      final info = UpdateInfo.fromJson({
        'version': '1.7.11',
        'versionCode': 9999,
        'url': _apkUri,
        'notes': '- 第一条\n- 第二条',
        'mandatory': true,
      });

      expect(info.versionCode, 9999);
      expect(info.notes, ['第一条', '第二条']);
      expect(info.force, isTrue);
    });

    test('rejects non-HTTPS download URLs', () {
      expect(
        () => UpdateInfo.fromJson({
          'version': '1.7.11',
          'url': 'http://obs.chimu-claw.xyz/APK/Citro-v1.7.11-release.apk',
        }),
        throwsFormatException,
      );
    });

    test('compares numeric versions without lexicographic traps', () {
      expect(UpdateInfo.compareVersions('1.7.10', '1.7.9'), greaterThan(0));
      expect(UpdateInfo.compareVersions('1.10.0', '1.9.9'), greaterThan(0));
      expect(UpdateInfo.compareVersions('1.7.10', '1.7.10'), 0);

      final info = UpdateInfo(
        version: '1.7.10',
        versionCode: 0,
        url: Uri.parse(_apkUri),
      );
      expect(
        info.isNewerThan(
          const InstalledVersion(version: '1.7.9', versionCode: 0),
        ),
        isTrue,
      );
    });

    test('picks the newest release package from the OBS listing', () {
      final info = UpdateInfo.latestFromListing(
        _listingXml,
        baseUri: Uri.parse(_listingUri),
      );

      expect(info, isNotNull);
      expect(info!.version, '1.7.10');
      expect(info.versionCode, 1710);
      expect(info.size, 200);
      expect(
        info.url.toString(),
        'https://obs.chimu-claw.xyz/APK/Citro-v1.7.10-release.apk',
      );
      expect(info.publishedAt, '2026-10-23');
    });
  });

  group('UpdateService', () {
    test('prefers update.json when it is available', () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/update.json')) {
          return http.Response(
            jsonEncode({'version': '1.7.11', 'url': _apkUri, 'size': 300}),
            200,
          );
        }
        return http.Response('', 404);
      });
      final service = UpdateService(
        client: client,
        manifestUri: Uri.parse(_manifestUri),
        listingUri: Uri.parse(_listingUri),
      );
      addTearDown(service.close);

      final info = await service.fetchLatest();
      expect(info?.version, '1.7.11');
    });

    test('falls back to the OBS listing when update.json is missing', () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/update.json')) {
          return http.Response('', 404);
        }
        return http.Response(_listingXml, 200);
      });
      final service = UpdateService(
        client: client,
        manifestUri: Uri.parse(_manifestUri),
        listingUri: Uri.parse(_listingUri),
      );
      addTearDown(service.close);

      final info = await service.fetchLatest();
      expect(info?.version, '1.7.10');
      expect(info?.size, 200);
    });

    test('throws a friendly error when both sources fail', () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/update.json')) {
          return http.Response('', 404);
        }
        return http.Response('', 503);
      });
      final service = UpdateService(
        client: client,
        manifestUri: Uri.parse(_manifestUri),
        listingUri: Uri.parse(_listingUri),
      );
      addTearDown(service.close);

      expect(service.fetchLatest(), throwsA(isA<UpdateException>()));
    });
  });

  group('UpdateDownloader', () {
    test('streams the APK to cache and reports progress', () async {
      final directory = await Directory.systemTemp.createTemp(
        'citro-update-test',
      );
      addTearDown(() => directory.delete(recursive: true));

      final payload = List<int>.generate(8192, (i) => i % 256);
      final client = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream.fromIterable([
            payload.sublist(0, 2000),
            payload.sublist(2000),
          ]),
          200,
          contentLength: payload.length,
        );
      });
      addTearDown(client.close);

      final info = UpdateInfo(
        version: '1.7.11',
        versionCode: 1711,
        url: Uri.parse(_apkUri),
        size: payload.length,
      );
      final progress = <int>[];
      final file = await UpdateDownloader(client: client, directory: directory)
          .download(
            info,
            onProgress: (received, total) {
              progress.add(received);
            },
          );

      expect(await file.readAsBytes(), payload);
      expect(progress.last, payload.length);
      expect(file.path, endsWith('/Citro-v1.7.11-release.apk'));
    });

    test('rejects a truncated APK and removes the partial file', () async {
      final directory = await Directory.systemTemp.createTemp(
        'citro-update-test',
      );
      addTearDown(() => directory.delete(recursive: true));

      final payload = List<int>.filled(1024, 7);
      final client = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream.value(payload),
          200,
          contentLength: payload.length,
        );
      });
      addTearDown(client.close);

      final info = UpdateInfo(
        version: '1.7.11',
        versionCode: 1711,
        url: Uri.parse(_apkUri),
        size: payload.length + 1,
      );

      await expectLater(
        UpdateDownloader(client: client, directory: directory).download(info),
        throwsA(isA<UpdateException>()),
      );
      expect(
        await File('${directory.path}/${info.fileName}').exists(),
        isFalse,
      );
    });
  });

  testWidgets('update dialog shows version notes and can be postponed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    UpdateDialogResult? result;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildCitroTheme(CitroColors.light),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await showUpdateDialog(
                    ctx,
                    info: UpdateInfo(
                      version: '1.7.11',
                      versionCode: 1711,
                      url: Uri.parse(_apkUri),
                      size: 77265134,
                      notes: const ['新增应用内更新', '修复若干问题'],
                      publishedAt: '2026-10-24',
                    ),
                    installed: const InstalledVersion(
                      version: '1.7.10',
                      versionCode: 1710,
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.text('最新 v1.7.11'), findsOneWidget);
    expect(find.text('新增应用内更新'), findsOneWidget);
    expect(find.text('立即更新'), findsOneWidget);

    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();
    expect(result, UpdateDialogResult.dismissed);
  });
}
