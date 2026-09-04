---
track: A
prio: 60
type: bug
blocked-by: []
status: backlog
summary: "EVERY NilPy module built for wasm32 is INVALID wasm. `print(\"hi\")` is enough. The encoder writes a local index of -1 as the operand of local.set and local.get -- ten LEB bytes ending 01, where u32 permits five -- so wasm-validate says `unable to read u32 leb128: local.set local index` at 0x4593c and wasmtime says `invalid var_u32: integer representation too long`. Pascal for wasm32 is unaffected. THE COMPILE SUCCEEDS AND PRINTS ok:, so the gap census cannot see this class at all: no refusal is recorded and the module is unusable. frankA holds the wasm32 topic and has the diagnosis by message; this exists so it is not only in a message."
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
