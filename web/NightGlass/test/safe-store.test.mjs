// Storage can throw (blocked site data, some private modes, a full quota).
// The app must still start, on defaults, and a failed save must not crash a tap.
import { test } from "node:test";
import assert from "node:assert/strict";
import { safeStore } from "../app/js/safe-store.js";

const throwing = {
  getItem() { throw new Error("blocked"); },
  setItem() { throw new Error("quota"); },
};

test("reads from throwing storage give null, as if nothing were saved", () => {
  const s = safeStore(() => throwing);
  assert.equal(s.get("k"), null);
});

test("reaching the storage object itself may throw", () => {
  const s = safeStore(() => { throw new Error("SecurityError"); });
  assert.equal(s.get("k"), null);
  assert.equal(s.set("k", "v"), false);
});

test("a failed write reports false and does not throw", () => {
  assert.equal(safeStore(() => throwing).set("k", "v"), false);
});

test("working storage behaves as plain storage", () => {
  const m = new Map();
  const s = safeStore(() => ({
    getItem: (k) => (m.has(k) ? m.get(k) : null),
    setItem: (k, v) => m.set(k, String(v)),
  }));
  assert.equal(s.get("k"), null);
  assert.equal(s.set("k", "v"), true);
  assert.equal(s.get("k"), "v");
});
