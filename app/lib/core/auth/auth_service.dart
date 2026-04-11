import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final _googleSignIn = GoogleSignIn.instance;
  final _supabase = Supabase.instance.client;

  String? get currentUserId => _supabase.auth.currentUser?.id;
  bool get isSignedIn => _supabase.auth.currentUser != null;
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  /// Sign in with Google, then create Supabase session directly.
  Future<void> signInWithGoogle() async {
    try {
      debugPrint('[AUTH] Starting Google Sign-In...');
      final googleAccount = await _googleSignIn.authenticate();
      debugPrint('[AUTH] Google account: ${googleAccount.email}');
      final idToken = googleAccount.authentication.idToken;
      debugPrint('[AUTH] ID token received: ${idToken != null}');
      if (idToken == null) throw Exception('No ID token from Google Sign-In');

      debugPrint('[AUTH] Signing in to Supabase with ID token...');
      await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
      );
      debugPrint('[AUTH] Supabase sign-in successful');
    } catch (e, st) {
      debugPrint('[AUTH] Sign in failed: $e');
      debugPrint('[AUTH] Stack trace: $st');
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }
}
