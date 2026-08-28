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

    expect(hosting['public'], 'dist');

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

  test('web-native startup retires legacy Flutter service workers', () {
    final index = File('index.html').readAsStringSync();

    expect(index, contains('navigator.serviceWorker.getRegistrations()'));
    expect(index, contains('registration.unregister()'));
    expect(index, contains('/src/main.tsx'));
  });
}
