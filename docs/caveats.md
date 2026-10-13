# Caveats

**Commands can only be named from March 2017.** Store paths reach back to
2012, but a command inside one can only be found by name where the cache
published a file listing beside the narinfo, and Hydra did not always. A 2013
path answers `narinfo=200 ls=404`. Those paths still fetch and still run, and
`/nix/store/<digest>-<name>` resolves for them exactly as it does for anything
newer; they just cannot be searched for by the command they contain. 245,532
of 253,817 package versions are named on `x86_64-linux`.

**A first read needs the cache.** The index and cached listings work offline.
`omnibin-shell` imports packages into the real Nix store; Nix garbage
collection may remove them after the session ends, so a later read can need
the network again. The NixOS module and container still use the private cache.

**Cold starts are downloads.** `omnibin-shell` asks Nix to import the full
dependency closure on first byte read. This can fetch more than the old
one-path-at-a-time private cache. The module and container continue to fetch
individual NARs; see [design.md](./design.md#does-a-nar-index-help).

**Coverage is whatever the cache still has.** The multiverse census re-checks
liveness weekly, and omnibin only advertises paths it found alive. The tail
thins out going back in time, and a 2013 binary that does substitute may still
fail to run on a modern kernel.

**One database per system.** A store path belongs to one system, so each
system gets its own database and the flake serves the one matching yours.
`x86_64-linux` and `aarch64-linux` are both published. Darwin is not, and will
not be: the store paths exist, but there is no FUSE-over-`/nix/store` story on
macOS worth having.

aarch64 is slightly smaller than x86_64 rather than an afterthought: 47,672
executables against 51,468, over 224,246 package versions against 253,817. The
gap is packages Hydra never built for it.

**`ls /nix/store` lies by omission.** It lists what has been fetched. The
index is how you enumerate.

**Bare names are a policy, not a fact.** `python3` resolving to the `python3`
attribute's newest build is a rule this project chose. Two packages can ship
the same executable at the same version. `curl` and `curlWithGnuTls` both
have a `curl` 8.10.1, and `<name>@<version>` picks between them by the same
rule. When it matters, go through `/nix/store` directly.

**Run Nix outside the shell.** `omnibin-shell` registers imported paths in the
host Nix store, where `nix path-info` can query them. Inside the shell,
`/nix/store` is still the FUSE view; run Nix commands in the host namespace.
The NixOS module and container retain their private, unregistered cache.

**The FUSE process is a dependency of everything.** On a machine where the
module mounted `/nix/store`, killing omnibin takes the store with it until
systemd restarts it. This is the reason `omnibin-shell` exists and the reason
the module is documented for machines you can throw away.
