---
slug: bug-c-hosted-c-on-wasm32-needs-environ-and-va-arg-so-stdio-programs-still-refuse
track: C
type: bug
prio: 40
status: open
found: 2026-09-06
found-by: frankC
owner: ""
blocked-by: []
summary: "**WALL B (va_arg) IS DONE 2026-09-19 (frankB) and is NOT inert -- it is RUN.** wasm32 now defines, calls and reads a C variadic function: the caller marshals the tail into a shadow-stack area (packed 4-byte slots, an 8-byte scalar taking two, no 8-alignment -- the layout __pxx_va_arg_cross32 already walks for i386-cdecl) and hands it over as a trailing i32 reserved at index ParamCount, before the aggregate-dest slot; the callee stores it into __va_overflow at body entry, where the parameter locals exist. NO NEW READER: wasm32 joined the four 32-bit sets in cparser.inc with reg-save size 0, like i386. VERIFIED BY RUNNING IT: test/c_wasm32_variadic.c exercises five shapes -- 3 ints, 4/8/8 interleaved twice, an EMPTY tail, a variadic call nested INSIDE a variadic tail, and five named params before the tail -- and exits 42 under both gcc and wasmtime, with a positive control (two expectations perturbed -> 18) and a negative control (the pinned compiler refuses the same source). 61 wasm32 sources unchanged: 60 compile, one carries the pre-existing main$0 gap with identical text, one unrelated SetSignalHandler refusal. NOT done on purpose: an aggregate in the variadic tail is REFUSED by name (cparser reads it as a pointer here, so marshalling the bytes would validate and round-trip wrong), and WasmEmitCallInd is untouched so an INDIRECT variadic call still hits the old `passes more than its N parameters`. **THE REMAINING WALLS ARE TWO AND NEITHER IS ABOUT VARIADICS.** Re-measured the same day: hosted printf now dies at MAX_WASM_BODY_VARS=288 in crtl stdio.c; raising that to 2048 gets a whole MODULE and wasmtime then refuses to instantiate on exactly ONE unresolved import of eighteen (seventeen are WASI) -- __pxx_fegetround, which EmitCFenvStubs emits as raw machine code and cannot for a target that has none. **So do not raise the bound alone**: it trades a named COMPILE refusal for a link failure at instantiation, which is later and worse. The raise and a wasm32 fenv stub land together. Both probes reverted, compiler rebuilt byte-identical to f104f4b22922. Wall A (environ) is still INERT and still unasserted -- run a getenv program the day those two land."
---

# Hosted C on wasm32: environ and va_arg

The entry is done and is not the issue any more. See
`done/bug-c-no-c-program-entry-stub-for-wasm32-so-no-c-program-can-target-it`
for the wrapper, and for why every test of it asserts a NONZERO exit code.

## What works today

```
$ ./compiler/pascal26 --target=wasm32 t.c t.wasm && wasmtime t.wasm; echo $?
42                                    # int main(void){return 42;}
```

`argc`/`argv` are live through WASI `args_get` (`return argc` gives 1 bare and
3 with two arguments; `argv[0][0]` is a real character). `void main` runs.
`tools/c_wasm32_entry.sh` is the check.

## Wall A — `environ`, and it is wider than its name

`__pxx_run_initializers` takes the INITIAL STACK POINTER and walks it to find
envp. WASI has no initial stack; it reports the environment through
`environ_get`. There is no value that could be passed, so the C driver refuses.

**The refusal is not narrow, and the first version of its comment said it was.**
`CNeedsEnvironInit` is a token scan over the whole stream, and the stream
includes the crtl the program pulls — `lib/crtl/src/unistd.c` and `stdlib.c`
both name `environ`. It cannot tell a declaration from a use. Measured:

| header | result |
| --- | --- |
| `stdarg.h`, `string.h` | compile |
| `stdlib.h`, `stdio.h`, `unistd.h`, `math.h` | refused |

So essentially every non-trivial C program trips it.

**Refusing is still the right direction** and the alternative was considered:
xtensa takes the other road (`CNeedsEnvironInit` exits early for it), which is
right THERE because ESP genuinely has no environment to report. WASI HAS one, so
silently answering "empty" would be wrong about a fact the host would have told
us — and a wrong `environ` is a wrong answer no test distinguishes from a right
one, while a refusal is visible immediately.

**The fix is to wire `environ_get`**, which makes the refusal unnecessary rather
than narrower. A WASI initializer that fills `environ` from `environ_sizes_get`
+ `environ_get` is the same shape as `WasmEmitArgvFetch`, which already does
exactly this for argv and can be read as the worked example.

## Wall B — `va_arg` on wasm32

