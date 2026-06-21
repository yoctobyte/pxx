# About PXX

PXX (pascal26) is an experimental, self-hosting Pascal-dialect compiler — a
single-developer project, early and small. No illusions about its standing: it has
had essentially zero impact on the world so far, and it sits in the long shadow of
the people and projects in [the Pascal lineage](the-pascal-lineage.md). It doesn't
claim a place there; if it ever earns one, that's for others to say.

What it is, plainly:

- **Self-hosting.** Bootstrapped by FPC, then compiles itself to a fixed point,
  byte-identical.
- **From scratch.** Its own RTL, its own PCL widget set, its own backends — nothing
  copied or ported from FPC, Borland, or anyone else. FPC-compatible in dialect and
  naming, independent in implementation.
- **Multi-target.** x86-64, i386, aarch64, arm32, and the ESP32 pair xtensa /
  riscv32.
- **Reproducible.** Every shipped binary rebuilds bit-for-bit from source on your
  own machine — meant to be read and verified, not just trusted.

Why it exists: mostly the joy and the learning, built in the spirit of the tools that
once put a serious compiler in an individual's hands without a serious invoice. It's
for the maker who wants to *understand* their tools, not just rent them.

That's the whole pitch. No more is claimed.
