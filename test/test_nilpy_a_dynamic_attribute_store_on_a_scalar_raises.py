# bug-n-a-dynamic-attribute-store-on-a-scalar-variant-segfaults
xs = [1, "a", 2.5, True, None]
for v in xs:
    try:
        v.foo = 1
        print("stored")
    except AttributeError as e:
        print("AE", e)
try:
    xs[0].foo = 1
except AttributeError as e:
    print("AE", e)
