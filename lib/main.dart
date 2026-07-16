//main.dart

import 'package:flutter/material.dart';
import 'screens/auth_gate.dart';
import 'services/backend.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  // Backend.init touches platform channels (secure storage for the session,
  // SharedPreferences for the local fallback), so the binding has to exist
  // first. Awaiting it before runApp means AuthGate can read a restored session
  // synchronously on the first frame.
  WidgetsFlutterBinding.ensureInitialized();
  await Backend.init();
  runApp(const ThoughtLoomApp());
}

class ThoughtLoomApp extends StatelessWidget {
  const ThoughtLoomApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: const AuthGate(),
    );
  }
}
