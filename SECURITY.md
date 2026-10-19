# Security policy

Maintainer: [Tkkdy](https://github.com/Tkkdy).

## Report a vulnerability privately

Use [GitHub Private Vulnerability Reporting](https://github.com/Tkkdy/codex-rescue-kit/security/advisories/new). Do not disclose vulnerabilities or sensitive reproduction material in public Issues. Public distribution of this Preview requires the repository owner to enable private vulnerability reporting and verify the report form is available. If that form is unavailable, do not post the details publicly; the release gate remains blocked.

For ordinary bugs and feature requests containing no sensitive information, use [GitHub Issues](https://github.com/Tkkdy/codex-rescue-kit/issues). No personal email address is published.

Include the affected version/commit, Windows and PowerShell versions, expected/observed behavior and a minimal reproduction using synthetic fixtures. Redact local paths, credentials and user metadata. Never upload original incident bundles, backups, auth files, chat content, SQLite databases or private Plan/Journal data.

## Preview support and scope

`v0.1.0-preview.1` is Experimental / Pre-release. Default recommended use is Diagnose. Live Windows Quarantine and Undo remain blocked at the entry and function levels with `PREVIEW_REAL_MUTATION_DISABLED` / exit 3. Synthetic tests are not live adapter, GUI, sandbox or recovery certification.

Verify/ToolProbe can write explicitly chosen test canaries. Diagnostic reports may contain sensitive metadata and must be reviewed before sharing. Source and hashes do not provide a sandbox against a malicious same-user process. See [the threat model](docs/SECURITY.md), [known limitations](docs/KNOWN-LIMITATIONS.md) and [validation scope](docs/PREVIEW-VALIDATION.md).

Reports will be reviewed by the maintainer as capacity permits. No fixed response time, repair guarantee or long-term support commitment is promised. Restoring live mutation requires a separately reviewed release and real Windows adapter validation.
