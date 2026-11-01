// Hands [text] to the browser as a file to save, named [fileName]. The
// bytes never leave this device: the link points at memory, not a server.
export function downloadText(text, fileName) {
  const url = URL.createObjectURL(new Blob([text], { type: "application/json" }));
  const a = document.createElement("a");
  a.href = url;
  a.download = fileName;
  document.body.append(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
