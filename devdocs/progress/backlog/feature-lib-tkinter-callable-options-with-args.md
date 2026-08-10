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

## Moved to blocked/ 2026-07-31 — the missing piece is runtime, not façade

Re-read against the code rather than the ticket text. Of the three things listed
under "what is missing", the first two are façade work Track B owns — a registry
flag and a dispatcher branch. The third is not:

> call bridges for 2 and 3 arguments — `pycallback_call2/3` for a bound method,
> and a bound-fn / closure that accepts more than one own parameter (today
> `pyboundfn_call_ptr` passes exactly one).

`pycallback_call0/1` live in `compiler/builtin/pylib.pas:581` and
`pyboundfn_call_ptr` in `pyeval.pas:1870` — shared NilPy runtime, which Track B
does not edit. Without them the façade half has nothing to call, so building
the registry and the dispatcher branch first would land dead code.

Split and filed as [[feature-nilpy-multi-arg-callback-bridges]] (Track N).
**Tagged for later:** when that lands, the remaining work here is small and
entirely in `lib/pcl/tkinter.pas`.

Nothing regresses in the meantime. The case that motivated this ticket — the
scrollbar pair — turned out not to need it at all: CPython's tkinter does not
call back into Python for `yscrollcommand` either, it wires Tcl straight to the
other widget's subcommand, and `TkiOptScrollCmd` now does the same and refuses
loudly for anything that is not a widget method. Nothing enters the regression
suite from here until the bridges exist.

## 2026-08-03 — dependency recorded in frontmatter

The 2026-07-31 note above identified the blocker in prose (the shared-runtime
`pycallback_call2/3` / multi-arg `pyboundfn_call_ptr` bridges) but no
`blocked-by:` edge existed, so the board could not see it: this ticket ranked as
ready and would have been handed to a Track B agent who cannot edit
`compiler/builtin/pylib.pas`. The bridges have their own ticket —
[[feature-nilpy-multi-arg-callback-bridges]] — and it is now the recorded edge,
so priority propagates to it and this surfaces only once it lands.

## Unblocked 2026-08-09 (Track B): the blocker is satisfied in practice

Swept as part of checking whether Track B's blocked tickets were still really
blocked — the pattern this session kept hitting is that they were not. The
capability this ticket waited on was MEASURED working on the current pin (v252);
the evidence is recorded on the blocker itself, which Track N still owns
formally closing.

`blocked-by` removed here so the ticket stops hiding from `progress.sh ready`.

## 2026-08-10 — actually MOVED out of blocked/

The 2026-08-09 note above removed `blocked-by` and said the ticket should stop
hiding from `progress.sh ready` — but the FILE was never moved out of
`blocked/`, so it went on hiding anyway. `ready` reads the directory, not the
frontmatter. Moved to `backlog/` now; the unblocking claim above is unchanged
and is the one that matters.
