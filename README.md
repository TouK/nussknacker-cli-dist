# Nussknacker CLI

**nu-cli** is the command line client for [Nussknacker](https://nussknacker.io) — the web application
scenarios are built in, documented at [docs.nussknacker.io](https://docs.nussknacker.io). One file with its
runtime inside it, so there is no npm and no Node to install first.

It holds **two unrelated tools** under one name. They talk to different machines, use different credentials
and have a config file each; nothing carries over from one to the other, and `nu-cli --help` lists them
apart for the same reason.

**[Scenarios and deployments](#scenarios-and-deployments)** — a [Designer](https://docs.nussknacker.io/about/GLOSSARY/#designer) instance: what is on it, what the [scenarios](https://docs.nussknacker.io/about/GLOSSARY/#scenario) do, changing and deploying them. Also what an AI agent gets, since [the MCP server](#serving-an-ai-agent-mcp) serves this half.

```bash
nu-cli login --url https://your-designer.example --token-stdin < token.txt   # once, with a Nussknacker API token
nu-cli scenario list                                         # what is on this instance
nu-cli scenario graph fraud-detection                        # what that scenario actually does
nu-cli scenario validate fraud-detection                     # why it will not deploy
```

**[Data in and out of a running scenario](#data-in-and-out-of-a-running-scenario)** — a topic endpoint:
messages pushed into a scenario, and whatever it emits.

```bash
nu-cli init-data                                             # once
nu-cli send                                                  # push one message through
nu-cli consume                                               # watch what comes out
```

## Install

One executable per platform, the runtime inside it, nothing else to install:

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/TouK/nussknacker-cli-dist/main/install.sh)"
```

It picks the file for this machine, checks it against the published `SHA256SUMS`, asks where to put it and
installs `~/.local/bin/nu-cli`. At a terminal it asks before downloading and lets the path be edited; in a
pipe or a CI job it asks nothing.

|                   |                                                      |
| ----------------- | ---------------------------------------------------- |
| `--snapshot`      | the newest snapshot of master instead of a release   |
| `--version <v>`   | that exact version                                   |
| `--prefix <dir>`  | directory to install into, instead of `~/.local/bin` |
| `--target <name>` | a platform other than the detected one               |
| `-y`, `--yes`     | take the defaults and ask nothing                    |

Flags go after a `--`, which stands in for the name a shell expects first — without it they are swallowed:

```bash
sh -c "$(curl -fsSL …/install.sh)" -- --snapshot
curl -fsSL …/install.sh | sh -s -- --snapshot     # the same, through a pipe
```

A release is what the bare command installs, however many snapshots came after it. `--snapshot` follows
master; builds published from a branch are installed by name with `--version`.

### Windows

```powershell
irm https://raw.githubusercontent.com/TouK/nussknacker-cli-dist/main/install.ps1 | iex
```

Installs `%LOCALAPPDATA%\Programs\nu-cli\nu-cli.exe` and asks the same questions. Flags need the scriptblock
form, since `iex` on a string has nowhere to put them, and `-AddToPath` is the one worth knowing — without
it the command is only there by its full path:

```powershell
& ([scriptblock]::Create((irm …/install.ps1))) -Snapshot -AddToPath
```

Under WSL or Git Bash use `install.sh` instead: those want the Linux binary.

### Updating

An installed `nu-cli` replaces itself:

```bash
nu-cli update            # to the newest release
nu-cli update --check    # only say whether there is one; exit code 1 when there is
```

It does what the installer does — the file for this machine, checked against the published `SHA256SUMS` —
and puts it where the running executable is, whatever that was called and wherever it was put. At a
terminal it asks before downloading; in a pipe or a CI job it does not.

|                 |                                                    |
| --------------- | -------------------------------------------------- |
| `--snapshot`    | the newest snapshot of master instead of a release |
| `--version <v>` | that exact version, newer or not                   |
| `--check`       | compare and report, change nothing                 |
| `-y`, `--yes`   | do not ask                                         |

Nothing is done when the channel holds what is already installed, or something older — `--version` is the
way to go back on purpose. The replacement is a rename, so a `nu-cli` running elsewhere — an MCP server in
an editor — keeps its old file until it exits and gets the new one when it starts again. Windows will not
let a running executable go: there the old one is set aside as `nu-cli.exe.old` and removed on the next
start.

Only the installed executable can do this. From a checkout, `nu-cli update` says so and stops: that is
updated with `git pull` and a build.

### By hand

From the [releases page](https://github.com/TouK/nussknacker-cli-dist/releases), or:

```bash
dist=https://github.com/TouK/nussknacker-cli-dist/releases
curl -fsSLO $dist/latest/download/nu-cli-linux-x64.gz          # or /download/<version>/… for one build
curl -fsSL  $dist/latest/download/SHA256SUMS -o SHA256SUMS
sha256sum -c SHA256SUMS --ignore-missing
gunzip nu-cli-linux-x64.gz && chmod +x nu-cli-linux-x64
```

| file                      | for                                                             |
| ------------------------- | --------------------------------------------------------------- |
| `nu-cli-linux-x64`        | most Linux machines and CI runners (glibc)                      |
| `nu-cli-linux-arm64`      | arm64 Linux (glibc)                                             |
| `nu-cli-linux-x64-musl`   | Alpine and other musl distributions — needs `apk add libstdc++` |
| `nu-cli-linux-arm64-musl` | arm64 Alpine — same                                             |
| `nu-cli-darwin-arm64`     | Apple silicon                                                   |
| `nu-cli-darwin-x64`       | Intel Macs                                                      |
| `nu-cli-windows-x64.exe`  | Windows                                                         |

macOS kills a binary a _browser_ downloaded, silently — `xattr -d com.apple.quarantine <file>` clears it,
and fetching with `curl` avoids it. This is also the file to point an agent's MCP config at: see
[Serving an AI agent (MCP)](#serving-an-ai-agent-mcp).

### Shell completion

The same command in bash, zsh, fish and PowerShell, then a new shell:

```sh
nu-cli completion install
```

It tells which shell it is run from and adds the line that loads the completion to that shell's startup file
(`~/.bashrc`, `~/.zshrc`, `~/.config/fish/config.fish`, `$PROFILE`; on macOS bash reads `~/.bash_profile`),
printing the line and the file. Run again, it finds the line there and changes nothing.
`nu-cli completion install zsh` names the shell when it is not the one the command runs in.

TAB then completes commands, their options, and the values the CLI can know without asking a designer: the
profiles in `designer.yaml` after `-p`, the shells after `completion`, a `--format`. Scenario names are
not among them — they live on the instance, and a TAB should not wait on the network. A path option hands
over to the shell's own file completion.

The script the line loads is a few lines that never change: on every TAB it asks the binary on the `PATH` what
fits, so the answer is always that of the build installed, and nothing needs regenerating after an upgrade.

## Scenarios and deployments

_A Nussknacker Designer: what is on it, what the scenarios do, and changing them. Configured by
`nu-cli login`, in `designer.yaml`._

### Talking to a Designer

Every `scenario` command needs to know which Designer to ask, and as whom. In order of precedence:

| source            | example                                                           |
| ----------------- | ----------------------------------------------------------------- |
| flag              | `nu-cli scenario list --url https://demo.nussknacker.io`          |
| `$NU_URL`         | `NU_URL=https://… nu-cli scenario list`                           |
| `$BACKEND_DOMAIN` | the variable `npm run dev` already uses, so one shell serves both |
| config profile    | `nu-cli scenario list --profile production`                       |
| default           | `http://localhost:8080`                                           |

That comes from `designer.yaml`, which is about a Designer and nothing else:

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

#### Where the config is

| half     | file                             | written by         |
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

#### Profiles

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

One profile is there without being written down: `demo`, the public instance at
`https://demo.nussknacker.io`, which lets anyone in anonymously — `nu-cli scenario list -p demo` works before
you have logged in anywhere. It is only ever used when named: without `-p` the choice is made among the
file's profiles alone, so a machine with no config still talks to `http://localhost:8080` rather than to the
demo. A `demo` profile in the file is layered over the built-in one, so it can change the url or add a
credential.

A name that _is_ given and is not in the file is an **error**, not a quiet fall back — a typo should not
point a deploy at a different instance. `nu-cli whoami` prints the profile actually in use.

`login` is the exception, because it is how a profile comes into existence:

```bash
nu-cli login --url https://staging.example -p cloud --token-stdin < token.txt
```

That writes `profiles.cloud` — the url it was pointed at and the credential it obtained — without touching
any other profile. Every command afterwards reaches it with `-p cloud`.

`nu-cli profile list` shows what the files add up to:

```
$ nu-cli profile list
   NAME     URL                          AUTH                      FILE
*  default  https://staging.example      bearer                    user+project
   cloud    https://cloud.example        bearer $CLOUD_TOKEN       user
   legacy   https://legacy.example       basic alice $NU_PASSWORD  user
   local    http://localhost:8080        none                      project
   demo     https://demo.nussknacker.io  none                      built-in

user     /home/you/.config/nussknacker-cli/designer.yaml
project  /home/you/work/thing/.nussknacker-cli/designer.yaml
```

`*` marks the profile a command run from here would use — with `-p`, the one named, so `-p cloud` moves the
mark and a typo fails the same way it fails every other command. `FILE` says which of the two files defines
the profile, or `built-in` for `demo` when no file mentions it; one in both is layered like everything else,
project over user, and that is the profile shown.
A credential is reported by kind and, when the file names an environment variable, by that variable —
never by its value. `--json` prints the same as data; `--config` lists that one file instead.

#### Getting a token

The credential to prefer is a **Nussknacker API token**: a `nuk_...` string shown once when issued, scoped by
RBAC roles, with an expiry, and revocable in the Designer under Administration > Access control. Where it comes
from depends on how you sign in to that Designer:

- a **local user** (an instance with its own user list) issues their own under Access control > API tokens;
- a user signing in through **OIDC** cannot have personal tokens (their permissions come with each sign-in), so
  ask an administrator for a token of a **service account** with the roles you need - that is the way for CI jobs
  and for using the CLI by hand alike;
- without either, log in with the browser session described below.

Hand it to the CLI without putting it in the shell history, and name the Designer it is for - without `--url`
`login` writes the credential into whatever instance the profile names (or `localhost:8080`):

```bash
nu-cli login --url https://your-designer.example                            # a hidden prompt to paste it into
nu-cli login --url https://your-designer.example --token-stdin < token.txt  # from a file, or: pbpaste | nu-cli login ... --token-stdin
```

`--token-stdin` reads the whole input, so it needs a redirection or a pipe; pasting at a terminal and pressing
Enter leaves it waiting (and the token on screen) - that is what the flagless prompt is for. `nu-cli login
--token <t>` takes it as an argument, which is fine in a script that already holds it. In CI set `$NU_URL` and
`$NU_TOKEN` instead and skip `login` altogether.

**Second choice: a browser session.** Instances that authenticate with OIDC hand the Designer a session
token that lives in `sessionStorage`: scoped to the Designer's own origin, per tab, gone when the tab closes,
and tied to your own account. **No page the CLI serves can read it** — that is the same-origin policy, not a
missing feature — so every route below ends with code running inside a Designer tab.

**`nu-cli login --browser`** — nothing to install, nothing to restart:

```bash
nu-cli login --browser
```

On an instance that signs in through a federated auth module — `strategy: "Remote"` in
`/api/authentication/{provider}/settings`, which is what the cloud deployments use — the page does what the
Designer does when it has no token: it loads that same module, hands it React through the federation share
scope, and lets its `useLogin` hook sign in. The CLI therefore needs to know nothing about the identity
provider, and keeps working when its configuration changes.

This is why the page is served on **`http://test.localhost:4000`**: the provider only redirects back to
origins it was configured with, and that is the one local development already uses. The hostname matters as
much as the port — `http://127.0.0.1:4000` is a different origin and would be refused — so the page is
bound to both loopback addresses, because `test.localhost` resolves to `::1` on some machines and
`127.0.0.1` on others. Override with `--origin` if your setup differs. Stop `npm run dev` first: its proxy
holds that port, and the CLI says so if it is taken.

Everywhere else the same flag serves a page offering a bookmarklet to drag to the bookmarks bar (and the
same line as a snippet, if you would rather paste into DevTools). Click it on your Designer tab and the
token comes back. That hand-back is a navigation carrying the token in the URL fragment rather than a
`fetch`, because a fetch from an https page to `http://127.0.0.1` is mixed content and browsers disagree
about it; a fragment never reaches the server anyway.

**`nu-cli login --from-browser`** — no clicking, but Chrome has to be started for it:

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    --remote-debugging-port=9222 --user-data-dir=/tmp/nu-cli-chrome &

# log in to the Designer in that window, then:
nu-cli login --from-browser
```

That port is full control of the browser, which is why the separate `--user-data-dir` is worth the trouble.

Either way the token goes into the config and nowhere else — it is never printed. It is checked against
`GET /user` before being stored, so a token that does not work fails here instead of on every command
afterwards.

All the ways in, preferred first:

| flag                  | for                                                      |
| --------------------- | -------------------------------------------------------- |
| `--token-stdin`       | a Nussknacker API token from a file, the clipboard or CI |
| _(no flag)_           | a hidden prompt, for pasting a Nussknacker API token in  |
| `--token <t>`         | a token you already hold in a script                     |
| `--browser`           | the session token of a Designer tab, with a click there  |
| `--from-browser`      | the session token, read from a Chrome with DevTools open |
| `--basic-user <name>` | instances that authenticate with basic auth              |

`--basic-user` never takes the password as an argument — that would put it in the shell history and in the
process list. It reads `$NU_PASSWORD`, or asks. A password that came from the environment stays there:
the config records only the variable's name. One typed at the prompt is written to the file unless
`--password-env <VAR>` says otherwise, and the command says so when it does.

`--profile <name>` stores the credential under that profile, so one config can hold several instances.

#### Logging out

```bash
nu-cli logout             # the default profile
nu-cli logout -p demo     # one profile
```

This removes the credential from the config and nothing more. The token stays valid on the instance until
it expires — the CLI cannot revoke it, and does not pretend to.

#### Where credentials live

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

### Picking a scenario

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

### Reading a scenario

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
| `--live`           | the live counts of the running scenario instead (see below)                       |
| `--format edges`   | `from -> to [label]` lines, plus an id/type/name table — for grepping and diffing |
| `--format mermaid` | a diagram to paste into docs                                                      |
| `--ascii`          | plain ASCII instead of box-drawing characters                                     |
| `--spacing <n>`    | room around the connectors: 1 tight, 2 default, 3 airy — both directions at once  |
| `--width <n>`      | wrap to this width instead of the terminal's                                      |

### Deploying

```bash
nu-cli deploy orders --wait          # deploy the saved version and wait until it runs or fails
nu-cli redeploy orders --wait 300    # replace the running version, waiting up to 300 seconds
nu-cli cancel orders --wait
```

Deploying is asynchronous: without `--wait` the command returns as soon as the Designer accepts the request, and
`nu-cli status` shows where it got to. `--wait [seconds]` (default 120) reads the state until the engine is done.
RUNNING counts only once it has held for 15 seconds, because a job that fails and restarts passes through RUNNING
on every attempt. The exit code is non-zero when the scenario ends up in PROBLEM or RESTARTING, or is still on its
way when the time runs out. `cancel --wait` waits until each scenario has stopped.

### Watching a running scenario

`nu-cli live <name>` shows what a deployed scenario processes right now: events and errors per node,
traffic per edge, the latest records that went along each edge, and recent exceptions.

```
orders  live  10:00:10

NODE    EVENTS  ERRORS
source     120       0
filter     120       2

EDGE             TOTAL  PER SEC  SAMPLES
source → filter    120     2.50        2
filter → (end)      80     1.67        1

exceptions (1)
  10:00:05  filter  java.lang.NullPointerException: amount is null
```

An edge ending in `(end)` holds the records that stopped in its node — a sink, or a filter that dropped
them. The records themselves are long, so they are printed only with `--node`, which also narrows
everything else to the edges touching that node; `--json` always carries them.

The runtime sends sample records only while someone reads them, so the first read of a scenario nobody
watches usually has counts alone. The command waits a few seconds for the records before answering.

| flag                    | what it does                                                       |
| ----------------------- | ------------------------------------------------------------------ |
| `-n, --node <id>`       | only that node's counts, edges and exceptions, with sample records |
| `--samples <n>`         | records kept per edge (default 3)                                  |
| `--wait <seconds>`      | how long to wait for the records (default 5; 0 answers at once)    |
| `-w, --watch [seconds]` | read again every few seconds (default 2) until interrupted         |

The scenario has to be running, its engine has to collect live data, and the user needs the right to view it;
otherwise the command says which of these is missing.

### Creating a scenario

```bash
nu-cli scenario create orders
nu-cli scenario create pricing --mode Request-Response --engine "Embedded"
nu-cli scenario create fare --fragment --mode Request-Response
```

The new scenario is empty; its graph comes from `scenario add-node` and the commands below, or from
`scenario save --file`. An instance accepts only certain combinations of category, processing mode and engine, so
the flags are matched against them: leave out whatever the instance has one choice for, and an ambiguous or unknown
combination is answered with the ones it offers.

`--fragment` creates a fragment: a piece of flow other scenarios use as a single node. It starts with a fragment
input (`builtin-input`), whose parameters become the parameters of that node, and ends in fragment outputs
(`builtin-output`), each one an outgoing edge of that node. Only scenarios with the fragment's own category,
processing mode and engine can use it, so create it with theirs.

### Changing a scenario's structure

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

Nodes are named by id or by the name the graph shows. A component id is the one the Designer's toolbox uses
(`builtin-filter`, `sink-dead-end`, ...); guess it wrong and the answer lists the ones that come close. A new node
is named after its component unless `--node-name` says otherwise, and a name already taken gets a number.

A graph built from here needs arranging before anyone opens it: nodes are placed one under another as they
arrive, so branches land on top of each other, and a graph saved from a file may carry no positions at all.

```bash
nu-cli scenario layout orders              # top to bottom, as the Designer reads
nu-cli scenario layout orders --horizontal # left to right
```

That is the Designer's own auto-layout — the same algorithm, options and spacing as its Layout button, run here
instead of in the browser — so a scenario an agent built opens looking like one a person arranged.

The rules are the Designer's own, run by the same code as the canvas: how many inputs and outputs a node has,
which kinds of edge it offers, what a join does with a branch it gains or loses. An edit the canvas would not
allow is refused with the rule that refused it (exit 5), and the draft stays as it was. Inserting onto an edge
needs only one side to fit - a source inserted that way is connected by its output alone, as on the canvas.

### Archiving and deleting

```bash
nu-cli scenario archive orders old-orders-copy
nu-cli scenario list --archived
nu-cli scenario unarchive orders
nu-cli scenario delete old-orders-copy
```

Archiving takes a scenario out of the lists and out of reach of edits and deployments; unarchiving brings it back
whole. A running scenario cannot be archived - `nu-cli cancel` it first. These commands, `nu-cli cancel` and
`nu-cli status` take any number of names and go through them one by one: one scenario failing does not stop the
others, and the exit code says whether all of them went.

`delete` removes scenarios for good, with every version and their history. Whatever is not archived yet is archived
first, so a running scenario is refused here too. Every name is looked up before anything is deleted, and in a
terminal you are asked to confirm the list each time, with "no" as the default. Without a terminal, or with
`--json`, the command refuses unless `--yes` is given.

### Kafka topics

On a Designer with the topics extension (the one behind its Topics tab), `topic` manages its Kafka topics and
their schemas:

```bash
nu-cli topic list
nu-cli topic get orders
nu-cli topic preview orders                          # the latest messages, at most 30
nu-cli topic create orders --schema-file orders.schema.json
nu-cli topic create orders --schema '{"type":"object"}' --if-exists update
cat orders.avsc | nu-cli topic create orders --schema-type AVRO --schema-file -
nu-cli topic create                                  # a random name, no schema
nu-cli topic update orders --retention 72            # the schema stays as it is
nu-cli topic update orders --schema-file v2.json     # registered as a new schema version
nu-cli topic update orders --remove-schema
nu-cli topic apply --dir contracts/topics            # one topic per <name>.schema.json
nu-cli topic delete orders                           # asks first, --yes where nobody can be asked
```

`create` is safe to repeat. A topic that already has the given settings is left alone (`unchanged`), and
`--if-exists` decides what happens to one that differs: `fail` (the default), `skip`, or `update`. Schemas are
compared by content, so a schema the registry handed back with its keys reordered still matches.

`delete` removes a topic for good, with every message on it and its schema. Like `scenario delete`, it looks the
topic up first and asks every time, with "no" as the default; without a terminal, or with `--json`, it refuses
unless `--yes` is given.

`update` changes only what it is given. The schema stays unless a new one is passed or `--remove-schema` asks for
its deletion.

`apply` runs `create --if-exists update` for every `<name>.schema.json` file in a directory (`--suffix` changes
the ending, `--schema-type` and `--retention` apply to all of them) and prints what happened to each. Topics
without a file are left alone, so nothing is ever deleted. It exits non-zero when any file failed.

These commands run the same tool definitions as the agent tools of the same names, below.

### Serving an AI agent (MCP)

`nu-cli mcp` serves the Designer to an AI agent as MCP tools over stdio. They are the Designer's own AI tools
under the same names (`list_scenarios`, `get_scenario`, `change_scenario_values`, `get_validation_results`,
...), with one difference that follows from where they run: nothing is "currently opened" in a terminal, so
every scenario tool takes `scenarioName`. Edits land in the same local draft `nu-cli scenario set` writes, so
`nu-cli scenario diff` shows a person what the agent changed before anything is saved.

`get_instance_info` says which instance the agent talks to, as whom, and whether it is Nu Cloud or self-managed: on
Nu Cloud, users and the instance are administered in the tenant manager (the user menu's "Admin"), on a self-managed
one by the installation's own admins, so the agent can point the user to the right place. `nu-cli whoami` prints the
same.

`list_skills` and `get_skill` hand over the Designer's own playbooks — the markdown it publishes beside the app —
so an agent plans a multi-step request the way the Designer's assistant would. They are read from the instance,
not from this package, so they are always the ones that instance ships; an instance too old to publish any says
so plainly instead of failing.

`create_scenario` with `isFragment: true` creates a fragment, as `nu-cli scenario create --fragment` does, and its
description tells the agent how a fragment's input and outputs work.

The agent's client starts the server and talks to it over stdin and stdout, so it is registered there rather
than run. Run `nu-cli mcp` in a terminal and it prints what to register instead of serving: a server for every
profile in `designer.yaml`, with the full path to this executable and any other flag given on that line.
`nu-cli mcp -p staging --allow-write` prints that one server. The output looks like this:

```
Claude Code:

  claude mcp add nussknacker-local -- /Users/me/.local/bin/nu-cli mcp -p local
  claude mcp add nussknacker-staging -- /Users/me/.local/bin/nu-cli mcp -p staging

clients configured with JSON (Claude Desktop, Cursor, ...):

  {
    "mcpServers": {
      "nussknacker-local": { "command": "/Users/me/.local/bin/nu-cli", "args": ["mcp", "-p", "local"] },
      "nussknacker-staging": { "command": "/Users/me/.local/bin/nu-cli", "args": ["mcp", "-p", "staging"] }
    }
  }
```

One server serves one Designer, and what it may do there is set by its own flags - so an agent may save on a
local Designer and only read staging, as two servers with two sets of flags. The profile in the name is what
tells them apart in the client.

`command` is the **full path** to the executable because most GUI clients do not have `~/.local/bin` on their
`PATH`. Having one file to point at, with no `npx` and no Node to install first, is what the standalone build
is for. A client reads its servers when it starts, so restart or reload it after adding one.

There is nobody on stdio to confirm a call, so what the server may do is decided by the flags it starts with.
A tool that is not allowed is not listed at all:

| flag             | tools it adds                                                                                                  |
| ---------------- | -------------------------------------------------------------------------------------------------------------- |
| _(none)_         | reading scenarios, components and validation; editing and discarding the draft                                 |
| `--allow-write`  | `create_scenario`, `save_scenario`, `archive_scenarios`, `unarchive_scenarios`, `create_topic`, `update_topic` |
| `--allow-deploy` | `deploy_scenario`, `redeploy_scenario`, `cancel_scenarios`, `send_message`                                     |
| `--allow-delete` | `delete_scenarios`, `delete_topic`                                                                             |
| `--dry-run`      | everything, but writes answer with the request they would send, and send none                                  |

Deleting is the one exception to "the flags decide". `delete_scenarios` takes a whole list, so an agent can clean
up in one call, and every call asks the person behind the client to confirm. The question goes out as an MCP
elicitation: the client shows the list of scenarios and asks for a phrase, `delete <name>` for one or
`delete <N> scenarios` for several. The tool's description tells the agent to put that phrase in the chat
beforehand, ready to paste. `delete_topic` asks the same way, for one topic and the phrase `delete <name>`.
Declining, or typing anything else, deletes nothing. A client that does not support
elicitation cannot delete at all; nothing skips the question.

The flags mean the same on any Designer, local or not: whether an agent may change one is decided by which
server it is registered under. `send_message` sends to the topic from `data.yaml`; `--data-profile` picks its
profile.

A graph that already sits in a file does not have to pass through the agent's context: `apply_scenario_graph`
takes `file` instead of `nodes`, `edges` and `properties`, a `.json` file inside `~/.local/state/nussknacker/graphs`
(under `$XDG_STATE_HOME` when set, created when the server starts). The agent copies the file there and passes its
name. Nothing outside that directory is read, symlinks included; `--files-dir` points the server at another one.

Every tool that can fail answers with `{ "status": "rejected", "reason": ... }` instead of an error the agent
cannot read, and stdout carries nothing but the protocol. The tools that take `scenarioNames` - archiving,
deleting, cancelling and reading statuses - answer per scenario instead, `{ name, ok: true }` or
`{ name, ok: false, reason }`, so one scenario failing does not hide what happened to the others.

What the agent did goes to a file, a line per call - `~/.local/state/nussknacker/mcp.log` (under
`$XDG_STATE_HOME` when set), or wherever `--log-file` points. stderr is not used for it: it ends up wherever the
MCP client puts it, which is rarely where a person looks. `tail -f` the file while an agent works:

```
2026-09-14T20:51:03.120Z  --- nu-cli mcp (pid 89022) → https://staging.example (profile default) · write dry run, deploy dry run, delete dry run
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

#### What the agent gets

| access           | tools                                                                                                                                                                                                                                                                                                                          |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| read             | `list_scenarios` `get_scenario` `get_scenario_statuses` `get_scenario_diagnostics` `wait_for_scenario_status` `get_live_data` `get_validation_results` `get_components` `get_component_definition` `list_configured_services` `get_instance_info` `list_skills` `get_skill` `list_topics` `get_topic` `preview_topic_messages` |
| draft (default)  | `change_scenario_values` `change_scenario_labels` `add_node` `add_node_between` `replace_node` `delete_node` `add_edge` `delete_edge` `apply_scenario_graph` `run_auto_layout` `discard_draft`                                                                                                                                 |
| `--allow-write`  | `create_scenario` `save_scenario` `archive_scenarios` `unarchive_scenarios` `create_topic` `update_topic`                                                                                                                                                                                                                      |
| `--allow-deploy` | `deploy_scenario` `redeploy_scenario` `cancel_scenarios` `send_message`                                                                                                                                                                                                                                                        |
| `--allow-delete` | `delete_scenarios` `delete_topic` - each call confirmed by the person, see above                                                                                                                                                                                                                                               |

#### If you are an agent setting this up

Run these in order and stop at the first one that fails:

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/TouK/nussknacker-cli-dist/main/install.sh)"
~/.local/bin/nu-cli --version
~/.local/bin/nu-cli whoami            # needs a Designer and a Nussknacker API token first: `nu-cli login --help`
~/.local/bin/nu-cli scenario list
```

On Windows the first line is `irm …/nussknacker-cli-dist/main/install.ps1 | iex` and the binary lands in
`%LOCALAPPDATA%\Programs\nu-cli\nu-cli.exe`. If the install reports that there is no release yet, say so and
ask before reaching for `-- --snapshot`.

Then register the servers. Your shell is not a terminal, so a bare `nu-cli mcp` would start serving instead of
printing what to register: read `nu-cli mcp --help`, which ends with the lines to use and this executable's full
path in them, and `nu-cli profile list` for the profiles to fill in. Before acting:

- Register one server per profile the person wants to use, named `nussknacker-<profile>`, each with
  `-p <profile>`. Ask which ones; a profile pointing at production is not one to add unasked.
- Before creating or modifying a scenario, call the MCP tool `list_skills`, then `get_skill` with the
  exact names of relevant skills. Start with `get_skill({"name":"scenario-authoring"})` if it is listed.
  These are MCP calls, not shell commands; if the instance serves no skills, continue without them.
- Logging in takes a Nussknacker API token: ask the person for one (their own under Administration > Access
  control for a local user; a service account's from an administrator on an instance with OIDC sign-in) and
  pass it with `nu-cli login --url <designer> --token-stdin < file`; never print or store it yourself. The
  fallback `nu-cli login --browser` needs a human at a browser: print the command and ask for it, do not try
  to automate a sign-in.
- Start without `--allow-write`, `--allow-deploy` and `--allow-delete`. Draft edits are local and reversible;
  saving, deploying and deleting are not. Ask before requesting any of them, for each server separately, and
  say which instance it points at.
- Tell the person to restart or reload the client: it reads its servers when it starts.
- Prefer the draft loop over one large `apply_scenario_graph`: make the change, call
  `get_validation_results`, and tell the person to run `nu-cli scenario diff <name>` before you save.
- A `{ "status": "rejected" }` answer is the Designer refusing, not a transport failure. Read `reason` and
  change the request; retrying it unchanged fails identically.
- Do not write to stdout from a wrapper around `nu-cli mcp` — stdout is the protocol, and one stray line
  breaks the client's framing.
- Anything the tools do not cover exists as a command, and `--json` gives output you can parse.

## Data in and out of a running scenario

_A topic endpoint: messages pushed into a scenario and whatever comes out the other side. A different
host and a different credential from the half above, configured by `nu-cli init-data`, in `data.yaml` -
the two share nothing but the binary._

### Quick start

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

### The commands

#### `nu-cli init-data`

Sets up the data config — a topic to send messages to. A Designer instance is a config of its own, and that
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

#### `nu-cli send`

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

#### `nu-cli produce`

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

#### `nu-cli consume`

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

#### `nu-cli schema`

Generate Avro schema from message template.

```bash
nu-cli schema                  # Print to stdout
nu-cli schema -o schema.avsc   # Save to file
```

**Options:**

- `-o, --output <path>` - Output file (stdout if not specified)

### Configuration

#### Basic config (`.nussknacker-cli/data.yaml`)

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

#### Multiple profiles

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

### Message templates

Templates define the structure of generated messages using faker.js for realistic test data.

#### Default Template

The CLI includes a default template with faker.js support:

```yaml
name: "::person.fullName"
email: "::internet.email"
age: "::number.int({min:18, max:65})"
timestamp: "current_timestamp"
```

#### Custom Templates

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

#### Faker.js Syntax

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

#### Advanced Examples

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

### Examples

#### Continuous production with custom delay

```bash
nu-cli produce --delay 3
```

#### Single message to production environment

```bash
nu-cli produce --profile production --once
```

#### Dry run to test message structure

```bash
nu-cli produce --dry-run --once
{
  "name": "Alice"
}
```

#### Generate and save Avro schema

```bash
nu-cli schema -o schema.avsc
```

#### Start consumer on custom port without tunnel

```bash
nu-cli consume --port 9000 --no-tunnel
```

## Where things live

|                                             |                                         |
| ------------------------------------------- | --------------------------------------- |
| `~/.local/bin/nu-cli`                       | the executable                          |
| `%LOCALAPPDATA%\Programs\nu-cli\nu-cli.exe` | the same, on Windows                    |
| `./.nussknacker-cli/designer.yaml`          | this directory's Designer, layered over |
| `~/.config/nussknacker-cli/designer.yaml`   | your Designer profiles and credentials  |
| `~/.config/nussknacker-cli/data.yaml`       | topic endpoints, written by `init-data` |
| `~/.local/state/nussknacker/mcp.log`        | a line per MCP tool call                |

`$XDG_CONFIG_HOME` and `$XDG_STATE_HOME` are honoured where set.

## Troubleshooting

### "Nothing has been released yet"

Until the first release, `--snapshot` is the only thing to install.

### `nu-cli` is not found after installing

Its directory is not on your `PATH`. The installer prints the line that adds it; on Windows, run it again
with `-AddToPath` and open a new terminal.

### It did not run at all

On Alpine and other musl systems the binary needs libstdc++: `apk add libstdc++`. On macOS, a binary saved
by a _browser_ is quarantined and killed without a message: `xattr -d com.apple.quarantine <file>`.

### Windows: `could not replace …\nu-cli.exe`

Windows locks a running executable. Close whatever has it open — an MCP server inside an editor is the
usual one — and install again.

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

There is one version number, the Nussknacker one — this client is not released on its own. `nu-cli -v`
reports the build it came from, down to the commit for a snapshot, and `nu-cli whoami` prints the version of
the instance it is pointed at.

Comparing the two is left to you: nothing refuses to run on a mismatch, and a mismatch usually works. This
client is built from the Designer's own code, so the API it speaks is the one that Designer version shipped
with, and the parts that have not changed between the two versions behave the same. What fails is the part
that did change — a command reaching for an endpoint that does not exist there, or a field renamed since —
and it fails in that command rather than at start-up, which is why the version worth checking is the one in
`whoami` when something behaves oddly.

Of the two directions, a client older than the instance is likelier to be fine: it asks for what has already
been there long enough to still be there. A client newer than the instance is where commands reach for
things not yet built.

## License

Apache-2.0. What ships is one file with its dependencies compiled into it, and their terms ask to travel
with the copies — so they do, inside the binary:

```bash
nu-cli --licenses | less
```

Some 150 packages, each with its own license text and `NOTICE` where there is one, plus the Bun runtime the
executable was compiled with. The list is collected from the bundle itself when the build is made, so it
names what the file actually contains rather than what a manifest declares; a package that ships no license
file at all says so in place of the text, rather than quietly dropping out.

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
