---
slug: bug-c-command-line-undef-is-applied-after-every-define
track: C
prio: 40
type: bug
status: done
created: 2026-11-22
closed: 2026-11-22
found-by: claude-pxx (micropython v1.24.1, py/nlrx64.c built with -U__GNUC__ -D__GNUC__=8)
summary: "pxx collected -D and -U into separate lists and applied every -U after every -D, so `-U__GNUC__ -D__GNUC__=8` left __GNUC__ undefined (gcc: 8), and `-UFOO -DFOO=3` left FOO undefined. Now one list, in command-line order, as gcc does (row c_undord26)."
---

# A command-line -U was applied after every -D

gcc processes `-D` and `-U` in the order given. pxx kept them in two lists
(CCmdDefRaw, CCmdUndefRaw), and CPApplyCmdlineDefines ran all defines and
then all undefs, so redefining a predefined macro the usual way
(`-U__GNUC__ -D__GNUC__=8`) removed it.

Fix: compiler.pas appends `-U` to the same list, marked with a leading #1.
CPApplyCmdlineDefines applies the list in order. CCmdUndefRaw and
CCmdUndefCount are gone.

Test: test/c_cmdline_undef_order.c, built with
`-U__GNUC__ -D__GNUC__=8 -DFOO=3 -UFOO -UBAR -DBAR=4` and checked against gcc.
