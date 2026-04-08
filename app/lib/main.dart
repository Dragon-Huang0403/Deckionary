import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/database/database_provider.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initDatabases();

  runApp(
    const ProviderScope(
      child: OxfordDictionaryApp(),
    ),
  );
}
