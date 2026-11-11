---
slug: bug-n-an-extended-slice-store-from-a-variant-source-is-refused
title: An extended-slice store from a variant source is refused, and lekkerzeilen stopped building
track: N
type: bug
status: done
prio: 60
found-by: claude (pxx session), 2026-11-11, building lekkerzeilen against latest-de04e4e978
summary: >
  `pixels[channel::step] = grid.values.tobytes()[lo::2].translate(...)` with
  `pixels` a bytearray and the source typed VARIANT was refused at compile
  time ("the source of an extended-slice assignment must have a static list or
  bytes type"). lekkerzeilen's app.py has exactly that line, so the app did
  not build on latest -- and apps build with latest, so that is a pxx bug.
---

## Why

PyRewriteSliceAssign sends a statically typed target to the typed
pylist/pybytes_setslice_step, which take a TPyList/TPyBytes source; a raw
variant there would be read as an object header, so the variant case was
refused. But pyvar_setslice_step already unboxes both sides and dispatches on
the runtime types (it serves untyped targets).

## Fix

A variant source with a typed target boxes the target (PyForceVariant) and
goes to pyvar_setslice_step. Wrong-typed sources still raise at run time.

lekkerzeilen now compiles (wt2 side compiler, 2026-11-11) and its
`--conform` pixel checksums match CPython on all 6 cases (the `file` column
is zlib-dependent by the tool's own note). Test:
test_nilpy_an_extended_slice_store_from_a_variant_source.py (row xslicev26),
expected = python3.

Not fixed: a list target given a bytes source of the wrong length raises
TypeError where CPython raises ValueError (pyvar_setslice_step's list arm
takes only a list source).
