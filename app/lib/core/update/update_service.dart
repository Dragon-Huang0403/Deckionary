import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import '../config.dart';
import '../logging/logging_service.dart';

class UpdateInfo {
  final String latestVersion;
  final String currentVersion;
  final String releaseUrl;
  final String? releaseNotes;

  UpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    required this.releaseUrl,
    this.releaseNotes,
  });

  bool get hasUpdate => _compareVersions(latestVersion, currentVersion) > 0;
}

/// Returns update info if a newer version exists, null otherwise.
/// Fails silently — update checks should never block the app.
Future<UpdateInfo?> checkForUpdate() async {
  try {
    final response = await http
        .get(
          Uri.parse('https://api.github.com/repos/$githubRepo/releases/latest'),
          headers: {'Accept': 'application/vnd.github.v3+json'},
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) return null;

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final tagName = json['tag_name'] as String? ?? '';
    final latestVersion = tagName.startsWith('v')
        ? tagName.substring(1)
        : tagName;
    final releaseUrl =
        json['html_url'] as String? ??
        'https://github.com/$githubRepo/releases/latest';
    final releaseNotes = json['body'] as String?;

    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;

    final info = UpdateInfo(
      latestVersion: latestVersion,
      currentVersion: currentVersion,
      releaseUrl: releaseUrl,
      releaseNotes: releaseNotes,
    );

    return info.hasUpdate ? info : null;
  } catch (e, st) {
    globalTalker.error('[UPDATE] Update check failed', e, st);
    return null;
  }
}

/// Compare two semver strings. Returns positive if a > b.
int _compareVersions(String a, String b) {
  final aParts = a.split('.').map((s) => int.tryParse(s) ?? 0).toList();
  final bParts = b.split('.').map((s) => int.tryParse(s) ?? 0).toList();
  final len = aParts.length > bParts.length ? aParts.length : bParts.length;
  for (var i = 0; i < len; i++) {
    final av = i < aParts.length ? aParts[i] : 0;
    final bv = i < bParts.length ? bParts[i] : 0;
    if (av != bv) return av - bv;
  }
  return 0;
}
