# pdfgen — vendored

Upstream: https://github.com/AndreRenaud/PDFGen
Commit: 6817e6e4c4b19e04fd9e1a663ef1ee2de42ca97d
License: Unlicense (public domain) — see LICENSE, redistribution is unrestricted.

Single-file C PDF writer. pxx compiles it with its own C frontend and links it
statically, so a program using it has no runtime dependency on anything.

**This is the first third-party source committed to this repository**, and that
is a deliberate reversal: the tree previously carried none (both `external/` and
`library_candidates/` are gitignored). The reasoning is that a dependency we
ship is a dependency we must be able to support and patch — a fetch step cannot
promise that. Public domain makes it legally free of conditions.

Unmodified. Patch only with a note here saying what and why.

Consumed by `lib/pcl/mimic_reportlab_pdfgen.pas` and its sibling shims, which
present reportlab's canvas API over it.
