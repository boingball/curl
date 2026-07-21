#!/usr/bin/env bash
#
# Reproducible multi-CPU AmigaOS release builder for curl/libcurl.
#
# Default:
#   - regenerates Autotools files
#   - builds 68000, 68020, 68030, 68040 and 68060
#   - uses the known-good GCC 13.2 toolchain under /opt/amiga
#   - stages release binaries, libraries, headers and documentation
#   - creates a .tar.gz release archive
#
# Examples:
#   ./scripts/build-amiga-release.sh
#   ./scripts/build-amiga-release.sh 020 030 040 060
#   ./scripts/build-amiga-release.sh --jobs 1 --no-package 030
#   ./scripts/build-amiga-release.sh --clean-only
#
set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# The script is intended to live in curl/scripts/.  It also works when copied
# to the repository root.
if [[ -f "$SCRIPT_DIR/../configure.ac" ]]; then
  ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
elif [[ -f "$SCRIPT_DIR/configure.ac" ]]; then
  ROOT_DIR="$SCRIPT_DIR"
else
  printf 'ERROR: Could not find curl configure.ac relative to %s\n' "$SCRIPT_DIR" >&2
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
KEEP_STAGE=1
VERBOSE_MAKE=1

ALL_CPUS=(000 020 030 040 060)
REQUESTED_CPUS=()

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [options] [CPU...]

Build curl and static libcurl for AmigaOS CPU targets.

CPU targets:
  000   68000 baseline
  020   68020
  030   68030
  040   68040
  060   68060
  all   all of the above (default)

Options:
  --toolchain DIR     Toolchain prefix (default: /opt/amiga)
  --build-root DIR    Build directory root
  --dist-root DIR     Release output directory root
  --jobs N            Parallel make jobs (default: 1)
  --no-regen          Do not run autoreconf -fi
  --no-clean          Reuse existing per-CPU build directories
  --no-package        Build and stage files, but do not create tar.gz
  --strip             Strip curl executables before staging
  --clean-only        Remove build and dist directories, then exit
  --quiet-make        Use normal compact make output instead of V=1
  -h, --help          Show this help

Environment equivalents:
  AMIGA_PREFIX, BUILD_ROOT, DIST_ROOT, JOBS

Common commands:
  $SCRIPT_NAME
  $SCRIPT_NAME 020 030 040 060
  $SCRIPT_NAME --no-package 030
  $SCRIPT_NAME --clean-only
EOF
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

note() {
  printf '\n==> %s\n' "$*"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

canonical_cpu() {
  case "$1" in
    000|68000) printf '%s\n' 000 ;;
    020|68020) printf '%s\n' 020 ;;
    030|68030) printf '%s\n' 030 ;;
    040|68040) printf '%s\n' 040 ;;
    060|68060) printf '%s\n' 060 ;;
    all)       printf '%s\n' all ;;
    *) return 1 ;;
  esac
}

cpu_cflag() {
  case "$1" in
    000) printf '%s\n' '-m68000' ;;
    020) printf '%s\n' '-m68020' ;;
    030) printf '%s\n' '-m68030' ;;
    040) printf '%s\n' '-m68040' ;;
    060) printf '%s\n' '-m68060' ;;
    *) die "Internal error: unknown CPU target $1" ;;
  esac
}

cpu_suffix() {
  case "$1" in
    000) printf '%s\n' '' ;;
    020) printf '%s\n' '.020' ;;
    030) printf '%s\n' '.030' ;;
    040) printf '%s\n' '.040' ;;
    060) printf '%s\n' '.060' ;;
    *) die "Internal error: unknown CPU target $1" ;;
  esac
}

cpu_name() {
  case "$1" in
    000) printf '%s\n' '68000' ;;
    020) printf '%s\n' '68020' ;;
    030) printf '%s\n' '68030' ;;
    040) printf '%s\n' '68040' ;;
    060) printf '%s\n' '68060' ;;
    *) die "Internal error: unknown CPU target $1" ;;
  esac
}

