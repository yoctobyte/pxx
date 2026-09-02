---
slug: bug-a-a-managed-temp-in-a-frame-unwound-by-an-exception-is-never-released
title: "A managed TEMP in a frame unwound by an exception leaks; the landing-pad gate cannot see temps"
track: A
prio: 65
type: bug
status: backlog
found: 2026-09-02
found-by: frankB
owner: ""
blocked-by: []
tags: [memory-leak, exceptions, unwind]
summary: "FIXED 2026-09-02 (frankC) by asking the landing-pad gate a SECOND time inside CompileAST, between IRLowerAST and IREmitMachineCode -- the two points where the hidden temps already exist and no body code has been emitted yet. Costs +1.3%/0%/+3.3% code size on the three programs where dropping the condition cost +20.3%/+23.6%/+12.4%, because only a proc that actually mints a managed temp gets a pad. Plain bodies only: asm and generator bodies keep the prologue decision and a generator raising past a managed temp is NOT covered. Original report: a hidden managed ARGUMENT TEMP in a frame that an exception unwinds past is never released — one heap block per raise, unbounded, and FPC reports 0 unfreed on the same program. `raise Exception.Create(gmsg + Chr(65))` leaks 1/raise; so does `Boom(gmsg + Chr(65))` where the CALLEE raises, so it is not confined to the raise statement. The frame's unwind landing pad is gated on ProcHasManagedLocalCleanup at pasparser_proc.inc:2604, but the body is not parsed until line 2687 — so the gate is decided BEFORE the temps it should be asking about exist, and can only ever see DECLARED locals. Merely declaring an unused AnsiString in the raising routine makes the leak vanish; an Integer local does not. Dropping the ProcHasManagedLocalCleanup condition fixes it completely and costs +12% to +24% code size on exception-using programs (measured), which is why it is filed rather than landed."
---

# A managed temp in a frame unwound by an exception is never released

## The control triple

`Raiser` called 2000 and 8000 times, `-dPXX_ALLOC_CENSUS`, live at exit:

| raiser body | N=2000 | N=8000 | slope |
| --- | --- | --- | --- |
| `raise Exception.Create(gmsg)` — no temp | 2 | 2 | **flat** |
| `raise Exception.Create(gmsg + Chr(65))` — temp | 1901 | 7815 | **0.99 / raise** |
| `if Length(gmsg + Chr(65)) = 0 then …` — temp, NO raise | 2 | 2 | **flat** |

The third row is the one that names the bug: the very same temp, in the very
same routine, is released correctly on the NORMAL path and never on the UNWIND
path. So this is not "temps are not released", it is "the unwind path does not
run the release".

`gmsg` is a global AnsiString, so `Create(gmsg)` allocates nothing and
`Create(gmsg + Chr(65))` allocates exactly one temp. Slope, not the raw census
line, is the measurement — the census prints at geometric thresholds, so its
last `allocs=` is a snapshot and dividing it by N is wrong.

## Not confined to the raise statement

```pascal
procedure Boom(const s: AnsiString); begin raise Exception.Create(gmsg); end;
procedure Caller(n: Integer); begin Boom(gmsg + Chr(65)); end;
```

live 1901 @ 2000, 7815 @ 8000 — slope 0.986. The temp belongs to `Caller` and
the raise happens in `Boom`. **A fix that only drains temps at a `raise`
statement would not close this**, which is worth knowing before anyone tries the
cheap version.

## What decides it

```pascal
{ pasparser_proc.inc:2604 }
needsProcCleanupFrame := TargetHasProcCleanupFrame and ExceptionUsed and
                         (not isAsmFunc) and ProcHasManagedLocalCleanup(procIdx, -1);
if needsProcCleanupFrame then EmitProcCleanupFrameEnterForTarget(cleanupJnePatch);   { 2606 }
...
inlineBodyNode := WrapManagementOps(procIdx, ParseBlockAST);                          { 2687 }
```

The gate runs at 2604. The body is parsed at 2687. `ProcHasManagedLocalCleanup`
walks `Syms[]` from `Procs[procIdx].ScopeBase` for `skLocal` entries needing
cleanup — and the hidden argument temps are created while LOWERING THE BODY,
eighty lines later. **The gate is not filtering temps out; they do not exist yet
when it is asked.** It is structurally incapable of a different answer, which is
why the failure is silent and shape-dependent rather than occasional.

The existing comment above the gate is correct about its own subject and is
worth keeping — it says a proc holding managed locals that can be unwound past
needs a landing pad "or the locals are never released", and records that the gate
once read `TargetArch = TARGET_X86_64` and leaked on every other target silently.
Same class of bug, one level down: the predicate was widened across targets and
never questioned on WHAT it counts.

## Confirming the mechanism, from the other side

| declared in the raising routine | result |
| --- | --- |
| nothing | leaks 1901 |
| `s: AnsiString`, assigned | clean, live=2 |
| `s: AnsiString`, **declared and never used** | clean, live=3 |
| `x: Integer` | leaks 1901 |

An unused managed declaration is enough to switch the landing pad on and take
the temps with it. That is as direct a confirmation as the mechanism admits, and
it is also a nasty trap: adding or removing an unrelated local changes whether a
routine leaks.

A managed local in the HANDLER's frame does not help (measured, both in `main`
and in an intermediate `Catcher`): it is the frame the temp lives in that needs
the pad.

