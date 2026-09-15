---
track: N
prio: 75
type: feature
blocked-by: []
summary: "Call-site parameter typing (PyParamTypeFromSites) scans only the def's own file, because modules are lexed one at a time as their import is met; the demo's callers are mostly cross-module (text.measure: one own-file site, four real callers in ui.py/app.py), so int claims are switched OFF and float claims rest on a sample. Lex the whole import closure before parsing, then every site is visible and ints can be claimed again."
status: open
---

# Lex the import closure before parsing, so call-site typing sees every caller

The importer (pasparser_proc.inc, the `isPyUnit` branch around
`PyLexAppend`) lexes a module onto the token stream when its `import` is
reached during the importer's parse, then parses it there. So when module
A's def headers are parsed, the modules that call into A but are imported
LATER are not in the stream yet, and PyParamTypeFromSites bounds its scan to
A's own file anyway (an unbounded scan met Pascal builtin tokens).

Measured 2026-09-16 by the lekkerzeilen seat: 191 of the demo's 357 typed
parameters rested on ONE site, 80 of them int; `measure(line, scale=2)` was
typed int from its single own-file site while `measure(line, 1.25)` from
another module is CPython-valid -- refused at compile time when static,
truncated when variant. Ints are therefore not claimed at all (the int-site
veto in PyParamTypeFromSites), and float claims are correct in both
directions but still drawn from a sample.

**The fix:** a pre-lex phase over the import closure -- resolve and append
every reachable `.py` module before any module body is parsed, register each
(path -> token start) so the importer parses from the recorded start instead
of lexing again -- then scan every `.py` range (PasSrcRangeStart/PasSrcOfTok
give the file per range) and drop the own-file bound. Name collisions across
modules become vetoes, never mis-claims. Then re-enable int claims, with the
fixture's Grid.cols/tick.n rows flipping from veto to tk=13.

Owner: the seat that built the typer (frankuser). Depends on nothing.
