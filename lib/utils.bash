#!/usr/bin/env bash

set -euo pipefail

GH_REPO="https://github.com/nodejs/node"
TOOL_NAME="nodejs"

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
	local version="$1"
	local download_path="$2"
	local release_file="$download_path/release.tar.gz"
	local release_dir="$download_path/release"
	mkdir -p "$release_dir"

	platform="$(uname -s | tr '[:upper:]' '[:lower:]')"
	arch="$(detect_arch)" || fail "unsupported architecture"

	# e.g. https://nodejs.org/dist/v18.17.1/node-v18.17.1-linux-x64.tar.gz
	url="https://nodejs.org/dist/v${version}/node-v${version}-${platform}-${arch}.tar.gz"

	echo "Downloading $TOOL_NAME release $version..."
	echo "  from url: $url"
	echo "  to path: $release_file"
	curl "${curl_opts[@]}" -o "$release_file" "$url" || fail "Could not download $url"

	tar -xzf "$release_file" -C "$release_dir" --strip-components=1 || fail "Could not extract $release_file"
}

install_version() {
	local install_type="$1"
	local version="$2"
	local install_path="$3"
	local download_path="$4"
	local release_dir="$download_path/release"

	if [ "$install_type" != "version" ]; then
		fail "asdf-$TOOL_NAME supports release installs only"
	fi

	(
		mkdir -p "$install_path"
		cp -r "$release_dir"/* "$install_path"

		chmod +x "$install_path/bin/node"
		"$install_path/bin/node" --help &>/dev/null || fail "failed to execute $TOOL_NAME"

		echo "Successfully installed to"
		echo "  $install_path"
	) || (
		rm -rf "$install_path"
		fail "An error occurred while installing $TOOL_NAME $version."
	)
}

#
# os/arch detection is based on https://github.com/pnpm/get.pnpm.io/blob/68ddd8aaa283a74bd10191085fff7235aa9043b5/install.sh#L45C1-L91
#

detect_platform() {
	local platform
	platform="$(uname -s | tr '[:upper:]' '[:lower:]')"

	case "${platform}" in
	windows) platform="win" ;;
	esac

	printf '%s' "${platform}"
}

detect_arch() {
	local arch
	arch="$(uname -m | tr '[:upper:]' '[:lower:]')"

	case "${arch}" in
	x86_64 | amd64) arch="x64" ;;
	arm64 | aarch64) arch="arm64" ;;
	esac

	printf '%s' "${arch}"
}
