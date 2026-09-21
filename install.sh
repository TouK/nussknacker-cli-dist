#!/bin/sh
# Installs nu-cli, the Nussknacker command line client, as a single executable - no Node, no npm.
#
#   sh -c "$(curl -fsSL https://raw.githubusercontent.com/TouK/nussknacker-cli-dist/main/install.sh)"
#
# Downloading with curl rather than a browser is not incidental: a browser marks what it saves with
# com.apple.quarantine, and macOS then kills the binary on sight, with no message at all. Nothing
# fetched here carries that attribute.
#
# Options:
#   --version <v>   version to install (default: the newest release)
#   --snapshot      the newest snapshot of master instead of the newest release
#   --prefix <dir>  where to put the binary (default: ~/.local/bin, or $NU_CLI_PREFIX)
#   --target <name> override platform detection, e.g. linux-x64-musl
#   --help
set -eu

# Every build is a GitHub release of this repository, tagged with its version, and every file is one of that
# release's assets. Three addresses follow from that, and no API call does: `releases/latest/download/<file>`
# is whatever is released now - GitHub resolves it and leaves prereleases out - `releases/download/<tag>/<file>`
# is one named build, and the redirect of `releases/latest` names the released version without asking for it.
REPO="${NU_CLI_REPO:-TouK/nussknacker-cli-dist}"
BASE="${NU_CLI_BASE_URL:-https://github.com/${REPO}}"
PREFIX="${NU_CLI_PREFIX:-$HOME/.local/bin}"
VERSION=""
TARGET=""
# Which of the two to read when no version is named. A release is what someone gets by default; a snapshot has
# to be asked for. The snapshot pointer moves only for a build of master, so asking for one never lands on
# somebody's branch - those are published too, and reached by name with --version.
CHANNEL="latest"

# Colour only when somebody is looking at it: a pipe, a file or a CI log gets plain text, and NO_COLOR is
# honoured because it costs one condition to honour it.
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]; then
    BOLD=$(printf '\033[1m')
    RED=$(printf '\033[31m')
    GREEN=$(printf '\033[32m')
    CYAN=$(printf '\033[36m')
    DIM=$(printf '\033[2m')
    OFF=$(printf '\033[0m')
else
    BOLD="" RED="" GREEN="" CYAN="" DIM="" OFF=""
fi

# What went wrong, on its own, with room around it. Every one of these ends the run, so the blank line above
# separates it from whatever the shell printed last rather than from more of ours.
problem() {
    printf '\n%s%s%s\n\n' "${BOLD}${RED}" "$1" "${OFF}" >&2
}

# A line of prose under a problem, and a command to run, which is what people actually copy out.
note() { printf '%s\n' "$1" >&2; }
command_hint() { printf '    %s%s%s\n' "$CYAN" "$1" "$OFF" >&2; }

die() {
    problem "$1"
    exit 1
}

usage() {
    # Spelled out rather than read back from this file: the usual way to run this is
    # `sh -c "$(curl ...)"`, where there is no file to read.
    cat << 'EOF'
install.sh - install nu-cli, the Nussknacker command line client, as a single executable

  --version <v>   version to install (default: the newest release)
  --snapshot      the newest snapshot of master instead of the newest release
  --prefix <dir>  where to put the binary (default: ~/.local/bin, or $NU_CLI_PREFIX)
  --target <name> override platform detection, e.g. linux-x64-musl
  --help

  NU_CLI_REPO       the GitHub repository the builds are published to
  NU_CLI_BASE_URL   its address, if not https://github.com/<NU_CLI_REPO>
EOF
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
    --version) VERSION="${2:-}" && VERSION_GIVEN=yes && shift 2 || die "--version needs a value" ;;
    --snapshot) CHANNEL="snapshot" && shift ;;
    --prefix) PREFIX="${2:-}" && shift 2 || die "--prefix needs a value" ;;
    --target) TARGET="${2:-}" && shift 2 || die "--target needs a value" ;;
    --help | -h) usage ;;
    *) die "unknown option '$1' (try --help)" ;;
    esac
done

command -v curl > /dev/null 2>&1 || die "curl is needed and was not found"

fetch() {
    # --fail turns an HTML error page into a non-zero exit, which is the difference between a clear failure
    # here and a "binary" that turns out to be an error page. --location because every one of these addresses
    # is a redirect: GitHub answers with the release's storage URL.
    curl --fail --silent --show-error --location "$@"
}

