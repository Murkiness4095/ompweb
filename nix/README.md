# Nix packaging (fork notes)

`nix run .` builds and starts the web UI. Requires `nix` with flakes enabled; no
`omp` on `PATH` is needed to *start* the app, but talking to an agent does require it.

```bash
nix run .                    # http://127.0.0.1:30177
nix run . -- --port 8080     # flags are forwarded to the ompweb binary
nix build .#default          # build without running
nix flake check              # evaluate everything
```

## What is fork-local

Upstream ([kahme247/ompweb](https://github.com/kahme247/ompweb)) tracks `flake.nix`
and `nix/package.nix`, and those files are kept close to upstream so merges stay small.
Two things here are fork-local:

| File | Why it exists |
| --- | --- |
| `nix/local-fonts-shim.mjs` | Rewrites `next/font/google` → `next/font/local` at build time. Upstream's approach was a `patches` diff against `app/layout.tsx`, which had to restate that file's import block and every font call verbatim and so broke on unrelated upstream edits. |
| `.github/workflows/verify-nix.yml` | Upstream CI never builds with Nix, so nothing caught the broken flake. |

## Things that will need attention after an upstream sync

### 1. `npmDepsHash` (expected — this one always happens)

Any upstream change to `package-lock.json` changes the npm dependency tree, so the
pinned hash no longer matches and the build fails with a hash mismatch. This is
inherent to `buildNpmPackage`, not a bug in this packaging.

Nix prints the expected value in the error, so fixing it is a copy-paste:

```bash
nix build .#default 2>&1 | grep -oE 'got: +sha256-[A-Za-z0-9+/=]+'
```

Paste that value into the `npmDepsHash` line in `nix/package.nix`. CI
(`.github/workflows/verify-nix.yml`) does this check on every push, so a sync that
misses it fails in CI instead of on your machine.

### 2. A new font added to `app/layout.tsx`

The shim warns and falls back to Geist:

```
[local-fonts-shim] WARNING: no vendored font for Roboto; falling back to Geist.ttf.
```

That keeps the build working, but the font renders wrong. To vendor it properly, add a
`fetchurl` for the face in `nix/package.nix`, `cp` it into `app/fonts/` in `postPatch`,
and add an entry to `FONT_MAP` in `nix/local-fonts-shim.mjs`.

### 3. A new network-dependent build step

The build is sandboxed with no network. The Google-font fetch was the only such step,
and it is handled above. Anything else that reaches the network during `next build`
needs a vendored substitute added here.