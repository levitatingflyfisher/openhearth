// Deleting a saved montage (fleet delete ruling): a deliberate act, so no
// "DELETE COMPILATION?" dialog; the row goes at once and the app-wide bar
// offers an Undo that never times out. Undo brings the row back. The
// montage then stays pending, row and file, across a dismissed bar and a
// kill, until its owner restores it or confirms "Delete for good".
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_second_a_day/models/clip.dart';
import 'package:one_second_a_day/screens/compilation_screen.dart';
import 'package:one_second_a_day/services/storage_service.dart';
import 'package:one_second_a_day/theme/app_theme.dart';
import 'package:one_second_a_day/widgets/undo_host.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.base);
  final String base;
  @override
  Future<String?> getApplicationDocumentsPath() async => base;
  @override
  Future<String?> getApplicationSupportPath() async => base;
  @override
  Future<String?> getTemporaryPath() async => '$base/tmp';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late StorageService svc;

  setUp(() {
    AppTheme.visualStyle = 'hearth';
    tmp = Directory.systemTemp.createTempSync('pt_montage_delete_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    SharedPreferences.setMockInitialValues({'crt_effects': false});
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  testWidgets('Delete does not ask; Undo brings the montage back',
      (tester) async {
    final file = File('${tmp.path}/compiled/m1.mp4');
    await tester.runAsync(() async {
      svc = StorageService(await SharedPreferences.getInstance());
      await svc.initialize();
      await file.parent.create(recursive: true);
      await file.writeAsBytes([1, 2, 3]);
      await svc.addCompilation(Compilation(
        id: 'm1',
        title: 'Jul 1 - Jul 31, 2026',
        filePath: file.path,
        clipIds: const [],
        createdAt: DateTime(2026, 8, 1),
      ));
    });
    final undo = OhUndoController();
    addTearDown(undo.dispose);
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.buildTheme(Brightness.light, Colors.green),
      builder: (context, child) => UndoHost(controller: undo, child: child!),
      home: CompilationScreen(storageService: svc),
    ));
    await settle(tester);

    await tester.ensureVisible(find.byTooltip('Delete montage'));
    await tester.tap(find.byTooltip('Delete montage'));
    await settle(tester);

    expect(find.byType(AlertDialog), findsNothing);
    expect(svc.compilations, isEmpty);
    expect(file.existsSync(), isTrue, reason: 'kept for the Undo');
    expect(find.text('Deleted the montage “Jul 1 - Jul 31, 2026”'),
        findsOneWidget);

    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(svc.compilations.map((c) => c.id), ['m1']);
    expect(find.byTooltip('Delete montage'), findsOneWidget);
  });

  // Owner ruling (board-0138): a montage gets the same protection as a
  // clip. Before, a kill with the Undo bar on screen destroyed the
  // montage's file at the next start, and a dismissed bar destroyed it
  // at once.
  Future<(SharedPreferences, File)> deleteOnScreen(WidgetTester tester) async {
    final file = File('${tmp.path}/compiled/m1.mp4');
    late SharedPreferences prefs;
    await tester.runAsync(() async {
      prefs = await SharedPreferences.getInstance();
      svc = StorageService(prefs);
      await svc.initialize();
      await file.parent.create(recursive: true);
      await file.writeAsBytes([1, 2, 3]);
      await svc.addCompilation(Compilation(
        id: 'm1',
        title: 'Jul 1 - Jul 31, 2026',
        filePath: file.path,
        clipIds: const [],
        createdAt: DateTime(2026, 8, 1),
      ));
    });
    final undo = OhUndoController();
    addTearDown(undo.dispose);
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.buildTheme(Brightness.light, Colors.green),
      builder: (context, child) => UndoHost(controller: undo, child: child!),
      home: CompilationScreen(storageService: svc),
    ));
    await settle(tester);

    await tester.ensureVisible(find.byTooltip('Delete montage'));
    await tester.tap(find.byTooltip('Delete montage'));
    await settle(tester);
    expect(find.text('Undo'), findsOneWidget);
    return (prefs, file);
  }

  testWidgets('a montage deleted with Undo on screen survives a kill',
      (tester) async {
    final (prefs, file) = await deleteOnScreen(tester);

    // The kill: the process goes with the bar on screen, and the next
    // start builds a new storage over the same disk, as main() does.
    late StorageService next;
    await tester.runAsync(() async {
      next = StorageService(prefs);
      await next.initialize();
      await next.keepOldPendingFiles();
    });

    expect(file.existsSync(), isTrue);
    expect(next.compilations, isEmpty);
    expect(next.pendingCompilationRemovals.map((r) => r.compilation.id),
        ['m1']);

    // Its Undo still works after the kill.
    await tester.runAsync(() =>
        next.restoreCompilation(next.pendingCompilationRemovals.single));
    expect(next.compilations.map((c) => c.id), ['m1']);
    expect(next.pendingCompilationRemovals, isEmpty);
  });

  testWidgets('dismissing the Undo bar keeps the montage', (tester) async {
    final (_, file) = await deleteOnScreen(tester);

    await tester.tap(find.byTooltip('Dismiss'));
    await settle(tester);

    expect(find.text('Undo'), findsNothing);
    expect(file.existsSync(), isTrue);
    expect(svc.pendingCompilationRemovals.map((r) => r.compilation.id),
        ['m1']);
  });
}
