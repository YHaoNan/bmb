import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum WorkoutState { idle, exercising, resting }

enum WorkoutPhase { notStarted, inProgress, finished }

class WorkoutStateManager {
  WorkoutStateManager._();
  static final WorkoutStateManager _instance = WorkoutStateManager._();
  static WorkoutStateManager get instance => _instance;

  WorkoutState _state = WorkoutState.idle;
  WorkoutPhase _phase = WorkoutPhase.notStarted;

  WorkoutState get state => _state;
  WorkoutPhase get phase => _phase;

  String? activeGroupTitle;
  String? activeCardName;
  int activeSetIndex = -1;
  int activeSetPlanned = 0;

  int restTotalSeconds = 0;
  int restRemainingSeconds = 0;
  Timer? _restTimer;

  VoidCallback? onStateChanged;
  VoidCallback? onRestTick;

  static const _restMessages = [
    '认真回忆动作要领吧~',
    '好好舒展一下吧~',
    '去看看小红书放松下吧~',
    '调整呼吸，准备下一组~',
    '喝口水，别急着开始~',
    '想想刚才的动作哪里可以改进~',
  ];
  static const _idleMessages = [
    '当前还没开始训练，抓紧整两下子吧！',
    '别愣着了，该动起来了！',
    '热身做了吗？准备开始吧~',
    '今天的目标是什么？',
  ];
  static const _exercisingMessages = [
    '集中注意力，感受目标肌群~',
    '控制节奏，不要借力~',
    '保持呼吸，不要憋气~',
    '动作标准比重量更重要~',
  ];
  String? _currentMessage;

  String get message {
    return _currentMessage ?? _idleMessages[0];
  }

  void _pickRandomMessage(WorkoutState forState) {
    switch (forState) {
      case WorkoutState.idle:
        _currentMessage =
            _idleMessages[DateTime.now().millisecondsSinceEpoch %
                _idleMessages.length];
      case WorkoutState.exercising:
        _currentMessage =
            _exercisingMessages[DateTime.now().millisecondsSinceEpoch %
                _exercisingMessages.length];
      case WorkoutState.resting:
        _currentMessage =
            _restMessages[DateTime.now().millisecondsSinceEpoch %
                _restMessages.length];
    }
  }

  String get title {
    switch (_state) {
      case WorkoutState.idle:
        return '尚未开始';
      case WorkoutState.exercising:
        return activeCardName ?? '训练中';
      case WorkoutState.resting:
        return '休息中';
    }
  }

  String get exercisingBody {
    final g = activeGroupTitle ?? '';
    final c = activeCardName ?? '';
    final s = activeSetIndex + 1;
    final p = activeSetPlanned;
    return '$g - $c\n第$s组 / 计划$p组';
  }

  bool canStartSet() => _state != WorkoutState.exercising;

  void startSet({
    required String groupTitle,
    required String cardName,
    required int setIndex,
    required int plannedSets,
  }) {
    if (_state == WorkoutState.exercising) return;
    if (_state == WorkoutState.resting) {
      _restTimer?.cancel();
      _restTimer = null;
    }
    _state = WorkoutState.exercising;
    _phase = WorkoutPhase.inProgress;
    activeGroupTitle = groupTitle;
    activeCardName = cardName;
    activeSetIndex = setIndex;
    activeSetPlanned = plannedSets;
    _pickRandomMessage(WorkoutState.exercising);
    onStateChanged?.call();
  }

  void completeSet({int restSeconds = 60}) {
    _state = WorkoutState.resting;
    restTotalSeconds = restSeconds;
    restRemainingSeconds = restSeconds;
    _pickRandomMessage(WorkoutState.resting);
    _restTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      restRemainingSeconds--;
      onRestTick?.call();
      if (restRemainingSeconds <= 0) {
        _restTimer?.cancel();
        _restTimer = null;
        _state = WorkoutState.idle;
        _pickRandomMessage(WorkoutState.idle);
        _onRestComplete();
      }
    });
    onStateChanged?.call();
  }

  VoidCallback? onRestComplete;

  void _onRestComplete() {
    onRestComplete?.call();
    onStateChanged?.call();
  }

  void skipRest() {
    _restTimer?.cancel();
    _restTimer = null;
    _state = WorkoutState.idle;
    _pickRandomMessage(WorkoutState.idle);
    onStateChanged?.call();
  }

  int get restProgressPercent {
    if (restTotalSeconds <= 0) return 0;
    return ((restRemainingSeconds / restTotalSeconds) * 100).round();
  }

  void reset() {
    _restTimer?.cancel();
    _restTimer = null;
    _state = WorkoutState.idle;
    _phase = WorkoutPhase.notStarted;
    _currentMessage = null;
    activeGroupTitle = null;
    activeCardName = null;
    activeSetIndex = -1;
    activeSetPlanned = 0;
    restTotalSeconds = 0;
    restRemainingSeconds = 0;
  }
}

class WorkoutChannel {
  static const _channel = MethodChannel('com.bmb.app/workout');

  static Future<bool> startService() async {
    return await _channel.invokeMethod('startWorkoutService') ?? false;
  }

  static Future<void> updateNotification({
    required String state,
    required String title,
    required String text,
    int remainingSeconds = 0,
    int totalSeconds = 0,
  }) async {
    await _channel.invokeMethod('updateNotification', {
      'state': state,
      'title': title,
      'text': text,
      'remainingSeconds': remainingSeconds,
      'totalSeconds': totalSeconds,
    });
  }

  static Future<void> stopService() async {
    await _channel.invokeMethod('stopWorkoutService');
  }

  static Future<void> showFloatingTimer({
    required int remainingSeconds,
    required int totalSeconds,
  }) async {
    await _channel.invokeMethod('showFloatingTimer', {
      'remainingSeconds': remainingSeconds,
      'totalSeconds': totalSeconds,
    });
  }

  static Future<void> hideFloatingTimer() async {
    await _channel.invokeMethod('hideFloatingTimer');
  }

  static Future<void> updateFloatingTimer({
    required int remainingSeconds,
    required int totalSeconds,
  }) async {
    await _channel.invokeMethod('updateFloatingTimer', {
      'remainingSeconds': remainingSeconds,
      'totalSeconds': totalSeconds,
    });
  }

  static Future<void> showFloatingRestDone() async {
    await _channel.invokeMethod('showFloatingRestDone');
  }

  static Future<void> triggerVibration() async {
    await _channel.invokeMethod('triggerVibration');
  }

  static Future<bool> checkOverlayPermission() async {
    return await _channel.invokeMethod('checkOverlayPermission') ?? false;
  }

  static Future<void> requestOverlayPermission() async {
    await _channel.invokeMethod('requestOverlayPermission');
  }
}

class LlmLogSaver {
  static const _channel = MethodChannel('com.bmb.app/backup');

  static Future<void> save(String prompt, String response) async {
    try {
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final fileName = 'llm_$timestamp.json';
      final content = jsonEncode({
        'timestamp': DateTime.now().toIso8601String(),
        'prompt': prompt,
        'response': response,
      });
      await _channel.invokeMethod('saveLlmLog', {
        'content': content,
        'fileName': fileName,
      });
    } catch (e) {
      debugPrint('[LlmLogSaver] save error: $e');
    }
  }
}
