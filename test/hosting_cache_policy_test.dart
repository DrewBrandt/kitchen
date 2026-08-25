import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Firebase revalidates every web entry file', () {
    final config =
        jsonDecode(File('firebase.json').readAsStringSync())
            as Map<String, dynamic>;
    final hosting = config['hosting'] as Map<String, dynamic>;
    final headers = hosting['headers'] as List<dynamic>;

    expect(
      headers,
      contains(
        predicate<Map<String, dynamic>>(
          (rule) =>
              rule['source'] == '**/*.@(html|js|json)' &&
              (rule['headers'] as List<dynamic>).any(
                (header) =>
                    header['key'] == 'Cache-Control' &&
                    header['value'] == 'no-cache, must-revalidate',
              ),
        ),
      ),
    );
  });

  test('web startup retires legacy Flutter service workers', () {
    final index = File('web/index.html').readAsStringSync();

    expect(index, contains('navigator.serviceWorker.getRegistrations()'));
    expect(index, contains('item.unregister()'));
    expect(index, contains("const marker = '_pantry_sw_retired'"));
    expect(index, contains('location.replace(reloadUrl)'));
    expect(index, contains("bootstrap.src = 'flutter_bootstrap.js'"));
  });
}
