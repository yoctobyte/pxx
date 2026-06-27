# C chained pointer indexing loses base type

- **Type:** bug (Track C / C pointer metadata)
- **Status:** backlog
- **Owner:** —
- **Found / Opened:** 2026-06-27, while validating C `main(argc, argv)`.

## Symptom

Direct chained indexing through a multi-level pointer can lose the ultimate base
type. This fails even though stepping through an explicit intermediate pointer
works:

```c
int main(int argc, char **argv) {
  if (argv[1][0] != 'a') return 2;
  return 42;
}
```

Observed with `/tmp/cargv_cmp ab xyz`:

```text
exit=2
```

But both probes below work:

```c
int main(int argc, char **argv) { return argv[1][0]; }        // exits 97
int main(int argc, char **argv) { char *p = argv[1]; return p[0]; } // exits 97
```

## Likely Cause

The C frontend currently records only the immediate pointed-at type for symbols.
For `char **argv`, the symbol is represented as pointer-to-pointer, so the first
subscript correctly has pointer stride, but the second subscript no longer knows
that the pointed-at base type is `char`. The expression is then lowered/tagged as
a pointer-width value in comparison contexts instead of a byte-sized `char`.

## Acceptance

- `argv[1][0] == 'a'` works directly for `char **argv`.
- Nested pointer indexing preserves both immediate pointer stride and the
  ultimate scalar/record base type.
- Add a C regression for direct chained indexing through `char **`.

## Workaround

Assign the intermediate pointer first:

```c
char *p = argv[1];
if (p[0] != 'a') return 2;
```
