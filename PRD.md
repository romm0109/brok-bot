# PRD: Team spaces

Status: draft, October 2026. Builds on `docs/software-teams-research.md` (option 1) and the product
decisions agreed in review.

## 1. Executive summary

Today every Rakazo space belongs to one person. The database already allows several members per
space, but nothing lets a second person join, and if one did they would see an empty space: bots,
chats and routines are scoped to the user who created them.

Team spaces let a small software team share one space. Everyone in it sees and uses the same bots,
chats, routines, memory, files and Team Computer. The space has its own plan, model credits, vault
and approval rules, so a shared bot behaves the same no matter who asks it, and nobody lends their
personal keys to the team.

The MVP goal: two to ten engineers can create a team space, invite each other, and work with a
shared bot on web, desktop and mobile, with approvals routed to the right person. Team spaces are
the prerequisite for the repo-owning engineer bot described in the research notes.

## 2. Mission

Give a team one persistent, self-hostable colleague it shares, instead of each person running their
own forgetful agent.

Principles:

1. **One space, one truth.** Everything in a team space is visible to every member. No hidden
   per-person corners in v1.
2. **The space acts, not a person.** Credits, credentials, connections and approval rules belong to
   the space.
3. **Nothing private leaks in.** Team spaces start empty; private spaces never become shared.
4. **Same product everywhere.** Web, desktop and mobile ship together.
5. **Approvals show their origin.** Every approval says what started the run and who wrote it.

## 3. Target users

**Primary: a small software team (2 to 10 engineers).** Comfortable with GitHub, CI and chat tools;
some have used Devin, Cursor background agents or Copilot. They want a bot that remembers the
codebase and the team's conventions, takes work from anyone on the team, and does not need each
person to set it up again.

Pain points today:

- Each engineer's bot is private, so knowledge and setup are duplicated.
- A shared bot would have to run on one person's credits and credentials.
- There is no way to see what the bot did for a teammate, or to pick up where they left off.

**Secondary: the space owner** (often a team lead) who pays for the plan and manages who is in it.

## 4. MVP scope

### Core functionality

- ✅ Create a new team space (always starts empty).
- ✅ Invite people by email; accept or decline an invite.
- ✅ Every member sees all bots, chats, routines, memory, files and computers in the space.
- ✅ Members can invite people, create, edit and delete any bot or routine, and add credentials and
  connections.
- ✅ Owners can additionally remove members, change roles and delete the space.
- ✅ Leave a team space. A leaver's bots and routines stay and pass to the owner.
- ✅ Approvals go to the person who asked. Runs nobody asked for (webhooks, PR comments, routines)
  can be approved by any member.
- ✅ Every approval shows its trigger: the message, comment or event, and its author.
- ✅ Messages in shared chats show who sent them.
- ❌ Converting an existing private space into a team space.
- ❌ Private chats or private bots inside a team space.
- ❌ Personal approval rules applying inside a team space.

### Technical

- ✅ Space-scoped authorization for space content, replacing per-user filters where the content
  belongs to the space.
- ✅ Space-level approval rules, vault and connections.
- ✅ Deterministic offline tests for every new route and each authorization change.
- ❌ An admin role between owner and member.
- ❌ SSO, SCIM or directory sync.

### Billing

- ✅ Each team space has its own plan, chosen through the same picker as today, and its own model
  credit balance.
- ✅ Members' personal credits are never spent in a team space.
- ❌ Per-seat pricing changes (seats can come later; the billing table already has a `seats` field).

### Integration

- ✅ Existing chat apps, Git event routines and MCP connections work inside a team space using the
  space's credentials.
- ❌ A native GitHub app install and the repo-owning engineer bot (follow-up PRD).

### Deployment

- ✅ Works the same on hosted and self-hosted instances; no new required vendor.
- ✅ Migrations are additive and safe with the previous release running side by side.

## 5. User stories

1. **As a team lead, I want to create a team space and invite my engineers, so that we share one
   set of bots.**
   Example: Dana creates "Payments team", invites three teammates by email, and they appear as
   members once they accept.

2. **As an engineer, I want to use the team's bot without setting it up myself, so that I benefit
   from what it already knows.**
   Example: Sam joins and asks the existing "Payments bot" why the refund job is flaky; the bot
   answers from memory built up in Dana's earlier chats.

