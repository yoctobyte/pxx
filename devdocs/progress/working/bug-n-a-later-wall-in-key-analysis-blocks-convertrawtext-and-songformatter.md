---
prio: 55
track: N
type: bug
blocked-by: []
summary: "convertrawtext.py and SongFormatter.py fail at key_analysis.py:82 (`tonic, mode = label.split(\" \", 1)`) with `unexpected token`. Pre-existing, was hidden behind the grid keyword-call refusal. Does NOT reproduce standalone or through a plain from-import — needs more of convertrawtext.py's context, not yet minimised."
status: working
owner: frankwasm
---

# A later wall at key_analysis.py:82 blocks convertrawtext.py and SongFormatter.py

- **Type:** bug — Track N. Filed 2026-08-30 by frankwasm out of
  [[feature-demo-songformatter-pxx-target]].
- **Pre-existing, not a regression.** See the attribution below; this was
  simply behind
  [[bug-n-a-methods-keyword-call-drops-a-tuple-argument-when-an-earlier-default-is-skipped]]
  until that landed.

## What happens

```
pascal26:82: error: unexpected token
  near: label  split     >>>
Expected: ), but got:  (Kind: 2, Line: 82)
```

The line is in `key_analysis.py`, not in the file being compiled:

```python
def _key_label_to_parts(label: str) -> tuple[str, str]:
    if label.endswith("m") and " " not in label:
        return (label[:-1], "minor")
    if " " in label:
        tonic, mode = label.split(" ", 1)      # <- line 82
        return tonic, mode
    return (label, "major")
```

Note the reported line number belongs to an **imported module**, so it is not
on the same scale as the line numbers of the file on the command line. Reading
it as "the failure moved earlier in convertrawtext.py" is wrong, and is what it
looks like at first glance.

## Attribution — pre-existing, measured

Compilers built from the same base, one with and one without the keyword-call
fix that unblocked the earlier wall:

| compiler | convertrawtext.py (tuple pads neutralised in a copy of the app) |
| --- | --- |
| `f8f879988222` — **without** the fix | `82: error: unexpected token` |
| `bcb428ba25ac` — with the fix | `82: error: unexpected token` |

The copy has every `padx=(a, b)` / `pady=(a, b)` rewritten to its first element,
which removes the earlier refusal so the **baseline** can reach the same depth.
Both compilers then fail identically. Without that step the baseline stops at
the grid call and never reaches this, which is the whole reason the wall looks
new.

## What does NOT reproduce it

All of these compile clean, on both compilers:

- `key_analysis.py` on its own
- `import key_analysis`
- `from key_analysis import analyze_key` (the spelling `convertrawtext.py` uses)
- `from settings import get, set, getF, getI` followed by the above
- the `_key_label_to_parts` shape extracted on its own

So it needs more of `convertrawtext.py`'s context than any of these carry, and
**it is not minimised**. That is the first job on this ticket; the shape above
is where to start, not a diagnosis.

## A second, probably separate observation from the same file

`convertrawtext.py:1387` rebinds the imported module's own name as a variable
(`key_analysis = analyze_song_key(...)` alongside `from key_analysis import
analyze_key`). Reduced to:

```python
from key_analysis import analyze_key
def f(song):
    key_analysis = analyze_key(song)
    return key_analysis
```

→ `no overload of analyze_key matches these arguments`, **identically on both
compilers**, so also pre-existing. It is probably NOT about the name reuse: the
same shape against a throwaway module (`from mymod import analyze` with a local
named `mymod`) compiles and matches CPython. Something about `analyze_key`'s own
signature is what the overload probe rejects. Recorded here rather than filed
separately until one of the two is minimised, in case they turn out to be one
defect.

## Impact

`settings.py` and `key_analysis.py` compile. `convertrawtext.py` and
`SongFormatter.py` do not, so this is the current wall for
[[feature-demo-songformatter-pxx-target]]. `render_backend.py` is blocked by a
different animal — [[bug-nilpy-render-backend-py-compile-does-not-terminate]] —
which is no answer rather than a wrong one.

---

## MINIMISED, 2026-08-30 (frankwasm)

### Correction first: the `analyze_key` lead in this ticket was wrong, and it was mine

