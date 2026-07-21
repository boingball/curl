#!/usr/bin/env bash
#
# Prepare an existing multi-CPU AmigaOS curl build for Aminet upload.
#
# The script generates an Aminet .readme from packages/AmigaOS/curl.readme.in,
# places it both inside the release drawer and beside the archive, refreshes
# checksums and the tar.gz archive, and can optionally create an LHA archive.
#
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_ROOT="${DIST_ROOT:-$ROOT_DIR/dist-amiga}"
CREATE_LHA=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [--lha]

Prepare the latest AmigaOS curl release under dist-amiga for Aminet.

Options:
  --lha       Also create the Aminet LHA archive. Requires the lha command.
  -h, --help  Show this help.

Optional environment overrides:
  DIST_ROOT       Release output directory.
  AMINET_DATE     Six-digit DDMMYY upload date.
  AMINET_VERSION  Complete Aminet version field.
  AMINET_REPLACES Package replaced by this upload.
EOF
}

while (($#)); do
  case "$1" in
    --lha)
      CREATE_LHA=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'ERROR: Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

VERSION="$(
  awk '
    $1 == "#define" && $2 == "LIBCURL_VERSION" {
      gsub(/"/, "", $3)
      print $3
      exit
    }
  ' "$ROOT_DIR/include/curl/curlver.h"
)"
[[ -n "$VERSION" ]] || {
  printf 'ERROR: Could not determine LIBCURL_VERSION\n' >&2
  exit 1
}

SAFE_VERSION="${VERSION//[^A-Za-z0-9._-]/_}"
RELEASE_DIR_NAME="curl-${SAFE_VERSION}-amigaos"
STAGE_DIR="$DIST_ROOT/$RELEASE_DIR_NAME"
TEMPLATE="$ROOT_DIR/packages/AmigaOS/curl.readme.in"

[[ -d "$STAGE_DIR" ]] || {
  printf 'ERROR: Release drawer does not exist: %s\n' "$STAGE_DIR" >&2
  printf 'Run: make -f Makefile.amiga release\n' >&2
  exit 1
}
[[ -f "$TEMPLATE" ]] || {
  printf 'ERROR: Aminet readme template is missing: %s\n' "$TEMPLATE" >&2
  exit 1
}

# An Aminet upload should contain every supported CPU target.
for required in \
  curl curl.020 curl.030 curl.040 curl.060 \
  libcurl.a libcurl.a.020 libcurl.a.030 libcurl.a.040 libcurl.a.060; do
  [[ -f "$STAGE_DIR/$required" ]] || {
    printf 'ERROR: Complete Aminet release is missing: %s\n' "$required" >&2
    exit 1
  }
done

if [[ "$VERSION" == *-DEV ]]; then
  VERSION_CORE="${VERSION%-DEV}"
  VERSION_CORE="${VERSION_CORE%.0}"
  DEFAULT_AMINET_VERSION="${VERSION_CORE}-DEV-${AMINET_DATE:-$(date -u '+%d%m%y')}"
else
  DEFAULT_AMINET_VERSION="$VERSION"
fi

AMINET_VERSION="${AMINET_VERSION:-$DEFAULT_AMINET_VERSION}"
AMINET_REPLACES="${AMINET_REPLACES:-comm/tcp/curl-8.18-DEV-18112025.lha}"
AMINET_BASENAME="curl-${AMINET_VERSION}"
AMINET_README_NAME="${AMINET_BASENAME}.readme"
AMINET_README_INNER="$STAGE_DIR/$AMINET_README_NAME"
AMINET_README_OUTER="$DIST_ROOT/$AMINET_README_NAME"
TAR_ARCHIVE="$DIST_ROOT/${RELEASE_DIR_NAME}.tar.gz"

mkdir -p "$DIST_ROOT"

sed \
  -e "s|@VERSION@|$VERSION|g" \
  -e "s|@AMINET_VERSION@|$AMINET_VERSION|g" \
  -e "s|@AMINET_REPLACES@|$AMINET_REPLACES|g" \
  -e "s|@BUILD_DATE@|$(date -u '+%Y-%m-%d')|g" \
  "$TEMPLATE" >"$AMINET_README_INNER"
cp -f "$AMINET_README_INNER" "$AMINET_README_OUTER"

if [[ -f "$STAGE_DIR/FILES.txt" ]]; then
  sed -i '/Aminet upload readme/d' "$STAGE_DIR/FILES.txt"
  printf '%-30s Aminet upload readme\n' \
    "$AMINET_README_NAME" >>"$STAGE_DIR/FILES.txt"
fi

(
  cd "$STAGE_DIR"
  find . -type f ! -name SHA256SUMS -print0 |
    sort -z |
    xargs -0 sha256sum >SHA256SUMS
)

# Refresh the normal archive so it includes the generated readme as well.
rm -f "$TAR_ARCHIVE" "$TAR_ARCHIVE.sha256"
tar -C "$DIST_ROOT" -czf "$TAR_ARCHIVE" "$RELEASE_DIR_NAME"
sha256sum "$TAR_ARCHIVE" >"$TAR_ARCHIVE.sha256"

printf '\nAminet package prepared\n'
printf '=======================\n'
printf 'Version field:  %s\n' "$AMINET_VERSION"
printf 'Release drawer: %s\n' "$STAGE_DIR"
printf 'Readme:         %s\n' "$AMINET_README_OUTER"
printf 'LHA filename:   %s/%s.lha\n' "$DIST_ROOT" "$AMINET_BASENAME"

if ((CREATE_LHA)); then
  command -v lha >/dev/null 2>&1 || {
    printf 'ERROR: --lha requested but the lha command is not installed\n' >&2
    exit 1
  }

  (
    cd "$DIST_ROOT"
    rm -f "${AMINET_BASENAME}.lha"
    lha a -r "${AMINET_BASENAME}.lha" "$RELEASE_DIR_NAME"
  )

  printf 'LHA archive:    %s/%s.lha\n' "$DIST_ROOT" "$AMINET_BASENAME"
else
  printf '\nCreate the Aminet archive with:\n'
  printf '  (cd %q && lha a -r %q %q)\n' \
    "$DIST_ROOT" "${AMINET_BASENAME}.lha" "$RELEASE_DIR_NAME"
  printf '\nOr run:\n'
  printf '  make -f Makefile.amiga aminet-lha\n'
fi
