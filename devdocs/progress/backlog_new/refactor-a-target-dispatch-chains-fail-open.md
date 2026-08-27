---
slug: refactor-a-target-dispatch-chains-fail-open
title: "Target dispatch chains fail OPEN — a 7th target matches no arm and is silently configured as nothing"
track: A
prio: 50
type: refactor
blocked-by: []
status: backlog_new
owner: ""
created: 2026-08-27
summary: "Not a missing-helper ticket: TARGET_PTR_SIZE exists and is read at 129 sites. The narrow, verified gap is that several per-target if/else-if chains have no final else, so adding target #7 (wasm32) or #8 (riscv64) matches no arm and configures nothing, silently. lexer.inc:936 is the worked example. Fix is a mandatory else that Errors, not a collapse of the 180 TargetArch sites — util.inc:87 already documents why collapsing is wrong."
---

# What this ticket is NOT

**It is not "pointer width has no single answer".** It does.
`TARGET_PTR_SIZE: Integer` is declared at `compiler/defs.inc:1758`, assigned at
`compiler.pas:788` (default 8) and `compiler.pas:1508/1510` (4 vs 8 per target),
and read at **129 sites** across `compiler/` — including `symtab.inc` (32),
`cparser.inc` (22), `ir.inc` (17), `pasparser_decl.inc` (15).

An earlier draft of this ticket claimed otherwise. It was wrong, and it was
wrong because its grep only looked for `function TargetPtrSize` and could never
have matched a variable. Recorded here so the next person greps for the
concept, not the spelling.

**It is also not "collapse the raw `TargetArch` sites".** There are ~180 of them
(`ir_codegen.inc` 83, `symtab.inc` 47, `cparser.inc` 31, `elfwriter.inc` 27,
`lexer.inc` 19), and **most are legitimately per-arch codegen** — a `case` over
five ISAs is the correct shape for emitting five instruction encodings.

`compiler/util.inc:87` (`TargetIsEspClass`) already did the collapse that was
worth doing — 24 hand-written copies of one predicate, three of them found only
by a grep-for-the-sibling pass — **and its comment documents the refusal**: 13
sites spelling `(TargetArch = TARGET_XTENSA) or (TargetArch = TARGET_RISCV32)`
are deliberately left alone in `emit.inc`, `elfwriter.inc`,
`exception_emit.inc`, `pasparser_decl.inc`, `lexer.inc`, `pasparser_prog.inc`,
because there the one spelling means four different things — "no DWARF", "the
only two `--emit-obj` targets", "`Real` is Single", "no hardware FPU". One
predicate would assert a sameness that is not there.

That refusal is the strongest thing in the tree on this subject and this ticket
does not touch it.

# The actual finding, verified on `origin/master@8787cfe42`

Several per-target chains **fail open**. `compiler/lexer.inc:936`:

```pascal
  if TargetArch <> TARGET_X86_64 then
  begin
    ...
    if TargetArch = TARGET_AARCH64 then      begin ... end
    else if TargetArch = TARGET_ARM32 then   begin ... end
    else if TargetArch = TARGET_I386 then    begin ... end
    else if TargetArch = TARGET_XTENSA then  begin ... end
    else if TargetArch = TARGET_RISCV32 then begin ... end;
  end;   { …end of the non-x86-64 CPU-define swap }
```

There is **no final `else`**. The chain is complete for the six targets we have,
which is exactly what hides the shape.

Add a 7th target and it enters the outer block (it is not x86-64), matches no
arm, and falls out having set **no CPU defines at all**. Not "the x86-64
answer" — *nothing*. No error, no warning, and the failure surfaces much later
as source that compiles under the wrong conditional defines.

# Two more sites, measured 2026-08-27

A heuristic scan for `TargetArch` chains of >=3 arms with no final bare `else`:

```
  6 arms  compiler/exception_emit.inc:8
  4 arms  compiler/coroutine_emit.inc:25
```

Both emit **nothing at all** for an unrecognised target — no exception runtime,
no coroutine runtime, no diagnostic. Together with `lexer.inc:936` above that is
three confirmed, and **the scan undercounts**: it missed `lexer.inc` entirely
because that chain sits inside an outer `if TargetArch <> TARGET_X86_64` guard
the scan did not follow. So the audit is genuinely the work here; the scan is a
starting point and must not be mistaken for an inventory.

# Why it is worth fixing before target #7 or #8, not after

Two tickets add a target and both hit this:

- `feature-target-wasm` — wasm32.
- `feature-a-riscv64-as-a-hosted-first-class-target` (rainy-day, prio 10) —
  whose own text says riscv64 "must NOT simply be added" to the 13 refused
  sites, each needing its own answer.

Fixing it after a target exists means auditing which chains silently skipped the
new target, from the symptoms. Fixing it before means the chains say so.

# Shape of the fix

Not new predicates. A **mandatory `else`** on the chains that dispatch on target
*identity* and currently have none:

```pascal
    else Error('lexer: no CPU-define profile for this target');
```

