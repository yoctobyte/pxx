# Pinned v36 binary is missing from git — `pinned` symlink dangles

- **Type:** bug (infra) — **Track A**
- **Status:** urgent — breaks `make lib-test`/`demos` for anyone on origin
- **Opened:** 2026-06-22
- **Owner:** — (Track A / "sis")
- **Found by:** Track B, after rebasing onto the v36 pin.

## Summary

Commit `564f7d0` ("chore(stable): pin v36 — dyn-array record field assignment
fix") updated `stable_linux_amd64/default/VERSION` to `36` and pointed
`stable_linux_amd64/default/pinned -> v36`, but **the `v36` binary blob was not
committed**. `git ls-files stable_linux_amd64/default/` shows binaries only up to
`v35`. So `$(PXX_STABLE)` (= `…/default/pinned`) resolves to a non-existent file:

```
$ stable_linux_amd64/default/pinned …
bash: stable_linux_amd64/default/pinned: No such file or directory
```

`make lib-test` and `make demos` fail immediately for everyone who pulls.

## Fix

Commit + push the `v36` binary (and verify `pinned`/`latest` symlinks resolve),
or revert `pinned`/`VERSION` back to `v35` until the binary is pushed. v35 is
present and good.

## Workaround (Track B, meanwhile)

Build/test against the present v35 binary explicitly:
`make lib-test PXX_STABLE=$(pwd)/stable_linux_amd64/default/v35` — green there
(all libs incl. vm + mathf).

## Log
- 2026-06-22 — Filed by Track B. v35 binary present + green; v36 binary absent.
