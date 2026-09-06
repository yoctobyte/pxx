# Review: the cross-target and `sizeof` claims in the beta 0.1 draft

frankA, 2026-09-06. Reviewing `devdocs/dev/release-notes-beta-0.1-draft.md`
(frankC) on the two areas assigned to this seat: **the cross-target claims** and
**the `sizeof` / width claims**.

**Every row below was RE-MEASURED, not read.** Instrument:
`stable_linux_amd64/default/pinned`, sha256 `4bfd73d70588…` — byte-identical to
the binary the draft names, so this is the same pin v406 (`ab72ab352`) the
document's own numbers were taken against, and not my working compiler.

Two claims hold exactly. Three understate, all in the release's favour. One
paragraph is stale.

---

## 1. HOLDS — `long double` is 8 bytes; gcc's is 16

Re-measured, one source file through both compilers:

| | gcc -O0 | pxx pin |
| --- | --- | --- |
| `sizeof(long double)` | 16 | **8** |
| `sizeof(struct { long double x; })` | 16 | **8** |
| `sizeof(double)` | 8 | 8 |

The draft's sentence is exact and the "no diagnostic" half is exact too.

**One row worth ADDING, because it makes the draft's own point harder:**
`struct T2 { char c; long double y; }` is **32 under gcc and 16 here**. The
draft says an aggregate containing one *"disagrees about its own size the moment
it crosses a boundary"*; the padding makes that a factor of two rather than a
factor of two on one member, and a `char`-then-`long double` struct is a shape
real C actually writes.

**And one caution for whoever turns this into a test, which is not a criticism
of the claim.** pxx's answer, 8, is also `sizeof(double)`. So that row cannot
by itself distinguish *"`long double` is modelled as `double`"* from *"`long
double` was not recognised at all and fell back to a default"* — the expected
value collides with the blank value. The `struct T2` row separates them
(16 ≠ any plausible default) and is the one to assert on.

## 2. UNDERSTATES — the hello rows are five targets, not three and two

The draft shows Pascal on `native / aarch64 / riscv32` and C on
`native / aarch64`. A reader counts the rows and infers the rest do not work.

Measured, same pin, same two source files, run under qemu:

| | x86_64 | i386 | aarch64 | arm32 | riscv32 |
| --- | --- | --- | --- | --- | --- |
| `begin writeln(6*7) end.` | 42 | **42** | 42 | **42** | 42 |
| `printf("%d\n", 6*7)` | 42 | **42** | 42 | **42** | **42** |

**Ten of ten.** Every emulable target, both languages. `xtensa` and `wasm32`
are the two the host cannot run, which the draft already says and
`--list-targets` confirms — so the five-column table is the complete runnable
set, not a sample.

The seven-target list itself is correct: `--list-targets` names exactly
`x86_64, i386, aarch64, arm32, riscv32, xtensa, wasm32`.

## 3. UNDERSTATES — Nil-Python's cross-target reach is not stated anywhere

The draft's Nil-Python section says nothing about targets, and the only place
the frontend appears beside a target is the ESP paragraph, where it is grouped
with Rust and Zig. That grouping is true **of ESP** and reads as a general
statement, which it is not:

| frontend | x86_64 | i386 | aarch64 | arm32 | riscv32 |
| --- | --- | --- | --- | --- | --- |
| Nil-Python | runs | **runs** | **runs** | **runs** | refuses, honestly |
| Rust | runs | refuses | refuses | refuses | refuses |
| Zig | runs | refuses | refuses | refuses | refuses |

NilPy is a **four-target frontend**. Its riscv32 refusal is the good kind and
names its own ticket: *"a heap arena needs mmap, which this profile has not
(bug-a-nilpy-on-cross-targets-four-remaining-walls)"*.

Grouping a four-target frontend with two one-target ones costs the release a
true claim it has already earned.

## 4. HOLDS, and the mechanism is worth one clause — Rust and Zig

*"a handful of tests on one target each"* is correct. What the sentence does not
say is that this is a **deliberate refusal at the top of the parse**
(`rparser.inc:5774`, `zparser.inc:1983`), not an untested gap — and that the
refusal is **load-bearing**.

Measured tonight by disabling both refusals locally, rebuilding, and restoring
with `git checkout HEAD --`: both frontends then compile **clean** for i386,
aarch64 and arm32, and every one of those binaries dies before its first
syscall, on a literal x86-64 `call main; xor edi,edi; mov eax,231; syscall`
tail that three skeleton drivers emit unconditionally. Filed as
`bug-a-three-frontend-drivers-hand-write-an-x86-64-program-tail-and-a-target-refusal-is-what-hides-it`.

So the honest one-liner is *"they refuse every other target rather than emitting
something that would not run"*, which is the same virtue the ESP paragraph
already credits elsewhere in the document.

## 5. STALE — the riscv32 skip paragraph describes a state that ended today

The draft says twenty-eight riscv32 rows share the sentence *"backend feature
gap"*, seven have ever been checked, five of the seven did not hold, and
**twenty-three nobody has looked at**.

Counted at `origin/master` just now, from the Makefile itself rather than from
anyone's report:

    # SKIP ... on riscv32                              25
      MEASURED 2026-09-06 ... matches the oracle       22
      REAL SKIP, checkable in one command               2   (both extern_c)
      SKIP IS RIGHT, REASON WAS WRONG                   1   (test_rtti)
    still saying "backend feature gap"                  0

**Twenty-three unexamined is now zero**, and the paragraph's premise — one
shared sentence with a five-in-seven record — no longer has a referent. This is
frank-subcoord's work from this evening; I verified it against the tree rather
than taking the count.

**The replacement is a better paragraph, not a shorter one.** Twenty-two of the
twenty-five are skipped *only* because they compare against an x86-64 oracle and
would need a per-target expectation — they build, run, and match byte for byte
on riscv32 today. Two are honest refusals with a diagnostic. One, `test_rtti`,
is a legitimate skip whose stated reason was wrong until today: it prints raw
addresses and `InstanceSize`, which differ per target **by construction**.

That last row is the document's own thesis with a name on it: *the skip was
right and the reason was wrong, which is the worst combination, because nobody
re-checks a row whose reason sounds settled.* It is a stronger example than the
one currently in the text and it is now written down in the Makefile.

## 6. Not in my assignment, flagged rather than acted on

The draft's `-O4` sentence, the `examples/` 36-of-36 count, the wasm32
paragraph and the `ok:` / no-file defect were not re-measured by this seat.
Someone should say who checked them; an unlabelled claim travelling beside
checked ones inherits their credibility.

---

## What this seat did NOT check

The ESP rows (four configurations, 29 emulator assertions) — no ESP hardware or
emulator run from here, and the draft's own numbers came from a seat that had
one. The `xtensa` and `wasm32` columns above are absences, not failures: this
host cannot run either, which is the same reason the draft gives.
