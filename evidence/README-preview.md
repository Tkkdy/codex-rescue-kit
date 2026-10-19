# Evidence scope (public preview)

The top-level JSON/logs in this directory were recorded for the frozen e7ce4f5 lineage and earlier baselines. They were independently inspected, but are **not fresh runtime evidence of this preview patch**. In particular, `current-source-manifest.json` contains the hashes of e7ce4f5. Changing those hashes to match preview code without rerunning tests would falsify the association. The historical `tools/Test-CandidateEvidence.ps1` therefore **is not a passing validator of preview code**. See docs/PREVIEW-PUBLICATION.md for the required minimal Windows safety-gate checks.

Fresh preview-specific evidence is under `preview1/`. Its tested-source manifest and summary bind the new runtime source and tests. The initial PS5.1 module-discovery failure is disclosed there; original failed captures and host snapshot digests remain local and are not published. No historical evidence or hashes were rewritten.