# ---- which file this machine needs --------------------------------------------------------------

detect_target() {
    os=$(uname -s)
    arch=$(uname -m)

    case "$os" in
    Darwin) platform=darwin ;;
    Linux) platform=linux ;;
    *) die "unsupported system '$os'. The published targets are linux and darwin (x64/arm64) and windows-x64; pass --target to force one." ;;
    esac

    case "$arch" in
    x86_64 | amd64) cpu=x64 ;;
    arm64 | aarch64) cpu=arm64 ;;
    *) die "unsupported architecture '$arch'" ;;
    esac

    # The plain linux builds link against glibc. Alpine and friends need the musl ones, and they in turn
    # need libstdc++ present (apk add libstdc++). The dynamic loader is the reliable tell: musl installs
    # it as /lib/ld-musl-<arch>.so.1, and where that is missing, `ldd --version` names the library.
    libc=""
    if [ "$platform" = linux ]; then
        if ls /lib/ld-musl-* > /dev/null 2>&1 || (ldd --version 2>&1 | grep -qi musl); then
            libc="-musl"
        fi
    fi

    echo "${platform}-${cpu}${libc}"
}

[ -n "$TARGET" ] || TARGET=$(detect_target)

# The windows build is published with the extension Windows needs; every other target is bare. Only
# `--target` can ask for it - detection never yields windows - but asking for it has to work.
case "$TARGET" in
windows*) BINARY="nu-cli-${TARGET}.exe" ;;
*) BINARY="nu-cli-${TARGET}" ;;
esac
# What is published is the executable gzipped: under half the size, so that much less to download. gzip is
# the one compressor a machine can be assumed to already have - Debian and Ubuntu ship no xz decompressor,
# and nothing ships zstd.
ARCHIVE="${BINARY}.gz"

# ---- which version, and where its files are -----------------------------------------------------

# `releases/latest` answers 302 to `releases/tag/<version>`, so the released version can be read from the
# redirect. One request, no API, and nothing to rate-limit: the API allows 60 calls an hour to an address
# with no token, which is not something to spend on an install.
released_version() {
    location=$(curl --silent --show-error --output /dev/null --write-out '%{redirect_url}' "${BASE}/releases/latest" || true)
    case "$location" in
    */releases/tag/*) echo "${location##*/releases/tag/}" ;;
    *) echo "" ;;
    esac
}

if [ -z "$VERSION" ]; then
    if [ "$CHANNEL" = latest ]; then
        VERSION=$(released_version)
        [ -n "$VERSION" ] || {
            problem "Nothing has been released yet."
            note "For the newest build of master, ask for a snapshot:"
            command_hint "sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/${REPO}/main/install.sh)\" -- --snapshot"
            printf '\n%sThe -- is not decoration: without it the flag is taken as the script'"'"'s own name.%s\n' "$DIM" "$OFF" >&2
            printf '%sEvery build there is, released or not: %s/releases%s\n\n' "$DIM" "$BASE" "$OFF" >&2
            exit 1
        }
    else
        # A tiny asset on a release that carries nothing else, rewritten by every publish from master. An
        # asset rather than a file in the repository, because a release asset is replaced in place and served
        # at once, where raw file serving sits behind a cache measured in minutes.
        #
        # Fetched on its own line, and quietly: through a pipe it is `tr`'s status that survives, so a 404
        # would pass for an empty file and the message would be about the wrong thing.
        marker=$(curl --fail --silent --location "${BASE}/releases/download/snapshot/latest.txt") || {
            # What somebody sees when the only builds published so far came from a branch: those exist, they
            # are just not what `--snapshot` means. The file this reads is nobody's business - where to look
            # instead is.
            problem "There is no snapshot of master to install yet."
            note "Builds made from a branch are published under their own version:"
            command_hint "sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/${REPO}/main/install.sh)\" -- --version <version>"
            printf '\n%sWhich versions there are: %s/releases%s\n\n' "$DIM" "$BASE" "$OFF" >&2
            exit 1
        }
        VERSION=$(printf '%s' "$marker" | tr -d ' \t\r\n')
        # Published, but naming nothing: not something the person running this can do anything about, so it
        # says what it is rather than where it read it.
        [ -n "$VERSION" ] || die "the snapshot channel names no version. Ask for one by name with --version, or report it."
    fi