3. **As an engineer, I want to see what the bot did for a teammate, so that I can pick up their
   work.**
   Example: Sam opens Dana's chat from yesterday, sees the half-finished migration and asks the bot
   to continue it.

4. **As the person who asked, I want risky actions from my request to come to me, so that I stay
   responsible for my own work.**
   Example: Sam asks the bot to push a fix; only Sam gets the push approval.

5. **As any member, I want to approve actions from runs nobody started, and see exactly what
   triggered them, so that unattended work does not stall and I can spot suspicious requests.**
   Example: a CI failure starts a routine; the approval shows "Triggered by: workflow run failed on
   `main`" and the proposed diff, and Lee approves it from their phone.

6. **As the owner, I want to remove someone who left the company, so that they lose access
   immediately.**
   Example: Dana removes Alex; Alex's routines keep running, now owned by Dana.

7. **As a member, I want the team's bot to use the team's keys and credits, so that I'm not paying
   for or exposing my own.**
   Example: Lee adds the team's GitHub token to the space vault; every member's requests use it.

8. **As a self-hosting operator, I want team spaces to work without any hosted service, so that we
   can run Rakazo internally.**
   Example: an instance with no billing provider configured creates team spaces with no plan step.

## 6. Core architecture and patterns

### A team space is its own organization

Billing (`BillingAccount`) and model credits (`ModelCreditAccount`) already live on
`Organization`, and each user has a personal organization that holds their private spaces. A team
space is created inside a new organization whose members are the team. This gives the space its
own plan and credit balance without changing the billing model, and existing account-deletion logic
already handles organizations with several members.

```
Organization (team)          ── BillingAccount, ModelCreditAccount
 ├─ Member (one per person)  ── role: owner | member
 ├─ Invitation               ── email, status, expiresAt
 └─ Space (team space)
     ├─ SpaceMember          ── role: owner | member
     └─ Bots, Threads, Routines, Memory, Secrets, Connections, Computers …
```

A team organization holds exactly one space in v1, which keeps the organization and space
membership lists identical.

### Authorization: from "my content" to "my space's content"

The request actor already resolves to a `spaceId` the user is a member of. About 50 queries also
filter by `userId: actor.userId`. Each one is audited and put in one of two groups:

- **Space content** (bots, threads, messages, routines, memory, artifacts, skills, connections,
  computers): scope by `spaceId` only, after the membership check. `userId` stays as "created by".
- **Personal data** (voice, model preferences, AI-data consent, notification preferences, push
  tokens): keep the `userId` filter.

The membership check stays in one shared place in the actor resolution, so no route can forget it.
For a private space nothing changes: it has one member.

### Settings resolution

Today account settings follow the user into every space unless the space customizes them. In a
team space, approval rules, vault and connections always resolve from the space; personal
equivalents are ignored. Models and voice can stay personal preferences, but only the space's
credentials and credits are used to run them.

### Approvals

Each run records who started it (`Run` already has a user) and what triggered it. Approval routing:

| Run started by | Who can approve |
|---|---|
| A member's message or task | That member |
| Webhook, PR comment, Git event, schedule | Any member |

The approval payload includes the trigger kind, source (repo, PR, channel) and the author as the
external system reported it.

### Patterns to follow

- Contracts in `packages/contracts`, routes in `apps/api`, database helpers in `packages/db`.
- Frontends express intent and render state; the API owns authorization and validation.
- Coordinate across instances through Postgres, never in-process locks.

## 7. Features

### Create a team space

Entry point: the existing **Create** menu gains **New team space**. It asks for a name, creates the
team organization, space and owner membership in one transaction, then opens the plan picker on
hosted instances.

### Invite and join

- Any member enters one or more emails. Each becomes an `Invitation` with a 7-day expiry.
- The invitee gets an email with a link. Signed-in users with a matching email see the invite in
  the app.
- Accepting creates `Member` and `SpaceMember` rows; declining or expiry closes the invite.
- Members can cancel pending invites.

### Members list

Settings for the space show members and pending invites. Owners see **Remove** and a role control;
everyone sees **Leave**.

### Leaving and removal

