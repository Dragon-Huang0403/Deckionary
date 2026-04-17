import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talker_riverpod_logger/talker_riverpod_logger.dart';
import 'package:window_manager/window_manager.dart';
import 'firebase_options.dart';
import 'core/build_info.dart';
import 'core/config.dart';
import 'core/database/database_provider.dart';
import 'core/database/settings_dao.dart';
import 'core/logging/logging_service.dart';
import 'app.dart';

/// Whether Firebase + Supabase auth/sync is available.
/// False until Firebase project is configured.
bool syncEnabled = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isMacOS) {
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
  }

  // Initialize databases + sync services before runApp so that
  // globalTalker is fully configured when TalkerRiverpodObserver captures it.
  try {
    await Future.wait([initDatabases(), _initSyncServices()]);
    await initLogging(
      settingsDao: SettingsDao(globalUserDb),
      supabaseClient: syncEnabled ? Supabase.instance.client : null,
    );
  } catch (e) {
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: Text('Failed to start: $e'))),
      ),
    );
    return;
  }

  if (sentryDsn.isNotEmpty) {
    await SentryFlutter.init((options) {
      options.dsn = sentryDsn;
      options.environment = sentryEnvironment;
      options.release = 'deckionary@$appVersion';
      options.dist = appBuildNumber.toString();
    }, appRunner: () => _runApp());
  } else {
    _runApp();
  }
}

Future<void> _initSyncServices() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    if (supabaseAnonKey.isNotEmpty) {
      await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
      await GoogleSignIn.instance.initialize(
        serverClientId:
            '43742335452-ef9piond4ujid0ulcf3695857s938urc.apps.googleusercontent.com',
      );
      syncEnabled = true;
    }
  } catch (e) {
    globalTalker.warning('[INIT] sync services not available: $e');
  }
}

void _runApp() {
  runApp(
    ProviderScope(
      observers: [TalkerRiverpodObserver(talker: globalTalker)],
      child: const DeckionaryApp(),
    ),
  );
}
