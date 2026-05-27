import 'package:flutter/material.dart';

import 'workout_models.dart';

class WorkoutSummaryPage extends StatelessWidget {
  const WorkoutSummaryPage({super.key, required this.session});

  final WorkoutSession session;

  @override
  Widget build(BuildContext context) {
    final dateStr =
        '${session.startTime.year}/${session.startTime.month}/${session.startTime.day} ${session.startTime.hour.toString().padLeft(2, '0')}:${session.startTime.minute.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(title: Text(session.templateName)),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dateStr,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _infoRow('时长', session.durationText),
                  _infoRow(
                    '完成动作',
                    '${session.completedCount}/${session.totalCount}',
                  ),
                  if (session.note != null && session.note!.isNotEmpty)
                    _infoRow('备注', session.note!),
                ],
              ),
            ),
          ),
          if (session.aiSummary != null && session.aiSummary!.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AI总结',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(session.aiSummary!),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          const Text(
            '动作详情',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          ...session.exercises
              .where((e) => e.sets.isNotEmpty)
              .map((e) => _buildExerciseCard(e)),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildExerciseCard(ExerciseRecord rec) {
    final feelingWidget = rec.feeling != null
        ? Chip(
            label: Text(
              rec.feeling!.label,
              style: const TextStyle(fontSize: 12),
            ),
            visualDensity: VisualDensity.compact,
          )
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    rec.cardName,
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
                if (feelingWidget != null) feelingWidget,
              ],
            ),
            const SizedBox(height: 6),
            ...rec.sets.asMap().entries.map((entry) {
              final i = entry.key;
              final s = entry.value;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Text(
                  '第${i + 1}组: ${s.weightKg.toStringAsFixed(0)}kg × ${s.reps}次 · 休${s.restSec}秒',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              );
            }),
            if (rec.compensation != null || rec.notes != null) ...[
              const SizedBox(height: 4),
              if (rec.compensation != null && rec.compensation!.isNotEmpty)
                Text(
                  '代偿: ${rec.compensation}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              if (rec.notes != null && rec.notes!.isNotEmpty)
                Text(
                  '备注: ${rec.notes}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
