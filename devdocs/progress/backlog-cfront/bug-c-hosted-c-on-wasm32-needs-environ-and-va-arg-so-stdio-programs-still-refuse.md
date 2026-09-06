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
summary: "The wasm32 C entry landed (WasmEmitCEntry) and FREESTANDING C now builds and runs -- `int main(void){return 42;}` exits 42 under wasmtime, argc/argv are live. HOSTED C still refuses, at two walls in front of crtl, and the first is reached by any of <stdio.h> <stdlib.h> <unistd.h> <math.h>: (1) `environ` -- the pre-main initializer derives the environment from the initial stack pointer and WASI has none, reporting it through environ_get instead, and CNeedsEnvironInit is a token scan that cannot tell the crtl DECLARATION from a use, so it fires for programs that never mention it; (2) va_arg is unimplemented for wasm32, which lib/crtl/src/fcntl.c needs for open/openat. Measured: stdarg.h and string.h compile, stdlib.h/stdio.h/unistd.h/math.h refuse. So `printf` on wasm32 -- the second acceptance criterion of the entry-stub ticket -- needs BOTH."
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

## Where this lane actually was, 2026-09-06 (frankC) — note to self, and to whoever is next

**Wall A (`environ`) is the next piece and it was NOT started.** No code exists
for it, no branch, no stash. The fleet moved to reds-only for the beta 0.1 pin
before I began, so this is a clean stopping point rather than an interrupted one.

**What I would do first, so the next session does not re-derive it.** The shape
is already in the tree as a worked example: `WasmEmitArgvFetch`
(`ir_codegen_wasm32.inc`) fetches argv with `args_sizes_get` + `args_get` into a
`PXXAlloc`'d block and hands back a count and a pointer vector. WASI's
`environ_sizes_get` / `environ_get` are the same two calls with the same shape,
and `environ` wants exactly what `args_get` already produces — a NULL-terminated
pointer vector. So the first move is to read that function, not to design one.

**Then the refusal comes out, not the predicate.** The refusal I added in
`ParseCProgram`'s `TARGET_WASM32` arm exists only because there was no way to
fill `environ`; once there is, delete it rather than narrowing
`CNeedsEnvironInit`. The predicate's over-approximation (a token scan that
cannot tell the crtl DECLARATION from a use, so `#include <stdio.h>` is enough)
stops mattering the moment the answer is available — it would only ever have
caused an unnecessary *initialisation*, never a wrong one.

**Order is not negotiable.** Wall B (va_arg) is unreachable behind wall A for
every program that would exercise it, because reaching `lib/crtl/src/fcntl.c`
requires a header that trips A first. Doing B alone changes no observable, and
`tools/c_va_arg_every_target.sh` will keep reporting `refuses no environ on
wasm32` and passing — see that ticket's own note on why the script cannot grade
B until A is done.

**One thing already true and easy to lose:** freestanding C on wasm32 works
today and is covered by `tools/c_wasm32_entry.sh`. Do not let a wall-A attempt
regress it — that script is the guard, and its rows are all nonzero-expecting
for a reason written at the top of the file.
