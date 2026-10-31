# Software teams: market gap and feature direction

Notes from a competitor review (October 2026). Competitor details come from third-party blogs, not
vendor documentation, so treat them as directional.

## Competitors

| Product | Strengths | Gap for software teams |
|---|---|---|
| Meta Muse | Cloud machine, watchable browser, split permissions (read email without sending it). | Consumer product with no team or admin features. |
| Grok Bot | Persistent VM, teach-by-demonstration, a coordinator bot over specialist bots. | Memory can't be inspected, corrected or exported. No public API. |
| OpenAI Dots | Lives in Slack and Teams, read-only background work, built-in rules for when to ask. | Teams of Dots haven't shipped. Limited to paid plans. |
| Devin, Cursor background agents, Factory | Ticket in, pull request out, with logs and screenshots as evidence. | Task runners with no persistent identity or memory. Not self-hostable. |

The consumer agents are persistent but not built for teams. The coding agents work in teams but
forget everything between tasks. Rakazo is persistent, self-hostable and open source, so it can
combine both.

## What Rakazo has today

- A Git event routine trigger backed by a GitHub webhook receiver that verifies the HMAC signature
  and accepts about 23 event types (pull requests, reviews, comments, issues, checks, workflow runs,
  pushes, releases). An offline emulator covers it in tests.
- GitHub actions only through generic connectors: Composio, Pipedream, or the GitHub MCP server.
- Skills importable from a GitHub repository (instructions only).
- Slack and other chat apps, group chats, bot-to-bot messaging, subagents, Team Computers, and an
  approval system with stricter rules for webhook-started runs.

## What is missing

- A native GitHub app or OAuth install. Setup is a manually pasted webhook URL plus your own credentials.
- A bot bound to a repo, with a checked-out clone and codebase memory.
- A pull request lifecycle: tracking a PR from opened through review comments and CI failures to
  merged, and mapping those events back to the bot's task.
- A CI-failure loop that tells the bot to fix and push.
- Unconfirmed: whether a webhook-triggered routine continues the bot's existing conversation or
  starts a fresh run.
- Unconfirmed: whether spaces can be shared by several people. The docs describe spaces as private.

## Feature options

1. **Shared team space with a repo-owning engineer bot (preferred).** Several people share bots in
   one space. A bot bound to a repo opens pull requests, answers review comments and CI failures,
   and keeps its own memory of the codebase. Much of the plumbing exists: event intake, signature
   verification, Team Computers and approvals.
2. **Evidence bundles on finished work.** Each pull request or result carries a test run, a
   screenshot or video of the bot's desktop, and a diff summary.
3. **Incident and on-call bot.** Triggered by alert webhooks, reads logs, proposes a fix, and asks
   before acting.
4. **Inspectable team memory.** A team-visible, editable and exportable record of what a bot has
   learned about the codebase and its conventions.

## Constraints

- Keep tracker and repo integrations provider-neutral, using the generic Git event and MCP paths
  rather than a GitHub-only adapter.
- Treat pull request comments as untrusted text. A repo-owning bot makes the stricter approval
  rules for webhook runs more important.
- New user-facing copy needs a written justification in the PR description.

## Next steps

1. Read the inbound webhook delivery code and how routines resume threads.
2. Check whether multi-person spaces exist; if not, they are the prerequisite for option 1.
3. Write an implementation plan for option 1.
