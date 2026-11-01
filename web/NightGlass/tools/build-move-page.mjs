// Builds the move page into one folder: node tools/build-move-page.mjs <out>
// The folder goes in the landing site at /move/nightglass/, the old address
// for good. It holds the page and only what it needs, with relative paths.
import { copyFile, mkdir } from "node:fs/promises";
import path from "node:path";

const out = process.argv[2];
if (!out) {
  console.error("usage: node tools/build-move-page.mjs <out-folder>");
  process.exit(2);
}
const root = new URL("../", import.meta.url).pathname;

const files = [
  ["move/index.html", "index.html"],
  ["move/move.js", "move.js"],
  ["app/js/backup.js", "js/backup.js"],
  ["app/js/download.js", "js/download.js"],
  ["app/js/safe-store.js", "js/safe-store.js"],
  ["app/css/style.css", "css/style.css"],
  ["app/icons/icon.svg", "icons/icon.svg"],
];

for (const [from, to] of files) {
  await mkdir(path.dirname(path.join(out, to)), { recursive: true });
  await copyFile(path.join(root, from), path.join(out, to));
}
