"use strict";

const assert = require("assert");
const { buildToastFocusLaunchUri } = require("../toast-focus");

const launchUri = buildToastFocusLaunchUri({
  workspaceName: "Codex Notifier",
  workspacePath: "C:\\Users\\RADZ\\project io\\Codex Notifier",
  activeFileName: "extension.js",
  windowSessionId: "window-session-test",
  windowPid: 12345
});
const payload = new URL(launchUri).searchParams.get("target");
assert.deepStrictEqual(
  JSON.parse(Buffer.from(payload, "base64url").toString("utf8")),
  {
    workspaceName: "Codex Notifier",
    workspacePath: "C:\\Users\\RADZ\\project io\\Codex Notifier",
    activeFileName: "extension.js",
    windowSessionId: "window-session-test",
    windowPid: 12345
  }
);
assert.strictEqual(buildToastFocusLaunchUri({}), "");

console.log("Toast focus tests passed.");
