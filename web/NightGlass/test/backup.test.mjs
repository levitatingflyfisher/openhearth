// NightGlass keeps one saved place and the night-mode choice in this
// browser. Each web app moves to its own address (owner ruling, 15 Nov
// 2026), and a browser keeps data per address, so the family carries it
// across as a backup file: saved here, opened there. backup.js is the pure
// part: make the file, read it back, put it in the store.
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  makeBackup, readBackup, applyBackup, countRecords, foundLine,
} from "../app/js/backup.js";

// A store like safeStore's, over a Map, that records every write.
function memStore(init = {}) {
  const m = new Map(Object.entries(init));
  const writes = [];
  return {
    writes,
    get: (k) => (m.has(k) ? m.get(k) : null),
    set: (k, v) => { writes.push(k); m.set(k, v); return true; },
  };
}

const PLACE = { lat: 44.6, lon: -110.5, name: "Yellowstone camp" };

test("a saved place is one record; nothing saved is none", () => {
  assert.equal(countRecords(memStore()), 0);
  assert.equal(countRecords(memStore({ "nightglass.location": JSON.stringify(PLACE) })), 1);
  assert.equal(countRecords(memStore({ "nightglass.mode": "night" })), 0);
});

test("making a backup only reads", () => {
  const store = memStore({
    "nightglass.location": JSON.stringify(PLACE), "nightglass.mode": "night",
  });
  const b = makeBackup(store, new Date("2026-11-15T10:00:00Z"));
  assert.deepEqual(store.writes, []);
  assert.equal(b.fileName, "nightglass-backup-2026-11-15.json");
  const data = JSON.parse(b.text);
  assert.equal(data.app, "nightglass");
  assert.deepEqual(data.location, PLACE);
  assert.equal(data.mode, "night");
});

test("a backup opens again and fills an empty store", () => {
  const from = memStore({ "nightglass.location": JSON.stringify(PLACE), "nightglass.mode": "night" });
  const to = memStore();
  assert.equal(applyBackup(to, readBackup(makeBackup(from).text)), true);
  assert.deepEqual(JSON.parse(to.get("nightglass.location")), PLACE);
  assert.equal(to.get("nightglass.mode"), "night");
});

test("a backup with no place leaves the place alone", () => {
  const to = memStore({ "nightglass.location": JSON.stringify(PLACE) });
  applyBackup(to, readBackup(makeBackup(memStore()).text));
  assert.deepEqual(JSON.parse(to.get("nightglass.location")), PLACE);
});

test("anything else is refused in plain words", () => {
  for (const text of ["", "not json", "{}", '{"app":"lilt"}',
    '{"app":"nightglass","location":{"lat":"x","lon":1}}',
    '{"app":"nightglass","location":{"lat":91,"lon":1}}']) {
    assert.throws(() => readBackup(text), { message: "This isn’t a NightGlass backup file." }, text);
  }
});

test("the count line is ohStyle's, word for word", () => {
  assert.equal(foundLine(0), "We found no records saved in this browser.");
  assert.equal(foundLine(1), "We found 1 record saved in this browser.");
  assert.equal(foundLine(2), "We found 2 records saved in this browser.");
});
