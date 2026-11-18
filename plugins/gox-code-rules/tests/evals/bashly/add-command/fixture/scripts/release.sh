#!/usr/bin/env bash
# 把版本号写入 VERSION 文件
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: release.sh <version>

Write <version> to the VERSION file in the current directory.

Exit codes: 0 ok, 1 usage error
USAGE
}

die() { echo "Error: $*" >&2; exit 1; }

VERSION=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -*) usage >&2; die "unknown option: $1" ;;
    *) [ -z "${VERSION}" ] || die "unexpected argument: $1"; VERSION="$1"; shift ;;
  esac
done
[ -n "${VERSION}" ] || { usage >&2; die "missing <version>"; }

echo "${VERSION}" >VERSION
echo "released ${VERSION}"
