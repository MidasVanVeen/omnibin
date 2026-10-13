# `omnibin-shell`: the whole thing, in a mount namespace, on any Linux.
#
# This is the version for a machine you care about. The lazy store appears at
# /nix/store inside a namespace only this shell and its children can see, and
# it disappears when the shell exits. The host's own store is served through
# it untouched, so software the machine already has keeps working.
#
# The daemon deliberately runs OUTSIDE the namespace. omnibin is a process
# whose own libraries live in /nix/store; serving /nix/store from inside the
# namespace means a page fault on one of them is answered by a thread blocked
# on that same fault, and the whole namespace hangs. Mounting over a live
# store from within is possible, and the NixOS module does it as root with
# mlockall, but it is not worth needing privileges for here.
#
# So: the daemon serves a neutral mountpoint in the host's namespace, where
# /nix/store is still the real one and nothing can recurse, and the namespace
# binds that mount over /nix/store. The passthrough is then simply the real
# store, with no bind mount needed at all.
{ pkgs, omnibin }:
let
  # The inner half, as its own script. Nesting three levels of shell quoting
  # into an unshare invocation is how you get a script nobody can edit.
  inner = pkgs.writeShellScript "omnibin-shell-inner" ''
    set -eu

    # Everything below is invisible to the host. This is the only mount the
    # namespace makes, and it is what puts thirteen years of nixpkgs at the
    # absolute paths every binary in them expects.
    mount --bind "$OMNIBIN_STORE" /nix/store

    # Last on PATH. First would mean every mistyped command becomes a lookup
    # in a filesystem with tens of thousands of answers, and would shadow the
    # tools the surrounding project pinned.
    PATH="$PATH:$OMNIBIN_TREE/bin"
    export PATH

    exec "$@"
  '';
in
pkgs.writeShellApplication {
  name = "omnibin-shell";
  runtimeInputs = [
    omnibin
    pkgs.util-linux
    pkgs.coreutils
    pkgs.fuse3
    pkgs.nix
  ];
  text = ''
    runtime=''${XDG_RUNTIME_DIR:-/tmp/omnibin-$(id -u)}

    # The tree goes under XDG_RUNTIME_DIR, which this user owns, since /
    # belongs to root and /omnibin cannot be created here. $OMNIBIN_TREE
    # names it. The NixOS module can create a real /omnibin.
    mkdir -p "$runtime"

    # A killed shell can leave indirect roots behind. The lock stays open in
    # the daemon and shell children, so only abandoned sessions are removed.
    for candidate in "$runtime"/omnibin.*; do
      [ -f "$candidate/lock" ] || continue
      exec 8<>"$candidate/lock"
      if flock -n 8; then
        fusermount3 -u "$candidate/tree" 2>/dev/null || true
        fusermount3 -u "$candidate/store" 2>/dev/null || true
        rm -rf "$candidate/gcroots"
        rm -f "$candidate/lock"
        rmdir "$candidate/tree" "$candidate/store" "$candidate" 2>/dev/null || true
      fi
      exec 8>&-
    done

    session_dir=$(mktemp -d "$runtime/omnibin.XXXXXXXX")
    exec 9>"$session_dir/lock"
    flock 9
    OMNIBIN_TREE=''${OMNIBIN_TREE:-$session_dir/tree}
    OMNIBIN_STORE=''${OMNIBIN_STORE:-$session_dir/store}
    OMNIBIN_GC_ROOTS="$session_dir/gcroots"
    OMNIBIN_CACHE=''${OMNIBIN_CACHE:-''${XDG_CACHE_HOME:-$HOME/.cache}/omnibin}
    export OMNIBIN_TREE OMNIBIN_STORE OMNIBIN_CACHE OMNIBIN_GC_ROOTS

    mkdir -p "$OMNIBIN_CACHE"

    mkdir -p "$OMNIBIN_TREE" "$OMNIBIN_STORE" "$OMNIBIN_GC_ROOTS"

    cleanup() {
      kill "$mount_pid" 2>/dev/null || true
      wait "$mount_pid" 2>/dev/null || true
      fusermount3 -u "$OMNIBIN_TREE" 2>/dev/null || true
      fusermount3 -u "$OMNIBIN_STORE" 2>/dev/null || true
      rm -rf "$OMNIBIN_GC_ROOTS"
      rm -f "$session_dir/lock"
      rmdir "$OMNIBIN_TREE" "$OMNIBIN_STORE" "$session_dir" 2>/dev/null || true
    }

    omnibin mount \
      --store "$OMNIBIN_STORE" \
      --passthrough /nix/store \
      --tree "$OMNIBIN_TREE" \
      --gc-roots "$OMNIBIN_GC_ROOTS" \
      --cache-dir "$OMNIBIN_CACHE" &
    mount_pid=$!
    trap cleanup EXIT

    # Wait for the tree to answer before handing over the shell, so the first
    # command typed is not a race with the mount.
    ready=""
    for _ in $(seq 1 100); do
      if [ -e "$OMNIBIN_TREE/README.md" ]; then
        ready=yes
        break
      fi
      sleep 0.1
    done

    if [ -z "$ready" ]; then
      echo "omnibin-shell: the mount never came up" >&2
      exit 1
    fi

    if [ "$#" -eq 0 ]; then
      set -- "''${SHELL:-/bin/sh}"
    fi

    # Keep the caller's uid and gid visible to shells and agents. Capabilities
    # in the new user namespace are needed for the private bind mount.
    unshare --user --map-current-user --keep-caps --mount -- ${inner} "$@"
  '';
}
