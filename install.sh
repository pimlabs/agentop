#!/bin/sh
# Pemasang satu baris untuk agentop.
#
#   curl -fsSL https://raw.githubusercontent.com/pimlabs/agentop/main/install.sh | sh
#
# POSIX sh (bukan bash) supaya jalan di /bin/sh minimal (dash di Debian/Ubuntu,
# ash di Alpine, sh bawaan macOS), karena kita tidak tahu shell apa yang
# tersedia di mesin pengguna sebelum instalasi.
set -eu

REPO="pimlabs/agentop"
BINARY="agentop"

# AGENTOP_VERSION kosong berarti "ambil rilis terbaru dari GitHub API".
# Diset lewat env, bukan flag, karena skrip ini dijalankan lewat pipe ke sh
# dan tidak punya argv yang mudah dijangkau pengguna curl | sh.
: "${AGENTOP_VERSION:=}"
: "${AGENTOP_INSTALL_DIR:=}"

err() {
	echo "install.sh: $*" >&2
	exit 1
}

info() {
	echo "install.sh: $*"
}

# Direktori sementara dibersihkan lewat trap supaya berkas unduhan tidak
# menumpuk kalau skrip berhenti di tengah jalan (verifikasi gagal, dsb).
tmpdir=""
cleanup() {
	if [ -n "$tmpdir" ] && [ -d "$tmpdir" ]; then
		rm -rf "$tmpdir"
	fi
}
trap cleanup EXIT INT TERM

# --- deteksi platform -------------------------------------------------
# Nama arsip goreleaser memakai istilah Go (darwin/linux, amd64/arm64), jadi
# petakan keluaran uname ke istilah itu, bukan sebaliknya.
os_raw="$(uname -s)"
case "$os_raw" in
Darwin) os="darwin" ;;
Linux) os="linux" ;;
*)
	err "sistem operasi '$os_raw' belum didukung skrip ini. agentop menyediakan biner darwin dan linux; untuk yang lain unduh manual dari https://github.com/$REPO/releases atau build dari sumber dengan 'go install github.com/$REPO/cmd/agentop@latest'."
	;;
esac

arch_raw="$(uname -m)"
case "$arch_raw" in
x86_64 | amd64) arch="amd64" ;;
arm64 | aarch64) arch="arm64" ;;
*)
	err "arsitektur '$arch_raw' belum didukung skrip ini. agentop menyediakan biner amd64 dan arm64; unduh manual dari https://github.com/$REPO/releases kalau arsitekturmu berbeda."
	;;
esac

# --- pilih unduh: curl lalu wget --------------------------------------
downloader=""
if command -v curl >/dev/null 2>&1; then
	downloader="curl"
elif command -v wget >/dev/null 2>&1; then
	downloader="wget"
else
	err "butuh curl atau wget untuk mengunduh, tidak ada satu pun yang ditemukan di PATH."
fi

fetch() {
	# $1 = url, cetak isi ke stdout
	url="$1"
	if [ "$downloader" = "curl" ]; then
		curl -fsSL "$url"
	else
		wget -qO- "$url"
	fi
}

download_to() {
	# $1 = url, $2 = path tujuan
	url="$1"
	dest="$2"
	if [ "$downloader" = "curl" ]; then
		curl -fsSL -o "$dest" "$url"
	else
		wget -qO "$dest" "$url"
	fi
}

# --- versi -------------------------------------------------------------
version="$AGENTOP_VERSION"
if [ -z "$version" ]; then
	info "mengambil versi rilis terbaru dari GitHub API..."
	# API GitHub mengembalikan JSON; ambil "tag_name" tanpa dependensi jq
	# karena skrip ini sengaja tanpa dependensi non-standar selain
	# curl/wget dan sha256sum/shasum.
	version="$(fetch "https://api.github.com/repos/$REPO/releases/latest" | grep '"tag_name"' | head -n1 | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')"
	if [ -z "$version" ]; then
		err "gagal membaca versi rilis terbaru dari GitHub API. Set AGENTOP_VERSION=vX.Y.Z secara eksplisit dan jalankan ulang."
	fi
fi
# goreleaser name_template memakai {{ .Version }} tanpa awalan 'v', tapi tag
# git dan URL rilis GitHub memakai 'v'. Simpan keduanya terpisah.
version_notag="${version#v}"

info "memasang agentop $version untuk $os/$arch..."

archive_name="agentop_${version_notag}_${os}_${arch}.tar.gz"
base_url="https://github.com/$REPO/releases/download/$version"

tmpdir="$(mktemp -d 2>/dev/null || mktemp -d -t agentop)"

download_to "$base_url/$archive_name" "$tmpdir/$archive_name"
download_to "$base_url/checksums.txt" "$tmpdir/checksums.txt"

# --- verifikasi checksum -------------------------------------------------
# goreleaser menghasilkan SATU checksums.txt gabungan untuk semua arsip
# rilis, bukan satu .sha256 per arsip, jadi saring baris yang cocok dengan
# nama arsip kita sebelum diverifikasi.
cd "$tmpdir"
grep " $archive_name\$" checksums.txt >"checksums.filtered.txt" || true
if [ ! -s "checksums.filtered.txt" ]; then
	err "checksums.txt tidak berisi baris untuk $archive_name. Rilisnya mungkin tidak lengkap; laporkan di https://github.com/$REPO/issues."
fi

if command -v sha256sum >/dev/null 2>&1; then
	sha256sum -c "checksums.filtered.txt" >/dev/null || err "verifikasi checksum gagal untuk $archive_name. Arsip unduhan mungkin rusak atau diganggu; jangan lanjutkan pemasangan."
elif command -v shasum >/dev/null 2>&1; then
	shasum -a 256 -c "checksums.filtered.txt" >/dev/null || err "verifikasi checksum gagal untuk $archive_name. Arsip unduhan mungkin rusak atau diganggu; jangan lanjutkan pemasangan."
else
	err "butuh sha256sum atau shasum untuk memverifikasi unduhan, tidak ada satu pun yang ditemukan di PATH. Pemasangan dihentikan sengaja karena kami tidak memasang biner tanpa verifikasi checksum."
fi

tar -xzf "$archive_name" "$BINARY"
cd - >/dev/null

# --- pilih direktori pasang ----------------------------------------------
# Urutan: env eksplisit, lalu /usr/local/bin kalau bisa ditulis, lalu
# ~/.local/bin sebagai fallback tanpa sudo (dengan peringatan PATH).
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

# --- buang karantina Gatekeeper di darwin --------------------------------
# Biner yang diunduh lewat browser/curl dapat atribut xattr
# com.apple.quarantine di macOS, yang membuat Gatekeeper memblokirnya saat
# pertama dijalankan karena belum ditandatangani/notarized. xattr -d gagal
# kalau atributnya memang tidak ada (mis. unduhan lewat curl polos tanpa
# quarantine flag), jadi kegagalan itu bukan error dan sengaja diabaikan.
if [ "$os" = "darwin" ] && command -v xattr >/dev/null 2>&1; then
	xattr -d com.apple.quarantine "$install_path" 2>/dev/null || true
fi

info "agentop $version terpasang di $install_path"

case ":$PATH:" in
*":$install_dir:"*) ;;
*)
	path_warning=1
	;;
esac

if [ "$path_warning" -eq 1 ]; then
	info "peringatan: $install_dir sepertinya belum ada di PATH kamu."
	info "tambahkan baris berikut ke shell profile kamu (mis. ~/.zshrc atau ~/.bashrc):"
	info "  export PATH=\"$install_dir:\$PATH\""
fi

info "coba jalankan: $BINARY -v"
