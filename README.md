# agentop

Watch Claude Code multi-agent workflows live, from a terminal, a browser, or
inside VS Code.

![agentop watching one workflow run: eight agents across three phases, one failed, two idle](docs/demo.gif)

That recording is `agentop --demo`, a built-in run that never touches the disk,
so it contains nobody's project names or transcript contents. You can run it
yourself before installing anything.

Claude Code has `/workflows` for following many subagents at once, and it
exists only in the official CLI. Start a workflow from the VS Code extension
and there is no way to watch its progress at all.

agentop reads the files Claude Code already writes to disk while a workflow
runs, and shows them. It connects to no API and speaks no protocol. **No API
key, no account, and no service that we run.** `agentop serve` exists for
screens that cannot reach the disk, a phone over Tailscale for example, but
even that only *listens* on an address you choose, and defaults to loopback.

## Install

| Platform | Command |
|---|---|
| **macOS** | `brew install pimlabs/tap/agentop` |
| **macOS, Linux** | `curl -fsSL https://agentop.pimlabs.id/install \| sh` |
| **Windows** | `irm https://agentop.pimlabs.id/install.ps1 \| iex` |
| **anywhere with Node** | `npm install -g @pimlabs/agentop` |

Then check it arrived, and watch it work without needing a live workflow:

```
agentop --version
agentop --demo
```

Both scripts do the same three things: work out your platform, download the
matching archive from Releases, and **verify its SHA-256 against the published
checksums**, stopping rather than installing when that fails. Neither one
installs a binary it has not verified.

<details>
<summary><b>Pinning a version, choosing a directory, leaving PATH alone</b></summary>

Piped into a shell there is no way to pass flags, so both scripts read the
environment instead. The names are the same on either platform:

| Variable | Default | Effect |
|---|---|---|
| `AGENTOP_VERSION` | the latest release | install a specific one, for example `v0.11.0` |
| `AGENTOP_INSTALL_DIR` | `/usr/local/bin` when writable, else `~/.local/bin`; on Windows `%LOCALAPPDATA%\agentop\bin` | where the binary lands |
| `AGENTOP_NO_PATH` | unset | Windows only: skip writing PATH |

The two platforms differ on PATH deliberately. `install.sh` prints the line to
add and leaves your shell profile alone, because a `curl | sh` that edits a
dotfile is the thing people rightly distrust about `curl | sh`. `install.ps1`
writes PATH, because no directory is already on a Windows user's PATH and a
script that installs and then prints an instruction has installed something
nobody can run.

</details>

<details>
<summary><b>What each route can and cannot install</b></summary>

Releases carry archives for all six combinations of darwin, linux and windows
on amd64 and arm64. The convenience routes are narrower than that, so start
here rather than with whichever command you recognise:

| Route | macOS | Linux | Windows |
|---|---|---|---|
| Homebrew | yes | no | no |
| `install.sh` | yes | yes | hands over to `install.ps1` |
| `install.ps1` | no | no | yes |
| npm | yes | yes | yes |
| Download from Releases | yes | yes | yes |

A Homebrew *cask* is a macOS mechanism, and `install.sh` reads `uname -s`. Run
it under Git Bash, MSYS or Cygwin and it hands over to the PowerShell installer
rather than failing; under WSL it does not, because WSL reports Linux and
genuinely wants the Linux binary.

The npm package is a thin shim that runs a prebuilt binary shipped as a
platform-specific `optionalDependency`, so npm downloads only the one matching
your machine.

