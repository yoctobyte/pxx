---
slug: bug-a-a-perf-commit-silently-fixed-41-xtensa-windowed-divergences-and-nobody-knows-why
track: A+S
prio: 60
type: bug
blocked-by: []
status: backlog
found: 2026-08-30
found-by: frankS
owner: unassigned
summary: "75d2ba662 pads Code[] so data starts on its own page — filed and reviewed as a qemu PERFORMANCE fix (287x). Bisected: it also takes xtensa/windowed from 53 to 94 of 129 programs matching the oracle, lost=0 gained=41. A layout change fixed 41 CORRECTNESS divergences on a target its author was not looking at, the mechanism is unknown, and an unrelated layout change could take all 41 back."
---

# A perf commit silently fixed 41 xtensa/windowed divergences

## The bisect

Two compilers, both self-host fixedpoints (`converged after N round(s)`, shas
confirmed different from `pinned`), swept against the **same** 129 sources and
the same `lib/rtl` on the same box, so the compiler is the only variable:

| build | windowed MATCH |
| --- | --- |
| `75d2ba662^` (`41e452a55913`) | **53** |
| `75d2ba662` (`a3f0f9e3325f`) | **94** |

`lost=0, gained=41`, totals cross-checked against the row sets. Nothing later in
the range moves it: `658f4bea5` and `10c869750` both sit above `75d2ba662` and
measure 94, and the current HEAD also measures 94.

## What the commit says it does

> *perf(O): page-separate code from data in the ELF writer — 287x under qemu*
>
> A hot write to a word that shares a 4 KiB page with translated code makes a
> qemu-user-style emulator invalidate that page's translations on every store.

Pure performance, target-agnostic, and correct on its own terms. Its own gate
was a timing measurement, which is exactly the gate that cannot notice 41
programs changing their **output**.

## The 41

Almost entirely aggregate and managed shapes — records, dynamic arrays,
interfaces, variants, sets:

```
test_cross_record, test_cross_record_array_store, test_cross_dynarray,
test_dynarray_copy{,_nested}, test_dynarray_field, test_dynarray_whole_assign,
test_nested_dynarray_setlen, test_interface_arc, test_interfaces{,_as,_is,
_inherit,_param,_multi_secondary}, test_cross_variant,
test_cross_variant_payload_widths, test_variant_class_cross, test_cross_sets,
test_set_runtime, test_cross_typed_const, test_frozen_string_cross_b305, ...
```

That family is the one that goes through **data references** — RTTI descriptors,
literal blocks, typed constants. A change to where the data section begins is
plausibly connected to it. **That is a hypothesis and this ticket does not claim
it**; nobody has diffed the emitted code for one of these programs across the
two builds, which is the next step and is cheap.

## Why this is a bug ticket and not a note

**The 41 are passing for a reason nobody chose.** If the mechanism is that a
data-address shift moved something out of a range it was silently out of, then
the underlying defect is still there and is being masked by a layout property
that no test asserts. Any future change to code/data placement — a different
page size, a section added, `--emit-obj`, the ESP image layout, an alignment
tweak — can take all 41 back with no diagnostic and no obvious culprit, and
whoever lands it will look responsible for a regression they did not cause.

Note the ESP angle specifically: the padding follows a 4096-byte constant, and
the commit's own comment says a host with 16 KiB pages would still leave a
residual shared page. An ESP image is not laid out like a hosted ELF at all.

## What to do

1. Pick one of the 41 — `test_cross_record` is small — and diff the emitted
   xtensa code at `75d2ba662^` vs `75d2ba662`. If the instruction stream is
   identical and only addresses moved, the defect is an address-range or
   alignment sensitivity and is still live.
2. Name it, file it, and give it a test that asserts the property directly
   rather than relying on the page padding to keep it true.
3. If instead the two streams differ, then the ELF writer was feeding codegen a
   wrong data base and this was a real fix — in which case say so on
   `75d2ba662`'s ticket, because it is recorded as a perf change and its
   correctness effect is undocumented.

## Provenance

Found while confirming the attribution of a windowed jump the coordinator and I
initially disagreed about. Neither of us was right from reasoning: the
coordinator attributed it to frankS's seven xtensa commits by file ownership,
frankS attributed it to "other lanes" — it is one commit by neither route, and
only the bisect said so. **A saved binary that brackets your own commits does
not bracket what those commits were REBASED onto**, which is what made the first
answer look settled.

## Gate

Whatever the mechanism turns out to be, the windowed differential must stay at
94 or better, and the property that keeps the 41 green must be asserted by
something other than the page padding.

## DIAGNOSED 2026-08-30 (frankS) — masked defect confirmed. THE DATA SECTION IS NOT ALIGNED.

The ticket asked for the emitted code to be diffed before theorising. Done, and
the answer is the branch that wants a test.

### 1. Codegen is identical BY CONSTRUCTION

`75d2ba662` touches exactly one compiler file: `elfwriter.inc`. No backend, no
IR, no codegen. So the instruction stream this commit produces cannot differ —
and the 217 bytes that do differ in the first 195,723 are shifted **address
immediates** plus the header, exactly the signature of data moving underneath
unchanged code.

### 2. The failure is not a wrong value. It is SIGBUS.

`test_cross_record`, windowed, same source, same libs:

| build | result |
| --- | --- |
| `75d2ba662^` | `qemu: uncaught target signal 7 (Bus error) - core dumped` |
| `75d2ba662` | `Alice 30 / Bob 30 / Bob` — matches the x86-64 oracle |

