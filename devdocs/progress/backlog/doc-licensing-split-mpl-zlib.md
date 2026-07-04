# Document the licensing split (MPL 2.0 compiler / Zlib RTL)

- **Type:** doc (Track D — user/website licensing docs)
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-07-04 (surfaced while adding `lib/rtl/types.pas`)

## What

The repo has a deliberate two-license split that is not called out in the
user-facing docs:

- **Project root `LICENSE` / `LICENSE.md` = MPL 2.0** — the compiler
  (`compiler/**`) and project as a whole.
- **`lib/rtl/**` (and the wider runtime) = Zlib** — every RTL source carries
  `{ SPDX-License-Identifier: Zlib }` (70/70 files). A permissive choice so the
  runtime you link into your program is liberally reusable, mirroring how FPC
  licenses its RTL separately (LGPL-with-static-exception there; Zlib here).

New RTL files should keep the Zlib SPDX header to stay consistent.

## Why a ticket

A user shipping a binary needs to know the RTL that ends up in their executable
is Zlib (very permissive), distinct from the MPL-2.0 compiler. Today they'd have
to grep SPDX headers to discover it.

## Do

Add a short "Licensing" section to the user docs (`docs/**`): state the split,
what each covers, and the practical takeaway ("code you compile links only the
Zlib RTL; the MPL-2.0 terms apply to the compiler, not your program's output").
Prose only — no code/license-file changes here (any actual license change is a
separate decision, not this ticket).
