import 'package:flutter/material.dart';

import '../data/daily_task_repository.dart';
import '../data/learning_repository.dart';

class NewWordSettingsPage extends StatefulWidget {
  const NewWordSettingsPage({super.key, required this.repository});

  final LearningRepository repository;

  @override
  State<NewWordSettingsPage> createState() => _NewWordSettingsPageState();
}

class _NewWordSettingsPageState extends State<NewWordSettingsPage> {
  static const _presets = [10, 20, 30, 50];
  late Future<int> _targetFuture;

  @override
  void initState() {
    super.initState();
    _targetFuture = widget.repository.getDailyNewWordTarget();
  }

  Future<void> _save(int value) async {
    await widget.repository.setDailyNewWordTarget(value);
    if (mounted) {
      setState(() {
        _targetFuture = Future.value(value);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('每日新词设置已保存')));
    }
  }

  Future<void> _customize(int current) async {
    var input = '$current';
    String? errorText;
    final value = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('自定义每日新词'),
          content: TextFormField(
            initialValue: input,
            autofocus: true,
            keyboardType: TextInputType.number,
            onChanged: (value) {
              input = value;
              if (errorText != null) {
                setDialogState(() => errorText = null);
              }
            },
            decoration: InputDecoration(
              helperText: '允许 1～200',
              errorText: errorText,
              labelText: '单词数',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final parsed = int.tryParse(input.trim());
                if (parsed == null ||
                    parsed <
                        VocabularySettingsDefaults.minimumDailyNewWordTarget ||
                    parsed >
                        VocabularySettingsDefaults.maximumDailyNewWordTarget) {
                  setDialogState(() => errorText = '请输入 1～200 之间的整数');
                  return;
                }
                Navigator.pop(context, parsed);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (value != null) await _save(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('每日新词设置')),
      body: FutureBuilder<int>(
        future: _targetFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final current = snapshot.requireData;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const ListTile(
                title: Text('新数量从今天开始生效'),
                subtitle: Text('调高后会补充今天的剩余新词；调低时不会删除已经开始学习的单词。'),
              ),
              for (final value in _presets)
                ListTile(
                  leading: Icon(
                    current == value
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  title: Text('$value 个'),
                  onTap: () => _save(value),
                ),
              ListTile(
                title: const Text('自定义'),
                trailing: _presets.contains(current)
                    ? null
                    : Text('$current 个'),
                onTap: () => _customize(current),
              ),
            ],
          );
        },
      ),
    );
  }
}
