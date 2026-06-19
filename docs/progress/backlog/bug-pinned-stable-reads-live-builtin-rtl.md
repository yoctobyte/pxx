# Pinned stable reads LIVE builtin RTL source — track A WIP breaks track B

- **Type:** bug (infra / build isolation)
- **Status:** backlog
- **Owner:** — (track A / shared infra)
- **Opened:** 2026-06-19 (track B, hard-blocked mid-session)

## Symptom

Every track-B compile against the pinned stable (v9) died with:

```
pascal26:497: error: unexpected character ()
```

...including a 2-line `hello world` with no `uses`. The v9 binary is intact
(sha256 matches `last.sha256`). The cause was an **uncommitted, mid-edit
`compiler/builtin/builtinheap.pas`** in track A's lane (interface-refcounting
work) — temporarily not syntactically valid.

## Root cause — the isolation hole

The pinned binary is **not self-contained**. At runtime it does an implicit
`uses builtinheap` and reads `compiler/builtin/builtinheap.pas` **from the live
working tree**. Proof:

```
$ (cd /tmp && /path/to/pinned hello.pas out)
pascal26:2: error: uses: unit source not found: builtinheap ()
```

So the builtin RTL *source* is shared ground even though the *binary* is pinned.
`docs/dev/parallel-tracks.md` claims "a half-built compiler in the tree does not
block B because B uses `$(PXX_STABLE)`" — that is **false for runtime-read RTL**
like `builtinheap.pas` (and any other source the stable resolves live).

## Fix — freeze the runtime-read sources with the binary

On `make pin`, snapshot the builtin RTL sources next to the pinned binary and
make the pinned binary resolve them from there, not the live tree:

- copy `compiler/builtin/*.pas` (and any other source the binary reads at
  runtime) into e.g. `stable_linux_amd64/default/builtin_vN/`
- point the pinned binary's builtin search at that frozen dir (env var / flag /
  baked search path), so track A's WIP in `compiler/builtin/**` can no longer
  reach track B
- audit: `make pxx-stable-check` reports the frozen builtin dir alongside the
  pinned binary version

Then B's ground is genuinely frozen until a deliberate `make pin`.

## Interim protocol (until the fix lands)

Grey-area shared files (the builtin RTL) are a **halt-and-wait** zone: if
`compiler/builtin/**` shows uncommitted edits, the other agent **stops and
waits** rather than working around or stomping. Safer to halt than to make a
mess. (Kept deliberately simple — no heavier protocol.)

## Log
- 2026-06-19 — opened by track B after being hard-blocked. Diagnosed the
  runtime-read dependency; B is holding until `compiler/builtin/builtinheap.pas`
  is valid again. Recommend the snapshot fix so this cannot recur.
