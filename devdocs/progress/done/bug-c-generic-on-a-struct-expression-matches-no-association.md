---
title: "C _Generic: a struct-valued expression matched no `struct X:` association"
status: done
owner: claude-dupwt
prio: 65
area: cfront
---

CExprCG gave a struct-typed identifier its record, but a struct-valued
EXPRESSION (`*(s)`, `h.a`, `p->m`) got a bare cgStruct with no record. It
then matched no `struct X:` association at all ("no matching association and
no default"). LinuxKPI's seqlock.h dispatches write_seqcount_begin/end as
`_Generic(*(s), struct seqcount: ..., struct seqcount_mutex: ...)`. Found in
the GPU-driver census (feature-nodisx-linux-gpu-drivers-built-by-pxx).

Fix: the expression arm of CExprCG fills the record from ResolveNodeRec when
the kind is a struct. Test row c_genstruct26
(test/c_generic_on_a_struct_expression.c), whose expected output is gcc's.
