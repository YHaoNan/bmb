import 'package:flutter/material.dart';

import 'template_store.dart';

class ModelConfigPage extends StatefulWidget {
  const ModelConfigPage({super.key, required this.store});

  final TemplateStore store;

  @override
  State<ModelConfigPage> createState() => _ModelConfigPageState();
}

class _ModelConfigPageState extends State<ModelConfigPage> {
  final _baseUrlController = TextEditingController();
  final _modelNameController = TextEditingController();
  final _apiKeyController = TextEditingController();
  bool _loading = true;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _modelNameController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final config = await widget.store.loadModelConfig();
    _baseUrlController.text = config['baseUrl'] ?? '';
    _modelNameController.text = config['modelName'] ?? '';
    _apiKeyController.text = config['apiKey'] ?? '';
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    await widget.store.saveModelConfig(
      baseUrl: _baseUrlController.text.trim(),
      modelName: _modelNameController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('模型配置已保存')));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('模型配置', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        const Text('配置 OpenAI 兼容模型连接参数', style: TextStyle(color: Color(0xFFA6ABB2))),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _baseUrlController,
                          decoration: const InputDecoration(
                            labelText: 'Base URL',
                            hintText: '例如：https://api.openai.com/v1',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _modelNameController,
                          decoration: const InputDecoration(
                            labelText: 'Model Name',
                            hintText: '例如：gpt-4.1-mini',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _apiKeyController,
                          obscureText: _obscure,
                          decoration: InputDecoration(
                            labelText: 'API Key',
                            suffixIcon: IconButton(
                              onPressed: () => setState(() => _obscure = !_obscure),
                              icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _save,
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('保存配置'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