## Oracle

FPC 3.2.2 with `-gh`, same programs: **`0 unfreed memory blocks`** for the
raise-with-temp shape, the callee-raises shape and the depth-4 shape. This is a
divergence on code someone meant to write, so it is a bug and not a compat note.

## The fix that works, and why it is not landed

Dropping the last condition:

```pascal
needsProcCleanupFrame := TargetHasProcCleanupFrame and ExceptionUsed and (not isAsmFunc);
```

closes it completely — `computedarg` goes flat at live=2 for both N — and 54
tests in the exception family pass. Measured cost, same three programs:

| program | before | after | delta |
| --- | --- | --- | --- |
| test_exception_object_leaks | 302872 | 364312 | **+20.3%** |
| test_cross_exception | 69400 | 85784 | **+23.6%** |
| examples/json/jsondemo | 1122072 | 1261336 | **+12.4%** |

`compiler/pascal26` itself is byte-identical either way, because compiler.pas
does not set `ExceptionUsed` — so **the self-host fixedpoint cannot see this
change at all**, in either direction. Do not read a green fixedpoint as evidence
about it.

12–24% on every exception-using program is a real cost to pay by default, so
this is filed rather than landed.

## Recommended direction

Make the gate see the temps rather than guessing before they exist. The body is
already parsed to an AST at 2687 (`ParseBlockAST`), so the information exists —
what is missing is that the frame ENTER must be emitted before the body's code.
Either reserve and patch the enter sequence (the call already threads a
`cleanupJnePatch`, so a patch point exists), or decide from the AST before
emitting. A cheaper approximation — "does this body contain any call taking a
managed argument by value" — would cover the measured shapes, but it is a
predicate about the body and so needs the body either way.

Whatever the approach: the leak is per-raise and unbounded, so any program that
raises in a loop grows without limit. That is what sets prio 65 rather than the
low prio a code-size trade-off would suggest.

## 2026-09-02 (frankC) — FIXED by asking the gate where it can see the answer

This ticket's own recommended direction, taken: *"Make the gate see the temps
rather than guessing before they exist."*

The gate is now asked a SECOND time, inside `CompileAST` between `IRLowerAST`
and `IREmitMachineCode`. Those two points are exactly where the answer is
available: `IRLowerAST` has just minted the hidden argument temps as `Syms[]`
entries, and no machine code for the body has been emitted yet. The predicate
itself is unchanged — `ProcHasManagedLocalCleanup` was never wrong, it was
asked before its subject existed.

```
                              before        after
raise Exception.Create(gmsg + Chr(65))   7816 @ 8000    live 4, FLAT
Boom(gmsg + Chr(65)), callee raises      7815 @ 8000    live 4, FLAT
the same at depth 4                      leaks          live 4, FLAT
```

### It costs a fraction of the always-on fix

That is the whole reason to do it this way rather than drop the condition.
Measured on this tree, the same three programs the ticket used, against a
pre-change compiler built from one tree with four files stashed:

| program | before | after | this fix | dropping the condition (above) |
| --- | --- | --- | --- | --- |
| test_exception_object_leaks | 306968 | 311064 | **+1.3%** | +20.3% |
| test_cross_exception | 69400 | 69400 | **0%** | +23.6% |
| examples/json/jsondemo | 1122072 | 1158936 | **+3.3%** | +12.4% |

Only a proc that actually mints a managed temp gets a landing pad, so the cost
lands on the procs that need one instead of on every proc in an
exception-using program. `test_cross_exception` is unchanged at all: nothing in
it needs a pad it did not already have.

### Why this was safe to move, checked rather than assumed

`ProcExceptionCleanupFrameActive` has exactly ONE reader,
`ir_codegen.inc:14052`, and it runs during code generation — after lowering. So
setting it later than the prologue changes nothing. Had it been read during
parsing, this approach would have been wrong and silently so.

For a PLAIN body nothing is emitted between the old gate site and `CompileAST`
(the generator prologue is inside an `isGenerator` branch), so when the early
gate already fires the emitted bytes are unchanged — the late path only adds a
frame where there was none.

### Scope, stated rather than implied

- **Plain bodies only.** An `asm` body and a generator/stackless body keep the
  prologue decision and are not re-asked. A generator whose step function raises
  past a managed temp would still leak; that is NOT covered here and was not
  measured in this ticket either.
- The request is raised only when the prologue said NO, so a proc that already
  has a frame cannot get a second one.
- The wanted/armed/patch globals are saved and restored per proc alongside
  `ProcExceptionCleanupFrameActive`, because a nested proc's body is parsed and
  lowered during the outer proc's parse and would otherwise return its answer as
  the outer proc's.

### The regression test, and it is proven able to fail

`test/test_exception_unwind_temp_leak.pas`, wired with `assert_no_leak.sh` at
bound 200. Measured BOTH ways before wiring: **live=8392 on the pre-fix
compiler, live=4 on the fixed one.** Its header carries the trap this ticket
found — merely declaring an unused `AnsiString` in a raising routine switches
the old gate on and takes the temps with it, so a well-meaning local added to
any routine in that file would quietly convert it into a test that passes on the
broken compiler.

As this ticket warned, `compiler/pascal26` is byte-identical either way because
`compiler.pas` never sets `ExceptionUsed` — the self-host fixedpoint cannot see
this change in either direction and is not evidence about it.
