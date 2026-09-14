---
slug: bug-n-a-keyword-call-to-update-on-a-dynamic-receiver-is-routed-to-dict-update
title: a keyword call to a method named update on a dynamic receiver is routed to dict.update
summary: >
  `obj.update(x, flag=True)` where the compiler has no static type for `obj`
  is dispatched to TPyDict.update unconditionally, so a user class with a
  method named `update` taking keyword parameters raises
  `TypeError: dict.update expects a mapping or an iterable of pairs`. The same
  call with only POSITIONAL arguments is correct, and so is the same call on a
  statically-typed receiver. `update` is the only name affected -- it is the one
  hardcoded. This is lekkerzeilen's current wall on every entry point
  (app.py:4162, `self.sound.update(self.boat, running=..., paused=...)`).
track: N
type: bug
prio: 70
owner: frank-user
status: open
---

## Repro

One file, no imports. Every row should print; two raise.

```python
class C:
    def __init__(self, n=0):
        self.n = n
    def update(self, a, b=True, d=False):
        return "update:%s %s %s" % (a, b, d)

def through_param(o):
    return o

c = 0            # rebound -> `c` is a VARIANT holding a C
c = C(1)
st = C(1)        # statically typed
pp = through_param(C(1))   # a variant arriving through a parameter

print(st.update(2, b=False, d=True))   # ok
print(c.update(2))                     # ok -- positional
print(c.update(2, b=False, d=True))    # TypeError: dict.update expects ...
print(pp.update(2, b=False, d=True))   # TypeError: dict.update expects ...
```

## What is and is not affected

Measured at 80840e14f, 45 rows: fifteen method names x {variant by rebinding,
static, variant through a parameter}, each called with two keyword arguments.
The same fifteen names called POSITIONALLY are a second 90-row sweep, all clean.

| | positional | with keywords |
| --- | --- | --- |
| static receiver | correct | correct |
| variant receiver, method named `update` | correct | **TypeError** |
| variant receiver, any of 14 other names | correct | correct |

The fourteen others are `tick get add keys pop count index append clear sort
copy setdefault read step` -- deliberately including several that ARE methods of
pylib's own containers (`get`, `add`, `keys`, `pop`, `append`, `sort`, `copy`,
`setdefault`), which is what says the cause is not "a name pylib also uses". It
is `update` specifically, because `update` is the one name written into the
compiler.

## Mechanism

`compiler/pyparser.inc` ~19566, in the dynamic method-call scan, after every
overload promotion and before the open-world fall-through:

```pascal
  dictKwHit := False;
  if isNilPy then
  begin
    i := PyDictKwOverloadAhead(FindUClass('TPyDict'), mname);
    if i >= 0 then
    begin
      hitCi := FindUClass('TPyDict');
      hitMmi := i;
      hitPi := UMthProc_[i];
      dictKwHit := True;
    end;
  end;
```

Its own comment states the premise:

> A KEYWORD run only ever means dict.update -- CPython's list and set take no
> keywords -- so the dict arm is the one answer, exactly as the static path
> picks it.

**"Only ever" is the clause to have measured.** It is true of `TPyList` and
`TPySet`, which is the population that was checked, and false of every USER
class: nothing stops a program declaring `def update(self, boat, running=True,
paused=False)`, and lekkerzeilen does. The arm then rewrites a correct dynamic
dispatch into a call on a class the program never named -- the same shape as the
`Wind.at has no parameter named 'outside'` case the paragraph immediately below
it was written to fix, with the roles reversed.

`PyKeywordsAreKeys` and `PyDictKwOverloadAhead` are correct about the STATIC
path, where the receiver's class is known to be TPyDict. The defect is only in
applying them where there is no receiver type at all.

## The fix, and why it is two halves

Neither half works alone.

1. **Parser.** Stop claiming the dict arm on a receiver with no static type.
2. **Runtime.** `PyDynMethL` (`compiler/builtin/pyeval.pas` ~5587) already
   dispatches on the receiver's own RTTI and binds keywords by PARAMETER NAME
   through `PyHostCall`. A `TPyDict` receiver with a keyword run has to be
   answered there instead -- the keywords are KEYS, so build the dict from
   `kwNames`/`args` and merge, with empty-named (positional) slots merged as
   mappings exactly as `pydict_merge_any` does.

That is where CPython decides it too: by the receiver's actual type, at the
call. Removing the parser arm without the runtime one regresses
`test_nilpy_dict_update_keywords` line 66 (`xs[0].update(r=1, s=2)`), which is
the shape the parser arm was added for.

A narrower parser-only repair exists -- claim the dict arm only when no
candidate class declares a parameter of the keyword's name, which the scan
already asks two paragraphs below -- but it stays a guess: a program with both
`def update(self, a=1)` on a user class and a genuine `d.update(a=1)` would
still be resolved by a coin toss, silently. Prefer the two halves.

## What it costs the demo

This is lekkerzeilen's single wall on every entry point at 80840e14f plus the
dunder fix. `app.py:4162`:

```python
self.sound.update(self.boat, running=self.boat.motoring,
                  paused=self.paused or self.flying is not None)
```

`self.sound` is `None` at app.py:879, a `Soundscape` at 4036 and `None` again at
4252 -- so it is a variant, which is the ordinary way an optional subsystem is
written. Located by instrumenting the top-level statements of the frame loop
with a marker naming the line each is ABOUT to run.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` carrying the matrix
above. The rows that must not move are `test_nilpy_dict_update_keywords` (all
of it, especially line 66's `xs[0].update(r=1, s=2)` -- a dynamic receiver that
really is a dict) and `test_nilpy_dict_update_mixed_positional_and_keyword`.
The positional rows belong in the same file as the keyword ones: they are what
stops a fix from being credited to the name lookup rather than to the keyword
run.

## Log
- 2026-09-14 -- filed from the lekkerzeilen frame loop, reached after
  `bug-n-arithmetic-on-a-user-class-fails-when-the-other-operand-is-object-typed`
  was fixed in pylib. Reduction is single-file and inline above.
