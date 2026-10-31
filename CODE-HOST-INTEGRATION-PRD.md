# PRD: Code host integration (GitHub and GitLab)

Status: draft · October 2026 · Supersedes the "use the generic Git event and MCP paths" constraint in
[`docs/software-teams-research.md`](docs/software-teams-research.md) for repository access.

## 1. Executive Summary

Rakazo bots can already run commands on their own computer, but working in a real repository means
handing them a personal token through a generic MCP connector. Setup is fiddly, the generic tools are
unreliable, and the token ends up somewhere the bot can read it. This feature adds a native,
first-party integration with GitHub and GitLab so a bot can clone a repository, commit, push and open
a pull request (GitHub) or merge request (GitLab) as a normal part of a chat-started task.

The core value is a bot that works in your codebase like a careful teammate: it has its own identity
on the code host, keeps a persistent clone on its computer, pushes only to branches it created, and
asks before opening a pull request that other people will see. Host credentials never enter the
sandbox; every git operation passes through a Rakazo git proxy that enforces those rules.

**MVP goal:** a user connects GitHub or GitLab (cloud or self-hosted), binds one or more repositories
to a bot, asks the bot in chat to make a change, and receives an approval request to open a pull or
merge request containing the bot's commits on a `rakazo/<bot>/…` branch.

## 2. Mission

Let any Rakazo bot do real work in a team's repositories without giving it more access than the task
needs, and without requiring a hosted vendor or an MCP server.

**Core principles**

1. **The server enforces, the model proposes.** Branch rules, repository scope and approvals are
   checked by the backend and the git proxy, never by instructions to the model.
2. **No host credential in the sandbox.** The bot's computer only ever holds a short-lived proxy
   grant that is useless outside Rakazo.
3. **One contract, many hosts.** GitHub and GitLab are adapters behind one provider-neutral
   code-host contract; nothing outside the adapters knows which host a repository lives on.
4. **Honest identity.** Work done by a bot is attributed to the bot wherever the host allows it.
5. **Self-hostable first.** github.com, gitlab.com, GitHub Enterprise Server and self-managed GitLab
   all work, with each user bringing their own app or token.

## 3. Target Users

| Persona | Description | Technical comfort | Needs and pain points |
|---|---|---|---|
| **Self-hosting developer** | Runs Rakazo for themselves, wants a bot that fixes bugs and opens PRs in their own repos. | High | Wants setup in a couple of clicks, no MCP plumbing, no token sitting in the sandbox. |
| **Small team lead** | Uses Rakazo with a few teammates and an org on GitHub or a group on GitLab. | Medium to high | Needs bot changes to arrive as reviewable PRs, never as surprise pushes to `main`. |
| **Self-managed GitLab user** | Company runs GitLab on its own domain, often on the free tier. | Medium | Most agent products only support github.com; needs a base URL and a token option. |

## 4. MVP Scope

### Core Functionality
- ✅ Connect GitHub by registering a personal GitHub App through the manifest flow, then installing it on chosen repositories
- ✅ Connect GitLab with OAuth (user-registered OAuth application) **or** a pasted access token (personal, project or group)
- ✅ Bind specific repositories to a bot from its settings
- ✅ Clone a bound repository onto the bot's computer, kept between runs and fetched on later runs
- ✅ Commit and push to branches the bot created under `rakazo/<bot>/…`
- ✅ Open a pull request (GitHub) or merge request (GitLab) after the user approves
- ✅ Disconnect a connection, which revokes access and removes the bot's repository bindings
- ❌ Pushing to branches the bot did not create, the default branch, or protected branches
- ❌ Merging, closing, approving or labelling pull or merge requests
- ❌ Reading or replying to review comments, issues or CI results

