class Environment:
    def gust(self, x):
        return x * 3.0


class Craft:
    def gusty(self, env):
        # A CALL site. This is what concretises gust's signature (RetKind
        # becomes Double); without it gust is already all-variant and the bug
        # cannot appear. The earlier probes passed for exactly this reason.
        return env.gust(4.0)
