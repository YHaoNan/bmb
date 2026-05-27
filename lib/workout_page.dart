import 'dart:async';
import 'package:flutter/material.dart';
import 'models.dart';
import 'workout_models.dart';

class _SetState {
  String exerciseName;
  String groupTitle;
  bool isAlternative;
  List<String> primaryMuscles;
  List<String> secondaryMuscles;
  double weightKg;
  int reps;
  int restSec;
  bool isComplete = false;
  bool editing = false;
  Feeling? feeling;
  String? compensation;
  String? notes;
  final double _origWeight;
  final int _origReps;
  final int _origRest;

  bool get weightModified => weightKg != _origWeight;
  bool get repsModified => reps != _origReps;
  bool get restModified => restSec != _origRest;

  _SetState({
    required this.exerciseName,
    required this.groupTitle,
    this.isAlternative = false,
    List<String>? primaryMuscles,
    List<String>? secondaryMuscles,
    required this.weightKg,
    required this.reps,
    required this.restSec,
  }) : _origWeight = weightKg,
        _origReps = reps,
        _origRest = restSec,
        primaryMuscles = primaryMuscles ?? [],
        secondaryMuscles = secondaryMuscles ?? [];

  ExerciseRecord toRecord() {
    final rec = ExerciseRecord(
      groupTitle: groupTitle,
      cardName: exerciseName,
      isAlternative: isAlternative,
      feeling: feeling,
      compensation: compensation,
      notes: notes,
      weightModified: weightModified,
      repsModified: repsModified,
      restModified: restModified,
    );
    rec.sets.add(SetRecord(weightKg: weightKg, reps: reps, restSec: restSec));
    return rec;
  }
}

class _GroupWorkout {
  final String groupTitle;
  final List<ExerciseCardData> cards;
  int activeCardIndex = 0;
  final List<_SetState> sets;
  bool actionsExpanded = false;
  bool groupCollapsed = true;

  _GroupWorkout({
    required this.groupTitle,
    required this.cards,
  }) : sets = [];

  ExerciseCardData get activeCard => cards[activeCardIndex];

  /// 按动作名称统计完成组数和计划组数
  Map<String, ({int done, int planned})> actionStats() {
    final result = <String, ({int done, int planned})>{};
    for (final c in cards) {
      result[c.name] = (done: 0, planned: c.sets.length);
    }
    for (final s in sets) {
      final entry = result[s.exerciseName];
      if (entry != null && s.isComplete) {
        result[s.exerciseName] = (done: entry.done + 1, planned: entry.planned);
      }
    }
    return result;
  }

  void addExtraSetFromActiveCard() {
    final card = activeCard;
    final ts = card.sets.first;
    sets.add(_setFromCard(card, ts));
  }

  _SetState _setFromCard(ExerciseCardData card, TrainingSet ts) {
    return _SetState(
      exerciseName: card.name,
      groupTitle: groupTitle,
      isAlternative: !card.isPrimary,
      primaryMuscles: card.primaryMuscles,
      secondaryMuscles: card.secondaryMuscles,
      weightKg: ts.weightKg,
      reps: ts.reps,
      restSec: ts.restSec,
    );
  }
}

class WorkoutPage extends StatefulWidget {
  const WorkoutPage({super.key, required this.template, required this.onSaved});

  final TrainingTemplate template;
  final VoidCallback onSaved;

  @override
  State<WorkoutPage> createState() => _WorkoutPageState();
}

class _WorkoutPageState extends State<WorkoutPage> {
  final _startTime = DateTime.now();
  Timer? _timer;
  late String _id;

  final List<_GroupWorkout> _groups = [];
  int? _activeGIdx;
  int? _activeSIdx;

  int _restRemaining = 0;
  Timer? _restTimer;

  final _weightCtrl = TextEditingController();
  final _repsCtrl = TextEditingController();
  final _restCtrl = TextEditingController();
  final _compensationCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  Feeling? _pendingFeeling;

  @override
  void initState() {
    super.initState();
    _id = DateTime.now().microsecondsSinceEpoch.toString();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    for (final action in widget.template.actions) {
      _groups.add(_GroupWorkout(
        groupTitle: action.groupTitle,
        cards: List.from(action.cards),
      ));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _restTimer?.cancel();
    _weightCtrl.dispose();
    _repsCtrl.dispose();
    _restCtrl.dispose();
    _compensationCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  String get _elapsedText {
    final d = DateTime.now().difference(_startTime);
    final min = d.inMinutes;
    final sec = d.inSeconds % 60;
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  _SetState? get _activeSet {
    if (_activeGIdx == null || _activeSIdx == null) return null;
    if (_activeGIdx! >= _groups.length) return null;
    final g = _groups[_activeGIdx!];
    if (_activeSIdx! >= g.sets.length) return null;
    return g.sets[_activeSIdx!];
  }

  void _restartRestTimer(int sec) {
    _restTimer?.cancel();
    _restRemaining = sec;
    if (sec <= 0) return;
    _restTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_restRemaining > 0) {
        setState(() => _restRemaining--);
      } else {
        _restTimer?.cancel();
        _restTimer = null;
        setState(() {});
      }
    });
  }

