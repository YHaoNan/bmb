import 'dart:async';

import 'package:flutter/material.dart';

import 'models.dart';
import 'workout_models.dart';

enum _WorkoutView { overview, exercise, rest }

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

  // workout state
  _WorkoutView _view = _WorkoutView.overview;
  final Map<String, ExerciseRecord> _records = {};
  String? _activeKey;
  int _currentSetIndex = 0;
  int _restRemaining = 0;
  Timer? _restTimer;
  bool _restCountdownActive = false;
  final _compensationCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  Feeling? _pendingFeeling;

  // editable values for active exercise
  final _weightCtrl = TextEditingController();
  final _repsCtrl = TextEditingController();
  final _restCtrl = TextEditingController();
  double _originalWeight = 0;
  int _originalReps = 0;
  int _originalRest = 0;

  List<
    ({String key, ExerciseCardData card, bool isAlternative, String groupTitle})
  >
  get _allExercises => _buildExerciseList();

  List<
    ({String key, ExerciseCardData card, bool isAlternative, String groupTitle})
  >
  _buildExerciseList() {
    final list =
        <
          ({
            String key,
            ExerciseCardData card,
            bool isAlternative,
            String groupTitle,
          })
        >[];
    for (final group in widget.template.actions) {
      for (var i = 0; i < group.cards.length; i++) {
        final card = group.cards[i];
        list.add((
          key: '${group.groupTitle}|${card.name}|$i',
          card: card,
          isAlternative: i > 0,
          groupTitle: group.groupTitle,
        ));
      }
    }
    return list;
  }

  bool get _hasModifications =>
      _records.values.any((r) => r.sets.isNotEmpty && r.modified);

  @override
  void initState() {
    super.initState();
    _id = DateTime.now().microsecondsSinceEpoch.toString();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _restTimer?.cancel();
    _compensationCtrl.dispose();
    _notesCtrl.dispose();
    _weightCtrl.dispose();
    _repsCtrl.dispose();
    _restCtrl.dispose();
    super.dispose();
  }

  String get _elapsedText {
    final d = DateTime.now().difference(_startTime);
    final min = d.inMinutes;
    final sec = d.inSeconds % 60;
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  ExerciseRecord _ensureRecord(String key) {
    if (!_records.containsKey(key)) {
      final entry = _allExercises.firstWhere((e) => e.key == key);
      _records[key] = ExerciseRecord(
        groupTitle: entry.groupTitle,
        cardName: entry.card.name,
        isAlternative: entry.isAlternative,
      );
    }
    return _records[key]!;
  }

  void _startExercise(String key) {
    final entry = _allExercises.firstWhere((e) => e.key == key);
    final rec = _ensureRecord(key);
    final lastSet = rec.sets.isNotEmpty
        ? rec.sets.last
        : SetRecord.fromTrainingSet(entry.card.sets.first);
    _currentSetIndex = rec.sets.length;
    _activeKey = key;
    _originalWeight = lastSet.weightKg;
    _originalReps = lastSet.reps;
    _originalRest = lastSet.restSec;
    _weightCtrl.text = lastSet.weightKg.toStringAsFixed(0);
    _repsCtrl.text = lastSet.reps.toString();
    _restCtrl.text = lastSet.restSec.toString();
    _pendingFeeling = null;
    _compensationCtrl.clear();
    _notesCtrl.clear();
    setState(() => _view = _WorkoutView.exercise);
  }

  void _completeSet() {
    final w = double.tryParse(_weightCtrl.text) ?? _originalWeight;
    final r = int.tryParse(_repsCtrl.text) ?? _originalReps;
    final rest = int.tryParse(_restCtrl.text) ?? _originalRest;
    final key = _activeKey!;
    final rec = _ensureRecord(key);
    final entry = _allExercises.firstWhere((e) => e.key == key);

    rec.sets.add(SetRecord(weightKg: w, reps: r, restSec: rest));
    if (w != entry.card.sets.first.weightKg) rec.weightModified = true;
    if (r != entry.card.sets.first.reps) rec.repsModified = true;
    if (rest != entry.card.sets.first.restSec) rec.restModified = true;

    if (_currentSetIndex + 1 >= entry.card.sets.length) {
      _restRemaining = rest;
      _startRest();
    } else {
      _currentSetIndex++;
      final next = entry.card.sets[_currentSetIndex];
      final useWeight = rec.weightModified ? w : next.weightKg;
      final useReps = rec.repsModified ? r : next.reps;
      final useRest = rec.restModified ? rest : next.restSec;
      _weightCtrl.text = useWeight.toStringAsFixed(0);
      _repsCtrl.text = useReps.toString();
      _restCtrl.text = useRest.toString();
      _restRemaining = useRest;
      _startRest();
    }
  }

  void _startRest() {
    setState(() {
      _view = _WorkoutView.rest;
      _restCountdownActive = true;
    });
    _restTimer?.cancel();
    _restRemaining = int.tryParse(_restCtrl.text) ?? 60;
    _restTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_restRemaining > 0) {
        setState(() => _restRemaining--);
      } else {
        _restTimer?.cancel();
        setState(() => _restCountdownActive = false);
      }
    });
  }

  void _endRest() {
    _restTimer?.cancel();
    setState(() {
      _restCountdownActive = false;
      _view = _WorkoutView.exercise;
    });
  }

  void _completeExercise() {
    final rec = _ensureRecord(_activeKey!);
    rec.feeling = _pendingFeeling;
    rec.compensation = _compensationCtrl.text.isNotEmpty
        ? _compensationCtrl.text
        : null;
    rec.notes = _notesCtrl.text.isNotEmpty ? _notesCtrl.text : null;
    _restTimer?.cancel();
    setState(() {
      _view = _WorkoutView.overview;
      _activeKey = null;
    });
  }

  Future<void> _finishWorkout() async {
    // build final records
    final allExercises = _allExercises;
    for (final entry in allExercises) {
      _ensureRecord(entry.key);
    }

    final session = WorkoutSession(
      id: _id,
      templateId: widget.template.id,
      templateName: widget.template.name,
      startTime: _startTime,
      endTime: DateTime.now(),
      exercises: _records.values.toList(),
    );

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('结束训练'),
        content: _buildFinishContent(session),
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

  Widget _buildFinishContent(WorkoutSession session) {
    final missingFeelings = _records.values
        .where((r) => r.sets.isNotEmpty && r.feeling == null)
        .toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('已完成 ${session.completedCount}/${session.totalCount} 个动作'),
        Text('时长 ${session.durationText}'),
        if (_hasModifications) ...[
          const SizedBox(height: 8),
          const Text(
            '⚠️ 已修改部分动作的重量/次数/休息时间',
            style: TextStyle(color: Colors.orangeAccent),
          ),
        ],
        if (missingFeelings.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text(
            '⚠️ 以下动作未记录感受：',
            style: TextStyle(color: Colors.orangeAccent),
          ),
          ...missingFeelings.map(
            (r) => Text(
              '  • ${r.cardName}',
              style: const TextStyle(color: Colors.orangeAccent),
            ),
          ),
        ],
      ],
    );
  }

  Future<bool> _onWillPop() async {
    if (_view == _WorkoutView.overview) {
      final result = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('退出训练'),
          content: const Text('当前训练进度不会保存，确定退出？'),
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
    setState(() {
      _restTimer?.cancel();
      _view = _WorkoutView.overview;
      _activeKey = null;
    });
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
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
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            TextButton(
              onPressed: _finishWorkout,
              child: const Text(
                '结束',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        ),
        body: _view == _WorkoutView.overview
            ? _buildOverview()
            : _buildExerciseView(),
      ),
    );
  }

  Widget _buildOverview() {
    final grouped =
        <
          String,
          List<({String key, ExerciseCardData card, bool isAlternative})>
        >{};
    for (final e in _allExercises) {
      grouped.putIfAbsent(e.groupTitle, () => []).add((
        key: e.key,
        card: e.card,
        isAlternative: e.isAlternative,
      ));
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        ...grouped.entries.map(
          (entry) => _buildGroupSection(entry.key, entry.value),
        ),
      ],
    );
  }

  Widget _buildGroupSection(
    String title,
    List<({String key, ExerciseCardData card, bool isAlternative})> items,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          ...items.map((item) {
            final rec = _records[item.key];
            final done = rec?.feeling != null && rec!.sets.isNotEmpty;
            final doing = _activeKey == item.key;
            final started = rec != null && rec.sets.isNotEmpty && !done;

            Color statusColor;
            String statusText;
            if (done) {
              statusColor = Colors.green;
              statusText = '已完成';
            } else if (doing) {
              statusColor = Colors.blueAccent;
              statusText = '进行中';
            } else if (started) {
              statusColor = Colors.orangeAccent;
              statusText = '未完成';
            } else {
              statusColor = Colors.grey;
              statusText = '未开始';
            }

            final doneSets = rec?.sets.length ?? 0;

            return Card(
              margin: const EdgeInsets.only(bottom: 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: done
                    ? null
                    : () {
                        if (_activeKey != null) return;
                        _startExercise(item.key);
                      },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (item.isAlternative)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 4),
                                    child: Text(
                                      '平替',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ),
                                Text(
                                  item.card.name,
                                  style: const TextStyle(fontSize: 15),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${item.card.sets.first.weightKg.toStringAsFixed(0)}kg × ${item.card.sets.first.reps}次 · 休${item.card.sets.first.restSec}秒',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (started)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            '$doneSets/${item.card.sets.length} 组',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.orangeAccent,
                            ),
                          ),
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withAlpha(40),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          statusText,
                          style: TextStyle(fontSize: 11, color: statusColor),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildExerciseView() {
    final entry = _allExercises.firstWhere((e) => e.key == _activeKey);
    final totalSets = entry.card.sets.length;
    final isLastSet = _currentSetIndex >= totalSets - 1;

    if (_view == _WorkoutView.rest) {
      return _buildRestView(entry, totalSets, isLastSet);
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            entry.card.name,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            '${isLastSet ? "最后一" : "第${_currentSetIndex + 1}"}组 / 共$totalSets组',
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              _metricField('重量 (kg)', _weightCtrl, 3),
              const SizedBox(width: 12),
              _metricField('次数 (次)', _repsCtrl, 3),
              const SizedBox(width: 12),
              _metricField('休息 (秒)', _restCtrl, 3),
            ],
          ),
          const Spacer(),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: _completeSet,
              icon: const Icon(Icons.check),
              label: Text(isLastSet ? '完成所有组' : '完成这组'),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildRestView(
    ({String key, ExerciseCardData card, bool isAlternative, String groupTitle})
    entry,
    int totalSets,
    bool isLastSet,
  ) {
    final remaining = _currentSetIndex + 1;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(
            entry.card.name,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text('已完成 $remaining/$totalSets 组'),
          const SizedBox(height: 24),
          SizedBox(
            width: 120,
            height: 120,
            child: CircularProgressIndicator(
              value: _restCountdownActive
                  ? 1 - (_restRemaining / (int.tryParse(_restCtrl.text) ?? 60))
                  : 0,
              strokeWidth: 8,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _restRemaining.toString(),
            style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w200),
          ),
          const SizedBox(height: 4),
          const Text('秒休息'),
          if (_restCountdownActive)
            TextButton(onPressed: _endRest, child: const Text('跳过休息')),
          const SizedBox(height: 24),
          if (!_restCountdownActive || isLastSet) ...[
            const Divider(),
            const Text('记录感受', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: Feeling.values.map((f) {
                final selected = _pendingFeeling == f;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(f.label, style: const TextStyle(fontSize: 13)),
                    selected: selected,
                    onSelected: (_) => setState(() => _pendingFeeling = f),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _compensationCtrl,
              decoration: const InputDecoration(
                labelText: '代偿部位（可选）',
                hintText: '如：腰部、斜方肌',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notesCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: '补充感受（可选）',
                hintText: '如：左肩有点不适',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: FilledButton(
                onPressed: _restCountdownActive ? null : _completeExercise,
                child: Text(isLastSet ? '完成动作' : '开始下一组'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metricField(String label, TextEditingController ctrl, int flex) {
    return Expanded(
      flex: flex,
      child: TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 10,
            horizontal: 8,
          ),
        ),
      ),
    );
  }
}
