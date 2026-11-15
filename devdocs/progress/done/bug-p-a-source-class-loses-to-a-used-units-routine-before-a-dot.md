---
slug: bug-p-a-source-class-loses-to-a-used-units-routine-before-a-dot
track: P
prio: 70
type: bug
status: done
created: 2026-11-15
found-by: pxx (kernels seat): a relocation test for --os=nt declared `TB = class(TA)`
tags: [pascal, scope, kernels]
blocked-by: []
summary: "`type TB = class(TA)` then `TB.Create` failed with \"class method not found (Create)\" when a used unit had a routine named TB: the expression path bound the name to the routine (procIdx >= 0), so the constructor arm never ran. The kernel translators made it target-dependent: every --os=freebsd/netbsd/openbsd/dragonfly/nt program pulls its translator in unasked, winabi has a `procedure TB` and fbsdabi a `PathIs`, so a program's own class of either name built for Linux and not there. Now a class declared in the unit being compiled beats a used unit's routine in front of `.` (the twin of the type-alias-before-`(` rule beside it). Test: test/test_p_a_class_beats_a_used_units_routine_before_a_dot.pas (-Itest/class_routine_shadow)."
---

# A program's own class lost to a used unit's routine before `.`

The rule was already written for a type alias in front of `(` (a cast) in
pasparser_expr.inc; the class-in-front-of-`.` arm was missing. Ordinary user
units hit it too (a `procedure TB` in a unit's interface), but nobody had a
reason to; the translators' implementation-section helpers are also visible
to the program because they load as ambient units.