- On leave or removal, bots, routines and threads the person created stay, with their creator
  reassigned to an owner for anything that requires an accountable user (routines, connections).
- Their sessions lose access to the space immediately; open realtime connections are closed.
- The last owner can't leave without promoting someone or deleting the space.

### Shared chats

All threads in the space are listed for every member. Messages show the sender's name and avatar.
Anyone can continue any thread.

### Approvals with origin

The existing approval card adds who it's waiting on and, for unattended runs, the trigger summary
and author.

### Team billing

The plan picker and credit options work as today, scoped to the team organization. Self-hosted
instances without billing skip the step.

## 8. Technology stack

No new dependencies. Current stack:

| Layer | Technology |
|---|---|
| API | Hono 4.13, oRPC 1.15 |
| Contracts | oRPC contract, Zod 4.6 |
| Database | PostgreSQL, Prisma 7.10 |
| Auth | Better Auth 1.7 (organization plugin routes stay closed) |
| Web | React 19.2, React Router 7.18, Vite 8.3, shadcn/ui on Base UI |
| Desktop | Electron 45, hosting the web UI |
| Mobile | Expo 57, Expo Router, @expo/ui, React Native 0.86 |
| Tests | Vitest 4.1, Playwright for desktop e2e in CI |

Invite emails go through the existing email sending path.

## 9. Security and configuration

- **Authorization.** Membership is checked once, centrally, on every space-scoped request. Each
  converted query gets a test proving a non-member gets nothing and a member sees space content.
- **Roles.** `owner` and `member`. Only owners remove members, change roles and delete the space.
- **Invites.** Single-use, expiring tokens bound to the invited email; cancelled on removal.
  Rate-limited per space and per inviter.
- **Better Auth.** Its organization routes remain blocked; all lifecycle goes through product RPCs.
- **Secrets.** Space secrets stay encrypted with the space key. Members can add and use them; the
  UI never reveals stored values.
- **Prompt injection.** Unattended runs triggered by outside text (for example a PR comment from a
  non-member) can request risky actions, and any member can approve them. This is a deliberate
  product choice; the mitigation is that every approval clearly shows the trigger text and its
  author. See risks.
- **Audit.** Membership changes, role changes, invites and approvals write `AuditEvent` rows.
- **Configuration.** No new environment variables.

Out of scope: SSO, SCIM, per-member credential restrictions, approval quorums.

## 10. API specification

New oRPC procedures (names indicative). All require a signed-in user; space procedures require
membership.

| Procedure | Who | Input | Output |
|---|---|---|---|
| `spaces.createTeam` | Any user | `{ name }` | `{ spaceId }` |
| `spaces.members.list` | Member | `{ spaceId }` | `{ members[], invites[] }` |
| `spaces.invites.create` | Member | `{ spaceId, emails[] }` | `{ invites[] }` |
| `spaces.invites.cancel` | Member | `{ inviteId }` | `{}` |
| `spaces.invites.accept` | Invitee | `{ token }` | `{ spaceId }` |
| `spaces.invites.decline` | Invitee | `{ token }` | `{}` |
| `spaces.members.remove` | Owner | `{ spaceId, userId }` | `{}` |
| `spaces.members.setRole` | Owner | `{ spaceId, userId, role }` | `{}` |
| `spaces.leave` | Member | `{ spaceId }` | `{}` |

Example:

```json
// spaces.invites.create
{ "spaceId": "spc_example", "emails": ["teammate@example.com"] }

// response
{ "invites": [{ "id": "inv_example", "email": "teammate@example.com", "expiresAt": "2026-11-07T00:00:00Z" }] }
```

Existing list procedures for bots, threads and routines keep their shapes and add a `createdBy`
summary where the UI shows authorship. Approval payloads add `waitingOn` (a member or "any member")
and `trigger` (`{ kind, source, author }`).

## 11. Success criteria

The MVP is done when a team of three can create a team space, invite each other, share one bot and
route approvals correctly on all three surfaces.

