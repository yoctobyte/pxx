---
slug: bug-a-managed-string-arg-temp-predicate-is-duplicated-seven-times-and-guarded-nowhere
title: "Six of seven copies were already consolidated; the seventh let a default value onto an array parameter"
summary: "FIXED (80eb4aeaf). The consolidation this ticket asked for had already half-happened: ParamWantsManagedStrTemp landed 2026-08-29 carrying the missing `not IsArray` and converted SIX sites — but there are SEVEN. The omitted-default-argument path still read TypeKind directly, and the helper header saying SIX is why nobody recounted. It was reachable and not only for strings: `array of string = 'x'` gave High = 1073741823, `array of Integer = 5` an empty High. The real fix is a parser refusal at the one place that learns both isArr and hasDefault; the seventh site now calls the predicate for one spelling, not because it is load-bearing. Ten shapes agree with fpc in both directions."
track: A
type: bug
prio: 20
status: done
found: 2026-08-29
found-by: frankwasm
owner: frankA
---

> **Refiled 2026-08-30 out of `chore-a-grant-wasm32-lane-holds-ir-inc-for-the-11207-mistyping`.**
> That ticket was 80% grant bookkeeping for a mechanism that no longer exists, and
> 20% this — a measured seven-site design flaw that lived nowhere else. Closing it
> by slug shape, with its five siblings, would have deleted the only record of the
> defect. The grant half is gone; the investigation below is verbatim.
>
> **Prio stays 20 because of REACH, not because it was a wasm ticket.** The
> mistyped retain and release cancel out on every register backend, so no native
> target can observe it today. It is a latent defect in shared IR, which is exactly
> the kind that stops being latent when a backend changes.

## The defect

frankwasm re-derived its own ticket before touching anything and found the
load-bearing claim in it false. The ticket said *"the same file already gets this
right one site over"* at `ir.inc:11329`. On current master that line is in a
`tyVariant` **default-parameter** branch, unrelated to the managed-string arg
temp. It then checked every candidate: all four `argIsManagedTemp` predicates
(11060, 11305, 11813, 12931) and all seven
`hiddenArgSym := AllocVar('', tyAnsiString)` sites (11069, 11360, 11532, 11704,
11831, 12825, 12951). **Not one tests `IsArray`.**

So there is no correct sibling to copy from. Seven sites, one concept — *does
this parameter want an owning managed-string temp?* — and zero guarded. By
`root-cause-over-microfix`'s own counting rule that is a design flaw, not a typo
at one site, and the likely right fix is **one predicate every site calls**,
deleting six copies rather than adding a seventh clause.

**The grant therefore covers the managed-string arg-temp decision across all its
sites in `ir.inc`, not the single line `:11207`.** Granting the line number would
have forced the microfix the repo has a document telling us not to make, and
would have left six sites for someone to rediscover.

**Where the fix lands:** `compiler/ir.inc`. Gate is Track A's — `make
compiler/pascal26` (which IS the fixedpoint) plus the repro, and cross-target
confirmation, because the change is backend-visible.

**Do the measurement before the edit:** a repro exercising the direct,
constructor, indirect, virtual and interface call paths with an
open-array-of-string argument, to establish which of the seven sites can actually
fire. Shape implying a bug is not the bug, and the count of unguarded sites is
what justifies consolidating rather than patching.

## Log
- 2026-09-01 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change: PENDING-COMMIT.

## Resolved 2026-09-01 (frankA) — and the count was the finding

**Re-derived before touching anything, as this ticket's own body asks.** The
counts still hold (4 `argIsManagedTemp` predicates, 7 `hiddenArgSym :=
AllocVar('', tyAnsiString)` sites) at drifted line numbers. But the load-bearing
claim — "**not one tests `IsArray`**" — was **no longer true**:
`ParamWantsManagedStrTemp` landed 2026-08-29 with exactly that test, and six of
the seven sites call it.

**The seventh does not, and the helper's own header is the reason.** It opened
"ONE PLACE, because the question is asked at SIX sites" and enumerated six. There
are seven — the omitted-default-argument arm — and it kept the raw
`Procs[cpi].Params[pathIdx].TypeKind = tyAnsiString` read that the helper exists
to delete. **A count written into a comment is read as a census**, and this one
was written by whoever had just converted the other six, so it was as
authoritative as a comment gets. Corrected to SEVEN, with why it said SIX.

### It was reachable, and the string case was the least of it

| declaration | pxx before | fpc 3.2.2 |
| --- | --- | --- |
| `const a: array of string = 'x'` | `High(a) = 1073741823` | refuses at the `=` |
| `const a: array of Integer = 5` | `High(a)` prints **empty** | refuses |
| `a: array of string = 'x'` | `1073741823` | refuses |
| `const a: array of Char = 'x'` | `1073741823` | refuses |

There is no syntax for an array literal in a default, so the value parsed is
always a scalar and the callee reads its length header out of that scalar's
bytes — `1073741823` is a frozen literal's inline length prefix. **Compiling and
running wrong**, so this is a bug, not the "we accept what FPC rejects" exemption.

### Which is why the fix is NOT at the seventh site

Making the seventh site ask the predicate fixes only the `tyAnsiString` arm and
leaves `array of Integer = 5` exactly as broken. The refusal belongs at the **one
place the parser learns both halves** — `isArr` and `hasDefault` are set on
adjacent lines in `pasparser_proc.inc`. The durable param row is copied to three
places downstream; guarding those would be guarding the reads rather than the
write.

**The first version of that guard was too broad, and only running it caught
that.** It tested `isArr` alone. `isArr` is true for open-array, named-FIXED-array
and named-DYNAMIC-array params alike, and `a: TArr = nil` is a legitimate default
that FPC compiles (`Length = 0`) — the parameter is a handle and `nil` means
something. Now gated on `paramDynDepth <= 0`. **Ten shapes against fpc, five that
must refuse and five that must compile, agreeing in both directions.** A guard
tested only by what it rejects cannot tell you it rejects too much, so
`test_array_param_default_allowed` ships beside the refusal test as its positive
control.

The seventh site calls the predicate now anyway, and its comment says plainly
that this is **not** load-bearing once the parser refuses — one concept, one
spelling, so the next person to widen defaults changes the predicate rather than
rediscovering the line.

### Searched, not constructed — so claimed as nothing

Two further raw reads of the same field omit `IsArray`: the WideChar->UTF-8
conversion and the NilPy Char->PyStr one. Passing a `WideChar` to an
`array of string` param **does** reach the wrap — pxx's own refusal reports the
argument type as `AnsiString`, so the conversion fired — but overload resolution
rejects it downstream, so no program compiles wrong today. Latent, and the
masking is incidental rather than designed. Not filed: I could not construct a
defect.

### On the prio-20 reach argument

Prio 20 rested on "the mistyped retain and release cancel out on every register
backend, so no native target can observe it". True of the sites the helper had
already fixed. **This arm was observable on x86-64 the whole time** — it is a
wrong length, not a mistyped refcount. The reach argument was correct about the
population it was written for and inherited by an arm it had never seen.

### Landed

- `compiler/pasparser_proc.inc` — the refusal, at the single parse site.
- `compiler/ir.inc` — seventh site routed through the predicate; helper header
  corrected SIX -> SEVEN.
- `test/test_array_param_default_refused.pas` + `..._allowed.pas`, both wired.
- `gate.sh quick` GREEN with the FPC seed canary PASS (run before the commit).
  Quick covers no NilPy and this is argument marshalling, so a NilPy probe with
  a defaulted parameter was run separately against CPython: matches.
