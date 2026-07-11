program zengl_probe1;
{ First Pascal-ladder probe for New-ZenGL (feature-game-library-candidate-suite
  slice C): compile the leaf math unit and exercise a few pure functions.

  Fetch the candidate first: tools/install_lib_candidates.sh zengl
  Compile: pxx -Fulibrary_candidates/zengl/Zengl_SRC/src \
               -Fulibrary_candidates/zengl/Zengl_SRC/srcGL \
               -Fulibrary_candidates/zengl/Zengl_SRC/headers \
               test/gamelib/zengl_probe1.pas

  CURRENTLY BLOCKED (2026-07-11) by, in order of encounter:
  - bug-pascal-high-low-in-const-expr (zgl_types.pas:105 array bounds;
    local-patchable in the gitignored candidate tree)
  - bug-pascal-directive-inside-paren-star-comment (zgl_gltypeconst.pas
    commented-out C-junk block is evaluated)
  - bug-pascal-include-search-silent-miss ({$I zgl_config.cfg} from headers/
    silently dropped for every unit under src/) }
uses zgl_math_2d;
var
  s, c: Single;
begin
  m_SinCos(90.0, s, c);
  writeln('sincos=', (s > 0.99) and (s < 1.01) and (c > -0.01) and (c < 0.01));
  writeln('minmax=', (min(1.0, 2.0) = 1.0) and (max(1.0, 2.0) = 2.0));
end.