while (($#)); do
  case "$1" in
    --toolchain)
      (($# >= 2)) || die "--toolchain needs a directory"
      AMIGA_PREFIX="$2"
      shift 2
      ;;
    --build-root)
      (($# >= 2)) || die "--build-root needs a directory"
      BUILD_ROOT="$2"
      shift 2
      ;;
    --dist-root)
      (($# >= 2)) || die "--dist-root needs a directory"
      DIST_ROOT="$2"
      shift 2
      ;;
    --jobs)
      (($# >= 2)) || die "--jobs needs a number"
      JOBS="$2"
      [[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || die "--jobs must be a positive integer"
      shift 2
      ;;
    --no-regen)
      REGENERATE=0
      shift
      ;;
    --no-clean)
      CLEAN_FIRST=0
      shift
      ;;
    --no-package)
      PACKAGE=0
      shift
      ;;
    --strip)
      STRIP_BINARIES=1
      shift
      ;;
    --clean-only)
      CLEAN_ONLY=1
      shift
      ;;
    --quiet-make)
      VERBOSE_MAKE=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      while (($#)); do
        REQUESTED_CPUS+=("$1")
        shift
      done
      ;;
    -*)
      die "Unknown option: $1"
      ;;
    *)
      REQUESTED_CPUS+=("$1")
      shift
      ;;
  esac
done

if ((CLEAN_ONLY)); then
  note "Removing build and release directories"
  rm -rf -- "$BUILD_ROOT" "$DIST_ROOT"
  printf 'Removed:\n  %s\n  %s\n' "$BUILD_ROOT" "$DIST_ROOT"
  exit 0
fi

if ((${#REQUESTED_CPUS[@]} == 0)); then
  CPUS=("${ALL_CPUS[@]}")
else
  CPUS=()
  for requested in "${REQUESTED_CPUS[@]}"; do
    canonical="$(canonical_cpu "$requested")" ||
      die "Unknown CPU target: $requested"
    if [[ "$canonical" == all ]]; then
      CPUS=("${ALL_CPUS[@]}")
      break
    fi

    already_added=0
    for existing in "${CPUS[@]:-}"; do
      if [[ "$existing" == "$canonical" ]]; then
        already_added=1
        break
      fi
    done
    ((already_added)) || CPUS+=("$canonical")
  done
fi

CC="$AMIGA_PREFIX/bin/m68k-amigaos-gcc"
AR="$AMIGA_PREFIX/bin/m68k-amigaos-ar"
RANLIB="$AMIGA_PREFIX/bin/m68k-amigaos-ranlib"
STRIP="$AMIGA_PREFIX/bin/m68k-amigaos-strip"
READELF="$AMIGA_PREFIX/bin/m68k-amigaos-readelf"
SIZE_TOOL="$AMIGA_PREFIX/bin/m68k-amigaos-size"

[[ -x "$CC" ]] || die "Compiler not found or not executable: $CC"
[[ -x "$AR" ]] || die "Archiver not found or not executable: $AR"
[[ -x "$RANLIB" ]] || die "ranlib not found or not executable: $RANLIB"

require_command autoreconf
require_command make
require_command awk
require_command sed
require_command sha256sum
require_command tar
require_command git
require_command file

if ((STRIP_BINARIES)); then
  [[ -x "$STRIP" ]] || die "--strip requested but tool is missing: $STRIP"
fi

VERSION="$(
  awk '
    $1 == "#define" && $2 == "LIBCURL_VERSION" {
      gsub(/"/, "", $3)
      print $3
      exit
    }
  ' "$ROOT_DIR/include/curl/curlver.h"
)"
[[ -n "$VERSION" ]] || die "Could not determine LIBCURL_VERSION"

SAFE_VERSION="${VERSION//[^A-Za-z0-9._-]/_}"
RELEASE_DIR_NAME="curl-${SAFE_VERSION}-amigaos"
STAGE_DIR="$DIST_ROOT/$RELEASE_DIR_NAME"
ARCHIVE="$DIST_ROOT/${RELEASE_DIR_NAME}.tar.gz"

GIT_COMMIT="$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || printf unknown)"
GIT_BRANCH="$(git -C "$ROOT_DIR" branch --show-current 2>/dev/null || true)"
[[ -n "$GIT_BRANCH" ]] || GIT_BRANCH="detached"
GIT_DIRTY="no"
git -C "$ROOT_DIR" diff --quiet --ignore-submodules HEAD -- 2>/dev/null || GIT_DIRTY="yes"

COMPILER_VERSION="$("$CC" --version | sed -n '1p')"

note "AmigaOS curl release build"
printf 'Repository:       %s\n' "$ROOT_DIR"
printf 'Git branch:       %s\n' "$GIT_BRANCH"
printf 'Git commit:       %s\n' "$GIT_COMMIT"
printf 'Working tree dirty: %s\n' "$GIT_DIRTY"
printf 'curl version:     %s\n' "$VERSION"
printf 'Toolchain:        %s\n' "$AMIGA_PREFIX"
printf 'Compiler:         %s\n' "$COMPILER_VERSION"
printf 'CPU targets:      %s\n' "${CPUS[*]}"
printf 'Build root:       %s\n' "$BUILD_ROOT"
printf 'Release root:     %s\n' "$DIST_ROOT"
printf 'Make jobs:        %s\n' "$JOBS"

if ((REGENERATE)); then
  note "Regenerating Autotools files"
  (
    cd "$ROOT_DIR"
    autoreconf -fi
  )

  if grep -R --line-number --fixed-strings 'curl_rtmp.c' \
      "$ROOT_DIR/lib/Makefile.in" "$ROOT_DIR/lib/Makefile.inc" \
      >/dev/null 2>&1; then
    die "Stale curl_rtmp.c reference remains after autoreconf"
  fi
fi

mkdir -p -- "$BUILD_ROOT" "$DIST_ROOT"
rm -rf -- "$STAGE_DIR"
mkdir -p -- "$STAGE_DIR/include/curl" "$STAGE_DIR/docs" "$STAGE_DIR/build-logs"

# Static link order is deliberate:
#   - clib2 is linked before libgcc
#   - libgcc is followed by libm, which resolves soft-float helpers such as
#     __adddf3 without pulling in clib2 a second time and causing __CTOR_LIST__
#     multiple-definition errors.
AMIGA_LIBS='-lnet -lc -lz -lunix -latomic -lgcc -lm'

build_cpu() {
  local cpu="$1"
  local cflag suffix build_dir build_log curl_src libcurl_src curl_dst libcurl_dst
  local make_verbose

  cflag="$(cpu_cflag "$cpu")"
  suffix="$(cpu_suffix "$cpu")"
  build_dir="$BUILD_ROOT/$cpu"
  build_log="$STAGE_DIR/build-logs/build-${cpu}.log"

  if ((CLEAN_FIRST)); then
    rm -rf -- "$build_dir"
  fi
  mkdir -p -- "$build_dir"

  note "Configuring $(cpu_name "$cpu") target ($cflag)"
  (
    cd "$build_dir"

    PKG_CONFIG=true "$ROOT_DIR/configure" \
      --host=m68k-amigaos \
      CC="$CC" \
      AR="$AR" \
      RANLIB="$RANLIB" \
      --disable-shared \
      --disable-ipv6 \
      --disable-dependency-tracking \
      --prefix="$AMIGA_PREFIX" \
      --disable-netrc \
      --without-libpsl \
      --with-amissl \
      --with-zlib \
      --disable-threaded-resolver \
      CFLAGS="$cflag -O0 -msoft-float -mcrt=clib2" \
      LIBS="$AMIGA_LIBS"
  ) 2>&1 | tee "$build_log"

  note "Building CPU $cpu"
  if ((VERBOSE_MAKE)); then
    make_verbose=1
  else
    make_verbose=0
  fi

  (
    cd "$build_dir"
    make -j"$JOBS" V="$make_verbose"
  ) 2>&1 | tee -a "$build_log"

  curl_src="$build_dir/src/curl"
  libcurl_src="$build_dir/lib/.libs/libcurl.a"
  [[ -f "$curl_src" ]] || die "Missing curl output for CPU $cpu: $curl_src"
  [[ -f "$libcurl_src" ]] || die "Missing libcurl output for CPU $cpu: $libcurl_src"

  curl_dst="$STAGE_DIR/curl${suffix}"
  libcurl_dst="$STAGE_DIR/libcurl.a${suffix}"

  cp -f -- "$curl_src" "$curl_dst"
  cp -f -- "$libcurl_src" "$libcurl_dst"

  if ((STRIP_BINARIES)); then
    "$STRIP" "$curl_dst"
  fi

  {
    printf '\n=== CPU %s ===\n' "$cpu"
    printf 'CFLAGS: %s -O0 -msoft-float -mcrt=clib2\n' "$cflag"
    printf 'LIBS:   %s\n' "$AMIGA_LIBS"
    file "$curl_dst"
    if [[ -x "$SIZE_TOOL" ]]; then
      "$SIZE_TOOL" "$curl_dst" || true
    fi
    if [[ -x "$READELF" ]]; then
      "$READELF" -h "$curl_dst" 2>/dev/null |
        sed -n '/Class:/p;/Data:/p;/Machine:/p' || true
    fi
  } | tee -a "$STAGE_DIR/BUILD-INFO.txt"

  printf 'Built:\n  %s\n  %s\n' "$curl_dst" "$libcurl_dst"
}

cat >"$STAGE_DIR/BUILD-INFO.txt" <<EOF
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
Parallel jobs:      $JOBS

Common configuration
--------------------

--host=m68k-amigaos
--disable-shared
--disable-ipv6
--disable-dependency-tracking
--disable-netrc
--without-libpsl
--with-amissl
--with-zlib
--disable-threaded-resolver

Common CFLAGS:
  -O0 -msoft-float -mcrt=clib2

Static library order:
  $AMIGA_LIBS
EOF

for cpu in "${CPUS[@]}"; do
  build_cpu "$cpu"
done

note "Adding headers, documentation and licence"
cp -f -- "$ROOT_DIR/COPYING" "$STAGE_DIR/COPYING"
cp -f -- "$ROOT_DIR/docs/AMIGAOS.md" "$STAGE_DIR/docs/AMIGAOS.md"
cp -f -- "$ROOT_DIR/include/curl/"*.h "$STAGE_DIR/include/curl/"

cat >"$STAGE_DIR/FILES.txt" <<'EOF'
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

include/curl/     Public libcurl development headers
docs/AMIGAOS.md  AmigaOS release and build notes
COPYING           curl licence
BUILD-INFO.txt    Exact build provenance and flags
SHA256SUMS        SHA-256 checksums
build-logs/       Configure and compiler output for each CPU
EOF

# Remove entries from FILES.txt that were not requested in this invocation.
for cpu in "${ALL_CPUS[@]}"; do
  present=0
  for built_cpu in "${CPUS[@]}"; do
    [[ "$cpu" == "$built_cpu" ]] && present=1
  done
  if ((present == 0)); then
    suffix="$(cpu_suffix "$cpu")"
    if [[ -z "$suffix" ]]; then
      sed -i '/^curl             68000/d;/^libcurl\.a         68000/d' "$STAGE_DIR/FILES.txt"
    else
      escaped_suffix="${suffix//./\\.}"
      sed -i "/^curl${escaped_suffix}[[:space:]]/d;/^libcurl\\.a${escaped_suffix}[[:space:]]/d" \
        "$STAGE_DIR/FILES.txt"
    fi
  fi
done

note "Generating checksums"
(
  cd "$STAGE_DIR"
  find . -type f ! -name SHA256SUMS -print0 |
    sort -z |
    xargs -0 sha256sum > SHA256SUMS
)

if ((PACKAGE)); then
  note "Creating release archive"
  rm -f -- "$ARCHIVE"
  tar -C "$DIST_ROOT" -czf "$ARCHIVE" "$RELEASE_DIR_NAME"
  sha256sum "$ARCHIVE" >"$ARCHIVE.sha256"
fi

note "Release complete"
printf 'Staged release:\n  %s\n' "$STAGE_DIR"
if ((PACKAGE)); then
  printf 'Archive:\n  %s\n  %s\n' "$ARCHIVE" "$ARCHIVE.sha256"
fi

printf '\nNext checks on AmigaOS:\n'
printf '  curl --version\n'
printf '  curl https://example.com/\n'
printf '  curl --compressed https://example.com/\n'
