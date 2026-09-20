"""Dead: the innermost guard RESOLVES, so its handler never runs.

Lexically BEFORE deep_hit, which is what makes it the dangerous one -- if the
pre-scan resolves this arm, its alias registers first and wins."""

WHO = "deep-miss"
SYM_DEEP_MISS = "sym-deep-miss"
