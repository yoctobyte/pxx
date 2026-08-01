---
summary: "Policy: how to carry dependency-grade third-party source — vendor in-tree vs fetch-gitignored vs system-dynamic"
type: idea
track: U
prio: 45
status: resolved
resolved: 2026-08-01
---

## DECIDED 2026-08-01 — the tiered policy, informally, no new ceremony

**User's call**: corpus stays fetch-gitignored (unchanged, the default). The
two existing exceptions (pdfgen, MarkupSafe's `_speedups.c`) are fine as
precedent — they confirm the general rule rather than break it, since the
alternative in both cases is reimplementing the thing ourselves. Keep doing
what's already being done case-by-case (small, permissively-licensed,
dependency-grade, license file + provenance note alongside) — no need to
build a formal vendor/ directory system or write more policy than this.

# decide: third-party source policy — vendor vs fetch vs system-dynamic

- **Type:** decision (Track U — human policy call, escalate-don't-guess)
- **Status:** backlog
- **Opened:** 2026-07-25 — surfaced by the songformatter/pxxpdf design
  ([[feature-lib-pxxpdf-reportlab-compat]]). Rene: "if we are to depend on it, we
  may have to support it."

## The fork

pxx today commits **zero** foreign source — BOTH `external/` (`.gitignore:28`) and
`library_candidates/` (`:34`) are gitignored; all third-party is fetched into
ignored dirs. That's a deliberate stance. It fits **test corpus** (zlib, lua, tcc
— compiled to test ourselves, can vanish, we don't care) but has **no clean
answer for a dependency** the product actually needs at build/link time (pxxpdf's
pdfgen; arguably sqlite). A dependency you can't reliably get is a dependency you
must *support*.

Three models, in play across the repo:
1. **System-dynamic** — rely on an OS `.so` (gtk via `gtk3.pas`; `import sqlite3`
   → `libsqlite3.so.0`). Nothing in repo; runtime dep on the host.
2. **Fetch-gitignored** — pinned commit+sha into `library_candidates/`, compiled
   in, never committed (current corpus convention).
3. **Vendor in-tree** — commit the source. Self-contained, patchable, no network.
   NONE today.

## Trade-offs

| | vendor in-tree | fetch-gitignored | system-dynamic |
|---|---|---|---|
| build reproducible / offline | ✅ | ✗ (network+upstream) | ✗ (host must have lib) |
| self-contained binary | ✅ (static) | ✅ (static) | ✗ (runtime .so) |
| repo stays clean of foreign src | ✗ | ✅ | ✅ |
| can patch for pxx | ✅ | ✗ (patch lost on refetch) | ✗ |
| license exposure (redistribution) | must vet per-lib | avoided (not re-hosted) | avoided |
| upstream security tracking | manual | manual | OS-managed |

## The question for the user

Adopt a **tiered policy**? Proposed:
- **corpus** → fetch-gitignored (unchanged).
- **dependency-grade + permissive/PD license + small** → **vendor in-tree** (new
  dir e.g. `vendor/` or `lib/<x>/vendor/`, license file alongside, provenance +
  pinned upstream commit recorded).
- **dependency-grade + heavy or copyleft** → prefer system-dynamic or reconsider.

If yes, where do vendored deps live, and what provenance metadata is required
(UPSTREAM.md with URL+commit+sha+license per vendored lib)?

## Recommendation

Adopt the tiered policy. pdfgen (PD, single-file) is the clean first case and
can be vendored now without blocking on this. Revisit sqlite/others case-by-case.

## Log
- 2026-07-25 — filed. pxxpdf proceeds with vendored pdfgen (PD-safe); this sets
  the general rule.
