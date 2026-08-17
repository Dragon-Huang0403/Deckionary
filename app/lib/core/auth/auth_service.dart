import 'dart:async';
import 'dart:io' show Platform;

import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../logging/logging_service.dart';

/// Deep link Supabase redirects to after browser-based OAuth. The scheme is
/// registered in macos/Runner/Info.plist, and this exact URL must be listed under
/// Authentication -> URL Configuration in the Supabase dashboard.
const _oauthRedirect = 'com.deckionary.deckionary://login-callback';

/// How long to wait for the user to finish signing in in their browser.
const _browserSignInTimeout = Duration(minutes: 5);

class AuthService {
  final _googleSignIn = GoogleSignIn.instance;
  final _supabase = Supabase.instance.client;

  String? get currentUserId => _supabase.auth.currentUser?.id;
  bool get isSignedIn => _supabase.auth.currentUser != null;
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  /// Sign in with Google, then create a Supabase session.
  ///
  /// macOS goes through the system browser instead of the native SDK. The
  /// GoogleSignIn SDK stores tokens in the data-protection keychain, which needs a
  /// `keychain-access-groups` entitlement; `$(AppIdentifierPrefix)` in that
  /// entitlement only resolves from a real provisioning profile, so on any build
  /// signed ad-hoc — including every published macOS release — it fails with
  /// `GoogleSignInException(providerConfigurationError, keychain error)`.
  /// Browser OAuth touches no keychain: supabase_flutter keeps the session in
  /// shared_preferences.
  Future<void> signInWithGoogle() async {
    try {
      if (Platform.isMacOS) {
        await _signInViaBrowser();
      } else {
        await _signInViaGoogleSdk();
      }
      globalTalker.info('[AUTH] Supabase sign-in successful');
    } catch (e, st) {
      globalTalker.error('[AUTH] Sign in failed', e, st);
      rethrow;
    }
  }

  /// Opens the system browser and waits for Supabase to pick up the deep link.
  ///
  /// Returning early is not an option: callers sync straight after awaiting this,
  /// and signInWithOAuth completes as soon as the browser opens, long before a
  /// session exists.
  Future<void> _signInViaBrowser() async {
    globalTalker.info('[AUTH] Starting browser OAuth...');

    // Subscribe before launching. onAuthStateChange is not replayed, so a fast
    // callback would otherwise land before there is a listener.
    final signedIn = _supabase.auth.onAuthStateChange.firstWhere(
      (state) => state.event == AuthChangeEvent.signedIn,
    );

    await _supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: _oauthRedirect,
      // macOS has no in-app webview; the default would fall back to one on mobile.
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
    globalTalker.info('[AUTH] Browser opened, waiting for callback...');

    await signedIn.timeout(
      _browserSignInTimeout,
      onTimeout: () => throw TimeoutException(
        'No sign-in callback received. Check that $_oauthRedirect is listed as a '
        'redirect URL in the Supabase dashboard.',
        _browserSignInTimeout,
      ),
    );
  }

  Future<void> _signInViaGoogleSdk() async {
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
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }
}
