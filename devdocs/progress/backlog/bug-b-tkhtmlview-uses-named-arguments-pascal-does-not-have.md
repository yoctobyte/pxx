---
track: B
prio: 60
type: bug
summary: "lib/pcl/tkhtmlview.pas has never compiled: line 171 uses Python-style NAMED ARGUMENTS (`configure(yscrollcommand := bar.set_)`), which this dialect does not have, and calls `bar.set_` where tkinter declares plain `set`. Any NilPy app importing tkhtmlview fails to build — songformatter does"
---

# `lib/pcl/tkhtmlview.pas` does not compile — named arguments, and `set_`

- **Type:** bug (library — **Track B**, `lib/pcl` file ownership)
- **Opened:** 2026-08-10 by Track A+C+P+N, found while resolving
  [[bug-nilpy-songformatter-no-longer-compiles-set-callback-and-get-arity]].
  Filed rather than fixed: `lib/pcl` is Track B's, and a Track B agent is
  active (`feature-real-dynlib-loader`).

## Measured

```
$ printf 'program p;\nuses tkhtmlview;\nbegin end.\n' > /tmp/th.pas
$ compiler/pascal26 /tmp/th.pas /tmp/th
pascal26:171: error: undefined variable (yscrollcommand)
  near:  text_  configure  yscrollcommand >>>  bar
```

**Identical on `stable_linux_amd64/default/pinned`** — controlled, so this is
not a regression from any recent compiler change. The unit appears never to
have compiled.

`lib/pcl/tkhtmlview.pas:171-172`:

```pascal
  text_.configure(yscrollcommand := bar.set_);
  bar.config(command := text_.yview);
```

## Two independent defects on those two lines

1. **Named arguments are not a feature of this dialect.** `name := value`
   inside a call's parentheses is Python/Ada syntax; Pascal reads
   `yscrollcommand` as an expression, finds no such variable, and says so.
   These two lines are the **only** place in all of `lib/pcl` that writes it —
   `grep -n "configure(.* := " lib/pcl/*.pas` returns exactly them — so this is
   a one-file mistake, not a convention the compiler dropped.

2. **`bar.set_` does not exist.** `lib/pcl/tkinter.pas` declares
   `procedure set(const first, last: AnsiString);` on the scrollbar (line 431),
   and `StringVar`/`BooleanVar` likewise declare plain `set`. The only `set_`
   spellings in tkinter.pas are `set_scrollregion` and `set_text`, which are
   whole names rather than the reserved-word convention. The trailing-underscore
   convention exists (`destroy_`), but tkinter did not apply it to `set`.

Both must be fixed; correcting only the syntax leaves an unresolved member.

## Blast radius

Any NilPy program importing `tkhtmlview` cannot build. `~/songformatter`'s
`SongFormatter.py` does (`from tkhtmlview import HTMLScrolledText`), and after
the Track N half of that ticket was fixed this is the ONLY thing still stopping
it. It is also why `tkhtmlview` was the single lib unit failing a full
`lib/**` compile sweep on 2026-08-10, on both new and pinned binaries.

## Suggested fix

Positional calls against the real signatures, e.g.

```pascal
  text_.configure_yscrollcommand(bar.set);   { or whatever configure() takes }
  bar.config_command(text_.yview);
```

— but check `Text.configure` / `Scrollbar.config`'s actual declarations first;
the intent is "wire the scrollbar to the text widget both ways", and the
facade may already expose a dedicated call for it.

**Then verify the unit actually compiles**, which no test currently does. That
is the deeper miss: a `lib/pcl` unit could sit permanently broken because
nothing compiles it. Worth a smoke test that `uses` every `lib/pcl` unit — it
would have caught this the day it landed.

## Gate

`printf 'program p;\nuses tkhtmlview;\nbegin end.\n'` compiling; `make
lib-test` / `make demos` green; ideally the all-units smoke test above. Then
`pascal26 SongFormatter.py` should build (Track N's half is already in).

## 2026-08-10 — SUPERSEDED: do not fix this file, it is being replaced

The repo owner chose to **rewrite the unit in NilPy** rather than repair the
Pascal or teach Pascal named parameters:
[[feature-b-tkhtmlview-in-nilpy]] (blocked on
[[feature-nilpy-import-a-py-module-from-the-library-path]]).

The alternative — named parameters in the Pascal dialect — is parked at
[[idea-p-named-parameters-in-the-pascal-dialect]] with the reasoning recorded.
The decisive argument was that named parameters are not standard Pascal, so no
existing Pascal code could ever use them; the only consumers would be
pxx-authored wrappers of Python-shaped APIs, which can simply be Python.

**Explicitly NOT unblocking songformatter with a two-line positional fix**, on
the owner's call: songformatter is a test case, there is no need to unblock it
today, and the file is valuable exactly as the thing that surfaced this
question. Left broken deliberately.

This ticket stays as the measurement record (what is wrong with the file, and
that it fails identically on `pinned`). The work is on the feature ticket.
