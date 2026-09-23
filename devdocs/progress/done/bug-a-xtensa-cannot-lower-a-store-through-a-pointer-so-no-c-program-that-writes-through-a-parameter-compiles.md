---
slug: bug-a-xtensa-cannot-lower-a-store-through-a-pointer-so-no-c-program-that-writes-through-a-parameter-compiles
title: "xtensa: a store through a pointer is IR_UNSUPPORTED (AN_BINOP), so no C program that writes through a pointer parameter compiles"
track: A
prio: 60
type: bug
status: done
created: 2026-09-22
found-by: frankb-8e
owner:
blocked-by: []
summary: "FIXED 2026-09-23. NOT an xtensa codegen bug and not about the store: `LastTypePointerElemArrAi` is documented `else -1` and is a zero-initialised Pascal global, and 0 is a VALID ArrType row -- the same default/sentinel collision the four Alloc* sites already spell out. Only ParseTypeKindInner ever assigns it, so a compile that parses NO Pascal type runs holding 0, SetPtrElemArrayInfo reads row 0 for every pointer symbol, and CDerefDecayStride then takes every `*p` for the no-op deref of a pointer-to-ARRAY and rewrites it to `p + 0`. Every other target parses the RTL first and is left holding -1 BY ACCIDENT, which is the whole reason it looked target-specific -- `--no-default-rtl` reproduces it on riscv32. THE REFUSAL WAS THE SAFE HALF: a store through `p + 0` cannot lower as an lvalue and stops, but a READ lowers fine and yields THE POINTER, so `char g(char *d){ return *d; }` compiled on xtensa and returned the address -- this ticket recorded that row as `ok`. Kind 5 is AN_BINOP with ival=70 (tkPlus), NOT the assignment form (that is AN_COMPOUND_ASSIGN=70, a different number that reads alike). Fix is two lines in compiler.pas's init block. Pascal was never affected, measured: a Pascal compile always parses a Pascal type."
---

# Reduction

```c
char *f(char *d){ *d = 0; return d; }     /* xtensa: IR_UNSUPPORTED kind 5 */
char  g(char *d){ return *d; }            /* xtensa: ok */
```

| shape | xtensa | riscv32 |
| --- | --- | --- |
| `*d = 0` (char store through a param) | **IR_UNSUPPORTED kind 5** | ok |
| `*d = 65` (non-zero) | **IR_UNSUPPORTED kind 5** | ok |
| `d++; *d = 0` | **IR_UNSUPPORTED kind 5** | ok |
| `void f(char *d){ *d = 0; }` (result unused) | **IR_UNSUPPORTED kind 5** | ok |
| `int *f(int *d){ *d = 0; ... }` | **IR_UNSUPPORTED kind 5** | ok |
| `return *d` (read, same parameter) | ok | ok |

So: the STORE, any width, whether or not the value or the pointer is used
afterwards. Not the dereference, not the constant, not `char`.

`AN_BINOP = 5` (`defs.inc:745`) is the C frontend's assignment-expression node.
The lowering that handles it is reached on riscv32 and not on xtensa, which
says the store path branches on target somewhere it should not — the two ESP
backends are otherwise the pair that share this shape.

# What it costs today

`lib/crtl/src/string.c:188` is `*d = '\0'` in `strncat`. Compiling that file
alone for xtensa refuses at 188, so every xtensa C program that pulls crtl in
refuses at the same line — measured with `strlen`, `puts` and `printf`, each
of which resolves to a crtl implementation. A program that calls only its own
functions, or declares an external pxx does not implement, compiles.

**The line number is the imported unit's and carries no file name**, which is
the usual trap: three unrelated programs all report `pascal26:188` and it reads
as one shared cause in the SUBJECT. It is one shared cause, in `string.c`.

# Why it has stayed invisible

`--target=xtensa` refuses a C *executable* outright (`C program entry stub on
xtensa: a STANDALONE ...`), so `--emit-obj` is the only C route on xtensa, and
nothing in the tier drives an xtensa C object that calls libc. The ESP rows in
`test-emit-obj` build Pascal.

**Whether the Pascal frontend has the same gap is NOT measured here.** The
reduction and the whole table above are C. Someone should check before assuming
this is C-only.

# Found by

Writing an xtensa probe for
[[feature-a-a-target-generic-resolve-and-compare-harness-for-emit-obj-objects]].
The harness printed `SKIP -- pxx cannot emit an object here` with the compiler's
own diagnostic rather than passing over the target, which is the only reason it
was seen. Filed rather than routed past, so the next person to write an xtensa
probe does not rediscover it.

# Umbrella

[[meta-a-pxx-produces-linkable-code]]

