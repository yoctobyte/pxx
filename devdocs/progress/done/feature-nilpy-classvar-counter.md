---
track: N
prio: 55
type: feature
---

# NilPy: ClassVar storage, next(), counter shim, lambda default_factory

Part of [[feature-nilpy-corpus-uforth]] milestone 1 — the current uforth
parse wall (Word.xt_id):

    xt_id: int = field(default_factory=lambda: next(Word._xt_counter))
    _xt_counter: ClassVar = None    # later: Word._xt_counter = _count(1)

Chain needed: (1) ClassVar class-level statics readable/writable as
Class.name (pxx has Pascal `class var` machinery — FindClassVar — to map
onto); (2) an itertools.count shim (pylib TPyCounter with a next method);
(3) next(x) builtin -> x's next method; (4) `field(default_factory=<expr>)`
evaluating <expr> per construction — the general form beyond the shipped
`=list` case; a restricted zero-arg lambda body is enough for uforth.

Semantics to preserve: unique increasing xt ids per Word creation.