- ✅ A non-member gets no data from any space-scoped procedure (tested per procedure).
- ✅ A member sees every bot, thread, routine and memory document in the space.
- ✅ Private spaces behave exactly as before.
- ✅ A requester-started run's approval is only actionable by the requester.
- ✅ An unattended run's approval is actionable by any member and shows its trigger and author.
- ✅ Removing a member revokes access immediately and keeps their bots and routines running.
- ✅ Team space runs never spend a member's personal credits or use their personal vault.
- ✅ Invites, members, roles and leaving work on web, desktop and mobile.
- ✅ Migrations pass the side-by-side deploy check.

Quality: no new user-facing explainer text beyond what the flows need; every new string is justified
in its PR.

## 12. Implementation phases

Estimates assume one engineer familiar with the codebase.

### Phase 1: membership foundation (about 2 weeks)

Goal: a team space can exist and people can join it.

- ✅ `spaces.createTeam` with a team organization.
- ✅ Invite, accept, decline, cancel, remove, set role, leave.
- ✅ Invite email.
- ✅ Audit events.

Validation: offline tests for every procedure, including expiry, wrong email and last-owner rules.

### Phase 2: space-scoped authorization (about 3 weeks)

Goal: members see and use everything in the space; nobody else sees anything.

- ✅ Classify all per-user queries as space content or personal data.
- ✅ Convert space content to space scoping behind the central membership check.
- ✅ Creator reassignment on leave and removal.
- ✅ Space-level approval rules, vault and connections in team spaces.

Validation: a member and non-member test for each converted query; private-space regression suite
unchanged.

### Phase 3: approvals and billing (about 2 weeks)

Goal: runs act as the space and approvals reach the right person.

- ✅ Requester versus any-member approval routing.
- ✅ Trigger kind, source and author on approvals.
- ✅ Team plan and credits through the existing picker.

Validation: tests for routing per trigger kind, and that personal credits are never charged.

### Phase 4: surfaces (about 3 weeks, overlapping phase 3)

Goal: full parity on web, desktop and mobile.

- ✅ New team space flow, members list, invites and leave on web and desktop.
- ✅ The same on mobile with native sheets, menus and alerts.
- ✅ Sender names in shared threads; approval origin on all surfaces.

Validation: web e2e for the members screen (screenshot in the PR), desktop e2e in CI, iOS
screenshot catalog flow for the mobile members screen.

## 13. Future considerations

- Repo-owning engineer bot: native GitHub app install, repo binding, pull request lifecycle and the
  CI-fix loop.
- Evidence bundles on finished work.
- Private chats or bots inside a team space.
- An admin role, approval quorums and restricting which members can approve unattended runs.
- Treating triggers from non-members differently from triggers from members.
- Per-seat pricing, SSO and SCIM for larger organizations.
- Inspectable, exportable team memory.

## 14. Risks and mitigations

| Risk | Mitigation |
|---|---|
| A converted query drops its user filter without the membership check and exposes another user's data. | One central membership check; a non-member test for every converted query; security review of phase 2 as its own PR. |
| Prompt injection: an outsider's PR comment leads the bot to propose a harmful action, and any member approves it. | Approvals show the trigger text, source and author prominently. Revisit restricting outsider-triggered actions after launch (see future considerations). |
| Members can add credentials, delete bots and invite people, so one careless or compromised member affects the whole team. | Audit events for all of these; owners can remove members instantly. Consider an admin role later. |
| Shared memory exposes something a member told the bot privately. | Team spaces start empty and private spaces can't be converted; members know everything is shared. |
| Any member can change the space's plan and payment. | Accepted per current decision. Audit billing changes and notify owners; revisit making billing owner-only. |

## 15. Appendix

- `docs/software-teams-research.md`: competitor review and feature options.
- `docs/spaces.md`: current space behavior.
- `packages/db/prisma/schema.prisma`: `Organization`, `Member`, `Space`, `SpaceMember`,
  `Invitation`, `BillingAccount`, `ModelCreditAccount`.
- `packages/db/src/spaces.ts`: space creation, deletion and account-deletion claims.
- `packages/auth/src/index.ts`: `isBlockedAuthPath`, which keeps Better Auth organization routes
  closed.

### Assumptions made

- Two roles (owner, member); owners can promote members to owner.
- One team space per team organization in v1.
- Invites are by email with a 7-day expiry.
- Models and voice stay personal preferences in a team space; credentials and credits come from the
  space.
- Timeline estimates are rough and assume one engineer.
