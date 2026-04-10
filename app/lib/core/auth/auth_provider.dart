import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../main.dart';
import 'auth_service.dart';

final authServiceProvider = Provider<AuthService?>((ref) {
  if (!syncEnabled) return null;
  return AuthService();
});

/// Stream of Supabase auth state changes.
final authStateProvider = StreamProvider<AuthState?>((ref) {
  final service = ref.read(authServiceProvider);
  if (service == null) return const Stream.empty();
  return service.authStateChanges;
});
