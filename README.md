# n8n Content Pipeline

Two local automation workflows powered by n8n + Claude CLI over SSH.

---

## Workflows

### 1. LinkedIn Pipeline (Telegram)

Send a rough idea to your Telegram bot → Claude writes a LinkedIn post → approve/regenerate/cancel with inline buttons → post to LinkedIn.

```
Telegram message (idea)
  → n8n (Docker)
    → SSH → Mac host → claude -p "..."
      → Draft sent to Telegram with buttons
        → ✅ Post      → LinkedIn
        → 🔄 Regen    → Claude rewrites → new draft
        → ❌ Cancel   → Done
```

### 2. Blog Pipeline (Browser)

Open a local URL in your browser → type an idea → Claude writes a blog post, LinkedIn post, and tweet in sequence → review and approve each before it publishes.

```
Browser form (idea)
  → n8n (Docker)
    → SSH → Mac host → generate_content.sh blog:...
      → Review page in browser
        → ✅ Approve → Medium publishes
          → SSH → linkedin:...|<mediumUrl>
            → Review → ✅ Approve → LinkedIn posts
              → SSH → tweet:...|<mediumUrl>
                → Review → ✅ Approve → Twitter posts
```

State is tracked in `$getWorkflowStaticData('global')` across requests. The pipeline is resumable — if Claude fails mid-chain, a retry button appears without losing prior published content.

---

## Prerequisites

- Docker Desktop
- Claude CLI installed and authenticated (`~/.local/bin/claude -p "test"` works)
- Telegram bot token — for the LinkedIn pipeline only
- LinkedIn Developer App with **Share on LinkedIn** + **Sign In with LinkedIn using OpenID Connect** products (requires a LinkedIn Company Page)
- Medium integration token — for the blog pipeline
- Twitter OAuth2 credentials — for the blog pipeline

---

## Setup

### 1. Environment

```bash
cp .env.example .env
```

```env
GENERIC_TIMEZONE=America/New_York
N8N_ENCRYPTION_KEY=<run: openssl rand -hex 16>
WEBHOOK_URL=https://<your-cloudflare-tunnel>.trycloudflare.com   # LinkedIn pipeline only
```

### 2. SSH key

n8n runs in Docker and can't access the Mac's `claude` binary directly. A forced-command SSH key bridges the gap — the key can only run the specified script, nothing else on the machine is accessible.

**LinkedIn pipeline** — uses `generate_post.sh`:
```bash
ssh-keygen -t ed25519 -f ~/.ssh/n8n_docker_key -N ""
```

Add to `~/.ssh/authorized_keys`:
```
restrict,command="/path/to/scripts/generate_post.sh" ssh-ed25519 AAAA...your-public-key...
```

**Blog pipeline** — uses `generate_content.sh`:
```bash
ssh-keygen -t ed25519 -f ~/.ssh/n8n_blog_key -N ""
```

Add to `~/.ssh/authorized_keys`:
```
restrict,command="/path/to/scripts/generate_content.sh" ssh-ed25519 AAAA...your-public-key...
```

Enable Remote Login: **System Settings → General → Sharing → Remote Login → ON**

### 3. Start n8n

```bash
docker compose up -d
```

Open [http://localhost:5678](http://localhost:5678)

### 4. Tunnel (LinkedIn pipeline only)

The Telegram webhook requires a public HTTPS URL:

```bash
cloudflared tunnel --url http://localhost:5678 --no-autoupdate &
```

Copy the `https://...trycloudflare.com` URL into `WEBHOOK_URL` in `.env`, then restart n8n and re-publish the workflow. The URL changes every time the process restarts (free tier).

---

## Credentials

| Name | Type | Used by |
|---|---|---|
| Telegram Bot | Telegram API | LinkedIn pipeline |
| Mac SSH (LinkedIn) | SSH | LinkedIn pipeline |
| Mac SSH (Blog) | SSH | Blog pipeline |
| LinkedIn OAuth2 API | LinkedIn OAuth2 API | Both |
| Medium | Medium API | Blog pipeline |
| Twitter/X | Twitter OAuth2 API | Blog pipeline |

**SSH credential config:** host `host.docker.internal`, port `22`, user `anmolsahu2k`, auth via private key.

**LinkedIn OAuth2 redirect URL:** `http://localhost:5678/rest/oauth2-credential/callback`

---

## Importing workflows

### LinkedIn Pipeline

1. Workflows → Import from File → `workflows/linkedin-pipeline.json`
2. Open **Auth Gate** node → replace `YOUR_CHAT_ID` with your Telegram Chat ID (get it from @userinfobot)
3. Assign credentials to each node
4. Click **Publish**

### Blog Pipeline

1. Workflows → Import from File → `workflows/blog-pipeline.json`
2. Assign credentials to each node
3. Click **Publish**
4. Open `http://localhost:5678/webhook/blog-pipeline` in your browser

---

## Testing

```bash
# Test generate_post.sh (LinkedIn pipeline)
SSH_ORIGINAL_COMMAND="Why shipping fast beats waiting for perfect" \
  ./scripts/generate_post.sh

# Test generate_content.sh (blog pipeline)
SSH_ORIGINAL_COMMAND="blog:$(echo 'Why shipping fast beats waiting for perfect' | base64)" \
  ./scripts/generate_content.sh

# Test SSH from n8n's perspective (LinkedIn)
ssh -i ~/.ssh/n8n_docker_key anmolsahu2k@host.docker.internal "your idea here"

# View logs
docker compose logs -f n8n
```

---

## Files

```
.
├── docker-compose.yml               # n8n service (port 5678, localhost only)
├── .env                             # secrets (gitignored)
├── scripts/
│   ├── generate_post.sh             # LinkedIn pipeline: called via SSH, runs claude -p
│   └── generate_content.sh          # Blog pipeline: handles blog/linkedin/tweet commands
└── workflows/
    ├── linkedin-pipeline.json       # Telegram → LinkedIn
    ├── blog-pipeline.json           # Browser form → Medium + LinkedIn + Twitter
    └── blog-pipeline-simple.json    # Simplified version (for reference)
```
