import 'package:flutter/material.dart';

import 'models.dart';
import 'template_store.dart';
import 'workout_models.dart';
import 'workout_page.dart';
import 'workout_summary_page.dart';

class WorkoutRecordsPage extends StatefulWidget {
  const WorkoutRecordsPage({super.key, required this.store});

  final TemplateStore store;

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
  }

  Future<void> _reload() async {
    final workouts = await widget.store.loadWorkouts();
    final templates = await widget.store.loadTemplates();
    if (!mounted) return;
    setState(() {
      _workouts = workouts..sort((a, b) => b.startTime.compareTo(a.startTime));
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
    final result = await Navigator.push<WorkoutSession>(
      context,
      MaterialPageRoute(
        builder: (_) => WorkoutPage(template: template, onSaved: _reload),
      ),
    );
    if (result != null) {
      _workouts.insert(0, result);
      await widget.store.saveWorkouts(_workouts);
      _reload();
    }
  }

  Future<void> _selectTemplate() async {
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

  Widget _buildSessionCard(WorkoutSession session) {
    final dateStr =
        '${session.startTime.month}/${session.startTime.day} ${session.startTime.hour.toString().padLeft(2, '0')}:${session.startTime.minute.toString().padLeft(2, '0')}';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => WorkoutSummaryPage(session: session),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.templateName,
                      style: const TextStyle(fontSize: 16),
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
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
