# nilpy-micropython-native-viper

FINISHED, not landed. It was parked 2026-09-27 because its full test-nilpy run
could not get past an unrelated upstream red (test_result_fresh_verdicts
`TA.ViaLocal`, which also fails on cdb8162bfd without this patch).

It has been checked in these ways:

- The fixture matches.
- The refusal rows pass here and fail on the pin.
- The pointer views do not leak (live 5 → 5 from N=1 to N=11).
- The driver census is 16/16 (compiler c9e8dd35480b, scratch tree
  2e170a1d73 + both patches).

To land it: `git apply` the patch, rebuild, and run a full test-nilpy once
that row is green again.
