#!/usr/bin/env bash

set -euo pipefail

GH_REPO="https://github.com/pnpm/pnpm"
TOOL_NAME="pnpm"

fail() {
	echo -e "asdf-$TOOL_NAME: $*"
	exit 1
}

curl_opts=(-fsSL)

# NOTE: You might want to remove this if <YOUR TOOL> is not hosted on GitHub releases.
if [ -n "${GITHUB_API_TOKEN:-}" ]; then
	curl_opts=("${curl_opts[@]}" -H "Authorization: token $GITHUB_API_TOKEN")
fi

sort_versions() {
	sed 'h; s/[+-]/./g; s/.p\([[:digit:]]\)/.z\1/; s/$/.z/; G; s/\n/ /' |
		LC_ALL=C sort -t. -k 1,1 -k 2,2n -k 3,3n -k 4,4n -k 5,5n | awk '{print $2}'
}

list_github_tags() {
	# TODO: filter out versions without binary releases
	git ls-remote --tags --refs "$GH_REPO" |
		grep -o 'refs/tags/v.*' | cut -d/ -f3- |
		sed 's/^v//' # NOTE: You might want to adapt this sed to remove non-version strings from tags
}

list_all_versions() {
	list_github_tags
}

download_release() {
	local version filename url
	version="$1"
	filename="$2"

	platform="$(detect_platform)"
	arch="$(detect_arch)" || fail "unsupported architecture"
	url="$GH_REPO/releases/download/v${version}/pnpm-${platform}-${arch}"

	echo "* Downloading $TOOL_NAME release $version..."
	echo "* - url = $url"
	echo "* - filename = $filename"
	curl "${curl_opts[@]}" -o "$filename" "$url" || fail "Could not download $url"
}

install_version() {
	local install_type="$1"
	local version="$2"
	local install_path="${3%/bin}/bin"

	if [ "$install_type" != "version" ]; then
		fail "asdf-$TOOL_NAME supports release installs only"
	fi

	(
		mkdir -p "$install_path"
		cp -r "$ASDF_DOWNLOAD_PATH"/* "$install_path"

		chmod +x "$install_path/$TOOL_NAME"
		"$install_path/$TOOL_NAME" --help &>/dev/null || fail "failed to execute $TOOL_NAME"

		echo "$TOOL_NAME $version installation was successful!"
	) || (
		rm -rf "$install_path"
		fail "An error occurred while installing $TOOL_NAME $version."
	)
}

#
# os/arch detection is copied from https://github.com/pnpm/get.pnpm.io/blob/68ddd8aaa283a74bd10191085fff7235aa9043b5/install.sh#L45C1-L91
#

is_glibc_compatible() {
	getconf GNU_LIBC_VERSION >/dev/null 2>&1 || ldd --version >/dev/null 2>&1 || return 1
}

detect_platform() {
	local platform
	platform="$(uname -s | tr '[:upper:]' '[:lower:]')"

	case "${platform}" in
	linux)
		if is_glibc_compatible; then
			platform="linux"
		else
			platform="linuxstatic"
		fi
		;;
	darwin) platform="macos" ;;
	windows) platform="win" ;;
	esac

	printf '%s' "${platform}"
}

detect_arch() {
	local arch
	arch="$(uname -m | tr '[:upper:]' '[:lower:]')"

	case "${arch}" in
	x86_64 | amd64) arch="x64" ;;
	armv*) arch="arm" ;;
	arm64 | aarch64) arch="arm64" ;;
	esac

	# `uname -m` in some cases mis-reports 32-bit OS as 64-bit, so double check
	if [ "${arch}" = "x64" ] && [ "$(getconf LONG_BIT)" -eq 32 ]; then
		arch=i686
	elif [ "${arch}" = "arm64" ] && [ "$(getconf LONG_BIT)" -eq 32 ]; then
		arch=arm
	fi

	case "$arch" in
	x64*) ;;
	arm64*) ;;
	*) return 1 ;;
	esac
	printf '%s' "${arch}"
}
