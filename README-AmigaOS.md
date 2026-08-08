# curl for AmigaOS — build and maintenance cheat sheet

This file is the short version for maintaining the `amigaos` branch of this fork.

The normal upstream curl source remains on `master`. The AmigaOS port lives on the separate `amigaos` branch as a small set of Amiga-specific commits, build scripts and packaging files on top of upstream curl.

For the detailed AmigaOS port notes, requirements and manual compiler setup, see [`docs/AMIGAOS.md`](docs/AMIGAOS.md).

## First-time checkout

Clone this fork and switch to the AmigaOS branch:

```sh
git clone https://github.com/boingball/curl.git
cd curl
git switch amigaos
```

Add the official curl repository as `upstream` once:

```sh
git remote add upstream https://github.com/curl/curl.git
git fetch upstream
```

Check the remotes if needed:

```sh
git remote -v
```

Expected layout:

```text
origin    -> https://github.com/boingball/curl.git
upstream  -> https://github.com/curl/curl.git
```

## Normal AmigaOS builds

Build all supported CPU releases:

```sh
make -f Makefile.amiga release
```

Supported CPU targets are:

```text
000 020 030 040 060
```

Build just one CPU, for example 68030:

```sh
make -f Makefile.amiga 030
```

Other individual builds:

```sh
make -f Makefile.amiga 000
make -f Makefile.amiga 020
make -f Makefile.amiga 040
make -f Makefile.amiga 060
```

Clean generated Amiga build files:

```sh
make -f Makefile.amiga clean
```

## Aminet package

After a release build has already been made, prepare the Aminet release drawer and generated `.readme`:

```sh
make -f Makefile.amiga aminet
```

To also create an LhA archive when `lha` is installed:

```sh
make -f Makefile.amiga aminet-lha
```

To build everything and then prepare the Aminet package in one command:

```sh
make -f Makefile.amiga release-aminet
```

Or build, package and make the LhA in one command:

```sh
make -f Makefile.amiga release-aminet-lha
```

Versioned output is written under:

```text
dist-amiga/
```

The exact drawer and `.readme` names are generated from the current curl version/date, so they will change as upstream curl changes.

## Updating to the latest upstream curl

This is the normal maintenance procedure. It keeps upstream curl on `master` and then merges the new upstream code underneath the AmigaOS changes.

Before starting, make sure the working tree is clean:

```sh
git status
```

Fetch both repositories:

```sh
git fetch origin --prune
git fetch upstream --prune
```

Update the fork's `master` branch to the latest official curl `master`:

```sh
git switch master
git pull --ff-only origin master
git merge --ff-only upstream/master
git push origin master
```

The `--ff-only` options are deliberate: if `master` has unexpected local/fork-only commits, Git stops instead of silently creating a messy merge.

Now apply the latest upstream curl underneath the AmigaOS port:

```sh
git switch amigaos
git pull --ff-only origin amigaos
git merge master
```

If there are no conflicts, test the Amiga build:

```sh
make -f Makefile.amiga clean
make -f Makefile.amiga release
```

If the full release succeeds, optionally prepare the Aminet package too:

```sh
make -f Makefile.amiga aminet
```

Then push the updated AmigaOS branch:

```sh
git push origin amigaos
```

That is the normal update cycle. There is no need to recreate the port or cherry-pick all the Amiga commits again: merging the updated `master` into `amigaos` carries the existing AmigaOS work forward.

## If upstream causes merge conflicts

A conflict only means upstream curl changed the same lines/files that the AmigaOS port changed.

See the affected files:

```sh
git status
```

Resolve each conflict, then stage the resolved files:

```sh
git add <resolved-file>
```

Finish the merge:

```sh
git commit
```

Then rebuild all Amiga targets before pushing:

```sh
make -f Makefile.amiga clean
make -f Makefile.amiga release
```

If the merge turns out to be wrong and has not been committed yet, return to the pre-merge state with:

```sh
git merge --abort
```

## Quick update checklist

For an already-configured checkout, this is the whole routine:

```sh
git status

git fetch origin --prune
git fetch upstream --prune

git switch master
git pull --ff-only origin master
git merge --ff-only upstream/master
git push origin master

git switch amigaos
git pull --ff-only origin amigaos
git merge master

make -f Makefile.amiga clean
make -f Makefile.amiga release
make -f Makefile.amiga aminet

git push origin amigaos
```

## Important AmigaOS files

The port-specific pieces are intentionally kept small and easy to identify:

```text
Makefile.amiga
README-AmigaOS.md
docs/AMIGAOS.md
packages/AmigaOS/curl.readme.in
scripts/build-amiga-release.sh
scripts/prepare-amiga-aminet.sh
```

There are also small integration changes to the normal curl build/documentation files. To see the complete AmigaOS delta against upstream/fork `master` at any time:

```sh
git diff master...amigaos
```

Or just list the changed files:

```sh
git diff --name-status master...amigaos
```

## Known-good release toolchain

The current AmigaOS release process uses the known-good GCC 13.2 m68k-amigaos toolchain. GCC 15.2 builds previously showed runtime crashes on AmigaOS, so do not casually change the release compiler without testing on real AmigaOS/WinUAE first.

The automated builder handles the CPU flags and release layout; use `Makefile.amiga` rather than manually reconstructing the compiler command unless debugging the port.
