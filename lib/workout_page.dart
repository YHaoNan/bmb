import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'ai_plan_service.dart';
import 'models.dart';
import 'template_store.dart';
import 'workout_models.dart';
import 'workout_state_manager.dart';
import 'workout_summary_page.dart';

class _SetState {
  String exerciseName;
  String groupTitle;
  bool isAlternative;
  List<MuscleGroup> primaryMuscles;
  List<MuscleGroup> secondaryMuscles;
  double weightKg;
  int reps;
  int restSec;
  bool isComplete = false;
  bool editing = false;
  Feeling? feeling;
  String? compensation;
  String? notes;
  double _origWeight;
  int _origReps;
  int _origRest;

  bool get weightModified => weightKg != _origWeight;
  bool get repsModified => reps != _origReps;
  bool get restModified => restSec != _origRest;

  _SetState({
    required this.exerciseName,
    required this.groupTitle,
    this.isAlternative = false,
    List<MuscleGroup>? primaryMuscles,
    List<MuscleGroup>? secondaryMuscles,
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

  Map<String, dynamic> toJson() => {
    'exerciseName': exerciseName,
    'groupTitle': groupTitle,
    'isAlternative': isAlternative,
    'primaryMuscles': primaryMuscles.map((m) => m.name).toList(),
    'secondaryMuscles': secondaryMuscles.map((m) => m.name).toList(),
    'weightKg': weightKg,
    'reps': reps,
    'restSec': restSec,
    'isComplete': isComplete,
    'editing': editing,
    'feeling': feeling?.name,
    'compensation': compensation,
    'notes': notes,
    'origWeightKg': _origWeight,
    'origReps': _origReps,
    'origRestSec': _origRest,
  };

  static _SetState fromJson(Map<String, dynamic> json) {
    final s = _SetState(
      exerciseName: json['exerciseName'] as String,
      groupTitle: json['groupTitle'] as String,
      isAlternative: json['isAlternative'] as bool? ?? false,
      primaryMuscles: (json['primaryMuscles'] as List<dynamic>? ?? [])
          .map((e) => MuscleGroup.tryParse(e.toString()))
          .whereType<MuscleGroup>()
          .toList(),
      secondaryMuscles: (json['secondaryMuscles'] as List<dynamic>? ?? [])
          .map((e) => MuscleGroup.tryParse(e.toString()))
          .whereType<MuscleGroup>()
          .toList(),
      weightKg: (json['weightKg'] as num).toDouble(),
      reps: json['reps'] as int,
      restSec: json['restSec'] as int,
    );
    s._setOrig(
      (json['origWeightKg'] as num?)?.toDouble() ?? s.weightKg,
      json['origReps'] as int? ?? s.reps,
      json['origRestSec'] as int? ?? s.restSec,
    );
    s.isComplete = json['isComplete'] as bool? ?? false;
    s.editing = false;
    s.feeling = (json['feeling'] as String?) != null
        ? Feeling.values.firstWhere((f) => f.name == json['feeling'])
        : null;
    s.compensation = json['compensation'] as String?;
    s.notes = json['notes'] as String?;
    return s;
  }

  void _setOrig(double w, int r, int rs) {
    _origWeight = w;
    _origReps = r;
    _origRest = rs;
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
    List<_SetState>? sets,
    this.activeCardIndex = 0,
    this.groupCollapsed = true,
  }) : sets = sets ?? [];

  ExerciseCardData get activeCard => cards[activeCardIndex];

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

  /// 当前活跃动作已从模板消耗的组数
  int consumedCount(String exerciseName) {
    return sets.where((s) => s.exerciseName == exerciseName).length;
  }

  /// 当前活跃动作的模板定义组数
  int get templateCount => activeCard.sets.length;

  /// 按顺序从模板取下一组，返回 false 表示模板组已耗尽
  bool addNextTemplateSet() {
    final card = activeCard;
    final used = consumedCount(card.name);
    if (used >= card.sets.length) return false;

    // 若用户自定义了上一组的任意参数（偏离模板），则复制上一组参数
    final lastForCard = sets.lastWhere(
      (s) => s.exerciseName == card.name,
      orElse: () => _setFromCard(card, card.sets[used]),
    );
    final ts = card.sets[used];
    if (lastForCard.weightKg != ts.weightKg ||
        lastForCard.reps != ts.reps ||
        lastForCard.restSec != ts.restSec) {
      sets.add(
        _SetState(
          exerciseName: card.name,
          groupTitle: groupTitle,
          isAlternative: !card.isPrimary,
          primaryMuscles: card.primaryMuscles,
          secondaryMuscles: card.secondaryMuscles,
          weightKg: lastForCard.weightKg,
          reps: lastForCard.reps,
          restSec: lastForCard.restSec,
        ),
      );
    } else {
      sets.add(_setFromCard(card, ts));
    }
    return true;
  }

  /// 用模板最后一组参数追加一组（超出模板时使用）
  void addExtraSet() {
    final card = activeCard;
    sets.add(_setFromCard(card, card.sets.last));
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

  Map<String, dynamic> toJson() => {
    'groupTitle': groupTitle,
    'activeCardIndex': activeCardIndex,
    'groupCollapsed': groupCollapsed,
    'cards': cards.map((c) => c.toJson()).toList(),
    'sets': sets.map((s) => s.toJson()).toList(),
  };

  static _GroupWorkout fromJson(Map<String, dynamic> json) => _GroupWorkout(
    groupTitle: json['groupTitle'] as String,
    cards: (json['cards'] as List<dynamic>)
        .map((c) => ExerciseCardData.fromJson(c as Map<String, dynamic>))
        .toList(),
    sets: (json['sets'] as List<dynamic>)
        .map((s) => _SetState.fromJson(s as Map<String, dynamic>))
        .toList(),
    activeCardIndex: json['activeCardIndex'] as int? ?? 0,
    groupCollapsed: json['groupCollapsed'] as bool? ?? true,
  );
}

class WorkoutPage extends StatefulWidget {
  const WorkoutPage({
    super.key,
    required this.template,
    required this.store,
    required this.onSaved,
    this.savedStateJson,
  });

  final TrainingTemplate template;
  final TemplateStore store;
  final VoidCallback onSaved;
  final String? savedStateJson;

  @override
  State<WorkoutPage> createState() => _WorkoutPageState();
}

class _WorkoutPageState extends State<WorkoutPage> with WidgetsBindingObserver {
  late DateTime _startTime;
  late String _id;
  Timer? _timer;

  final List<_GroupWorkout> _groups = [];
  int? _activeGIdx;
  int? _activeSIdx;
  bool _appInBackground = false;
  bool _keepFloatingOnIdle = false;

  final _weightCtrl = TextEditingController();
  final _repsCtrl = TextEditingController();
  final _restCtrl = TextEditingController();
  final _compensationCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  Feeling? _pendingFeeling;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));

