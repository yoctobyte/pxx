# An f-string inside an f-string hole, and a computed precision in the spec.
# The inner one was copied through as the identifier `f` beside a plain
# string ("undefined variable (f)"). Expected = python3.
# feature-nilpy-fstring-nested-spec-and-nested-fstring
w = 6
name = "pxx"
print(f"[{f'{w}x':>{w}}]", f"{3.14159:.{w-3}f}", f"{'a' + f'{w*2}'}")
print(f"<{f'{name!r}'}>", f"{f'{w}' * 2}", f"{len(f'{name}{w}')}")