The section above records `key_analysis = analyze_key(song)` failing with
`no overload of analyze_key matches these arguments` on both compilers, offered
as "a stronger lead". **It is not a defect.** `analyze_key`'s parameters after
`chords` are keyword-only, and `chord_to_notes` is required:

```python
def analyze_key(
    chords: list[str],
    *,
    chord_to_notes: Callable[[str], list[str]],
    ...
```

CPython rejects the same call: `analyze_key() missing 1 required keyword-only
argument: 'chord_to_notes'`. So pxx refusing it is **correct behaviour**, and I
wrote an invalid call and recorded it as evidence. Corrected in place rather
than deleted, because the wrong lead is the reason the next section took the
route it did. (Keyword-only parameters themselves work: `def f(a, *, b)`,
`*, b=5` and mixed forms all match CPython.)

### The real defect, in two lines plus a unit

```python
# mod.py
def zzzz(label: str):
    tonic, mode = label.split(" ", 1)
    return tonic, mode
```

```python
# main.npy
import 'usesutil.pas' as u      # any unit whose `uses` clause names sysutils
from mod import zzzz
print(zzzz("C minor"))
```

→ `pascal26:2: error: unexpected token`, `near: label split >>>`.

CPython prints `('C', 'minor')`.

### Mechanism — confirmed by prediction, not by story

`sysutils` declares a **string helper** taking one argument:

```pascal
    function Split(const Separators: array of Char): TStringArray;
```

Python's `str.split(sep, maxsplit)` takes **two**. When the receiver is
statically a `str`, the two-argument Python call is matched against the Pascal
helper, and the parse dies on the second argument.

The prediction that confirms it: `rsplit` has the identical Python shape and
**no** sysutils helper, so it must work where `split` does not.

| call | sysutils declares it? | result |
| --- | --- | --- |
| `label.split(" ", 1)` | yes, 1-arg | **ERR** |
| `label.rsplit(" ", 1)` | no | ok |
| `label.split(" ")` | yes, 1-arg | ok |
| `label.partition(" ")` | no | ok |

### The four conditions, each necessary

| condition | drop it and | 
| --- | --- |
| a unit that pulls **sysutils** is imported first | ok |
| receiver is **statically `str`** (`: str` on a param or local) | ok |
| `.split` called with **two** arguments | ok |
| the module is **pulled as a unit**, not compiled directly | ok |

`pathlib` and `json` trigger it because their `uses` clauses name sysutils;
`configparser`, `re`, `io`, `collections`, `typing`, `dataclasses` do not and
are clean. It is not a capacity effect — pathlib is 250 lines against
configparser's 401.

This fully explains the original report: `key_analysis.py:82` is
`tonic, mode = label.split(" ", 1)` inside
`def _key_label_to_parts(label: str) -> tuple[str, str]`, `key_analysis` is
pulled as a unit, and `convertrawtext.py` imports `pathlib` at line 49.

### One observable I could NOT explain, recorded rather than guessed

The **function's own name** changes the outcome, deterministically (three runs
each), with everything else byte-identical:

| name | result | | name | result |
| --- | --- | --- | --- | --- |
| `f` `g` `q` `z` (1 char) | ok | | `aa` `ab` `ff` `gg` `zz` `qq` `abc` `xyz` | ERR |
| `word` `item` `value` `chunk` `part` `parts` `split` | ok | | `aaaa` `zzzz` `xxxx` | ERR |

It is not length (`word` ok, `aaaa` ERR) and not presence in the RTL (`ff`
occurs in 6 RTL files and fails; `tonic` occurs in none). The names that pass
are real words and single letters; the ones that fail are invented sequences.
**I do not know why, and I am not going to invent a rule for it** — it is
recorded so the next holder does not have to rediscover that the name is a
variable at all. The mechanism above reproduces regardless, on any failing
name.

Warning for anyone sampling names here: `label`, `tonic` and `mode` *look*
like passes and are not — they compile and then return wrong values, because
the function name collides with one of its own locals. That is a separate
defect, filed as
[[bug-n-a-local-named-after-its-own-def-aliases-the-function-result]].

---

## ROOT-CAUSED, 2026-08-30 (frankwasm) — and it is bigger than `split`

### The site