  void _skipRest() {
    _restTimer?.cancel();
    _restTimer = null;
    _restRemaining = 0;
    setState(() {});
  }

  void _loadCtrlsFromSet(_SetState s) {
    _weightCtrl.text = s.weightKg.toStringAsFixed(0);
    _repsCtrl.text = s.reps.toString();
    _restCtrl.text = s.restSec.toString();
    _pendingFeeling = s.feeling;
    _compensationCtrl.text = s.compensation ?? '';
    _notesCtrl.text = s.notes ?? '';
  }

  void _startSet(int gIdx, int sIdx) {
    _skipRest();
    final s = _groups[gIdx].sets[sIdx];
    _activeGIdx = gIdx;
    _activeSIdx = sIdx;
    s.editing = true;
    _loadCtrlsFromSet(s);
    setState(() {});
  }

  void _completeOrSaveSet() {
    final s = _activeSet;
    if (s == null) return;
    final w = double.tryParse(_weightCtrl.text) ?? s.weightKg;
    final r = int.tryParse(_repsCtrl.text) ?? s.reps;
    final rest = int.tryParse(_restCtrl.text) ?? s.restSec;
    s.weightKg = w;
    s.reps = r;
    s.restSec = rest;
    s.feeling = _pendingFeeling;
    s.compensation =
        _compensationCtrl.text.isNotEmpty ? _compensationCtrl.text : null;
    s.notes = _notesCtrl.text.isNotEmpty ? _notesCtrl.text : null;
    s.isComplete = true;
    s.editing = false;

    _restartRestTimer(s.restSec);
    setState(() {});
  }

  void _reopenSet(int gIdx, int sIdx) {
    _skipRest();
    final s = _groups[gIdx].sets[sIdx];
    _activeGIdx = gIdx;
    _activeSIdx = sIdx;
    s.editing = true;
    _loadCtrlsFromSet(s);
    setState(() {});
  }

  bool get _canAddSet =>
      _activeGIdx == null ||
      _activeSIdx == null ||
      _groups[_activeGIdx!].sets[_activeSIdx!].isComplete;

  void _addExtraSet(int gIdx) {
    _groups[gIdx].addExtraSetFromActiveCard();
    setState(() {});
  }

  void _switchCardInGroup(int gIdx, int cardIdx) {
    final g = _groups[gIdx];
    if (cardIdx == g.activeCardIndex) return;
    g.activeCardIndex = cardIdx;
    setState(() {});
  }

  void _deleteCardFromGroup(int gIdx, int cardIdx) {
    final g = _groups[gIdx];
    g.cards.removeAt(cardIdx);
    if (cardIdx < g.activeCardIndex) {
      g.activeCardIndex--;
    } else if (cardIdx == g.activeCardIndex && g.activeCardIndex >= g.cards.length) {
      g.activeCardIndex = g.cards.length - 1;
    }
    if (g.cards.isEmpty) {
      _groups.removeAt(gIdx);
    }
    setState(() {});
  }

