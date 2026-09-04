---
slug: bug-c-no-c-program-entry-stub-for-wasm32-so-no-c-program-can-target-it
track: C
prio: 40
type: bug
blocked-by: [bug-a-wasm32-emits-a-separate-function-per-compileast-call-so-a-proc-built-in-two-calls-loses-a-body]
owner: 
created: 2026-09-04
found-by: franks-ab (measured while checking whether its crtl signal bridge reached wasm32); filed by frankA
summary: "`--target=wasm32` on ANY C program fails at cparser.inc:11666 with `C program entry stub not implemented for this target yet`, on a trivial `int main(void){return 0;}`. So the whole C x wasm32 cell of the goal's languages-x-platforms product is empty, and every wasm32 measurement anyone has made is a Pascal-only measurement -- including this lane's corpus census, whose source list is Pascal-only for exactly this reason. The same shape was solved once for xtensa (done/bug-cfront-no-entry-stub-for-xtensa), so this is a known pattern with a worked precedent, not new ground."
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
