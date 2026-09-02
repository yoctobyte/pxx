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
summary: "A hidden managed ARGUMENT TEMP in a frame that an exception unwinds past is never released — one heap block per raise, unbounded, and FPC reports 0 unfreed on the same program. `raise Exception.Create(gmsg + Chr(65))` leaks 1/raise; so does `Boom(gmsg + Chr(65))` where the CALLEE raises, so it is not confined to the raise statement. The frame's unwind landing pad is gated on ProcHasManagedLocalCleanup at pasparser_proc.inc:2604, but the body is not parsed until line 2687 — so the gate is decided BEFORE the temps it should be asking about exist, and can only ever see DECLARED locals. Merely declaring an unused AnsiString in the raising routine makes the leak vanish; an Integer local does not. Dropping the ProcHasManagedLocalCleanup condition fixes it completely and costs +12% to +24% code size on exception-using programs (measured), which is why it is filed rather than landed."
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