```
pascal26:32: error: variadic C functions (va_arg) are not yet supported on this cross target
  in: ./compiler/../lib/crtl/src/fcntl.c
```

`open`/`openat` are variadic. This is
[[bug-c-the-32-bit-va-arg-set-is-complete-only-because-two-targets-cannot-compile-c-yet]]
reaching the target it was filed to predict, and **it is guarded**:
`tools/c_va_arg_every_target.sh` lists wasm32 and admits exactly two named
refusals — the entry stub (historical) and this environ wall. A va_arg refusal
there FAILS the check, deliberately: it would mean wall A is fixed and wasm32
should now be covered.

## Order

A before B. B is behind A for every program that would exercise it, because
reaching `fcntl.c` requires a header that trips A first. Doing B alone changes
no observable.

## Wall C — `MAX_WASM_BODY_VARS = 288`, and it was invisible until A came out

Found only by removing wall A, which is the point of this section: **a wall
behind a wall is not merely unmeasured, it is unmeasurABLE, and the count of
walls was wrong in the direction that flatters the estimate.** This ticket said
"two" with confidence for a day.

```
pascal26:91: error: wasm: too many params+locals
  in: ./compiler/../lib/crtl/src/stdio.c
```

`wasmenc.inc:87`, `MAX_WASM_BODY_VARS = 288`, a fixed array bound on
params+locals per body. Raising it to 2048 locally moved the failure from
`stdio.c` to `fcntl.c`'s va_arg, which is how B and C were separated at all
rather than one being reported as "the" wall.

**Not raised in that commit, deliberately.** It is the wasm backend's bound and
the number wants an owner who knows what it costs — BSS grew ~16KB at 2048 in
the local probe, which is nothing, but the choice is not this arm's to make.
The revert was verified the strongest available way: the compiler rebuilt to
the byte-identical `63f56a42bef6` it had before the probe.

## Order, corrected

**A, then C, then B** — and the old "A before B" line was right about A and
silent about the wall it could not see. C (the bound) is hit first by any
program that pulls stdio; B (va_arg) is behind it. Both are now reachable and
measurable, which they were not this morning.

## Wall A is done — what landed, and what it does NOT claim

`63d077feb`. `WasmEmitEnvironFetch` in `ir_codegen_wasm32.inc`, called from
`WasmEmitCEntry` before `main`; `ParseCProgram`'s `TARGET_WASM32` arm records
the request and resolves `__pxx_set_environ` at the tail (crtl is not pulled
until after that arm, so `FindProc` answers -1 up there for every program).

Two differences from `WasmEmitArgvFetch`, both correctness and neither
spelling, written up in the function's own header:

- **The vector is NULL-terminated and argv's is not asked to be.** WASI writes
  exactly `count` pointers for either call. argv survives that because argc is
  carried separately; `environ` has no count at all and every reader walks to a
  NULL the host never wrote. So the block holds `count + 1` pointers and
  `vec[count]` is stored as 0.
- **The block is never freed.** `environ` points into it for the life of the
  program.

**IT HAS NEVER RUN.** Nothing can reach it until C and B land. It is inert
rather than untested — `WasmCEntryEnvp` stays -1 for every program that
compiles today — and that was verified rather than asserted: the two wasm32 C
programs that DO compile are unchanged across the commit (`return 42` exits 42,
argc/argv exits 31). **Do not close this ticket, or quote the notes, as
"environ works on wasm32".** The first thing to do when C and B land is to run
a program that reads `getenv` and check the value, because that assertion has
never been made.

## The cost that was taken, and should be taken back

The old refusal was a sentence written for a C author. What a user naming
`environ` gets now is `wasm: too many params+locals` — a compiler-internal
message that is about the true obstacle. That is a real regression in message
quality, accepted because the old text named a wall that was not the wall.
**Take it back when C and B land**; until then both replacements at least name
the crtl file they come from, so a reader can tell it is our runtime rather
than their program.

## The guard moved with it, and caught the move

`tools/c_va_arg_every_target.sh` failed the moment A landed — *"wasm32 refused
for a reason that is NEITHER the C entry stub NOR the environ wall"* — because
removing A moved wasm32's refusal onto va_arg itself. That is the script
working, and the fix was to follow the wall rather than loosen the check: the
admitted set is now `{entry stub, va_arg-by-name}` and **the environ spelling
was DELETED rather than kept "just in case"**, since no target can produce it
any more and an admissible reason that cannot occur is dead tolerance that
reads as coverage. Still `6 built, 1 refused at a named wall, 7 examined`.

