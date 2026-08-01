#!/bin/sh
# One-line installer for agentop.
#
#   curl -fsSL https://raw.githubusercontent.com/pimlabs/agentop/main/install.sh | sh
#
# POSIX sh rather than bash, so it runs under a minimal /bin/sh (dash on
# Debian/Ubuntu, ash on Alpine, the stock sh on macOS). We cannot know which
# shell a machine has before anything is installed.
set -eu

REPO="pimlabs/agentop"
BINARY="agentop"

# An empty AGENTOP_VERSION means "ask the GitHub API for the latest release".
# Both knobs come from the environment rather than flags, because this script
# is piped into sh and a curl | sh user has no easy way to pass argv.
: "${AGENTOP_VERSION:=}"
: "${AGENTOP_INSTALL_DIR:=}"

err() {
	echo "install.sh: $*" >&2
	exit 1
}

info() {
	echo "install.sh: $*"
}

# The temp directory is removed through a trap so downloads do not pile up
# when the script stops halfway, for example on a failed checksum.
tmpdir=""
cleanup() {
	if [ -n "$tmpdir" ] && [ -d "$tmpdir" ]; then
		rm -rf "$tmpdir"
	fi
}
trap cleanup EXIT INT TERM

# --- detect the platform ----------------------------------------------
# goreleaser names its archives in Go's terms (darwin/linux, amd64/arm64), so
# map uname output onto those names rather than the other way round.
os_raw="$(uname -s)"
case "$os_raw" in
Darwin) os="darwin" ;;
Linux) os="linux" ;;
*)
	err "this script does not support the operating system '$os_raw'. agentop ships darwin and linux binaries; for anything else download one by hand from https://github.com/$REPO/releases or build from source with 'go install github.com/$REPO/cmd/agentop@latest'."
	;;
esac

arch_raw="$(uname -m)"
case "$arch_raw" in
x86_64 | amd64) arch="amd64" ;;
arm64 | aarch64) arch="arm64" ;;
*)
	err "this script does not support the architecture '$arch_raw'. agentop ships amd64 and arm64 binaries; download one by hand from https://github.com/$REPO/releases if yours differs."
	;;
esac

# --- pick a downloader: curl first, then wget --------------------------
downloader=""
if command -v curl >/dev/null 2>&1; then
	downloader="curl"
elif command -v wget >/dev/null 2>&1; then
	downloader="wget"
else
	err "downloading needs curl or wget, and neither was found on PATH."
fi

fetch() {
	# $1 = url, contents go to stdout
	url="$1"
	if [ "$downloader" = "curl" ]; then
		curl -fsSL "$url"
	else
		wget -qO- "$url"
	fi
}

download_to() {
	# $1 = url, $2 = destination path
	url="$1"
	dest="$2"
	if [ "$downloader" = "curl" ]; then
		curl -fsSL -o "$dest" "$url"
	else
		wget -qO "$dest" "$url"
	fi
}

# --- version -----------------------------------------------------------
version="$AGENTOP_VERSION"
if [ -z "$version" ]; then
	info "asking the GitHub API for the latest release..."
	# The API answers with JSON, and "tag_name" is pulled out without jq
	# because this script deliberately depends on nothing beyond curl/wget
	# and sha256sum/shasum.
	version="$(fetch "https://api.github.com/repos/$REPO/releases/latest" | grep '"tag_name"' | head -n1 | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')"
	if [ -z "$version" ]; then
		err "could not read the latest release version from the GitHub API. Set AGENTOP_VERSION=vX.Y.Z explicitly and run this again."
	fi
fi
# goreleaser's name_template uses {{ .Version }} with no leading 'v', while the
# git tag and the GitHub release URL both carry one. Keep the two apart.
version_notag="${version#v}"

info "installing agentop $version for $os/$arch..."

archive_name="agentop_${version_notag}_${os}_${arch}.tar.gz"
base_url="https://github.com/$REPO/releases/download/$version"

tmpdir="$(mktemp -d 2>/dev/null || mktemp -d -t agentop)"

download_to "$base_url/$archive_name" "$tmpdir/$archive_name"
download_to "$base_url/checksums.txt" "$tmpdir/checksums.txt"

# --- verify the checksum -------------------------------------------------
# goreleaser produces ONE combined checksums.txt for every archive in the
# release rather than a .sha256 per archive, so filter down to the line for
# our archive before verifying.
cd "$tmpdir"
grep " $archive_name\$" checksums.txt >"checksums.filtered.txt" || true
if [ ! -s "checksums.filtered.txt" ]; then
	err "checksums.txt has no line for $archive_name. The release may be incomplete; please report it at https://github.com/$REPO/issues."
fi

if command -v sha256sum >/dev/null 2>&1; then
	sha256sum -c "checksums.filtered.txt" >/dev/null || err "checksum verification failed for $archive_name. The download may be corrupt or tampered with; the install stops here."
elif command -v shasum >/dev/null 2>&1; then
	shasum -a 256 -c "checksums.filtered.txt" >/dev/null || err "checksum verification failed for $archive_name. The download may be corrupt or tampered with; the install stops here."
else
	err "verifying the download needs sha256sum or shasum, and neither was found on PATH. The install stops deliberately, because we do not install a binary we have not verified."
fi

tar -xzf "$archive_name" "$BINARY"
cd - >/dev/null

# --- choose the install directory ----------------------------------------
# In order: an explicit environment variable, then /usr/local/bin when it is
# writable, then ~/.local/bin as a fallback that needs no sudo (with a PATH
# warning).
install_dir=""
path_warning=0
if [ -n "$AGENTOP_INSTALL_DIR" ]; then
	install_dir="$AGENTOP_INSTALL_DIR"
elif [ -w "/usr/local/bin" ]; then
	install_dir="/usr/local/bin"
else
	install_dir="$HOME/.local/bin"
	path_warning=1
fi

mkdir -p "$install_dir"
install_path="$install_dir/$BINARY"
cp "$tmpdir/$BINARY" "$install_path"
chmod +x "$install_path"

# --- drop the Gatekeeper quarantine on darwin ----------------------------
# A binary downloaded through a browser or curl picks up the
# com.apple.quarantine xattr on macOS, and Gatekeeper then blocks it on first
# run because it is neither signed nor notarized. xattr -d fails when the
# attribute is not there at all (a plain curl download, for instance), so that
# failure is expected and deliberately ignored.
if [ "$os" = "darwin" ] && command -v xattr >/dev/null 2>&1; then
	xattr -d com.apple.quarantine "$install_path" 2>/dev/null || true
fi

info "agentop $version installed at $install_path"

case ":$PATH:" in
*":$install_dir:"*) ;;
*)
	path_warning=1
	;;
esac

if [ "$path_warning" -eq 1 ]; then
	info "warning: $install_dir does not look like it is on your PATH."
	info "add this line to your shell profile (~/.zshrc or ~/.bashrc, for example):"
	info "  export PATH=\"$install_dir:\$PATH\""
fi

info "try it: $BINARY -v"
