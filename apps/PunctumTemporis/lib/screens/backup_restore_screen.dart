import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart'
    show OpenHearthMnemonic, SecureKeyStore;
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart'
    show
        BackupVault,
        FileVaultStore,
        PhraseEntryDialog,
        PhraseReEntryDialog,
        SeedPhraseModal,
        createPlatformVaultFileApi;
import '../platform/file_storage.dart';
import '../theme/app_theme.dart';
import '../services/storage_service.dart';
import '../services/backup_key.dart';
import '../services/backup_service.dart';
import '../services/backup_stream_cipher.dart';
import '../widgets/crt_effects.dart';
import '../widgets/metadata_snapshots_section.dart';
import '../widgets/error_snack_bar.dart';
import 'package:openhearth_design/openhearth_design.dart'
    show ohFriendlyErrorMessage, OhPage;

class BackupRestoreScreen extends StatefulWidget {
  final StorageService storageService;

  /// Where this phone keeps the recovery words. Tests pass a fake; the app
  /// uses the keychain slot named for PunctumTemporis.
  final SecureKeyStore? keyStore;

  /// Only the backup: no restore and no previous snapshots. The move page
  /// at the old web address uses it, because it must write nothing there.
  final bool exportOnly;

  const BackupRestoreScreen({
    super.key,
    required this.storageService,
    this.keyStore,
    this.exportOnly = false,
  });

  /// One true sentence about the file, shown before the button (lens audit
  /// writing-is-designing-03). Each claim matches what createBackup packs:
  /// clips and thumbnails; metadata.json with dates, tags, place names and
  /// coordinates and the names face recognition wrote; the named face crops;
  /// montages when included. The file is sealed with the recovery words
  /// (BackupStreamCipher), so the words are what opens it.
  static const backupFileNotice =
      'The backup is locked with your 12 recovery words. With the file and '
      'the words, anyone can watch your clips and see their dates, places, '
      'tags, and the names and face pictures of people you’ve named. '
      'Without the words nobody can open it, you included, so keep them '
      'on paper.';

  /// The success line after a backup: the count comes from reading the
  /// written file back, and "locked" from opening every chunk again.
  static String backedUpMessage(int clipFiles) =>
      'Backed up, locked and verified: $clipFiles clip files';

  /// Asks for the words when a locked backup is picked on a phone without
  /// any (a new phone, or one that never made a backup).
  static const lockedBody =
      'This backup is locked. Type the 12 recovery words it was made with.';

  /// Shown when words do not open a backup. The cipher cannot tell wrong
  /// words from a changed or cut-off file, so the line names both.
  static const otherWordsBody =
      'These words do not open this backup, or the file was changed or cut '
      'short. Type the 12 words it was made with, or cancel and pick '
      'another copy.';

  /// Shown when what was typed is not 12 valid recovery words.
  static const notWordsBody =
      'Those are not 12 recovery words. Check the paper copy and type them '
      'again.';

  /// Android's own backup to Google is on for this app (allowBackup is left
  /// at its default). That copy is Android's, not this file, so this line
  /// does not call it private or encrypted.
  static const googleBackupNotice =
      'Android may also back up this app’s data to Google, if the phone’s '
      'owner allows it in Android settings.';

  /// Android skips an app whose data is large (25 MB). createBackup packs
  /// every clip with a readable file, and montages while the switch is on.
  static const largeBackupNotice =
      'Android skips its own backup of an app whose data is large, so '
      'photos and video may not be in it. The backup here holds your clips, '
      'and your montage videos if the switch above is on.';

  static const cancelRestoreWarning =
      'Restore may be partial. Corrupt data is unlikely but possible. Continue?';

  // Exactly true, calmly said: a restore only rewrites the journal index
  // and settings. Clip FILES are never deleted (see BackupService.vault —
  // UUID names don't collide, old metadata simply re-adopts them), so
  // clips missing from the backup leave the app's view but stay on disk.
  // Copy claiming "ALL data" is replaced would be a lie in both
  // directions.
  static const replaceAllTitle = 'REPLACE FROM BACKUP?';

  static const replaceAllWarning =
      'Your journal index and settings will be replaced with what is in '
      'the backup. Clips that are not in the backup will no longer appear '
      'in the app, but their video files stay on your device. A snapshot '
      'of your current journal index is saved to Previous snapshots '
      'first, so you can roll back.';