Note what a va_arg refusal there means: it is the *safe* direction. The danger
the script exists for is a C-capable target missing from `cparser.inc`'s four
sets, which falls into the `TargetArch <> TARGET_X86_64` arm, silently takes
aarch64's 8-byte two-bank layout, and prints wrong values from the second
argument on.

## Still true and easy to lose

Freestanding C on wasm32 works and `tools/c_wasm32_entry.sh` is the guard. Do
not let a wall-B or wall-C attempt regress it; its rows are all
nonzero-expecting for a reason written at the top of that file.

## RE-SCOPED 2026-09-16 (frankb-56) — it is NOT a missing prologue arm; BOTH SIDES are missing

This ticket (and its sibling
[[bug-c-the-32-bit-va-arg-set-is-complete-only-because-two-targets-cannot-compile-c-yet]])
says the obligation belongs to *"whoever adds a wasm32 PROLOGUE arm"*. Measured
at HEAD (`b7f9f80c7d80`) with two probes chosen to reach one side each, that is
half the job and the smaller half.

**Callee side**, a variadic function DEFINED in the TU:

```
pascal26:2: error: variadic C functions (va_arg) are not yet supported on this cross target
```

**Caller side**, a variadic function CALLED and not defined — and this is the
one nobody has recorded:

```
wasm32: 476 of 477 bodies lowered; 1 emitted as `unreachable`; 1 distinct gap(s) seen
    main — call to pxx_probe_va passes more than its 1 parameters
```

A wasm function has a FIXED typed signature, so "pass three arguments to a
function declared with one" has no encoding at all. The caller cannot marshal
what the callee cannot receive, and neither end exists today.

### Why the existing framing missed it, and it is a probe-route problem

The obvious probe is `printf("%d", x)`. On wasm32 that dies FIRST at

```
pascal26:91: error: wasm: too many params+locals
  in: ./compiler/../lib/crtl/src/stdio.c
```

— **wall B, an unrelated bound** (`MAX_WASM_BODY_VARS`), reached because
`printf` pulls crtl's `stdio.c` in. So the natural caller-side probe never
reaches the caller-side gap and misattributes it to wall B. The isolating probe
is a variadic `extern` that is NOT a crtl function, so nothing is pulled and the
only route to the refusal is the variadic call itself. CLAUDE.md, *"does my
probe reach the thing under test BY THE ROUTE under test, and by no other?"*

### And the caller-side gap is NOT a build failure

`vacall2.wasm` was **written, 116955 bytes**, with the offending body lowered to
`unreachable`. The build "succeeds"; the module validates; it traps when that
body runs. So a variadic call on wasm32 today is a RUNTIME trap reported in a
summary line, not a compile error — which is a different and quieter failure
mode than the callee side's hard `Error`.

### What the work actually is

