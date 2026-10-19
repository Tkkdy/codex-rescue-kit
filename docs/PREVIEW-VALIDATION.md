# Preview validation and remaining release gates

State: PUBLIC_PREVIEW_CANDIDATE; not published. This is a new source state derived from e7ce4f5, not a release of that unchanged commit.

Windows PowerShell 5.1.26100.9711 and PowerShell 7.6.5 each passed 73 synthetic cases, including four preview cases: entry refusal without a loadable module (Quarantine and Undo), function-level refusal before context IO, and rejection of an invalid FixtureRoot. Static checks and the synthetic default rescue.cmd Diagnose entry passed on both engines. The existing Skill validator returned `Skill is valid!` / exit 0 for the repository copy.

The exact portable entry commands, each returning the JSON below and actual process exit 3, were:

```powershell
powershell.exe -NoProfile -File kit/Rescue.ps1 -Mode Quarantine
powershell.exe -NoProfile -File kit/Rescue.ps1 -Mode Undo
pwsh.exe -NoProfile -File kit/Rescue.ps1 -Mode Quarantine
pwsh.exe -NoProfile -File kit/Rescue.ps1 -Mode Undo
```

```json
{"status":"BLOCKED","code":"PREVIEW_REAL_MUTATION_DISABLED","exit_code":3}
```

The session was non-elevated. Before/after checks matched 198 task definitions, nine current-user Registry64 Run values, three Startup entries by metadata, auth/config/AGENTS metadata and 1,067 Skill files by metadata; Rules were absent both times. No credential or chat content was read. Full active Codex data-tree immutability is NOT_TESTED: a complete post-run inventory was deliberately not repeated. Metadata agreement cannot prove content identity or recoverability.

The first PS5.1 suite returned 26 PASS / 47 FAIL (exit 2): inherited PS7 module discovery prevented Get-FileHash resolution (46 direct failures and one related stability assertion). The already existing engine-specific Modules isolation was applied only to the test child process and the affected PS5.1 suite rerun: 73 PASS / 0 FAIL. No product code was changed to make those failures pass. The successful PS7 suite was reused. Failed results and raw local driver captures remain available privately, not silently replaced.

Fresh source hashes, results and gate output are in `evidence/preview1/`. Its command strings are portable reconstructions from the executed driver; they are not an original terminal transcript. Copied gate stdout files are raw Python subprocess PIPE bytes. Historical top-level evidence remains decoded/reencoded text associated with earlier commits. The historical candidate builder/evidence checker is not a Preview validator; a separate committed-file export produces the new candidate ZIP and external manifest.

Real Windows Task/Run/COM modification, Journal/Undo fault injection, A GUI, B/C origin, sandbox boundaries and full VM compatibility remain NOT_TESTED. These host refusal/synthetic checks do not certify them. No live repair, authentication/Skills installation, configuration/ACL change, push or release was performed.

A bounded scan of the three baseline commits covered 109 distinct blobs: no configured secret/user-path patterns matched; the third-party notice contained an explicit non-inclusion reference to incident materials. Public staging uses a fresh repository initialized from the reviewed allowlist, followed only by publication metadata/documentation commits, with no inherited private Git history, bundle, user-supplied reports or host snapshots. Final scanning is bounded and cannot guarantee absence of all sensitive information.

The rights holder has confirmed Copyright (c) 2026 Tkkdy, MIT authorization limited to original implementation they may license, maintainer Tkkdy, GitHub Issues for ordinary reports, Private Vulnerability Reporting for security reports, and target Tkkdy/codex-rescue-kit. A subsequent lookup confirms Public repository Tkkdy/codex-rescue-kit (ID 1425249603), empty, with administrator access via the Tkkdy connector. The owner enabled Private Vulnerability Reporting and the public REST API returned enabled=true. The owner also authorized starting the official GitHub CLI device-login flow; human account confirmation is pending at this preparation snapshot. This agent did not create the repository. Final publication is determined by the actual GitHub release and its commit/assets, not this prepublication record. Existing runtime and Skill bytes are unchanged, so the prior 73/73 per-engine and gate evidence is reused; publication metadata does not relabel any untested live behavior. The full VM matrix remains future work for restoring live functionality, rather than a prerequisite imposed on this write-disabled source Preview.
