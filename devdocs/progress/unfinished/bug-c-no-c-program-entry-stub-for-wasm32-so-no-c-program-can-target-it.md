---
slug: bug-c-no-c-program-entry-stub-for-wasm32-so-no-c-program-can-target-it
track: C
prio: 40
type: bug
blocked-by: []
owner: 
created: 2026-09-04
found-by: franks-ab (measured while checking whether its crtl signal bridge reached wasm32); filed by frankA
summary: "`--target=wasm32` on ANY C program fails at cparser.inc:11666 with `C program entry stub not implemented for this target yet`, on a trivial `int main(void){return 0;}`. So the whole C x wasm32 cell of the goal's languages-x-platforms product is empty, and every wasm32 measurement anyone has made is a Pascal-only measurement -- including this lane's corpus census, whose source list is Pascal-only for exactly this reason. The same shape was solved once for xtensa (done/bug-cfront-no-entry-stub-for-xtensa), but NOT the same work: xtensa needed five machine-code arms and wasm32 needs a synthesised `_start` wrapper, because wasm `_start` is [] -> [] while C `main` is (i32,i32) -> i32. UNBLOCKED 2026-09-06 -- wall 4 verified gone against its own symptom. Two walls remain and they block the two acceptance criteria SEPARATELY: wall 5 is that no entry export exists at all, and its failure is SILENT (a module with no `_start` runs nothing and exits 0 under wasmtime, which is indistinguishable from `int main(void){return 0;}` succeeding -- any test here must return NONZERO); wall 6 is that `va_arg` is unsupported on wasm32, which blocks <stdio.h> via lib/crtl/src/fcntl.c and is the case bug-c-the-32-bit-va-arg-set-is-complete-only-because-two-targets-cannot-compile-c-yet was filed to predict. Wall 5 alone buys freestanding C; printf needs wall 6."
status: unfinished
---

# No C entry stub for wasm32

Measured 2026-09-04 by franks-ab, checking whether its crtl signal bridge
(`baec9c0bd`) could be reached from C on wasm32. It cannot be reached from C on
wasm32 at all, and neither can anything else.

## Repro

```c
int main(void) { return 0; }
```

```
$ ./compiler/pascal26 --target=wasm32 t.c t.wasm
pascal26:5: error: C program entry stub not implemented for this target yet
```

`cparser.inc:11666`. Independently reproduced by this lane on a larger C
program (a time/exit probe) before the ticket was written -- same message, same
line, and it is the FIRST error, so nothing after it has ever been exercised.

## Why it is worth more than its size

The goal is languages **x** platforms, and this is an empty cell in the product,
not a missing feature in one axis. Everything C-shaped that has been made to
work on wasm32 has been made to work *through Pascal*.

It also silently scopes other people's numbers. This lane's wasm32 gap census
runs over a Pascal-only source list, because a C list would fail before codegen
on every row and land in the census's own "never measured" bucket. So "518
IR_SYSCALL refusals" and every figure derived from it is a claim about the
Pascal frontend on wasm32 and says nothing about the C one. That is not a defect
in the census; it is what the census can physically see.

## The precedent

`devdocs/progress/done/bug-cfront-no-entry-stub-for-xtensa` is the same shape on
the other odd target and was solved. Read that first: whoever takes this should
be checking whether the xtensa stub generalises rather than writing a third one,
because a per-target entry stub written three times is the shape that grows a
fourth.

wasm32 differs from xtensa in one way that matters to the design: a wasm module
has no ELF `_start`, it has a WASI `_start` export, and argv/envp come from
`args_get`/`environ_get` rather than off the stack. The Pascal driver already
does all of that -- `WasmEmitEntry` and the wasi backend's argv/environ path --
so the material exists; the question is whether the C driver can reuse it or
whether the two entry paths need normalising first
(`devdocs/dev/normalise-dont-special-case.md`).

## What would close it

`int main(void){return 0;}` exits 0 under wasmtime, and a C program that calls
`printf` prints. Then re-run the wasm32 gap census over a C source list and
report the denominator, because the current one cannot cover a single C source.

