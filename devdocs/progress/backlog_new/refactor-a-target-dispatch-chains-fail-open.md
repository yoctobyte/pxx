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
