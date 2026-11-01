// The move page lives at the old address for good, in the landing site at
// /move/nightglass/. It counts what this browser holds there, saves the
// backup file, links to the new address, and writes nothing. The app at the
// new address offers the way back while it holds no place. The words are
// ohStyle's OhMoveDataScreen and OhMovedHereOffer, word for word.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile, mkdtemp, readdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

const ROOT = new URL("../", import.meta.url).pathname;
const words = (html) => html.replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim();

const MOVE_HTML = await readFile(path.join(ROOT, "move/index.html"), "utf8");
const MOVE_JS = await readFile(path.join(ROOT, "move/move.js"), "utf8");
const APP_HTML = await readFile(path.join(ROOT, "app/index.html"), "utf8");

test("the move page says the move in ohStyle's words", () => {
  const w = words(MOVE_HTML);
  for (const line of [
    "NightGlass has moved",
    "NightGlass now lives at nightglass.familyflourishing.org.",
    "To bring them across, save a backup file here. Then go to the new address and open the file there.",
    "Save a backup file",
    "Nothing here is deleted. Your data stays in this browser.",
    "Go to nightglass.familyflourishing.org",
  ]) assert.ok(w.includes(line), line);
  assert.match(MOVE_HTML, /<a [^>]*href="https:\/\/nightglass\.familyflourishing\.org\/"/);
});

test("the move page writes nothing", () => {
  const code = MOVE_JS.replace(/^\s*\/\/.*$/gm, "");
  for (const banned of [".set(", "setItem", "removeItem", ".clear(", "applyBackup"]) {
    assert.ok(!code.includes(banned), `move.js contains ${banned}`);
  }
});

test("the app offers the way back on its setup screen", () => {
  const setup = APP_HTML.match(/<section id="setup"[\s\S]*?<\/section>/)[0];
  const w = words(setup);
  for (const line of [
    "Used this app before at the old address?",
    "Bring your data across. Save a backup file at the old address, then open it here.",
    "Open a backup file", "Go to the old address", "Not now",
  ]) assert.ok(w.includes(line), line);
  assert.match(setup, /<a [^>]*href="https:\/\/levitatingflyfisher\.github\.io\/move\/nightglass\/"/);
});

test("the app can save and open a backup file", () => {
  const w = words(APP_HTML);
  assert.ok(w.includes("Save a backup file"));
  assert.match(APP_HTML, /<input [^>]*id="backup-file"[^>]*type="file"|<input [^>]*type="file"[^>]*id="backup-file"/);
});

test("the published folder names the new address", async () => {
  assert.equal((await readFile(path.join(ROOT, "app/CNAME"), "utf8")).trim(),
    "nightglass.familyflourishing.org");
});

test("the build puts the move page and only what it needs in one folder", async () => {
  const out = await mkdtemp(path.join(tmpdir(), "ng-move-"));
  try {
    await promisify(execFile)("node", [path.join(ROOT, "tools/build-move-page.mjs"), out]);
    const files = (await readdir(out, { recursive: true })).sort();
    assert.deepEqual(files, [
      "css", "css/style.css", "icons", "icons/icon.svg", "index.html",
      "js", "js/backup.js", "js/download.js", "js/safe-store.js", "move.js",
    ]);
  } finally {
    await rm(out, { recursive: true, force: true });
  }
});
