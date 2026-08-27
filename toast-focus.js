"use strict";

function buildToastFocusLaunchUri(target) {
  if (!target?.workspaceName) return "";
  const payload = Buffer.from(JSON.stringify({
    workspaceName: String(target.workspaceName),
    workspacePath: String(target.workspacePath || ""),
    activeFileName: String(target.activeFileName || ""),
    windowSessionId: String(target.windowSessionId || ""),
    windowPid: Number.isInteger(target.windowPid) ? target.windowPid : 0
  }), "utf8").toString("base64url");
  return `codex-notifier://focus?target=${payload}`;
}

module.exports = { buildToastFocusLaunchUri };
