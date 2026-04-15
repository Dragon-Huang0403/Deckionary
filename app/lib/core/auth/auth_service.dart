import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../logging/logging_service.dart';

class AuthService {
  final _googleSignIn = GoogleSignIn.instance;
  final _supabase = Supabase.instance.client;

  String? get currentUserId => _supabase.auth.currentUser?.id;
  bool get isSignedIn => _supabase.auth.currentUser != null;
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  /// Sign in with Google, then create Supabase session directly.
  Future<void> signInWithGoogle() async {
    try {
      globalTalker.info('[AUTH] Starting Google Sign-In...');
      final googleAccount = await _googleSignIn.authenticate();
      globalTalker.info('[AUTH] Google account: ${googleAccount.email}');
      final idToken = googleAccount.authentication.idToken;
      globalTalker.info('[AUTH] ID token received: ${idToken != null}');
      if (idToken == null) throw Exception('No ID token from Google Sign-In');

      globalTalker.info('[AUTH] Signing in to Supabase with ID token...');
      await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
      );
      globalTalker.info('[AUTH] Supabase sign-in successful');
    } catch (e, st) {
      globalTalker.error('[AUTH] Sign in failed', e, st);
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }
}
