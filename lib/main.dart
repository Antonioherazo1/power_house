// lib/main.dart
import 'package:flutter/material.dart';
import 'services/background_service.dart';
import 'screens/energy_monitor_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeService();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Monitor de Energía',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: EnergyMonitorScreen(),
    );
  }
}
