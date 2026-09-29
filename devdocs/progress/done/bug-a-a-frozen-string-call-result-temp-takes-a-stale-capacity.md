---
track: A
prio: 10
type: bug
blocked-by: []
status: done
found-by: borg full tier at 64db7e7 (test-pascal-conformance#shard2/6, toperator94.pp, exit 139), via frankuser; bisected by frankH
tags: [pascal, shortstring, operator, memory-corruption, cross-target]
summary: "The caller's hidden temp for a function returning a `string[N]` or ShortString was sized from LastTypeStrCap, which during IR lowering holds whatever string type the parser saw last, not the callee's result capacity. The callee copies ProcRetStrCap+1 bytes out, so toperator94's ShortString operator wrote 256 bytes into an 81-byte temp sized from a String[80] declared earlier. The temp is now sized from the callee's ProcRetStrCap in IRAppendCall and IRBuildHiddenDest."
owner: ""
---

# A frozen-string call result temp takes a stale capacity

toperator94 (pure Pascal, `class operator :=(const aArg: TTest2): ShortString`
stored into a `String[80]`) segfaulted after printing its second line. It
passed at v451 by luck. The overrun has been there all along, but it landed in
mapped .bss slack until ab63ffd350 added one runtime proc (PXXWriteVariantPy),
which moved the 81-byte temp to within 248 bytes of the end of the mapping.

Bisect (x86-64; toperator94 from the v451 tree): dcd5c7d, 7de3785917 and
e19f69611b exit 0. ab63ffd350, 3a406ba550, e375fbfd68, 91f79084c4, ff6115d2d1
and 863d1cc2df exit 139. ab63ffd350 does not change how this program is
compiled; it only shifts the layout.

gdb: the fault is in the operator's epilogue, `rep movsb` with rcx=0x100, into
r10=0x421f08, the caller's nameless hidden-dest sym, faulting at 0x422000.

## Fix

`IRHiddenRetStrCap(procIdx)` gives ProcRetStrCap, or DEFAULT_STR_CAP when that
is 0. Both hidden-dest allocation sites pin LastTypeStrCap to it around
AllocVar and restore it afterwards, the same way they already pin
LastTypeRecId.

## Test

test_a_shortstring_result_temp_holds_the_whole_result.pas puts the call in a
procedure with a 300-byte canary local declared first and a `String[10]`
declared last, so the overrun hits the stack deterministically instead of
depending on .bss layout. It matches fpc 3.2.2. On the v451 compiler the canary
takes 216 bytes of damage (212 on riscv32 and xtensa-windowed) on all six
targets; it takes 0 with the fix.

## Census: the other anonymous temps (2026-09-29, frankH, at db816a204d)

The same class would be any `AllocVar('', <kind decided at run time>)` that
can be a `string[N]` or ShortString. AllocVar reads the capacity of
tyShortString/tyFixedString from LastTypeStrCap. tyString gets 255 regardless
and is safe. `string[N]` for N in 1..255 IS tyShortString with capacity N, so
"anonymous temps default to 255" would break truncation to N. Each caller has
to state its own capacity.

Method: a scratch build routed all 46 such call sites through a tagged wrapper
that logged (site, kind, inherited capacity) whenever the kind was frozen. It
then compiled every Pascal test in test/ plus the fpc testsuite (2405 files)
and every .npy test (1161 files). The instrumentation was reverted afterwards
and never committed.

| site | reached with a frozen kind | capacity source | status |
|---|---|---|---|
| ir.inc IRAppendCall hidden dest | yes (caps 8,10,40,80,90,255) | ProcRetStrCap (this fix) | fixed here |
| ir.inc IRBuildHiddenDest | not in corpus | ProcRetStrCap (this fix) | fixed here |
| ir.inc by-value param temp (managed->frozen arm) | yes (4,8,10,20,255) | ProcParamStrCap, pinned | correct |
| ir.inc by-value param temp (frozen arm) | yes (4,12,255) | ProcParamStrCap, pinned | correct |
| 42 other sites (ir.inc spill/argTk/case/for/inline/vrBox/dcElem, pasparser_expr cast temps, pasparser_stmt, pasparser_lval, pyparser, zparser, cparser) | never, in 3566 files | inherited | unreached |

A canary probe also covered by-value and const string[N] params fed from an
expression, an inline function's result and param, and a ShortString result
passed straight on, with a String[5] declared last. All matched fpc with zero
damage.

Conclusion: no second site shows the defect. The 42 unreached sites inherit a
capacity only for a kind they have not been seen to allocate. If one ever
does, the fix is the one used here: pin LastTypeStrCap from the value's own
capacity around the AllocVar and restore it afterwards. No ticket was filed,
by frankuser's rule (no damage anywhere means no ticket).
