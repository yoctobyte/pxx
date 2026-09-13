---
slug: bug-n-the-lazy-builtin-constructors-and-divmod-are-still-not-values
title: the lazy builtin constructors and divmod are still not values
summary: >
  The remaining five of the twelve name-keyed builtins that refuse as a VALUE.
  `abs ascii chr hash id ord round` were fixed (one pylib helper each, bound
  through PyBuiltinValueHelper); `divmod enumerate filter map zip` were left out
  ON PURPOSE and still answer `undefined variable`. divmod is arity 2 returning a
  TPyList that PyProcIsFreshContainerCtor does not vouch for -- correctly, since
  its user-class exit returns whatever the program's own `__divmod__` gave and
  may alias -- so the wrapper's return side is declined. The other four are lazy constructors with
  SEVERAL pylib entry points picked from the argument's STATIC type
  (pymap_iter / pymap_iter_i / pymap_int / pymap_str / pymap_float ...), and a
  bare value has no argument to pick with -- binding one arm would silently mean
  the wrong one, which is the mistake min/max already embody.
track: N
type: bug
prio: 25
owner: unassigned
status: open
---

## What is already done

[[bug-n-abs-is-not-a-value-while-len-and-str-are]] censused twelve names and
fixed seven of them. The mechanism is `PyBuiltinValueHelper`, a
Python-name -> pylib-helper table consulted by `PyBuiltinValueNameAhead` from
BOTH doors into a callable value (assignment, and the factor chain for an
argument). Adding a name to that table is a one-line change **when the name has
exactly one helper with a wrappable signature**. These five do not.

## divmod -- one reason, and it is NOT the mechanical one it looks like

    function pydivmod_v(const a: Variant; const b: Variant): TPyList;

Arity 2 is fine: `PyGetOrMakeCallableWrapper` is arity-generic. The obstacle is
the RESULT. A tyClass return is only admitted when
`PyProcIsFreshContainerCtor` vouches that the callee returns a NEWLY
constructed container -- otherwise the wrapper would hand back a second owner of
an aliased object (the ARC gap
bug-nilpy-bound-fn-closure-objects-are-never-freed tracks). That predicate keys
on the PYTHON name (`list`, `tuple`, `dict`, `bytes`, `bytearray`, `reversed`,
and `sorted` in pyeval) and the helper here is called `pydivmod_v`, so it
answers False and the wrapper is declined.

**AND IT IS RIGHT TO, WHICH I ONLY FOUND BY READING THE BODY.** My first draft
of this ticket said `pydivmod_v` is obviously a fresh container ctor and that
adding it to the predicate was a one-line change. That is FALSE, and
PyProcIsFreshContainerCtor's own comment is why it insists the bodies be read
rather than inferred from the Python semantics. `pydivmod_v` has two exits
(pylib.pas around 9582-9621):

    numeric path      Result := TPyList.Create; ... append; append      FRESH
    user-class path   if PyUserObjDivmod(oa, ob, a, b, r) then
                        pydivmod_v := TPyList(r)                        NOT FRESH

The second returns whatever the program's own `__divmod__` handed back, which
may be a list the user still holds -- the exact aliasing case the predicate
exists to keep out. So `divmod` is NOT admissible as written, and vouching for
it would reintroduce the double-owner bug on any class defining `__divmod__`.

What it actually needs is one of: a wrapper that copies the result; a split so
the dunder path returns a fresh list; or a value-side entry point that is fresh
on both exits. Cheap, but not the one-liner it looks like -- and the shape of
the mistake (a routine that is fresh on the path you read first and aliasing on
the one you did not) is the general hazard for anything else added to that
predicate.

## enumerate / filter / map / zip -- a real design question

These are not one function each:

    enumerate   pyenumerate  pyenumerate2
    filter      pyfilter_call  pyfilter_iter  pyfilter_iter_i
    map         pymap_call  pymap_iter  pymap_iter_i  pymap_int  pymap_str  pymap_float
    zip         pyzip

The parser picks among them from the ARGUMENT's static type -- that is what
`pymap_iter_i` versus `pymap_iter` is, and `pymap_int`/`pymap_str`/`pymap_float`
are the conversion forms. A bare `map` taken as a value has no argument yet, so
there is nothing to pick with. Binding one arm would produce a callable that is
silently wrong for every other argument shape, which is exactly the defect
[[bug-n-min-and-max-as-a-value-bind-to-the-two-argument-arm-in-the-wrong-unit]]
describes -- do not repeat it here to close a row.

What these actually need is a single Variant-in entry point per name that
dispatches on the run-time tag, the way `pyabs_v` already does for `abs`. That
is a pylib addition, not a frontend one, and it is the honest shape of this
ticket. `zip` may be the cheap one -- it has a single entry already.

## Ranked low on purpose

`map(abs, xs)` -- the idiom that started the group -- works now. `map` ITSELF as
a value (`f = map`) is rare in real Python, and `filter`/`enumerate`/`zip` as
bare values are rarer still; they are almost always called immediately. divmod
is the most likely of the five to appear in real code, and is cheap but NOT
mechanical -- see the two-exit note above. Rank by that rather than by the count
of names.

## Positive control for whoever takes it

Any fixture here must assert the value form against MORE THAN ONE argument
shape, because the failure mode of a wrong pick is a callable that works for the
shape you tested. `map(str, xs)` versus `map(len, xs)` is the cheap pair: they
take different pylib arms today.