Signal 7 on xtensa is an **alignment fault**. Sampled further: `test_cross_dynarray`,
`test_interfaces` and `test_cross_sets` all SIGBUS on the parent build;
`test_cross_variant` gets partway (`42`) and then diverges.

### 3. The alignment that changed

The reported code length, which is where the data section begins:

| build | `code=` | mod 4 |
| --- | --- | --- |
| `75d2ba662^` | 195723 | **3** |
| `75d2ba662` | 196492 | **0** |

The data section began three bytes past a word boundary. Every 32-bit datum in
it whose in-section offset is not ≡1 (mod 4) is therefore misaligned, and xtensa
faults on an unaligned word load where x86-64 and riscv32 do not. The page
padding 4-aligned the section as a side effect, and that is the whole of the fix.

**So the ELF writer never aligned the data section at all**, on any target. It
began wherever code happened to end.

### 4. A sub-hypothesis I checked and it was WRONG — recorded because it shapes the fix

I predicted `code mod 4` would separate the 41 gained programs from the 53 that
already passed. It does not: **every** sampled program in BOTH groups is ≡3
(mod 4) on the parent build.

That refutes "the 41 are the unlucky ones" and replaces it with something worse:
**the misalignment is universal and always was.** Which program faults depends
only on whether it dereferences a data word that lands misaligned — so the
aggregate/RTTI-heavy family (records, dynamic arrays, interfaces, variants,
sets) faults because it reads multi-word descriptors, and the other 53 pass by
touching nothing misaligned. The 53 were never safe; they were untested.

### 5. What this means for the repair — and it is NOT "keep the padding"

The 41 are green on a **side effect**. The data section still has no alignment
guarantee; it currently gets one from a padding step introduced for a qemu
translation-cache reason, sized by `ELF_DATA_PAGE = 4096`. Anything that changes
that arithmetic can take all 41 back with no diagnostic:

- a second PT_LOAD so data is not executable — **already an open ticket, cited
  in `75d2ba662`'s own body**
- a 16 KiB-page host, which `75d2ba662`'s comment says leaves a residual shared page
- `--emit-obj`, where the hosted layout does not apply
- any ESP image, which is not laid out like a hosted ELF at all

**The fix is to align the data section explicitly, as a stated invariant with a
test that asserts it** — not to rely on the padding continuing to imply it. The
alignment should be the target's word size at minimum; 8 is safer given
`Int64`/`Double` data.

Prio raised 45 → 60: not because it is failing today, but because it is a
correctness property held up by an unrelated perf change while that same file is
under active edit.

### 6. LIVE COORDINATION HAZARD

frank-optimize-b4 owns `75d2ba662` and is in `elfwriter.inc` **now**, on further
page-align work. The 41 programs are the canary for this property and nothing
currently watches them: **they are not in any gated suite** — the 129-source
differential is my scratch harness, and `test-xtensa` does not run the windowed
ABI at all. Wiring a windowed alignment assertion is the cheap protection.

### Not fixed here, deliberately

Diagnosis only. The mechanism is the ELF writer's, not the xtensa backend's, and
whoever repairs it should own that file rather than inherit it from the lane
that noticed.

## CONFIRMED at `df98fea47` (frankS, 2026-08-30) — the same 94 programs, not merely the same number

Three sweeps of the 129 cross sources against the x86-64 oracle, at the **pushed**
tree, compiler binary `62cfb924053f` (`make compiler/pascal26`, converged after 1
round; the binary sha differs from every saved baseline, which is the check
[[218f]] exists to force).

| target / ABI | before | at `df98fea47` | lost | gained |
| --- | --- | --- | --- | --- |
| xtensa call0 | 104 (`2d2bc2fb0e15`) | **104** | 0 | 0 |
| xtensa **windowed** | 94 (`a3f0f9e3325f` = `75d2ba662`) | **94** | 0 | 0 |
| riscv32 | 111 (`bba42787923d`) | **111** | 0 | 0 |

Set difference both directions, totals cross-checked (`matches_before - lost +
gained == matches_after`) on every row.

**The windowed row is the one that carries the finding, and the count is the
weaker half of it.** At `75d2ba662` those 94 passed *by accident*: the page pad
inserted for an unrelated performance reason happened to push the data section
onto a 4-byte boundary. b4 deleted the pad and the canary still passes at
`code=195724`, so the 4096 was never load-bearing — the alignment was. **The same
94 sources pass now for a stated reason instead of a lucky one**, and that is
what `lost=0 gained=0` says and a bare `94 == 94` does not: an equal count can
hide an equal swap, which is why the comparison is a set difference.

**call0 and riscv32 measure the cost, and it is zero.** Both tolerate unaligned
word loads, so neither could gain from the fix; the only thing they could show is
damage from moving every data address, and they show none across 215 program
runs.

**Scope, stated so the number is not over-read.** These 129 are hosted programs
under qemu. They say nothing about ESP bare-metal (`--esp-profile=bare`), nothing
about the other four targets, and — because the compiler binary is the same
`62cfb924053f` b4 re-verified at — they are not an independent check of *which
tree* was measured, only of what that tree does. `gate.sh quick` was green at
b4's pre-rebase `0f609eb67c7a` and has not been re-run on the merged tree; this
sweep is the merged tree's first breadth measurement, and it is clean.

**Not resolving this ticket** — the fix is b4's and so is the close. Recording
the confirmation it asked for by name, in the ticket rather than in a message,
because a finding that lives in a message is not recorded.
