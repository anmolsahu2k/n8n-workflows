# n8n LinkedIn Posting Pipeline

## Project Overview
Automated LinkedIn posting via Telegram. Send a rough idea → Claude generates a LinkedIn post → review/approve via Telegram inline buttons → post to LinkedIn.

## Architecture
- **n8n** runs in Docker (`docker.n8n.io/n8nio/n8n:2.11.3`) on port 5678 (localhost only)
- **Telegram webhook** receives messages via cloudflared quick tunnel (URL changes on restart)
- **Claude CLI** (`~/.local/bin/claude`) runs on the Mac host, called via SSH from n8n
- **Draft storage** uses `$getWorkflowStaticData('global')` in n8n — NOT file I/O
- **LinkedIn posting** uses n8n's LinkedIn OAuth2 node

## Key Files
- `docker-compose.yml` — n8n container config
- `.env` — `WEBHOOK_URL`, `N8N_ENCRYPTION_KEY`, `GENERIC_TIMEZONE`
- `scripts/generate_post.sh` — SSH forced-command script that calls Claude CLI
- `workflows/linkedin-pipeline.json` — n8n workflow (import via UI)
- `n8n_data/` — bind-mounted to `/home/node/.n8n` in container (gitignored except structure)

## Common Operations

### Start n8n
```bash
docker compose up -d
```

### Update webhook URL (cloudflare tunnel rotates on restart)
1. Start new tunnel: `cloudflared tunnel --url http://localhost:5678`
2. Copy new URL → update `WEBHOOK_URL` in `.env`
3. Restart n8n: `docker compose up -d`
4. Re-publish workflow in n8n UI (Publish button)

### Test Claude SSH locally
```bash
SSH_ORIGINAL_COMMAND="your test idea here" /Users/anmolsahu2k/Stuff/Create/n8n/scripts/generate_post.sh
```

### Test SSH from n8n perspective
```bash
ssh -i ~/.ssh/n8n_docker_key anmolsahu2k@host.docker.internal "your test idea"
```

### View n8n logs
```bash
docker compose logs -f n8n
```

## SSH Setup
- Key: `~/.ssh/n8n_docker_key` (ed25519, no passphrase)
- `~/.ssh/authorized_keys` entry uses `restrict,command=` to force `generate_post.sh` only
- Script calls `security unlock-keychain` to access macOS Keychain for Claude CLI OAuth

## n8n Workflow: LinkedIn Pipeline
The workflow handles two branches:

**Branch A — New Idea (Telegram message):**
`Telegram Trigger → Auth Gate → Route → Text Guard → Extract Idea → SSH Generate → Save Draft → Send Draft + Buttons`

**Branch B — Button Tap (callback_query):**
`Telegram Trigger → Auth Gate → Route → Parse Callback → Answer Callback → Restore Callback Data → Malformed Guard → Load Draft → Status Guard → Route Action → [Post | Regenerate | Cancel]`

### Critical n8n quirks to remember
- `answerCallbackQuery` returns `{"ok": true}` — all downstream nodes lose input data. Always insert a `Restore Callback Data` Code node: `return [{ json: $('Parse Callback').first().json }];`
- Inline keyboard `callbackData` expressions must use template syntax: `=post:{{ $json.draftId }}` (NOT `={{ 'post:' + $json.draftId }}`)
- Draft storage uses `$getWorkflowStaticData('global')` — data persists in n8n's SQLite DB
- `N8N_CONCURRENCY_PRODUCTION_LIMIT=1` is set to prevent race conditions on double-taps

### After importing workflow
1. Re-assign all credentials (Telegram, SSH, LinkedIn OAuth2)
2. Replace `YOUR_CHAT_ID` in Auth Gate node with actual Telegram Chat ID
3. Set LinkedIn Post node Text field to expression: `{{ $json.post }}`
4. Publish the workflow

## Credentials Needed
| Credential | Type | Notes |
|---|---|---|
| Telegram Bot | Telegram API | Bot Token from @BotFather |
| Mac SSH | SSH | `host.docker.internal`, port 22, user `anmolsahu2k`, private key `~/.ssh/n8n_docker_key` |
| LinkedIn | LinkedIn OAuth2 API | Client ID + Secret → OAuth connect flow in n8n |

## Known Issues / Gotchas
- **Keychain in SSH**: Claude CLI OAuth tokens are in macOS Keychain. Script calls `security unlock-keychain` with login password to make them accessible in headless SSH sessions.
- **File write permissions**: Docker container runs as `node` (uid 1000); Mac bind mount uses Mac user uid — UID mismatch prevents file writes from container. Draft storage was migrated to static data to avoid this entirely.
- **cloudflared quick tunnels**: URL is temporary and changes every time the process restarts. Must update `.env` + restart n8n + re-publish workflow each time.
- **LinkedIn app requirement**: App must be associated with a LinkedIn Company Page even when posting to personal profile. Required products: "Share on LinkedIn" + "Sign In with LinkedIn using OpenID Connect".