fi

# `releases/latest/download/...` where that is what was asked for: it is one redirect rather than two, and it
# stays correct if a release is published between these two requests.
if [ "$CHANNEL" = latest ] && [ -z "${VERSION_GIVEN:-}" ]; then
    FILES="${BASE}/releases/latest/download"
else
    FILES="${BASE}/releases/download/${VERSION}"
fi

printf '%snu-cli %s%s %s(%s)%s\n' "$BOLD" "$VERSION" "$OFF" "$DIM" "$TARGET" "$OFF"

# ---- download, check, install -------------------------------------------------------------------

TMP=$(mktemp -d)
# The trap covers every exit, so a failed download leaves nothing behind.
trap 'rm -rf "$TMP"' EXIT INT TERM

fetch --output "${TMP}/${ARCHIVE}" "${FILES}/${ARCHIVE}" ||
    die "could not download ${ARCHIVE} of version ${VERSION}. Check the version, and that this target was published."
fetch --output "${TMP}/SHA256SUMS" "${FILES}/SHA256SUMS" || die "could not download SHA256SUMS"

if command -v sha256sum > /dev/null 2>&1; then
    checksum=$(sha256sum "${TMP}/${ARCHIVE}" | cut -d' ' -f1)
elif command -v shasum > /dev/null 2>&1; then
    checksum=$(shasum -a 256 "${TMP}/${ARCHIVE}" | cut -d' ' -f1)
else
    die "neither sha256sum nor shasum was found, so the download cannot be verified"
fi

# Verified before it is unpacked, and on the bytes that crossed the network rather than on something
# derived from them.
expected=$(sed -n "s/^\([0-9a-f]\{64\}\)  *${ARCHIVE}\$/\1/p" "${TMP}/SHA256SUMS")
[ -n "$expected" ] || die "SHA256SUMS of version ${VERSION} says nothing about ${ARCHIVE}"
[ "$checksum" = "$expected" ] || die "checksum mismatch for ${ARCHIVE}: got ${checksum}, expected ${expected}. The download is not what was published - do not run it."

# Whichever of the three the machine has; they are the same program under different names, and a system
# without any of them is rare enough to be worth a clear message rather than a fallback.
if command -v gunzip > /dev/null 2>&1; then
    gunzip -c "${TMP}/${ARCHIVE}" > "${TMP}/${BINARY}"
elif command -v gzip > /dev/null 2>&1; then
    gzip -dc "${TMP}/${ARCHIVE}" > "${TMP}/${BINARY}"
elif command -v zcat > /dev/null 2>&1; then
    zcat "${TMP}/${ARCHIVE}" > "${TMP}/${BINARY}"
else
    die "none of gunzip, gzip or zcat was found, and the download is gzipped"
fi

mkdir -p "$PREFIX"
chmod 755 "${TMP}/${BINARY}"
# mv within the same filesystem is atomic, so nobody can catch a half-written binary; across filesystems it
# falls back to a copy, which is why the temporary directory is not under $PREFIX.
mv -f "${TMP}/${BINARY}" "${PREFIX}/nu-cli"

printf '%sinstalled%s %s\n' "$GREEN" "$OFF" "${PREFIX}/nu-cli"

case ":${PATH}:" in
*":${PREFIX}:"*) ;;
*)
    # To stderr, like every other remark here: stdout carries the two lines worth piping anywhere, which are
    # what was installed and where.
    printf '\n%s%s is not on your PATH.%s Add it, or call the binary by its full path:\n' "$BOLD" "$PREFIX" "$OFF" >&2
    command_hint "export PATH=\"${PREFIX}:\$PATH\""
    printf '\n' >&2
    ;;
esac

"${PREFIX}/nu-cli" --version > /dev/null 2>&1 || {
    problem "${PREFIX}/nu-cli did not run."
    note "On Alpine and other musl systems it needs libstdc++:"
    command_hint "apk add libstdc++"
    # Worth saying, because --target is the one way to end up with a binary for a machine that is not this
    # one, and then "did not run" is the expected outcome rather than a problem.
    printf '\n%sA binary fetched with --target for another platform is not expected to run here either.%s\n\n' "$DIM" "$OFF" >&2
}
