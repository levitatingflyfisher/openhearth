// Words on the page: how they are set and what they claim.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const CSS = await readFile(new URL("../app/css/style.css", import.meta.url), "utf8");

test("labels are set in sentence case, never forced to capitals", () => {
  assert.doesNotMatch(CSS, /text-transform:\s*uppercase/);
});

// House typography: no spaced em dash in words on the page (the setup
// paragraph carried one; parked from the rollout).
test("the page's words carry no spaced em dash", async () => {
  const html = await readFile(new URL("../app/index.html", import.meta.url), "utf8");
  const text = html.replace(/<!--[\s\S]*?-->/g, "").replace(/<script[\s\S]*?<\/script>/g, "")
    .replace(/<style[\s\S]*?<\/style>/g, "").replace(/<[^>]+>/g, " ").replace(/\s+/g, " ");
  assert.doesNotMatch(text, / — /);
});

// The fleet's one publisher line, word for word as ohStyle's ohPublisherLine,
// in the page footer as in the other fleet apps.
test("the footer names the publisher", async () => {
  const html = await readFile(new URL("../app/index.html", import.meta.url), "utf8");
  const footer = html.match(/<footer>([\s\S]*?)<\/footer>/)[1];
  assert.match(footer, /Published by Intergenerational Symbolic Systems/);
});
