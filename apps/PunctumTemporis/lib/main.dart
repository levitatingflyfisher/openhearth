import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openhearth_design/openhearth_design.dart'
    show OhReadError, OhUndoController, ohWebDataNoticeBuilder;
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart'
    show BackupVault, FileVaultStore, createPlatformVaultFileApi;
import 'package:shared_preferences/shared_preferences.dart';
import 'move/move_page.dart';
import 'theme/app_theme.dart';
import 'screens/calendar_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/storage_service.dart';
import 'services/face_service.dart';
import 'services/notification_service.dart';
import 'services/backup_service.dart';
import 'widgets/set_aside_notice.dart';
import 'widgets/undo_host.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The move page build (OH_MOVE_PAGE=true) is only the move screen: it
  // opens the journal read-only and returns here, before anything at the
  // normal start can write.
  if (ohMovePage) {
    final storage = StorageService(await SharedPreferences.getInstance());
    await storage.initialize(readOnly: true);
    runApp(MovePageApp(storage: storage));
    return;
  }

  // Lock to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialize storage
  final prefs = await SharedPreferences.getInstance();
  final storageService = StorageService(prefs);
  await storageService.initialize();
  // A montage file a build before the rulings listed for purge goes now.
  // A deleted clip or montage is never purged here; the calendar offers
  // its Undo again. Not while the journal is unread: Try again runs it.
  if (!storageService.readFailed) await storageService.keepOldPendingFiles();

  // Initialize face recognition (model may not be present)
  await FaceService.instance.initialize();
  debugPrint('Face recognition available: ${FaceService.instance.isAvailable}');
  if (!FaceService.instance.isAvailable) {
    debugPrint('Face init error: ${FaceService.instance.initError}');
  }

  // Initialize notifications
  await NotificationService.instance.initialize();
  if (storageService.getReminderEnabled()) {
    await NotificationService.instance.scheduleDailyReminder(
      storageService.getReminderTime(),
    );
  }

  // Initialize visual style
  AppTheme.visualStyle = storageService.getVisualStyle();

  runApp(OneSecondApp(storageService: storageService));
}

class OneSecondApp extends StatefulWidget {
  final StorageService storageService;

  /// Builds the [BackupService] the post-first-frame freshness hook uses.
  /// Injectable so tests can point the vault at an in-memory store; the
  /// default builds the same metadata_vault the Backup & Restore screen
  /// drives (app-documents/metadata_vault on Android, OPFS on web).
  final BackupService Function()? backupServiceFactory;

  /// Sets the daily reminder to match the stored setting after a restore.
  /// Injectable so tests need no notification plugin; the default is the
  /// same pair of calls Settings makes.
  final Future<void> Function(bool enabled, TimeOfDay time)? syncReminder;

  const OneSecondApp(
      {super.key,
      required this.storageService,
      this.backupServiceFactory,
      this.syncReminder});

  @override
  State<OneSecondApp> createState() => _OneSecondAppState();
}

class _OneSecondAppState extends State<OneSecondApp> {
  late int _themeMode;
  late Color _accentColor;
  late bool _showOnboarding;

  /// The app-wide Undo offer for deliberate deletes (see UndoHost).
  final _undo = OhUndoController();

  /// The notice for a journal file set aside, until the family dismisses
  /// it. It stays recorded until then, so an app closed at once tells
  /// again at the next start.
  String? _setAsideNotice;

  /// Dismiss: only now is the notice cleared from storage.
  void _dismissSetAsideNotice() {
    final shown = _setAsideNotice;
    setState(() => _setAsideNotice = null);
    if (shown == null) return;
    unawaited(widget.storageService
        .dismissSetAsideNotice(shown)
        .catchError((Object e) {
      // Not cleared: the notice shows once more at the next start.
      debugPrint('Set-aside notice not cleared: ${e.runtimeType}');
    }));
  }

  /// Try again on the journal's read error. A read that works again may
  /// also have set a file aside, which the family is then told.
  Future<void> _retryRead() async {
    final storage = widget.storageService;
    try {
      await storage.retryRead();
    } finally {
      if (mounted) {
        setState(() {
          _setAsideNotice = storage.setAsideNotice ?? _setAsideNotice;
        });
      }
    }
  }

  @override
  void dispose() {
    widget.storageService.reloads.removeListener(_forgetCachedData);
    _undo.dispose();
    super.dispose();
  }

