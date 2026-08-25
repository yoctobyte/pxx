---
track: P
prio: 60
type: bug
summary: "`stdcall`/`safecall`/`pascal`/`mwpascal` are accepted on a class METHOD declaration but are a parse ERROR on a plain routine, an `external`, or a procedural type — so FPC sources that spell a convention on a routine do not compile, and which spelling works depends on where it is written."
---

# Calling-convention directives are accepted in some positions and rejected in others

- **Type:** bug (Pascal frontend — dialect surface) — **Track P**, tag compat
- **Found:** 2026-08-03 while documenting calling conventions for
  `docs/language/dialect.md` (Track D discovery → ticket, not an inline fix).

## Measured

Same compiler, same directive, four positions. Identical on HEAD and on the
pinned binary, so this is shipped behaviour, not a regression:

| directive | routine w/ body | `external` | procedural type | method decl |
| --- | --- | --- | --- | --- |
| `cdecl` | ok | ok | ok (**and meaningful**) | ok |
| `register` | ok | ok | **REJECT** | ok |
| `stdcall` | **REJECT** | **REJECT** | **REJECT** | ok |
| `safecall` | **REJECT** | **REJECT** | **REJECT** | ok |
| `pascal` | **REJECT** | **REJECT** | **REJECT** | ok |
| `mwpascal` | **REJECT** | **REJECT** | **REJECT** | ok |

```
pascal26:2: error: unexpected token
  near:  Integer   >>> stdcall
```

A REJECT is a parse error, not a warning.

## Why it matters

The project's design rule is that a calling convention is the **target's** — the
markers are decoration (user, 2026-08-03: *"we just treat any calling definition
as pure decoration … any calling convention is host specific by definition"*).
Decoration should be *accepted and ignored*, uniformly. Instead the accepted set
depends on where the word appears, which is the worst of both worlds: it carries
no meaning, and it still refuses to compile real FPC code.

`stdcall` in particular is all over Windows-facing FPC sources, and
`safecall` all over COM-facing ones. A port hits a parse error on a directive
that would have been ignored had it been written one line lower, inside a class.

## The asymmetry in the code

Two independent lists, which is why they disagree:

- the routine-directive skip loop in `ParseSubroutine` (`compiler/parser.inc`,
  the `while ((CurTok.Kind = tkIdent) and (... 'inline' ... 'register' ...
  'cdecl' ...))` loop) accepts only `inline`, `register` and `cdecl` among the
  conventions;
- the method-declaration path uses a separate predicate that accepts `cdecl`,
  `stdcall`, `safecall`, `register`, `pascal` and `mwpascal` (guarded on a
  following `;`, since none of these are reserved words).

The procedural-type path accepts `cdecl` only.

## Fix shape

Give all four positions ONE predicate — the method path's set is already the
right one, and its `;` guard is what makes accepting non-reserved words safe
(a field named `register` stays a field because `register: Integer;` has a `:`
next). Accept and ignore, uniformly.

**Do not** make any of them change the ABI. `cdecl` on a **procedural type** is
the sole exception that must keep its meaning: it marks the signature C-ABI so
an indirect call through a C function pointer marshals correctly (measured:
without it a `dlsym`'d `double dtwice(double)` called through the type returns
21.0 for an argument of 21.0; with it, 42.0). Whether the other spellings should
also mark a procedural type C-ABI is a smaller question — on the supported
targets they would all mean the same thing as `cdecl`.

## Sequencing — deliberately left at prio 35

User, 2026-08-03, on whether to raise it: *"nah don't bother we will get there
once we start working on windows target."*

That is the right pairing: `stdcall` and `safecall` are Windows/COM spellings,
so the sources that trip over this are the ones a Windows port brings in.
Picking it up alongside [[feature-port-windows-pe]] also answers the open
sub-question here — whether the non-`cdecl` spellings should *mark* a procedural
type C-ABI — with a real target where the answer might not be "same as cdecl".

So the 35 is a decision, not neglect. Do not re-rank it on the grounds that it
is a parse error; take it when Windows work starts.

## Gate

Each of `cdecl`, `stdcall`, `safecall`, `register`, `pascal` and `mwpascal`
compiles in all four positions; `cdecl` on a procedural type still yields 42.0
through the dlsym probe; self-host fixedpoint byte-identical.

## Docs

`docs/language/dialect.md` documents the current uneven table as-is, plus the
procedural-type exception. When this lands, that table collapses to "accepted
everywhere, meaningful only on a procedural type" and the doc needs the edit.
