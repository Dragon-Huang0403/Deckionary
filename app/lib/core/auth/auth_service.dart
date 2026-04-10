import 'package:firebase_auth/firebase_auth.dart' as firebase;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final _firebaseAuth = firebase.FirebaseAuth.instance;
  final _googleSignIn = GoogleSignIn.instance;
  final _supabase = Supabase.instance.client;

  /// Current Supabase user ID (null if not signed in)
  String? get currentUserId => _supabase.auth.currentUser?.id;

  bool get isSignedIn => _supabase.auth.currentUser != null;

  /// Stream of auth state changes (Supabase session)
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  /// Sign in with Google via Firebase, then exchange for Supabase session.
  Future<void> signInWithGoogle() async {
    // 1. Google Sign-In (v7 API: singleton + authenticate)
    final googleAccount = await _googleSignIn.authenticate();
    final googleIdToken = googleAccount.authentication.idToken;

    // 2. Firebase Auth with Google credential
    final credential = firebase.GoogleAuthProvider.credential(
      idToken: googleIdToken,
    );
    await _firebaseAuth.signInWithCredential(credential);

    // 3. Get Firebase ID token and exchange for Supabase session
    final firebaseIdToken = await _firebaseAuth.currentUser?.getIdToken();
    if (firebaseIdToken == null) throw Exception('Failed to get Firebase ID token');

    await _supabase.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: firebaseIdToken,
    );
  }

  /// Sign out from all services.
  Future<void> signOut() async {
    await _supabase.auth.signOut();
    await _firebaseAuth.signOut();
  }
}
