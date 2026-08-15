import 'package:flutter/material.dart';

import '../settings/ai_service_settings.dart';

class AiServiceSettingsPage extends StatefulWidget {
  const AiServiceSettingsPage({super.key, required this.settings});

  final AiServiceSettings settings;

  @override
  State<AiServiceSettingsPage> createState() => _AiServiceSettingsPageState();
}

class _AiServiceSettingsPageState extends State<AiServiceSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _tokenController = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final configuration = await widget.settings.load();
    if (!mounted) return;
    _urlController.text = configuration.backendUrl;
    _tokenController.text = configuration.accessToken;
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() => _saving = true);
    try {
      await widget.settings.save(
        AiServiceConfiguration(
          backendUrl: _urlController.text,
          accessToken: _tokenController.text,
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('AI 服务设置已保存')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 服务设置')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const Text(
                    '这里只配置 Recall 自己的 Worker。不要在 App 中输入任何 AI 厂商 API Key。',
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    key: const ValueKey('ai-backend-url'),
                    controller: _urlController,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Backend URL',
                      hintText: 'https://recall-ai.example.workers.dev',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final uri = Uri.tryParse(value?.trim() ?? '');
                      if (uri == null ||
                          !uri.hasAuthority ||
                          (uri.scheme != 'https' && uri.scheme != 'http')) {
                        return '请输入有效的 HTTP(S) Worker 地址';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    key: const ValueKey('ai-backend-token'),
                    controller: _tokenController,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Backend Access Token',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => (value?.trim().isEmpty ?? true)
                        ? '请输入 Recall Worker 访问令牌'
                        : null,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: const Text('保存'),
                  ),
                ],
              ),
            ),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }
}
