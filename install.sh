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
  -y, --yes       do not ask anything; take the defaults
  --help

  NU_CLI_REPO       the GitHub repository the builds are published to
  NU_CLI_BASE_URL   its address, if not https://github.com/<NU_CLI_REPO>
  NU_CLI_YES        same as --yes
EOF
    exit 0
}

YES="${NU_CLI_YES:-}"

while [ $# -gt 0 ]; do
    case "$1" in
    --version) VERSION="${2:-}" && VERSION_GIVEN=yes && shift 2 || die "--version needs a value" ;;
    --snapshot) CHANNEL="snapshot" && shift ;;
    --prefix) PREFIX="${2:-}" && shift 2 || die "--prefix needs a value" ;;
    --target) TARGET="${2:-}" && shift 2 || die "--target needs a value" ;;
    -y | --yes) YES=1 && shift ;;
    --help | -h) usage ;;
    *) die "unknown option '$1' (try --help)" ;;
    esac
done

# Questions go to the terminal on fd 3, not to stdin: the two documented ways to run this are
# `sh -c "$(curl ...)"` and `curl ... | sh`, and in the second one stdin is the script being read. Where there
# is no terminal to open - a container, a CI job, a pipeline - nothing is asked and the defaults stand, which
# is what keeps the one-liner a one-liner.
# Braced, so that the redirection silencing "no such device" belongs to the group rather than to `exec`
# itself - an `exec` with only redirections applies them to the shell, and stderr would stay in /dev/null for
# the rest of the run.
if [ -z "$YES" ] && { exec 3<> /dev/tty; } 2> /dev/null; then
    ASKING=yes
else
    ASKING=""
fi

ask() {
    printf '%s' "$1" >&3
    read -r REPLY <&3 || REPLY=""
}

# Yes unless told otherwise, since the person ran this to install something.
confirm() {
    [ -n "$ASKING" ] || return 0
    ask "$1 [Y/n] "
    case "$REPLY" in
    [nN] | [nN][oO]) return 1 ;;
    *) return 0 ;;
    esac
}

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

# ---- what is about to happen ---------------------------------------------------------------------

# Asked with a HEAD request, so the size is the one thing said about the download that is not a guess. A
# server that will not answer it costs nothing: the line is left out.
size=$(curl --fail --silent --show-error --location --head "${FILES}/${ARCHIVE}" 2> /dev/null |
    tr -d '\r' | sed -n 's/^[Cc]ontent-[Ll]ength: *//p' | tail -1)
if [ -n "$size" ]; then
    size=$(awk -v bytes="$size" 'BEGIN { printf "%.0f MB", bytes / 1048576 }')
else
    size="size unknown"
fi

printf '\n%snu-cli %s%s %s(%s)%s\n\n' "$BOLD" "$VERSION" "$OFF" "$DIM" "$TARGET" "$OFF"
printf '  %-11s %s %s(%s)%s\n' "download" "$ARCHIVE" "$DIM" "$size" "$OFF"
printf '  %-11s %s\n' "from" "$FILES"
printf '  %-11s %s\n\n' "install to" "${PREFIX}/nu-cli"

confirm "Download it?" || die "nothing was downloaded."

# ---- download, check, install -------------------------------------------------------------------

TMP=$(mktemp -d)
# The trap covers every exit, so a failed download leaves nothing behind.
trap 'rm -rf "$TMP"' EXIT INT TERM

# A progress bar where somebody is watching it, and silence in a log. Tens of megabytes is long enough that
# silence reads as a hang.
if [ -n "$ASKING" ] || [ -t 2 ]; then
    curl --fail --show-error --location --progress-bar --output "${TMP}/${ARCHIVE}" "${FILES}/${ARCHIVE}" ||
        die "could not download ${ARCHIVE} of version ${VERSION}. Check the version, and that this target was published."
else
    fetch --output "${TMP}/${ARCHIVE}" "${FILES}/${ARCHIVE}" ||
        die "could not download ${ARCHIVE} of version ${VERSION}. Check the version, and that this target was published."
fi
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

# Said out loud, because a checksum that is only checked in silence might as well not be checked: this is the
# line that tells somebody the bytes are the published ones.
printf '  %ssha256 ok%s %s%s…%s\n' "$GREEN" "$OFF" "$DIM" "$(printf '%s' "$checksum" | cut -c1-16)" "$OFF"

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

# Where it goes is asked rather than announced, and what is asked about is the whole path, the file name
# included - that is what somebody is deciding, and seeing `/nu-cli` on the end is how they know it is not
# being asked for a directory to dump things in.
DEST="${PREFIX}/nu-cli"

if [ -n "$ASKING" ]; then
    printf '\n' >&2
    # bash from 4 onwards can put the default into the line and leave the cursor after it, which is an answer
    # somebody edits rather than retypes. Everything else - dash, and the bash 3.2 that macOS still ships as
    # /bin/sh - gets the default in brackets, where enter accepts it.
    if [ -n "${BASH_VERSION:-}" ] && [ "${BASH_VERSION%%.*}" -ge 4 ] 2> /dev/null; then
        printf 'Install to: ' >&3
        # Readline reads the terminal as stdin, so the tty goes there rather than on fd 3.
        read -r -e -i "$DEST" REPLY < /dev/tty || REPLY="$DEST"
    else
        ask "Install to [${DEST}]: "
    fi

    if [ -n "$REPLY" ]; then
        # An answer typed at a prompt is not expanded by any shell, so a leading ~ would become a directory
        # with that name.
        case "$REPLY" in
        "~") REPLY="$HOME" ;;
        "~/"*) REPLY="${HOME}/${REPLY#\~/}" ;;
        esac
        # A directory was meant if it says so - it exists, or it ends in a slash - and then the file keeps the
        # name it had. Anything else is the path of the file itself, which is also how to install it under
        # another name.
        case "$REPLY" in
        */) DEST="${REPLY}nu-cli" ;;
        *) if [ -d "$REPLY" ]; then DEST="${REPLY}/nu-cli"; else DEST="$REPLY"; fi ;;
        esac
    fi
fi

PREFIX="$(dirname "$DEST")"
mkdir -p "$PREFIX" || die "cannot create ${PREFIX}. Choose a directory you can write to, or pass --prefix."
[ -w "$PREFIX" ] || die "${PREFIX} is not writable. Choose another directory, or pass --prefix."

chmod 755 "${TMP}/${BINARY}"
# mv within the same filesystem is atomic, so nobody can catch a half-written binary; across filesystems it
# falls back to a copy, which is why the temporary directory is not under $PREFIX.
mv -f "${TMP}/${BINARY}" "$DEST"

printf '\n%sinstalled%s %s\n' "$GREEN" "$OFF" "$DEST"

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

# Runs it rather than trusting it, and shows what it says: the version out of the binary is the only proof
# that what was installed is what was asked for.
if reported=$("$DEST" --version 2> /dev/null); then
    printf '%s%s%s says it is %s%s%s\n\n' "$DIM" "nu-cli" "$OFF" "$BOLD" "$reported" "$OFF"
    [ "$reported" = "$VERSION" ] || printf '%snote: that is not %s, which is what this installed.%s\n\n' "$DIM" "$VERSION" "$OFF" >&2
else
    problem "${DEST} did not run."
    note "On Alpine and other musl systems it needs libstdc++:"
    command_hint "apk add libstdc++"
    # Worth saying, because --target is the one way to end up with a binary for a machine that is not this
    # one, and then "did not run" is the expected outcome rather than a problem.
    printf '\n%sA binary fetched with --target for another platform is not expected to run here either.%s\n\n' "$DIM" "$OFF" >&2
fi
