enum BodyRegion {
  core('核心'),
  chest('胸部'),
  back('背部'),
  shoulders('肩部'),
  arms('手臂'),
  legs('腿部'),
  calves('小腿');

  const BodyRegion(this.displayName);
  final String displayName;
}

enum MuscleGroup {
  // 核心
  rectusAbdominis('腹直肌', BodyRegion.core),
  obliques('腹斜肌', BodyRegion.core),
  transverseAbdominis('腹横肌', BodyRegion.core),
  erectorSpinae('竖脊肌', BodyRegion.core),

  // 胸部
  upperChest('上胸', BodyRegion.chest),
  midChest('中胸', BodyRegion.chest),
  lowerChest('下胸', BodyRegion.chest),
  pectoralisMinor('胸小肌', BodyRegion.chest),

  // 背部
  latissimusDorsi('背阔肌', BodyRegion.back),
  midTraps('斜方肌中束', BodyRegion.back),
  lowerTraps('斜方肌下束', BodyRegion.back),
  rhomboids('菱形肌', BodyRegion.back),
  teresMajor('大圆肌/小圆肌', BodyRegion.back),

  // 肩部
  frontDeltoid('三角肌前束', BodyRegion.shoulders),
  sideDeltoid('三角肌中束', BodyRegion.shoulders),
  rearDeltoid('三角肌后束', BodyRegion.shoulders),
  upperTraps('斜方肌上束', BodyRegion.shoulders),

  // 手臂
  biceps('肱二头肌', BodyRegion.arms),
  triceps('肱三头肌', BodyRegion.arms),
  forearms('前臂肌群', BodyRegion.arms),

  // 腿部
  quadriceps('股四头肌', BodyRegion.legs),
  hamstrings('腘绳肌', BodyRegion.legs),
  adductors('内收肌群', BodyRegion.legs),
  glutes('臀部', BodyRegion.legs),

  // 小腿
  gastrocnemius('腓肠肌', BodyRegion.calves),
  soleus('比目鱼肌', BodyRegion.calves);

  const MuscleGroup(this.displayName, this.region);
  final String displayName;
  final BodyRegion region;

  static MuscleGroup? tryParse(String value) {
    final v = value.trim().replaceAll(' ', '');
    for (final mg in values) {
      if (mg.name == v) return mg;
      if (mg.displayName == v) return mg;
      if (mg.displayName.replaceAll('/', '') == v) return mg;
    }
    for (final mg in values) {
      if (mg.displayName.replaceAll('/', '').contains(v) ||
          v.contains(mg.displayName.replaceAll('/', ''))) {
        return mg;
      }
    }
    if (v == '胸大肌') return upperChest;
    if (v == '大圆肌' || v == '小圆肌') return teresMajor;
    if (v == '斜方肌') return midTraps;
    if (v == '三角肌') return sideDeltoid;
    if (v == '大腿内收肌') return adductors;
    if (v == '小腿' || v == '小腿后侧') return gastrocnemius;
    if (v == '上背') return rhomboids;
    if (v == '下背' || v == '下背部') return erectorSpinae;
    if (v == '腹肌' || v == '腹部') return rectusAbdominis;
    if (v == '腰' || v == '腰部') return erectorSpinae;
    return null;
  }
}

class TrainingSet {
  TrainingSet({
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
    List<MuscleGroup>? primaryMuscles,
    List<MuscleGroup>? secondaryMuscles,
    List<String>? keyPoints,
    List<String>? commonMistakes,
  }) : sets = sets ?? [TrainingSet(weightKg: 20, reps: 10, restSec: 60)],
       primaryMuscles = primaryMuscles ?? [],
       secondaryMuscles = secondaryMuscles ?? [],
       keyPoints = keyPoints ?? [],
       commonMistakes = commonMistakes ?? [];

  String name;
  bool isPrimary;
  List<TrainingSet> sets;
  List<MuscleGroup> primaryMuscles;
  List<MuscleGroup> secondaryMuscles;
  List<String> keyPoints;
  List<String> commonMistakes;

