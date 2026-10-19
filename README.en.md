# Codex Rescue Kit — v0.1.0-preview.1

**Public source preview, not a production recovery release.** Independent Windows Codex diagnostic kit and optional Skill; not affiliated with or endorsed by OpenAI.

## Start with diagnostics only

Unzip the trusted source archive to a local directory and double-click `rescue.cmd`, or run `./rescue.cmd` from an ordinary PowerShell session. Default `Diagnose` does not modify Codex config, authentication, skills, tasks, or registry, but does create diagnostic report files outside your Codex home.

This preview **blocks real Windows `Quarantine` and `Undo`**, returning `PREVIEW_REAL_MUTATION_DISABLED`. Synthetic fixture tests remain available. Do not circumvent the gate for production use.

The verification framework may write explicit test canaries in user-selected controlled locations; A/B/C origin evidence and Sandbox behaviors have not been verified on live systems. It is not a Codex repair certification. CheckBackup checks listed hashes, not restore viability.

Baseline: `e7ce4f5bf7ce75a2039b7036cc5c1a9356ad24af`; previous code review passed, but live Windows API testing remains incomplete. Its 62+8 per-engine synthetic/targeted test records do **not** certify this new preview gate modification. See [Preview policy](docs/PREVIEW-PUBLICATION.md), [Security](docs/SECURITY.md), [Operations](docs/OPERATIONS.md) and [LICENSE](LICENSE).

No customer backups, credentials, chat logs, telemetry, installers, or private Git history are included. Reports may contain sensitive metadata: review them before sharing. Copyright (c) 2026 Tkkdy. MIT covers only original implementation the rights holder is entitled to license; restricted third-party and private incident materials are excluded. Maintainer: [Tkkdy](https://github.com/Tkkdy); ordinary reports: [Issues](https://github.com/Tkkdy/codex-rescue-kit/issues); vulnerabilities: [private reporting](https://github.com/Tkkdy/codex-rescue-kit/security/advisories/new). See [SECURITY.md](SECURITY.md). No personal email is published.

## Preview validation

Windows PowerShell 5.1.26100.9711 and PowerShell 7.6.5 each passed 73 synthetic cases, including four preview-specific gate cases. All four live entry refusal commands returned BLOCKED / PREVIEW_REAL_MUTATION_DISABLED / exit 3 in a non-elevated session. Static checks, synthetic default Diagnose entry and Skill structure validation passed. This does not certify live adapters, GUI/tool origins, sandbox boundaries or complete active Codex data-tree immutability. See [validation scope](docs/PREVIEW-VALIDATION.md) and the fresh records under `evidence/preview1/`. The rights holder, maintainer and target Tkkdy/codex-rescue-kit are confirmed. The Public repository and Private Vulnerability Reporting enablement have been verified. This is the prepublication candidate source; see the actual GitHub Pre-release for publication status.
