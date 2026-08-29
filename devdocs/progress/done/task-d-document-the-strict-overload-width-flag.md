---
track: D
prio: 20
type: task
blocked-by: []
summary: "`--strict-overload-width` shipped 2026-08-15 with no row in docs/reference/cli.md, modes.md or directives.md. One table row each, plus the one sentence that explains why it is standalone rather than part of the --strict-fpc umbrella."
status: done
owner: frankD
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

## Log
- 2026-08-29 — resolved, commit PENDING-COMMIT.

---

## RESOLVED 2026-08-29 (frankD)

Two pages, as the ticket scoped: a row in `docs/reference/cli.md`'s strictness
table and, in `docs/reference/modes.md`, a granular-switch row plus
`### --strict-overload-width — parity on request` next to the existing
`--strict-overload` exclusion paragraph. **`directives.md` deliberately
untouched** — the ticket said only if a source directive exists, and it does not.

### The ticket's table is wrong in two rows — the flag's own oracle says so

The ticket's Gate names `test/test_strict_overload_width.pas` as *"the live
oracle for every row"*, so it was run rather than transcribed. Two rows disagree:

| argument | ticket says default | actually (v393) |
| --- | --- | --- |
| `Integer` | `Int64` | **`LongInt`** |
| literal | `Int64` | **`LongInt`** |

`Integer` and a literal already select `LongInt` without the flag, so the flag
changes nothing for them. The Makefile's own recorded expectation for the
unflagged run agrees with the measurement exactly — and the comment directly
above it says as much (*"SmallInt, Byte and Cardinal still widen to Int64 here"*,
citing `bug-p-integer-and-longint-are-not-the-same-type-in-overload-matching`).
So the published table groups `Integer`/`LongInt`/literal/alias as the row the
flag does **not** move, and `SmallInt`/`Byte` as the row it does.

That also means the ticket's one-line summary of the default — *"takes the first
qualifying candidate and so lands on the widest"* — does not survive contact with
`Integer`. The page says what is observable instead: an exact-width match wins,
and otherwise the widest candidate. Every published row was re-checked against
the compiler programmatically after writing, including the unsigned set.

### `--strict-shift-width` does not exist

The ticket asks for the flag to be presented *"exactly like
`--strict-shift-width`"*. There is no such flag — `pxx --strict-shift-width` is
rejected as an unknown option. FPC shift widths ride under `--strict-fpc` only,
which `cli.md` already states. The framing the ticket wanted (parity on request,
the default is intended and not a bug) is kept; the false analogy is not.

### Kept from the ticket, because it is right and it is the interesting part

- the **`Cardinal` row carries the rule** — narrowest-that-*fits*, not
  narrowest-declared, since `LongInt` is `Cardinal`'s width but cannot hold its
  top half. Stated in bold on the page;
- **why it is standalone**, sharpened: `--strict-overload` changes which programs
  are *accepted*, while this changes which **body a call binds to**, so enrolling
  it would change what the corpora `--strict-fpc` is proven against resolve to.
  That is a separate measured decision and has not been made;
- **the default is intended, not a bug** — said plainly, so the copy does not
  imply the dialect is broken.

### One thing left undocumented on purpose

`{$STRICT_OVERLOAD_WIDTH ON}` is **silently accepted and does nothing** — it
compiles clean as an unrecognised directive. Documenting the flag as
command-line-only is the correct answer here, and the general problem (an ignored
directive that says nothing) already has a mechanism and a ticket of its own:
`--warn-ignored-directives`, which is the next ticket in this lane's queue. No
new ticket filed.

### Measured — pinned v393, no rebuild

`test_strict_overload_width.pas` compiled and run both ways; all eight rows the
page publishes verified against the binary programmatically; `--strict-shift-width`
and `{$STRICT_OVERLOAD_WIDTH ON}` both probed directly.
