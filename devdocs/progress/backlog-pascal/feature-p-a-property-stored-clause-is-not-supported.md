---
slug: feature-p-a-property-stored-clause-is-not-supported
title: "A property's `stored` clause is refused, on ordinary published properties FPC accepts"
track: P
prio: 45
type: feature
blocked-by: []
status: open
owner: ""
created: 2026-09-06
summary: "`published property F: Integer read FF write FF stored False;` is refused with `expected ':' before 'False'`. FPC accepts it, and `stored` is a STREAMING attribute -- it decides whether a property is written out -- so the consumer is `lib/pcl`, our own widget set, and any .lfm round-trip. Measured 2026-09-06 by probe while dispositioning tclass14a, whose `%FAIL` was being satisfied by this gap rather than by its own subject (that `stored` is invalid on a CLASS property specifically)."
---

# The measurement

```pascal
program p; {$mode delphi}
type TC = class
     private FF: Integer;
     published property F: Integer read FF write FF stored False;
     end;
begin end.
```

```
pascal26: error: expected ':' before 'False'
```

FPC accepts this. The clause also takes a field or a parameterless boolean
method (`stored FIsStored`, `stored GetStored`), not only a constant.

# Why it is ranked here rather than lower

`stored` is not decoration: it is what a streaming system asks before writing a
property out, so it is load-bearing for anything that persists a component. We
ship `lib/pcl` and `test_pcl_lfm` reads an `.lfm`. A form that round-trips
through us today cannot express "do not persist this property".

# How it was found, which is the part worth keeping

Dispositioning `tclass14a`, a `%FAIL` row whose own comment says *"class
properties are not for sreaming therefore 'stored' is not supported"*. pxx
refuses the row, so it counted as a pass — **for the wrong reason**. The
discriminator was probing the construct where it is LEGAL: an ordinary published
property. That is refused too, so the row was never testing its own subject.

`task-t-twelve-syntax-shaped-fail-rows-may-be-refused-by-a-parse-gap-rather-than-their-own-subject`
