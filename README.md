# agentop

A TUI for watching Claude Code multi-agent workflows live, from the terminal.

![agentop watching one workflow run: eight agents, two failed, two stalled](docs/demo.gif)

That recording is `agentop --demo`, a built-in run that never touches the disk, so it contains nobody's project names or transcript contents. Try it yourself before installing anything.

## The problem

Claude Code has `/workflows` for tracking multi-agent progress, where many subagents run in parallel and a run can take tens of minutes. That slash command only exists in the official CLI and TUI. Anyone using the VSCode extension has no way at all to see a running workflow's progress.

`agentop` does not connect to Claude Code through an API or any protocol, and it never contacts anyone. It only reads the files Claude Code already writes to disk while a workflow runs, then presents them as a TUI you can use from any terminal, whatever editor started the workflow.

No API key, no account, no service that we run. `agentop serve` is planned for consumers that cannot reach the disk, a phone over Tailscale for example, but even that only **listens** on an address you choose, defaulting to loopback.

## What it reads from disk

For every workflow run, Claude Code writes a directory:

```
<config-root>/projects/<project-slug>/<session-id>/subagents/workflows/wf_<runid>/
  journal.jsonl              one line per event (agent started / agent finished)
  agent-<id>.jsonl           the full transcript of each subagent
  agent-<id>.meta.json       agent type, spawn depth, model
```

`journal.jsonl` decides how many agents have started and how many have reported back. Each agent transcript is read incrementally, taking only the new bytes, because a transcript can grow to several megabytes while a workflow runs.

**Both config roots are scanned**: `~/.claude` for personal config and `~/.claude-work` for work or organisation config. agentop shows runs from both without you choosing between them.

## Install

This public repo holds only the README, LICENSE, `install.sh`, and Releases. The source lives in a separate private repo, so `go install` does not apply here. Pick one of three routes.

Homebrew:

```
brew install pimlabs/tap/agentop
```

npm:

```
npm install -g @pimlabs/agentop
```

Install script:

```
curl -fsSL https://raw.githubusercontent.com/pimlabs/agentop/main/install.sh | sh
```

## Usage

```
agentop                 # the most recent workflow, across both config roots
agentop wf_e63f8578     # a specific run, an ID prefix is enough
agentop -i 2            # change the refresh interval, default 1 second
agentop -v              # or --version, print the version and exit
```

The `AGENTOP_HOME` environment variable overrides the config root being scanned. It defaults to the user's home directory, where `.claude` and `.claude-work` are looked for. This is useful for pointing agentop at a captured directory with no live workflow running.

### Key map

Only two panels take focus: runs, and the agents inside the selected run. An agent transcript is not a panel but a screen of its own, opened with Enter.

| Key | Action |
|---|---|
| `Tab` / `→` / `l` | move focus to the other panel (runs ⇄ agents) |
| `Shift+Tab` / `←` / `h` | move focus to the other panel, the other way |
| `↑`/`↓` or `j`/`k` | move within the focused panel |
| `Enter` | in runs: move focus to agents. In agents: open the selected agent's transcript |
| `Esc` | on the transcript or help screen: go back to the list. On a list screen: nothing |
| `f` | show only agents that failed or are still running |
| `r` | refresh now, without waiting for the interval |
| `?` | open help; from help, `?`/`Enter`/`Esc` all close it |
| `q` / `Ctrl+C` | quit |

## Safety

agentop only reads. It never writes to a Claude Code config directory. Running it alongside a live workflow is safe, and there is no race against Claude Code itself.

Besides files, agentop runs two of the system's own read-only commands: `ps` to list processes, and `lsof` to read the working directory of a live Claude Code process. Both feed a single column: whether an unfinished run still has someone working on it, or its parent session is gone. agentop never signals, stops, or alters any process, and on a machine without `ps` or `lsof` that column reads `unknown` while everything else keeps working.

## Releases

Releases are published by [GoReleaser](https://goreleaser.com), triggered when a `v*` tag is pushed. It builds binaries for darwin, linux, and windows on amd64 and arm64, publishes a GitHub Release here, a cask to the `pimlabs/homebrew-tap` tap, and packages to npm under the `@pimlabs` scope.
