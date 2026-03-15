#!/bin/zsh
# Called by n8n SSH node via forced-command restriction in authorized_keys.
# SSH_ORIGINAL_COMMAND format:
#   blog:<base64_idea>
#   linkedin:<base64_idea>|<mediumUrl>
#   tweet:<base64_idea>|<mediumUrl>
# When run directly for testing, falls back to $@ (positional arguments).
set -euo pipefail
INPUT="${SSH_ORIGINAL_COMMAND:-$*}"
TYPE="${INPUT%%:*}"
PAYLOAD="${INPUT#*:}"

security unlock-keychain -p "1455" "$HOME/Library/Keychains/login.keychain-db" 2>/dev/null

case "$TYPE" in
  blog)
    IDEA=$(echo "$PAYLOAD" | base64 -d)
    /Users/anmolsahu2k/.local/bin/claude -p "Write a Medium-style blog post based on this idea: ${IDEA}

Output format — your response must start with exactly:
TITLE: [your title here]
---
[full blog content below]

Requirements:
- Clear, engaging title on the TITLE line
- Strong hook in the first 2 sentences
- Conversational, human tone (not AI-sounding)
- Mix paragraphs and bullet points with headings
- Practical examples and a real use case
- End with TL;DR (3-4 bullets) then PS (one final takeaway)
- 800-1200 words total"
    ;;

  linkedin)
    IDEA=$(echo "${PAYLOAD%%|*}" | base64 -d)
    MEDIUM_URL="${PAYLOAD#*|}"
    /Users/anmolsahu2k/.local/bin/claude -p "Write a LinkedIn post based on this idea: ${IDEA}

Blog published at: ${MEDIUM_URL} — include this link at the end.

Requirements:
- First line must be a strong hook
- Short lines, mobile-friendly
- Conversational tone, no buzzwords
- Include 1 personal insight
- End with an engagement question
- Relevant emojis but not too many
- 150-300 words
Output ONLY the post text — no preamble, no quotes"
    ;;

  tweet)
    IDEA=$(echo "${PAYLOAD%%|*}" | base64 -d)
    MEDIUM_URL="${PAYLOAD#*|}"
    /Users/anmolsahu2k/.local/bin/claude -p "Write a tweet about this idea: ${IDEA}

Blog is at: ${MEDIUM_URL} — include this link.

Requirements:
- Strong hook
- Punchy, concise sentences
- Emojis
- Focus on outcome or insight
- Under 280 characters total including the link
Output ONLY the tweet text"
    ;;

  *)
    echo "ERROR: Unknown type: $TYPE" >&2
    exit 1
    ;;
esac
