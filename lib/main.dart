import 'dart:convert';
import 'package:flutter/material.dart';
import 'models.dart';
import 'template_store.dart';
import 'ai_plan_service.dart';
import 'model_config_page.dart';
import 'workout_records_page.dart';
import 'workout_page.dart';

void main() {
  runApp(const BmbApp());
}

class BmbApp extends StatelessWidget {
  const BmbApp({super.key});

  @override
  Widget build(BuildContext context) {
    const neon = Color(0xFFB7FF00);
    const carbon = Color(0xFF111315);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BMB',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0B0C0E),
        colorScheme: ColorScheme.fromSeed(
          seedColor: neon,
          brightness: Brightness.dark,
        ).copyWith(primary: neon, surface: carbon),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        cardTheme: const CardThemeData(
          color: Color(0xFF15181B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(18)),
          ),
        ),
      ),
      home: const AppShell(),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  final TemplateStore _store = TemplateStore();

  @override
  Widget build(BuildContext context) {
    final pages = [
      const TemplateHomePage(),
      WorkoutRecordsPage(store: _store),
      ModelConfigPage(store: _store),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (v) => setState(() => _index = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.fitness_center), label: '模板'),
          NavigationDestination(
            icon: Icon(Icons.sports_gymnastics),
            label: '运动记录',
          ),
          NavigationDestination(icon: Icon(Icons.tune), label: '模型配置'),
        ],
      ),
    );
  }
}

class TemplateHomePage extends StatefulWidget {
  const TemplateHomePage({super.key});

  @override
  State<TemplateHomePage> createState() => _TemplateHomePageState();
}