so that adding a target is loud at each site that needs a decision, at the
moment it is added.

The work is the audit — which chains are exhaustive-by-intent (need the `else`)
versus which are genuinely "x86-64 does this extra thing" (correct as-is). That
distinction is the ticket; the edit is trivial once it is made.

Where a chain turns out to be asking a *property* rather than an identity, the
established method is `util.inc`'s: one named predicate with a comment saying
which bug it prevents (`TargetIsEspClass`, `RealTypeKind`) — **and an explicit
list of the sites it refuses to absorb.** Follow that, including the refusals.

# Acceptance

1. Every chain that dispatches on target identity and is exhaustive-by-intent
   has a final `else` that Errors.
2. `make compiler/pascal26` converges byte-identical.
3. **Compile a fixed corpus for all six targets before and after; every output
   binary byte-identical.** This is a pure refactor — any diff is a chain that
   was doing something other than what it appeared to.

# Overlap with `feature-a-wasm32-target-registration-skeleton`

That ticket applies this medicine to one concrete target (wasm32) and therefore
fixes the chains wasm32 reaches, with a consumer and a date. Sensible order: it
first, then this general sweep using the site list it produces. Doing both
independently is the only bad option.

## Log
- 2026-08-27 — filed from the wasm-target scoping session. Replaces an earlier
  draft (`refactor-a-target-properties-have-no-single-answer`) that was filed on
  a wrong premise and onto the retired `dev` branch; corrected after
  frank1-80 measured `TARGET_PTR_SIZE`'s 129 call sites and pointed at
  `util.inc:87`. Findings: `devdocs/dev/wasm-target-findings.md`.

- 2026-08-27 (frank-optimize) — **the site list produced by the wasm32
  registration, and it changes this ticket's scope.** Landed
  `feature-a-wasm32-target-registration-skeleton` at `290ee8ca4`; the audit it
  required is the "starting point, not an inventory" warning above coming true.

  **The scan found 2 of 4, and missed the two that matter.** Confirmed as filed:
  `exception_emit.inc:8`, `lexer.inc:936`, and `coroutine_emit.inc:25` (real,
  but currently unreachable — the codegen chain below errors first). The two the
  scan could not see:

  | site | what it falls through to |
  | --- | --- |
  | **`ir_codegen.inc:9048`** (`IREmitMachineCode`) | **the x86-64 emitter** |
  | **`compiler.pas:2082`** (output writer) | **`writeELF`** (64-bit ELF) |

  Both are `if ... Exit` **ladders**, not `if / else if` chains — each arm ends
  in `Exit` and the "else" is simply the code after the last one. A heuristic
  looking for a missing final `else` cannot match that shape at all. **This
  ticket's site list must grep for Exit-terminated target ladders as well as
  chains without an `else`**; on the two spellings measured so far the ladder
  form is where the worse failures live.

  **And that changes what this ticket is about.** The framing above is "matches
  no arm and configures *nothing*" — no defines, no runtime, no diagnostic. That
  is the cheap half: an absence, and absences tend to surface as a confusing
  error somewhere downstream. The two ladder sites do something else. A 7th
  target reaching `ir_codegen.inc:9048` receives **x86-64 machine code in a file
  claiming to be its own architecture**, and `compiler.pas:2082` then wraps it
  in a 64-bit ELF. That is not a missing error message, it is a **plausible
  wrong output far from its cause** — the class `devdocs/dev/debugging-playbook.md`
  opens by naming as the expensive one, and the reason it is expensive is that
  the binary exists, has a normal size, and fails only when someone runs it on
  the hardware. Worth stating in the summary line: this ticket prevents wrong
  code generation, not just silent no-ops.

  Both ladder sites are already loud **for wasm32 specifically** (an explicit
  arm each, landed in `290ee8ca4`). What is still open here is the general
  `else` for target #8, which is this ticket's job.

  **One boundary that ticket hit and this one inherits.** `coroutine_emit.inc`
  did **not** get a mandatory `else`: riscv32 and xtensa fall through it
  deliberately ("Other targets land in later phases"), so an `else Error` there
  would move an existing target and break that ticket's acceptance #3. It is a
  live example of the audit this ticket calls the work — the chain looks
  exhaustive-by-intent and is not. Whoever takes this must decide what riscv32
  and xtensa should do when a program uses `__pxxcoswitch`, which is a real
  question about those targets rather than a refactor. If the answer is "error
  clearly", that is a behaviour change for two shipped targets and wants its own
  ticket, not a line in a sweep.

  Method note for acceptance #3, since it is the same bar the registration
  ticket had to clear: an 8-program corpus x 6 targets = 48 output hashes,
  before and after, **failures included** (a program that fails identically on
  both sides is evidence too). Build the "before" compiler by stashing the edits
  and rebuilding rather than reusing `pinned`, which carries unrelated deltas —
  and check the corpus actually reaches the chains being changed. Mine did not
  on the first pass: it contained no `try` at all, so it never exercised the one
  chain where a bare `else` had been added.
