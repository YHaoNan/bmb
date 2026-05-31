import 'dart:convert';
import 'package:flutter/material.dart';
import 'ai_plan_service.dart';
import 'models.dart';
import 'template_store.dart';
import 'workout_models.dart';

class WorkoutSummaryPage extends StatelessWidget {
  const WorkoutSummaryPage({
    super.key,
    required this.session,
    this.store,
    this.lastSession,
  });

  final WorkoutSession session;
  final TemplateStore? store;
  final WorkoutSession? lastSession;

  String get _dateStr =>
      '${session.startTime.year}/${session.startTime.month}/${session.startTime.day}';
  String get _timeStr =>
      '${session.startTime.hour.toString().padLeft(2, '0')}:${session.startTime.minute.toString().padLeft(2, '0')}';
  String get _endTimeStr {
    final e = session.endTime;
    if (e == null) return '';
    return '${e.hour.toString().padLeft(2, '0')}:${e.minute.toString().padLeft(2, '0')}';
  }

  int get _totalVolume => session.exercises.fold(0, (s, e) => s + e.volume);

  WorkoutEvaluation? get _evaluation {
    final text = session.aiSummary;
    if (text == null || text.isEmpty) return null;
    try {
      return WorkoutEvaluation.fromJson(
        jsonDecode(text) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Map<Feeling, int> get _feelingCounts {
    final m = <Feeling, int>{};
    for (final f in Feeling.values) {
      m[f] = 0;
    }
    for (final e in session.exercises) {
      if (e.feeling != null) m[e.feeling!] = (m[e.feeling!] ?? 0) + 1;
    }
    return m;
  }

  Map<String, List<ExerciseRecord>> get _groups {
    final groups = <String, List<ExerciseRecord>>{};
    for (final e in session.exercises) {
      groups.putIfAbsent(e.groupTitle, () => []).add(e);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(session.templateName)),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _buildHeader(),
          _buildAiSummarySection(context),
          const SizedBox(height: 8),
          ..._groups.entries.map(
            (e) => _buildGroupCard(title: e.key, exercises: e.value),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final total = session.totalCount;
    final feelings = _feelingCounts;
    final hasModified = session.exercises.any((e) => e.modified);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$_dateStr  $_timeStr${_endTimeStr.isNotEmpty ? ' - $_endTimeStr' : ''}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.timer_outlined,
                            size: 14,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            session.durationText,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(width: 16),
                          const Icon(
                            Icons.fitness_center,
                            size: 14,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$_totalVolume kg',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.grey,
                            ),
                          ),
                          if (hasModified) ...[
                            const SizedBox(width: 16),
                            const Icon(
                              Icons.edit,
                              size: 14,
                              color: Colors.orangeAccent,
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              '有修改',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.orangeAccent,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$total 组',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.greenAccent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: Feeling.values.map((f) {
                final count = feelings[f] ?? 0;
                return Expanded(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(f.emoji, style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 2),
                      Text(
                        '${f.label}$count',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiSummarySection(BuildContext context) {
    final eval = _evaluation;
    if (eval == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 16, color: Colors.grey),
                    SizedBox(width: 10),
                    Text(
                      '本次运动未开启 AI 总结',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ],
                ),
                if (store != null) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _regenerateAiSummary(context),
                      icon: const Icon(Icons.auto_awesome, size: 16),
                      label: const Text(
                        '生成 AI 总结',
                        style: TextStyle(fontSize: 13),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFB7FF00),
                        side: const BorderSide(color: Color(0xFFB7FF00)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFB7FF00).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      size: 16,
                      color: Color(0xFFB7FF00),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'AI 总结',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  if (eval.grade != null && eval.grade!.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _gradeColor(
                              eval.grade!,
                            ).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '评分 ${eval.grade}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: _gradeColor(eval.grade!),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () => _showGradeRules(context),
                          child: Container(
                            width: 22,
                            height: 22,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.grey.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: const Icon(
                              Icons.help_outline,
                              size: 14,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              if (eval.summary != null && eval.summary!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  eval.summary!,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
              if (eval.groups.isNotEmpty) ...[
                const SizedBox(height: 10),
                ...eval.groups
                    .where((g) => g.analyse != null || g.suggestion != null)
                    .map((g) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1D20),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (g.name != null)
                              Text(
                                g.name!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            if (g.changes != null && g.changes!.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              InkWell(
                                onTap: lastSession != null && g.name != null
                                    ? () => _showComparison(context, g.name!)
                                    : null,
                                child: Row(
                                  children: [
                                    Text(
                                      '较上次: ',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    Flexible(
                                      child: Text(
                                        g.changes!,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: lastSession != null
                                              ? Colors.orangeAccent
                                              : Colors.grey,
                                          decoration: lastSession != null
                                              ? TextDecoration.underline
                                              : null,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if (g.analyse != null && g.analyse!.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                g.analyse!,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                            if (g.suggestion != null &&
                                g.suggestion!.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                '建议: ${g.suggestion}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFFB7FF00),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }),
              ],
              if (eval.modifiedPlan != null &&
                  eval.modifiedPlan!.isNotEmpty) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        _showModifiedPlan(context, eval.modifiedPlan!),
                    icon: const Icon(Icons.auto_fix_high, size: 16),
                    label: const Text(
                      'AI 修改计划',
                      style: TextStyle(fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFB7FF00),
                      side: const BorderSide(color: Color(0xFFB7FF00)),
                    ),
                  ),
                ),
              ],
              if (store != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _regenerateAiSummary(context),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('重新生成', style: TextStyle(fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey,
                      side: const BorderSide(color: Colors.grey),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGroupCard({
    required String title,
    required List<ExerciseRecord> exercises,
  }) {
    final total = exercises.length;
    final complete = exercises.where((e) => e.feeling != null).length;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Card(
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          title: Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            '${exercises.length}个动作 · 总容量 ${exercises.fold(0, (s, e) => s + e.volume)} kg',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: complete >= total
                  ? Colors.green.withValues(alpha: 0.15)
                  : const Color(0xFF1B1F22),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$complete/$total',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: complete >= total ? Colors.greenAccent : Colors.grey,
              ),
            ),
          ),
          children: exercises.map((e) => _buildExerciseCard(e)).toList(),
        ),
      ),
    );
  }

  Widget _buildExerciseCard(ExerciseRecord rec) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D20),
        borderRadius: BorderRadius.circular(10),
        border: rec.isAlternative
            ? Border.all(color: Colors.grey.withValues(alpha: 0.15))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                rec.isAlternative ? '🔄' : '⭐',
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  rec.cardName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: rec.isAlternative ? Colors.grey : null,
                  ),
                ),
              ),
              if (rec.modified)
                const Icon(Icons.edit, size: 14, color: Colors.orangeAccent),
              if (rec.feeling != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB7FF00).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${rec.feeling!.emoji} ${rec.feeling!.label}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFFB7FF00),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          ...rec.sets.asMap().entries.map((entry) {
            final i = entry.key;
            final s = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  _setIndexBadge('${i + 1}'),
                  const SizedBox(width: 8),
                  Text(
                    '${s.weightKg.toStringAsFixed(s.weightKg % 1 == 0 ? 0 : 1)} kg × ${s.reps} 次',
                    style: const TextStyle(
                      fontSize: 13,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '休息 ${s.restSec}秒',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            );
          }),
          if (rec.compensation != null || rec.notes != null) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (rec.compensation != null && rec.compensation!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '代偿: ${rec.compensation}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.orangeAccent,
                      ),
                    ),
                  ),
                if (rec.notes != null && rec.notes!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '备注: ${rec.notes}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.blueAccent,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _setIndexBadge(String text) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFB7FF00).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 11,
          color: Color(0xFFB7FF00),
        ),
      ),
    );
  }

  void _showComparison(BuildContext context, String groupName) {
    final currentExercises = session.exercises
        .where((e) => e.groupTitle == groupName)
        .toList();
    final lastExercises =
        lastSession?.exercises
            .where((e) => e.groupTitle == groupName)
            .toList() ??
        [];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          groupName,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              _sectionHeader('本次训练', currentExercises.length),
              ...currentExercises.map(_buildExerciseCard),
              if (lastExercises.isNotEmpty) ...[
                const SizedBox(height: 12),
                _sectionHeader('上次训练', lastExercises.length),
                ...lastExercises.map(_buildExerciseCard),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String label, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: const Color(0xFFB7FF00),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFFB7FF00),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count 组',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  void _showModifiedPlan(BuildContext context, List<TrainingAction> plan) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.auto_fix_high, size: 18, color: Color(0xFFB7FF00)),
            SizedBox(width: 8),
            Text(
              'AI 修改计划',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: plan.map((action) {
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1D20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action.groupTitle,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...action.cards.map((card) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: card.isPrimary
                                        ? const Color(
                                            0xFFB7FF00,
                                          ).withValues(alpha: 0.15)
                                        : Colors.grey.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    card.isPrimary ? '主动作' : '平替',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: card.isPrimary
                                          ? const Color(0xFFB7FF00)
                                          : Colors.grey,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  card.name,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            ...card.sets.map(
                              (s) => Padding(
                                padding: const EdgeInsets.only(
                                  left: 12,
                                  top: 2,
                                ),
                                child: Text(
                                  '${s.weightKg.toStringAsFixed(s.weightKg % 1 == 0 ? 0 : 1)} kg × ${s.reps} 次 · 休息 ${s.restSec}秒',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                            ),
                            if (card.primaryMuscles.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Padding(
                                padding: const EdgeInsets.only(left: 12),
                                child: Wrap(
                                  spacing: 4,
                                  runSpacing: 2,
                                  children: card.primaryMuscles
                                      .map(
                                        (m) => Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.green.withValues(
                                              alpha: 0.1,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            m.displayName,
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color: Colors.greenAccent,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          if (store != null)
            TextButton.icon(
              onPressed: () => _applyPlan(context, plan),
              icon: const Icon(Icons.check, size: 16),
              label: const Text('应用到模板'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFB7FF00),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Future<void> _applyPlan(
    BuildContext context,
    List<TrainingAction> plan,
  ) async {
    try {
      final templates = await store!.loadTemplates();
      final idx = templates.indexWhere((t) => t.id == session.templateId);
      if (idx < 0) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('未找到对应模板')));
        }
        return;
      }
      templates[idx].actions = plan;
      await store!.saveTemplates(templates);
      if (context.mounted) {
        Navigator.pop(context); // close preview dialog
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('AI 修改计划已应用到模板')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('应用失败: $e')));
      }
    }
  }

  void _showGradeRules(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline, size: 18, color: Color(0xFFB7FF00)),
            SizedBox(width: 8),
            Text(
              '评分规则',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '运动评分基于本次训练对刺激增肌的最终效用打分。',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              _gradeRule(
                'S',
                '无代偿、动作走形等问题。运动感受占比完全符合参考值，训练内容包含或大于模板全部内容。当前计划完美适配，无需调整。',
                const Color(0xFFB7FF00),
              ),
              _gradeRule(
                'A',
                '无代偿、动作走形等问题。运动感受轻微偏离参考值（5%以内），训练内容包含或大于模板全部内容。可能需轻微调整，但价值不大。',
                Colors.greenAccent,
              ),
              _gradeRule(
                'B',
                '轻微代偿、动作走形等问题出现。运动感受偏离参考值20%以内但不严重，训练内容包含或大于模板全部内容。可能需要调整计划。',
                Colors.blueAccent,
              ),
              _gradeRule(
                'C',
                '代偿、动作走形已成常态。运动感受偏离参考值40%以内，运动内容可能已无法完成。需要立即调整计划。',
                Colors.orangeAccent,
              ),
              _gradeRule(
                'D',
                '严重代偿、走形。运动感受偏离参考值40%以上。需要立即调整计划。',
                Colors.redAccent,
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1D20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '运动感受占比参考值',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFB7FF00),
                      ),
                    ),
                    const SizedBox(height: 6),
                    _feelingRef('😋 轻而易举', '20%', '用于热身、动作学习或恢复组'),
                    const SizedBox(height: 4),
                    _feelingRef('😣 有点吃力', '70%–80%', '正式组，每组保留1–2次重复余量'),
                    const SizedBox(height: 4),
                    _feelingRef('🥵 难以完成', '0%–10%', '偶尔极限组突破平台，不宜过多'),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _feelingRef(String label, String pct, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              pct,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFFB7FF00),
              ),
            ),
          ),
          Expanded(
            child: Text(
              desc,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _gradeRule(String grade, String desc, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              grade,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              desc,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _regenerateAiSummary(BuildContext context) async {
    if (store == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          margin: EdgeInsets.all(40),
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('AI 评估中，请稍候…'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final templates = await store!.loadTemplates();
      final template = templates.cast<TrainingTemplate?>().firstWhere(
        (t) => t?.id == session.templateId,
        orElse: () => null,
      );
      if (template == null) {
        Navigator.of(context, rootNavigator: true).pop();
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('未找到对应模板')));
        }
        return;
      }

      WorkoutSession? lastFull;
      {
        final allSessions = await store!.loadSessions();
        final sameTemplate = allSessions
            .where(
              (s) =>
                  s.templateId == session.templateId &&
                  s.id != session.id &&
                  s.endTime != null,
            )
            .toList();
        sameTemplate.sort((a, b) => a.startTime.compareTo(b.startTime));
        WorkoutSession? prev;
        for (final s in sameTemplate.reversed) {
          if (s.startTime.isBefore(session.startTime)) {
            prev = s;
            break;
          }
        }
        if (prev != null) {
          lastFull = await store!.loadFullSession(prev.id);
        }
      }

      final full = await store!.loadFullSession(session.id);
      if (full == null) {
        Navigator.of(context, rootNavigator: true).pop();
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('加载训练数据失败')));
        }
        return;
      }

      final aiService = AIPlanService(store: store!);
      final evaluation = await aiService.evaluateWorkout(
        session: full,
        template: template,
        lastSession: lastFull,
      );

      Navigator.of(context, rootNavigator: true).pop();

      if (evaluation != null && context.mounted) {
        full.aiSummary = jsonEncode({
          'grade': evaluation.grade,
          'summary': evaluation.summary,
          'groups': evaluation.groups
              .map(
                (g) => {
                  'name': g.name,
                  'changes_enum': g.changesEnum,
                  'changes': g.changes,
                  'analyse': g.analyse,
                  'suggestion': g.suggestion,
                },
              )
              .toList(),
          if (evaluation.modifiedPlan != null &&
              evaluation.modifiedPlan!.isNotEmpty)
            'modified_plan': evaluation.modifiedPlan!
                .map((a) => a.toJson())
                .toList(),
        });
        await store!.saveWorkoutSession(full);
        if (context.mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => WorkoutSummaryPage(
                session: full,
                store: store,
                lastSession: lastFull,
              ),
            ),
          );
        }
      } else if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('AI 评估生成失败，请重试')));
      }
    } catch (e) {
      Navigator.of(context, rootNavigator: true).pop();
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('AI评估失败: $e')));
      }
    }
  }

  Color _gradeColor(String grade) {
    switch (grade.toUpperCase()) {
      case 'S':
        return const Color(0xFFB7FF00);
      case 'A':
        return Colors.greenAccent;
      case 'B':
        return Colors.blueAccent;
      case 'C':
        return Colors.orangeAccent;
      case 'D':
        return Colors.redAccent;
      default:
        return Colors.grey;
    }
  }
}
