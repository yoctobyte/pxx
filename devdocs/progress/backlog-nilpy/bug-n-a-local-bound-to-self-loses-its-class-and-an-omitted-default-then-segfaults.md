---
slug: bug-n-a-local-bound-to-self-loses-its-class-and-an-omitted-default-then-segfaults
title: a local bound to `self` loses its class, and an omitted defaulted argument through it then segfaults
summary: >
  `o = self` inside a method gives a local that is tyClass with NO class recorded
  (`n.locals`: `o tk=6 rec=0`). Calling a method through it works with an
  EXPLICIT argument and SEGFAULTS when a defaulted argument is omitted. `o = C()`
  in the same position is fine, so it is the inference of `self`'s class onto a
  plain local, not the call. PRE-EXISTING: identical on pin v408 and at HEAD, so
  it is not a regression from either marshalling fix landed 2026-09-13.
track: N
type: bug
prio: 35
owner: unassigned
status: backlog
---

## What was measured

2026-09-13. Found while fixing
`bug-n-a-method-s-non-constant-default-is-none-when-the-call-is-inside-the-class`
— this is the same concept (fill an omitted argument for an intra-class call)
reached by a different receiver spelling, which is why it is filed rather than
left as a loose end.

    class C:
        def m(self, n=30):
            return n

        def inside_alias(self):
            o = self
            return o.m()

        def inside_new(self):
            o = C()
            return o.m()

    def outside_alias(c):
        o = c
        return o.m()

    c = C()
    print("A", c.m())                  # 30   both
    o = c
    print("B", o.m())                  # 30   both
    print("C", outside_alias(c))       # 30   both
    print("D", c.inside_new())         # 30   both
    print("E", c.inside_alias())       # 30 CPython, SEGFAULT pin v408 AND HEAD

Row E is the whole ticket, and rows A–D are there because each of them is the
same call through a route that works — so the ticket cannot be read as "method
calls through a local are broken".

Narrowed further: with an EXPLICIT argument the same route is fine, and a
parameter with no default is fine too.

    def a_explicit(self):   o = self;  return o.m(5)        # 5  both
    def b_nodefault(self):  o = self;  return o.nodefault(5)# 5  both
    def c_omitted(self):    o = self;  return o.m()         # SEGFAULT

So the crash needs BOTH the `o = self` receiver and an omitted defaulted
argument.

## What is wrong

`PXXDBG=n.locals` says it in one line:

    C.via_local  o tk=6 rec=0 | sym=<none>

tk=6 is tyClass, and rec=0 is REC_NONE — a statically class-typed local with no
class behind it. That combination is the broken state: being tyClass picks the
STATIC dispatch route, and the static route's omitted-argument fill needs the
receiver's class to complete the call. `o = C()` records the class and works; a
PARAMETER is tyVariant and takes the runtime-dispatch route, which works too.

The AST is not where it goes wrong, and this is worth saying because it is the
first place anyone will look: `PXXDBG=a.ast` for the working `self.m()` and the
crashing `o.m()` are **structurally identical** — both `AN_VIRTUAL_CALL` with
the same proc index and the same `[receiver, AN_INT_LIT 30]` argument chain.
The difference is entirely in what the receiver SYMBOL records.

The inference arm that handles `w = self.lookup(k)` is at pyparser.inc ~5835
(`bug-nilpy-self-method-call-loses-return-class`) and covers a POSTFIX chain on
`self`. A bare `o = self` has no postfix and does not reach it.

## Why prio 35

Nothing measured asks for it. `o = self` is a rare spelling — it appeared here
only because it was written as a probe to vary the receiver route while holding
the callee fixed. The crash is loud rather than silent, which is the better
failure. Raise it if real source turns up.