  /// The app's one reset after a restore or a rollback
  /// (StorageService.reload). Each step is a copy of stored data, or a
  /// write waiting, that lives as long as the app. Settings re-reads its
  /// own copy; the calendar and the day view redraw on `changes`. A new
  /// long-lived copy belongs here, or the guard in
  /// test/services/restore_reset_guard_test.dart fails.
  ///
  /// The onboarding flag is read once at start on purpose: a restore never
  /// sends the household back to onboarding.
  void _forgetCachedData() {
    final storage = widget.storageService;
    // A pending Undo would put an old clip or montage into the restored
    // journal. Cancelled, neither undone nor committed: the item stays in
    // Recently deleted, as after a dismissed bar, whatever the offer carries.
    _undo.cancel();
    // The theme, the accent and the visual style came from settings the
    // restore may have replaced.
    AppTheme.visualStyle = storage.getVisualStyle();
    setState(() {
      _themeMode = storage.getThemeMode();
      _accentColor = Color(storage.getAccentColor());
    });
    // The reminder is set in the phone, not in memory, and must match the
    // restored setting.
    final sync = widget.syncReminder ?? _syncReminderWithPhone;
    unawaited(Future(
            () => sync(storage.getReminderEnabled(), storage.getReminderTime()))
        .catchError((Object e) {
      // A reminder the phone refuses must not fail a finished restore.
      debugPrint('Reminder not updated after restore: $e');
    }));
  }

  static Future<void> _syncReminderWithPhone(bool enabled, TimeOfDay time) =>
      enabled
          ? NotificationService.instance.scheduleDailyReminder(time)
          : NotificationService.instance.cancelReminder();

  @override
  void initState() {
    super.initState();
    _themeMode = widget.storageService.getThemeMode();
    _accentColor = Color(widget.storageService.getAccentColor());
    _showOnboarding = !widget.storageService.getOnboardingComplete();
    _setAsideNotice = widget.storageService.setAsideNotice;
    widget.storageService.reloads.addListener(_forgetCachedData);

    // BACKUP_RETENTION_SPEC trigger 3, post-first-frame: when the newest
    // metadata snapshot is >7 days old (or none exists), quietly vault a
    // fresh one. Best-effort by contract — maybeFreshnessSnapshot never
    // throws, so a missing vault dir or full disk can't reach the UI.
    // No nag, no badge — it just happens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final service = widget.backupServiceFactory?.call() ??
          BackupService(
            widget.storageService,
            vault: BackupVault(
              FileVaultStore(
                  createPlatformVaultFileApi(dirName: 'metadata_vault')),
              appId: 'punctum',
              extension: 'json',
            ),
          );
      unawaited(service.maybeFreshnessSnapshot());
    });
  }

  void updateTheme(int mode, Color accent) {
    setState(() {
      _themeMode = mode;
      _accentColor = accent;
    });
    widget.storageService.setThemeMode(mode);
    widget.storageService.setAccentColor(accent.toARGB32());
  }

  void _onVisualStyleChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Punctum Temporis',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.buildTheme(Brightness.light, _accentColor),
      darkTheme: AppTheme.buildTheme(Brightness.dark, _accentColor),
      themeMode: StorageService.themePreferenceFromInt(_themeMode).themeMode,
      // Width is capped per screen (OhPage around each body), so bars and
      // backgrounds span a tablet or browser window. On the web the data
      // lives in this browser: the fleet notice sits above every screen and
      // its Undo bar.
      builder: (context, child) => ohWebDataNoticeBuilder(
        context,
        withSetAsideNotice(
          context,
          UndoHost(
            controller: _undo,
            child: child ?? const SizedBox.shrink(),
          ),
          message: _setAsideNotice,
          onDismiss: _dismissSetAsideNotice,
        ),
      ),
      // A journal that could not be read is said, with Try again. It is
      // never drawn as an empty calendar: the file is still there.
      home: widget.storageService.readFailed
          ? Scaffold(
              body: SafeArea(
                child: OhReadError(
                  title: 'Couldn’t read your journal',
                  error: widget.storageService.readError,
                  stackTrace: widget.storageService.readErrorStack,
                  onRetry: _retryRead,
                ),
              ),
            )
          : _showOnboarding
          ? OnboardingScreen(
              storageService: widget.storageService,
              onComplete: () {
                setState(() => _showOnboarding = false);
              },
            )
          : CalendarScreen(
              storageService: widget.storageService,
              onThemeChanged: updateTheme,
              onVisualStyleChanged: _onVisualStyleChanged,
            ),
    );
  }
}
