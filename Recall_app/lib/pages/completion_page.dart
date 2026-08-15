import 'package:flutter/material.dart';

import '../learning/first_layer_session.dart';

class CompletionPage extends StatelessWidget {
  const CompletionPage({super.key, required this.summary});

  final FirstLayerSummary summary;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('学习完成')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '本轮学习完成',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                Text('本轮目标单词：${summary.targetWordCount}'),
                Text('第一次直接认识：${summary.firstKnownCount}'),
                Text('第一次不确定：${summary.firstUnsureCount}'),
                Text('第一次不认识：${summary.firstUnknownCount}'),
                Text('经过三次学习：${summary.threeAppearanceCount}'),
                Text('高难词：${summary.difficultWordCount}'),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                  child: const Text('返回首页'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
