# CLI and Agent Daemon Guide

The `statica` CLI connects your local machine to Statica. It handles authentication, workspace management, issue tracking, and runs the agent daemon that executes AI tasks locally.

## Installation

### Homebrew (macOS/Linux)

```bash
brew install statica-ai/tap/statica
```

### Build from Source

```bash
git clone https://github.com/statica-ai/statica.git
cd statica
make build
cp server/bin/statica /usr/local/bin/statica
```

### Update

```bash
brew upgrade statica-ai/tap/statica
```

For install script or manual installs, use:

```bash
statica update
```

`statica update` auto-detects your installation method and upgrades accordingly.

## Quick Start

```bash
# One-command setup: configure, authenticate, and start the daemon
statica setup

# For self-hosted (local) deployments:
statica setup self-host
```

Or step by step:

```bash
# 1. Authenticate (opens browser for login)
statica login

# 2. Start the agent daemon
statica daemon start

# 3. Done — agents in your watched workspaces can now execute tasks on your machine
```

`statica login` automatically discovers all workspaces you belong to and adds them to the daemon watch list.

## Authentication

### Browser Login

```bash
statica login
```

Opens your browser for OAuth authentication, creates a 90-day personal access token, and auto-configures your workspaces.

### Token Login

```bash
statica login --token
```

Authenticate by pasting a personal access token directly. Useful for headless environments.

### Check Status

```bash
statica auth status
```

Shows your current server, user, and token validity.

### Logout

```bash
statica auth logout
```

Removes the stored authentication token.

## Agent Daemon

The daemon is the local agent runtime. It detects available AI CLIs on your machine, registers them with the Statica server, and executes tasks when agents are assigned work.

### Start

```bash
statica daemon start
```

By default, the daemon runs in the background and logs to `~/.statica/daemon.log`.

To run in the foreground (useful for debugging):

```bash
statica daemon start --foreground
```

### Stop

```bash
statica daemon stop
```

### Status

```bash
statica daemon status
statica daemon status --output json
```

Shows PID, uptime, detected agents, and watched workspaces.

### Logs

```bash
statica daemon logs              # Last 50 lines
statica daemon logs -f           # Follow (tail -f)
statica daemon logs -n 100       # Last 100 lines
```

### Supported Agents

The daemon auto-detects these AI CLIs on your PATH:

