// The fleet's web data notice. NightGlass keeps its place and settings in
// this browser, and clearing the browser's website data erases them. The
// family opens every app from one link in a phone browser, so the page says
// so once, at the top, in its quiet small text. The sentence is word for
// word ohStyle's ohWebDataNotice (curly apostrophe included).
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const NOTICE =
  "Your data stays on this device, in this browser. " +
  "If you clear the browser’s website data, it is erased.";

const HTML = await readFile(new URL("../app/index.html", import.meta.url), "utf8");
const words = (html) => html.replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim();

test("the page says the data notice once, word for word", () => {
  assert.equal(words(HTML).split(NOTICE).length - 1, 1);
});

test("the notice is the first thing in the page, in the quiet small text", () => {
  const body = HTML.match(/<body[^>]*>([\s\S]*)<\/body>/)[1];
  const first = body.match(/<(\w+)([^>]*)>([\s\S]*?)<\/\1>/);
  assert.equal(words(first[3]), NOTICE);
  assert.match(first[2], /class="[^"]*\bhint\b/);
});
