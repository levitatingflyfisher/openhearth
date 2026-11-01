// "What leaves your device" — the honest inventory (§1.6 residuals, named;
// WeatherGlass-style structural-privacy disclosure page).
import 'package:flutter/material.dart';
import 'package:openhearth_design/openhearth_design.dart';

class WhatLeavesScreen extends StatelessWidget {
  const WhatLeavesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('What leaves your device')),
      body: OhPage(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            Text('Leaves, as ciphertext only',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('• Your availability posts, group changes, invites '
                'and key handoffs, all encrypted on this phone before '
                'sending. The server stores bytes it cannot parse.'),
            const Text('• Everything is addressed by random-looking '
                'capability ids derived from keys the server never holds. '
                'There is no account, user record, or group registry.'),
            const SizedBox(height: 16),
            Text('The relay can still see', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('• Your IP address, and when it polls which channel '
                'ids. This is a real, accepted residual: Porch does not '
                'promise Tor-grade anonymity.'),
            const Text('• Sizes and timing of ciphertext blobs. Nothing is '
                'logged or stored beyond short TTLs.'),
            const SizedBox(height: 16),
            Text('Never leaves this phone', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('• Your name and contact note in plaintext.'),
            const Text('• Who your friends are (rosters live in an '
                'encrypted file here, and inside end-to-end envelopes).'),
            const Text('• Your notification choices: alerts are computed '
                'on-device.'),
            const Text('• Your Porch stats. There is no analytics plane at '
                'all.'),
            const SizedBox(height: 16),
            Text('And by design', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('• No read receipts exist: reads are anonymous '
                'fetches the protocol cannot attribute.'),
            const Text('• Leaving a group notifies no one.'),
            const Text('• Losing your 12 words AND your backup means no '
                'one can recover your identity. There is no server-side '
                'reset, on purpose.'),
          ],
        ),
      ),
    );
  }
}
