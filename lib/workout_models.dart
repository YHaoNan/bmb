import 'models.dart';

enum Feeling { easy, moderate, failed }

extension FeelingLabel on Feeling {
  String get label {
    switch (this) {
      case Feeling.easy:
        return '轻而易举';
      case Feeling.moderate:
        return '有点吃力';
      case Feeling.failed:
        return '无法完成';
    }
  }

  String get emoji {
    switch (this) {
      case Feeling.easy:
        return '😋';
      case Feeling.moderate:
        return '😣';
      case Feeling.failed:
        return '🥵';
    }
  }
}

class SetRecord {
  SetRecord({
    required this.weightKg,
    required this.reps,
    required this.restSec,
  });

  double weightKg;
  int reps;
  int restSec;

  Map<String, dynamic> toJson() => {
    'weightKg': weightKg,
    'reps': reps,
    'restSec': restSec,
  };

  static SetRecord fromJson(Map<String, dynamic> json) => SetRecord(
    weightKg: (json['weightKg'] as num?)?.toDouble() ?? 20,
    reps: (json['reps'] as num?)?.toInt() ?? 10,
    restSec: (json['restSec'] as num?)?.toInt() ?? 60,
  );

  factory SetRecord.fromTrainingSet(TrainingSet s) =>
      SetRecord(weightKg: s.weightKg, reps: s.reps, restSec: s.restSec);
}

class ExerciseRecord {
  ExerciseRecord({
    required this.groupTitle,
    required this.cardName,
    this.isAlternative = false,
    List<SetRecord>? sets,
    this.feeling,
    this.compensation,
    this.notes,
    this.weightModified = false,
    this.repsModified = false,
    this.restModified = false,
  }) : sets = sets ?? [];

  String groupTitle;
  String cardName;
  bool isAlternative;
  List<SetRecord> sets;
  Feeling? feeling;
  String? compensation;
  String? notes;
  bool weightModified;
  bool repsModified;
  bool restModified;

  bool get modified => weightModified || repsModified || restModified;

  Map<String, dynamic> toJson() => {
    'groupTitle': groupTitle,
    'cardName': cardName,
    'isAlternative': isAlternative,
    'sets': sets.map((e) => e.toJson()).toList(),
    'feeling': feeling?.name,
    'compensation': compensation,
    'notes': notes,
    'weightModified': weightModified,
    'repsModified': repsModified,
    'restModified': restModified,
  };

  static ExerciseRecord fromJson(Map<String, dynamic> json) => ExerciseRecord(
    groupTitle: json['groupTitle'] as String? ?? '',
    cardName: json['cardName'] as String? ?? '',
    isAlternative: json['isAlternative'] as bool? ?? false,
    sets:
        (json['sets'] as List<dynamic>?)
            ?.map((e) => SetRecord.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    feeling: (json['feeling'] as String?) != null
        ? Feeling.values.firstWhere((f) => f.name == json['feeling'])
        : null,
    compensation: json['compensation'] as String?,
    notes: json['notes'] as String?,
    weightModified: json['weightModified'] as bool? ?? false,
    repsModified: json['repsModified'] as bool? ?? false,
    restModified: json['restModified'] as bool? ?? false,
  );
}

class WorkoutSession {
  WorkoutSession({
    required this.id,
    required this.templateId,
    required this.templateName,
    required this.startTime,
    this.endTime,
    List<ExerciseRecord>? exercises,
    this.note,
    this.aiSummary,
    this.totalSets,
    this.completedSets,
  }) : exercises = exercises ?? [];

  String id;
  String templateId;
  String templateName;
  DateTime startTime;
  DateTime? endTime;
  List<ExerciseRecord> exercises;
  String? note;
  String? aiSummary;
  int? totalSets;
  int? completedSets;

  Duration? get duration {
    if (endTime == null) return null;
    return endTime!.difference(startTime);
  }

  String get durationText {
    final d = duration;
    if (d == null) return '进行中';
    final min = d.inMinutes;
    if (min < 60) return '$min分钟';
    return '${min ~/ 60}小时${min % 60}分钟';
  }

  int get completedCount => completedSets ?? exercises.where((e) => e.feeling != null).length;

  int get totalCount => totalSets ?? exercises.length;

  Map<String, dynamic> toJson() => {
    'id': id,
    'templateId': templateId,
    'templateName': templateName,
    'startTime': startTime.toIso8601String(),
    'endTime': endTime?.toIso8601String(),
    'exercises': exercises.map((e) => e.toJson()).toList(),
    'note': note,
    'aiSummary': aiSummary,
  };

  static WorkoutSession fromJson(Map<String, dynamic> json) => WorkoutSession(
    id:
        json['id'] as String? ??
        DateTime.now().microsecondsSinceEpoch.toString(),
    templateId: json['templateId'] as String? ?? '',
    templateName: json['templateName'] as String? ?? '',
    startTime: DateTime.parse(json['startTime'] as String),
    endTime: json['endTime'] != null
        ? DateTime.tryParse(json['endTime'] as String)
        : null,
    exercises:
        (json['exercises'] as List<dynamic>?)
            ?.map((e) => ExerciseRecord.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    note: json['note'] as String?,
    aiSummary: json['aiSummary'] as String?,
  );
}
