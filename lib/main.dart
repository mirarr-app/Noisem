import 'package:Noisem/homepage.dart';
import 'package:flutter/material.dart';
import 'package:nes_ui/nes_ui.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorObservers: [
        PosthogObserver(),
      ],
      title: 'Noisem',
      home: const Homepage(),
      debugShowCheckedModeBanner: false,
      theme: flutterNesTheme(),
    );
  }
}
