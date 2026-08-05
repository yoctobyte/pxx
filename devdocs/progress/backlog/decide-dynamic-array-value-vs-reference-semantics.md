---
summary: "dynamic arrays: pxx gives b := a VALUE semantics (a copy), FPC/Delphi give REFERENCE semantics (an alias) — is ours deliberate?"
type: decision
track: U
prio: 55
---

# Decide: are dynamic arrays references (FPC) or values (pxx today)?

- **Type:** decision — **Track U**
- **Status:** open
- **Opened:** 2026-08-04
- **Raised by:** Track B, `tools/fpc_diff_probe.sh` `str-dynarray-ref` case.

## The fork

```pascal
var a, b: array of Integer;
begin
  SetLength(a, 2); a[0] := 1;
  b := a;
  b[0] := 9;
  writeln(a[0], '|', b[0]);
end.
```

    FPC/Delphi:  9|9     b and a are the SAME array; assignment aliases
    pxx:         1|9     b is a copy

Same for a `array of string`. Two related rows:

| case | FPC | pxx |
| --- | --- | --- |
| `b := a` then `b[0] := 9` | `9\|9` (aliased) | `1\|9` (copied) |
| `Copy(a,0,2)` then modify | detached | detached — **agree** |
| `SetLength(b,3)` on an alias | detaches | detaches — **agree** |
| open-array **value** param, callee writes `a[0]` | caller unaffected | **caller IS affected** |

Note the last row runs the *opposite* way: FPC copies for a value parameter and
we alias, while for assignment FPC aliases and we copy. Whatever is decided, those
two should end up consistent with each other.

## Why this is Track U and not a bug ticket

Both designs are coherent. FPC/Delphi dynamic arrays are refcounted **reference**
types with no copy-on-write — `b := a` aliases and only `Copy` detaches.
Copy-on-write *value* semantics (what pxx appears to do, and what `AnsiString`
genuinely does in both languages) is a defensible alternative, and this project
has deliberately chosen its own dialect before. Nothing in `docs/language/**` or
the dev docs states a decision either way; the only mention calls dynamic arrays
"managed", which is true under both models.

So this could be an intended dialect choice that was never written down, or an
unintended divergence. I cannot settle it from the code, and guessing would
either paper over a real bug or file a "fix" against a deliberate design.

## Options

1. **Match FPC — reference semantics.** Best for the mission of compiling
   real-world Pascal as-is: any ported code that relies on aliasing (passing a
   dynamic array around expecting the callee to see writes) is silently wrong
   today. Cost: a real codegen change, and it makes dynamic arrays behave
   differently from `string`, which surprises people the other way.
2. **Keep value/COW semantics and document it.** Cheaper, arguably safer
   (no spooky action at a distance), and consistent with `string`. Cost: an
   FPC-parity divergence in a core type, which is exactly the class of thing
   that makes ported code fail far from the cause. Would need a `compat-` note
   and a mention in `docs/language/**`.
3. **Match FPC and put value semantics behind a strict-mode-style flag** — the
   inverse of how `--strict-*` flags work today.

## Recommendation

**Option 1**, on mission grounds: "compile real-world code as-is" is the north
star, aliasing is observable, and a program that relies on it fails silently
rather than loudly. But the open-array-parameter row should be settled in the
same pass so the two stop contradicting each other.

Whichever way it goes, it wants writing down in `docs/language/**` — the absence
of any statement is what made this a question rather than a lookup.


## Evidence added 2026-08-05 (Track A) — it is NOT uniform across targets, and the machinery IS deliberate

A duplicate of this question was filed the next day as
`decide-dynarray-cow-vs-fpc-reference-semantics` before this ticket was found.
Merged here and the duplicate withdrawn; its evidence:

### Only x86-64 copies — the other five targets already alias

Measured, `b := a` then a write through each name:

| | after `b[0]:=77` | after `a[1]:=88` |
| --- | --- | --- |
| **FPC** | a[0]=77 (visible) | b[1]=88 (visible) |
| pxx i386 / arm32 / aarch64 / riscv32 | a[0]=77 | b[1]=88 |
| **pxx x86-64** | **a[0]=1** | **b[1]=2** |

So the divergence is one target, not the dialect. Reproduces with both plain
(`Integer`) and managed (`string`) element types, so it is not the
managed-element machinery. `pinned` behaves identically, so it is long-standing.

**That materially changes the cost of option 1**: "match FPC" is not a
whole-compiler change, it is removing the copy from ONE backend, and it brings
x86-64 into line with the five targets that already do what FPC does. Option 2
(keep COW) is the expensive one — it means implementing the copy on four more
backends.

### The COW is deliberate machinery, not an accident

- `IR_DYNUNIQUE` exists specifically to "load the data pointer on a read and
  clone-if-shared (copy-on-write) on a write, decided by `InLValueWrite`";
- `PXXDynArrayUnique` is its RTL half;
- `compiler/ir.inc` states the invariant outright: *"writing through one alias
  never mutates another at any depth."*

Meanwhile `ir_codegen_arm32.inc` says *"v1: no COW either way"* — so the cross
targets are not implementing a rival design, they simply have not implemented
this one. The split is an implementation gap sitting on top of an intentional
divergence, which is why it reads as a bug from either side.

### Recommendation unchanged, now cheaper

Option 1. Whoever takes it should measure the blast radius first — build the
corpora and `make test` with the x86-64 copy disabled — before committing.
`bug-a-x86-64-dynarray-assignment-copies-instead-of-aliasing` is the
implementation ticket and is already `blocked-by` this decision.
