import 'package:flutter/material.dart';

/// What Android's own backup to Google does, and what the app's encrypted
/// backup holds, said beside the backup tiles. The manifest leaves Android
/// backup on, so the owner can turn it on in Android settings; Android skips
/// an app whose data is large, and photos make that likely. The photo backup
/// (.ohbkz) holds every photo and receipt image up to 10 MB each, so the
/// copy says "up to 10 MB" rather than "everything". The records-only backup
/// (.ohbk) holds no images and is not mentioned as holding them.
class AndroidBackupNote extends StatelessWidget {
  const AndroidBackupNote({super.key});

  static const googleLine =
      'Android may also back up this app’s data to Google, if the phone’s '
      'owner allows it in Android settings. The encrypted backup here is the '
      'private choice.';

  static const largeLine =
      'Android skips its own backup of an app whose data is large, so photos '
      'may not be in it. Export with photos, above, is the encrypted backup '
      'that holds them. It leaves out any single image over 10 MB and tells '
      'you when it does.';

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(googleLine, style: style),
          const SizedBox(height: 6),
          Text(largeLine, style: style),
        ],
      ),
    );
  }
}