  Future<void> _finishWorkout() async {
    final allSets = _groups.expand((g) => g.sets).toList();
    final completedSets = allSets.where((s) => s.isComplete).toList();
    final totalSets = allSets.length;

    final records = completedSets.map((s) => s.toRecord()).toList();
    final session = WorkoutSession(
      id: _id,
      templateId: widget.template.id,
      templateName: widget.template.name,
      startTime: _startTime,
      endTime: DateTime.now(),
      exercises: records,
    );

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('结束训练'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('已完成 ${completedSets.length}/$totalSets 组'),
            Text('时长 ${session.durationText}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存并结束'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      widget.onSaved();
      Navigator.pop(context, session);
    }
  }

  Future<bool> _onWillPop() async {
    if (_groups.isEmpty) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出训练'),
        content: const Text('当前进度不会保存，确定退出？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('继续训练'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.template.name),
          actions: [
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  _elapsedText,
                  style: const TextStyle(
                      fontSize: 18,
                      fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ),
            ),
            TextButton(
              onPressed: _finishWorkout,
              child: const Text('结束',
                  style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
        body: _groups.isEmpty ? _buildEmptyState() : _buildContent(),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Text('模板中没有动作组',
          style: TextStyle(fontSize: 16, color: Colors.grey)),
    );
  }

  Widget _buildContent() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: List.generate(_groups.length, (i) => _buildGroupCard(i)),
    );
  }

  // ────────── Group Card ──────────

  Widget _buildGroupCard(int gIdx) {
    final g = _groups[gIdx];
    final completed = g.sets.where((s) => s.isComplete).length;
    final total = g.sets.length;
    final allDone = total > 0 && completed == total;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: allDone ? Colors.green.withValues(alpha: 0.4) : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => g.groupCollapsed = !g.groupCollapsed),
              child: Row(
                children: [
                  Icon(
                    g.groupCollapsed ? Icons.keyboard_arrow_right : Icons.keyboard_arrow_down,
                    size: 20, color: Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(g.groupTitle,
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w700)),
                        if (!g.groupCollapsed)
                          Text(
                            '$completed/$total 组 · ${g.activeCard.name}',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                      ],
                    ),
                  ),
                  if (total > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: completed == total
                            ? Colors.green.withValues(alpha: 0.15)
                            : const Color(0xFF1B1F22),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        completed == total ? '已完成 ✓' : '$completed/$total',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: completed == total ? Colors.greenAccent : Colors.grey,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            _buildAllMusclesRow(g),
            if (!g.groupCollapsed) ...[
              const SizedBox(height: 6),
              _buildActionsExpandable(g, gIdx),
              const Divider(height: 16),
              _buildCardSwitcher(g, gIdx),
              const SizedBox(height: 8),
              ...List.generate(g.sets.length, (sIdx) {
                return _buildSetCard(g, gIdx, sIdx);
              }),
              const SizedBox(height: 4),
              if (_canAddSet)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _addExtraSet(gIdx),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('增加一组',
                        style: TextStyle(fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8)),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// 显示组内所有动作的主肌群（去重）
  Widget _buildAllMusclesRow(_GroupWorkout g) {
    final all = <String>{};
    for (final c in g.cards) {
      all.addAll(c.primaryMuscles);
    }
    if (all.isEmpty) return const SizedBox.shrink();
    return Text('主肌群: ${all.join(" · ")}',
        style: const TextStyle(fontSize: 12, color: Colors.grey));
  }

  /// 可展开的组内动作列表
  Widget _buildActionsExpandable(_GroupWorkout g, int gIdx) {
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => g.actionsExpanded = !g.actionsExpanded),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(
                  g.actionsExpanded
                      ? Icons.expand_less
                      : Icons.expand_more,
                  size: 18,
                  color: Colors.grey,
                ),
                const SizedBox(width: 4),
                Text(
                  '组内动作 (${g.cards.length}个)',
                  style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ),
        if (g.actionsExpanded)
          ...g.cards.toList().asMap().entries.map((entry) {
            final i = entry.key;
            final c = entry.value;
            final stats = g.actionStats()[c.name]!;
            return Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.only(left: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1D20),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Text(
                    c.isPrimary ? '⭐ ' : '🔄 ',
                    style: const TextStyle(fontSize: 11),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${c.name}  ${c.isPrimary ? "主动作" : "平替"}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        if (c.primaryMuscles.isNotEmpty)
                          Text(
                            '主: ${c.primaryMuscles.join("·")}',
                            style: const TextStyle(
                                fontSize: 10, color: Colors.grey),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      '${stats.done}/${stats.planned} 组',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: stats.done >= stats.planned && stats.planned > 0
                            ? Colors.greenAccent
                            : Colors.grey,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 16),
                    color: Colors.redAccent,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _deleteCardFromGroup(gIdx, i),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildCardSwitcher(_GroupWorkout g, int gIdx) {
    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: List.generate(g.cards.length, (i) {
          final c = g.cards[i];
          final selected = i == g.activeCardIndex;
          final stats = g.actionStats()[c.name]!;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilterChip(
              label: Text('${c.name} ${stats.done}/${stats.planned}',
                  style: const TextStyle(fontSize: 12)),
              selected: selected,
              onSelected: (_) => _switchCardInGroup(gIdx, i),
              visualDensity: VisualDensity.compact,
              selectedColor: const Color(0xFFB7FF00).withValues(alpha: 0.2),
              checkmarkColor: const Color(0xFFB7FF00),
            ),
          );
        }),
      ),
    );
  }

  // ────────── Set Card ──────────

  Widget _buildSetCard(_GroupWorkout g, int gIdx, int sIdx) {
    final s = g.sets[sIdx];
    if (s.isComplete && !s.editing) return _buildCompletedSet(s, gIdx, sIdx);
    if (s.editing) return _buildEditingSet(g, s, gIdx, sIdx);
    return _buildPendingSet(s, gIdx, sIdx);
  }

  Widget _buildPendingSet(_SetState s, int gIdx, int sIdx) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D20),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _setIndexBadge('${sIdx + 1}', Colors.grey),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${s.exerciseName}  ${s.weightKg.toStringAsFixed(0)}kg × ${s.reps}次',
              style: const TextStyle(fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: () => _startSet(gIdx, sIdx),
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            child: const Text('开始', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  void _showTutorial(ExerciseCardData card) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Text(card.name, style: const TextStyle(fontSize: 18)),
            if (!card.isPrimary)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Text('(平替)', style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.normal)),
              ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (card.keyPoints.isNotEmpty) ...[
                const Text('核心要领', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                ...card.keyPoints.map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ', style: TextStyle(fontSize: 13)),
                      Expanded(child: Text(p, style: const TextStyle(fontSize: 13))),
                    ],
                  ),
                )),
              ],
              if (card.commonMistakes.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('常见错误', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                ...card.commonMistakes.map((m) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('✗ ', style: TextStyle(fontSize: 13, color: Colors.redAccent)),
                      Expanded(child: Text(m, style: const TextStyle(fontSize: 13))),
                    ],
                  ),
                )),
              ],
              if (card.keyPoints.isEmpty && card.commonMistakes.isEmpty)
                const Text('暂无教程信息', style: TextStyle(fontSize: 13, color: Colors.grey)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  Widget _buildEditingSet(_GroupWorkout g, _SetState s, int gIdx, int sIdx) {
    final card = g.cards.firstWhere((c) => c.name == s.exerciseName,
        orElse: () => g.activeCard);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1F22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: const Color(0xFFB7FF00).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 0),
            child: Row(
              children: [
                _setIndexBadge(
                    '${sIdx + 1}', const Color(0xFFB7FF00)),
                const SizedBox(width: 8),
                Text(s.exerciseName,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB7FF00).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    s.isComplete ? '编辑中' : '进行中',
                    style: const TextStyle(
                        fontSize: 10, color: Color(0xFFB7FF00)),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.school_outlined, size: 20),
                  tooltip: '动作教程',
                  color: Colors.grey,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _showTutorial(card),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                _miniField('重量(kg)', _weightCtrl, flex: 2),
                const SizedBox(width: 6),
                _miniField('次数', _repsCtrl, flex: 1),
                const SizedBox(width: 6),
                _miniField('休息(秒)', _restCtrl, flex: 1),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _buildFeelingRow(),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _compensationCtrl,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      labelText: '代偿部位',
                      hintText: '如: 腰部',
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                          vertical: 6, horizontal: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _notesCtrl,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      labelText: '补充感受',
                      hintText: '如: 左肩不适',
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                          vertical: 6, horizontal: 8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_restTimer != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _buildRestTimer(),
            ),
          ],
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: SizedBox(
              width: double.infinity,
              height: 40,
              child: FilledButton.icon(
                onPressed: _completeOrSaveSet,
                icon: const Icon(Icons.check, size: 18),
                label: Text(s.isComplete ? '保存修改' : '完成这组'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedSet(_SetState s, int gIdx, int sIdx) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          _setIndexBadge('✓', Colors.greenAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${s.exerciseName}  ${s.weightKg.toStringAsFixed(0)}kg × ${s.reps}次',
                  style: const TextStyle(fontSize: 13),
                ),
                if (s.feeling != null ||
                    s.compensation != null ||
                    s.notes != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: [
                        if (s.feeling != null) ...[
                          Text(s.feeling!.emoji,
                              style: const TextStyle(fontSize: 14)),
                          const SizedBox(width: 2),
                          Text(s.feeling!.label,
                              style: const TextStyle(
                                  fontSize: 10, color: Colors.grey)),
                        ],
                        if (s.compensation != null) ...[
                          const SizedBox(width: 6),
                          Text('代: ${s.compensation}',
                              style: const TextStyle(
                                  fontSize: 10, color: Colors.orangeAccent)),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _reopenSet(gIdx, sIdx),
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            child: const Text('编辑', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  // ────────── Shared Widgets ──────────

  Widget _setIndexBadge(String text, Color color) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: color)),
    );
  }

  Widget _buildFeelingRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('训练感受（可选）',
            style:
                TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: Feeling.values.map((f) {
            final selected = _pendingFeeling == f;
            return GestureDetector(
              onTap: () => setState(() => _pendingFeeling = f),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFFB7FF00).withValues(alpha: 0.2)
                      : const Color(0xFF2A2F34),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected
                        ? const Color(0xFFB7FF00)
                        : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(f.emoji, style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 4),
                    Text(f.label,
                        style: TextStyle(
                            fontSize: 11,
                            color: selected
                                ? const Color(0xFFB7FF00)
                                : Colors.grey)),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildRestTimer() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF25282D),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.timer_outlined, size: 16, color: Colors.grey),
          const SizedBox(width: 6),
          Text(
            '休息: ${_restRemaining}s',
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()]),
          ),
          const Spacer(),
          TextButton(
            onPressed: _skipRest,
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            child: const Text('跳过', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _miniField(String label, TextEditingController ctrl,
      {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 10),
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        ),
      ),
    );
  }
}
