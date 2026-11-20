#!/bin/sh
# Aggregate built artifacts in dist/ into release form:
#   - SHA256SUMS over all cpython-*.tar.gz
#   - python-downloads.json (uv-compatible download metadata, ohos entries only)
#
#   ./scripts/release.sh <tag> [--repo owner/name]
set -eu

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
TAG=${1:?"usage: $0 <tag> [--repo owner/name]"}
shift
REPO_NAME=ohos-python/ohos-python
while [ $# -gt 0 ]; do
    case "$1" in
        --repo) REPO_NAME=$2; shift 2 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

cd "$REPO_ROOT/dist"
ls cpython-*.tar.gz >/dev/null

sha256sum cpython-*.tar.gz > SHA256SUMS
echo "=== SHA256SUMS ==="
cat SHA256SUMS

python3 "$REPO_ROOT/scripts/generate-uv-metadata.py" \
    --tag "$TAG" \
    --repo "$REPO_NAME" \
    --dir . \
    --output python-downloads.json
echo "=== python-downloads.json ==="
cat python-downloads.json
