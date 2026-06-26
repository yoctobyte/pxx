# Library Test Suite

The library suite is Track B's test surface. It runs against the pinned stable
compiler, not the in-progress compiler seed, and it is separate from the
compiler regression suite.

Use:

```sh
make library-suite-green
make library-suite-discovery
make library-suite
```

`library-suite-green` is the hard-fail curated library regression set. Keep it
green. It covers library behavior and examples that function as library oracles:
SysUtils, Random, Math, Collections smoke, PAL, Sudoku, and Bignum.

`library-suite-discovery` is non-gating. It compiles larger demos or candidate
library workloads and reports `GAP` lines with a Track A/B hint. A discovery gap
should become a `devdocs/progress/backlog/` ticket instead of being silently worked
around in the suite.

`make lib-test` remains the compact historical smoke gate. New library coverage
should go into `tools/library_suite.sh`; `lib-test` can stay short or eventually
delegate to `library-suite-green`.

## Ticket Discipline

Library-suite work should have a `devdocs/progress/` ticket like any other feature.
If a suite change is small enough to happen inline, add the ticket in the same
commit. When a discovery case reports a new `GAP`, either map it to an existing
ticket in that ticket's log or create a new backlog ticket before moving on.

## Track Hints

File Track A tickets when a library test needs compiler, language, codegen,
frontend, ABI, parser, or stable-binary behavior.

File Track B tickets when a library test needs RTL units, PAL backends, CRTL
headers/implementations, examples, or demo/library API work.

Compiler `make test` must not grow by absorbing these library cases unless the
same source is also a compiler regression. Some overlap is fine, but ownership
should stay explicit.