`compiler/pasparser_lval.inc:275-308`, the **TYPE-HELPER dispatch**:

```pascal
  if (idx >= 0) and (CurTok.Kind = tkDot) and
     (Syms[idx].RecName < REC_UCLASS_BASE) and (not Syms[idx].IsArray) and
     not (Syms[idx].TypeKind in [tyRecord, tyClass, tyVariant, tyPointer]) and
     (TokPos < TokCount) and (Tokens[TokPos].Kind = tkIdent) then
  begin
    mci := FindHelperForType(Syms[idx].TypeKind, Syms[idx].RecName);
    if (mci >= 0) and ((FindUMeth(mci, GetTokenStr(TokPos)) >= 0) or
                       (FindUProp(mci, GetTokenStr(TokPos)) >= 0)) then
    begin
      ...
      Result := node;
      Exit;
    end;
  end;
```

**There is no `isNilPy` guard.** `sysutils.pas:100` declares
`TStringHelper = type helper for AnsiString`, so once any imported unit pulls
sysutils, a NilPy receiver statically typed `str` has a helper in scope. This
block `Exit`s with the Pascal helper before the NilPy str-method loop in
`pasparser_expr.inc:8559` (`PyIsStrBaseTk` → `PyParseStrMethod`) is ever
reached. **The Pascal helper wins over the Python method, silently.**

### The collision set is four names, not one

Pascal member lookup is case-insensitive, so `TStringHelper`'s surface collides
with Python's `str` on:

| Python | TStringHelper | how it fails |
| --- | --- | --- |
| `split(sep, maxsplit)` | `Split(array of Char)` | **arity** → `unexpected token`, the reported wall |
| `startswith(tuple)` | `StartsWith(AnsiString)` | **argument type** → `no overload of startswith matches these arguments` |
| `startswith(str)` | `StartsWith(AnsiString)` | **compiles** — silently the Pascal method |
| `endswith(str)` | `EndsWith(AnsiString)` | **compiles** — silently the Pascal method |
| `replace(old, new)` | `Replace(Old, New)` | **compiles** — silently the Pascal method |

Measured, same file, only the def's name changed (see below):

```
label.startswith(("C", "D"))   helper reached  -> no overload of startswith matches these arguments
label.startswith(("C", "D"))   helper missed   -> ok
```

The last three rows are the reason this matters beyond one wall: they are the
**silent-wrong-behavior** class, so by CLAUDE.md's compat escape rule they are a
`bug-`, not a compat item. `str.replace` takes an optional third `count`;
`TStringHelper.Replace`'s third parameter is `TReplaceFlags`. Any NilPy program
that reaches the helper and passes three arguments gets a different function
under the same spelling.

### What the def-name effect actually is

The unexplained name table above is now localised, though not explained: the
name decides whether `FindHelperForType` / `FindUMeth` at line 288 **finds** the
helper. Failing names are the ones where it succeeds. Re-measured tonight on
`9ea7174aa`:

```
ok :  a  b  f  a1  a2  word  split
ERR:  aa ab zz ff qq zzz aaa abc foo bar baz parse tonic x1 zzzz wzzz zzzw zzzz2
```

`return label.split(" ", 1)`, `x = label.split(" ", 1)` and
`tonic, mode = label.split(" ", 1)` all behave identically, so the tuple-unpack
in the original report was **not** a condition — only the name is. I do not know
why the name moves the lookup, and I am not guessing; but the fix below makes
it moot for every str method, which is why chasing it further is not on the
critical path.

### Proposed fix (NOT applied — needs a Track A grant)

One condition at `pasparser_lval.inc:283`: in NilPy mode, when the receiver is a
str base and the member names a known Python str method (`PyStrMethodInfo`),
skip the type-helper dispatch and let `PyParseStrMethod` have it. Python's
`str` surface owns its own spellings; the Pascal helper is for Pascal receivers.

**File ownership:** `pasparser_lval.inc` is Pascal-frontend ground shared with
Track A — same situation as the `pasparser_call.inc` change in
[[bug-n-a-methods-keyword-call-drops-a-tuple-argument-when-an-earlier-default-is-skipped]],
which needed a grant and A's gate (`gate.sh quick`), not just the fixedpoint.
Not applied under Track N.