  Map<String, dynamic> toJson() => {
    'name': name,
    'isPrimary': isPrimary,
    'sets': sets.map((e) => e.toJson()).toList(),
    'primaryMuscles': primaryMuscles.map((e) => e.name).toList(),
    'secondaryMuscles': secondaryMuscles.map((e) => e.name).toList(),
    'keyPoints': keyPoints,
    'commonMistakes': commonMistakes,
  };

  static ExerciseCardData fromJson(Map<String, dynamic> json) =>
      ExerciseCardData(
        name: json['name'] as String? ?? '',
        isPrimary: json['isPrimary'] as bool? ?? false,
        sets: (json['sets'] as List<dynamic>? ?? [])
            .map((e) => TrainingSet.fromJson(e as Map<String, dynamic>))
            .toList(),
        primaryMuscles: (json['primaryMuscles'] as List<dynamic>? ?? [])
            .map((e) => MuscleGroup.tryParse(e.toString()))
            .whereType<MuscleGroup>()
            .toList(),
        secondaryMuscles: (json['secondaryMuscles'] as List<dynamic>? ?? [])
            .map((e) => MuscleGroup.tryParse(e.toString()))
            .whereType<MuscleGroup>()
            .toList(),
        keyPoints: (json['keyPoints'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
        commonMistakes: (json['commonMistakes'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      );
}

class TrainingAction {
  TrainingAction({
    required this.groupTitle,
    required List<ExerciseCardData> cards,
  }) : cards = cards.isEmpty
           ? [ExerciseCardData(name: groupTitle, isPrimary: true)]
           : cards;

  String groupTitle;
  List<ExerciseCardData> cards;

  Map<String, dynamic> toJson() => {
    'groupTitle': groupTitle,
    'cards': cards.map((e) => e.toJson()).toList(),
  };

  static TrainingAction fromJson(Map<String, dynamic> json) {
    final legacySets = (json['sets'] as List<dynamic>?)
        ?.map((e) => TrainingSet.fromJson(e as Map<String, dynamic>))
        .toList();
    final legacyAlts = (json['alternatives'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList();
    final cardsJson = (json['cards'] as List<dynamic>? ?? [])
        .map((e) => ExerciseCardData.fromJson(e as Map<String, dynamic>))
        .toList();
    if (cardsJson.isNotEmpty)
      return TrainingAction(
        groupTitle:
            json['groupTitle'] as String? ?? json['name'] as String? ?? '动作',
        cards: cardsJson,
      );

    final mainName = json['name'] as String? ?? '动作';
    final baseSets = legacySets == null || legacySets.isEmpty
        ? [TrainingSet(weightKg: 20, reps: 10, restSec: 60)]
        : legacySets;
    final cards = <ExerciseCardData>[
      ExerciseCardData(name: mainName, isPrimary: true, sets: baseSets),
    ];
    for (final alt in legacyAlts) {
      cards.add(
        ExerciseCardData(
          name: alt,
          sets: [
            TrainingSet(
              weightKg: baseSets.first.weightKg,
              reps: baseSets.first.reps,
              restSec: baseSets.first.restSec,
            ),
          ],
        ),
      );
    }
    return TrainingAction(groupTitle: mainName, cards: cards);
  }
}

class TrainingTemplate {
  TrainingTemplate({
    required this.id,
    required this.folder,
    required this.name,
    required this.actions,
    this.intent = '',
    this.aiSummary = '',
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

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

  static TrainingTemplate fromJson(Map<String, dynamic> json) =>
      TrainingTemplate(
        id:
            json['id'] as String? ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        folder: json['folder'] as String? ?? '',
        name: json['name'] as String? ?? '',
        intent: json['intent'] as String? ?? '',
        aiSummary: json['aiSummary'] as String? ?? '',
        actions: (json['actions'] as List<dynamic>? ?? [])
            .map((e) => TrainingAction.fromJson(e as Map<String, dynamic>))
            .toList(),
        updatedAt:
            DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.now(),
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
    actions: (json['actions'] as List<dynamic>? ?? [])
        .map((e) => TrainingAction.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
