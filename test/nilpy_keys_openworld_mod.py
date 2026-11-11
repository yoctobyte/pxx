# Helper for test_nilpy_keys_through_an_untyped_receiver_across_a_module.npy:
# an imported module calls methods on an UNTYPED receiver whose class it never
# sees. Mapping's self-iterating keys() is the candidate that used to be bound
# statically. bug-n-keys-through-an-untyped-receiver-is-not-dispatched-cross-module
class Mapping:
    def __iter__(self):
        raise NotImplementedError('abstract')
    def __getitem__(self, key):
        raise KeyError(key)
    def keys(self):
        out = []
        for k in self:
            out.append(k)
        return out

class Caller:
    def take_keys(self, other):
        out = []
        for k in other.keys():
            out.append(k)
        return out
    def take_items(self, other):
        return list(other.items())
    def take_values(self, other):
        return [v for v in other.values()]
    def take_get(self, other, k):
        return other.get(k)
