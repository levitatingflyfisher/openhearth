import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/result.dart';
import '../../../../features/backup/webdav_backup_flow.dart';
import '../../../../services/backup/webdav_backup_service.dart';
import 'package:still_life/core/widgets/failure_feedback.dart';

class WebDavSettingsScreen extends ConsumerStatefulWidget {
  const WebDavSettingsScreen({super.key});

  @override
  ConsumerState<WebDavSettingsScreen> createState() =>
      _WebDavSettingsScreenState();
}

class _WebDavSettingsScreenState extends ConsumerState<WebDavSettingsScreen> {
  final _urlCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscurePass = true;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final cfg = await ref.read(webDavServiceProvider).loadConfig();
    if (cfg != null && mounted) {
      setState(() {
        _urlCtrl.text = cfg.url;
        _userCtrl.text = cfg.username ?? '';
        _passCtrl.text = cfg.password ?? '';
      });
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    if (!url.startsWith('https://')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'WebDAV URL must start with https://. Over plain http your '
              'login would travel readable.',
            ),
          ),
        );
      }
      return;
    }
    await ref
        .read(webDavServiceProvider)
        .saveConfig(
          WebDavConfig(
            url: url,
            username: _userCtrl.text.trim().isEmpty
                ? null
                : _userCtrl.text.trim(),
            password: _passCtrl.text.isEmpty ? null : _passCtrl.text,
          ),
        );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('WebDAV settings saved')));
    }
  }

  Future<void> _backup() async {
    setState(() => _isBusy = true);
    try {
      final result = await const WebDavBackupFlow().upload(ref.read);
      if (mounted) {
        result.when(
          success: (_) => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Encrypted backup sent to your server.'),
            ),
          ),
          failure: (f) => ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                failureSentence("Couldn’t back up to your server", f.message),
              ),
            ),
          ),
        );
      }
    } on WebDavNeedsWordsException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(webDavNeedsWordsMessage)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              failureSentence("Couldn’t back up to your server", e),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  /// The spinner shows only while the file downloads. Then the encrypted
  /// backup's own restore asks for the words when needed, shows the
  /// preview and confirm, takes the safety snapshot, and resets the cached
  /// reads through its restore hook (backup_wiring.dart).
  Future<void> _restore() async {
    const flow = WebDavBackupFlow();
    setState(() => _isBusy = true);
    final Result<Uint8List> fetched;
    try {
      fetched = await flow.download(ref.read);
    } catch (e) {
      _sayRestoreFailed(e);
      return;
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
    if (!mounted) return;
    switch (fetched) {
      case Success(:final data):
        await flow.restore(context, ref, data);
      case Err(:final error):
        _sayRestoreFailed(error.message);
    }
  }

  void _sayRestoreFailed(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failureSentence("Couldn’t restore from your server", error),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WebDAV Backup')),
      body: OhPage(
        padding: EdgeInsets.zero,
        child: ListView(
          padding: OhSpacing.insetMd,
          children: [
            const Text(
              'Point Still Life at a WebDAV server (Nextcloud, Synology, etc.) '
              'to back up and restore your inventory.',
            ),
            const SizedBox(height: 12),
            const Text(webDavWhatLeavesText),
            const SizedBox(height: 20),
            TextFormField(
              controller: _urlCtrl,
              decoration: const InputDecoration(
                labelText: 'WebDAV URL',
                hintText:
                    'https://cloud.example.com/remote.php/dav/files/alice/still-life.ohbk',
                helperText: 'Must start with https://',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _userCtrl,
              decoration: const InputDecoration(
                labelText: 'Username (optional)',
                border: OutlineInputBorder(),
              ),
              autocorrect: false,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passCtrl,
              obscureText: _obscurePass,
              decoration: InputDecoration(
                labelText: 'Password / App token (optional)',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePass ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () => setState(() => _obscurePass = !_obscurePass),
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _isBusy ? null : _save,
              child: const Text('Save Settings'),
            ),
            const SizedBox(height: OhSpacing.lg),
            const Divider(),
            const SizedBox(height: OhSpacing.md),
            if (_isBusy)
              const Center(child: CircularProgressIndicator())
            else ...[
              OutlinedButton.icon(
                onPressed: _backup,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('Back Up Now'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _restore,
                icon: const Icon(Icons.cloud_download_outlined),
                label: const Text('Restore from WebDAV'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
