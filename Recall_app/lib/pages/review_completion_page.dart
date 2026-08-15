import 'package:flutter/material.dart';

class ReviewSummary {
  const ReviewSummary({
    required this.total,
    required this.known,
    required this.unsure,
    required this.unknown,
    required this.knownNormal,
    required this.knownSlow,
  });

  final int total;
  final int known;
  final int unsure;
  final int unknown;
  final int knownNormal;
  final int knownSlow;
}

class ReviewCompletionPage extends StatelessWidget {
  const ReviewCompletionPage({super.key, required this.summary});

  final ReviewSummary summary;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('复习完成')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('今日复习完成', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 24),
            Text('本次复习总数：${summary.total}'),
            Text('认识：${summary.known}'),
            Text('其中正常：${summary.knownNormal}'),
            Text('其中很慢：${summary.knownSlow}'),
            Text('不确定：${summary.unsure}'),
            Text('不认识：${summary.unknown}'),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).popUntil((route) => route.isFirst),
              child: const Text('返回首页'),
            ),
          ],
        ),
      ),
    );
  }
}
