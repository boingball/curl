#!/usr/bin/env bash
# Reproducible multi-CPU AmigaOS release builder for curl/libcurl.
set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/../configure.ac" ]]; then
  ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
elif [[ -f "$SCRIPT_DIR/configure.ac" ]]; then
  ROOT_DIR="$SCRIPT_DIR"
else
  echo "ERROR: cannot find curl configure.ac" >&2
  exit 1
fi

AMIGA_PREFIX="${AMIGA_PREFIX:-/opt/amiga}"
BUILD_ROOT="${BUILD_ROOT:-$ROOT_DIR/build-amiga}"
DIST_ROOT="${DIST_ROOT:-$ROOT_DIR/dist-amiga}"
JOBS="${JOBS:-1}"
REGENERATE=1
PACKAGE=1
CLEAN_FIRST=1
CLEAN_ONLY=0
STRIP_BINARIES=0
VERBOSE_MAKE=1
ALL_CPUS=(000 020 030 040 060)
REQUESTED_CPUS=()

usage() {
  cat <<EOF_USAGE
Usage: $SCRIPT_NAME [options] [CPU...]

CPU targets: 000 020 030 040 060 all

Options:
  --toolchain DIR   Toolchain prefix (default: /opt/amiga)
  --build-root DIR  Build directory root
  --dist-root DIR   Release output directory root
  --jobs N          Parallel make jobs (default: 1)
  --no-regen        Skip autoreconf -fi
  --no-clean        Reuse per-CPU build directories
  --no-package      Do not create the tar.gz archive
  --strip           Strip staged curl executables
  --clean-only      Remove build and dist directories
  --quiet-make      Use compact make output
  -h, --help        Show this help
EOF_USAGE
}

die() { echo "ERROR: $*" >&2; exit 1; }
note() { printf '\n==> %s\n' "$*"; }
require() { command -v "$1" >/dev/null 2>&1 || die "required command missing: $1"; }

canonical_cpu() {
  case "$1" in
    000|68000) echo 000;; 020|68020) echo 020;; 030|68030) echo 030;;
    040|68040) echo 040;; 060|68060) echo 060;; all) echo all;; *) return 1;;
  esac
}
cpu_flag() { case "$1" in 000) echo -m68000;; 020) echo -m68020;; 030) echo -m68030;; 040) echo -m68040;; 060) echo -m68060;; esac; }
cpu_suffix() { case "$1" in 000) echo '';; 020) echo .020;; 030) echo .030;; 040) echo .040;; 060) echo .060;; esac; }
cpu_name() { case "$1" in 000) echo 68000;; 020) echo 68020;; 030) echo 68030;; 040) echo 68040;; 060) echo 68060;; esac; }

while (($#)); do
  case "$1" in
    --toolchain) AMIGA_PREFIX="$2"; shift 2;;
    --build-root) BUILD_ROOT="$2"; shift 2;;
    --dist-root) DIST_ROOT="$2"; shift 2;;
    --jobs) JOBS="$2"; shift 2;;
    --no-regen) REGENERATE=0; shift;;
    --no-clean) CLEAN_FIRST=0; shift;;
    --no-package) PACKAGE=0; shift;;
    --strip) STRIP_BINARIES=1; shift;;
    --clean-only) CLEAN_ONLY=1; shift;;
    --quiet-make) VERBOSE_MAKE=0; shift;;
    -h|--help) usage; exit 0;;
    -*) die "unknown option: $1";;
    *) REQUESTED_CPUS+=("$1"); shift;;
  esac
done

