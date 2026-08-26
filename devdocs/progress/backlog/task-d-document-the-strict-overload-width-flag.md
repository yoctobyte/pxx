---
track: D
prio: 20
type: task
blocked-by: []
summary: "`--strict-overload-width` shipped 2026-08-15 with no row in docs/reference/cli.md, modes.md or directives.md. One table row each, plus the one sentence that explains why it is standalone rather than part of the --strict-fpc umbrella."
---

# Document `--strict-overload-width`

- **Type:** task (docs) — **Track D**. Filed by Track A, which shipped the flag
  and does not edit `docs/**`.
- **Shipped:** 2026-08-15, `compat-pascal-strict-fpc-should-pick-the-narrowest-integer-overload`.

## What it does

FPC picks the **narrowest integer overload that FITS**; PXX's default dialect
takes the first qualifying candidate and so lands on the widest. Given
`f(Int64)` and `f(LongInt)`:

| argument | default dialect | `--strict-overload-width` (= FPC) |
| --- | --- | --- |
| `Integer` / `SmallInt` / `Byte` / literal | `Int64` | `LongInt` |
| `LongInt` | `LongInt` | `LongInt` |
| `Cardinal` | `Int64` | `Int64` |

The `Cardinal` row is worth keeping in the docs: it is what shows the rule is
narrowest-that-**fits**, not narrowest-declared — `LongInt` is the same width as
`Cardinal` but cannot hold its top half, so `Int64` is the narrowest that fits.

The default is **intended**, not a bug (user, 2026-08-14: *"this widening is not
a bug. BUT it affects `--strict-fpc` mode"*), so the copy should present the
flag as parity-on-request, exactly like `--strict-shift-width`, and not imply
the default is wrong.

## Why it is standalone

Same reason `--strict-overload` is: it changes which BODY a call binds to, so
enrolling it in `--strict-fpc` changes what the corpora that umbrella is
*"proven to compile"* (fgl, Synapse, fpjson 203/203) actually resolve to. That
enrolment is a separate, measured call and has not been made — `modes.md`
already carries the paragraph explaining the umbrella's exclusions, and this
flag belongs in it.

## Where

- `docs/reference/cli.md` — the flag table (beside `--strict-overload`).
- `docs/reference/modes.md` — the strict-flag table, and the
  not-in-the-umbrella paragraph.
- `docs/reference/directives.md` — **only if** a `{$STRICT_OVERLOAD_WIDTH ON}`
  source directive exists. It does **not** today; the flag is command-line only.
  Do not document one that is not there. (Adding the directive is a Track A
  change, not a docs one — file it separately if it is wanted.)

## Gate

Docs stay internally consistent; the table above matches what
`test/test_strict_overload_width.pas` asserts, which is the live oracle for
every row. Do not rebuild the compiler.