  // Legacy v1 archives carry no settings.json, so a replace-mode restore
  // of one leaves current settings exactly as they are. Promising
  // "settings will be replaced" there would be a lie in the other
  // direction.
  static const replaceAllWarningNoSettings =
      'Your journal index will be replaced with what is in the backup. '
      'This older backup contains no settings, so your current settings '
      'stay as they are. Clips that are not in the backup will no longer '
      'appear in the app, but their video files stay on your device. A '
      'snapshot of your current journal index is saved to Previous '
      'snapshots first, so you can roll back.';

  static const replaceAllConfirmLabel = 'YES, REPLACE';

  /// The second confirmation shown before a replace-mode restore. Pops
  /// `true` to proceed, `false` to cancel. [archiveHasSettings] picks the
  /// honest copy: v2 archives replace settings, v1 archives can't.
  @visibleForTesting
  static AlertDialog buildReplaceConfirmDialog(BuildContext ctx,
      {bool archiveHasSettings = true}) {
    return AlertDialog(
      backgroundColor: Theme.of(ctx).colorScheme.surface,
      title: Text(
        replaceAllTitle,
        style: AppTheme.displayFont(fontSize: 16),
      ),
      content: Text(
        archiveHasSettings ? replaceAllWarning : replaceAllWarningNoSettings,
        style: AppTheme.monoFont(fontSize: 13),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('CANCEL', style: AppTheme.monoFont(fontSize: 12)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            replaceAllConfirmLabel,
            style: AppTheme.monoFont(fontSize: 12, color: Colors.red),
          ),
        ),
      ],
    );
  }

  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen> {
  late final BackupService _backupService;
  late final SecureKeyStore _keyStore =
      widget.keyStore ?? BackupKey.defaultStore();

  /// The key from the words on this phone, or null when it has none yet.
  Future<FileKeyDeriver?> _storedWords() async {
    final phrase = await _keyStore.readMnemonic();
    return phrase == null ? null : BackupKey.fromPhrase(phrase);
  }

  /// The words for a new backup. A phone without words sets them up first,
  /// with the shared sheets every fleet app uses: show the 12 words, then
  /// have them typed back from paper. Returns null when the owner stops.
  Future<FileKeyDeriver?> _wordsForBackup() async {
    final stored = await _storedWords();
    if (stored != null) return stored;
    if (!mounted) return null;

    final phrase = OpenHearthMnemonic.generate();
    final wroteDown = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SeedPhraseModal(
        phrase: phrase,
        onAcknowledged: () {},
        declineLabel: 'Not now',
      ),
    );
    if (wroteDown != true || !mounted) return null;
    final typed = await PhraseReEntryDialog.show(
      context,
      expectedPhrase: phrase,
      onShowWords: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => SeedPhraseModal(
          phrase: phrase,
          onAcknowledged: () {},
          acknowledgeLabel: 'Done',
        ),
      ),
    );
    if (typed == null) return null;
    await _keyStore.writeMnemonic(phrase);
    await _keyStore.writeSeedAcknowledged();
    return BackupKey.fromPhrase(phrase);
  }

  /// Opens a picked backup, asking for the words when the file is locked
  /// and this phone's words (if any) do not open it. Words typed here and
  /// proven by opening the file are kept when the phone had none, as on a
  /// new phone. Returns null when the owner stops.
  Future<PreparedBackup?> _prepare({String? path, Uint8List? bytes}) async {
    var words = await _storedWords();
    String? typed;
    var body = BackupRestoreScreen.lockedBody;
    while (true) {
      try {
        final prepared = await _backupService.prepareRestore(
            path: path, bytes: bytes, decryptWith: words);
        if (typed != null && await _keyStore.readMnemonic() == null) {
          await _keyStore.writeMnemonic(BackupKey.normalize(typed));
          await _keyStore.writeSeedAcknowledged();
        }
        return prepared;
      } on BackupNeedsWordsException {
        // No words on this phone: ask for them.
      } on BackupStreamException {
        // Wrong words and a damaged file look the same to the cipher.
        body = BackupRestoreScreen.otherWordsBody;
      }
      if (!mounted) return null;
      typed = await PhraseEntryDialog.show(context,
          title: 'Enter the recovery words', body: body, confirmLabel: 'Open');
      if (typed == null || !mounted) return null;
      if (!BackupKey.isValidPhrase(typed)) {
        body = BackupRestoreScreen.notWordsBody;
        words = null;
        continue;
      }
      words = await BackupKey.fromPhrase(typed);
    }
  }

  bool _isBackingUp = false;
  bool _isRestoring = false;
  double _progress = 0;
  String? _statusMessage;
  int? _estimatedSize;

  @override
  void initState() {
    super.initState();
    // The metadata snapshot vault (BACKUP_RETENTION_SPEC in PT's plaintext
    // idiom): app-documents/metadata_vault on Android, OPFS on web.
    _backupService = BackupService(
      widget.storageService,
      vault: BackupVault(
        FileVaultStore(createPlatformVaultFileApi(dirName: 'metadata_vault')),
        appId: 'punctum',
        extension: 'json',
      ),
    );
    _loadEstimatedSize();
  }

  Future<void> _loadEstimatedSize() async {
    final size = await _backupService.getBackupSize(
        includeMontages: widget.storageService.getIncludeMontagesInBackup());
    if (mounted) {
      setState(() => _estimatedSize = size);
    }
  }

  Future<void> _restoreSnapshot(String id) async {
    setState(() {
      _isRestoring = true;
      _progress = 0;
      _statusMessage = 'Restoring snapshot...';
    });
    try {
      await _backupService.restoreMetadataSnapshot(id, (progress) {
        if (mounted) setState(() => _progress = progress);
      });
      if (mounted) {
        setState(() {
          _isRestoring = false;
          _statusMessage = null;
        });
        _showSuccess('Snapshot restored');
        _loadEstimatedSize();
      }
    } on PreRestoreSnapshotException {
      if (mounted) {
        setState(() {
          _isRestoring = false;
          _statusMessage = null;
        });
        _showError("Couldn’t save a safety snapshot first, so nothing was "
            'changed. Free up some space and try again.');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRestoring = false;
          _statusMessage = null;
        });
        debugPrint('Snapshot restore failed: $e');
        _showError(
            "The snapshot wasn’t restored. ${ohFriendlyErrorMessage(e)}");
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> _createBackup() async {
    // The words first: a phone without them sets them up before any file
    // exists, and stopping there makes no backup at all.
    final words = await _wordsForBackup();
    if (words == null || !mounted) return;

    // On native: write to app-private storage first (no permission needed),
    // then share via system sheet. Direct external writes fail on Android 11+
    // scoped storage even after the user grants SAF folder access.
    String outputPath = '';
    if (!kIsWeb) {
      final appDir = await FileStorage.appDocDir();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      outputPath = '$appDir/onesecond_backup_$timestamp.'
          '${BackupService.encryptedExtension}';
    }

    setState(() {
      _isBackingUp = true;
      _progress = 0;
      _statusMessage = 'Creating backup...';
    });

    try {
      final info = await _backupService.createBackup(
        outputPath,
        includeMontages: widget.storageService.getIncludeMontagesInBackup(),
        encryptWith: words,
        (progress) {
          if (mounted) {
            setState(() {
              _progress = progress;
              if (progress < 0.5) {
                _statusMessage = 'Packing files...';
              } else if (progress < 0.75) {
                _statusMessage = 'Locking backup...';
              } else {
                _statusMessage = 'Checking backup...';
              }
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _isBackingUp = false;
          _statusMessage = null;
        });
        // The count comes from reading the written file back, and every
        // chunk was opened again: a verification receipt, not an assumption.
        final done = BackupRestoreScreen.backedUpMessage(info.clipFileCount);
        if (kIsWeb) {
          _showSuccess('$done downloaded');
        } else {
          final fileName = outputPath.split('/').last;
          try {
            final completed = await _showBackupOptions(outputPath, fileName);
            if (mounted && completed) _showSuccess(done);
          } finally {
            await FileStorage.deleteFile(outputPath).catchError((_) {});
          }
        }
      }
    } catch (e) {
      if (!kIsWeb && outputPath.isNotEmpty) {
        await FileStorage.deleteFile(outputPath).catchError((_) {});
      }
      if (mounted) {
        setState(() {
          _isBackingUp = false;
          _statusMessage = null;
        });
        debugPrint('Backup failed: $e');
        _showError("The backup wasn’t made. ${ohFriendlyErrorMessage(e)}");
      }
    }
  }

  Future<void> _restoreBackup() async {
    if (_isRestoring || _isBackingUp) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      // Locked backups, and the plain ZIPs made before them.
      allowedExtensions: ['zip', BackupService.encryptedExtension],
      withData: kIsWeb, // fetch bytes directly on web
    );
    if (result == null) return;

    // Android hands over a path and the file is read in pieces from it;
    // the web hands over bytes.
    final path = kIsWeb ? null : result.files.single.path;
    final bytes = kIsWeb ? result.files.single.bytes : null;
    if (path == null && bytes == null) {
      _showError('Could not read backup file');
      return;
    }

    // Lock restore state before decryption begins so double-taps cannot
    // race on restore_work.zip and back navigation is guarded.
    setState(() {
      _isRestoring = true;
      _progress = 0;
      _statusMessage = 'Checking backup...';
    });

    PreparedBackup? prepared;
    try {
      prepared = await _prepare(path: path, bytes: bytes);
      if (prepared == null) {
        return;
      }
      final info = prepared.info;

      if (!mounted) return;

      // Show confirmation dialog
      final restoreMode = await showDialog<String>(
        context: context,
        builder: (context) {
          final theme = Theme.of(context);
          return AlertDialog(
            backgroundColor: theme.colorScheme.surface,
            title: Text(
              'RESTORE BACKUP',
              style: AppTheme.displayFont(fontSize: 18),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${info.clipCount} clips',
                  style: AppTheme.monoFont(fontSize: 14),
                ),
                if (info.dateRange != null)
                  Text(
                    info.dateRange!,
                    style: AppTheme.monoFont(
                      fontSize: 12,
                      color: AppTheme.dimInk(theme),
                    ),
                  ),
                Text(
                  _formatBytes(info.sizeBytes),
                  style: AppTheme.monoFont(
                    fontSize: 12,
                    color: AppTheme.dimInk(theme),
                  ),
                ),
                if (info.faceCount > 0)
                  Text(
                    '${info.faceCount} face references',
                    style: AppTheme.monoFont(
                      fontSize: 12,
                      color: AppTheme.dimInk(theme),
                    ),
                  ),
                const SizedBox(height: 16),
                Text(
                  'How should this be restored?',
                  style: AppTheme.monoFont(fontSize: 14),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: Text('CANCEL', style: AppTheme.monoFont(fontSize: 12)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, 'merge'),
                child: Text(
                  'MERGE',
                  style: AppTheme.monoFont(
                    fontSize: 12,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, 'replace'),
                child: Text(
                  'REPLACE ALL',
                  style: AppTheme.monoFont(fontSize: 12, color: Colors.red),
                ),
              ),
            ],
          );
        },
      );

      if (restoreMode == null) {
        setState(() => _statusMessage = null);
        return;
      }

      // Second confirmation for the destructive REPLACE ALL path
      if (restoreMode == 'replace') {
        if (!mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => BackupRestoreScreen.buildReplaceConfirmDialog(ctx,
              archiveHasSettings: info.hasSettings),
        );
        if (confirmed != true) {
          if (mounted) setState(() => _statusMessage = null);
          return;
        }
      }

      setState(() {
        _isRestoring = true;
        _progress = 0;
        _statusMessage = 'Restoring...';
      });

      await _backupService.restorePrepared(
        prepared,
        (progress) {
          if (mounted) {
            setState(() {
              _progress = progress;
              if (progress < 0.8) {
                _statusMessage = 'Extracting files...';
              } else if (progress < 0.95) {
                _statusMessage = 'Updating metadata...';
              } else {
                _statusMessage = 'Reloading...';
              }
            });
          }
        },
        replace: restoreMode == 'replace',
      );

      if (mounted) {
        setState(() {
          _isRestoring = false;
          _statusMessage = null;
        });
        _showSuccess('Backup restored successfully');
        _loadEstimatedSize();
      }
    } on PreRestoreSnapshotException {
      // Fail-closed: the mandatory safety snapshot couldn't be saved, so
      // the restore never started — say exactly that, calmly.
      if (mounted) {
        setState(() {
          _isRestoring = false;
          _statusMessage = null;
        });
        _showError("Couldn’t save a safety snapshot of your current "
            'journal, so the restore was not started. Free up some space '
            'and try again.');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRestoring = false;
          _statusMessage = null;
        });
        debugPrint('Restore failed: $e');
        _showError("The restore didn’t finish. ${ohFriendlyErrorMessage(e)}");
      }
    } finally {
      // A cancelled choice, a refusal or an error: the decrypted copy, if
      // any, never stays beside the app's data, and restore lock always clears.
      if (prepared != null) await _backupService.discardPrepared(prepared);
      if (mounted && (_isRestoring || _statusMessage != null)) {
        setState(() {
          _isRestoring = false;
          _statusMessage = null;
        });
      }
    }
  }

  Future<void> _cancelRestore() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        title: Text('CANCEL RESTORE?', style: AppTheme.pixelFont(fontSize: 12)),
        content: Text(
          BackupRestoreScreen.cancelRestoreWarning,
          style: AppTheme.monoFont(fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('KEEP WAITING', style: AppTheme.monoFont(fontSize: 12)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'LEAVE ANYWAY',
              style: AppTheme.monoFont(
                fontSize: 12,
                color: Theme.of(ctx).colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) Navigator.pop(context);
  }

  Future<bool> _showBackupOptions(String outputPath, String fileName) async {
    if (!mounted) return false;
    final theme = Theme.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'BACKUP CREATED',
                style: AppTheme.pixelFont(
                  fontSize: 11,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                fileName,
                style: AppTheme.monoFont(
                  fontSize: 12,
                  color: AppTheme.dimInk(theme),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading:
                    Icon(Icons.folder_open, color: theme.colorScheme.primary),
                title: Text('Save to Device',
                    style: AppTheme.displayFont(fontSize: 15)),
                subtitle: Text('Choose a folder on your device',
                    style: AppTheme.monoFont(fontSize: 12)),
                onTap: () => Navigator.pop(ctx, 'save'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.share, color: theme.colorScheme.primary),
                title: Text('Share', style: AppTheme.displayFont(fontSize: 15)),
                subtitle: Text('Send via app, cloud, or email',
                    style: AppTheme.monoFont(fontSize: 12)),
                onTap: () => Navigator.pop(ctx, 'share'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return false;
    if (action == 'save') {
      final bytes = await FileStorage.readBytes(outputPath);
      if (bytes == null) {
        _showError('Could not read backup file');
        return false;
      }
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Backup',
        fileName: fileName,
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: [BackupService.encryptedExtension],
      );
      if (mounted && savedPath != null) {
        return true;
      }
      return false;
    } else if (action == 'share') {
      final res = await SharePlus.instance.share(ShareParams(
        files: [XFile(outputPath)],
        subject: 'Punctum Temporis Backup',
      ));
      return res.status != ShareResultStatus.dismissed;
    }
    return false;
  }

  Future<void> _shareCompilation(String filePath) async {
    if (!await FileStorage.exists(filePath)) {
      _showError('File not found');
      return;
    }
    if (kIsWeb) {
      final bytes = await FileStorage.readBytes(filePath);
      if (bytes == null) {
        _showError('File not found');
        return;
      }
      final filename = filePath.split('/').last;
      await FileStorage.downloadFile(bytes, filename, 'video/mp4');
    } else {
      await SharePlus.instance.share(ShareParams(files: [XFile(filePath)]));
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    showErrorSnackBar(context, message);
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compilations = widget.storageService.compilations;

    return PopScope(
      canPop: !_isBackingUp && !_isRestoring,
      // Back during a restore asks through the screen's own CANCEL RESTORE?
      // dialog. A backup is short and ends in the share step, so back waits
      // for it, and says what it is waiting for.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_isRestoring) {
          _cancelRestore();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Finishing the backup. One moment.')),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'BACKUP & RESTORE',
            style: AppTheme.pixelFont(fontSize: 12),
          ),
        ),
        body: OhPage(
          padding: EdgeInsets.zero,
          safeArea: false,
          child: CrtOverlay(
            enabled: widget.storageService.getCrtEffects(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // BACKUP section
                _buildSectionHeader('BACKUP'),

                RetroCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.backup, color: theme.colorScheme.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Create Backup',
                                  style: AppTheme.displayFont(
                                    fontSize: 16,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                Text(
                                  kIsWeb
                                      ? 'Download ZIP of all clips and metadata'
                                      : 'Save all clips, thumbnails, and metadata',
                                  style: AppTheme.monoFont(
                                    fontSize: 11,
                                    color: AppTheme.dimInk(theme),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Text(
                            'Estimated size: ${_estimatedSize != null ? _formatBytes(_estimatedSize!) : "calculating..."}',
                            style: AppTheme.monoFont(
                              fontSize: 12,
                              color: AppTheme.dimInk(theme),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${widget.storageService.totalClips} clips',
                            style: AppTheme.monoFont(
                              fontSize: 12,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Switch(
                            value: widget.storageService
                                .getIncludeMontagesInBackup(),
                            onChanged: (v) async {
                              await widget.storageService
                                  .setIncludeMontagesInBackup(v);
                              if (mounted) setState(() {});
                              _loadEstimatedSize();
                            },
                            activeThumbColor: theme.colorScheme.primary,
                          ),
                          Expanded(
                            child: Text(
                              'Include montage videos',
                              style: AppTheme.monoFont(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        BackupRestoreScreen.backupFileNotice,
                        style: AppTheme.monoFont(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        BackupRestoreScreen.googleBackupNotice,
                        style: AppTheme.monoFont(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        BackupRestoreScreen.largeBackupNotice,
                        style: AppTheme.monoFont(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_isBackingUp) ...[
                        RetroProgressBar(value: _progress, height: 16),
                        const SizedBox(height: 8),
                        Text(
                          '${_statusMessage ?? ""} ${(_progress * 100).toInt()}%',
                          style: AppTheme.monoFont(fontSize: 12),
                        ),
                      ] else
                        Center(
                          child: RetroButton(
                            onPressed: _createBackup,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.save_alt, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  kIsWeb ? 'DOWNLOAD BACKUP' : 'CREATE BACKUP',
                                  style: AppTheme.monoFont(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                if (!widget.exportOnly) ...[
                  // RESTORE section
                  _buildSectionHeader('RESTORE'),

                  RetroCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.restore, color: theme.colorScheme.primary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Restore from Backup',
                                    style: AppTheme.displayFont(
                                      fontSize: 16,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                  Text(
                                    'Load clips from a backup ZIP',
                                    style: AppTheme.monoFont(
                                      fontSize: 11,
                                      color: AppTheme.dimInk(theme),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_isRestoring) ...[
                          RetroProgressBar(value: _progress, height: 16),
                          const SizedBox(height: 8),
                          Text(
                            '${_statusMessage ?? ""} ${(_progress * 100).toInt()}%',
                            style: AppTheme.monoFont(fontSize: 12),
                          ),
                          const SizedBox(height: 12),
                          Center(
                            child: TextButton(
                              onPressed: _cancelRestore,
                              child: Text(
                                'CANCEL',
                                style: AppTheme.monoFont(
                                  fontSize: 11,
                                  color: AppTheme.dimInk(Theme.of(context)),
                                ),
                              ),
                            ),
                          ),
                        ] else
                          Center(
                            child: RetroButton(
                              onPressed: _restoreBackup,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.upload_file, size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    'SELECT BACKUP FILE',
                                    style: AppTheme.monoFont(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // PREVIOUS SNAPSHOTS — the retention spec's vault, PT-style.
                  _buildSectionHeader('PREVIOUS SNAPSHOTS'),
                  MetadataSnapshotsSection(
                    vault: _backupService.vault,
                    onRestoreSnapshot: _restoreSnapshot,
                  ),

                ],
                const SizedBox(height: 24),

                // SHARE / DOWNLOAD section
                _buildSectionHeader(
                    kIsWeb ? 'DOWNLOAD COMPILATIONS' : 'SHARE COMPILATIONS'),

                if (compilations.isEmpty)
                  Text(
                    'No compilations yet',
                    style: AppTheme.monoFont(
                      fontSize: 12,
                      color: AppTheme.dimInk(theme),
                    ),
                  )
                else
                  ...compilations.reversed.map((c) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: RetroCard(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Icon(Icons.movie,
                                  color: theme.colorScheme.primary, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      c.title,
                                      style: AppTheme.displayFont(
                                        fontSize: 14,
                                        color: theme.colorScheme.onSurface,
                                      ),
                                    ),
                                    Text(
                                      '${c.clipIds.length} clips',
                                      style: AppTheme.monoFont(
                                        fontSize: 11,
                                        color: AppTheme.dimInk(theme),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  kIsWeb ? Icons.download : Icons.share,
                                  color: theme.colorScheme.primary,
                                  size: 20,
                                ),
                                onPressed: () => _shareCompilation(c.filePath),
                              ),
                            ],
                          ),
                        ),
                      )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: AppTheme.pixelFont(
          fontSize: 11,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
