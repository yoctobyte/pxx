---
track: N
prio: 80
type: bug
blocked-by: []
summary: "`hasattr(x, name)` returns False for EVERYTHING when x is a parameter with no static type — `hasattr(a_dict, 'keys')` and `hasattr(a_list, 'append')` are both False. Silently wrong, never an error, and it is how CPython code dispatches on duck type."
---

# `hasattr` through an untyped parameter is always False

Filed 2026-08-19 from [[feature-b-mimic-collections-abc-mapping-and-mutablemapping]],
where it made `MutableMapping.update({'x': 1})` take the pairs branch and index a
one-character string.

Measured on **pinned v356** (`2bb09afb0cff`):

```python
def probe(x):
    return hasattr(x, 'keys')
class C:
    def take(self, other):
        return hasattr(other, 'keys')
print(probe({'a': 1}), probe([1]), probe('s'))
print(C().take({'a': 1}), C().take([1]))
```

| | |
| --- | --- |
| CPython | `True False False` / `True False` |
| pxx (pinned v356) | `False False False` / `False False` |

Not dict-specific and not container-specific: through a dynamic receiver `hasattr`
answers False **uniformly**, including `hasattr(a_list, 'append')`. Written
against a local whose static type is known it answers correctly, so the resolution
is happening at compile time against the declared type and there is no runtime
fallback for the unknown case.

The failure mode is the expensive kind — no error, a plausible wrong value, and a
crash somewhere else entirely. `hasattr`-based duck-typing is how a large fraction
of real Python dispatches, so this will keep resurfacing under different symptoms.

Track B workaround: `lib/rtl/mimic_collections_abc.py`'s `update()` discriminates
with `isinstance(other, dict) or isinstance(other, Mapping)` instead of
`hasattr(other, 'keys')`. Registered in `devdocs/dev/track-b-workarounds.md`;
that workaround is narrower than CPython (a non-Mapping object exposing `keys()`
takes the wrong branch) and should be reverted when this closes.
