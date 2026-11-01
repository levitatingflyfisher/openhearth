// The backup file: the saved place and the night-mode choice, as JSON.
// Each web app moves to its own address (owner ruling, 15 Nov 2026), and a
// browser keeps data per address, so the family carries this file across:
// saved at the old address, opened at the new one. Pure: the caller passes
// a store like safeStore's ({get, set}). test/backup.test.mjs pins it.

export const LOCATION_KEY = "nightglass.location";
export const MODE_KEY = "nightglass.mode";

const NOT_A_BACKUP = "This isn’t a NightGlass backup file.";

function savedPlace(store) {
  try {
    const loc = JSON.parse(store.get(LOCATION_KEY) ?? "null");
    return validPlace(loc) ? loc : null;
  } catch {
    return null;
  }
}

function validPlace(loc) {
  return loc !== null && typeof loc === "object" &&
    typeof loc.lat === "number" && typeof loc.lon === "number" &&
    Math.abs(loc.lat) <= 90 && Math.abs(loc.lon) <= 180 &&
    (loc.name === undefined || typeof loc.name === "string");
}

/** The family's records here: the saved place, if there is one. */
export function countRecords(store) {
  return savedPlace(store) ? 1 : 0;
}

/** The count line, word for word ohStyle's ohMoveFound. */
export function foundLine(n) {
  if (n === 0) return "We found no records saved in this browser.";
  if (n === 1) return "We found 1 record saved in this browser.";
  return `We found ${n} records saved in this browser.`;
}

/** The backup file's text and name. Reads only. */
export function makeBackup(store, now = new Date()) {
  const mode = store.get(MODE_KEY);
  const data = {
    app: "nightglass",
    version: 1,
    createdAt: now.toISOString(),
    location: savedPlace(store),
    mode: mode === "night" || mode === "normal" ? mode : null,
  };
  return {
    text: JSON.stringify(data, null, 2),
    fileName: `nightglass-backup-${now.toISOString().slice(0, 10)}.json`,
  };
}

/** The backup in [text], checked. Throws an Error with plain words. */
export function readBackup(text) {
  let data;
  try {
    data = JSON.parse(text);
  } catch {
    throw new Error(NOT_A_BACKUP);
  }
  if (data === null || typeof data !== "object" || data.app !== "nightglass") {
    throw new Error(NOT_A_BACKUP);
  }
  if (data.location !== null && data.location !== undefined && !validPlace(data.location)) {
    throw new Error(NOT_A_BACKUP);
  }
  const mode = data.mode === "night" || data.mode === "normal" ? data.mode : null;
  return { location: data.location ?? null, mode };
}

/** Puts [backup] in the store. A part the backup lacks is left alone.
 *  Returns false when the browser refused a write. */
export function applyBackup(store, backup) {
  let ok = true;
  if (backup.location) ok = store.set(LOCATION_KEY, JSON.stringify(backup.location)) && ok;
  if (backup.mode) ok = store.set(MODE_KEY, backup.mode) && ok;
  return ok;
}