    final mgr = WorkoutStateManager.instance;
    mgr.onStateChanged = _onWorkoutStateChanged;
    mgr.onRestTick = () {
      if (!mounted) return;
      setState(() {});
      if (mgr.state == WorkoutState.resting) {
        WorkoutChannel.updateNotification(
          state: 'resting',
          title: mgr.title,
          text: mgr.message,
          remainingSeconds: mgr.restRemainingSeconds,
          totalSeconds: mgr.restTotalSeconds,
        );
        WorkoutChannel.updateFloatingTimer(
          remainingSeconds: mgr.restRemainingSeconds,
          totalSeconds: mgr.restTotalSeconds,
        );
      }
    };
    mgr.onRestComplete = _onRestComplete;

    if (widget.savedStateJson != null) {
      _restoreFromJson(widget.savedStateJson!);
    } else {
      _startTime = DateTime.now();
      _id = DateTime.now().microsecondsSinceEpoch.toString();
      for (final action in widget.template.actions) {
        _groups.add(
          _GroupWorkout(
            groupTitle: action.groupTitle,
            cards: List.from(action.cards),
          ),
        );
      }
    }
  }

  void _onWorkoutStateChanged() {
    final mgr = WorkoutStateManager.instance;
    switch (mgr.state) {
      case WorkoutState.exercising:
        WorkoutChannel.updateNotification(
          state: 'exercising',
          title: mgr.title,
          text: mgr.exercisingBody,
        );
        WorkoutChannel.hideFloatingTimer();
      case WorkoutState.resting:
        WorkoutChannel.updateNotification(
          state: 'resting',
          title: mgr.title,
          text: mgr.message,
          remainingSeconds: mgr.restRemainingSeconds,
          totalSeconds: mgr.restTotalSeconds,
        );
        if (_appInBackground) {
          WorkoutChannel.showFloatingTimer(
            remainingSeconds: mgr.restRemainingSeconds,
            totalSeconds: mgr.restTotalSeconds,
          );
        }
      case WorkoutState.idle:
        WorkoutChannel.updateNotification(
          state: 'idle',
          title: mgr.title,
          text: mgr.message,
        );
        if (!_keepFloatingOnIdle) {
          WorkoutChannel.hideFloatingTimer();
        }
        _keepFloatingOnIdle = false;
    }
    if (mounted) setState(() {});
  }

  void _onRestComplete() {
    WorkoutChannel.triggerVibration();
    WorkoutChannel.showFloatingRestDone();
    WorkoutChannel.updateNotification(
      state: 'idle',
      title: WorkoutStateManager.instance.title,
      text: WorkoutStateManager.instance.message,
    );
    _keepFloatingOnIdle = true;
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _persistState();
    }
    if (state == AppLifecycleState.paused) {
      _appInBackground = true;
      if (WorkoutStateManager.instance.state == WorkoutState.resting) {
        final mgr = WorkoutStateManager.instance;
        WorkoutChannel.showFloatingTimer(
          remainingSeconds: mgr.restRemainingSeconds,
          totalSeconds: mgr.restTotalSeconds,
        );
      }
    } else if (state == AppLifecycleState.resumed) {
      _appInBackground = false;
      WorkoutChannel.hideFloatingTimer();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    WorkoutStateManager.instance.reset();
    WorkoutChannel.stopService();
    WorkoutChannel.hideFloatingTimer();
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

  void _skipRest() {
    WorkoutStateManager.instance.skipRest();
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

  String _serializeState() => jsonEncode({
    'id': _id,
    'templateId': widget.template.id,
    'startTime': _startTime.toIso8601String(),
    'activeGIdx': _activeGIdx,
    'activeSIdx': _activeSIdx,
    'groups': _groups.map((g) => g.toJson()).toList(),
  });

  void _restoreFromJson(String json) {
    final data = jsonDecode(json) as Map<String, dynamic>;
    _id = data['id'] as String;
    _startTime = DateTime.parse(data['startTime'] as String);
    _activeGIdx = data['activeGIdx'] as int?;
    _activeSIdx = data['activeSIdx'] as int?;
    _groups.addAll(
      (data['groups'] as List<dynamic>).map(
        (g) => _GroupWorkout.fromJson(g as Map<String, dynamic>),
      ),
    );
  }

  void _persistState() {
    widget.store.saveActiveWorkout(_serializeState());
  }

  Future<void> _startSet(int gIdx, int sIdx) async {
    final mgr = WorkoutStateManager.instance;
    if (!mgr.canStartSet()) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先完成当前正在训练的组')));
      return;
    }
    mgr.skipRest();
    final s = _groups[gIdx].sets[sIdx];
    _activeGIdx = gIdx;
    _activeSIdx = sIdx;
    s.editing = true;
    _loadCtrlsFromSet(s);
    if (mgr.state == WorkoutState.idle) {
      final ok = await WorkoutChannel.startService();
      if (!ok && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('需要通知权限才能显示运动状态')));
      }
    }
    mgr.startSet(
      groupTitle: s.groupTitle,
      cardName: s.exerciseName,
      setIndex: sIdx,
      plannedSets: _groups[gIdx].templateCount,
    );
    setState(() {});
    _persistState();
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
    s.compensation = _compensationCtrl.text.isNotEmpty
        ? _compensationCtrl.text
        : null;
    s.notes = _notesCtrl.text.isNotEmpty ? _notesCtrl.text : null;
    s.isComplete = true;
    s.editing = false;

    WorkoutStateManager.instance.completeSet(restSeconds: s.restSec);
    setState(() {});
    _persistState();
  }

  void _reopenSet(int gIdx, int sIdx) {
    final mgr = WorkoutStateManager.instance;
    mgr.skipRest();
    final s = _groups[gIdx].sets[sIdx];
    _activeGIdx = gIdx;
    _activeSIdx = sIdx;
    s.editing = true;
    _loadCtrlsFromSet(s);
    mgr.startSet(
      groupTitle: s.groupTitle,
      cardName: s.exerciseName,
      setIndex: sIdx,
      plannedSets: _groups[gIdx].templateCount,
    );
    setState(() {});
    _persistState();
  }

  bool get _canAddSet =>
      _activeGIdx == null ||
      _activeSIdx == null ||
      _groups[_activeGIdx!].sets[_activeSIdx!].isComplete;

  void _addExtraSet(int gIdx) {
    final g = _groups[gIdx];
    if (g.addNextTemplateSet()) {
      setState(() {});
      _persistState();
    } else {
      _promptExtraSet(gIdx);
    }
  }

  Future<void> _promptExtraSet(int gIdx) async {
    final g = _groups[gIdx];
    final card = g.activeCard;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('增加组'),
        content: Text('「${card.name}」已无待训练组，是否按最后一组参数再加一组？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('再加一组'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      g.addExtraSet();
      setState(() {});
      _persistState();
    }
  }

  void _switchCardInGroup(int gIdx, int cardIdx) {
    final g = _groups[gIdx];
    if (cardIdx == g.activeCardIndex) return;
    g.activeCardIndex = cardIdx;
    setState(() {});
    _persistState();
  }

  void _deleteSet(int gIdx, int sIdx) {
    final g = _groups[gIdx];
    g.sets.removeAt(sIdx);
    setState(() {});
    _persistState();
  }

  void _deleteCardFromGroup(int gIdx, int cardIdx) {
    final g = _groups[gIdx];
    g.cards.removeAt(cardIdx);
    if (cardIdx < g.activeCardIndex) {
      g.activeCardIndex--;
    } else if (cardIdx == g.activeCardIndex &&
        g.activeCardIndex >= g.cards.length) {
      g.activeCardIndex = g.cards.length - 1;
    }
    setState(() {});
    _persistState();
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
    final result = await showDialog<String>(
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
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('丢弃'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('保存并结束'),
          ),
        ],
      ),
    );
    if (result == 'save' && mounted) {
      await widget.store.saveWorkoutSession(session);
      widget.store.clearActiveWorkout();

      // 检查感受填写率，决定是否弹窗问AI总结
      final feelingRate = completedSets.isEmpty
          ? 0.0
          : completedSets.where((s) => s.feeling != null).length /
                completedSets.length;

      // 查找上次同模板的训练（后续AI、对比弹窗都要用）
      WorkoutSession? lastFull;
      {
        final allSessions = await widget.store.loadSessions();
        final lastSession = allSessions
            .where((s) => s.templateId == widget.template.id && s.id != _id)
            .fold<WorkoutSession?>(null, (prev, s) {
              if (prev == null || s.startTime.isAfter(prev.startTime)) return s;
              return prev;
            });
        if (lastSession != null) {
          lastFull = await widget.store.loadFullSession(lastSession.id);
        }
      }

      if (feelingRate >= 0.8 && mounted) {
        final wantAi = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('AI 总结'),
            content: const Text('是否生成本次训练的 AI 总结？\n包括评分、组分析、改进建议。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('不需要'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('生成总结'),
              ),
            ],
          ),
        );

        if (wantAi == true && mounted) {
          // loading
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
            final aiService = AIPlanService(store: widget.store);
            final evaluation = await aiService.evaluateWorkout(
              session: session,
              template: widget.template,
              lastSession: lastFull,
            );
            if (mounted) Navigator.pop(context); // 关掉loading
            if (evaluation != null) {
              session.aiSummary = jsonEncode({
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
              await widget.store.saveWorkoutSession(session);
            }
          } catch (e, s) {
            debugPrint('[finishWorkout] AI评估失败: $e\n$s');
            if (mounted) Navigator.pop(context); // 关掉loading
          }
        }
      }

      WorkoutStateManager.instance.reset();
      WorkoutChannel.stopService();
      WorkoutChannel.hideFloatingTimer();
      widget.onSaved();
      if (mounted) {
        // 跳转到详情页
        final full = await widget.store.loadFullSession(session.id);
        if (mounted) {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => WorkoutSummaryPage(
                session: full ?? session,
                store: widget.store,
                lastSession: lastFull,
              ),
            ),
          );
        }
      }
    } else if (result == 'discard' && mounted) {
      WorkoutStateManager.instance.reset();
      WorkoutChannel.stopService();
      WorkoutChannel.hideFloatingTimer();
      widget.store.clearActiveWorkout();
      Navigator.pop(context);
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
        body: Column(
          children: [
            if (WorkoutStateManager.instance.state == WorkoutState.resting)
              _buildRestTimerBar(),
            Expanded(
              child: _groups.isEmpty ? _buildEmptyState() : _buildContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Text(
        '模板中没有动作组',
        style: TextStyle(fontSize: 16, color: Colors.grey),
      ),
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
          color: allDone
              ? Colors.green.withValues(alpha: 0.4)
              : Colors.transparent,
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
                    g.groupCollapsed
                        ? Icons.keyboard_arrow_right
                        : Icons.keyboard_arrow_down,
                    size: 20,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          g.groupTitle,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (!g.groupCollapsed)
                          Text(
                            '$completed/$total 组 · ${g.activeCard.name}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (total > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
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
                          color: completed == total
                              ? Colors.greenAccent
                              : Colors.grey,
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
                    label: const Text('增加一组', style: TextStyle(fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
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
    final all = <MuscleGroup>{};
    for (final c in g.cards) {
      all.addAll(c.primaryMuscles);
    }
    if (all.isEmpty) return const SizedBox.shrink();
    return Text(
      '主肌群: ${all.map((m) => m.displayName).join(" · ")}',
      style: const TextStyle(fontSize: 12, color: Colors.grey),
    );
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
                  g.actionsExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: Colors.grey,
                ),
                const SizedBox(width: 4),
                Text(
                  '组内动作 (${g.cards.length}个)',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
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
                            '主: ${c.primaryMuscles.map((m) => m.displayName).join("·")}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
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
              label: Text(
                '${c.name} ${stats.done}/${stats.planned}',
                style: const TextStyle(fontSize: 12),
              ),
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
              style: const TextStyle(
                fontSize: 13,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 16),
            color: Colors.redAccent,
            visualDensity: VisualDensity.compact,
            onPressed: () => _deleteSet(gIdx, sIdx),
          ),
          TextButton(
            onPressed: () => _startSet(gIdx, sIdx),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
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
                child: Text(
                  '(平替)',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (card.keyPoints.isNotEmpty) ...[
                const Text(
                  '核心要领',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                ...card.keyPoints.map(
                  (p) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• ', style: TextStyle(fontSize: 13)),
                        Expanded(
                          child: Text(p, style: const TextStyle(fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (card.commonMistakes.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  '常见错误',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                ...card.commonMistakes.map(
                  (m) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '✗ ',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.redAccent,
                          ),
                        ),
                        Expanded(
                          child: Text(m, style: const TextStyle(fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (card.keyPoints.isEmpty && card.commonMistakes.isEmpty)
                const Text(
                  '暂无教程信息',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
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

  Widget _buildEditingSet(_GroupWorkout g, _SetState s, int gIdx, int sIdx) {
    final card = g.cards.firstWhere(
      (c) => c.name == s.exerciseName,
      orElse: () => g.activeCard,
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1F22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFB7FF00).withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 0),
            child: Row(
              children: [
                _setIndexBadge('${sIdx + 1}', const Color(0xFFB7FF00)),
                const SizedBox(width: 8),
                Text(
                  s.exerciseName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB7FF00).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    s.isComplete ? '编辑中' : '进行中',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFFB7FF00),
                    ),
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
                _adjustableField(
                  label: '重量(kg)',
                  ctrl: _weightCtrl,
                  step: 5,
                  isInt: false,
                ),
                const SizedBox(width: 6),
                _adjustableField(
                  label: '次数',
                  ctrl: _repsCtrl,
                  step: 1,
                  isInt: true,
                ),
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
                        vertical: 6,
                        horizontal: 8,
                      ),
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
                        vertical: 6,
                        horizontal: 8,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
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
                  style: const TextStyle(
                    fontSize: 13,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (s.feeling != null ||
                    s.compensation != null ||
                    s.notes != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: [
                        if (s.feeling != null) ...[
                          Text(
                            s.feeling!.emoji,
                            style: const TextStyle(fontSize: 14),
                          ),
                          const SizedBox(width: 2),
                          Text(
                            s.feeling!.label,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                        if (s.compensation != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            '代: ${s.compensation}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.orangeAccent,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 16),
            color: Colors.redAccent,
            visualDensity: VisualDensity.compact,
            onPressed: () => _deleteSet(gIdx, sIdx),
          ),
          TextButton(
            onPressed: () => _reopenSet(gIdx, sIdx),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('编辑', style: TextStyle(fontSize: 12)),
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
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 12,
          color: color,
        ),
      ),
    );
  }

  Widget _buildFeelingRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '训练感受（可选）',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        ),
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
                  horizontal: 10,
                  vertical: 4,
                ),
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
                    Text(
                      f.label,
                      style: TextStyle(
                        fontSize: 11,
                        color: selected ? const Color(0xFFB7FF00) : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildRestTimerBar() {
    final remaining = WorkoutStateManager.instance.restRemainingSeconds;
    final color = remaining > 20
        ? const Color(0xFFB7FF00)
        : remaining > 10
        ? Colors.orangeAccent
        : Colors.redAccent;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border(bottom: BorderSide(color: color.withValues(alpha: 0.3))),
      ),
      child: Row(
        children: [
          Icon(Icons.timer, size: 22, color: color),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '组间休息',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              Text(
                '$remaining 秒',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: color,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: _skipRest,
            icon: const Icon(Icons.skip_next, size: 18),
            label: const Text('跳过'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniField(String label, TextEditingController ctrl, {int flex = 1}) {
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
          contentPadding: const EdgeInsets.symmetric(
            vertical: 6,
            horizontal: 4,
          ),
        ),
      ),
    );
  }

  Widget _adjustableField({
    required String label,
    required TextEditingController ctrl,
    required double step,
    required bool isInt,
  }) {
    return Expanded(
      flex: 2,
      child: Row(
        children: [
          InkWell(
            onTap: () {
              final cur = isInt
                  ? (int.tryParse(ctrl.text) ?? 0)
                  : (double.tryParse(ctrl.text) ?? 0);
              final next = cur - step;
              ctrl.text = isInt
                  ? next.toInt().toString()
                  : next.toStringAsFixed(0);
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 2),
              child: Icon(Icons.remove_circle_outline, size: 18),
            ),
          ),
          Expanded(child: _miniField(label, ctrl)),
          InkWell(
            onTap: () {
              final cur = isInt
                  ? (int.tryParse(ctrl.text) ?? 0)
                  : (double.tryParse(ctrl.text) ?? 0);
              final next = cur + step;
              ctrl.text = isInt
                  ? next.toInt().toString()
                  : next.toStringAsFixed(0);
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 2),
              child: Icon(Icons.add_circle_outline, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}
