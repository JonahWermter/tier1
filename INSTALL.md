# Installing Tier1

## What you need

- **Windows 10 or 11**
- **[Claude Code](https://claude.ai/code)**

Tier1 uses PowerShell 5.1, which is already on your machine. No other software, no package managers, nothing to configure.

---

## Step 1: Install Claude Code

If you already have Claude Code, skip to Step 2.

Open PowerShell and run one of these:

```powershell
# Option A: direct install
irm https://claude.ai/install.ps1 | iex

# Option B: via WinGet
winget install Anthropic.ClaudeCode
```

Run `claude` once after installing to sign in and accept terms.

---

## Step 2: Get Tier1

### Option A: Git Clone

```powershell
git clone https://github.com/JonahWermter/tier1.git
```

### Option B: ZIP Download

1. Go to [github.com/JonahWermter/tier1](https://github.com/JonahWermter/tier1)
2. Click the green **Code** button, then **Download ZIP**
3. Extract it somewhere you'll remember (e.g., `C:\Users\YourName\tier1`)

---

## Step 3: Run it

Open a terminal, go to the tier1 folder, and start Claude Code:

```powershell
cd tier1
claude
```

Once Claude is running, type:

```
/tier1 'describe your problem here'
```

For example:

```
/tier1 'Windows Update stuck at 0% for two hours'
```

Tier1 is a Claude Code "skill" — a set of instructions inside the project's `.claude/skills/` folder. When you run `claude` from the `tier1/` directory, it picks up the skill automatically. No config files to edit.

---

## Global install (power users)

The steps above are project-scoped — `/tier1` only works when you launch Claude Code from inside the `tier1/` directory. If you want it available everywhere, you can copy the skill files into Claude Code's global config.

### What to copy

Clone the repo to a permanent location first:

```powershell
git clone https://github.com/JonahWermter/tier1.git C:\Tools\tier1
```

Then copy the skill and agent files into your Claude Code config:

```powershell
# Create directories if they don't exist
New-Item -ItemType Directory -Force -Path "$HOME\.claude\skills" | Out-Null
New-Item -ItemType Directory -Force -Path "$HOME\.claude\agents" | Out-Null

# Copy skills
Copy-Item -Recurse "C:\Tools\tier1\.claude\skills\tier1" "$HOME\.claude\skills\tier1"
Copy-Item -Recurse "C:\Tools\tier1\.claude\skills\tier1-safety" "$HOME\.claude\skills\tier1-safety"

# Copy agents
Copy-Item "C:\Tools\tier1\.claude\agents\tier1-*.md" "$HOME\.claude\agents\"
```

**One more thing:** the skill references `references/` and `scripts/` using relative paths that expect the full repo structure around it. You'll need to copy those into the right spot relative to the skill:

```powershell
# Copy references and scripts alongside the skill
Copy-Item -Recurse "C:\Tools\tier1\references" "$HOME\.claude\skills\tier1\references"
Copy-Item -Recurse "C:\Tools\tier1\scripts" "$HOME\.claude\skills\tier1\scripts"
```

Then update the paths in `$HOME\.claude\skills\tier1\SKILL.md` — find every instance of `${CLAUDE_SKILL_DIR}/../../../references/` and replace it with `${CLAUDE_SKILL_DIR}/references/`. Same for `scripts/safety/` paths: replace `${CLAUDE_SKILL_DIR}/../../../scripts/` with `${CLAUDE_SKILL_DIR}/scripts/`.

After that, `/tier1` works from any directory.

### Updating a global install

Pull the latest from the repo and re-copy the files. The repo is the source of truth.

---

## Domain agents

Tier1 ships with three specialized agents that skip routing and go straight to a specific domain. Same safety guarantees — just faster if you already know the problem area.

| Agent | Covers | Use when |
|-------|--------|----------|
| `tier1-system` | General Windows + BSOD | Crashes, blue screens, Windows Update, system-level stuff |
| `tier1-apps` | Gaming Mods + Outlook/M365 | Mod manager problems, Outlook crashes, M365 activation |
| `tier1-network` | Network / Connectivity | No internet, DNS, Wi-Fi, adapter issues |

Use `/tier1` when you're not sure what category the problem falls into. Use an agent directly when you already know.

---

## Troubleshooting

### "Skill not found" or `/tier1` doesn't work

**Project-scoped install:** Make sure you're running `claude` from inside the `tier1/` folder:

```powershell
cd C:\path\to\tier1
claude
```

**Global install:** Check that the skill file is in place:

```powershell
Test-Path "$HOME\.claude\skills\tier1\SKILL.md"
```

If that returns `False`, re-run the copy commands from the global install section.

### PowerShell scripts won't run

Claude Code passes `-ExecutionPolicy Bypass` at the process scope by default, so this shouldn't be an issue for most people.

If your machine enforces script restrictions via Group Policy (common on corporate/managed machines), Tier1 detects this and switches to manual mode — it walks you through each step instead of running scripts directly. Nothing you need to change on your end.

---

## Privacy

Tier1 runs locally. No telemetry, no third-party services, no additional data collection beyond what Claude Code itself uses. Nothing is stored between sessions.

---

## Updates

```powershell
cd tier1
git pull
```

ZIP users: re-download from GitHub and extract over your existing folder.

---

Back to [README](README.md).
