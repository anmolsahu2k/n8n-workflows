#!/bin/zsh
# Called by n8n SSH node via forced-command restriction in authorized_keys.
# The idea text arrives as $SSH_ORIGINAL_COMMAND (SSH forced-command mode).
# When run directly for testing, falls back to $@ (positional arguments).
IDEA="${SSH_ORIGINAL_COMMAND:-$*}"

security unlock-keychain -p "1455" "$HOME/Library/Keychains/login.keychain-db" 2>/dev/null

/Users/anmolsahu2k/.local/bin/claude -p "You are a LinkedIn content expert helping someone build their personal brand.

Write an engaging LinkedIn post based on this idea: ${IDEA}

Requirements:
- Start with a strong hook (question or bold statement)
- Use short paragraphs (1-3 lines each)
- Professional but conversational tone
- 150-250 words
- End with 3-5 relevant hashtags on their own line
- Output ONLY the post text — no preamble, no quotes, just the post itself"
