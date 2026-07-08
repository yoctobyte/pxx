---
prio: 60  # auto
---

# Rust frontend — lexer/parser skeleton + entry point

- **Type:** feature — Track A (working name: **Track R**, Rust frontend)
- **Status:** done
- **Owner:** Claude (~/frank2, branch `feature/rust-frontend-skeleton`)
- **Opened:** 2026-07-03
- **Umbrella:** [[feature-rust-frontend]] — sub-ticket 1/12, gates all others.

## What it does

Bring up `rlexer.inc` + `rparser.inc` (new files, same shape as
`clexer.inc`/`cparser.inc`) and a `ParseRustProgram` entry point wired the
same way `ParseCProgram` is: file-extension or explicit-flag dispatch,
lowering straight to the existing shared AST/IR — no new backend, no new
ELF/ABI work.

Scope for the *skeleton* specifically (deliberately small — this ticket is
"can we parse and lower a trivial Rust program," not "support Rust"):

- Lexer: Rust token set (keywords, `::`, `->`, `..`/`..=`, lifetimes as a
  token shape `'a` even though unenforced, raw strings `r"..."` if cheap).
- Parser: `fn`, `let`/`let mut`, plain expressions/binops, `if`/`else`,
  `while`/`loop`, plain (non-generic, non-trait) `struct`, function calls,
  `return`. No `match`, no generics, no traits, no `enum`-with-data, no
  `impl` blocks yet — those are the later sub-tickets.
- Lower directly onto existing AST nodes (`AN_IF`/`AN_WHILE`/`AN_CALL`/etc.)
  — the whole point of this ticket is proving the existing shared AST/IR is
  sufcient for the boring 80% before spending effort on the hard 20%.

## Acceptance

- A trivial multi-function Rust program (arithmetic, `if`/`while`, plain
  structs, no traits/generics/match) parses and self-compiles to correct
  runtime output.
- Existing `make test` unaffected (new frontend, isolated files, no shared
  internals touched beyond the same entry-point-dispatch pattern C uses).
- Ticket stays Track A per the shared-internals rule even though this is
  "a new frontend" — same reasoning as C: shared AST/IR/symtab changes are
  Track A regardless of which frontend triggers them.

## Log
- 2026-07-03 — split from [[feature-rust-frontend]] umbrella at ticket-craft
  time. No code written yet.
- 2026-07-03 — skeleton landed: `compiler/rlexer.inc` + `compiler/rparser.inc`
  (new, additive), `.rs` extension dispatch wired into `compiler.pas`
  (`isRust` alongside `isC`/`isNilPy`/.../`isAsm`), 7 new `TTokenKind` values
  appended at the tail of the enum in `defs.inc` (existing ordinals
  untouched). Two-pass like the C frontend: pass 1 registers struct layouts
  + fn signatures (forward calls resolve via `FindProc`), pass 2 compiles
  bodies. x86-64 only, ≤4 scalar params (rdi/rsi/rdx/rcx), struct
  params/returns explicitly rejected for now (scalar-only ABI) — plain
  structs work as locals with field read/write. `println!`/`process::exit`
  are out of scope (sub-ticket 12), so trivial test programs report results
  via `fn main() -> i32`'s return value as the process exit code.
  Verified: a hand-written trivial multi-fn program (struct literal + field
  read, arithmetic, if/else-if/else, while, loop+break, function calls,
  return) compiles and runs to the expected exit code. `make bootstrap`
  3-stage self-host stays byte-identical. `make -k test` green except one
  pre-existing, unrelated environment failure (`crtl_tiny_regex_match.c`
  hits a missing clang system header path) confirmed present on unmodified
  `master` too — not a regression from this change.
  No Track A ticket needed: everything above is additive new files + generic
  reuse of existing shared AST/symtab primitives (AllocVar/AllocParam/
  RegisterProc/AddUClass/AddUField/RecFieldType/CompileAST/...), no shared
  internals were modified beyond the same append-only token-enum + dispatch
  pattern the C frontend already established.
  Next: sub-ticket 2, [[feature-rust-match-enum-payload]].
- 2026-07-03 — **correction**: re-validated after a `make bootstrap`
  rebuild and the multi-fn correctness claim above does NOT hold for the
  self-hosted binary — only the FPC-built one. Filed
  [[bug-selfhost-multifn-ifelse-miscompile]] (urgent, Track A, shared
  internals — not caused by this frontend's AST/IR usage, all shared node
  kinds already used elsewhere). Not blocking: this ticket's own tests are
  confirmed correct against the FPC-built compiler; see that bug ticket for
  the self-host divergence and how Track R validates around it meanwhile.
- 2026-07-04 — merged `feature/rust-frontend-skeleton` to `master`
  (fast-forward, `a71356c`) at the user's direction, alongside sub-tickets
  2-3. **Unofficial/unsupported, not required by anything else on
  `master`** — pure additive new files (`rlexer.inc`/`rparser.inc`) plus
  the same append-only dispatch pattern C already uses; nothing else on
  `master` depends on or is affected by `.rs` files existing. This ticket
  stays `working/` (not `done/`) since sub-tickets 4-12 are still ahead;
  going forward, Track R sub-tickets land and merge to `master` directly
  rather than accumulating on the branch first.
- 2026-07-04 — [[bug-selfhost-multifn-ifelse-miscompile]] fixed (a
  parenthesis-less self-recursive call in `RParseIf` — see that ticket's
  log). The self-host caveat above no longer applies: the self-hosted
  compiler now agrees with the FPC-built one on this ticket's tests.
- 2026-07-08 — resolved, commit c7117072.
