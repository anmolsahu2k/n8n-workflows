TITLE: I Built a Single-Input Content Pipeline: Blog Idea → Dev.to → LinkedIn → Twitter (With Claude + n8n)
---

Every time I publish a blog post, I do the same thing three times. Write the post. Then write a LinkedIn take on it. Then write a tweet. Same idea, three different formats, three different tones. It's not hard — it's just tedious. And tedious things are exactly what automation is for.

So I built a pipeline. Type an idea once. Review each output. Click approve three times. Done.

Here's how it works — and what nearly broke while building it.

## The Problem

I already had a v1: a Telegram bot that takes a rough idea, sends it to Claude via SSH, and returns a LinkedIn post. Click approve → it posts. That workflow runs entirely on my local machine through an n8n Docker container.

But it only did LinkedIn. And I kept writing the same idea three ways anyway. What I wanted was a full chain: blog post first, then LinkedIn, then tweet — each one informed by the previous, each one reviewed before going live.

## What I Built

A single browser form running locally. Type in an idea. Wait about 30 seconds while Claude writes a ~1000-word Dev.to-style blog post. Review it in the browser. Hit Approve — it publishes to Dev.to.

Immediately after, Claude writes a LinkedIn post that links to the freshly published article. Review it. Approve. Then Claude writes a tweet. Review it. Approve.

If any draft isn't right, hit Regenerate. The pipeline keeps your progress — it knows Dev.to is already published, knows what the URL is, and only regenerates the piece you're not happy with. No work is lost.

The whole thing runs locally. No cloud infrastructure, no new subscriptions. Just n8n in Docker, Claude CLI called over SSH, and a browser.

## The Architecture

n8n handles orchestration. Claude CLI runs on the host machine and gets invoked via SSH from inside the Docker container. A forced-command restriction on the SSH key means that key can only run the content-generation script — nothing else on the machine is accessible.

The pipeline uses a single Webhook trigger. A GET request to the webhook URL returns the idea form. Every POST action from that form runs synchronously: n8n processes the full action (Claude generation, state updates, or platform API calls) and returns the next review page directly. No polling, no background jobs, no waiting for a callback.

State is stored in `$getWorkflowStaticData('global')`, which persists in n8n's SQLite database across requests. Each draft gets a unique ID that travels through every form submission as a hidden input.

The idea text is base64-encoded before being sent over SSH, which handles edge cases like pipes, newlines, and special characters without any escaping gymnastics.

## The Tricky Parts

**The n8n iframe trap.** My first instinct was to use n8n's Form Trigger node. It seemed like the right fit — form in, response out. But n8n sandboxes Form Trigger HTML responses inside an iframe. Relative form actions break. The buttons stopped working. The fix: a plain Webhook trigger with a `Respond to Webhook` node, which lets you return any HTML you want, rendered directly in the browser. One architecture decision that would have cost hours of debugging if I hadn't caught it in planning.

**The state machine.** The pipeline tracks 11 states: 8 in-flight stages from `blog_review` through `publishing_tweet`, plus terminal states `completed` and `cancelled`, and a replacement state `superseded` for regenerated drafts. The interesting ones are two recovery states: `medium_published` and `linkedin_published`. These get set immediately after a platform post succeeds, before the next Claude generation runs. If Claude fails mid-pipeline, the draft sits in a resumable state. A retry button appears. No data lost, no platform re-posted to.

**The duplicate post problem.** What if n8n times out on a Dev.to API call, but Dev.to actually received it? A blind retry would double-post. The solution: when a platform API call fails, n8n shows a "Manual Check Required" page. Did it go through? If yes, paste the URL and continue. If no, revert and try again. The user makes the call — the pipeline doesn't guess.

**Stage guards.** Every action checks two things before doing anything: does this draft ID exist, and is the draft in the expected stage? On every regenerate, the old draft ID is marked `superseded` and a new one is created. This means a stale browser tab can't accidentally re-approve a draft that's already been processed. Without this, hitting the back button and clicking Approve again would have fired a duplicate LinkedIn post.

## The Codex Review Loop

Before writing any workflow JSON, I used Codex CLI to iteratively review the architecture plan. It took 5 rounds. Each round caught something real: the sandboxing issue with Form Trigger, stale-page race conditions, dead-end states after partial failures, missing named-node context references in Code nodes, and attribute injection risk in hidden form fields.

That last one was subtle. HTML attribute escaping needs all five characters: `&`, `"`, `'`, `<`, and `>`. Most examples only cover three. A blog idea with a double quote in it would have broken every form submission downstream — silently, with no error, just wrong behavior.

Running the architecture plan through a second model before touching any implementation is something I'll do for every non-trivial n8n build from now on.

## Limitations & Edge Cases

This is a single-user local tool. The synchronous design works well for that — it would not scale to concurrent users without significant rework.

The state store (`$getWorkflowStaticData`) is backed by n8n's SQLite. Fine for personal use, not designed for high throughput.

macOS Keychain access in headless SSH sessions requires an explicit unlock step in the script. This is specific to the Mac environment where Claude CLI stores its OAuth tokens — if you're running this on Linux, the credential setup would be different.

Dev.to's API has been deprecated for publications created after 2023. If the n8n Dev.to node stops working with your account, there's no automatic fallback in this build — manual posting to Dev.to would be required, which somewhat defeats the purpose of this step.

## What It Looks Like in Practice

Open the local webhook URL in a browser. Type an idea. About 30 seconds later, a blog draft appears in a scrollable preview. Read through it, hit Approve, and Dev.to publishes it.

The LinkedIn draft appears immediately after, already referencing the live article. Read it, approve. Then the tweet. Approve.

Total hands-on time: about 3 minutes per piece of content. The rest is waiting on Claude and API calls.

## TL;DR

- One browser form, three platforms: type an idea once, review and approve each draft before it publishes anywhere
- n8n + Claude CLI over SSH handles the full chain — blog → Dev.to → LinkedIn → Twitter — with a state machine that survives partial failures
- The hard parts weren't the AI generation — they were iframe sandboxing, duplicate-post prevention, and stale browser tabs firing old actions
- A Codex plan review before implementation caught 5 real bugs, including a hidden form field injection that would have silently broken every submission with special characters

PS: The most valuable part of this build wasn't the workflow — it was being forced to think through failure modes before writing a single node.
