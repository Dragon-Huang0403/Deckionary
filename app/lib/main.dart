import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'firebase_options.dart';
import 'core/config.dart';
import 'core/database/database_provider.dart';
import 'app.dart';

/// Whether Firebase + Supabase auth/sync is available.
/// False until Firebase project is configured.
bool syncEnabled = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initDatabases();

  // Firebase + Supabase init (skip gracefully if not configured)
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    if (supabaseAnonKey.isNotEmpty) {
      await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
      await GoogleSignIn.instance.initialize();
      syncEnabled = true;
    }
  } catch (e) {
    debugPrint('Sync services not available: $e');
  }

  runApp(
    const ProviderScope(
      child: DeckionaryApp(),
    ),
  );
}