class _TemplateHomePageState extends State<TemplateHomePage> {
  final store = TemplateStore();
  List<TrainingTemplate> templates = [];
  List<String> folders = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    reload();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkActiveWorkout());
  }

  Future<void> _checkActiveWorkout() async {
    final saved = await store.loadActiveWorkout();
    if (saved == null || !mounted) return;
    final data = jsonDecode(saved) as Map<String, dynamic>;
    final templateId = data['templateId'] as String? ?? '';

    // 主动加载模板列表，避免竞态（reload 可能还没完成）
    var allTemplates = List<TrainingTemplate>.from(templates);
    if (allTemplates.isEmpty) {
      allTemplates = await store.loadTemplates();
    }
    final template = allTemplates.cast<TrainingTemplate?>().firstWhere(
      (t) => t?.id == templateId,
      orElse: () => null,
    );
    if (template == null) {
      await store.clearActiveWorkout();
      return;
    }
    final tpl = template!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复训练'),
        content: Text('检测到未完成的训练「${tpl.name}」，是否继续？'),
        actions: [
          TextButton(
            onPressed: () {
              store.clearActiveWorkout();
              Navigator.pop(ctx, false);
            },
            child: const Text('丢弃'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WorkoutPage(
            template: tpl,
            store: store,
            savedStateJson: saved,
            onSaved: reload,
          ),
        ),
      );
    }
  }

  Future<void> reload() async {
    folders = await store.loadFolders();
    templates = await store.loadTemplates();
    if (!mounted) return;
    setState(() => loading = false);
  }

  Future<void> openEditor([TrainingTemplate? t]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TemplateEditorPage(
          store: store,
          initialFolders: folders,
          allTemplates: templates,
          editing: t,
        ),
      ),
    );
    reload();
  }

  Future<void> renameFolder(String folder) async {
    final c = TextEditingController(text: folder);
    final v = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('改个更顺手的名字'),
        content: TextField(controller: c),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text.trim()),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (v == null || v.isEmpty || folders.contains(v)) return;
    final idx = folders.indexOf(folder);
    if (idx >= 0) folders[idx] = v;
    for (final t in templates.where((e) => e.folder == folder)) {
      t.folder = v;
    }
    await store.saveFolders(folders);
    await store.saveTemplates(templates);
    setState(() {});
  }

  Future<void> deleteFolder(String folder) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('确认删除文件夹？'),
        content: Text('会删除该文件夹下的全部模板。\n$folder'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    folders.remove(folder);
    templates.removeWhere((e) => e.folder == folder);
    await store.saveFolders(folders);
    await store.saveTemplates(templates);
    setState(() {});
  }

  Future<void> deleteTemplate(TrainingTemplate t) async {
    templates.removeWhere((e) => e.id == t.id);
    await store.saveTemplates(templates);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1D2D0F), Color(0xFF0E1012)],
                      ),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: const Color(0xFFB7FF00).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '把今天练什么，变成一套能坚持的模板。',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: openEditor,
                          icon: const Icon(Icons.bolt),
                          label: const Text('开始创建'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Theme(
                    data: Theme.of(context).copyWith(
                      dividerColor: Colors.transparent,
                      splashFactory: NoSplash.splashFactory,
                      highlightColor: Colors.transparent,
                    ),
                    child: Column(
                      children: folders.map((f) {
                        final list = templates
                            .where((e) => e.folder == f)
                            .toList();
                        return Card(
                          child: ExpansionTile(
                            tilePadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 2,
                            ),
                            childrenPadding: const EdgeInsets.fromLTRB(
                              10,
                              0,
                              10,
                              10,
                            ),
                            title: Text(f),
                            subtitle: Text('${list.length} 个模板'),
                            trailing: Wrap(
                              spacing: 4,
                              children: [
                                IconButton(
                                  onPressed: () => renameFolder(f),
                                  icon: const Icon(
                                    Icons.drive_file_rename_outline,
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => deleteFolder(f),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                            children: list
                                .map(
                                  (t) => Container(
                                    margin: const EdgeInsets.only(top: 8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1A1D20),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      splashFactory: NoSplash.splashFactory,
                                      highlightColor: Colors.transparent,
                                      onTap: () => openEditor(t),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    t.name,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 3),
                                                  Text(
                                                    '动作组 ${t.actions.length}',
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      color: Color(0xFFA6ABB2),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            IconButton(
                                              onPressed: () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) => WorkoutPage(
                                                       template: t,
                                                       store: store,
                                                       onSaved: reload,
                                                     ),
                                                  ),
                                                );
                                              },
                                              icon: const Icon(
                                                Icons.play_circle_outline,
                                                color: Color(0xFFB7FF00),
                                              ),
                                            ),
                                            IconButton(
                                              onPressed: () =>
                                                  deleteTemplate(t),
                                              icon: const Icon(
                                                Icons.delete_outline,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class TemplateEditorPage extends StatefulWidget {
  const TemplateEditorPage({
    super.key,
    required this.store,
    required this.initialFolders,
    required this.allTemplates,
    this.editing,
  });

  final TemplateStore store;
  final List<String> initialFolders;
  final List<TrainingTemplate> allTemplates;
  final TrainingTemplate? editing;

  @override
  State<TemplateEditorPage> createState() => _TemplateEditorPageState();
}

class _TemplateEditorPageState extends State<TemplateEditorPage> {
  final nameController = TextEditingController();
  final intentController = TextEditingController();

  late List<String> folders;
  late String selectedFolder;

  List<TrainingAction> actions = [];
  String aiSummary = '';
  bool ready = false;
  late AIPlanService _aiPlanService;
  final Map<int, PageController> _trackControllers = {};
  final Map<int, double> _trackPages = {};

  @override
  void initState() {
    super.initState();
    _aiPlanService = AIPlanService(store: widget.store);
    folders = [...widget.initialFolders];
    selectedFolder = folders.isEmpty ? '' : folders.first;
    loadData();
  }

  @override
  void dispose() {
    for (final controller in _trackControllers.values) {
      controller.dispose();
    }
    nameController.dispose();
    intentController.dispose();
    super.dispose();
  }

  String buildIntent() => '请帮我安排一套效率高、可执行的训练模板，并给出动作要领、常见错误、平替建议和整体评价。';

  Future<void> loadData() async {
    if (widget.editing != null) {
      final e = widget.editing!;
      nameController.text = e.name;
      selectedFolder = e.folder;
      actions = e.actions
          .map((a) => TrainingAction.fromJson(a.toJson()))
          .toList();
      intentController.text = e.intent;
      aiSummary = e.aiSummary;
      ready = true;
      setState(() {});
      return;
    }

    final draft = await widget.store.loadDraft();
    if (draft != null) {
      nameController.text = draft.templateName;
      intentController.text = draft.intentText;
      selectedFolder = draft.folder;
      actions = draft.actions;
      aiSummary = draft.aiSummary;
      if (!folders.contains(selectedFolder)) folders.add(selectedFolder);
    } else {
      intentController.text = buildIntent();
    }
    if (selectedFolder.isEmpty && folders.isNotEmpty) {
      selectedFolder = folders.first;
    }
    ready = true;
    setState(() {});
  }

  Future<void> saveDraft() async {
    if (widget.editing != null) return;
    await widget.store.saveDraft(
      TemplateDraft(
        folder: selectedFolder,
        templateName: nameController.text.trim(),
        intentText: intentController.text,
        actions: actions,
        aiSummary: aiSummary,
      ),
    );
  }

  Future<void> addFolder() async {
    final c = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('新增文件夹'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(hintText: '例如：推日 / 拉日 / 腿日'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text.trim()),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (v == null || v.isEmpty || folders.contains(v)) return;
    folders.add(v);
    selectedFolder = v;
    await widget.store.saveFolders(folders);
    saveDraft();
    setState(() {});
  }

  Future<void> addActionGroup() async {
    final c = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('添加动作组'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(
            labelText: '动作组名称（如：杠铃卧推）',
            hintText: '代表一个动作及其平替的集合',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text.trim()),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (v == null || v.isEmpty) return;
    actions.add(
      TrainingAction(
        groupTitle: v,
        cards: [ExerciseCardData(name: v, isPrimary: true)],
      ),
    );
    saveDraft();
    setState(() {});
  }

  Future<void> _editGroupTitle(TrainingAction action) async {
    final c = TextEditingController(text: action.groupTitle);
    final v = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('修改动作组名称'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(
            labelText: '动作组名称',
            hintText: '如：胸部推举类',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (v == null || v.isEmpty) return;
    action.groupTitle = v;
    saveDraft();
    setState(() {});
  }

  Future<void> _editCardName(ExerciseCardData card) async {
    final c = TextEditingController(text: card.name);
    final v = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('修改动作名称'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(
            labelText: '动作名称',
            hintText: '如：杠铃卧推',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (v == null || v.isEmpty) return;
    card.name = v;
    saveDraft();
    setState(() {});
  }

  Future<void> addAlternative(TrainingAction action) async {
    final c = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('添加平替动作'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(hintText: '比如：哑铃卧推'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text.trim()),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (v == null || v.isEmpty) return;
    final source = action.cards.first.sets.first;
    action.cards.add(
      ExerciseCardData(
        name: v,
        sets: [
          TrainingSet(
            weightKg: source.weightKg,
            reps: source.reps,
            restSec: source.restSec,
          ),
        ],
      ),
    );
    saveDraft();
    setState(() {});
  }

  void addSet(ExerciseCardData card) {
    final last = card.sets.last;
    card.sets.add(
      TrainingSet(
        weightKg: last.weightKg,
        reps: last.reps,
        restSec: last.restSec,
      ),
    );
    saveDraft();
    setState(() {});
  }

  Future<void> generateAiPlan({String extraContext = ''}) async {
    if (selectedFolder.isEmpty) {
      toast('请先创建并选择一个文件夹');
      return;
    }
    final templateName = nameController.text.trim().isEmpty
        ? '未命名模板'
        : nameController.text.trim();
    var intent = intentController.text.trim();
    if (extraContext.isNotEmpty) intent = '$intent\n\n$extraContext';
    if (intent.isEmpty) {
      toast('请先填写意图');
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final generated = await _aiPlanService.generatePlan(
        folderName: selectedFolder,
        templateName: templateName,
        intent: intent,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      setState(() {
        actions = generated;
      });
      await saveDraft();
      toast('已生成计划，可继续手动微调');
    } catch (e, s) {
      debugPrint('[generateAiPlan] ERROR: $e');
      debugPrint('[generateAiPlan] STACK: $s');
      if (!mounted) return;
      Navigator.of(context).pop();
      toast('生成失败：$e');
    }
  }

  Future<void> saveTemplate() async {
    final name = nameController.text.trim();
    if (name.isEmpty) return toast('先给这个模板起个名字');
    if (selectedFolder.isEmpty) return toast('请先创建并选择一个文件夹');
    if (actions.isEmpty) return toast('先添加至少一个动作');

    final duplicated = widget.allTemplates.any(
      (t) =>
          t.folder == selectedFolder &&
          t.name == name &&
          t.id != widget.editing?.id,
    );
    if (duplicated) return toast('同一文件夹下模板名不能重复');

    final all = [...widget.allTemplates];
    final item = TrainingTemplate(
      id:
          widget.editing?.id ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      folder: selectedFolder,
      name: name,
      actions: actions,
      intent: intentController.text,
      aiSummary: aiSummary,
      updatedAt: DateTime.now(),
    );
    all.removeWhere((e) => e.id == item.id);
    all.add(item);

    await widget.store.saveFolders(folders);
    await widget.store.saveTemplates(all);
    if (widget.editing == null) await widget.store.clearDraft();
    if (!mounted) return;
    Navigator.pop(context);
  }

  void toast(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> editNumber({
    required String title,
    required String initial,
    required ValueChanged<String> onSave,
  }) async {
    final c = TextEditingController(text: initial);
    final v = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (v == null) return;
    onSave(v);
    saveDraft();
    setState(() {});
  }

  Widget compactSetRow(TrainingSet s, int index) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1F22),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text(
              '#${index + 1}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: _metricCell(
              label: 'kg',
              value: s.weightKg.toStringAsFixed(s.weightKg % 1 == 0 ? 0 : 1),
              onTap: () => editNumber(
                title: '设置重量(kg)',
                initial: s.weightKg.toString(),
                onSave: (v) {
                  final p = double.tryParse(v);
                  if (p != null && p >= 0) s.weightKg = p;
                },
              ),
              onInc: () => setState(() => s.weightKg += 5),
              onDec: () => setState(
                () => s.weightKg = (s.weightKg - 5).clamp(0, 9999).toDouble(),
              ),
            ),
          ),
          Expanded(
            child: _metricCell(
              label: '次',
              value: '${s.reps}',
              onTap: () => editNumber(
                title: '设置次数',
                initial: '${s.reps}',
                onSave: (v) {
                  final p = int.tryParse(v);
                  if (p != null && p > 0) s.reps = p;
                },
              ),
              onInc: () => setState(() => s.reps += 1),
              onDec: () => setState(() => s.reps = s.reps > 1 ? s.reps - 1 : 1),
            ),
          ),
          Expanded(
            child: _metricCell(
              label: '秒',
              value: '${s.restSec}',
              onTap: () => editNumber(
                title: '设置休息(秒)',
                initial: '${s.restSec}',
                onSave: (v) {
                  final p = int.tryParse(v);
                  if (p != null && p >= 0) s.restSec = p;
                },
              ),
              onInc: () => setState(() => s.restSec += 15),
              onDec: () => setState(
                () => s.restSec = s.restSec >= 15 ? s.restSec - 15 : 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricCell({
    required String label,
    required String value,
    required VoidCallback onTap,
    required VoidCallback onInc,
    required VoidCallback onDec,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        InkWell(
          onTap: () {
            onDec();
            saveDraft();
          },
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 2),
            child: Icon(Icons.remove_circle_outline, size: 18),
          ),
        ),
        const SizedBox(width: 2),
        Flexible(
          child: InkWell(
            onTap: onTap,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '$value$label',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
        const SizedBox(width: 2),
        InkWell(
          onTap: () {
            onInc();
            saveDraft();
          },
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 2),
            child: Icon(Icons.add_circle_outline, size: 18),
          ),
        ),
      ],
    );
  }

  Widget actionTrack(TrainingAction action, int actionIndex) {
    final controller = _trackControllers.putIfAbsent(
      actionIndex,
      () => PageController(viewportFraction: 0.84),
    );
    final currentPage = _trackPages[actionIndex] ?? 0.0;

    return SizedBox(
      height: 310,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (controller.hasClients) {
            _trackPages[actionIndex] =
                controller.page ?? controller.initialPage.toDouble();
            setState(() {});
          }
          return false;
        },
        child: PageView.builder(
          controller: controller,
          physics: const BouncingScrollPhysics(parent: PageScrollPhysics()),
          pageSnapping: true,
          padEnds: false,
          itemCount: action.cards.length,
          itemBuilder: (_, i) {
            final card = action.cards[i];
            final delta = (currentPage - i).abs();
            final scale = (1 - delta * 0.1).clamp(0.86, 1.0);
            final yOffset = (delta * 12).clamp(0, 14).toDouble();
            final dim = (delta * 0.18).clamp(0.0, 0.22);

            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Transform.translate(
                offset: Offset(0, yOffset),
                child: Transform.scale(
                  scale: scale,
                  child: Stack(
                    children: [
                      Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: card.isPrimary
                                ? const Color(0xFFB7FF00)
                                : const Color(0xFF2D3338),
                            width: 1.2,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(20),
                                      color: card.isPrimary
                                          ? const Color(
                                              0xFFB7FF00,
                                            ).withValues(alpha: 0.2)
                                          : const Color(0xFF2A2F34),
                                    ),
                                    child: Text(
                                      card.isPrimary ? '主动作' : '平替动作',
                                    ),
                                  ),
                                  const Spacer(),
                                  TextButton.icon(
                                    onPressed: () => _editActionDetails(card),
                                    icon: const Icon(Icons.notes, size: 16),
                                    label: const Text('详情'),
                                  ),
                                  if (!card.isPrimary)
                                    IconButton(
                                      onPressed: () {
                                        action.cards.removeAt(i);
                                        saveDraft();
                                        setState(() {});
                                      },
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              GestureDetector(
                                onTap: () => _editCardName(card),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        card.name,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    Icon(Icons.edit, size: 14,
                                        color: Colors.grey.shade600),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: ListView(
                                  children: [
                                    ...card.sets.asMap().entries.map(
                                      (e) => compactSetRow(e.value, e.key),
                                    ),
                                  ],
                                ),
                              ),
                              Row(
                                children: [
                                  FilledButton.tonalIcon(
                                    onPressed: () => addSet(card),
                                    icon: const Icon(Icons.add),
                                    label: const Text('加一组'),
                                  ),
                                  const SizedBox(width: 8),
                                  if (card.sets.length > 1)
                                    OutlinedButton.icon(
                                      onPressed: () {
                                        card.sets.removeLast();
                                        saveDraft();
                                        setState(() {});
                                      },
                                      icon: const Icon(Icons.remove),
                                      label: const Text('减一组'),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (dim > 0)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                color: Colors.black.withValues(alpha: dim),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: Text(widget.editing == null ? '创建训练模板' : '编辑训练模板')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: folders.contains(selectedFolder)
                        ? selectedFolder
                        : null,
                    decoration: const InputDecoration(labelText: '放到哪个文件夹'),
                    items: folders
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      selectedFolder = v;
                      saveDraft();
                      setState(() {});
                    },
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: addFolder,
                      icon: const Icon(Icons.add),
                      label: const Text('创建文件夹'),
                    ),
                  ),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: '模板名称'),
                    onChanged: (_) => saveDraft(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _showAiGenerateDialog,
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('智能生成计划'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '动作组',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          ...actions.asMap().entries.map((e) {
            final idx = e.key;
            final action = e.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => _editGroupTitle(action),
                              child: Row(
                                children: [
                                  const Icon(Icons.folder_outlined,
                                      size: 18, color: Colors.grey),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      action.groupTitle,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Icon(Icons.edit, size: 14,
                                      color: Colors.grey.shade600),
                                ],
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => addAlternative(action),
                            icon: const Icon(Icons.swap_horiz),
                            label: const Text('加平替'),
                          ),
                          IconButton(
                            onPressed: () {
                              actions.removeAt(idx);
                              saveDraft();
                              setState(() {});
                            },
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      actionTrack(action, idx),
                    ],
                  ),
                ),
              ),
            );
          }),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: addActionGroup,
              icon: const Icon(Icons.add),
              label: const Text('加动作组'),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: saveTemplate,
            icon: const Icon(Icons.save_outlined),
            label: const Text('保存这个模板'),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Future<void> _editActionDetails(ExerciseCardData card) async {
    final primaryController = TextEditingController(
      text: card.primaryMuscles.join('、'),
    );
    final secondaryController = TextEditingController(
      text: card.secondaryMuscles.join('、'),
    );
    final keyPointsController = TextEditingController(
      text: card.keyPoints.join('\n'),
    );
    final mistakesController = TextEditingController(
      text: card.commonMistakes.join('\n'),
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${card.name} 动作详情'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: primaryController,
                  decoration: const InputDecoration(labelText: '主肌群（用、分隔）'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: secondaryController,
                  decoration: const InputDecoration(labelText: '辅助肌群（用、分隔）'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: keyPointsController,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: '核心要领（每行一条，最多5条）',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: mistakesController,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: '常见错误（每行一条，最多5条）',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (saved == true) {
      card.primaryMuscles = primaryController.text
          .split(RegExp(r'[、,，]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      card.secondaryMuscles = secondaryController.text
          .split(RegExp(r'[、,，]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      card.keyPoints = keyPointsController.text
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .take(5)
          .toList();
      card.commonMistakes = mistakesController.text
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .take(5)
          .toList();
      await saveDraft();
      setState(() {});
    }

    primaryController.dispose();
    secondaryController.dispose();
    keyPointsController.dispose();
    mistakesController.dispose();
  }

  Future<void> _showAiGenerateDialog() async {
    final dialogIntentController = TextEditingController(
      text: intentController.text.isEmpty
          ? buildIntent()
          : intentController.text,
    );
    final selectedParts = <String>{};
    final selectedAbilities = <String>{};
    final selectedPreferences = <String>{};

    const bodyParts = [
      '胸',
      '背',
      '肩',
      '肱二头肌',
      '肱三头肌',
      '腹肌',
      '臀',
      '股四头肌',
      '腘绳肌',
      '小腿',
    ];
    const abilities = ['菜鸟', '小登', '中登', '老登'];
    const preferences = ['固定器械', '哑铃', '徒手'];

    Widget chipRow<T>(
      List<T> items,
      Set<T> selected,
      String Function(T) label, {
      required void Function(VoidCallback fn) setDialogState,
    }) {
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: items
            .map(
              (item) => FilterChip(
                label: Text(label(item)),
                selected: selected.contains(item),
                onSelected: (v) {
                  setDialogState(() {
                    if (v) {
                      selected.add(item);
                    } else {
                      selected.remove(item);
                    }
                  });
                },
              ),
            )
            .toList(),
      );
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('智能生成计划'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: dialogIntentController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: '告诉AI你想怎么练',
                    hintText: '可以补充时长、强度、旧伤限制等',
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {
                      dialogIntentController.clear();
                      setDialogState(() {});
                    },
                    icon: const Icon(Icons.cleaning_services_outlined),
                    label: const Text('一键清空意图'),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '训练部位',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: chipRow(
                    bodyParts,
                    selectedParts,
                    (p) => p,
                    setDialogState: setDialogState,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '健身经验',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                chipRow(
                  abilities,
                  selectedAbilities,
                  (a) => a,
                  setDialogState: setDialogState,
                ),
                const SizedBox(height: 12),
                const Text(
                  '训练偏好',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                chipRow(
                  preferences,
                  selectedPreferences,
                  (p) => p,
                  setDialogState: setDialogState,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('开始生成'),
            ),
          ],
        ),
      ),
    );
    if (result == true) {
      final extraParts = <String>[];
      if (selectedParts.isNotEmpty) {
        extraParts.add('训练部位：${selectedParts.join('、')}');
      }
      if (selectedAbilities.isNotEmpty) {
        extraParts.add('健身经验：${selectedAbilities.join('、')}');
      }
      if (selectedPreferences.isNotEmpty) {
        extraParts.add('训练偏好：${selectedPreferences.join('、')}');
      }
      intentController.text = dialogIntentController.text;
      await saveDraft();
      await generateAiPlan(extraContext: extraParts.join('\n'));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      dialogIntentController.dispose();
    });
  }
}
