---
track: P
prio: 40
type: feature
status: done
found: 2026-08-31
found-by: frank-user-a2, shape confirmed by frankC
owner: "frankD"
blocked-by: []
summary: "DONE — `library foo;` parses, and `exports` is CHECKED against the object writer's own export predicate rather than merely accepted: a name that is not a routine, is `external`, is C `static`, or is not `cdecl` is an error at the exports clause. The fork the ticket named is answered at the REJECT arm and re-filed as decide-may-exports-name-a-routine-that-is-not-cdecl, because reject is the only arm that can be relaxed later without breaking a program that compiles today. Verified by linking the object into a gcc-built C host and calling it."
---

# A Pascal `library` unit does not parse

> **RESOLVED 2026-09-04 (frankD, Track P).**
>
> ## What landed
>
> - `compiler/defs.inc` — `tkLibrary`, `tkExports` appended at the TAIL of
>   TTokenKind (no existing ordinal moves; told frankA first, per CLAUDE.md's one
>   coordination rule, and he confirmed no collision). `IsLibrary`,
>   `ExportName`/`ExportLine`/`ExportCount`.
> - `compiler/lexer.inc` — both keywords in the length-7 bucket.
> - `compiler/pasparser_prog.inc` — `ParseExportsClause`, `ValidateExports`, a
>   `tkLibrary` arm beside `tkProgram` in the header, a `tkExports` arm in the
>   pass-1 declaration loop.
> - `docs/reference/directives.md` untouched; this is syntax, not a directive.
> - `test/test_library_exports.pas` + `test/library_exports_host.c` wired into
>   `test-emit-obj`; four `*_fail.pas` refusals wired into `test-core`.
>
> ## The fork, answered — and re-filed rather than swallowed
>
> The ticket said to settle "may `exports` name a routine that is not `cdecl`?"
> before writing the parser. Answered at **reject**, and filed as
> [[decide-may-exports-name-a-routine-that-is-not-cdecl]] so the user still owns
> the relaxation. Three reasons it did not have to block the parse work:
>
> 1. **Option (iii) — export it under the pxx convention, which is FPC's literal
>    behaviour — is already ruled out by rules we have.** It produces a silently
>    wrong artifact (the caller marshals SysV, the body reads the internal
>    convention), and the compat ceiling says to prefer the answer that leaves
>    the mistake visible. FPC's answer is not a specification for a construct
>    only a mistake produces.
> 2. **Reject is the reversible arm.** Relaxing it later breaks nothing —
>    sources that were an error start compiling. Choosing "imply cdecl" first
>    and reversing it breaks programs.
> 3. **The three arms differ in what they MEAN, not in what they cost to
>    build.** They are one predicate in `ValidateExports`, not three parsers, so
>    "pick before writing the parser" turned out to overstate the coupling. Said
>    plainly here because the ticket's framing is what deferred it for four days.
>
> ## What `exports` is worth, measured
>
> Nothing at all as a *capability*: `ObjProcIsExported` is
> `ProcCdecl and not ProcCStaticLink` and the writer has always exported exactly
> that set. `test_library_exports.pas` produces the same object a `program` with
> the same three routines produces. What it buys is the **check** — four ways to
> write an export that would not appear in the surface are now errors at the
> `exports` line instead of a missing symbol at someone else's link step, which
> is the same failure class `bug-pascal-include-search-silent-miss` closed one
> layer down.
>
> `exports … name '…'` and `exports … index N` are **diagnosed, not ignored**.
> Accepting and dropping a rename writes a library whose symbol is not the one
> the source asked for — the same silent-wrong class the cdecl check exists for.
>
> ## The bug found on the way, and it is a general trap
>
> `ValidateExports` was first placed after declaration pass 1, which is where
> "every header is registered" says it belongs. It reported **every** exported
> routine as not-`cdecl`, including ones the object writer went on to export
> correctly — a check contradicting the writer it was supposed to agree with.
> Cause: the pre-scan arm of `ParseSubroutine` exits before the calling-convention
> directives are applied, so **`ProcCdecl` is only set when the BODY is parsed**.
> Moved to after pass 2. Anything else that wants to reason about a routine's
> convention during pass 1 has the same problem waiting for it.
>
> ## Gate
>
> `make compiler/pascal26` — `converged after 1 round(s)`, `6df6ef519b8e`.
> `tools/gate.sh quick` — `gate: GREEN (exit 0)` with `PASS  FPC seed canary`,
> run before committing so the canary was live rather than SKIP.
>
> **The proof is the link, not the symbol table.** `nm` showing `T PxxLibAdd`
> proves a NAME; only calling it from a gcc-built C host proves the CONVENTION,
> which is the entire thing the cdecl check protects. `library_exports_host.c`
> prints `42 / 42 / -42`. `Hidden` — not exported, not `cdecl` — is asserted
> ABSENT from the global block, because without that row every assertion in the
> test passes on a compiler that exports everything, which is exactly the
> population the test is about.
>
> **A green I had to re-earn.** `check_test_wiring.py` first reported clean over
> these files and that green was worth nothing: `subjects()` is git-tracked-only
> **by design**, so brand-new untracked test files are invisible to it. Caught by
> its own positive control — a deliberately unwired probe scored 0 hits. Staged
> first, the probe scores 1 and the real files still report clean, which is the
> green that counts. (frankA flagged the adjacent `origin/master..HEAD` scoping
> trap in `gate.sh`'s wiring row the same evening; same shape, different range.)
>
> ## Still open, unchanged by this
>
> `--shared` for compiled sources ([[feature-a-shared-library-output-for-compiled-sources]])
> is a separate backend blocker, so `library` still does not by itself produce a
> `.so` — it produces a linkable `.o` under `--emit-obj`, which is what the C
> host test links.

## Original ticket

```
$ pascal26 --shared foo.pas foo.so
foo.pas:1: error: expected 'begin' before 'library'
```

Deferred by [[meta-a-pxx-produces-linkable-code]] until the object writer's
shape was known.

## What it is worth, now that the writer exists

**Less than it looked.** The reason to want `library` was that nothing could
express an export surface. Something can:
[[feature-a-a-general-x86-64-relocatable-object-writer]] exports the
C-convention routines (`ProcCdecl`) under their own names, so a `cdecl` on the
definition is already the working spelling.

`library` + `exports` would be a second, *declarative* spelling of the same
thing — worth having for source compatibility with real FPC/Delphi code, which
is the compat axis, not the capability one. Hence p40.

## The design question to settle first, because it is not cosmetic

**May `exports` export a routine that is not `cdecl`?** FPC lets you, and the
object writer deliberately does not: an internal-convention routine exported
under its Pascal name is *callable and wrong* from anything outside pxx — the
foreign caller marshals SysV, the callee reads pxx's internal convention, and
nothing diagnoses it.

Three answers are available and they are genuinely different features: reject
it; accept it and make `exports` imply `cdecl`; or accept it and export it under
the pxx convention for pxx-to-pxx linking. Pick one **before** writing the
parser — this is a Track U-shaped fork sitting inside a Track P ticket, and
the compat ceiling applies (we do not chase FPC parity; we care that correct
Pascal compiles correctly).

Note also that `--shared` for compiled sources is a separate blocker with its
own backend dependency — [[feature-a-shared-library-output-for-compiled-sources]] —
so `library` landing does not by itself produce a `.so`.

## Umbrella

[[meta-a-pxx-produces-linkable-code]]

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
