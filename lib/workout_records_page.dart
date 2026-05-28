import 'package:flutter/material.dart';

import 'models.dart';
import 'template_store.dart';
import 'workout_models.dart';
import 'workout_page.dart';
import 'workout_summary_page.dart';

class WorkoutRecordsPage extends StatefulWidget {
  const WorkoutRecordsPage({super.key, required this.store, this.reloadSignal});

  final TemplateStore store;
  final ValueNotifier<int>? reloadSignal;

  @override
  State<WorkoutRecordsPage> createState() => _WorkoutRecordsPageState();
}

class _WorkoutRecordsPageState extends State<WorkoutRecordsPage> {
  List<WorkoutSession> _workouts = [];
  List<TrainingTemplate> _templates = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
    widget.reloadSignal?.addListener(_onReloadSignal);
  }

  @override
  void dispose() {
    widget.reloadSignal?.removeListener(_onReloadSignal);
    super.dispose();
  }

  void _onReloadSignal() {
    if (mounted) _reload();
  }

  Future<void> _reload() async {
    final workouts = await widget.store.loadSessions();
    final templates = await widget.store.loadTemplates();
    if (!mounted) return;
    setState(() {
      _workouts = workouts;
      _templates = templates;
      _loading = false;
    });
  }

  int get _thisWeekCount {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    return _workouts
        .where((w) => w.endTime != null && w.endTime!.isAfter(weekStart))
        .length;
  }

  int get _thisMonthCount {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    return _workouts
        .where((w) => w.endTime != null && w.endTime!.isAfter(monthStart))
        .length;
  }

  void _startWorkout(TrainingTemplate template) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => WorkoutPage(template: template, store: widget.store, onSaved: _reload),
      ),
    );
  }

  Future<void> _selectTemplate() async {
    _templates = await widget.store.loadTemplates();
    if (_templates.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('还没有模板，先去创建一个吧')));
      return;
    }
    final selected = await showDialog<TrainingTemplate>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择模板'),
        children: _templates.map((t) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, t),
            child: Text('${t.folder} / ${t.name}'),
          );
        }).toList(),
      ),
    );
    if (selected != null) {
      _startWorkout(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('运动记录'),
        actions: [
          TextButton.icon(
            onPressed: _selectTemplate,
            icon: const Icon(Icons.play_arrow),
            label: const Text('开始跟练'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _reload,
              child: _workouts.isEmpty
                  ? ListView(
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.6,
                          child: const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.fitness_center_outlined,
                                  size: 64,
                                  color: Colors.grey,
                                ),
                                SizedBox(height: 12),
                                Text(
                                  '还没有运动记录',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        _buildStats(),
                        const SizedBox(height: 12),
                        ..._workouts.map((w) => _buildSessionCard(w)),
                      ],
                    ),
            ),
    );
  }

  Widget _buildStats() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  Text(
                    '$_thisWeekCount',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text('本周', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
            Container(width: 1, height: 40, color: Colors.grey.withAlpha(60)),
            Expanded(
              child: Column(
                children: [
                  Text(
                    '$_thisMonthCount',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text('本月', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
            Container(width: 1, height: 40, color: Colors.grey.withAlpha(60)),
            Expanded(
              child: Column(
                children: [
                  Text(
                    '${_workouts.length}',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text('总计', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteSession(WorkoutSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除记录'),
        content: Text('确定删除「${session.templateName}」的训练记录？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await widget.store.deleteSession(session.id);
      _reload();
    }
  }

  Widget _buildSessionCard(WorkoutSession session) {
    final isComplete = session.endTime != null;
    final dateStr =
        '${session.startTime.month}/${session.startTime.day} ${session.startTime.hour.toString().padLeft(2, '0')}:${session.startTime.minute.toString().padLeft(2, '0')}';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: isComplete
            ? BorderSide.none
            : BorderSide(color: Colors.orangeAccent.withValues(alpha: 0.4)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () async {
          if (!isComplete) {
            // 恢复未完成训练
            final saved = await widget.store.loadActiveWorkout();
            if (saved == null || !context.mounted) return;
            // 需要 template 来恢复
            final templates = await widget.store.loadTemplates();
            final template = templates.cast<TrainingTemplate?>().firstWhere(
              (t) => t?.id == session.templateId,
              orElse: () => null,
            );
            if (template == null || !context.mounted) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => WorkoutPage(
                  template: template,
                  store: widget.store,
                  savedStateJson: saved,
                  onSaved: _reload,
                ),
              ),
            );
            return;
          }
          final full = await widget.store.loadFullSession(session.id);
          if (!context.mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => WorkoutSummaryPage(session: full ?? session),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            session.templateName,
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isComplete
                                ? Colors.green.withValues(alpha: 0.15)
                                : Colors.orange.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isComplete ? '已完成' : '进行中',
                            style: TextStyle(
                              fontSize: 10,
                              color: isComplete
                                  ? Colors.greenAccent
                                  : Colors.orangeAccent,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$dateStr · ${session.durationText}',
                      style: const TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    Text(
                      '完成 ${session.completedCount}/${session.totalCount} 个动作',
                      style: const TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.grey),
                onPressed: () => _deleteSession(session),
              ),
              Icon(
                isComplete ? Icons.chevron_right : Icons.play_circle_outline,
                color: isComplete ? Colors.grey : Colors.orangeAccent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