### Technical
- ✅ Provider-neutral `CodeHostProvider` contract in `@rakazo/adapter-kit`
- ✅ GitHub and GitLab adapters in `@rakazo/adapters` using the hosts' REST APIs over `fetch`
- ✅ Git smart-HTTP proxy in the API that injects short-lived host tokens and enforces push rules
- ✅ Offline emulators for both hosts and a shared conformance suite
- ❌ API-only commits (via the host's commits API) for bots without a computer
- ❌ Codebase memory or indexing of the clone

### Integration
- ✅ github.com and GitHub Enterprise Server
- ✅ gitlab.com and self-managed GitLab
- ❌ Webhooks of any kind (GitHub App is registered with its webhook disabled)
- ❌ Bitbucket, Gitea, Azure DevOps (the contract should not preclude them)
- ❌ Repository access through MCP for these hosts

### Deployment
- ✅ Works on every sandbox provider that gives a bot a computer with `git` and network access to the API
- ✅ Additive database migration only
- ❌ An instance-wide, admin-registered GitHub App (each user brings their own in v1)

## 5. User Stories

1. **As a developer, I want to connect GitHub without creating tokens by hand, so that setup takes
   a minute instead of a tutorial.**
   *Example:* In Settings → Connections they choose GitHub, confirm the prefilled app on GitHub,
   pick two repositories to install it on, and land back in Rakazo with the connection active.

2. **As a self-managed GitLab user, I want to paste an access token and my GitLab URL, so that I can
   use the integration without registering an OAuth app.**
   *Example:* They enter `https://gitlab.example.com` and a project access token with `api` and
   `write_repository`; Rakazo validates the scopes and lists the projects the token can reach.

3. **As a bot owner, I want to choose exactly which repositories a bot can work in, so that a bot
   for the docs site can't touch the billing service.**
   *Example:* In the bot's settings they bind `acme/docs` only. Asking the bot to change
   `acme/billing` fails with a message that the repository isn't bound.

4. **As a developer, I want to ask the bot in chat to fix a bug and get a pull request, so that I can
   review the change like any other teammate's.**
   *Example:* "Fix the date parsing bug in `acme/docs` and open a PR." The bot fetches its existing
   clone, creates `rakazo/docs-bot/fix-date-parsing`, commits, pushes, and shows an approval card
   with the PR title, body and diff summary. On approval the PR appears on GitHub authored by
   `docs-bot-app[bot]`.

5. **As a team lead, I want the bot to never push to `main` or a teammate's branch, so that a
   confused or manipulated bot can't overwrite real work.**
   *Example:* The bot runs `git push origin HEAD:main`; the proxy rejects it with
   `rakazo: bots can only push branches they created under rakazo/docs-bot/`.

6. **As a developer, I want later tasks to reuse the bot's clone, so that work on a large repository
   doesn't start with a multi-minute clone every time.**
   *Example:* The second task in a week only runs `git fetch` before starting.

7. **As a user, I want disconnecting to really cut access, so that I can trust removing the
   integration.**
   *Example:* After disconnecting GitHub, the bot's next fetch fails at the proxy, and the
   connection's stored app key and tokens are deleted.

**Technical stories**

8. **As a maintainer, I want both adapters tested offline against emulators with one conformance
   suite, so that adding a third host doesn't mean writing tests from scratch.**
9. **As a security reviewer, I want every push decision recorded in the audit log, so that I can
   see what a bot pushed, where, and what was refused.**

## 6. Core Architecture & Patterns

```
 Chat ──▶ Run (bot)                                        Code host
            │  repo tools                                  (GitHub / GitLab)
            ▼                                                    ▲
   Bot computer (sandbox)                                        │ short-lived,
   ~/repos/<host>/<owner>/<repo>                                 │ repo-scoped token
   git remote = https://<api>/git/<repo-id>.git                  │
   credential helper ──▶ proxy grant (per run, expires)          │
            │ smart HTTP (fetch / push)                          │
            ▼                                                    │
   API: git proxy ── checks grant, repo binding, push rules ─────┘
            │
            ├─▶ CodeHostProvider (adapter): mint token, list repos, open PR/MR
            ├─▶ SecretStore: app keys, OAuth/access tokens
            └─▶ Postgres: connections, bindings, bot-owned branches, audit
```

### Directory structure (new and touched)

```
packages/adapter-kit/src/code-host.ts          # CodeHostProvider contract and errors
packages/adapters/src/github-code-host.ts      # GitHub App adapter (manifest, JWT, tokens, PRs)
packages/adapters/src/gitlab-code-host.ts      # GitLab adapter (OAuth + token, MRs)
packages/adapters/src/code-host-emulator.ts    # offline GitHub/GitLab REST + git http-backend
packages/adapters/src/code-host-conformance.test.ts
packages/contracts/src/code-host.ts            # shared request/response schemas
apps/api/src/routes/code-hosts.ts              # connect, list repos, bind
apps/api/src/git-proxy.ts                      # smart-HTTP proxy + push policy
apps/web/src/pages/settings/…                  # connect flow, bot repository binding
apps/mobile/app/…                              # native auth session + bot repository picker
packages/db/prisma/schema.prisma               # new models (additive)
```

### Key patterns

- **Adapter + composition root.** Host-specific URLs, auth and translation live only in the two
  adapters; the API resolves the adapter from the connection's `provider`.
- **Policy at the proxy.** The proxy parses the `git-receive-pack` command list (`<old> <new> <ref>`)
  before forwarding any bytes and rejects the whole push if any ref breaks the rules.
- **Bot-owned branches in Postgres.** A branch becomes bot-owned when the proxy forwards a successful
  create (`old = 0000…`) under the bot's prefix. Later pushes to it must be fast-forwards.
- **Approvals through `ExternalEffect`.** Opening a PR/MR is an external effect with an idempotency
  key, so it uses the existing approval cards, rules and audit on every surface.
- **No global queues.** The proxy streams request and response bodies; concurrency is limited only
  per connection by the host's rate limits.

## 7. Tools/Features

### Bot tools (available only when the bot has a computer and at least one bound repository)

**`code_repos`** – list repositories bound to the bot.
- Returns host, full path, default branch, local clone path, and whether a clone exists.

**`code_repo_checkout`** – clone or update a bound repository on the bot's computer.
- First run: `git clone` via the proxy into `~/repos/<host>/<path>`.
- Later runs: `git fetch --prune` and report the current branch and status.
- Writes repo-local git config: remote URL pointing at the proxy, a credential helper that returns
  the run's proxy grant, and `user.name` / `user.email` for commit authorship (see Security).

**Plain `git`** – the bot commits and pushes with ordinary git commands. The proxy is the
enforcement point, so no special push tool is needed and refusals come back as normal git errors.

**`code_open_change_request`** – open a pull request (GitHub) or merge request (GitLab).
- Inputs: repository, source branch (must be bot-owned), target branch (default: repository default),
  title, body, draft flag.
- Requires user approval via the existing approval flow; the card shows title, target and a diff
  summary (files changed, insertions, deletions).
- Returns the PR/MR URL and number.

### User-facing features

- **Connect GitHub** – manifest flow creates a GitHub App owned by the user (or by an org they
  manage), then the GitHub install screen to pick repositories.
- **Connect GitLab** – base URL plus either OAuth (user supplies their OAuth app's client ID and
  secret) or an access token.
- **Bot repositories** – a picker in bot settings listing repositories the connection can reach.
- **Disconnect** – removes the connection, its secrets, bindings and outstanding proxy grants.

### Planned UI copy (to be justified in the PR per AGENTS.md)

| Copy | Where | Why it's needed |
|---|---|---|
| "GitHub", "GitLab" | Connections list | Names the provider; no alternative. |
| "Repositories" | Bot settings section heading | The binding control needs a label. |
| "Open pull request?" / "Open merge request?" | Approval card title | The approval must say what it approves. |
| "This bot needs a computer to use repositories." | Bot settings, only when the bot has no computer | Explains why the picker is disabled; shown only in that state. |

## 8. Technology Stack

Existing stack, no new runtime dependencies:

| Area | Technology |
|---|---|
| Runtime | Node.js 22.22+ / 24, pnpm 9.15, TypeScript 7 |
| API | Hono 4.13 |
| Database | PostgreSQL via Prisma 7.10 |
| Web / desktop | React 19.2, Vite 8, Electron 45 (hosts the web UI) |
| Mobile | Expo 57, Expo Router, native auth session for OAuth |
| Contracts | Zod 4.6 in `@rakazo/contracts` |
| Git | System `git` on the bot computer image; smart-HTTP protocol at the proxy |

**Host APIs, called directly with `fetch`:**
- GitHub REST: app manifest conversion, installation access tokens, repositories, pull requests.
- GitLab REST v4: OAuth, `personal_access_tokens/self`, projects, merge requests.

**Crypto:** GitHub App JWTs signed with `node:crypto` (RS256); no JWT library.

**Optional dependencies:** none. Because the adapters use plain `fetch`, nothing extra loads for
users who don't connect a code host.

## 9. Security & Configuration

### Authentication and authorization

| Host | Mode | Credential stored | Identity on the host |
|---|---|---|---|
| GitHub | GitHub App (manifest) | App ID, private key, client secret, installation ID | `<app-slug>[bot]` |
| GitLab | Project/group access token | Token | The token's bot user |
| GitLab | Personal access token | Token | The user |
| GitLab | OAuth | Access + refresh token, OAuth app client ID/secret | The user |

- All credentials go through the existing `SecretStore`; database rows hold only secret references.
- **GitHub App permissions:** Contents (write), Pull requests (write), Metadata (read). No
  `workflows`, so the bot can never change `.github/workflows`. No administration. Webhook disabled.
- **Host tokens are minted per proxy request** (GitHub installation tokens, restricted to the single
  repository, cached until near expiry) or loaded from the secret store (GitLab).
- **Proxy grants:** each run that checks out a repository gets an opaque random grant, stored hashed,
  bound to `{runId, botId, repositoryBindingId}` and expiring when the run ends or after a fixed
  maximum lifetime. The grant is the only secret in the sandbox and works only against the proxy.

### Push rules (enforced in `apps/api/src/git-proxy.ts`)

1. The grant is valid, its run is active, and the repository is still bound to the bot.
2. Every updated ref is `refs/heads/rakazo/<bot-slug>/…`.
3. Creates are allowed; updates must target a branch recorded as bot-owned and be fast-forwards
   (the proxy compares `<old>` to the host's current value); deletions and tags are refused.
4. **GitLab only:** if the push changes `.gitlab-ci.yml`, the push is refused unless approved (see
   Risk 3 for how the proxy detects this).
5. Every decision (allowed or refused, with refs) is written to the audit log.

### Commit authorship

- GitHub: `user.name = <app-slug>[bot]`, `user.email = <bot-user-id>+<app-slug>[bot]@users.noreply.github.com`.
- GitLab with a project/group token: the token's bot user.
- GitLab with OAuth or a personal token: author is the Rakazo bot's name with a no-reply address,
  committer is the connecting user, so history shows the bot did the work and who pushed it.

### Configuration

- No environment variables. Base URLs, auth mode and credentials are per-connection settings.
- The proxy's public URL is derived from the existing API base URL configuration.

### Security scope

- ✅ Branch, repository and lifetime limits enforced server-side
- ✅ No host credential inside the sandbox
- ✅ Audit trail for pushes and PR/MR creation
- ❌ Protecting CI secrets from code the bot pushes. A bot branch triggers CI, which on both hosts
  can read repository secrets. Documentation will recommend environments with required reviewers
  (GitHub) and protected variables (GitLab) for deploy secrets.
- ❌ Defending against prompt injection in repository content beyond the limits above

### Deployment considerations

- Migration is additive (new tables only), safe with the previous release running side by side.
- The bot computer must reach the API's proxy route; sandbox network policies need that host allowed.
- The proxy runs in every API instance; grants and branch ownership are in Postgres, so any instance
  can serve any request.

## 10. API Specification

Shapes are illustrative; final schemas live in `@rakazo/contracts`. All routes require a signed-in
user and act only on their own connections and bots.

### Connect GitHub

```http
POST /code-hosts/github/manifest
{ "baseUrl": "https://github.com", "owner": { "type": "org", "login": "acme" } }

200 { "postUrl": "https://github.com/organizations/acme/settings/apps/new?state=…",
      "manifest": { "name": "rakazo-docs-bot-3f9a", "url": "https://rakazo.example.com",
                    "redirect_url": "https://rakazo.example.com/code-hosts/github/callback",
                    "hook_attributes": { "active": false },
                    "default_permissions": { "contents": "write", "pull_requests": "write",
                                             "metadata": "read" },
                    "public": false } }
```

The web client posts the manifest form to `postUrl`. GitHub redirects to
`GET /code-hosts/github/callback?code=…&state=…`, which calls
`POST /app-manifests/{code}/conversions`, stores the credentials, and redirects to the app's install
page. GitHub then returns to `GET /code-hosts/github/installed?installation_id=…&state=…`.

### Connect GitLab

```http
POST /code-hosts/gitlab/token
{ "baseUrl": "https://gitlab.example.com", "token": "<placeholder>" }

200 { "connection": { "id": "chc_123", "provider": "gitlab", "label": "acme-bot", "authKind": "token" } }
422 { "error": "missing_scopes", "missing": ["write_repository"] }
```

```http
POST /code-hosts/gitlab/oauth/start
{ "baseUrl": "https://gitlab.example.com", "clientId": "<placeholder>", "clientSecret": "<placeholder>" }

200 { "authorizeUrl": "https://gitlab.example.com/oauth/authorize?…" }
```

Callback: `GET /code-hosts/gitlab/oauth/callback?code=…&state=…`.

### Connections and repositories

```http
GET    /code-hosts/connections
DELETE /code-hosts/connections/:id
GET    /code-hosts/connections/:id/repositories?query=docs
200 { "repositories": [ { "hostRepoId": "123", "fullPath": "acme/docs", "defaultBranch": "main" } ] }
```

### Bot bindings

```http
PUT /bots/:botId/repositories
{ "repositories": [ { "connectionId": "chc_123", "hostRepoId": "123" } ] }
200 { "repositories": [ { "id": "brb_1", "fullPath": "acme/docs", "host": "github" } ] }
```

### Git proxy (smart HTTP)

```http
GET  /git/:bindingId.git/info/refs?service=git-upload-pack|git-receive-pack
POST /git/:bindingId.git/git-upload-pack
POST /git/:bindingId.git/git-receive-pack
Authorization: Basic base64("rakazo:<proxy-grant>")
```

Refusal example (returned in the receive-pack report so git prints it):

```
remote: rakazo: bots can only push branches they created under rakazo/docs-bot/
 ! [remote rejected] HEAD -> main (rakazo policy)
```

### Provider contract (sketch)

```ts
export interface CodeHostProvider {
  provider: "github" | "gitlab";
  listRepositories(connection: CodeHostConnectionRef, query?: string): Promise<CodeHostRepository[]>;
  gitCredential(connection: CodeHostConnectionRef, repo: CodeHostRepository): Promise<GitCredential>;
  remoteUrl(connection: CodeHostConnectionRef, repo: CodeHostRepository): string;
  commitIdentity(connection: CodeHostConnectionRef, bot: BotRef): Promise<CommitIdentity>;
  openChangeRequest(connection: CodeHostConnectionRef, input: ChangeRequestInput): Promise<ChangeRequestResult>;
  revoke(connection: CodeHostConnectionRef): Promise<void>;
}
```

### Data model (additive)

```prisma
model CodeHostConnection {   // one connected GitHub App installation or GitLab account
  id, userId, spaceId, provider, baseUrl, authKind, label, secretId, metadata, createdAt, updatedAt
}
model BotRepository {        // a repository bound to a bot
  id, botId, connectionId, hostRepoId, fullPath, defaultBranch, createdAt
}
model BotRepositoryBranch {  // branches the bot created, and so may update
  id, botRepositoryId, ref, createdByRunId, createdAt   @@unique([botRepositoryId, ref])
}
model GitProxyGrant {        // per-run credential handed to the sandbox
  id, tokenHash, runId, botRepositoryId, expiresAt, createdAt
}
```

Whether `CodeHostConnection` should instead reuse the existing `Connection` model is decided in
Phase 1 (see Appendix).

## 11. Success Criteria

**MVP is successful when** a user on each supported host can go from no connection to an approved,
bot-authored PR/MR without touching a terminal, and no path exists for the bot to push outside its
own branches.

### Functional requirements
- ✅ GitHub connect works on github.com and GitHub Enterprise Server, for a personal account and an org
- ✅ GitLab connect works with OAuth and with a token, on gitlab.com and self-managed
- ✅ A bot can only clone, fetch and push repositories bound to it
- ✅ Pushes to the default branch, others' branches, tags and deletions are refused with a clear message
- ✅ Opening a PR/MR always shows an approval first and appears on the host with the bot's identity
  (GitHub, GitLab token mode) or bot-as-author (GitLab OAuth/personal token)
- ✅ Disconnecting revokes access within the current proxy request
- ✅ Repo tools are hidden when the bot has no computer

### Quality indicators
- Conformance suite passes for both adapters against offline emulators in CI
- Proxy push-policy tests cover every rule, including races (branch created concurrently on the host)
- No host token appears in sandbox environment, files, logs or run transcripts (asserted in tests)
- Second checkout of an unchanged repository does a fetch, not a clone

### User experience goals
- Connecting GitHub takes two confirmations on GitHub and no copy-pasted secrets
- Errors from the proxy read as normal git errors the bot can act on
- No new persistent UI beyond the connection, the repository picker and the approval card

## 12. Implementation Phases

Estimates assume one engineer familiar with the codebase.

### Phase 1 – Contract, data model, GitLab token path (≈1.5 weeks)
**Goal:** a bot can clone and fetch a GitLab repository through the proxy using a pasted token.
- ✅ `CodeHostProvider` contract and errors
- ✅ Prisma models and migration
- ✅ GitLab adapter: token validation, repository listing, credential
- ✅ Git proxy: grants, upload-pack passthrough, repository binding checks
- ✅ `code_repos` and `code_repo_checkout` tools
- ✅ Offline GitLab emulator (REST + `git http-backend`)

**Validation:** conformance and proxy tests pass offline; a manual clone from a dev sandbox works.

### Phase 2 – Push policy and change requests (≈1.5 weeks)
**Goal:** the bot pushes its own branches and opens an MR after approval.
- ✅ Receive-pack parsing and push rules, bot-owned branch tracking
- ✅ GitLab CI config change detection and approval
- ✅ `code_open_change_request` as an `ExternalEffect` with approval
- ✅ Audit events for push decisions and MR creation

**Validation:** policy tests for every rule; end-to-end offline test from chat to MR in the emulator.

### Phase 3 – GitHub App and GitLab OAuth (≈1.5 weeks)
**Goal:** GitHub parity and the OAuth option for GitLab.
- ✅ Manifest flow, conversion, install callback, JWT signing, installation tokens
- ✅ GitHub PR creation and commit identity
- ✅ GitLab OAuth with refresh
- ✅ GitHub emulator; both adapters in the shared conformance suite
- ✅ GitHub Enterprise Server and self-managed base URLs

**Validation:** conformance suite green for both hosts; manual run against real github.com and
gitlab.com test repositories.

### Phase 4 – UI on every surface and hardening (≈1.5 weeks)
**Goal:** shippable feature on web, desktop and mobile.
- ✅ Web/desktop: connect flows, bot repository picker, approval card details
- ✅ Mobile: native auth session for connect, native picker in bot settings
- ✅ Disconnect and revocation
- ✅ Web e2e test for the connect and bind screens; screenshot for the PR
- ✅ Docs: setup per host, CI secrets guidance

**Validation:** e2e in CI; manual check on iOS; PR description quotes and justifies new copy.

## 13. Future Considerations

- **Webhooks and the PR lifecycle:** review comments, CI results and the fix-and-push loop, with
  server-side checks that the commenter has write access before a run starts.
- **Instance-wide GitHub App** registered once by an admin, so users only click Install.
- **Pushing to a branch the user names**, behind approval, never default or protected branches.
- **Codebase memory:** an inspectable, editable record of what the bot learned about each repository.
- **Shared team spaces** where several people use one repo-bound bot, with roles for who can bind.
- **More hosts:** Bitbucket, Gitea/Forgejo, Azure DevOps on the same contract.
- **Evidence on PRs:** test output, screenshots or video of the bot's desktop attached to the PR body.

## 14. Risks & Mitigations

1. **Private GitHub Apps can only be installed on the account that owns them.** A user who registers
   the app on their personal account can't install it on their org's repositories.
   *Mitigation:* the connect flow asks where the repositories live and registers the app under that
   org (needs org owner or app manager rights); the error from GitHub is explained when it fails.

2. **Broad GitLab credentials.** OAuth and personal tokens reach every project the user can, so
   Rakazo's binding and proxy are the only limits.
   *Mitigation:* recommend project/group tokens in the token flow; proxy and binding checks get the
   heaviest test coverage; tokens are never sent to the sandbox.

3. **Detecting GitLab CI config changes at the proxy is non-trivial.** The pushed pack may not
   contain enough objects to diff against the parent.
   *Mitigation:* advertise `no-thin` so packs are self-contained, index the pack in a temporary
   directory, and compare the new root tree's `.gitlab-ci.yml` entry with the parent's (fetched via
   the GitLab tree API). Spike in Phase 2; if unreliable, require approval for every push on GitLab
   until solved.

4. **Prompt injection through repository content** (README, comments, issue text pasted in).
   *Mitigation:* the bot can't widen its own reach: repository binding, own-branch pushes, no
   `workflows` permission and the PR approval hold even if the model is manipulated.

5. **Per-user GitHub App keys multiply secrets.** Every user holds a private key.
   *Mitigation:* keys live in the `SecretStore`; disconnect deletes the key and tells the user how to
   delete the app on GitHub; a later instance-wide app reduces this.

## 15. Appendix

### Related documents
- [`docs/software-teams-research.md`](docs/software-teams-research.md) – competitor review and the
  repo-owning engineer bot direction
- `AGENTS.md` – provider-neutral adapters, UI copy rules, migration rules, concurrency rules

### Existing code to reuse
- `packages/adapter-kit/src/messaging-installations.ts` – install/exchange pattern to mirror
- `packages/adapters/src/slack-install-provider.ts` – a vendor install adapter
- `packages/adapters/src/computer-workspace.ts` – bot computer workspace paths
- `packages/adapters/src/github-webhook-emulator.ts` – starting point for the GitHub emulator
- `ExternalEffect` model and approval flow – PR/MR approval
- `SecretStore` – credential storage

### Open questions
- Reuse `Connection` (with a new `connectorId`) or add `CodeHostConnection`? Reuse is preferred if
  its fields fit without special cases.
- Should one GitHub App registration serve several installations (personal and org), or one app per
  installation?
- Exact maximum lifetime of a proxy grant for long-running tasks.

### Key external references
- GitHub: registering an app from a manifest – https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest
- GitHub: authenticating as an installation – https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/authenticating-as-a-github-app-installation
- GitLab: project access tokens – https://docs.gitlab.com/user/project/settings/project_access_tokens/
- GitLab: merge requests API – https://docs.gitlab.com/api/merge_requests/
- Git smart HTTP protocol – https://git-scm.com/docs/http-protocol
