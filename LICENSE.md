# Licensing

frankonpiler (PXX / pascal26) is licensed per directory. Every source file
carries a one-line `SPDX-License-Identifier` header; this table is the map.

| Path | License | Text |
| --- | --- | --- |
| `compiler/**` (except `compiler/builtin/`) | MPL 2.0 | [LICENSE](LICENSE) |
| `tools/**` | MPL 2.0 | [LICENSE](LICENSE) |
| `compiler/builtin/**`, `lib/rtl/**`, `lib/pcl/**`, `lib/crtl/**`, `lib/asmcore/**` | zlib | [licenses/Zlib.txt](licenses/Zlib.txt) |
| `examples/**` | 0BSD | [licenses/0BSD.txt](licenses/0BSD.txt) |
| `docs/**` | CC BY 4.0 | <https://creativecommons.org/licenses/by/4.0/> |
| everything else (tests, devdocs, build files) | MPL 2.0 | [LICENSE](LICENSE) |

Why the split: the runtime and libraries under zlib are **embedded into every
binary the compiler produces** — programs you compile with pascal26 are
entirely yours, with no license obligations from the toolchain. The compiler
itself is MPL 2.0: use it anywhere, link it with anything, but published
modifications to its files stay open.

## Compiled output

Binaries produced by the compiler belong to their author. The runtime code
embedded in them is zlib-licensed, which imposes no requirements on binary
distribution.

## Contributions

External contributions require a Developer Certificate of Origin sign-off
(`git commit -s`) and include a contributor license grant that permits the
project to relicense contributed code if the project license ever needs to
change; see [CONTRIBUTING.md](CONTRIBUTING.md).

## Third-party code

The repository contains no third-party code. Optional external material
(the Lua test corpus, library candidate sources fetched by
`tools/install_lib_candidates.sh`) is downloaded locally on demand, lives in
git-ignored directories, and keeps its own upstream licenses.

## No warranty

The software is provided "as is", without warranty of any kind. It is under
active development; see each license text for the full disclaimer.
