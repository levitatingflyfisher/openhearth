// The move page. It counts what this browser holds for NightGlass and saves
// the backup file; it never writes to the store. test/move-page.test.mjs
// pins that.
import { safeStore } from "./js/safe-store.js";
import { countRecords, foundLine, makeBackup } from "./js/backup.js";
import { downloadText } from "./js/download.js";

const store = safeStore(() => localStorage);
const $ = (id) => document.getElementById(id);

$("found").textContent = foundLine(countRecords(store));

$("save").addEventListener("click", () => {
  const backup = makeBackup(store);
  downloadText(backup.text, backup.fileName);
});
