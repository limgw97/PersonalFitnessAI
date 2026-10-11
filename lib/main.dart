import 'package:flutter/material.dart';

import 'dev/siwc_spike_page.dart';

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
      // TODO: ChatGPT 로그인 검증이 끝나면 온보딩/캘린더 화면으로 교체
      home: const SiwcSpikePage(),
    );
  }
}
