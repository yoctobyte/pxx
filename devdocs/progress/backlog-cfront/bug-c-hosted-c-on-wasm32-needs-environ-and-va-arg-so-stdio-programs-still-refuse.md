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
summary: "Wall A (`environ`) IS DONE as of 63d077feb -- WasmEmitEnvironFetch makes the WASI environ_sizes_get/environ_get pair inside the synthesised `_start` and hands the vector to __pxx_set_environ, and the refusal is deleted. It has NEVER EXECUTED and is inert (WasmCEntryEnvp stays -1 for every program that compiles today), because hosted C on wasm32 turns out to have THREE walls, not two, and A was only the first. Measured individually on 2026-09-06 by moving one and re-running: (B) lib/crtl/src/stdio.c hits `wasm: too many params+locals`, the MAX_WASM_BODY_VARS=288 bound in wasmenc.inc; (C) with that raised to 2048 locally, lib/crtl/src/fcntl.c hits the wasm32 va_arg gap, which open/openat need. The local raise was reverted -- it is the wasm backend`s call -- and the compiler rebuilt to the byte-identical 63f56a42bef6 it had before. Freestanding C is unaffected and still green. So `printf` on wasm32 needs B and C; A is no longer in the way and no longer the headline."
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
