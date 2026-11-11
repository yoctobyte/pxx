# hasattr(x, name) with a COMPUTED name sees a builtin type's methods.
# bug-n-hasattr-with-a-computed-name-cannot-see-a-builtin-method
class K:
    def __init__(self):
        self.f = 1
    def m(self):
        return 2

def comp(x, n):
    return hasattr(x, n)

def lit(x):
    return hasattr(x, 'keys')

d = {'a': 1}
print(lit(d), comp(d, 'keys'), comp(d, 'items'), comp(d, 'append'))
print(lit('s'), comp('s', 'upper'), comp('s', 'split'), comp('s', 'keys'))
print(comp(5, 'bit_length'), comp(5, 'hex'), comp(2.5, 'hex'), comp(2.5, 'bit_length'))
print(comp([1], 'append'), comp((1,), 'append'), comp({1}, 'add'), comp([1], 'add'))
print(comp(K(), 'f'), comp(K(), 'm'), comp(K(), 'g'))
names = ['keys', 'nope', 'get']
print([n for n in names if hasattr(d, n)])
