# Adopt MPL 2.0 (compiler) + zlib (runtime/libs) — licensing rollout

- **Type:** task (meta / repo-wide) — Track A (headers in compiler/**) + B (lib/**) + D (docs/website copy)
- **Status:** backlog — decision made 2026-07-02, implementation open
- **Owner:** —

## Decision (final)

- **Compiler and tools** (`compiler/**`, `tools/**`): **MPL 2.0**.
- **Runtime and libraries embedded in compiled output** (`lib/rtl`, `lib/pcl`,
  `lib/crtl`, `lib/asmcore`, `compiler/builtin/**`): **zlib license** — user
  binaries produced by the compiler carry no obligations.
- **Examples** (`examples/**`): **0BSD** (copy-paste freely).
- **Docs** (`docs/**`): **CC BY 4.0**.
- **Contributions:** DCO sign-off required from the first external PR onward.
  While the sole human author remains the only copyright holder, relicensing
  stays a unilateral option; DCO keeps that traceable once contributors join.
- **Name/identity:** the license governs code, not the project name. When the
  website/identity pass happens (Track D), decide the name policy explicitly
  (forks may take the code, not the identity).
- Commercial support / paid feature work stays available as an offering; it
  needs no special license terms.

## Implementation checklist

1. Replace `LICENSE.md` placeholder: MPL 2.0 full text as `LICENSE`, plus a
   short `LICENSE.md` overview table mapping directories to licenses, with
   zlib/0BSD/CC-BY texts under `licenses/`.
2. SPDX header line in every source file (`{ SPDX-License-Identifier: MPL-2.0 }`
   in .pas/.inc; `/* SPDX-License-Identifier: Zlib */` in crtl C) — one line
   per file instead of a full license block; machine-readable for GitHub and
   license scanners. Script the sweep; headers are comments, but verify
   `make test` + self-host byte-identical after (that is the gate).
3. Update `README.md` License section (currently says "no license yet").
4. Add DCO text (`docs/CONTRIBUTING.md` or repo root) — Track D wording pass.
   Enforce sign-off (`Signed-off-by:`) on external PRs from day one.
5. Website license page (Track D, when the site work starts).

## Acceptance

LICENSE files in place, SPDX headers repo-wide, README/docs consistent,
`make test` + self-host green after the header sweep, board regenerated.

## Done (2026-07-02)

- `LICENSE` = MPL 2.0 (canonical text); `licenses/Zlib.txt`, `licenses/0BSD.txt`;
  `LICENSE.md` = per-directory map + third-party statement; `CONTRIBUTING.md`
  with DCO sign-off requirement; README License section updated.
- SPDX one-liner in all 229 tracked source files (MPL-2.0: compiler+tools;
  Zlib: builtin/rtl/pcl/crtl/asmcore; 0BSD: examples). docs/devdocs/test
  covered by the LICENSE.md map, no per-file headers.
- Foreign-code audit: repo contains none. `test/dl.h` was a SYMLINK to the
  system dlfcn.h (never committed content) — replaced with a minimal
  project-owned prototype header (also fixes checkouts without glibc headers).
  `library_candidates/` (FreeBSD regex etc.) and the Lua corpus are fetched on
  demand into git-ignored paths.
- Gates: full `make test` + `make lib-test` green; compiler binary
  byte-identical after the header sweep (comments only) — no re-pin needed.
