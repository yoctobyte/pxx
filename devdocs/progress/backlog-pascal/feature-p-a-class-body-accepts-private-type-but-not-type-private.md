---
slug: feature-p-a-class-body-accepts-private-type-but-not-type-private
title: "A class body accepts `private type` but refuses `type private`; FPC takes both orders"
track: P
prio: 25
type: feature
blocked-by: []
status: open
owner: ""
created: 2026-09-06
summary: "In a class body `private type TF = (one, two);` compiles and `type private TF = (one, two);` is refused with `expected ':' before '='`. FPC accepts both orders. Measured 2026-09-06 by probe; ranked low because the second order is the rarer spelling and nothing miscompiles -- it is a refusal, not a wrong answer. Found dispositioning tclass10b, whose `%FAIL` was satisfied by this gap rather than by its own subject (that a visibility section after `type` resets the section so a following field decl is illegal)."
---

# The measurement

```pascal
type TFoo = class
     private type              { ACCEPTED }
       TF = (one, two, three);
     private
       f: TF;
     end;
```

```pascal
type TFoo = class
     type private              { REFUSED: expected ':' before '=' }
       TF = (one, two, three);
     ...
```

# Ranked 25 on purpose

`private type` is the commoner spelling and works, so real code mostly does not
hit this; and the failure is a clean refusal at compile time, never a wrong
answer. It is here so the gap is recorded rather than rediscovered, and because
it is currently propping up a `%FAIL` corpus row that is not testing it.

`task-t-twelve-syntax-shaped-fail-rows-may-be-refused-by-a-parse-gap-rather-than-their-own-subject`