# Resolution (2026-09-23, frank)

**Two lines in `compiler.pas`'s init block. The diagnosis in the body above was
sound about the symptom and wrong about the subsystem in two ways worth
recording, because both were reasonable readings.**

## What it actually was

`LastTypePointerElemArrAi` (`defs.inc:5586`) documents itself as *"that ArrType
index, else -1"*. It is a plain Pascal global, so it starts at **0** — and 0 is
a valid `ArrType` row. The four `Alloc*` sites already carry the comment
*"-1, not 0: zero is a VALID ArrType row"*, so this collision was known and
guarded at every site that WRITES a symbol. It was unguarded at the one place
nobody looks: **before anything has been parsed at all.**

Only `ParseTypeKindInner` assigns it. So:

- a compile that parses **no Pascal type** holds 0 the whole way;
- every allocator calls `SetPtrElemArrayInfo`, whose guard is
  `if LastTypePointerElemArrAi < 0 then Exit` — 0 passes it;
- so every pointer symbol is recorded as pointing at `ArrType` row 0, giving
  `ptrElemArrLen=1`;
- `CDerefDecayStride` then reads that and takes every `*p` for the **no-op
  deref of a pointer-to-array**, rewriting it to `p + 0`.

Measured with `PXXDBG=a.symptr:d` — xtensa `ptrElemArrAi=0 ptrElemArrLen=1`,
riscv32 `ptrElemArrAi=-1 ptrElemArrLen=0` — and `PXXDBG=a.ast:f`, where xtensa
built `AN_BINOP(5) ival=70` over `AN_IDENT` + `AN_INT_LIT 0` and riscv32 built
`AN_DEREF(36)`.

## Correction 1 — it is not an xtensa bug, and the ticket could not have known

**`--no-default-rtl` reproduces it on riscv32**, under the pinned compiler.
Every other target parses the RTL first and is left holding -1 **by accident**.
The condition is *"this translation unit pulled no Pascal unit in"*, and xtensa
is merely where that is the normal case.

The control that settles it costs one command and is already in the tree:
**`esp32c3`/`esp32c6` are the ESP platform on riscv32 and they compile fine**
(538 procs), while `esp32`/`esp32s3`/`xtensa` refuse. So it is the arch's
prelude, not the ESP profile — which also means
`bug-s-c-on-the-esp-profile-cannot-reach-crtl` is a **separate** cause and not
a duplicate of this one.

## Correction 2 — the refusal was the SAFE half, and this ticket recorded the
## dangerous half as a passing row

The table above has `return *d` (read, same parameter) → **ok** on xtensa, and
concludes *"So: the STORE, any width"*. The read does compile, and it is
**wrong**: `*d` had already become `p + 0`, so `char g(char *d){ return *d; }`
returned **the pointer**, truncated to `char`. A store through `p + 0` cannot
lower as an lvalue so it refused loudly; the read had nothing to refuse.

That is the expensive shape — a plausible wrong value far from its cause — and
it was sitting in the ticket as evidence of where the bug *was not*.

## Correction 3 — kind 5 is not the assignment form

The body reads `AN_BINOP = 5` as *"the C frontend's assignment-expression
node"*. It is not: the assignment expression is `AN_COMPOUND_ASSIGN = 70`.
`ival=70` on the failing node is the **operator token**, `tkPlus`. Two 70s that
mean different things, one of which is in the other's field — worth a line
because the coincidence reads as confirmation.

## Pascal — the ticket's own open question, now measured

Not affected, before or after: a Pascal compile always parses a Pascal type, so
the global always reaches its `-1`. Checked on xtensa and riscv32 under both
the pinned and the HEAD compiler.

## Tests

`test/c_store_and_read_through_a_pointer_param.c` (values, checked twice per
read with the pointer fixed and the value moved, so a broken read cannot
collide with the expected number) and
`test/c_read_through_a_pointer_param_is_a_load.c` (reads only, so the unfixed
compiler gets far enough to print the defect instead of dying at the first
store). Eight rows in `test-emit-obj`.

**Four of the eight are proven to fail under pinned v416** — the two `--emit-obj`
compiles with the real `IR_UNSUPPORTED`, and the two structural rows with a real
`MISMATCH` on `kind=5 ival=70` against `kind=36`. **The other four pass under
the pin and the Makefile says so beside them**: the default target's prelude
masks the defect, so the native value rows guard the semantics and are NOT a
control for this bug. The structural rows exist because a fix that special-cased
the lvalue path would green every compile row and leave the read answering an
address.

Full `test-emit-obj` GREEN, `gate.sh quick` GREEN, fixedpoint converged.

## Log
- 2026-09-23 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit ffe495ab6.
