---
track: D
prio: 35
type: bug
blocked-by: []
summary: "A THIRD population of docs-vs-compiler defect, which no existing check can see: the flag exists, the docs name it, and the docs are wrong about WHICH TARGETS OR SOURCES it applies to. Measured instance fixed here -- `--emit-obj` was documented as working `on any target` and is refused on 3 of 6 backends. A grep of docs against the parser's flag table cannot detect this class, because the flag is in both lists and the page still lies."
status: backlog
owner: unassigned
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