To install by hand, take the archive for your platform from the [Releases
page](https://github.com/pimlabs/agentop/releases), a `.tar.gz` on macOS and
Linux and a `.zip` on Windows, check it against the `checksums.txt` published
beside it, unpack it, and put `agentop` somewhere on your `PATH`.

</details>

<details>
<summary><b>The binaries are not code-signed, and what that looks like</b></summary>

Nothing here carries a signature on any platform, so a fresh download is
treated as untrusted until you say otherwise.

*macOS.* Homebrew and `install.sh` both clear the quarantine attribute for you.
An archive downloaded by hand is blocked by Gatekeeper until you clear it
yourself, either in System Settings under Privacy & Security, or with:

```
xattr -d com.apple.quarantine /path/to/agentop
```

*Windows.* `install.ps1` calls `Unblock-File` for the same reason. If you
unpack an archive by hand, SmartScreen will most likely show "Windows protected
your PC" the first time you run it: choose **More info**, then **Run anyway**.
There is no Authenticode signature and there will not be one until either the
download reputation builds or a certificate is bought.

*Linux.* Nothing to do.

</details>

If `agentop --version` says "command not found", the install directory is not
on your `PATH`. `install.sh` prints the directory it used on its last line.

## The three surfaces

One binary, three screens, all reading the same files and using the same words.

| Surface | How you start it | Best for |
|---|---|---|
| **[Terminal UI](#the-terminal-ui)** | `agentop` | the machine you are sitting at |
| **[Browser dashboard](#watching-a-machine-you-are-not-sitting-at)** | `agentop serve`, then open the printed address | another machine, or a phone |
| **[VS Code](#inside-vs-code)** | install the extension | staying in the editor |

There is a fourth, for programs rather than people: `runs`, `show` and `watch`
emit JSON, described under [Reading it from a
script](#reading-it-from-a-script).

## The terminal UI

```
agentop                 # the newest run, across both config roots
agentop wf_e63f8578     # a specific run; an id prefix is enough
agentop e63f            # any substring of the id works as a filter
agentop -i 2            # refresh every 2 seconds instead of every 1
agentop --demo          # the built-in sample run, no file is ever read
agentop -v              # or --version, print the version and exit
agentop help            # or -h, the full usage text
```

Every command takes `-h` for its own flags, and every one of them writes to
stdout, so `agentop serve -h | less` shows something. Errors keep stderr.

Three levels, and the arrow keys walk all of them. `→` goes one level in, `←`
one level out: runs, then the agents of the selected run, then that agent's
transcript. `Enter` and `Esc` do the same thing, so nothing you already know
stops working, but you never need them.

Runs are grouped by the session they came out of, since several runs commonly
come from one conversation. A session heading is not selectable; the cursor
moves between runs.

The layout follows the terminal width. At 144 columns and above the detail
earns a third column of its own; between 99 and 144 you get two columns with
the detail as a strip beneath them; below 99 only the level you are on is
drawn, and `←` is how you get back to the one above it.

### Key map

On the list screen:

| Key | Action |
|---|---|
| `↑` / `k`, `↓` / `j` | move within the level you are on |
| `→` / `l` / `Enter` | one level in: runs to agents, agents to the transcript |
| `←` / `h` / `Esc` | one level out |
| `Tab`, `Shift+Tab` | next or previous panel, without changing level |
| `f` | attention only: hide every agent that does not need you |
| `n` | jump to the next agent that needs attention |
| `s` | cycle how runs are sorted; the current mode is shown in the runs column heading |
| `S` | reverse the current sort |
| `+` / `=` | poll less often |
| `-` / `_` | poll more often |
| `r` | reload now, without waiting for the interval |
| `?` | open help |
| `q` / `Ctrl+C` | quit |

On the transcript screen:

| Key | Action |
|---|---|
| `↑` / `↓`, page keys | scroll |
| `Tab`, `Shift+Tab` | next or previous tool group |
| `→` / `l` / `Enter` | fold or unfold the group under the cursor |
| `←` / `h` / `Esc` | back to the list |
| `?` | open help |

On the help screen, `?`, `Enter` and `Esc` all close it. `q` and `Ctrl+C` quit
from anywhere.

The poll interval you set with `+` and `-` applies immediately and is shown on
the rule at the bottom of the screen, beside the clock. It is not remembered
between sessions.

## Watching a machine you are not sitting at

Claude Code often runs somewhere else: a server, a VM, a machine in another
room. `agentop serve` answers the same documents the terminal shows, over HTTP
and Server-Sent Events, and hosts a browser dashboard built from them.

```
agentop serve                          # loopback only, http://127.0.0.1:8477
agentop serve --listen 0.0.0.0:8477    # every interface, reachable from the network
agentop serve --interval 2s            # how often /events re-reads the disk
```

### The browser dashboard

Open the printed address and you get the same information the terminal shows,
with nothing installed on the machine doing the looking. Two views:

**Mission Control**, an overview: active runs, running agents, how many need
attention, total tokens, a breakdown of tokens by model, and cards for the runs
themselves.

**Runs**, three panes: the run list, the agents inside the selected run, and
one agent's detail with its timeline, prompt, result and last message. On a
phone those three become three steps with a way back, rather than three columns
squeezed into 393 pixels.

Keyboard navigation mirrors the TUI: `Tab` and the arrows move between panes,
`↑`/`↓` or `j`/`k` move within one, `Enter` descends, `Esc` goes back, `f`
filters to what needs attention, `r` reloads, `?` opens help.

The page can also **notify you** when a run starts needing attention. The
browser asks for permission the first time you turn it on, and nothing is
requested before that.

### On a phone

The dashboard is installable as a PWA: a manifest at
`/manifest.webmanifest`, icons, and a service worker at `/sw.js` that caches
the page shell so losing the binary shows you the dashboard saying the stream
dropped, instead of the browser's error page. **The live data is never
cached.** `/runs`, `/runs/{id}` and `/events` always go to the network, because
a cached run list is a screen that lies.

**One caveat, measured rather than assumed.** A service worker only registers
in a secure context. `http://192.168.x.x` is not one, so on a phone reaching
the server over the LAN there is no install prompt in Chrome and no offline
shell; iOS will still add a standalone tile by hand, without that half. Reach
the server over something that terminates TLS, or through a mesh that gives it
a real name, and the install works properly. `agentop serve` does not speak TLS
itself.

### The routes

Every route is `GET` and nothing else; anything else answers 405.

| Route | Answers |
|---|---|
| `/runs` | the run list, the same document `agentop runs --json` prints. `?filter=` narrows by run id |
| `/runs/{id}` | one run. `?agent=<id>` narrows to a single agent, `?brief=true` drops prompt, result and timeline |
| `/events` | a live stream. `?run=<id>` follows one run instead of the list, `?filter=` narrows it, `?interval=` overrides the poll rate, floored at 200ms |
| `/` and `/assets/*` | the dashboard |
| `/manifest.webmanifest`, `/sw.js`, `/icon*`, `/apple-touch-icon.png` | the PWA files |

A test asserts that `/runs` is byte-identical to what `agentop runs --json`
writes, so the two can never drift.

Every error is a JSON body with an `error` key: 400 for an unparseable
parameter or an ambiguous run id, 403 for a Host that is not allowed, 404 for a
run id that matches nothing, 500 when the disk could not be read.

### Two safety rules decide who is answered

It is worth knowing them before you wonder about a 403.

**The first is the `Host` header.** A request is answered when it names
loopback, the address the server is bound to, or the address of the interface
the request actually arrived on. That last rule is what makes `--listen
0.0.0.0:8477` work from any of the machine's own addresses. A request naming a
*domain* is refused unless you name it, because a name is what DNS rebinding
needs to make a web page in your browser read this server on your behalf:

```
agentop serve --listen 0.0.0.0:8477 \
  --allow-host agentop.example.com \
  --allow-host 203.0.113.5:8477
```

Repeat the flag, or separate entries with commas. The second form is what a
cloud VM needs: its public address usually belongs to a router rather than to
any interface the VM can see, so the machine cannot work it out for itself.

**The second is `--full`.** Prompts, results and timelines carry source code
and sometimes secrets, so `--full` is **refused on any address that is not
loopback** and there is no flag to override it. Over a network you get the run
list and the agent states, never the transcripts.

### There is no authentication

Anything that can reach the port can read that machine's run list. Put it
behind something that does the authenticating: a Tailscale or WireGuard
network, or an SSH tunnel.

```
ssh -L 8477:127.0.0.1:8477 you@server     # on your laptop, with agentop serve running on the server
```

The tunnel is worth preferring even when the network is private. From the
server's point of view the request arrives on loopback, so nothing needs
allowing, and it is the only way `--full` is available at all from somewhere
else.

## Inside VS Code

The extension gives you a status bar item, a Runs panel in the Activity Bar
with runs grouped under the session they came from, each agent's transcript as
a read-only editor document, a notification when a run stops moving with agents
still running, and a terminal profile that starts the TUI in a tab.

It is not on the Marketplace or Open VSX yet. Download
`agentop-<version>.vsix` from the
[Releases page](https://github.com/pimlabs/agentop/releases) and install it:

```
code --install-extension agentop-<version>.vsix
```

It needs the `agentop` binary on `PATH`, or the `agentop.binaryPath` setting
pointing at it. Under Remote SSH, a dev container or WSL the extension runs
where the workspace is, which is also where Claude Code writes its journal, so
it reads the right disk without being told. The exception is an editor on
Windows driving a workspace in WSL where the workflow was started on the
Windows side: point `agentop.home` at `/mnt/c/Users/<you>`.

Run **agentop: Report Diagnostics** from the Command Palette when something
looks wrong. It prints the remote kind, the platform, the home directory it
resolved, which route found the binary, and the schema version that binary
answered with.

Extension releases are tagged `vscode-v*` and move independently of the
binary's `v*` tags. The two do not have to be on the same number.

## Reading it from a script

Three subcommands emit JSON and exit, or stream it until interrupted. The
output flag is required rather than assumed, so that adding a human-readable
format later cannot silently change what an existing script receives.

```
agentop runs --json [filter]                 list every run once and exit
agentop show <runid> --json [--brief] [--agent <id>]
agentop watch [runid] --ndjson [--interval 1s]
```

| Flag | Applies to | Effect |
|---|---|---|
| `--json` | `runs`, `show` | required; emit JSON |
| `--ndjson` | `watch` | required; emit newline-delimited JSON |
| `--brief` | `show` | omit `prompt`, `result`, `timeline` and `lastText` |
| `--agent <id>` | `show` | narrow the answer to one agent |
| `--interval <d>` | `watch` | how often the disk is re-read, default `1s` |

`watch` with no run id follows the run list; with one it follows that run.
Every line is one message, and each carries `v`, `type` and `at`:

| `type` | Sent when |
|---|---|
| `hello` | first, naming the agentop version and schema version |
| `snapshot` | the full current state |
| `delta` | only what changed since the last message |
| `tick` | the interval elapsed and nothing changed |
| `gone` | the run being followed disappeared from disk |
| `error` | the disk could not be read |

Every document starts with the same envelope:

```json
{"v":2,"type":"runs","generatedAt":"2026-08-17T21:43:17Z","runs":[...]}
```

`v` is the schema version, currently **2**. Every key is treated as public API:
renaming one is a breaking change that bumps `v`, and golden files in the
source repo fail the build if a key changes without that bump. New keys can
appear without a bump, so decode leniently and ignore what you do not know.

**Piping the bare command does the same as `runs --json`**, so `agentop | jq`
works without the TUI's escape sequences ending up in the pipe. `--demo` is
left alone, since it is an explicit request for the visual sample.

```
agentop | jq '.runs[] | select(.attentionCount > 0) | .id'
agentop watch --ndjson | jq -c 'select(.type == "delta")'
```

## Reference

### What the words mean

Every surface uses the same four states and the same four attention reasons, so
a word learned in the terminal means the same thing in the browser and in the
editor.

**Agent state:**

| State | Meaning |
|---|---|
| `running` | still writing to its transcript |
| `stalled` | quiet for longer than its own pattern suggests it should be |
| `done` | finished and reported back |
| `failed` | finished with an error |

`stalled` is relative rather than absolute, which is the whole reason it is
usable. The threshold is **three times that agent's own longest gap between
tool calls**, with a floor of **two minutes**. An agent that genuinely spends
five minutes between tool calls is not called stalled at its first five-minute
silence, and an agent that has only made two fast calls is not called stalled
seconds after going quiet.

**Attention reasons**, which is what the `f` filter, the `n` key and the alert
counts are built on:

| Reason | Fires when |
|---|---|
| `dead` | the agent failed |
| `stalled` | the agent is in the `stalled` state above |
| `overspend` | its output tokens are more than 3x the run's median, on a run of at least four agents and above an absolute floor |
| `orphan` | the journal still counts agents as unfinished, and nobody appears to be working on them |

The first three are per agent. `orphan` is the odd one: it belongs to the run
rather than to an agent, and it is the only reason that looks outside the files
Claude Code writes. It fires when the journal says work is outstanding **and**
either nothing in the run directory has been written for longer than that run's
own pattern allows, or `ps` and `lsof` prove no session is attached any more.

Those two halves are kept apart on purpose. The disk half has to wait for the
run to go quiet before it can guess, and it is a guess: a slow agent and a dead
session look the same on disk. The process half can say so the moment it looks,
but needs `ps` and `lsof` to exist. Treat `orphan` as a strong hint rather than
as `dead`'s certainty. See [Safety](#safety) for what those two commands are
used for.

A run with no journal never reports attention at all, by design. It has no
started-versus-finished ledger to compare against, and treating a missing
ledger as a problem made attention fire on 71% of runs.

### What it reads from disk

For every workflow run, Claude Code writes a directory:

```
<config-root>/projects/<project-slug>/<session-id>/subagents/workflows/wf_<runid>/
  journal.jsonl              one line per event (agent started / agent finished)
  agent-<id>.jsonl           the full transcript of each subagent
  agent-<id>.meta.json       agent type, spawn depth, model
```

`journal.jsonl` decides how many agents have started and how many have reported
back. Each agent transcript is read incrementally, taking only the new bytes,
because a transcript can grow to several megabytes while a workflow runs.

**Both config roots are scanned**: `~/.claude` for personal config and
`~/.claude-work` for work or organisation config. agentop shows runs from both
without you choosing between them.

Ordinary `Task` subagents, the ones started without the Workflow tool, have no
journal of their own. They are gathered into a pseudo-run per session so they
appear too, rather than leaving the screen empty. Anything derived from the
journal, which means the started-versus-finished accounting and every attention
rule, is switched off for those.

### Environment variables

| Variable | Read by | Effect |
|---|---|---|
| `AGENTOP_HOME` | every command | the directory searched for `.claude` and `.claude-work`. Defaults to your home directory. This is how you point agentop at a captured directory with no live workflow running |

`AGENTOP_HOME` names the directory that *contains* the config roots, not a
config root itself. Both `.claude` and `.claude-work` are looked for inside it.

The installers read three more, `AGENTOP_VERSION`, `AGENTOP_INSTALL_DIR` and
`AGENTOP_NO_PATH`, which are described under [Install](#install) next to the
scripts that read them.

### Exit codes

| Code | When |
|---|---|
| `0` | success, and for `--version` and `-h` |
| `1` | a missing required flag, a run id that matches nothing, an id that matches several runs, a disk that could not be read |
| `2` | an unrecognised flag on the bare command, which Go's flag package exits with before agentop sees it |

Errors go to stderr. The bare command prefixes them with `agentop:`, and a
subcommand's errors already name themselves, so a failed `show` prints both:

```
agentop: agentop show: no run matches "wf_zz"
```

Match on the message rather than on the prefix, since the doubling is an
accident of two layers each adding one and may be tidied.

`watch` and `serve` shut down cleanly on `SIGINT` and `SIGTERM`, so a consumer
piping `watch --ndjson` into a file never sees a truncated JSON value.

## Troubleshooting

**"command not found" after installing.** The install directory is not on your
`PATH`. `install.sh` prints where it put the binary on its last line. If more
than one copy exists, `type -a agentop` shows all of them in the order your
shell searches; `which` shows only the first match and has misled people here
before.

**macOS refuses to open it.** The binaries are not signed. See
[Install](#install).

**The screen is empty.** Zero runs is not an error, and the TUI says which
directories it looked in. Check that a workflow has actually run on this
machine, and that `AGENTOP_HOME` is not pointing somewhere else.

**The screen is empty under WSL, a dev container, or Remote SSH.** The journal
is on the machine Claude Code runs on, not necessarily the one your editor
runs on. Set `AGENTOP_HOME`, or the extension's `agentop.home`, to the home
directory that holds `.claude`.

**Everything reads `unknown` in the liveness column.** `ps` or `lsof` is
missing. That column, and only that column, depends on them.

**403 from `agentop serve`.** The `Host` header was not allowed. See [Two
safety rules](#two-safety-rules-decide-who-is-answered).

**404 on the dashboard while `/runs` works.** The binary was built without the
browser bundle. Use an official release rather than a locally built binary.

**No install prompt for the PWA on a phone.** Plain HTTP over a LAN address is
not a secure context. See [On a phone](#on-a-phone).

## Safety

agentop only reads. It never writes to a Claude Code config directory. Running
it alongside a live workflow is safe, and there is no race against Claude Code
itself.

Besides files, agentop runs two of the system's own read-only commands: `ps` to
list processes, and `lsof` to read the working directory of a live Claude Code
process. Both feed a single column: whether an unfinished run still has someone
working on it, or its parent session is gone. agentop never signals, stops, or
alters any process, and on a machine without `ps` or `lsof` that column reads
`unknown` while everything else keeps working.

`agentop serve` is the only part that touches a network, it only ever
**listens**, it defaults to loopback, and it refuses `--full` anywhere else.
agentop makes no outbound connections at any point, with one exception you ask
for explicitly: `install.sh` downloads the release you are installing.

## Releases and versioning

Releases are published by [GoReleaser](https://goreleaser.com), triggered when
a `v*` tag is pushed. It builds binaries for darwin, linux, and windows on
amd64 and arm64, publishes a GitHub Release here, a cask to the
`pimlabs/homebrew-tap` tap, and packages to npm under the `@pimlabs` scope. The
VS Code extension is built and attached separately from a `vscode-v*` tag.

Tags follow SemVer and describe what a user got. The JSON contract has its own
number, `v` in every document, currently `2`; it moves only when the shape of
an existing field changes, not when a field is added.

## License

MIT.
