import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app.dart' show themeModeProvider;
import '../../../../core/database/database_provider.dart';
import '../../providers/settings_state.dart';

class ThemeTile extends StatelessWidget {
  final String current;
  final WidgetRef ref;
  const ThemeTile(this.current, this.ref, {super.key});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: const Text('Theme'),
      subtitle: Text(
        current == 'light'
            ? 'Light'
            : current == 'dark'
            ? 'Dark'
            : 'System',
      ),
      trailing: SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'system', label: Text('Auto')),
          ButtonSegment(value: 'light', label: Text('Light')),
          ButtonSegment(value: 'dark', label: Text('Dark')),
        ],
        selected: {current},
        onSelectionChanged: (val) async {
          await ref.read(settingsDaoProvider).setThemeMode(val.first);
          ref.invalidate(settingsStateProvider);
          ref.invalidate(themeModeProvider);
        },
      ),
    );
  }
}
