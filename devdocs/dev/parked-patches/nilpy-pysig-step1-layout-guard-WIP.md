# nilpy-pysig-step1-layout-guard-WIP

Found at the 2026-09-25 wrap-up as a stash in the frankH checkout, dated
2026-09-13 22:05, on base e37edcd7a1. Its message was
"PYSIG step 1 + layout guard (WIP)". It was exported here unchanged so that
nothing stays local-only.

What it contains:

- A PYSIG record layout: PYSIG_SIZE = 64 and PYSIG_OFF_* constants in
  compiler/defs.inc, with its mirror TPySigRec in pylib.pas and the emitter
  side in rtti_emit.inc.
- tools/pysig_layout.py, which derives all three copies of the layout from
  their sources and refuses a disagreement.

It no longer applies: compiler/rtti_emit.inc has moved since. At the wrap-up,
master already had 14 PYSIG_ lines in defs.inc, so this was most likely
landed in some form after the stash was taken. It is not
measured, and it is WIP by its own message. Check whether PYSIG exists on
master before reviving it (`grep -n PYSIG_ compiler/defs.inc`).
