import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

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
  String _backupSize = '';
  List<FileSystemEntity> _backups = [];

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
    _backupSize = await widget.store.backupSizeText;
    _backups = await widget.store.listBackups();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _reload() async {
    _backupSize = await widget.store.backupSizeText;
    _backups = await widget.store.listBackups();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _save() async {
    await widget.store.saveModelConfig(
      baseUrl: _baseUrlController.text.trim(),
      modelName: _modelNameController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('模型配置已保存')));
  }

  Future<void> _createBackup() async {
    try {
      final path = await widget.store.exportBackupJson();
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('备份已创建'),
        action: SnackBarAction(
          label: '分享',
          onPressed: () {
            Share.shareXFiles([XFile(path)], text: 'BMB 数据备份');
          },
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('备份失败: $e')));
    }
  }

  Future<void> _shareBackup(File file) async {
    Share.shareXFiles([XFile(file.path)], text: 'BMB 数据备份');
  }

  Future<void> _restoreFromBackup(FileSystemEntity file) async {
    final path = (file as File).path;
    final name = path.split('\\').last.split('/').last;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复数据'),
        content: Text('将从「$name」恢复全部数据，确定继续？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('恢复')),
        ],
      ),
    );
    if (confirmed != true) return;

    final ok = await widget.store.restoreFromJsonFile(path);
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? '数据恢复成功' : '恢复失败'),
    ));
  }

  Future<void> _deleteBackup(FileSystemEntity file) async {
    final path = (file as File).path;
    final name = path.split('\\').last.split('/').last;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除备份'),
        content: Text('确定删除「$name」？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await widget.store.deleteBackup(path);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildModelConfigCard(),
                const SizedBox(height: 12),
                _buildBackupCard(),
              ],
            ),
    );
  }

  // ─── 模型配置卡片 ───

  Widget _buildModelConfigCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('模型配置',
                style:
                    TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text('配置 OpenAI 兼容模型连接参数',
                style: TextStyle(color: Color(0xFFA6ABB2))),
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
    );
  }

  // ─── 数据管理卡片 ───

  Widget _buildBackupCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('数据管理',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const Spacer(),
                if (_backupSize.isNotEmpty)
                  Text(_backupSize,
                      style:
                          const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 6),
            const Text('备份文件保存在「下载/BMB_Backups」文件夹，重装应用后仍然保留',
                style: TextStyle(color: Color(0xFFA6ABB2), fontSize: 13)),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _createBackup,
                icon: const Icon(Icons.backup_outlined, size: 18),
                label: const Text('新建备份'),
              ),
            ),
            if (_backups.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 8),
              ..._backups.map((f) => _buildBackupItem(f as File)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBackupItem(File file) {
    final path = file.path;
    final name = path.split('\\').last.split('/').last;
    final modified = file.lastModifiedSync();
    final size = file.lengthSync();
    final sizeText = size < 1024
        ? '$size B'
        : size < 1024 * 1024
            ? '${(size / 1024).toStringAsFixed(1)} KB'
            : '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    final dateStr =
        '${modified.month}/${modified.day} ${modified.hour.toString().padLeft(2, '0')}:${modified.minute.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D20),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.description_outlined, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 2),
                Text('$dateStr · $sizeText',
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _shareBackup(file),
            icon: const Icon(Icons.share_outlined, size: 18),
            tooltip: '分享',
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            onPressed: () => _restoreFromBackup(file),
            icon: const Icon(Icons.restore_outlined, size: 18),
            tooltip: '恢复',
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            onPressed: () => _deleteBackup(file),
            icon: const Icon(Icons.delete_outline, size: 18),
            tooltip: '删除',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
