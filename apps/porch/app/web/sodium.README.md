# sodium.js

`sodium.js` is libsodium.js, the "sumo" build for browsers, vendored as one
file. The web build needs it: `SodiumSumoInit.init()` loads it at runtime.

| | |
|---|---|
| Version | libsodium.js 0.7.14, file `dist/browsers-sumo/sodium.js`, wrapping libsodium 1.0.20 |
| SHA-256 | `3ce8b64a20652dd815f070c953160c97e3839cf2e21567c830e1d8286096fbc6` |
| Size | 1,061,642 bytes |
| Source | https://github.com/jedisct1/libsodium.js, tag 0.7.14 |
| Put here by | `dart run sodium_libs:update_web --sumo` (sodium_libs 3.4.6+4) |

How each fact was found:

- The file has no version header.
- The version string `1.0.20` is inside the WebAssembly module the file
  embeds, decoded from its base64.
- sodium_libs 3.4.6+4 pins libsodium.js `0.7.14` and libsodium `1.0.20` in
  its `libsodium_version.dart`, and its `update_web` tool copies
  `dist/browsers-sumo/sodium.js` from that tag.
- The hash was taken from this file with `sha256sum`. It has not been
  compared with the file at the upstream tag.

`test/web_shell_test.dart` fails when the file changes and this hash does
not. When you update the file, update this table in the same change.
