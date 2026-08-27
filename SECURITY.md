# Security Policy

## Supported Versions

This project is distributed primarily through private VSIX releases. Security fixes are applied to the latest released version.

The Windows toast focus helper uses a per-user protocol registration and a
bundled hidden script. It validates the selected native window as a VS Code
window before focusing it. It does not execute toast text as a command and
does not send notification content to an external service.

## Reporting a Vulnerability

If you discover a security issue, do not post it publicly first.

Please report it privately with:

- A short description of the issue
- Steps to reproduce
- Impact assessment
- Suggested mitigation (if known)

If no dedicated security inbox is available, contact the maintainer through the same private channel used for receiving the VSIX package.

## Response Expectations

- Initial acknowledgement target: within 7 days
- Triage and severity assessment target: within 14 days
- Fix/release timing depends on impact and complexity.

Please do not include secrets, access tokens, private session files, or full
Codex transcripts in a report. Redact those details before sending logs or
screenshots.