## Parked 2026-09-04 by frankA — four walls measured, and the fourth is not mine to fix here

Taken because it is the same shape as the xtensa stub, which I had just closed.
It is not: xtensa needed five per-target machine-code arms, and this needs the
wasm32 backend to change an assumption about what a function IS. Parking with
the walls named, so the next person starts at wall four rather than wall one.

Measured by putting a no-op `TARGET_WASM32:` arm in the entry-stub case at
`cparser.inc` and compiling `int main(void){return 0;}`, then removing each
refusal in turn. Every arm below was REVERTED — the tree is unchanged except for
the diagnostic in (3), which stands on its own.

**Wall 1 — `EmitCSetjmpStubs: unsupported target`.** Raw machine-code stubs; a
wasm module has no stack to longjmp across. The xtensa split guard is already
there (`if TargetArch <> TARGET_XTENSA`) and wasm32 joins it. Two identical
copies, both must change — the comment above them says why.

**Wall 2 — `EmitCReturnZeroStub: unsupported target`, reached through
`EmitCFenvStubs`.** Same reason: it emits bytes. wasm32 skips fenv entirely, and
that is an honest gap — a C program calling `fesetround` will not link.

**Wall 3 — `wasm: duplicate export "main$463"`.** The message named a collision
and left two very different causes indistinguishable: two bodies whose names
collided, or ONE body exported twice. I first fixed the wrong one — the chunk
namer builds `main$<chunk index>` and the body exporter disambiguates by
appending `$<slot>`, so the two namespaces genuinely overlap — and it changed
nothing, because that was not what was happening. **That namespace overlap is
real, is NOT what this was, and I could not construct a case that reaches it, so
I reverted the rename rather than leave a guard whose necessity was never
shown.** What DID land is `wasmenc.inc` separating the two causes in the
message; it is what turned an hour of guessing into one reading.

**Wall 4 — the real one.**
[[bug-a-wasm32-emits-a-separate-function-per-compileast-call-so-a-proc-built-in-two-calls-loses-a-body]].
C's `main` is built in THREE `CompileAST` calls (`CompilePendingGlobalInits`,
`CEmitDeferredCAggInits`, then the body) and wasm32 makes one wasm function per
call, all claiming main's slot. That ticket is filed at prio 70 because it is
NOT about C at all: `procedure Fill(out s: string)` already prints `[KEEPXY]` on
wasm32 against `[XY]` on the five register targets, silently, today.

**Landing this stub before wall 4 would produce a C program that builds, runs,
and silently drops its global initialisers.** That is worse than the refusal it
replaces, so this ticket is `blocked-by` it rather than merely later than it.

Not investigated past wall 4, and it should not be assumed there are only four:
each was found only by removing the one in front of it, which is the same
counting problem the xtensa ticket had. argc/argv is a known fifth — WASI has no
initial stack, `WasmEmitArgvFetch` exists for the Pascal side and depends on
`PXXAlloc`, which a C program does not necessarily link.

Unclaimed again; `owner:` cleared.

## Parked 2026-09-04

blocked on the wasm32 one-function-per-CompileAST bug: four walls measured, the fourth needs the backend to change what a function is, and landing the stub before it would silently drop C global initialisers

**Before resuming:** read the reason above, then the ticket body. If the reason does not tell you what would make this worth picking up again, establishing that is the first step -- a park is a handoff to a stranger who may be you.

## 2026-09-06 (frankC): wall 4 IS gone — verified against its own symptom — and walls 5 and 6 are named

Wall 4 was resolved by frankwasm (`460f439f6`, `cf23cfaf0`). **Confirmed here
rather than inherited**, because a resolved blocker is the thing most often read
as more progress than it was. Checked against wall 4's OWN symptom, the one its
ticket names, not against "the C program gets further":

```pascal
procedure Fill(out s: string);
begin s := s + 'X'; s := s + 'Y'; end;
...  t := 'KEEP'; Fill(t); writeln('[', t, ']');
```

