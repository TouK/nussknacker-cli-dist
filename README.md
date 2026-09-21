# Nussknacker CLI

**nu-cli** is the command line client for a [Nussknacker](https://nussknacker.io) designer — the web
application scenarios are built in, documented at [docs.nussknacker.io](https://docs.nussknacker.io). One
file with its runtime inside it, so there is no npm and no Node to install first. Three things it does:

- **reads and edits scenarios** — list them, print the graph, see why one will not deploy, change it, save
  it, deploy it;
- **moves data** — produce messages into a running scenario and consume what comes out;
- **serves the designer to an AI agent** over MCP, so an agent does all of the above through its own tools.
  See [Serving an AI agent (MCP)](#serving-an-ai-agent-mcp).

```bash
nu-cli scenario list                     # what is on this instance
nu-cli scenario graph fraud-detection    # what that scenario actually does
nu-cli scenario validate fraud-detection # why it will not deploy
nu-cli send                              # push one message through it
```

First run, once it is installed:

```bash
nu-cli login --url https://your-designer.example --browser   # obtain a token
nu-cli whoami                                                # which instance, as whom, from which files
nu-cli scenario list                                         # what is on it
```

## Install

Each pipeline that touches the CLI builds one executable per platform — the whole client, runtime
included, in a single file. Installing one is a line, with no token and nothing to choose:

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/TouK/nussknacker-cli-dist/main/install.sh)"
```

The files live in [TouK/nussknacker-cli-dist](https://github.com/TouK/nussknacker-cli-dist), a public
repository that holds no code: one release per version, the executables attached to it, and the two
installers and this page beside them — see [Publishing](#publishing). The installer reads which version is
current, picks the file for the machine (musl included), verifies it against the published `SHA256SUMS`,
unpacks it and installs it as `~/.local/bin/nu-cli`. What it takes:

|                   |                                                      |
| ----------------- | ---------------------------------------------------- |
| `--snapshot`      | the newest published snapshot instead of a release   |
| `--version <v>`   | that exact version                                   |
| `--prefix <dir>`  | directory to install into, instead of `~/.local/bin` |
| `--target <name>` | a platform other than the detected one               |

Arguments go after a `--`, which stands in for the name a shell expects first:

```bash
sh -c "$(curl -fsSL .../nussknacker-cli-dist/main/install.sh)" -- --snapshot
curl -fsSL .../nussknacker-cli-dist/main/install.sh | sh -s -- --snapshot   # the same, through a pipe
```

Left out, the flag is taken as the script's own name and the installer sees no arguments at all — so it goes
to the release channel, and says only that there is no release to install.

A release is what the bare command installs, however many snapshots came after it: that is GitHub's own
`releases/latest`, which leaves prereleases out, so it needs no marker and no API call. `--snapshot` reads
one instead — a `latest.txt` on a release called `snapshot` — and that pointer is moved **only by a build of
master**. Branch builds are published too, under their own version and reachable with `--version`, but they
never take over the address people are told to use. `nu-cli -v` reports the version it was built from,
commit included, so what is installed is always identifiable and can be compared with the designer it talks
to.

Installing this way is also what keeps macOS quiet: Gatekeeper kills a binary that a _browser_ saved,
without printing anything, and nothing fetched with `curl` carries the attribute that triggers it.

### Windows

`install.sh` is POSIX `sh`, which Windows does not have, so `install.ps1` is published beside it and does
the same job with what PowerShell has:

```powershell
irm https://raw.githubusercontent.com/TouK/nussknacker-cli-dist/main/install.ps1 | iex
```

It installs `%LOCALAPPDATA%\Programs\nu-cli\nu-cli.exe`, and takes `-Version`, `-Snapshot`, `-Prefix`,
`-Target` and `-AddToPath` — the last one because a Windows installer is expected to make the command
work, while touching the environment is still a decision rather than a side effect. Without it, the
script says the directory is not on `PATH` and leaves it at that.

Passing an argument needs the scriptblock form, since `iex` on a string has nowhere to put one:

```powershell
& ([scriptblock]::Create((irm .../nussknacker-cli-dist/main/install.ps1))) -Snapshot -AddToPath
```

`Invoke-WebRequest` does not attach the mark of the web to what it writes, so the executable runs without
SmartScreen asking about it — the same reason the other installer uses `curl`. Windows also locks a
running executable instead of letting it be replaced, so an install over a `nu-cli mcp` that an editor
still has open fails; the script says which file and why.

WSL and Git Bash are POSIX enough for `install.sh`, and that is the better route if the binary is for use
inside them — the Windows executable cannot run there, nor the Linux one outside.

Taking a file by hand works too — from the releases page, or from the `build-cli-binaries` artifact of any
pipeline, which expires where a release does not. Everything published is gzipped, and `SHA256SUMS` covers
the gzipped file:

```bash
dist=https://github.com/TouK/nussknacker-cli-dist/releases
curl -fsSLO $dist/latest/download/nu-cli-linux-x64.gz          # or /download/<version>/… for one build
curl -fsSL  $dist/latest/download/SHA256SUMS -o SHA256SUMS
sha256sum -c SHA256SUMS --ignore-missing
gunzip nu-cli-linux-x64.gz
chmod +x nu-cli-linux-x64
./nu-cli-linux-x64 --version
```

Which file to take:

| File                      | For                                                             |
| ------------------------- | --------------------------------------------------------------- |
| `nu-cli-linux-x64`        | most Linux machines and CI runners (glibc)                      |
| `nu-cli-linux-arm64`      | arm64 Linux (glibc)                                             |
| `nu-cli-linux-x64-musl`   | Alpine and other musl distributions — needs `apk add libstdc++` |
| `nu-cli-linux-arm64-musl` | arm64 Alpine — same                                             |
| `nu-cli-darwin-arm64`     | Apple silicon                                                   |
| `nu-cli-darwin-x64`       | Intel Macs                                                      |
| `nu-cli-windows-x64.exe`  | Windows                                                         |

Published, each of those carries a `.gz` suffix. macOS quarantines a binary downloaded through a browser;
`xattr -d com.apple.quarantine nu-cli-darwin-arm64` clears it, and downloading with `curl` avoids it
altogether.

This is also the easiest way to give an agent the MCP server: the client config points at the file, with no
`npx` and no Node to install. See [Serving an AI agent (MCP)](#serving-an-ai-agent-mcp).

To build them from a checkout, with [Bun](https://bun.sh) installed
(`curl -fsSL https://bun.sh/install | bash`):

```bash
cd designer/client/packages/cli
npm run build:binary                        # this machine's platform, into dist-binary/
npm run build:binary -- --all               # every published target
npm run build:binary -- --target linux-x64  # one of them
NUSSKNACKER_VERSION=1.20.0 npm run build:binary   # stamp a version into `nu-cli -v`
```

Bun is the compiler only: the bundle inside the executable is the same esbuild output `npm run build:cli`
produces, so what ships and what you run from a checkout are the same program.

Every target leaves a `<binary>.gz` beside it, since that is what gets published. Asking for this machine's
target alone — the first line above — keeps the uncompressed executable as well, so there is something to
run; a build of several targets keeps only the archives, rather than putting a second copy of 60–85 MB into
the CI artifact.

## Licenses of what is inside

What ships is one file with its dependencies compiled into it, and those dependencies come with terms that
ask to travel with the copies. So they do:

```bash
nu-cli --licenses            # every bundled package, its license and its copyright notice
nu-cli --licenses | less
npm run licenses             # the same text from a checkout, without building anything
```

The list is collected at build time from esbuild's metafile — that is, from the bundle itself — so it names
what the artifact actually contains rather than what `package.json` declares. A dependency that is declared
but never imported is not in the file and is not listed; one that arrives as somebody else's transitive
dependency is in it and is. That is some 150 packages and a quarter of a megabyte of notices, which is 2% of
the bundle and 0.3% of an executable.

Each entry carries the package's own license file verbatim, `NOTICE` included where there is one. A package
that ships no license file at all says so in place of the text, rather than quietly dropping out.

An executable additionally contains the Bun runtime it was compiled with, which the header of the output
points at; run from a checkout there is no Bun in the picture and none is claimed.

## Publishing

The executables are published as **GitHub releases of [TouK/nussknacker-cli-dist](https://github.com/TouK/nussknacker-cli-dist)**:
one release per version, tagged with it, the gzipped binaries and their `SHA256SUMS` attached as assets. That
repository holds no code — its front page is this file, and the two installers beside it are the ones the
one-liners fetch. The Nussknacker pipeline pushes into it; nothing there is built there.

Two scripts, one credential:

| script                        | what it does                                                       |
| ----------------------------- | ------------------------------------------------------------------ |
| `scripts/publish-binaries.sh` | creates the release and uploads the assets                         |
| `scripts/publish-repo.sh`     | pushes this README and both installers to that repository's `main` |

The credential is `NU_CLI_GITHUB_TOKEN`, a token with `contents: write` on that repository, as a masked
CI/CD variable here. Releases and the repository's files are the same permission, so one token covers both;
`GH_TOKEN` is read as well, and outside CI `gh auth token` stands in, which is how either script can be run
by hand without a token in the shell history. No token, no publish — and the scripts say which one is
missing rather than failing obscurely.

### Channels, without markers where GitHub has them

| address                                 | what it is                                              |
| --------------------------------------- | ------------------------------------------------------- |
| `releases/latest/download/<file>`       | the newest release; GitHub resolves it, prereleases out |
| `releases/download/<version>/<file>`    | one named build, for `--version`                        |
| `releases/download/snapshot/latest.txt` | which build `--snapshot` takes                          |

A `-SNAPSHOT` version is published as a **prerelease**, which is what keeps it out of `releases/latest` — so
the release channel needs no marker of its own, and the installer resolves it with no API call at all: the
redirect of `releases/latest` carries the tag. The snapshot channel has nothing of the kind, so it gets one
file at a fixed address, a `latest.txt` on a release called `snapshot` that carries nothing else.

**Only a build of master moves that pointer.** A branch build is published under its own version and can be
handed to somebody with `--version <it>`, but the address people are told to use keeps meaning master. The
release channel moves on `production`, where the release job has already rewritten `version.sbt` so the
version carries no suffix.

### Publishing nothing, on purpose

Publishing on every push to master would be a version per commit — 300 MB of assets each — most of them the
same program under a new name, and a pointer that moves without anything having changed. So the job asks
first, and the question is answerable because the build writes **`BUNDLE_ID`**: the sha256 of the esbuild
bundle with the version string taken back out of it, plus Bun's version, since a compiler upgrade changes
the executables without changing a line of ours. It is uploaded with every release, and a publish whose
`BUNDLE_ID` equals the one the channel points at is skipped.

`SHA256SUMS` cannot answer this: it covers the executables, and the version is stamped into each one, so they
differ on every commit whether or not anything else did. What the hash measures is the bundle, so a change
that esbuild eliminates — a comment, or a branch that constant-folding drops — correctly counts as no change
at all.

The skip is not silent: the job says which version the channel still holds, and reports it as
`NU_CLI_PUBLISHED_VERSION`, so `verify-cli-install` checks what is actually installable rather than failing
on the version this pipeline happened to build. `NU_CLI_FORCE_PUBLISH=true` publishes anyway.

### Interrupted half way

A release is created as a **draft**, the assets are uploaded into it, and it is published last. Nothing is
downloadable until everything is there, and an interrupted run leaves a draft rather than a release that
claims to hold files it does not — the next run finds that draft and finishes it.

Which is also why "does this version exist" is asked twice: a draft has no tag, so GitHub's
`releases/tags/<version>` answers only for something published, and that is exactly the question the
republish guard needs. A second publish of a **release** version is refused rather than replacing bytes
people have already downloaded and checksummed (`ALLOW_REPUBLISH=true` overrides it); a snapshot names its
commit, so re-running the same commit legitimately produces the same thing and may replace its assets.

Replacing an asset means deleting it first — GitHub answers `422` rather than overwriting — which a re-run
and a resumed publish both need.

### This file is that repository's front page

There is one document, and you are reading it. `scripts/publish-repo.sh` copies it over with each release, so
whoever arrives for a binary reads what was reviewed in the same MR as the code it describes, and there is no
second copy to keep in step. **Edit it here; an edit made in that repository is overwritten by the next
release.**

That a page for outsiders and a page for whoever maintains the publishing are the same file is deliberate.
Everything here is true of the thing being downloaded, none of it is a secret, and the alternative was two
documents that disagree within a month.

```bash
cd designer/client/packages/cli
NUSSKNACKER_VERSION=1.20.0 scripts/publish-repo.sh      # with gh logged in, or NU_CLI_GITHUB_TOKEN set
```

It compares before it commits, so an unchanged file is left alone and the history over there records when
something actually changed rather than when a release happened. `NU_CLI_REPO_FORCE=true` pushes from a
snapshot build too, for a correction to an installer that should not wait for a release. The clone is one
commit deep and the token goes into the push URL for that one command — not into a config file, and not into
a remote that outlives it.

### The rest of it

Compression is gzip because the installer has to unpack on a machine it knows nothing about: xz would save
another ~8 MB per download, and Debian 12 and Ubuntu 24.04 have nothing that unpacks it — not even GNU
`tar`, which shells out to `xz` and fails without it. Nothing ships zstd either.

A tag becomes resolvable a few seconds after the release is created, not instantly, which is why
`verify-cli-install` retries before concluding that an install is broken.

Old snapshot releases are deleted by hand. There is deliberately no job for it: whatever the two channels
point at has to survive, and publication order does not protect it.

## Development

The package lives in the designer monorepo, at `designer/client/packages/cli`. Link it once and use
`nu-cli` everywhere:

```bash
cd designer/client
npm install
npm run build:cli
cd packages/cli && npm link
```

This is the setup worth having. `nu-cli` prints what it was asked for and nothing else, which matters both
when reading the output and when piping it:

```bash
nu-cli scenario list --json | jq '.data.scenarios[].name'
```

There is also `npm run cli` from `designer/client`, which rebuilds first (about 100 ms) so it can never run
a stale bundle:

```bash
npm run cli -- scenario list --url http://localhost:8080
```

It costs two lines of npm's own `> package@version` banner on stdout, printed before the script even
starts, so nothing inside this package can suppress them — for a pipe, either link the binary or add npm's
`--silent`.

The script is deliberately called `cli` and not `dev`. The monorepo's `npm run dev` fans out to the `dev`
script of every workspace that has one, and that set is the web client's dev servers — long-running
processes started together. A CLI is a one-shot command with no server to keep alive, so it has no place
in that group.

## Talking to a designer

Every `scenario` command needs to know which designer to ask, and as whom. In order of precedence:

| source            | example                                                           |
| ----------------- | ----------------------------------------------------------------- |
| flag              | `nu-cli scenario list --url https://demo.nussknacker.io`          |
| `$NU_URL`         | `NU_URL=https://… nu-cli scenario list`                           |
| `$BACKEND_DOMAIN` | the variable `npm run dev` already uses, so one shell serves both |
| config profile    | `nu-cli scenario list --profile production`                       |
| default           | `http://localhost:8080`                                           |

That comes from `designer.yaml`, which is about a designer and nothing else:

```yaml
profiles:
    default:
        url: "https://demo.nussknacker.io"
        auth:
            type: bearer # bearer | basic | none
            tokenEnv: NU_TOKEN # or `token:` inline, or username/passwordEnv for basic
```

`$NU_TOKEN` overrides whatever is configured, which is what a CI job should use. `nu-cli whoami` says
which instance you are pointed at, who the backend thinks you are, and which files it read.

### Two worlds, two configs

A designer instance and a topic endpoint are different subjects — different hosts, different credentials —
so they get a file each rather than two sections of one. `nu-cli --help` lists the commands the same way.

| world    | file                             | written by         |
| -------- | -------------------------------- | ------------------ |
| designer | `.nussknacker-cli/designer.yaml` | `nu-cli login`     |
| data     | `.nussknacker-cli/data.yaml`     | `nu-cli init-data` |

Each is looked for in the working directory first and in `~/.config/nussknacker-cli/` second, and the two
are **layered**, not chosen between: you are in this directory because you mean to work on this thing, so
what it says wins key by key. The usual split is a checkout that pins the instance and a user file that
holds the credential.

```
./.nussknacker-cli/designer.yaml        # "this repo talks to staging"
~/.config/nussknacker-cli/designer.yaml # "and this is my token"     (0600)
```

`--config <path>` replaces the search for the world the command belongs to.

### Profiles

Every instance lives under a profile, including the one you did not name — that one is called `default`.
There is no second shape for "the usual instance": it is a profile like the others, in the same list.

```yaml
insecureTLS: false # anything out here is a base every profile builds on

profiles:
    default:
        url: "https://staging.example"
        auth: { type: bearer, token: "…" }
    local:
        url: "http://localhost:8080"
        auth: { type: none }
```

`-p, --profile <name>` picks one. Without it you get `default`, or — when the file has no `default` — simply
the first profile in it, so a config holding one instance under some other name works without naming it
every time.

A name that _is_ given and is not in the file is an **error**, not a quiet fall back — a typo should not
point a deploy at a different instance. `nu-cli whoami` prints the profile actually in use.

`login` is the exception, because it is how a profile comes into existence:

```bash
nu-cli login --url https://staging.example -p cloud --browser
```

That writes `profiles.cloud` — the url it was pointed at and the credential it obtained — without touching
any other profile. Every command afterwards reaches it with `-p cloud`.

### Getting a token

Instances that authenticate with OIDC hand the designer a token that lives in `sessionStorage`: scoped to
the designer's own origin, per tab, and gone when the tab closes. **No page the CLI serves can read it** —
that is the same-origin policy, not a missing feature — so every route below ends with code running inside
a designer tab.

**`nu-cli login --browser`** — nothing to install, nothing to restart:

```bash
nu-cli login --browser
```

On an instance that signs in through a federated auth module — `strategy: "Remote"` in
`/api/authentication/{provider}/settings`, which is what the cloud deployments use — the page does what the
designer does when it has no token: it loads that same module, hands it React through the federation share
scope, and lets its `useLogin` hook sign in. The CLI therefore needs to know nothing about the identity
provider, and keeps working when its configuration changes.

This is why the page is served on **`http://test.localhost:4000`**: the provider only redirects back to
origins it was configured with, and that is the one local development already uses. The hostname matters as
much as the port — `http://127.0.0.1:4000` is a different origin and would be refused — so the page is
bound to both loopback addresses, because `test.localhost` resolves to `::1` on some machines and
`127.0.0.1` on others. Override with `--origin` if your setup differs. Stop `npm run dev` first: its proxy
holds that port, and the CLI says so if it is taken.

Everywhere else the same flag serves a page offering a bookmarklet to drag to the bookmarks bar (and the
same line as a snippet, if you would rather paste into DevTools). Click it on your designer tab and the
token comes back. That hand-back is a navigation carrying the token in the URL fragment rather than a
`fetch`, because a fetch from an https page to `http://127.0.0.1` is mixed content and browsers disagree
about it; a fragment never reaches the server anyway.

**`nu-cli login --from-browser`** — no clicking, but Chrome has to be started for it:

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    --remote-debugging-port=9222 --user-data-dir=/tmp/nu-cli-chrome &

# log in to the designer in that window, then:
nu-cli login --from-browser
```

That port is full control of the browser, which is why the separate `--user-data-dir` is worth the trouble.

Either way the token goes into the config and nowhere else — it is never printed. It is checked against
`GET /user` before being stored, so a token that does not work fails here instead of on every command
afterwards.

The remaining ways in:

| flag                  | for                                             |
| --------------------- | ----------------------------------------------- |
| `--token <t>`         | a token you already hold                        |
| `--token-stdin`       | CI, where it comes from a secret store          |
| `--basic-user <name>` | instances that authenticate with basic auth     |
| _(no flag)_           | a hidden prompt, for pasting a token in by hand |

`--basic-user` never takes the password as an argument — that would put it in the shell history and in the
process list. It reads `$NU_PASSWORD`, or asks. A password that came from the environment stays there:
the config records only the variable's name. One typed at the prompt is written to the file unless
`--password-env <VAR>` says otherwise, and the command says so when it does.

`--profile <name>` stores the credential under that profile, so one config can hold several instances.

### Logging out

```bash
nu-cli logout             # the default profile
nu-cli logout -p demo     # one profile
```

This removes the credential from the config and nothing more. The token stays valid on the instance until
it expires — the CLI cannot revoke it, and does not pretend to.

### Where credentials live

In the config files above, in plain text, mode `600`. That is a deliberate trade: no keychain means the same
behaviour on a laptop, in a container and in CI. What it costs is that the file's permissions are the only
thing protecting them, so a config holding a secret that others can read is **refused** with the `chmod`
that fixes it. A config that names no secret is never complained about.

`tokenEnv` / `passwordEnv` keep the secret out of the file entirely, which is what a shared config or a CI
job should use.

Other flags shared by every scenario command: `--json` (machine-readable output on stdout, everything
else on stderr), `--impersonate <user>`, `--insecure`, `--ca <path>`, `--timeout <seconds>`.

Exit codes: `0` ok, `2` bad usage, `3` not authenticated, `4` not found, `5` validation errors,
`6` network or timeout, `1` anything else.

## Picking a scenario

Leave the name out and the command asks which one you meant:

```bash
nu-cli scenario graph
```

```
? Scenario: (Use arrow keys)
❯ Credit Card Fraud Detection (canceled)
  Rating - events generation (running)
  SendMobileNotification [fragment]
```

Past twenty scenarios it asks for a filter first, since scrolling a few hundred entries is no better than
typing the name. The prompt is written to stderr, so redirecting a command's output still captures only its
result.

There is nobody to ask when the output is not going to a terminal, so `--json` and a non-TTY stdin both
turn a missing name into a usage error (exit 2) rather than a prompt that would hang waiting for an answer.
Scripts pass the name; people do not have to.

## Reading a scenario

`nu-cli scenario graph <name>` answers one question: what is the shape of this scenario. Node names, how
they connect, and what each branch is — nothing else, because everything else is noise when you are trying
to see the flow.

```
▷ read game events stream
│
● accept only events that indicate loss in the game
│[true]
● count losses for last 1 hour
│
● call external system for an offer
│
▣ send message with applied offer to kafka topic
```

Indentation only grows at a real branch. A node with one onward successor keeps the same column even when
that edge is named — a Filter with only its `true` branch wired is still a straight line, and indenting at
each one would walk a linear scenario off the right of the screen. A leaf reached only from here is folded
onto the connector line instead of claiming one:

```
▷ Kafka
│
● Credit Card Fraud ML Model
│
◇ is fraud?
├─ [false] ▸ accept transaction
└─ [true] ▸ block transaction
```

A branch that does open an indented block ends in an elbow, so the connector leads into it rather than
stopping short. The branch's name sits beside the elbow, never inside the connector — a long SpEL condition
would otherwise push the whole block it introduces off to the right:

```
◇ split
├─┐
│ ● Detect rapid measurement changes
│ │ [true]
│ ▣ write to alerts topic(1)
└─┐
  ● Detect anomalous measurement changes
  │
  ▣ write to alerts topic(2)
```

The feeds of a Join are branches too, so they are drawn as branches: each one runs down a column of its own
beside the branch you arrived on, and the columns close back into the node.

```
▷ transactions
│
● parse-tx
│
│ ▷ customers
│ │
│ ● parse-cust
├─┘
⇉ enrich
```

A feed that cannot be drawn — because the graph rejoins itself rather than merging two separate sources —
is named under the node instead (`← parse-tx`), since drawing it twice would invent a branch that does not
exist.

The glyph describes the node's place in the flow, not its type: `▷` source, `▣` sink or dead end,
`◇` branch point, `⇉` several inputs, `⇢` a forward reference to a node printed further down, `●`
everything else. When a scenario has validation errors a second column appears, flagging `✖` an error,
`▲` a warning, `⊘` a disabled node; a clean scenario is not indented by a column that says nothing.

Options:

| flag               | what it adds                                                                      |
| ------------------ | --------------------------------------------------------------------------------- |
| `-d, --details`    | each node's component type and main parameter                                     |
| `--counts`         | event counts per node, right-aligned                                              |
| `--format edges`   | `from -> to [label]` lines, plus an id/type/name table — for grepping and diffing |
| `--format mermaid` | a diagram to paste into docs                                                      |
| `--ascii`          | plain ASCII instead of box-drawing characters                                     |
| `--spacing <n>`    | room around the connectors: 1 tight, 2 default, 3 airy — both directions at once  |
| `--width <n>`      | wrap to this width instead of the terminal's                                      |

## Changing a scenario's structure

`scenario set` changes values inside a scenario; these change what it is made of. Every one edits the local
draft, the same one `set` writes, and nothing reaches the server until `scenario save`.

```bash
nu-cli scenario add-node orders builtin-filter --after "read orders" --node-name "big orders only"
nu-cli scenario add-node orders sink-dead-end --after "big orders only" --edge-type FilterFalse
nu-cli scenario insert-node orders builtin-variable --from "read orders" --to "big orders only"
nu-cli scenario replace-node orders "big orders only" builtin-choice
nu-cli scenario connect orders "big orders only" "archive" --edge-type FilterTrue
nu-cli scenario disconnect orders "big orders only" "archive"
nu-cli scenario rm-node orders "archive"
```

Nodes are named by id or by the name the graph shows. A component id is the one the designer's toolbox uses
(`builtin-filter`, `sink-dead-end`, ...); guess it wrong and the answer lists the ones that come close. A new node
is named after its component unless `--node-name` says otherwise, and a name already taken gets a number.

A graph built from here needs arranging before anyone opens it: nodes are placed one under another as they
arrive, so branches land on top of each other, and a graph saved from a file may carry no positions at all.

```bash
nu-cli scenario layout orders              # top to bottom, as the designer reads
nu-cli scenario layout orders --horizontal # left to right
```

That is the designer's own auto-layout — the same algorithm, options and spacing as its Layout button, run here
instead of in the browser — so a scenario an agent built opens looking like one a person arranged.

The rules are the designer's own, run by the same code as the canvas: how many inputs and outputs a node has,
which kinds of edge it offers, what a join does with a branch it gains or loses. An edit the canvas would not
allow is refused with the rule that refused it (exit 5), and the draft stays as it was. Inserting onto an edge
needs only one side to fit - a source inserted that way is connected by its output alone, as on the canvas.

## Serving an AI agent (MCP)

`nu-cli mcp` serves the designer to an AI agent as MCP tools over stdio. They are the designer's own AI tools
under the same names (`list_scenarios`, `get_scenario`, `change_scenario_values`, `get_validation_results`,
...), with one difference that follows from where they run: nothing is "currently opened" in a terminal, so
every scenario tool takes `scenarioName`. Edits land in the same local draft `nu-cli scenario set` writes, so
`nu-cli scenario diff` shows a person what the agent changed before anything is saved.

`list_skills` and `get_skill` hand over the designer's own playbooks — the markdown it publishes beside the app —
so an agent plans a multi-step request the way the designer's assistant would. They are read from the instance,
not from this package, so they are always the ones that instance ships; an instance too old to publish any says
so plainly instead of failing.

Registering it takes one line in Claude Code:

```bash
claude mcp add nussknacker -- nu-cli mcp --profile default
```

and a block of this shape in most other clients (Claude Desktop's `claude_desktop_config.json`, Cursor's
`.cursor/mcp.json`):

```json
{ "mcpServers": { "nussknacker": { "command": "nu-cli", "args": ["mcp", "--profile", "default"] } } }
```

Give `command` the **full path** to the executable if the agent runs where `~/.local/bin` is not on the
`PATH`, which is most GUI applications. Having one file to point at, with no `npx` and no Node to install
first, is what the standalone build is for.

There is nobody on stdio to confirm a call, so what the server may do is decided by the flags it starts with.
A tool that is not allowed is not listed at all:

| flag                    | tools it adds                                                                      |
| ----------------------- | ---------------------------------------------------------------------------------- |
| _(none)_                | reading scenarios, components and validation; editing and discarding the draft     |
| `--allow-write`         | `create_scenario`, `save_scenario`                                                 |
| `--allow-deploy`        | `deploy_scenario`, `cancel_scenario`, `send_message`                               |
| `--dry-run`             | everything, but writes answer with the request they would send, and send none      |
| `--allow-remote-writes` | nothing - lets the two `--allow-*` flags work against a designer that is not local |

The last one is a safety net, not a formality: a production profile left as the default is exactly how an agent
would end up deploying somewhere it should not, so against anything but `localhost` the write flags are refused
until they are asked for twice. `send_message` sends to the topic from `data.yaml`; `--data-profile` picks its
profile.

Every tool that can fail answers with `{ "status": "rejected", "reason": ... }` instead of an error the agent
cannot read, and stdout carries nothing but the protocol.

What the agent did goes to a file, a line per call - `~/.local/state/nussknacker/mcp.log` (under
`$XDG_STATE_HOME` when set), or wherever `--log-file` points. stderr is not used for it: it ends up wherever the
MCP client puts it, which is rarely where a person looks. `tail -f` the file while an agent works:

```
2026-09-14T20:51:03.120Z  --- nu-cli mcp (pid 89022) → https://staging.example (profile default) · write dry run, deploy dry run
2026-09-14T20:51:08.337Z  get_scenario              orders                    ok           93ms
2026-09-14T20:51:09.012Z  deploy_scenario           orders                    dry run       2ms  POST https://staging.example/api/processManagement/deploy/orders
2026-09-14T20:51:09.140Z  get_scenario              missing                   rejected     61ms  Not found (404): /processes/missing
```

Arguments are left out, since a graph runs to tens of kilobytes and a message may carry real data. A
`--dry-run` session logs them, because seeing what an agent would have done is what it is for; `NU_CLI_DEBUG=1`
adds them to any other session.

Calls that change a scenario's draft wait for each other, one scenario at a time: an agent fires calls in
parallel whenever it sees no dependency between them, and two edits of the same draft racing would silently
drop one of them. Reads never wait.

### What the agent gets

| access           | tools                                                                                                                                                                                         |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| read             | `list_scenarios` `get_scenario` `get_scenario_status` `get_validation_results` `get_components` `get_component_definition` `list_configured_services` `list_skills` `get_skill`               |
| draft (default)  | `change_scenario_values` `add_node` `add_node_between` `replace_node` `delete_node` `add_edge` `delete_edge` `apply_scenario_graph` `import_scenario_graph` `run_auto_layout` `discard_draft` |
| `--allow-write`  | `create_scenario` `save_scenario`                                                                                                                                                             |
| `--allow-deploy` | `deploy_scenario` `cancel_scenario` `send_message`                                                                                                                                            |

### If you are an agent setting this up

Run these in order and stop at the first one that fails:

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/TouK/nussknacker-cli-dist/main/install.sh)"
~/.local/bin/nu-cli --version
~/.local/bin/nu-cli whoami            # needs a designer and a token first: `nu-cli login --help`
~/.local/bin/nu-cli scenario list
```

On Windows the first line is `irm …/nussknacker-cli-dist/main/install.ps1 | iex` and the binary lands in
`%LOCALAPPDATA%\Programs\nu-cli\nu-cli.exe`. If the install reports that there is no release yet, say so and
ask before reaching for `-- --snapshot`.

Then register the server with the full path to the binary, since your host process probably does not have
`~/.local/bin` on its `PATH`. Before acting:

- `nu-cli login --browser` needs a human at a browser. Print the command and ask for it; do not try to
  automate a sign-in.
- Start without `--allow-write` and `--allow-deploy`. Draft edits are local and reversible; saving and
  deploying are neither. Ask before requesting either, and say which instance `whoami` reported.
- Prefer the draft loop over one large `apply_scenario_graph`: make the change, call
  `get_validation_results`, and tell the person to run `nu-cli scenario diff <name>` before you save.
- A `{ "status": "rejected" }` answer is the designer refusing, not a transport failure. Read `reason` and
  change the request; retrying it unchanged fails identically.
- Do not write to stdout from a wrapper around `nu-cli mcp` — stdout is the protocol, and one stray line
  breaks the client's framing.
- Anything the tools do not cover exists as a command, and `--json` gives output you can parse.

## Quick start for the data commands

1. **Initialize configuration:**

    ```bash
    nu-cli init-data
    ```

2. **Start consuming messages:**

    ```bash
    nu-cli consume
    ```

    Copy the webhook URL to Nu Cloud subscription.

3. **Start producing messages:**
    ```bash
    nu-cli produce
    ```

## Commands

### `nu-cli init-data`

Sets up the data config — a topic to send messages to. A designer instance is a config of its own, and that
one is `nu-cli login`.

The name says which of the two worlds it sets up; plain `init` reads like it initialises the CLI as a whole,
which is exactly what it does not do. `init` is what this was published as and still works — it is simply
not the name the help advertises.

```bash
nu-cli init-data                    # Interactive mode
nu-cli init-data --no-interactive   # Use template
nu-cli init-data -o myconfig.yaml   # Custom output path
```

**Creates:**

- `.nussknacker-cli/data.yaml` - where messages go
- `message-template.yaml` - Default message template

**Interactive prompts:**

- Nu Cloud API URL
- Username
- Password
- Delay between messages
- Multiple profiles support

### `nu-cli send`

Send a single message to Nu Cloud (manual mode).

```bash
# Using inline JSON/YAML data
nu-cli send --data '{"name": "John", "age": 30}'

# Using a file
nu-cli send --file message.json

# Using a custom template
nu-cli send --template custom-template.yaml

# Dry run
nu-cli send --dry-run

# With specific profile
nu-cli send --profile production --data '{"event": "user_login"}'
```

**Priority:** `--data` > `--file` > `--template` > config template > default template

**Options:**

- `-C, --config <path>` - read this file instead of searching for one
- `-p, --profile <name>` - Config profile to use
- `-d, --data <json>` - Message data as JSON/YAML string
- `-f, --file <path>` - Message data from file (JSON/YAML)
- `-t, --template <path>` - Template file to use (overrides config)
- `--dry-run` - Show what would be sent without sending

### `nu-cli produce`

Send messages to Nu Cloud continuously.

```bash
nu-cli produce                         # Start continuous production
nu-cli produce -c 10                   # Send 10 messages and exit
nu-cli produce -c 1                    # Send single message
nu-cli produce --dry-run               # Preview without sending
nu-cli produce -C custom.yaml          # Use custom config
nu-cli produce --profile production    # Use named profile
nu-cli produce --delay 5               # Override delay (seconds)
nu-cli produce --template custom.yaml  # Use custom template
```

**Options:**

- `-C, --config <path>` - read this file instead of searching for one
- `-p, --profile <name>` - Config profile to use
- `-d, --delay <seconds>` - Delay between messages (overrides config)
- `-t, --template <path>` - Template file to use (overrides config)
- `-c, --count <number>` - Send specified number of messages and exit
- `--dry-run` - Show what would be sent without sending

### `nu-cli consume`

Start webhook consumer with tunnel support.

```bash
# With auto-detected tunnel (cloudflared or tailscale)
nu-cli consume

# With specific tunnel provider
nu-cli consume --tunnel cloudflared
nu-cli consume --tunnel tailscale

# With custom webhook path (tailscale)
nu-cli consume --tunnel tailscale --tunnel-path /my-webhook

# Without tunnel (local only)
nu-cli consume --no-tunnel

# Custom port
nu-cli consume --port 8080

# Debug mode
nu-cli consume --debug

# JSON output mode (for piping)
nu-cli consume --json
nu-cli consume --json | jq '.email'
nu-cli consume --json --no-tunnel > messages.jsonl
```

**Options:**

- `-p, --port <number>` - Server port (default: `6555`)
- `--tunnel <provider>` - Tunnel provider: `cloudflared`, `tailscale`, `none` (default: `auto`)
- `--tunnel-path <path>` - Webhook path for tunnel (tailscale only, default: `/webhook`)
- `--no-tunnel` - Skip tunnel setup
- `--exact-path` - Accept webhooks only on root path `/` (default: wildcard `/*`)
- `--debug` - Enable debug logging
- `--json` - Output raw JSON only (suitable for piping to other tools)

**Tunnel Providers:**

- **cloudflared**: Automatic, requires `cloudflared` installed
- **tailscale**: Requires `tailscale` installed and authenticated
- **auto**: Detects which tool is available (cloudflared first, then tailscale)
- **none**: Local server only (no public URL)

**Webhook Path:**
By default, the consumer accepts webhooks on **any path** (wildcard `/*`). Each message includes the request path in output:

- Normal mode: Shows path with 📍 emoji before each message
- JSON mode: Includes `path` field in output object `{"path": "/webhook", "data": {...}}`

Use `--exact-path` to accept webhooks only on root path `/`:

```bash
nu-cli consume --exact-path
```

With `--exact-path`:

- Only `/` is accepted (other paths return 404)
- Path is not shown in output
- JSON mode outputs just the message data

**JSON Mode:**
The `--json` flag outputs only raw JSON messages (one per line) to stdout, suppressing all other logs.

- Default (wildcard): `{"path": "/webhook", "data": {...}}`
- With `--exact-path`: `{"email": "...", ...}` (just message data)

Perfect for piping to other tools:

```bash
# Filter emails with jq
nu-cli consume --json | jq '.email'

# Save to JSONL file
nu-cli consume --json --no-tunnel > messages.jsonl

# Process with custom script
nu-cli consume --json | while read -r msg; do
  echo "$msg" | jq '.userId' >> user_ids.txt
done
```

Errors are still sent to stderr in JSON format: `{"error": "message"}`

**Install tunnel tools:**

```bash
# Cloudflared
brew install cloudflare/cloudflare/cloudflared

# Tailscale
# Visit https://tailscale.com/download
```

### `nu-cli schema`

Generate Avro schema from message template.

```bash
nu-cli schema                  # Print to stdout
nu-cli schema -o schema.avsc   # Save to file
```

**Options:**

- `-o, --output <path>` - Output file (stdout if not specified)

## Configuration

### Basic config (`.nussknacker-cli/data.yaml`)

```yaml
api:
    url: "https://your-api.cloud.nussknacker.io/topics/your-topic"
    username: "publisher"
    password: "" # Leave empty for endpoints without authentication

producer:
    delay_seconds: 1
    template_path: "./message-template.yaml" # Path to message template (created by init)
```

**Optional Authentication:**  
If your endpoint doesn't require authentication, leave the password empty. If the endpoint requires auth but you provide no password, you'll get a `401` error.

### Multiple profiles

Use profiles to manage different environments (dev/staging/prod):

```yaml
# Default configuration
api:
    url: "https://dev.cloud.nussknacker.io/topics/dev"
    username: "publisher"
    password: "dev_pass"

producer:
    delay_seconds: 1

# Named profiles
profiles:
    production:
        api:
            url: "https://prod.cloud.nussknacker.io/topics/prod"
            password: "prod_pass"

    staging:
        api:
            url: "https://staging.cloud.nussknacker.io/topics/staging"
            password: "staging_pass"
```

**Usage:**

```bash
nu-cli produce --profile production
nu-cli produce --profile staging
```

Profiles are merged with the default configuration, so you only need to specify the values that differ.

## Message Templates

Templates define the structure of generated messages using faker.js for realistic test data.

### Default Template

The CLI includes a default template with faker.js support:

```yaml
name: "::person.fullName"
email: "::internet.email"
age: "::number.int({min:18, max:65})"
timestamp: "current_timestamp"
```

### Custom Templates

Create your own template file:

```yaml
# my-template.yaml
userId: "::string.uuid"
username: "::internet.userName"
company: "::company.name"
location: "::location.city"
price: "::commerce.price({min:10, max:1000})"
status: '::helpers.arrayElement(["active","pending","suspended"])'
```

**Use it:**

```bash
# In .nussknacker-cli/data.yaml
producer:
  template_path: "./my-template.yaml"

# Or via CLI flag
nu-cli produce --template ./my-template.yaml
nu-cli send --template ./my-template.yaml
```

### Faker.js Syntax

Full [faker.js API](https://fakerjs.dev/api/) support using `::` prefix. Parameters are parsed as JSON and spread as `...args` to faker functions.

**Simple calls (no parameters):**

```yaml
name: "::person.fullName"
email: "::internet.email"
company: "::company.name"
address: "::location.streetAddress"
uuid: "::string.uuid"
```

**With parameters (use JSON syntax, wrap in single quotes in YAML):**

```yaml
# Object parameters
age: "::number.int({min:18, max:65})"
price: "::commerce.price({min:10, max:1000})"

# Single argument (array)
event: '::helpers.arrayElement(["login","logout","purchase"])'

# Multiple arguments (array, options object)
tags: '::helpers.arrayElements(["tech","sports","music"], {min:2, max:4})'

# Multiple arguments (coordinates, distance, isMetric)
location: "::location.nearbyGPSCoordinate([52.52, 13.40], 10, true)"
```

**How it works:**

- `::category.method` maps to `faker.category.method()`
- Parameters are parsed as JSON: `({min:18,max:65})` → `fn({min:18, max:65})`
- Supports any faker.js function signature exactly as documented

**Special values:**

- `current_timestamp` → ISO 8601 timestamp

### Advanced Examples

**Complete event template:**

```yaml
# events.yaml
userId: "::string.uuid"
eventType: '::helpers.arrayElement(["login","logout","purchase","click"])'
timestamp: "current_timestamp"
user:
    name: "::person.fullName"
    email: "::internet.email"
    age: "::number.int({min:18, max:65})"
metadata:
    ip: "::internet.ip"
    device: '::helpers.arrayElement(["mobile","desktop","tablet"])'
    browser: '::helpers.arrayElement(["Chrome","Firefox","Safari","Edge"])'
    location: "::location.city"
    coordinates: "::location.nearbyGPSCoordinate([52.52, 13.40], 10, true)"
```

**E-commerce order:**

```yaml
orderId: "::string.uuid"
products: '::helpers.arrayElements(["laptop","phone","tablet","watch","headphones"], {min:1, max:3})'
totalPrice: "::commerce.price({min:50, max:5000})"
status: '::helpers.arrayElement(["pending","processing","shipped","delivered"])'
customer:
    id: "::string.uuid"
    name: "::person.fullName"
    email: "::internet.email"
shippingAddress:
    street: "::location.streetAddress"
    city: "::location.city"
    country: "::location.country"
    zipCode: "::location.zipCode"
createdAt: "current_timestamp"
```

## Examples

### Continuous production with custom delay

```bash
nu-cli produce --delay 3
```

### Single message to production environment

```bash
nu-cli produce --profile production --once
```

### Dry run to test message structure

```bash
nu-cli produce --dry-run --once
{
  "name": "Alice"
}
```

### Generate and save Avro schema

```bash
nu-cli schema -o schema.avsc
```

### Start consumer on custom port without tunnel

```bash
nu-cli consume --port 9000 --no-tunnel
```

## What is where in the sources

```
src/
├── cli.ts              the command tree, grouped the way --help prints it
├── commands/           one file per command; `scenario/` is a directory of its own
├── designer/           everything about talking to a designer:
│   ├── transport/      the client and the endpoint list shared with the designer's own code
│   ├── domain/         what a command means - scenarios, versions, deployments, layout
│   ├── draft/          where an unsaved edit is kept
│   ├── auth/           obtaining and storing a token, including the browser routes
│   ├── graph/          the ASCII drawing of a scenario
│   └── render/         tables and widths
├── mcp/                the MCP server: tool definitions, gating, the call log
├── lib/                the data half - producer, consumer, templates, config
└── utils/              logging, errors, stdout
scripts/                the builds and the publishing; see Publishing above
```

The designer half reads the shell's own types and edit logic through the `@shell/*` alias rather than
copying them, so a change to how the designer edits a scenario is a change to how this does.

## Where things live

|                                             |                                         |
| ------------------------------------------- | --------------------------------------- |
| `~/.local/bin/nu-cli`                       | the executable                          |
| `%LOCALAPPDATA%\Programs\nu-cli\nu-cli.exe` | the same, on Windows                    |
| `./.nussknacker-cli/designer.yaml`          | this directory's designer, layered over |
| `~/.config/nussknacker-cli/designer.yaml`   | your designer profiles and credentials  |
| `~/.config/nussknacker-cli/data.yaml`       | topic endpoints, written by `init-data` |
| `~/.local/state/nussknacker/mcp.log`        | a line per MCP tool call                |

`$XDG_CONFIG_HOME` and `$XDG_STATE_HOME` are honoured where set.

## Troubleshooting

### `could not read …/latest/latest.txt`

Nothing is released yet, so the bare install line has no version to read. Until the first release a
[snapshot](#install) is the only thing to install.

### The installer ran but `nu-cli` is not found

`~/.local/bin` is not on your `PATH` — the installer says so. Add it, or call the binary by its full path.
On Windows, run the installer again with `-AddToPath` and open a new terminal.

### It did not run at all

On Alpine and other musl systems the binary needs libstdc++: `apk add libstdc++`. On macOS, a binary saved
by a _browser_ is quarantined and killed without a message: `xattr -d com.apple.quarantine <file>`, or
install with `curl` as above.

### Windows: `could not replace …\nu-cli.exe`

Windows locks a running executable instead of letting it be replaced. Something still has it open — an MCP
server inside an editor being the usual candidate. Close it and install again.

### "Config file not found"

Run `nu-cli init-data` to create a config file, or specify a custom path with `--config`.

### "Invalid or placeholder password"

Edit your `.nussknacker-cli/data.yaml` and set a real password (not `your_password`).

### "cloudflared not found"

Install cloudflared or use `--no-tunnel` flag:

```bash
nu-cli consume --no-tunnel
```

### Schema validation errors

Generate the correct Avro schema for your message template:

```bash
nu-cli schema
```

Then create a topic in Nu Cloud with this schema.

## Versions

There is one version number, the Nussknacker one. This package is not released on its own and is not
published to npm: `nu-cli -v` reports the version of the build it came from, down to the commit for a
snapshot, so the client and the designer it talks to can be compared. Where those builds come from and how
they reach people is [Publishing](#publishing).

## License

Apache-2.0. `nu-cli --licenses` prints the terms of everything compiled into the build you are running.

## Nussknacker

- [nussknacker.io](https://nussknacker.io) — what Nussknacker is, and who it is for
- [docs.nussknacker.io](https://docs.nussknacker.io) — the documentation: scenarios, components,
  deployment, the REST API this client speaks
- [github.com/TouK/nussknacker](https://github.com/TouK/nussknacker) — the open source distribution: the
  same product, but usually an older and smaller version than the build this client comes from, so what it
  documents and what an instance here does can differ

---

This document is written in the Nussknacker repository, at `designer/client/packages/cli/README.md`, and
published from there as the front page of the downloads project with each release. An edit made in that
project is overwritten by the next one.
