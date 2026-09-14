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
status: done
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

## Resolution (2026-09-14)

Both halves, as set out above, with one correction the measurement forced.

**The parser still claims the `**` shape, and the line is CAPABILITY, not
taste.** Dropping the claim entirely -- the clean version -- broke
`def fill(m): m.update(**{"c": 3})`, which then bound against
`TPyList.setupdate(other)` and died with `forwarded call has no value for
parameter 'other'`: the same defect wearing the list class instead of the dict
one. A NAMED keyword reaches the dynamic dispatcher as a kwspec string parallel
to the arguments; a `**` has no dynamic-call shape to travel in at all. So the
parser keeps exactly the calls that must be bound at parse time and stops
guessing about the ones that need not be. `PyDictKwRunFrom` was split into
`PyKwRunFromKind(start, starOnly)` so the two halves are one scanner, and
`PyDictKwOverloadAhead` took the flag; the STATIC path passes False and is
unchanged.

**The residual, stated rather than hidden:** a user class with
`def update(self, **kw)` reached through an untyped receiver and called with
`**` still binds `TPyDict.update`. That was true before this change for every
keyword spelling; it is now true for one. Closing it needs a dynamic call shape
that can carry a `**`, which does not exist.

**A warning that fires on correct code.** With the claim dropped, every dynamic
`d.update(a=1)` -- correct code, correctly compiled -- printed *"no class here
declares a .update() with a parameter named 'a' -- dispatching on the receiver
at run time"*. True, and not a problem: on a dict receiver a keyword IS a key.
Suppressed by asking whether the call could have been `TPyDict.update` at all
(`dictKwMaybe`), which deliberately does NOT claim it. The same build prints 110
warnings and nobody reads the 111th.

### Guard

`test/test_nilpy_update_on_a_dynamic_receiver.npy`, eleven rows, expectations
from CPython. Three receivers (static, variant by rebinding, variant through a
parameter) x {positional, keyword}; a dict reached three ways including a
subscript result and an untyped parameter, with named keywords, `**` and mixed
positional-plus-keyword; and a control METHOD NAME (`tick`) on the same three
receivers, which is what stops a fix being credited to the name lookup rather
than to the keyword run. The dict rows are load-bearing in the other direction:
a fix that only taught the parser to leave user classes alone breaks every one
of them.

The user-class row is LAST on purpose -- every row above it has a dict
somewhere, and a run that only ever met a dict is the run that certified this
bug for as long as it existed.

Reverted, the fixture dies at row 2 with the original message. The 45-row
keyword matrix and the 90-row positional matrix both match CPython, and
`test_nilpy_dict_update_keywords` and `test_nilpy_dict_update_variant` pass.

### What it cost the demo, and what it bought

**lekkerzeilen runs on the open-water entry points.** `--open-water` under
`setarch -R`, sources byte-identical to the owner's tree: 19m16s of wall clock,
1149s of CPU across 13 threads, state R throughout, no exception, ended only
because it was killed. Confirmed independently by **lekkerzeilen-c8** at a 200s
cap, and `--m0` likewise.

**The world path is NOT covered by that claim, and my first report of it was
wrong.** I ran `--silent` five times under `timeout 20`, got rc=124 five times,
and reported it clean. It dies at **36.1s +/- 0.3**, so every one of those runs
ended before the defect could occur: five agreeing runs measured my own clock.
The peer reached the same false negative independently at a 25s cap, 10/10, and
caught it only by raising the cap to 90.

A timeout cannot fail below its own threshold, so a survival rate taken under
one is evidence about the window, not about the program. The tell was sitting in
my own numbers: `--open-water` survived nineteen MINUTES while the world path
"survived" twenty SECONDS, and I read the two as one result. Where a deadline is
suspected, report the TIME OF DEATH rather than a pass count.

What this fix did buy on the world path is real and smaller: it was a
**deterministic 3/3 rc=139** at 80840e14f, arriving before the frame loop. It
now reaches the frame loop and runs for 36 seconds. That is a different failure
at a later point, not this one surviving.
- 2026-09-14 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit d8424f01c.
