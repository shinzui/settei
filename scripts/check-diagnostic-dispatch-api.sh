#!/usr/bin/env bash
set -euo pipefail

# Run from the repository root inside the Nix development shell.
cabal build lib:settei-optparse-applicative
probe_dir=$(mktemp -d)
trap 'rm -rf "$probe_dir"' EXIT
fixtures=settei-optparse-applicative/test
compile() {
  cabal exec -- ghc -fno-code -fforce-recomp -outputdir "$probe_dir" \
    -package settei -package settei-optparse-applicative "$1"
}
compile "$fixtures/compile-pass/CheckedDispatch.hs" >"$probe_dir/positive.log" 2>&1 || {
  cat "$probe_dir/positive.log"
  exit 1
}
for fixture in OldResolutionDispatch OldValidatedDispatch; do
  if compile "$fixtures/compile-fail/$fixture.hs" >"$probe_dir/$fixture.log" 2>&1; then
    echo "ERROR: unchecked $fixture unexpectedly compiled" >&2
    exit 1
  fi
  if ! grep -q 'RuntimeDiagnosticMode' "$probe_dir/$fixture.log" ||
     ! grep -q 'DiagnosticMode' "$probe_dir/$fixture.log" ||
     ! grep -q "Couldn't match expected type" "$probe_dir/$fixture.log"; then
    cat "$probe_dir/$fixture.log"
    exit 1
  fi
done
echo 'Checked dispatch API: positive consumer compiles; both unchecked calls rejected by token type.'
