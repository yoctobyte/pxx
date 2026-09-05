---
track: D
prio: 35
type: bug
blocked-by: []
summary: "A THIRD population of docs-vs-compiler defect, which no existing check can see: the flag exists, the docs name it, and the docs are wrong about WHICH TARGETS OR SOURCES it applies to. Measured instance fixed here -- `--emit-obj` was documented as working `on any target` and is refused on 3 of 6 backends. A grep of docs against the parser's flag table cannot detect this class, because the flag is in both lists and the page still lies."
status: done
owner: frankD
---

# A doc can name a real flag and still be wrong — about its scope

- **Type:** bug — **Track D** (`docs/**` only). Third population beside
  [[bug-a-help-does-not-advertise-flags-the-compiler-accepts]] [A p35] and
  [[bug-d-the-cli-reference-documents-a-flag-the-compiler-rejects]].
- **Filed 2026-08-30 by frankD** at the coordinator's request, on the way out of
  the lane. **The two measured instances are already fixed** (below); this ticket
  exists for the *class*, which nothing detects.

## The three populations, and why only two are checkable today

| | the doc says | the compiler | who is wrong | detectable by |
| --- | --- | --- | --- | --- |
| **1** | names a flag | **accepts** it, `--help` omits it | `--help` | diff `docs/**` vs `--help` |
| **2** | names a flag | **rejects** it | the doc | diff `docs/**` vs the parser |
| **3** | names a flag **and a scope** | accepts it, **narrower scope** | the doc | **nothing** |

Population 3's flag appears in *both* lists, so every existence check passes and
the page still tells the reader to do something that fails.

## Measured instance — `--emit-obj` "on any target"

Against `$(PXX_STABLE)`, `--emit-obj t.pas o.out` for a trivial Pascal program:

| target | result |
| --- | --- |
| x86_64 | ELF 64-bit relocatable |
| riscv32 | ELF 32-bit relocatable |
| xtensa | ELF 32-bit relocatable |
| **i386** | `error: --emit-obj: only xtensa/riscv32 targets` |
| **aarch64** | same |
| **arm32** | same |

**False on three of six backends.** Two pages carried it —
`docs/reference/cli.md:125` and `docs/features/index.md:16` — both corrected in
the filing commit. The sentence's *other* half was verified and is true: an
output path ending `.o` behaves identically, restriction included, on all six.

## And the refusal message is itself wrong — filed for Track A

It says **"only xtensa/riscv32 targets"** while x86-64 demonstrably works. So a
reader who hits the refusal on aarch64 is told a set that excludes the one
mainstream target where the feature is fine. Two falsehoods pointing opposite
ways, and the error message is the instrument a reader would trust over the docs.
→ [[bug-a-the-emit-obj-refusal-names-a-target-set-that-excludes-x86-64]].

## How to sweep for this class

There is no cheap oracle, which is why it is filed rather than solved:

- **Candidate generator:** scope words next to a flag —
  `grep -rn 'any target\|all targets\|every target\|only \|on x86\|-only' docs/**`.
  That found the two above and one true claim (`-S` says x86-64, and `-S` writes
  a `.s` only on x86-64 — a correctly-scoped row, and the negative control that
  says the generator is not just matching prose).
- **Verdict:** run the flag on **each** target in the claimed scope. Six runs per
  flag against `$(PXX_STABLE)`; no rebuild. A scope claim is only ever settled by
  enumerating the scope.
- **Do not use the error message as the oracle** — see the Track A ticket above;
  on this very flag the message's target set is wrong.

## Why it must be said out loud in any sweep write-up

A completed population-1-and-2 sweep reads as *"the docs agree with the
compiler"*. It does not mean that. **Write the aperture into the sentence, not a
paragraph below it** — "checked which flags exist, not what they apply to" — or
the next reader takes a clean existence sweep as a clean bill of health, which
is what this ticket exists to prevent.

## Gate

`docs/**` internally consistent; every claim run against `$(PXX_STABLE)` on
every target in its stated scope. Compiler not rebuilt.

## Log
- 2026-09-05 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit e7b33cf2f.

## 2026-09-05 — the sweep was executed; the docs are clean, and here is the aperture

Ran the method this ticket describes across `docs/**`. **Every scope claim I
could settle is correct.** Measured against pin v403, binary `c31d03b202da`,
with the pin's sha256 printed before and after the run and unchanged, so the
numbers are not split across a pin swap.

**Candidate generator** (the ticket's own grep, plus `only on|on all |x86-64
only`) produced 30 lines. Six were real flag-scope claims; the rest were prose
matches like "read-only property", which is the generator behaving as designed.

| claim | doc | verdict |
| --- | --- | --- |
| `--emit-obj` writes objects on x86-64, i386, riscv32, xtensa; aarch64 and arm32 have none | cli.md:125 | **true**, all six enumerated |
| `--shared` is x86-64 only | cli.md:126, limits.md:39, objects.md:157 | **true**, all six enumerated |
| `-S` is x86-64 only | cli.md:127 | **true**, all six enumerated |
| `--fpc-float-errors` is x86-64 only | cli.md:176 | **true**, five enumerated |
| classes/interfaces/generics on all four Linux targets | dive/index.md:116 | **true** — built *and ran* a virtual-dispatch program on x86-64, i386, aarch64, arm32; all four print `woof` |
| `-g` DWARF on all four Linux targets | index.md:41, dive/index.md:120 | **true** — `.debug_line` and `.debug_info` present in all four objects |

The `--emit-obj` row is the one this ticket was filed over, and it now enumerates
correctly — including the refusal message, which used to name a target set
excluding x86-64 and today says `--emit-obj: no object writer for --target=<t>`.

**WHAT THIS SWEEP DID NOT SETTLE, stated in the sentence and not a paragraph
below it:** `docs/library/networking.md:143` says the OpenSSL backend is x86-64
only. Verifying that needs a TLS handshake on a cross target, not a compile, so
it is **unverified rather than confirmed** — the one candidate I could not run a
verdict on.

**One real finding, and it is the compiler's, not the docs':**
[[bug-a-shared-reports-an-internal-error-on-four-targets-where-i386-gets-a-clean-refusal]].
`--shared` refuses correctly on i386 and reaches a later stage on aarch64,
arm32, riscv32 and xtensa, where it answers `error: internal: no init/fini thunk
prologue`. Four of five non-x86-64 targets tell the reader the compiler broke
for a limitation the docs state accurately. Same shape as this ticket's own
Track A sibling; reproduces at HEAD.

## Why this is resolved rather than left open for the class

The class still has no automated detector and that has not changed — a scope
claim is only ever settled by enumerating the scope, and the enumeration is
hand-curated per flag. What has changed is that **the current docs tree has been
enumerated**, which is the deliverable; leaving it open would keep a ticket in
the ranker for a standing hazard rather than a piece of work.

**The residual has an owner and a trigger, which is what it needed.** Re-run
this table when a new backend target lands or a new target-scoped flag is
documented — those are the only two events that can falsify a row, and both are
visible in the commit that causes them. The six rows above are the regression
baseline: each is one command per target and the whole table is under a minute.

