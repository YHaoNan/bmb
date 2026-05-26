
class TrainingSet {
  TrainingSet({required this.weightKg, required this.reps, required this.restSec});
  double weightKg;
  int reps;
  int restSec;

  Map<String, dynamic> toJson() => {'weightKg': weightKg, 'reps': reps, 'restSec': restSec};

  static TrainingSet fromJson(Map<String, dynamic> json) => TrainingSet(
        weightKg: (json['weightKg'] as num?)?.toDouble() ?? 20,
        reps: (json['reps'] as num?)?.toInt() ?? 10,
        restSec: (json['restSec'] as num?)?.toInt() ?? 60,
      );
}

class ExerciseCardData {
  ExerciseCardData({
    required this.name,
    List<TrainingSet>? sets,
    this.isPrimary = false,
    List<String>? primaryMuscles,
    List<String>? secondaryMuscles,
    List<String>? keyPoints,
    List<String>? commonMistakes,
  })  : sets = sets ?? [TrainingSet(weightKg: 20, reps: 10, restSec: 60)],
        primaryMuscles = primaryMuscles ?? [],
        secondaryMuscles = secondaryMuscles ?? [],
        keyPoints = keyPoints ?? [],
        commonMistakes = commonMistakes ?? [];

  String name;
  bool isPrimary;
  List<TrainingSet> sets;
  List<String> primaryMuscles;
  List<String> secondaryMuscles;
  List<String> keyPoints;
  List<String> commonMistakes;

  Map<String, dynamic> toJson() => {
        'name': name,
        'isPrimary': isPrimary,
        'sets': sets.map((e) => e.toJson()).toList(),
        'primaryMuscles': primaryMuscles,
        'secondaryMuscles': secondaryMuscles,
        'keyPoints': keyPoints,
        'commonMistakes': commonMistakes,
      };

  static ExerciseCardData fromJson(Map<String, dynamic> json) => ExerciseCardData(
        name: json['name'] as String? ?? '',
        isPrimary: json['isPrimary'] as bool? ?? false,
        sets: (json['sets'] as List<dynamic>? ?? []).map((e) => TrainingSet.fromJson(e as Map<String, dynamic>)).toList(),
        primaryMuscles: (json['primaryMuscles'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
        secondaryMuscles: (json['secondaryMuscles'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
        keyPoints: (json['keyPoints'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
        commonMistakes: (json['commonMistakes'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
      );
}

class TrainingAction {
  TrainingAction({required this.groupTitle, required List<ExerciseCardData> cards}) : cards = cards.isEmpty ? [ExerciseCardData(name: groupTitle, isPrimary: true)] : cards;

  String groupTitle;
  List<ExerciseCardData> cards;

  Map<String, dynamic> toJson() => {'groupTitle': groupTitle, 'cards': cards.map((e) => e.toJson()).toList()};

  static TrainingAction fromJson(Map<String, dynamic> json) {
    final legacySets = (json['sets'] as List<dynamic>?)?.map((e) => TrainingSet.fromJson(e as Map<String, dynamic>)).toList();
    final legacyAlts = (json['alternatives'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
    final cardsJson = (json['cards'] as List<dynamic>? ?? []).map((e) => ExerciseCardData.fromJson(e as Map<String, dynamic>)).toList();
    if (cardsJson.isNotEmpty) return TrainingAction(groupTitle: json['groupTitle'] as String? ?? json['name'] as String? ?? '动作', cards: cardsJson);

    final mainName = json['name'] as String? ?? '动作';
    final baseSets = legacySets == null || legacySets.isEmpty ? [TrainingSet(weightKg: 20, reps: 10, restSec: 60)] : legacySets;
    final cards = <ExerciseCardData>[ExerciseCardData(name: mainName, isPrimary: true, sets: baseSets)];
    for (final alt in legacyAlts) {
      cards.add(ExerciseCardData(name: alt, sets: [TrainingSet(weightKg: baseSets.first.weightKg, reps: baseSets.first.reps, restSec: baseSets.first.restSec)]));
    }
    return TrainingAction(groupTitle: mainName, cards: cards);
  }
}

class TrainingTemplate {
  TrainingTemplate({required this.id, required this.folder, required this.name, required this.actions, this.intent = '', this.aiSummary = '', DateTime? updatedAt})
      : updatedAt = updatedAt ?? DateTime.now();

  String id;
  String folder;
  String name;
  String intent;
  String aiSummary;
  List<TrainingAction> actions;
  DateTime updatedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'folder': folder,
        'name': name,
        'intent': intent,
        'aiSummary': aiSummary,
        'actions': actions.map((e) => e.toJson()).toList(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  static TrainingTemplate fromJson(Map<String, dynamic> json) => TrainingTemplate(
        id: json['id'] as String? ?? DateTime.now().microsecondsSinceEpoch.toString(),
        folder: json['folder'] as String? ?? '',
        name: json['name'] as String? ?? '',
        intent: json['intent'] as String? ?? '',
        aiSummary: json['aiSummary'] as String? ?? '',
        actions: (json['actions'] as List<dynamic>? ?? []).map((e) => TrainingAction.fromJson(e as Map<String, dynamic>)).toList(),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
      );
}

class TemplateDraft {
  TemplateDraft({
    this.folder = '',
    this.templateName = '',
    this.intentText = '',
    List<TrainingAction>? actions,
    this.aiSummary = '',
    this.trainingPart = '胸背',
    this.ability = '新手',
    this.preference = '固定器械',
  }) : actions = actions ?? [];

  String folder;
  String templateName;
  String intentText;
  String aiSummary;
  String trainingPart;
  String ability;
  String preference;
  List<TrainingAction> actions;

  Map<String, dynamic> toJson() => {
        'folder': folder,
        'templateName': templateName,
        'intentText': intentText,
        'aiSummary': aiSummary,
        'trainingPart': trainingPart,
        'ability': ability,
        'preference': preference,
        'actions': actions.map((e) => e.toJson()).toList(),
      };

  static TemplateDraft fromJson(Map<String, dynamic> json) => TemplateDraft(
        folder: json['folder'] as String? ?? '',
        templateName: json['templateName'] as String? ?? '',
        intentText: json['intentText'] as String? ?? '',
        aiSummary: json['aiSummary'] as String? ?? '',
        trainingPart: json['trainingPart'] as String? ?? '胸背',
        ability: json['ability'] as String? ?? '新手',
        preference: json['preference'] as String? ?? '固定器械',
        actions: (json['actions'] as List<dynamic>? ?? []).map((e) => TrainingAction.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

