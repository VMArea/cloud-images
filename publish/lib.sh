HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export PATH="${PUBLISH_BIN:-$HOME/.local/bin}:$PATH"

die() { echo "error: $*" >&2; exit 1; }

need() { for c in "$@"; do command -v "$c" >/dev/null || die "missing $c (run publish/install-tools)"; done; }

selected_manifests() {
  python3 "$HERE/osfilter.py" "$1"
}
