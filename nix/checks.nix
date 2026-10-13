# What `nix flake check` verifies beyond the packages building.
#
# These run in the sandbox whenever `nix flake check` is invoked.
{ pkgs, self }:
{
  # House style over the whole tree, code comments included: no em dashes,
  # none of the vocabulary that marks machine written prose.
  #
  # The source is copied in rather than read from the store directly, so the
  # script sees a checkout with itself at tools/ and derives the same root it
  # would locally. check-prose.py fails when it finds nothing to read, which
  # is what catches a skip rule that has swallowed the tree.
  prose = pkgs.runCommand "omnibin-prose" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    cp -r ${self} ./source
    chmod -R u+w ./source
    cd ./source
    python3 tools/check-prose.py
    touch $out
  '';
}
