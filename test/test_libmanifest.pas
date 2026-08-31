program test_libmanifest;
{ Per-directory library manifests (pxxlib.cfg): a build profile scoped to one
  library's own tree. feature-dynamic-include-paths-config.

  Compiled with -dPROGDEF. Three populations, and the two NEGATIVE ones are the
  test:

    the library under test/libmanifest/  sees the manifest, and its `undef
                                         PROGDEF` has taken away a define the
                                         COMMAND LINE gave the build
    a sibling library next door          sees neither — no manifest of its own,
                                         and the neighbour's does not reach it
    the program itself                   still has PROGDEF and has never heard
                                         of MANIFEST_ON

  A manifest that leaked would pass a test that only checked the first line.
  The mechanism this exists for is a SAFETY one: PasApplyMimicDefines carries
  "NEVER call during a self-build", a landmine enforced by remembering, and a
  scope a manifest cannot escape makes it structural instead.

  The manifest also carries an unknown directive on purpose, so the accept-side
  behaviour is asserted too: it warns and the compile continues, because a
  manifest is read by a binary its author did not build. }
uses libmanifest_unit, libmanifest_sibling;
begin
  WriteLn('lib: ', LibSees);
  WriteLn('sib: ', SiblingSees);
  Write('prog: ');
{$ifdef MANIFEST_ON}
  Write('manifest ');
{$else}
  Write('NO-manifest ');
{$endif}
{$ifdef PROGDEF}
  WriteLn('progdef');
{$else}
  WriteLn('NO-progdef');
{$endif}
end.