| | |
| --- | --- |
| native | `[XY]` |
| wasm32, before | `[KEEPXY]` (the ticket's recorded value) |
| **wasm32, now** | **`[XY]`** |

The probe is chosen so the fixed answer DIFFERS from the broken one and from an
empty result; `[XY]` cannot be produced by the bug.

### The walls now, re-walked with frankA's method (a no-op `TARGET_WASM32:` arm, reverted)

Walls 1 and 2 are as frankA left them and remain honest gaps: `EmitCSetjmpStubs`
and `EmitCFenvStubs` emit machine code, wasm32 skips both, and a C program
calling `fesetround` or `setjmp` will not link. **Both copies of the guard must
move together** — the comment above them says so, and the probe's assertion
caught me editing one (`count == 2`, not 1).

Wall 3 is gone with wall 4. With the no-op arm the program COMPILES.

**Wall 5 — there is no entry export, and the failure is SILENT.** The module
exports `main` (C's own function) and no `_start`. Measured:

```
$ wasmtime <module exporting only "main">   -> rc=0, runs nothing
$ ./pascal26 --target=wasm32 t42.c t42.wasm && wasmtime t42.wasm
rc=0                                        # the program says return 42
```

**`int main(void){return 0;}` exiting 0 is exactly what a module that never ran
also does** — the ticket's own first acceptance criterion cannot tell them
apart, and I nearly recorded the no-op arm as a success on it. Any test for this
must return NONZERO. wasm `_start` is `[] -> []` while C's `main` is
`(i32,i32) -> i32`, so exporting main twice is not available; a wrapper is
required, as `WasmEmitMainWrapper` already is for Pascal.

*The material for it exists and is located*: `WasmEmitArgvFetch` (WASI
`args_sizes_get`/`args_get`, allocates via `PXXAlloc`), `WasmSlotForProc`,
`WasmAddExport`, and the `proc_exit` import. The shape is a `[] -> []` function
that runs initialisers, fetches argv, calls main, runs finalizers and
`proc_exit`s the result — the same five steps every machine-code arm does.

**Wall 6 — `va_arg` is unsupported on wasm32, and it blocks the ticket's SECOND
acceptance criterion.** `#include <stdio.h>` pulls crtl, and `lib/crtl/src/fcntl.c`
uses `va_arg` for `open`/`openat`:

```
pascal26:32: error: variadic C functions (va_arg) are not yet supported on this cross target
  in: ./compiler/../lib/crtl/src/fcntl.c
```

This is [[bug-c-the-32-bit-va-arg-set-is-complete-only-because-two-targets-cannot-compile-c-yet]],
and wasm32 is one of the two targets that ticket is named for. **So it is not a
new wall — it is the one that ticket predicted would surface exactly here.**

**And it is already guarded.** `tools/c_va_arg_every_target.sh` lists wasm32,
examines 7 targets, and separates "wasm32 refused at the C entry stub" (expected,
outside the check by construction) from "wasm32 refused for a NEW reason". With
the no-op arm in place it failed by name:

```
FAIL - wasm32 refused for a reason that is NOT the C entry stub, so this check
silently stopped covering it: ... va_arg ... not yet supported
```

That ticket's stated defence was *"a written instruction to whoever implements
the missing entry stub"*. It is not a written instruction any more; it fires.
Whoever lands wall 5 will be told the same day, and **the check going red at
that moment is correct** — it must be answered by implementing wasm32 va_arg or
by re-stating its expectation against that ticket, not by lowering the floor.

### What this changes for whoever takes it

Start at wall 5, not wall 1. Wall 5 alone buys freestanding C on wasm32 —
honest, and enough to empty the "no C program can target it" claim — but it does
NOT buy `printf`, because wall 6 sits in front of crtl. The two acceptance
criteria in this ticket are therefore **separately blocked** and only the first
is reachable without touching the va_arg lowering.

Probe reverted; tree unchanged. Binary back to `f2f11cd439e7`, refusal
reproduced, `c_va_arg_every_target.sh` green at `6 built, 1 awaiting a C entry
stub, 7 examined`.
