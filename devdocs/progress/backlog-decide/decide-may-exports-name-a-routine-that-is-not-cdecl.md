---
track: U
prio: 40
type: decide
blocked-by: []
summary: "`exports Foo;` where Foo is not `cdecl`. FPC exports it under its own calling convention, which for pxx means callable and wrong from outside. Three answers: reject, imply cdecl, or export under the pxx convention. Track P shipped the REJECT arm because it is the only one that can be relaxed later without breaking a program that already compiles — this ticket is the relaxation question, not a blocker."
---

# May `exports` name a routine that is not `cdecl`?

**Not blocking anything.** `library` + `exports` parses and works today
([[feature-p-a-pascal-library-unit-does-not-parse]]); this decides whether the
diagnostic it currently raises should become an implicit convention change.

## The fork

`exports Foo;` where `Foo` has no `cdecl`.

| | what it does | what it costs |
|---|---|---|
| **(i) reject** — SHIPPED | diagnostic naming `cdecl` as the fix | rejects source FPC accepts |
| **(ii) imply `cdecl`** | `exports` silently changes Foo's convention | the source said one thing and got another; a pxx-internal `@Foo` now points at a cdecl body (consistent, but not what was written) |
| **(iii) export under the pxx convention** | FPC's literal behaviour | **ruled out** — see below |

## Why (iii) is not a live option, and it is CLAUDE.md that rules it out

`ObjProcIsExported` is `ProcCdecl and not ProcCStaticLink` precisely because
"an internal-convention routine exported under its Pascal name is *callable and
wrong*": the foreign caller marshals SysV, the callee reads pxx's internal
convention, and nothing diagnoses it. That is a silently wrong artifact, and the
compat ceiling says to **prefer the answer that leaves the mistake visible**.
FPC's answer here is not a specification — `exports` with no `cdecl` is only
ever written by someone who meant "callable from outside", and outside means the
C ABI.

## Why (i) shipped without waiting for this

**Reversibility.** Relaxing (i) to (ii) later breaks nothing: sources that were
an error start compiling. Choosing (ii) first and reversing it breaks programs.
And the answer changes **one predicate**, not the parser — the three arms are
genuinely different features in what they MEAN, not in what they cost to build,
which is why the parse work did not have to wait. See the resolution note on the
Track P ticket.

## Recommendation

**Stay at (i) unless real source turns up that wants (ii).** The evidence that
would settle it is an FPC/Delphi `library` someone actually ships whose `exports`
list names non-`cdecl` routines and which is meant to be linked by something
that is not pxx. Absent that, the diagnostic is doing its job. If (ii) is ever
chosen, `exports` should still WARN rather than change the convention in silence.
