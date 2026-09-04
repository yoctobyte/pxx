---
track: A
prio: 60
type: bug
blocked-by: []
status: done
summary: "FIXED by frankA in f01eee6fa. wasm32 kept four per-body managed-string scratch locals; `msval` was allocated by the managed-STORE path only, while WasmVariantPayload reaches the same materialiser without a store -- so a body that boxed a string variable into a Variant and never assigned one emitted `local.set -1`, ten LEB bytes where u32 permits five. Every NilPy module for wasm32 was invalid; `print(\"hi\")` was enough. Verified here rather than taken on report: at fbc02f487f6f the one-liner validates and prints hi. MY OWN GUESS AT THE CAUSE WAS WRONG and I had labelled it as inference -- see below."
---

# wasm32 emits a local index of -1, so every NilPy module fails validation

## Repro, one line

```
printf 'print("hi")\n' > /tmp/m1.npy
./compiler/pascal26 --target=wasm32 /tmp/m1.npy /tmp/m1.wasm    # prints ok:
wasm-validate /tmp/m1.wasm
  004593c: error: unable to read u32 leb128: local.set local index
```

Any `.npy` reproduces it, always at `function[439]`, so it is in pylib rather
than in user code. A Pascal `WriteLn(42)` for wasm32 validates and runs.

## The bytes, which are not an inference

At 0x45930:

```
20 05  41 10  6a  24 00  20 0c  21 ff ff ff ff ff ff ff ff ff 01
                                ^^ local.set
local.get 5 / i32.const 16 / i32.add / global.set 0 / local.get 12 /
local.set <ten-byte LEB>
```

Ten continuation bytes ending `01` is **-1** sign-extended to 64 bits. A u32
LEB may be five bytes, hence "representation too long". The next instruction is
`20 ff ff ff ...` — `local.get` with the same -1. So a local-index sentinel of
-1 reaches the encoder and is written out in BOTH directions rather than
refused.

`local.get 12` immediately followed by `local.set -1` reads like a result slot
that was never allocated — something asks a proc for its Result local and gets
-1. **That last sentence is inference from twenty bytes and should not be built
on.** The -1 operand is not inference; it is in the file.

## Why the gap census is structurally blind to this

The compile SUCCEEDS. `ok:` is printed, no body is refused, nothing appears in
the per-gap coverage report — and the module cannot be instantiated. Every
check that stops at "did it build" passes, which is the whole reason this sat
behind a wall of front-end failures without ever being counted.

**`wasm-validate` is a different instrument from running the module**, and it
is the cheaper one: it named the instruction and the offset in one command
where wasmtime gave a byte offset and a function index. A validation row on the
emitted module would catch this class in general, not just this instance.

## Who has it

frankA holds the wasm32 backend and has the full diagnosis by message
(2026-09-04). Filed anyway because a message is not a record — see
`umbrella-wasm-is-a-real-platform`. Do not start on it without checking with
that session first.


## RESOLVED 2026-09-04 by frankA, `f01eee6fa` — and my inference was wrong

Verified here before closing, on `fbc02f487f6f`: `printf 'print("hi")\n'`
built for wasm32 now passes `wasm-validate` and prints `hi` under wasmtime.

**The cause was not what I guessed.** This ticket said the byte pattern
`local.get 12` / `local.set -1` "reads like a result slot that was never
allocated". It is not a Result slot at all: wasm32 keeps four per-body
managed-string scratch locals, allocated on demand and reset to -1 per body,
and `msval` was allocated by the managed-STORE path only. `WasmVariantPayload`
reaches the same materialiser without going through a store, so a body that
boxed a string VARIABLE into a Variant and never assigned one used a local that
had never been allocated. The other three scratch locals were correct by three
DUPLICATED copies of the same `if < 0 then` triple — the shape that let the
fourth drift.

**The labelling is the part worth keeping.** The `-1` operand was stated as a
fact read out of the file and the cause as inference from twenty bytes, with
"should not be built on" attached. The fact held and the inference did not,
which is the only reason the wrong half cost nothing.

## Why no existing test caught it, which is not the same as no test trying

All four wasm32 Variant rows (`test_cross_variant`, `_single`,
`_payload_widths`, `_self_assign`) emit a VALID module on the PRE-FIX compiler —
measured by frankA on a rebuilt pre-fix binary, not argued. They box string
LITERALS, and a literal goes through the string pool and never touches `msval`.
Reaching it needs a string VARIABLE boxed in a body with no preceding store,
which no test had. `test_cross_variant_boxed_string_no_store` is that row now,
on all six targets.

## The class, which outlived the instance

A compile that SUCCEEDS and prints `ok:` while emitting an unusable module is
invisible to a gap census by construction. Two instruments came out of it:
`WasmBodyU32` now refuses a negative index and names the body, and the census
runs `wasm-validate` on every module it writes and reports a fourth bucket,
"compiled ok, module REJECTED" — refusing to run at all if `wasm-validate` is
absent rather than silently dropping the bucket.

**The residual frankA named and did not claim to have fixed:** no Makefile
recipe validates or loads an emitted `.wasm` except the rows that RUN one, so
this class in a body no row reaches is still invisible.

## Log
- 2026-09-04 — resolved, commit f01eee6fa.