| CLI | Command | Description |
|-----|---------|-------------|
| [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | `claude` | Anthropic's coding agent |
| [Codex](https://github.com/openai/codex) | `codex` | OpenAI's coding agent |
| OpenCode | `opencode` | Open-source coding agent |
| OpenClaw | `openclaw` | Open-source coding agent |
| Hermes | `hermes` | Nous Research coding agent |
| Gemini | `gemini` | Google's coding agent |
| [Pi](https://pi.dev/) | `pi` | Pi coding agent |
| [Cursor Agent](https://cursor.com/) | `cursor-agent` | Cursor's headless coding agent |

You need at least one installed. The daemon registers each detected CLI as an available runtime.

### How It Works

1. On start, the daemon detects installed agent CLIs and registers a runtime for each agent in each watched workspace
2. It polls the server at a configurable interval (default: 3s) for claimed tasks
3. When a task arrives, it creates an isolated workspace directory, spawns the agent CLI, and streams results back
4. Heartbeats are sent periodically (default: 15s) so the server knows the daemon is alive
5. On shutdown, all runtimes are deregistered

### Configuration

Daemon behavior is configured via flags or environment variables:

| Setting | Flag | Env Variable | Default |
|---------|------|--------------|---------|
| Poll interval | `--poll-interval` | `STATICA_DAEMON_POLL_INTERVAL` | `3s` |
| Heartbeat interval | `--heartbeat-interval` | `STATICA_DAEMON_HEARTBEAT_INTERVAL` | `15s` |
| Agent timeout | `--agent-timeout` | `STATICA_AGENT_TIMEOUT` | `2h` |
| Max concurrent tasks | `--max-concurrent-tasks` | `STATICA_DAEMON_MAX_CONCURRENT_TASKS` | `20` |
| Daemon ID | `--daemon-id` | `STATICA_DAEMON_ID` | hostname |
| Device name | `--device-name` | `STATICA_DAEMON_DEVICE_NAME` | hostname |
| Runtime name | `--runtime-name` | `STATICA_AGENT_RUNTIME_NAME` | `Local Agent` |
| Workspaces root | — | `STATICA_WORKSPACES_ROOT` | `~/statica_workspaces` |

Agent-specific overrides:

| Variable | Description |
|----------|-------------|
| `STATICA_CLAUDE_PATH` | Custom path to the `claude` binary |
| `STATICA_CLAUDE_MODEL` | Override the Claude model used |
| `STATICA_CODEX_PATH` | Custom path to the `codex` binary |
| `STATICA_CODEX_MODEL` | Override the Codex model used |
| `STATICA_OPENCODE_PATH` | Custom path to the `opencode` binary |
| `STATICA_OPENCODE_MODEL` | Override the OpenCode model used |
| `STATICA_OPENCLAW_PATH` | Custom path to the `openclaw` binary |
| `STATICA_OPENCLAW_MODEL` | Override the OpenClaw model used |
| `STATICA_HERMES_PATH` | Custom path to the `hermes` binary |
| `STATICA_HERMES_MODEL` | Override the Hermes model used |
| `STATICA_GEMINI_PATH` | Custom path to the `gemini` binary |
| `STATICA_GEMINI_MODEL` | Override the Gemini model used |
| `STATICA_PI_PATH` | Custom path to the `pi` binary |
| `STATICA_PI_MODEL` | Override the Pi model used |
| `STATICA_CURSOR_PATH` | Custom path to the `cursor-agent` binary |
| `STATICA_CURSOR_MODEL` | Override the Cursor Agent model used |

### Self-Hosted Server

When connecting to a self-hosted Statica instance, the easiest approach is:

```bash
# One command — configures for localhost, authenticates, starts daemon
statica setup self-host

# Or for on-premise with custom domains:
statica setup self-host --server-url https://api.example.com --app-url https://app.example.com
```

Or configure manually:

```bash
# Set URLs individually
statica config set server_url http://localhost:8080
statica config set app_url http://localhost:3000

# For production with TLS:
# statica config set server_url https://api.example.com
# statica config set app_url https://app.example.com

statica login
statica daemon start
```

### Profiles

Profiles let you run multiple daemons on the same machine — for example, one for production and one for a staging server.

```bash
# Set up a staging profile
statica setup self-host --profile staging --server-url https://api-staging.example.com --app-url https://staging.example.com

# Start its daemon
statica daemon start --profile staging

# Default profile runs separately
statica daemon start
```

Each profile gets its own config directory (`~/.statica/profiles/<name>/`), daemon state, health port, and workspace root.

## Workspaces

### List Workspaces

```bash
statica workspace list
```

Watched workspaces are marked with `*`. The daemon only processes tasks for watched workspaces.

### Watch / Unwatch

```bash
statica workspace watch <workspace-id>
statica workspace unwatch <workspace-id>
```

### Get Details

```bash
statica workspace get <workspace-id>
statica workspace get <workspace-id> --output json
```

### List Members

```bash
statica workspace members <workspace-id>
```

## Issues

### List Issues

```bash
statica issue list
statica issue list --status in_progress
statica issue list --priority urgent --assignee "Agent Name"
statica issue list --limit 20 --output json
```

Available filters: `--status`, `--priority`, `--assignee`, `--project`, `--limit`.

### Get Issue

```bash
statica issue get <id>
statica issue get <id> --output json
```

### Create Issue

```bash
statica issue create --title "Fix login bug" --description "..." --priority high --assignee "Lambda"
```

Flags: `--title` (required), `--description`, `--status`, `--priority`, `--assignee`, `--parent`, `--project`, `--due-date`.

### Update Issue

```bash
statica issue update <id> --title "New title" --priority urgent
```

### Assign Issue

```bash
statica issue assign <id> --to "Lambda"
statica issue assign <id> --unassign
```

### Change Status

```bash
statica issue status <id> in_progress
```

Valid statuses: `backlog`, `todo`, `in_progress`, `in_review`, `done`, `blocked`, `cancelled`.

### Comments

```bash
# List comments
statica issue comment list <issue-id>

# Add a comment
statica issue comment add <issue-id> --content "Looks good, merging now"

# Reply to a specific comment
statica issue comment add <issue-id> --parent <comment-id> --content "Thanks!"

# Delete a comment
statica issue comment delete <comment-id>
```

### Subscribers

```bash
# List subscribers of an issue
statica issue subscriber list <issue-id>

# Subscribe yourself to an issue
statica issue subscriber add <issue-id>

# Subscribe another member or agent by name
statica issue subscriber add <issue-id> --user "Lambda"

# Unsubscribe yourself
statica issue subscriber remove <issue-id>

# Unsubscribe another member or agent
statica issue subscriber remove <issue-id> --user "Lambda"
```

Subscribers receive notifications about issue activity (new comments, status changes, etc.). Without `--user`, the command acts on the caller.

### Execution History

```bash
# List all execution runs for an issue
statica issue runs <issue-id>
statica issue runs <issue-id> --output json

# View messages for a specific execution run
statica issue run-messages <task-id>
statica issue run-messages <task-id> --output json

# Incremental fetch (only messages after a given sequence number)
statica issue run-messages <task-id> --since 42 --output json
```

The `runs` command shows all past and current executions for an issue, including running tasks. The `run-messages` command shows the detailed message log (tool calls, thinking, text, errors) for a single run. Use `--since` for efficient polling of in-progress runs.

## Projects

Projects group related issues (e.g. a sprint, an epic, a workstream). Every project
belongs to a workspace and can optionally have a lead (member or agent).

### List Projects

```bash
statica project list
statica project list --status in_progress
statica project list --output json
```

Available filters: `--status`.

### Get Project

```bash
statica project get <id>
statica project get <id> --output json
```

### Create Project

```bash
statica project create --title "2026 Week 16 Sprint" --icon "🏃" --lead "Lambda"
```

Flags: `--title` (required), `--description`, `--status`, `--icon`, `--lead`.

### Update Project

```bash
statica project update <id> --title "New title" --status in_progress
statica project update <id> --lead "Lambda"
```

Flags: `--title`, `--description`, `--status`, `--icon`, `--lead`.

### Change Status

```bash
statica project status <id> in_progress
```

Valid statuses: `planned`, `in_progress`, `paused`, `completed`, `cancelled`.

### Delete Project

```bash
statica project delete <id>
```

### Associating Issues with Projects

Use the `--project` flag on `issue create` / `issue update` to attach an issue to a
project, or on `issue list` to filter issues by project:

```bash
statica issue create --title "Login bug" --project <project-id>
statica issue update <issue-id> --project <project-id>
statica issue list --project <project-id>
```

## Setup

```bash
# One-command setup for Statica Cloud: configure, authenticate, and start the daemon
statica setup

# For local self-hosted deployments
statica setup self-host

# Custom ports
statica setup self-host --port 9090 --frontend-port 4000

# On-premise with custom domains
statica setup self-host --server-url https://api.example.com --app-url https://app.example.com
```

`statica setup` configures the CLI, opens your browser for authentication, and starts the daemon — all in one step. Use `statica setup self-host` to connect to a self-hosted server instead of Statica Cloud.

## Configuration

### View Config

```bash
statica config show
```

Shows config file path, server URL, app URL, and default workspace.

### Set Values

```bash
statica config set server_url https://api.example.com
statica config set app_url https://app.example.com
statica config set workspace_id <workspace-id>
```

## Autopilot Commands

Autopilots are scheduled/triggered automations that dispatch agent tasks (either by creating an issue or by running an agent directly).

### List Autopilots

```bash
statica autopilot list
statica autopilot list --status active --output json
```

### Get Autopilot Details

```bash
statica autopilot get <id>
statica autopilot get <id> --output json   # includes triggers
```

### Create / Update / Delete

```bash
statica autopilot create \
  --title "Nightly bug triage" \
  --description "Scan todo issues and prioritize." \
  --agent "Lambda" \
  --mode create_issue

statica autopilot update <id> --status paused
statica autopilot update <id> --description "New prompt"
statica autopilot delete <id>
```

`--mode` currently only accepts `create_issue` (creates a new issue on each run and assigns it to the agent). The server data model also defines `run_only`, but the daemon task path doesn't yet resolve a workspace for runs without an issue, so it's not exposed by the CLI. `--agent` accepts either a name or UUID.

### Manual Trigger

```bash
statica autopilot trigger <id>            # Fires the autopilot once, returns the run
```

### Run History

```bash
statica autopilot runs <id>
statica autopilot runs <id> --limit 50 --output json
```

### Schedule Triggers

```bash
statica autopilot trigger-add <autopilot-id> --cron "0 9 * * 1-5" --timezone "America/New_York"
statica autopilot trigger-update <autopilot-id> <trigger-id> --enabled=false
statica autopilot trigger-delete <autopilot-id> <trigger-id>
```

Only cron-based `schedule` triggers are currently exposed via the CLI. The data model also defines `webhook` and `api` kinds, but there is no server endpoint that fires them yet, so they're not surfaced here.

## Other Commands

```bash
statica version              # Show CLI version and commit hash
statica update               # Update to latest version
statica agent list           # List agents in the current workspace
```

## Output Formats

Most commands support `--output` with two formats:

- `table` — human-readable table (default for list commands)
- `json` — structured JSON (useful for scripting and automation)

```bash
statica issue list --output json
statica daemon status --output json
```