[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || die "--jobs must be a positive integer"
if ((CLEAN_ONLY)); then rm -rf -- "$BUILD_ROOT" "$DIST_ROOT"; exit 0; fi

if ((${#REQUESTED_CPUS[@]} == 0)); then
  CPUS=("${ALL_CPUS[@]}")
else
  CPUS=()
  for requested in "${REQUESTED_CPUS[@]}"; do
    cpu="$(canonical_cpu "$requested")" || die "unknown CPU: $requested"
    if [[ "$cpu" == all ]]; then CPUS=("${ALL_CPUS[@]}"); break; fi
    [[ " ${CPUS[*]-} " == *" $cpu "* ]] || CPUS+=("$cpu")
  done
fi

CC="$AMIGA_PREFIX/bin/m68k-amigaos-gcc"
AR="$AMIGA_PREFIX/bin/m68k-amigaos-ar"
RANLIB="$AMIGA_PREFIX/bin/m68k-amigaos-ranlib"
STRIP="$AMIGA_PREFIX/bin/m68k-amigaos-strip"
SIZE_TOOL="$AMIGA_PREFIX/bin/m68k-amigaos-size"
[[ -x "$CC" && -x "$AR" && -x "$RANLIB" ]] || die "GCC toolchain not found under $AMIGA_PREFIX"
for command in autoreconf make awk sed sha256sum tar git file tee; do require "$command"; done
((STRIP_BINARIES == 0)) || [[ -x "$STRIP" ]] || die "strip tool missing: $STRIP"

VERSION="$(awk '$1=="#define" && $2=="LIBCURL_VERSION" {gsub(/"/,"",$3); print $3; exit}' "$ROOT_DIR/include/curl/curlver.h")"
[[ -n "$VERSION" ]] || die "could not determine curl version"
SAFE_VERSION="${VERSION//[^A-Za-z0-9._-]/_}"
RELEASE_NAME="curl-${SAFE_VERSION}-amigaos"
STAGE_DIR="$DIST_ROOT/$RELEASE_NAME"
ARCHIVE="$DIST_ROOT/$RELEASE_NAME.tar.gz"
LOG_DIR="$BUILD_ROOT/logs"
AMIGA_LIBS='-lnet -lc -lz -lunix -latomic -lgcc -lm'
GIT_COMMIT="$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"
GIT_BRANCH="$(git -C "$ROOT_DIR" branch --show-current 2>/dev/null || true)"
[[ -n "$GIT_BRANCH" ]] || GIT_BRANCH=detached
GIT_DIRTY=no
git -C "$ROOT_DIR" diff --quiet --ignore-submodules HEAD -- 2>/dev/null || GIT_DIRTY=yes
COMPILER_VERSION="$("$CC" --version | sed -n '1p')"

note "AmigaOS curl release build: $VERSION (${CPUS[*]})"
if ((REGENERATE)); then
  (cd "$ROOT_DIR" && autoreconf -fi)
  ! grep -Rqs 'curl_rtmp.c' "$ROOT_DIR/lib/Makefile.in" "$ROOT_DIR/lib/Makefile.inc" || die "stale curl_rtmp.c reference"
fi

mkdir -p -- "$BUILD_ROOT" "$LOG_DIR" "$DIST_ROOT"
rm -rf -- "$STAGE_DIR"
mkdir -p -- "$STAGE_DIR/docs"

cat >"$STAGE_DIR/BUILD-INFO.txt" <<EOF_INFO
curl for AmigaOS build information
==================================
curl version:       $VERSION
Git branch:         $GIT_BRANCH
Git commit:         $GIT_COMMIT
Working tree dirty: $GIT_DIRTY
Build date UTC:     $(date -u '+%Y-%m-%d %H:%M:%S UTC')
Toolchain prefix:   $AMIGA_PREFIX
Compiler:           $COMPILER_VERSION
CPU targets:        ${CPUS[*]}
Common CFLAGS:      -O0 -msoft-float -mcrt=clib2
Static libraries:   $AMIGA_LIBS
EOF_INFO

for cpu in "${CPUS[@]}"; do
  cflag="$(cpu_flag "$cpu")"
  suffix="$(cpu_suffix "$cpu")"
  build_dir="$BUILD_ROOT/$cpu"
  build_log="$LOG_DIR/build-$cpu.log"
  ((CLEAN_FIRST == 0)) || rm -rf -- "$build_dir"
  mkdir -p -- "$build_dir"

  note "Configuring $(cpu_name "$cpu")"
  (
    cd "$build_dir"
    PKG_CONFIG=true "$ROOT_DIR/configure" \
      --host=m68k-amigaos CC="$CC" AR="$AR" RANLIB="$RANLIB" \
      --disable-shared --disable-ipv6 --disable-dependency-tracking \
      --prefix="$AMIGA_PREFIX" --disable-netrc --without-libpsl \
      --with-amissl --with-zlib --disable-threaded-resolver \
      CFLAGS="$cflag -O0 -msoft-float -mcrt=clib2" LIBS="$AMIGA_LIBS"
    make -j"$JOBS" V="$VERBOSE_MAKE"
  ) 2>&1 | tee "$build_log"

  curl_src="$build_dir/src/curl"
  libcurl_src="$build_dir/lib/.libs/libcurl.a"
  [[ -f "$curl_src" && -f "$libcurl_src" ]] || die "missing output for CPU $cpu"
  cp -f -- "$curl_src" "$STAGE_DIR/curl$suffix"
  cp -f -- "$libcurl_src" "$STAGE_DIR/libcurl.a$suffix"
  ((STRIP_BINARIES == 0)) || "$STRIP" "$STAGE_DIR/curl$suffix"

  {
    printf '\n=== CPU %s ===\n' "$cpu"
    printf 'CFLAGS: %s -O0 -msoft-float -mcrt=clib2\n' "$cflag"
    file "$STAGE_DIR/curl$suffix"
    [[ -x "$SIZE_TOOL" ]] && "$SIZE_TOOL" "$STAGE_DIR/curl$suffix" || true
  } >>"$STAGE_DIR/BUILD-INFO.txt"
done

note "Adding release documentation"
cp -f -- "$ROOT_DIR/COPYING" "$STAGE_DIR/COPYING"
cp -f -- "$ROOT_DIR/docs/AMIGAOS.md" "$STAGE_DIR/docs/AMIGAOS.md"

cat >"$STAGE_DIR/FILES.txt" <<'EOF_FILES'
curl             68000 command-line executable
curl.020         68020 command-line executable
curl.030         68030 command-line executable
curl.040         68040 command-line executable
curl.060         68060 command-line executable

libcurl.a         68000 static library
libcurl.a.020     68020 static library
libcurl.a.030     68030 static library
libcurl.a.040     68040 static library
libcurl.a.060     68060 static library

docs/AMIGAOS.md  AmigaOS release and build notes
COPYING           curl licence
BUILD-INFO.txt    Build provenance and flags
SHA256SUMS        SHA-256 checksums
EOF_FILES

for cpu in "${ALL_CPUS[@]}"; do
  [[ " ${CPUS[*]} " == *" $cpu "* ]] && continue
  suffix="$(cpu_suffix "$cpu")"
  if [[ -z "$suffix" ]]; then
    sed -i '/^curl             68000/d;/^libcurl\.a         68000/d' "$STAGE_DIR/FILES.txt"
  else
    escaped="${suffix//./\\.}"
    sed -i "/^curl${escaped}[[:space:]]/d;/^libcurl\\.a${escaped}[[:space:]]/d" "$STAGE_DIR/FILES.txt"
  fi
done

(cd "$STAGE_DIR" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum >SHA256SUMS)
if ((PACKAGE)); then
  rm -f -- "$ARCHIVE" "$ARCHIVE.sha256"
  tar -C "$DIST_ROOT" -czf "$ARCHIVE" "$RELEASE_NAME"
  sha256sum "$ARCHIVE" >"$ARCHIVE.sha256"
fi

note "Release complete"
printf 'Staged release: %s\nBuild logs:    %s\n' "$STAGE_DIR" "$LOG_DIR"
((PACKAGE == 0)) || printf 'Archive:       %s\n' "$ARCHIVE"
