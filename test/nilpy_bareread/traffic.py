# Two uses of ONE name, on a receiver whose class is not known statically.
# `env` is unannotated in both, so both are open-world.
class Craft:
    def gusty(self, env):
        return env.gust(4.0)      # CALL site -- warns, dispatches at run time, WORKS

class Reader:
    def bare_gust(self, env):
        g = env.gust              # READ site -- the same name, taken as a VALUE.
        return g                  # Silent. No diagnostic of any kind.
