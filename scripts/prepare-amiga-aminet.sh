#!/usr/bin/env bash
# Prepare an existing multi-CPU AmigaOS curl build for Aminet upload.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_ROOT="${DIST_ROOT:-$ROOT_DIR/dist-amiga}"
CREATE_LHA=0

usage() {
  cat <<EOF_USAGE
Usage: $(basename "$0") [--lha]

Prepare the latest AmigaOS curl release under dist-amiga for Aminet.

Options:
  --lha       Also create the Aminet LHA archive. Requires the lha command.
  -h, --help  Show this help.

Environment overrides:
  DIST_ROOT       Release output directory
  AMINET_DATE     Six-digit DDMMYY upload date
  AMINET_VERSION  Complete Aminet version field
  AMINET_REPLACES Package replaced by this upload
EOF_USAGE
}

while (($#)); do
  case "$1" in
    --lha) CREATE_LHA=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo "ERROR: unknown option: $1" >&2; usage >&2; exit 1;;
  esac
done

VERSION="$(awk '$1=="#define" && $2=="LIBCURL_VERSION" {gsub(/"/,"",$3); print $3; exit}' "$ROOT_DIR/include/curl/curlver.h")"
[[ -n "$VERSION" ]] || { echo 'ERROR: could not determine curl version' >&2; exit 1; }
SAFE_VERSION="${VERSION//[^A-Za-z0-9._-]/_}"
RELEASE_NAME="curl-${SAFE_VERSION}-amigaos"
STAGE_DIR="$DIST_ROOT/$RELEASE_NAME"
TEMPLATE="$ROOT_DIR/packages/AmigaOS/curl.readme.in"
[[ -d "$STAGE_DIR" ]] || { echo "ERROR: run make -f Makefile.amiga release first" >&2; exit 1; }
[[ -f "$TEMPLATE" ]] || { echo "ERROR: missing $TEMPLATE" >&2; exit 1; }

for required in curl curl.020 curl.030 curl.040 curl.060 \
  libcurl.a libcurl.a.020 libcurl.a.030 libcurl.a.040 libcurl.a.060; do
  [[ -f "$STAGE_DIR/$required" ]] || { echo "ERROR: release missing $required" >&2; exit 1; }
done

if [[ "$VERSION" == *-DEV ]]; then
  core="${VERSION%-DEV}"
  core="${core%.0}"
  default_version="${core}-DEV-${AMINET_DATE:-$(date -u '+%d%m%y')}"
else
  default_version="$VERSION"
fi
AMINET_VERSION="${AMINET_VERSION:-$default_version}"
AMINET_REPLACES="${AMINET_REPLACES:-comm/tcp/curl-8.18-DEV-18112025.lha}"
AMINET_BASENAME="curl-${AMINET_VERSION}"
README_NAME="${AMINET_BASENAME}.readme"
README_INNER="$STAGE_DIR/$README_NAME"
README_OUTER="$DIST_ROOT/$README_NAME"
TAR_ARCHIVE="$DIST_ROOT/$RELEASE_NAME.tar.gz"

# Old builder revisions placed these development/build artefacts in the release.
# Remove them before producing the upload, so an already-built release can be
# repackaged without recompiling every CPU target.
rm -rf -- "$STAGE_DIR/include" "$STAGE_DIR/build-logs"
if [[ -f "$STAGE_DIR/FILES.txt" ]]; then
  sed -i '/^include\/curl\//d;/^build-logs\//d;/Aminet upload readme/d' "$STAGE_DIR/FILES.txt"
fi

sed \
  -e "s|@VERSION@|$VERSION|g" \
  -e "s|@AMINET_VERSION@|$AMINET_VERSION|g" \
  -e "s|@AMINET_REPLACES@|$AMINET_REPLACES|g" \
  -e "s|@BUILD_DATE@|$(date -u '+%Y-%m-%d')|g" \
  "$TEMPLATE" >"$README_INNER"
cp -f -- "$README_INNER" "$README_OUTER"

if [[ -f "$STAGE_DIR/FILES.txt" ]]; then
  printf '%-30s Aminet upload readme\n' "$README_NAME" >>"$STAGE_DIR/FILES.txt"
fi

(cd "$STAGE_DIR" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum >SHA256SUMS)
rm -f -- "$TAR_ARCHIVE" "$TAR_ARCHIVE.sha256"
tar -C "$DIST_ROOT" -czf "$TAR_ARCHIVE" "$RELEASE_NAME"
sha256sum "$TAR_ARCHIVE" >"$TAR_ARCHIVE.sha256"

printf '\nAminet package prepared\n=======================\n'
printf 'Version field:  %s\nRelease drawer: %s\nReadme:         %s\n' "$AMINET_VERSION" "$STAGE_DIR" "$README_OUTER"

if ((CREATE_LHA)); then
  command -v lha >/dev/null 2>&1 || { echo 'ERROR: lha command is not installed' >&2; exit 1; }
  (cd "$DIST_ROOT" && rm -f "${AMINET_BASENAME}.lha" && lha a -r "${AMINET_BASENAME}.lha" "$RELEASE_NAME")
  printf 'LHA archive:    %s/%s.lha\n' "$DIST_ROOT" "$AMINET_BASENAME"
else
  printf 'LHA filename:   %s/%s.lha\n' "$DIST_ROOT" "$AMINET_BASENAME"
  printf '\nCreate it with: make -f Makefile.amiga aminet-lha\n'
fi
