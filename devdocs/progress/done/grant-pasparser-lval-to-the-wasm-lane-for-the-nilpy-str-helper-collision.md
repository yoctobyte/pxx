---
slug: grant-pasparser-lval-to-the-wasm-lane-for-the-nilpy-str-helper-collision
track: A
prio: 55
status: done
---

# GRANT: `compiler/pasparser_lval.inc` → the wasm lane, for the NilPy str/helper collision

**Granted by the coordinator, 2026-08-30.** Filed on master because *an
authorisation is a finding about what is permitted* — a grant that lives only in
message traffic reads as **covered** rather than as missing, because a
neighbouring ticket covers the same file. Direct precedent: `e268f9990`, the
`pasparser_call.inc` grant to the same lane, same reasoning.

## Scope

`compiler/pasparser_lval.inc`, the type-helper dispatch at ~275-308, for the fix
described in `bug-n-a-later-wall-in-key-analysis-blocks-convertrawtext-and-songformatter`
[N p55] — one condition that skips the Pascal type-helper dispatch when, in NilPy
mode, the receiver is a str base and the member names a known Python str method.

**Contention check at time of grant:** `pasparser_lval.inc` last moved **6 hours**
before the grant. `pasparser_expr.inc` is held by frankA (`managedlocalzerobytes`)
and is a **different file** — the two do not collide. `ir.inc` and `symtab.inc` are
frankC's (ptrdiff cell) and are out of scope here.

**Gate: Track A's, not just the fixedpoint** — `gate.sh quick` as well as
`make compiler/pascal26`, exactly as the `pasparser_call.inc` grant required. This
is Pascal-frontend ground shared with A, and the change alters member-lookup
precedence, which is reachable from every frontend that shares the dispatch.

## Why the finding earned an A-ground grant

The reported wall was one arity error. The root cause is **four** collisions,
because Pascal lookup is case-insensitive and `sysutils.pas:100` declares
`TStringHelper = type helper for AnsiString` — so any unit pulling sysutils puts a
Pascal helper in scope for every str-typed NilPy receiver, and the Pascal method
wins:

| spelling | outcome |
| --- | --- |
| `split(sep, maxsplit)` vs `Split(array of Char)` | arity → `unexpected token` (the reported wall) |
| `startswith(tuple)` vs `StartsWith(AnsiString)` | arg type → `no overload ... matches` |
| `startswith(str)` | **compiles, silently the Pascal method** |
| `endswith(str)` | **compiles, silently the Pascal method** |
| `replace(old, new)` | **compiles, silently the Pascal method** |

The last three are the **silent-wrong-behaviour class**, so by CLAUDE.md's compat
escape rule they are `bug-`, not compat. `replace` is the sharp one: Python's
optional third argument is a **count**; `TStringHelper.Replace`'s third is
`TReplaceFlags`. Same spelling, different function, no diagnostic.

That is what moves this from a NilPy parse failure to a shared-dispatch defect,
and it is why the fix belongs at the dispatch rather than in a NilPy-side
workaround. Python's str surface owns its own spellings.

## Recorded so it is not re-chased

The lane measured that the **name of the enclosing def** decides whether
`FindHelperForType`/`FindUMeth` finds the helper (`ok: a b f a1 a2 word split` /
`ERR: aa ab zz ff qq foo bar baz parse tonic ...`), and deliberately did **not**
chase it: the fix above makes it moot for every str method. Off the critical
path, not solved. It also **withdrew** the tuple-unpack from its own repro
conditions after measuring that `return`, plain assignment and unpack behave
identically — a correction to its own minimisation, which is the direction of
correction that costs something and nobody asks for.


## CLOSED 2026-08-30 — RETURNED UNUSED, and the grant should never have been asked for

The lane patched `pasparser_lval.inc`, measured **no change**, and a `PXXDBG` probe
on its own guard showed the block is **never asked during a NilPy parse**. The
type-helper dispatch is **duplicated**: the same block, comment and all, also sits
at `pyparser.inc:39038`, and that is the copy NilPy runs. So the fix was Track N's
own ground the whole time and needed no A-ground grant.

`grep FindHelperForType` is what found it, and would have found it before the ask.
The lane's own verdict: *"my escalation was correct in form and wrong in target."*

**This is not a failure of the grant process — it is the doctrine working.**
`the-substrate-is-ast-and-ir-not-the-parser.md` says share the AST and the IR and
**duplicate the parser per language**, so two copies of a dispatch block are the
intended design, not drift. The trap is that the duplication is invisible from the
Pascal copy: nothing at `pasparser_lval.inc:275` says a sibling exists, and a lane
reasoning about *"the type-helper dispatch"* will find one file and believe it is
the site.

**Generalisation worth carrying, and it inverts the usual advice.** This index keeps
recording *a parser that exists twice is one that gets fixed on one arm* — the
hazard of duplication. Here the hazard ran the other way: a lane found the **wrong**
arm, changed it correctly, and observed nothing, because the arm it changed was not
the one its language runs. **Before requesting access to a shared parser file, grep
the symbol across every frontend's parser** — if it appears in your own language's
parser too, that is your copy and the shared file is not involved.

Landed instead as `05eff4cc9`, entirely within Track N's files. All four collisions
match CPython; `s.Trim()` / `s.IsEmpty()` still reach the Pascal helper, so the
guard is **observed rejecting**, not only accepting.
