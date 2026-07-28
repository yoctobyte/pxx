---
track: B
prio: 40
type: feature
---

# tkinter façade: a callable option that receives Tk's OWN arguments

`bind` and `-command` hand a Python callable either nothing or one Event, and
the dispatcher (`pxxcb`) covers both. Tk also calls options with its own
argument lists, and those have no path through the façade yet:

| option | Tk calls it with |
| --- | --- |
| `-yscrollcommand` / `-xscrollcommand` | `first last` (two fractions) |
| a scrollbar's `-command` | `moveto <frac>` or `scroll <n> units\|pages` |
| `-validatecommand`, `-postcommand`, `trace` handlers | their own argument sets |

For the scroll pair this does not matter today: CPython's tkinter does not call
back into Python for them either — it wires Tcl straight to the other widget's
subcommand, and `TkiOptScrollCmd` now does the same (receiver → widget path,
option name → subcommand). Anything that is NOT a widget method is refused
loudly there rather than wired to something wrong.

What is missing is the general shape:

1. a registry entry that records "this callback takes Tcl's raw arguments";
2. a dispatcher branch that packs `argv[2..]` into Python values instead of
   building an Event;
3. call bridges for 2 and 3 arguments — `pycallback_call2/3` for a bound method,
   and a bound-fn / closure that accepts more than one own parameter (today
   `pyboundfn_call_ptr` passes exactly one).

Until it lands, a plain def or lambda as a scroll command fails with a message
naming the limit.

## Why it was filed

songformatter's settings.py writes both canonical spellings
(`Scrollbar(..., command=self.canvas.yview)` and
`canvas.configure(yscrollcommand=self.scrollbar.set)`). Passing a bound method
into the façade's former `AnsiString` option compiled silently and handed Tcl a
garbage script; the event loop then hung inside `update`. See
[[bug-nilpy-bound-method-coerced-to-string]].
