import 'package:flutter/material.dart';

void main() {
  runApp(const FitMindApp());
}

class FitMindApp extends StatelessWidget {
  const FitMindApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FitMind',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      // TODO: 캘린더 화면이 생기면 교체
      home: const Scaffold(body: Center(child: Text('FitMind'))),
    );
  }
}
