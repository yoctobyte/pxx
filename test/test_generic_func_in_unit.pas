{ A `generic function` in a UNIT: declared in the interface, defined in the
  implementation, and specialized inline from three different places. Every row
  here failed to compile before bug-p-a-generic-function-cannot-be-declared-in-
  a-unit; the identical code at program level always worked, which is what kept
  the gap invisible -- the top-level declaration dispatcher exists three times
  (program declarations, unit interface, unit implementation) and only the first
  copy had a `generic` arm.

  The rows, and what each one is for:

    ConsumerUse      21+21    a UNIT inline-specializing ANOTHER unit's routine
    ConsumerUseTry   10+10+1  the same, with a `try` body (the function-side
                              body-extent counter; see
                              test_generic_body_end_counting for its control)
    inline from here 4+4      the PROGRAM inline-specializing a unit's routine
    declaration form 5+5      `specialize F<C> as Name;` -- pxx-only spelling,
                              FPC rejects it, kept so the two paths stay wired
                              to one specialization each
    ProviderTag      7        an ordinary routine declared AFTER the generic
                              ones: a truncated template body only becomes
                              damage when something follows it

  Oracle: FPC 3.2.2 prints `42 21 8 7` for the four rows it will compile (it
  refuses the `as` spelling, which is ours). }
program test_generic_func_in_unit;
{$mode objfpc}

uses ugfcons, ugfprov;

specialize Twice<ShortInt> as TwiceShort;

begin
  writeln(ConsumerUse, ' ', ConsumerUseTry, ' ',
          specialize Twice<Integer>(4), ' ',
          TwiceShort(5), ' ', ProviderTag);
end.
