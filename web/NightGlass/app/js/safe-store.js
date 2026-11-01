// localStorage that cannot stop the app. Browsers throw on access when site
// data is blocked, and on write when the quota is full. A read then looks
// like "nothing saved" and a failed write returns false, so the app starts
// on its defaults. Pure: the caller passes a function that returns the
// storage object. test/safe-store.test.mjs pins it.
export function safeStore(getStorage) {
  return {
    get(key) {
      try { return getStorage().getItem(key); } catch { return null; }
    },
    set(key, value) {
      try { getStorage().setItem(key, value); return true; } catch { return false; }
    },
  };
}
