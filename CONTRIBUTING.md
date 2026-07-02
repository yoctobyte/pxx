# Contributing

The repository is open for study and discussion. Issues and discussions are
welcome. Pull requests are accepted selectively — the compiler has a strict
self-host gate, and changes to `compiler/**` need maintainer-run validation.

Every pull request must satisfy two conditions. Submitting one means you
agree to both.

## 1. Developer Certificate of Origin (DCO)

Every commit must carry a `Signed-off-by:` line (`git commit -s`), certifying
the [Developer Certificate of Origin](https://developercertificate.org/):
you wrote the change or otherwise have the right to submit it.

## 2. Contributor license grant (relicensing consent)

You keep the copyright on your contribution. By submitting it, you grant the
project maintainer a perpetual, worldwide, non-exclusive, irrevocable,
royalty-free license to use, reproduce, modify, distribute, sublicense, and
**relicense** your contribution as part of this project.

Why: the project is currently MPL 2.0 (see [LICENSE.md](LICENSE.md)) and
intends to stay that way — but if MPL 2.0 ever creates practical problems,
or a clearly better open-source license emerges, the project must be able to
switch without tracking down every past contributor. This grant is what
keeps that possible. It is a license grant, not a copyright transfer.

If you cannot or do not want to agree to this grant, please open an issue
describing the change instead of a pull request.

## Practical rules

- Match the file's license: each file declares it in an SPDX header (see
  [LICENSE.md](LICENSE.md)); new files take their directory's license.
- No code copied from other projects unless its license permits it and the
  commit message says exactly where it came from and under what license.
- Run the relevant gate before submitting (`make test` for compiler changes,
  `make lib-test` for library changes); compiler changes are additionally
  validated by a maintainer against the self-host byte-identical gate.