wasm32 has no argument registers AND no addressable incoming stack, so the
six existing arms (spill registers, point `__va_overflow` at the incoming
frame) have nothing to port. It needs a **convention designed for the target**:
the caller marshals variadic arguments into linear memory — the backend already
has a linear-memory frame stack (`devdocs/dev/wasm-target-findings.md`, "the
shadow stack has no guard page") — and passes one pointer, which becomes the
`va_list`. We control both ends, so there is no external ABI to match and the
layout is ours to choose; matching clang's wasm32 convention is optional and
worth deciding deliberately rather than by default.

Consequently `vaRegSz = 0` for wasm32 is correct and insufficient, and the four
consumer-set sites still must not be widened until a producer exists — the
sibling's own warning, which stands.

# MEASURED 2026-09-19 (frankB) — the ORDER is stale: C is no longer reachable, B is the only wall

**Not worked, re-measured.** This ticket's corrected order — *"A, then C, then
B"* — was true on 2026-09-06 and is false at HEAD (`402d61e0d`). Wall C is not
the next step; it is **behind** wall B and cannot be measured at all today.

## What HEAD actually does

```
$ ./compiler/pascal26 --target=wasm32 hello.c hello.wasm     # printf hello world
pascal26:32: error: variadic C functions (va_arg) are not yet supported on this cross target
  in: ./compiler/../lib/crtl/src/fcntl.c
```

Not `wasm: too many params+locals`. And it is not just `fcntl.c` — compiled
**alone** for wasm32, every crtl file this ticket names dies at the same wall:

| crtl file | rc | first wall at HEAD |
| --- | --- | --- |
| `stdio.c` | 1 | va_arg |
| `fcntl.c` | 1 | va_arg |
| `unistd.c` | 1 | va_arg |
| `stdlib.c` | 1 | va_arg |

`stdio.c` is the one this ticket recorded as the params+locals case, and it now
refuses for va_arg before the encoder ever runs — which is the shape to expect,
since **va_arg refuses at PARSE time and the bound fails at ENCODE time**, and
`stdio.c` defines the `printf` family, i.e. its own variadic callees.

## The null result, with the expectation recorded BEFORE the run

Predicted: raising the bound changes no observable, because va_arg fires first.
Measured, `MAX_WASM_BODY_VARS` 288 -> 2048, full rebuild:

| subject | at 288 | at 2048 |
| --- | --- | --- |
| `stdio.c` / `fcntl.c` / `unistd.c` / `stdlib.c` | va_arg | **va_arg** |
| hosted `printf` program | va_arg | **va_arg** |

**Zero observables moved.** The probe was reverted and the compiler rebuilt to
the byte-identical `cc3113bf07f5` it had before — the same verification this
ticket's own 09-06 probe used.

**So do not raise the bound as "the next step".** It costs a commit, moves
nothing, and produces exactly the null row this repo has burned five of. The
cost if someone does want it later is small and is arithmetic from the
declarations rather than a guess: the bound sizes `WFLoc` (1 byte/entry) and
`WFVar` (an AnsiString handle, 8), so 288 -> 2048 is (2048-288)*9 = **15,840
bytes** of compiler BSS, against 86.9 MB already. The number was never the
obstacle; reachability is.

Whether wall C is still real at all is now **unknown and unmeasurable** —
exactly the condition this ticket named in its own Wall C section (*"a wall
behind a wall is not merely unmeasured, it is unmeasurABLE"*). It has simply
changed which wall is in front. Re-measure C after B lands; do not assume it
is still there, and do not assume it is gone.

## Wall B is the whole remaining job, and it is an ABI design

Scoped at HEAD rather than estimated. The callee-side prologue is a per-target
arm at `cparser.inc:14582` that spills **argument registers** into `__va_save`
and points `__va_overflow` at the incoming stack frame (`vaRegSz` is 16 on
arm32, 32 on riscv32, 24 on xtensa, 0 elsewhere). **wasm32 has no argument
registers and no addressable incoming frame, so not one of those arms ports.**
And the caller side needs its own mechanism: a wasm function has a FIXED typed
signature, so "pass three arguments to a function declared with one" has no
encoding — the caller must marshal into linear memory and pass one pointer.
Both ends have to be designed together, and we own both, so there is no
external ABI to match (matching clang's wasm32 convention is a deliberate
choice, not a default).

That is a designed convention plus backend work, not ordinary work, and it is
the only thing standing between here and hosted C on wasm32.

## And the caller side still fails SILENTLY — same class as the `__thread` bug

Re-confirmed at HEAD, the 2026-09-16 finding, unchanged:

```
$ ./compiler/pascal26 --target=wasm32 vacall.c vacall.wasm ; echo $?
wasm32: 478 of 479 bodies lowered; 1 emitted as `unreachable`; 1 distinct gap(s) seen
    main — call to pxx_probe_va passes more than its 1 parameters
ok: .../vacall.wasm  [code=15627B ...]
0
```

**`ok:`, exit 0, a 117 KB module written — whose `main` traps when run.** That
is a green build of a program that cannot execute, which is the same defect
class as
[[bug-c-a-thread-declaration-that-does-not-fit-the-tls-area-becomes-a-shared-global-with-only-a-warning]]
(resolved today): compiles, says ok, wrong at runtime.

**Deliberately NOT changed here, and the reason is topic ownership rather than
doubt.** The `unreachable` floor is the wasm backend's own partial-lowering
instrument — the "N of M bodies lowered" line is how that work is tracked — and
its exit-code policy is that backend's to set, not this ticket's. Measured
blast radius if anyone does take it: of the 61 wasm32 sources named in the
Makefile, **59 compile clean, 1 fails for an unrelated reason
(`test_setsignalhandler_call.pas`, no signal runtime), and exactly ONE emits a
gap — `test/test_wasm32_two_gaps_in_one_body.pas`, the test that exists to
exercise the mechanism.** Its unreachable body is `main$0`, so "fatal when the
ENTRY body is unreachable" would red that test too; any change here has to
decide what that test should then assert.

## Summary of what changed on this ticket

Nothing in the tree. What changed is the map: **B is the only reachable wall, C
is behind it and unmeasurable, and the bound is not worth raising until B
lands.**


## WORKED 2026-09-19 (frankB) — wall B is DONE, and the wall count was wrong again

`tools/gate.sh quick` GREEN, compiler `f104f4b22922`, `converged after 1 round(s)`.

### The convention, and why it needed no new reader

Every other target lets the callee FIND its variadic tail: spill the argument
registers into `__va_save`, anchor `__va_overflow` at the incoming frame.
wasm32 has neither — parameters arrive as typed locals, there is no register
file and no addressable incoming frame — so the tail is **handed over** instead.

- `WasmSigForProcSelf` reserves one trailing `i32` for `ProcVariadic[p]`, at
  index exactly `ParamCount`, **before** the aggregate-destination slot. Every
  site computes the index the same way without asking which of the two trailing
  parameters is present.
- `WasmEmitCall` emits the named arguments, then `WasmVaAreaPush` sizes the tail
  in one pass, moves `$sp` once, stores each argument at its slot in a second
  pass, and leaves the area address on the stack as the final argument.
  `WasmVaAreaPop` adds the size back after the call. Both sequences are
  net-zero on the operand stack, which is why they can run with the named
  values — and the call's result — sitting underneath.
- Body entry stores the parameter into `__va_overflow`
  (`ProcVaOverflowSym[CurProc]`), the one place the parameter locals and the
  frame slots are both in scope. `__va_save` is deliberately untouched: the
  reg-save area is size 0 here.
- `cparser.inc`'s four `TargetArch in [...]` sets gained `TARGET_WASM32`.
  `vaRegSz` falls through to 0 and the slot alignment to 4, so the target reads
  through `__pxx_va_arg_cross32`'s overflow walk exactly as i386-cdecl does.
  **That reuse is the entire reason this is one commit and not a sixth reader.**

### The shadow stack, not a per-body buffer

One reserved area per body is one address per body, so
`printf("%d", snprintf(...))` — an inner variadic call inside the outer's
**second pass** — would marshal over arguments still live. A push nests by
construction, and the scratch local is taken from a depth-indexed pool
(`WASM_VA_DEPTH = 8`, exceeding it refuses by name). A variadic call in a
**named** argument position does not nest: it completes before the outer push.

### What the five-shape fixture is for

`sum3(3, 10, 20, 12)` alone passes under a packed layout, under an 8-aligned
one, and under a backend that pinned the area to a fixed position. The four
other rows are the arrangements that differ: 4/8/8 interleaved twice (packing),
an empty tail (the anchor still has to arrive), a nested variadic call (the
scratch pool), and five named parameters before the tail (the index really is
`ParamCount`). gcc is the oracle; the all-pass answer is **42 and not 0**,
because a module with no `_start` is instantiated, runs nothing and exits 0.

Positive control: perturbing two expectations gives exit 18 = 2|16.
Negative control: the pinned compiler refuses the same source at `va_list`.

### The wall count was wrong in the flattering direction, for the second time

This ticket has now been wrong about how many walls are left **twice**, both
times because a wall behind a wall is unmeasurable rather than merely
unmeasured. With B closed:

| wall | where | status |
| --- | --- | --- |
| A — `environ` | `WasmEmitEnvironFetch` | built, **never executed** |
| B — `va_arg` | this commit | **done, and run** |
| C — `MAX_WASM_BODY_VARS = 288` | `wasmenc.inc:87`, hit in crtl `stdio.c` | open |
| D — `__pxx_fegetround` | `EmitCFenvStubs` emits raw machine code | open, **new** |

D was found by raising C to 2048 and rebuilding: `#include <stdio.h>` +
`printf` then produces a module, and `wasmtime` refuses to instantiate it on
one unresolved import. `wasm-objdump -j Import -x` says eighteen imports,
seventeen `wasi_snapshot_preview1`, one `libc.so.6.__pxx_fegetround`.

**C alone is not an improvement.** Raising the bound converts a named COMPILE
refusal into a link failure at instantiation — later, and invisible to
`tools/c_va_arg_every_target.sh`'s refusal branch, which can only name a wall a
build actually reports. C and D land together.

Note D is not setjmp. The wasm32 skip in `ParseCProgram` covers both emitters
for one stated reason — they emit machine code — but the two are not alike:
`setjmp` cannot be made correct on wasm at all (no addressable call stack to
unwind across), while `fegetround` returning `FE_TONEAREST` on a machine with
exactly one rounding mode is **the truth**. `fesetround` is the half that must
not silently answer success. Whoever takes D should split that guard the way
the xtensa one was split.

### The guard followed the wall rather than loosening

`tools/c_va_arg_every_target.sh` would have gone red on this commit either way —
with B closed, wasm32's refusal is `wasm: too many params+locals`, which was in
neither admitted set. The admitted list gained that spelling **by name**, with
the C-and-D reasoning beside it, and the script still reports
`6 built, 1 refused at a named wall, 7 examined`. The alternative — `grep -q
error:` — is the check that cannot fail.
