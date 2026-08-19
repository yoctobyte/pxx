---
track: C
prio: 50
type: feature
blocked-by: [bug-c-definition-of-an-intrinsic-name-overwrites-the-pascal-routine]
summary: "Give C an explicit import site for a Pascal unit: `#include \"math.pas\"` declares its routines under mangled C identifiers (`math_pas_Sqrt`), case preserved from the Pascal declaration, path-qualified on collision. Overloads resolve by the declared C signature. AnsiString-bearing signatures are refused by name. Design settled by the user 2026-08-19; this ticket is a SPEC, not a discussion."
---

# C imports a Pascal unit under a mangled name

- **Track C** — C frontend files (`cparser.inc`, `cpreproc.inc`, C tests). Shared compiler
  internals stay Track A: a new AST node / IR op / symtab field → **file a Track A ticket**,
  do not edit under C.
- **Design settled by the user, 2026-08-19.** Every fork below was raised and closed in
  conversation. Do not reopen them on a hunch; if a MEASUREMENT contradicts one, say so
  here and escalate rather than choosing differently.

## Why

Pascal-into-C is an **intended, existing** capability — a C file today reaches Pascal
routines through implicit, global, case-insensitive `FindProc` matching. What it lacks is
not permission but a **name**.

That namelessness is the actual defect, and it is expensive:

- C has a flat global namespace, and `math.Sqrt` is not valid C, so there is no spelling
  for "the `Sqrt` in unit `math`".
- The match is **case-insensitive** while C is a case-sensitive language, so `sqrt` and
  `Sqrt` are one name. `lib/crtl/src/math.c:43` carries the consequence as a standing
  coding rule: *"never write a wrapper that calls the Pascal twin from its C namesake
  (`double sqrt(double x){ return Sqrt(x); }`): `Sqrt` binds case-insensitively back to the
  C `sqrt` and recurses forever."* A language hazard prevented by remembering.

**Case sensitivity gives distinguishability; mangling gives identity.** Both are needed —
that distinction is the design's hinge, and it is the user's.

## THE SPEC

### 1. The import site is an include

```c
#include "math.pas"
```

Chosen over a `#pragma` deliberately: gcc tries to textually include Pascal source and
**dies loudly**. An unknown pragma is silently ignored, producing a file that compiles
elsewhere and behaves differently — the worst failure shape. Honest non-portability beats
silent divergence.

### 2. Names are mangled, case preserved

`<unit>_<ext>_<Identifier>` — `math.pas` exporting `Sqrt` gives **`math_pas_Sqrt`**.

- **Case is preserved from the Pascal DECLARATION.** This is what makes the mangled name
  unable to collide with C's `sqrt`, so the infinite-recursion hazard above stops being
  spellable rather than being remembered.
- The `_pas_` infix earns its place: `math.pas` and `math.c` would otherwise both mangle
  to `math_`.

### 3. Collisions are path-qualified

Two units named `math` under different `-Fu` roots mangle identically. Then the path
participates: `path_math_pas_Sqrt`.

**State this property in the user docs, because the file that breaks is not the file
someone edited:** the short form is valid only while the unit name is unique across the
search path. Adding a second `math.pas` anywhere on the path invalidates every C file
using the short form. That fails loudly at compile time as an undefined symbol, which is
acceptable — but it is surprising unless documented.

### 4. Overloads resolve by the declared C signature — NOT a fork

Raised as a hard problem and dissolved by the user: it is not one.

```c
extern double math_pas_Max(double, double);
```

The C prototype names the unit, the routine, **and** the signature, in syntax C already
has. Resolve `math` → `Max` → the `(Double, Double)` overload by ordinary signature
matching. Pascal and C scalar types map cleanly, so this is mechanical.

**No suffix scheme. No `_ii` mangling. Nothing new to spell.** A declaration that cannot
discriminate (K&R `extern double math_pas_Max();`) is refused by name rather than guessed.

### 5. Non-mappable types are refused by name

Pascal types with no C spelling — `AnsiString`, sets, variants, open arrays — make a
routine **not importable**. Refuse at the declaration site, naming the routine. Partial
importability is expected and fine: a unit may export twelve importable routines and two
refused ones.

**`AnsiString` specifically, and the reasoning matters more than the rule** (user):

- `PChar` → `AnsiString` is fine; Pascal already owns that conversion.
- `AnsiString` → C has **no correct answer**. Hand C the buffer and you have handed out a
  reference the refcount does not know about; copy it and nobody owns the copy. There is
  no third option, so refusing is the honest one.
- **Returning `AnsiString` is refused unconditionally** — worse than a parameter, because
  there is no caller-side reference keeping the buffer alive and no way for C to release it.

**Recorded, deliberately NOT built:** a **`const AnsiString` parameter** is genuinely safe
— the Pascal caller holds the reference across the call, so the refcount is stable for the
call's duration and C sees an ordinary `const char*`. It is safe *provided the library does
not retain the pointer*, which is unverifiable from our side. That makes it a future
explicit opt-in, never a default. Written down so nobody re-derives it as a discovery.

### 6. The bare name is an EXPERIMENT, not a decision

Open question: should implicit cross-namespace binding be removed once the mangled name
exists? Two mechanisms for one concept is the shape this repo's own rules warn about — the
second path is the one that stays broken.

**Do not decide this by reasoning. Measure it.** `cparser.inc:9448` defends the implicit
bind on one ground: *"lua's `<math.h>` `sqrt`/`exp`/`sin`/… resolve to the RTL math
routines."* That justification may be stale — `lib/crtl/src/math.c` now DEFINES `exp`
(:282), `log` (:341), `sin` (:644), `cos` (:656), `atan` (:724) and `sqrt` (:965) in C,
correctly-rounded, and `CPullCrtlForPrototypes` pulls that module when a C file declares
those prototypes.

**The experiment:** delete the cross-namespace declaration bind and build the C corpus —
lua, tcc, quickjs, zlib. If nothing breaks, it was never a breaking change and there is
nothing to weigh. **If something breaks, those failures ARE the spec for what must stay.**
Report the result; do not quietly keep or quietly remove it.

## Sequencing

**`bug-c-definition-of-an-intrinsic-name-overwrites-the-pascal-routine` (C, p55) lands
first** and is a hard prerequisite. It is correct regardless of every choice above: a C
**definition** must never overwrite a non-C proc's body (`cparser.inc:9401` finds it,
`:9558` overwrites `BodyAddr`). A definition claims *this translation unit provides the
function*; that is a different act from a declaration, and only the declaration case has a
justification.

It is also currently producing a **silent wrong value out of the RTL** — `Sqrt(16.0)`
returns 42.0 when a C file in the same program defines `sqrt`, and `math.Sqrt` follows the
hijacked entry, so the qualified spelling does not save you.

## Gate

Track C's: C tests green + self-host byte-identical + cross. Land only green; incremental
or behind a flag, never a long-lived branch. New C tests should cover: the short form, a
path-qualified collision, an overload selected by prototype, and each refusal (AnsiString
param, AnsiString result, K&R declaration) failing by name at compile time.

## Provenance

Designed in conversation with the user, 2026-08-19, against measured code rather than
recollection. The coordinator raised overloads as a fork (it is not) and initially argued
the implicit bind should simply be deleted (premature — Pascal-into-C is intended and
works; it is the naming that is missing). Both corrections are the user's and are why the
spec has the shape it has.
