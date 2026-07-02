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
- Commercial support / paid feature work stays available as an offering; it
  needs no special license terms.

## Implementation checklist

1. Replace `LICENSE.md` placeholder: MPL 2.0 full text as `LICENSE`, plus a
   short `LICENSE.md` overview table mapping directories to licenses, with
   zlib/0BSD/CC-BY texts under `licenses/`.
2. SPDX header line in every source file (`{ SPDX-License-Identifier: MPL-2.0 }`
   in .pas/.inc; `/* SPDX-License-Identifier: Zlib */` in crtl C; script the
   sweep, keep it byte-safe for the self-host gate — headers are comments, but
   verify `make test` + self-host byte-identical after the sweep).
3. Update `README.md` License section (currently says "no license yet").
4. Add DCO text (`docs/CONTRIBUTING.md` or repo root) — Track D wording pass.
5. Website license page (Track D, when the site work starts).

## Acceptance

LICENSE files in place, SPDX headers repo-wide, README/docs consistent,
`make test` + self-host green after the header sweep, board regenerated.
