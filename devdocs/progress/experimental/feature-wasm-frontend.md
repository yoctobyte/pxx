---
prio: 45
---
# WebAssembly frontend — statically typed, IR-shaped; experimental

- **Type:** feature — frontend (experimental folder rules apply: never a
  prio ticket; upscale only for genuine AST/IR work on its own merits)
- **Opened:** 2026-07-09 (user decision, from the JS-frontend advice
  session: "wasm — trivial. worth a ticket")
- **Owner:** —

## Why this one is actually compilable

Unlike JS ([[feature-js-frontend-parked]]), wasm is exactly the shape the
shared IR eats: statically typed (i32/i64/f32/f64 map 1:1 onto existing
TTypeKinds), a validated stack machine (the Whitespace probe already
proved stack-discipline folds into AST expression trees at parse time),
structured control flow (block/loop/if/br map onto AN_IF/AN_WHILE/
AN_BREAK-family — no irreducible CFGs by construction), linear memory
(one big byte array + load/store = the raw-pointer math the C frontend
does all day). MVP wasm has no GC, no exceptions, no threads.

## Honest scope notes (why "trivial-adjacent", not trivial)

- **Two input formats.** .wat (text, s-exprs — a lexer/parser like any
  other frontend) vs .wasm (binary — a decoder, no lexer at all; arguably
  easier and more useful). Pick ONE for the skeleton: .wat is more
  probe-like, .wasm is more real-world. Suggest .wat first (pure
  parser, zero tooling needed to write tests by hand).
- **The stack discipline** needs folding into expression trees (Whitespace
  precedent) OR explicit temp locals per stack slot (simpler, always
  correct, slightly worse code). Start with temps; fold later if fun.
- **Imports are the actual boundary.** A wasm module importing
  `wasi_snapshot_preview1.fd_write` etc needs a host shim layer. Skeleton:
  support exactly one import shape (a `print_i64`-style debug hook wired
  to the shared write machinery) and exported functions called from a
  generated entry stub. Real WASI = its own later sub-ticket, on demand.
- **Value proposition** (distinct from the JS goal): consume the compiled
  polyglot ecosystem — C/Rust/Zig/Go code shipped as .wasm — not JS
  libraries (those are mostly not shipped as wasm; the JS answer is
  [[feature-c-corpus-quickjs]]).

## Skeleton scope (if/when picked up — esoteric-probe sized)

.wat subset: `(module (func (export ...) (param i64...) (result i64)
local.get/set, i64.const, i64.add/sub/mul/div_s, i64.eq/lt_s/gt_s, block/
loop/if/else/end, br/br_if, call, return))` + one debug-print import.
Lower onto existing AN_*/IR only; x86-64 only; test wired into make test
next to the other probe skeletons. Everything else (memories, globals,
tables, f32/f64, .wasm binary decoding, WASI) stays out until wanted.

## Log
- 2026-07-09 — filed per user decision; parked in experimental/ alongside
  the other optional frontends.
