# PRD: Code host integration (GitHub and GitLab)

Status: draft · October 2026 · Supersedes the "use the generic Git event and MCP paths" constraint in
[`docs/software-teams-research.md`](docs/software-teams-research.md) for repository access.

## 1. Executive Summary

Rakazo bots can already run commands on their own computer, but working in a real repository means
handing them a personal token through a generic MCP connector. Setup is fiddly, the generic tools are
unreliable, and the token ends up somewhere the bot can read it. This feature adds a native,
first-party integration with GitHub and GitLab so a bot can clone a repository, commit, push and open
a pull request (GitHub) or merge request (GitLab) as a normal part of a chat-started task.

The core value is a bot that works in your codebase like a careful teammate: its commits carry its
own name, it keeps a persistent clone on its computer, pushes only to branches it created, and
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
   all work, with each user bringing their own token (or, for GitLab, their own OAuth app).

## 3. Target Users

| Persona | Description | Technical comfort | Needs and pain points |
|---|---|---|---|
| **Self-hosting developer** | Runs Rakazo for themselves, wants a bot that fixes bugs and opens PRs in their own repos. | High | Wants setup in a couple of clicks, no MCP plumbing, no token sitting in the sandbox. |
| **Small team lead** | Uses Rakazo with a few teammates and an org on GitHub or a group on GitLab. | Medium to high | Needs bot changes to arrive as reviewable PRs, never as surprise pushes to `main`. |
| **Self-managed GitLab user** | Company runs GitLab on its own domain, often on the free tier. | Medium | Most agent products only support github.com; needs a base URL and a token option. |

## 4. MVP Scope

### Core Functionality
- ✅ Connect GitHub with a pasted access token (fine-grained or classic personal access token)
- ✅ Connect GitLab with OAuth (user-registered OAuth application) **or** a pasted access token (personal, project or group)
- ✅ Bind specific repositories to a bot from its settings
- ✅ Clone a bound repository onto the bot's computer, kept between runs and fetched on later runs
- ✅ Commit and push to branches the bot created under `rakazo/<bot>/…`
- ✅ On GitLab, every push needs the user's approval of the exact commit first
- ✅ Open a pull request (GitHub) or merge request (GitLab) after the user approves
- ❌ GitHub App registration (manifest flow) and installation tokens
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
- ❌ Webhooks of any kind
- ❌ Bitbucket, Gitea, Azure DevOps (the contract should not preclude them)
- ❌ Repository access through MCP for these hosts

### Deployment
- ✅ Works on every sandbox provider that gives a bot a computer with `git` and network access to the API
- ✅ Additive database migration only
- ❌ Any GitHub App (users bring their own token in v1)

## 5. User Stories

1. **As a developer, I want to connect GitHub by pasting one token, so that setup takes a minute
   instead of a tutorial.**
   *Example:* In Settings → Connections they choose GitHub, paste a fine-grained token limited to two
   repositories with Contents and Pull requests write access, and Rakazo validates it and lists the
   two repositories.

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
   with the PR title, body and diff summary. On approval the PR appears on GitHub, opened by the
   token's account, with commits authored by "docs-bot".

5. **As a team lead, I want the bot to never push to `main` or a teammate's branch, so that a
   confused or manipulated bot can't overwrite real work.**
   *Example:* The bot runs `git push origin HEAD:main`; the proxy rejects it with
   `rakazo: bots can only push branches they created under rakazo/docs-bot/`.

5b. **As a GitLab user, I want to approve each push before it reaches GitLab, so that a bot change to
   `.gitlab-ci.yml` (or anything else) can't run in our CI without me seeing it.**
   *Example:* The bot calls `code_request_push`; an approval card "Push to GitLab?" shows the branch,
   commits and diff stat. After approval, `git push` of exactly that commit succeeds; pushing any
   other commit is refused with `rakazo: GitLab pushes need approval; call code_request_push first`.

6. **As a developer, I want later tasks to reuse the bot's clone, so that work on a large repository
   doesn't start with a multi-minute clone every time.**
   *Example:* The second task in a week only runs `git fetch` before starting.

7. **As a user, I want disconnecting to really cut access, so that I can trust removing the
   integration.**
   *Example:* After disconnecting GitHub, the bot's next fetch fails at the proxy, and the
   connection's stored token is deleted.

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
   credential helper ──▶ proxy grant (per run, ends with run)    │
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
packages/adapters/src/github-code-host.ts      # GitHub adapter (token, repos, PRs)
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
- **Approvals through `ExternalEffect`.** Opening a PR/MR, and every GitLab push, is an external
  effect with an idempotency key, so it uses the existing approval cards, rules and audit on every
  surface.
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
enforcement point, and refusals come back as normal git errors.

**`code_request_push`** (GitLab repositories only) – ask the user to approve one push.
- Inputs: repository and a bot-owned (or new `rakazo/<bot>/…`) branch. The server reads the local
  branch's commit SHA, the commit subjects and a diff stat against the remote branch (or the default
  branch for a new branch) from the clone on the bot's computer.
- Requires approval; the card "Push to GitLab?" shows branch, commit subjects and diff stat.
- An approval allows exactly one push that sets that branch to that commit SHA during the same run.

**`code_open_change_request`** – open a pull request (GitHub) or merge request (GitLab).
- Inputs: repository, source branch (must be bot-owned), target branch (default: repository default),
  title, body, draft flag.
- Requires user approval via the existing approval flow; the card shows title, target and a diff
  summary (files changed, insertions, deletions) from the host's compare API.
- Returns the PR/MR URL and number.

### User-facing features

- **Connect GitHub** – base URL (default `https://github.com`, or a GitHub Enterprise Server URL)
  and a pasted fine-grained or classic personal access token.
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
| "Push to GitLab?" | Approval card title | The approval must say what it approves. |
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
- GitHub REST: `GET /user`, repositories, compare, pull requests (`/api/v3` prefix on Enterprise Server).
- GitLab REST v4: OAuth, `personal_access_tokens/self`, projects, compare, merge requests.

**Optional dependencies:** none. Because the adapters use plain `fetch`, nothing extra loads for
users who don't connect a code host.

## 9. Security & Configuration

### Authentication and authorization

| Host | Mode | Credential stored | Who opens the PR/MR | Commit author |
|---|---|---|---|---|
| GitHub | Fine-grained or classic personal access token | Token | The token's user | The bot |
| GitLab | Project/group access token | Token | The token's bot user | The token's bot user |
| GitLab | Personal access token | Token | The user | The bot |
| GitLab | OAuth | Access + refresh token, OAuth app client ID/secret | The user | The bot |

- All credentials go through the existing `SecretStore`; database rows hold only secret references.
- **GitHub token checks:** a classic token must have `repo` (or `public_repo`) and must not have
  `workflow`, `delete_repo` or any `admin:*` scope, so the bot can never change `.github/workflows`
  or administer repositories. Fine-grained tokens can't be inspected through the API; setup
  docs recommend Contents and Pull requests (write) and Metadata (read) only, on selected
  repositories, without Workflows.
- **GitLab token checks:** `api` and `write_repository` scopes are required.
- **Host tokens never leave the server.** The proxy loads the connection's token from the secret
  store per request (refreshing GitLab OAuth tokens near expiry).
- **Proxy grants:** each run that checks out a repository gets an opaque random grant, stored hashed,
  bound to `{runId, botId, repositoryBindingId}`. A grant has no timer of its own: it works only
  while its run is active and is deleted when the run completes, fails or is cancelled. The grant is
  the only secret in the sandbox and works only against the proxy.

### Push rules (enforced in `apps/api/src/git-proxy.ts`)

1. The grant is valid, its run is active, and the repository is still bound to the bot.
2. Every updated ref is `refs/heads/rakazo/<bot-slug>/…`.
3. Creates are allowed; updates must target a branch recorded as bot-owned and be fast-forwards
   (the proxy compares `<old>` to the host's current value); deletions and tags are refused.
4. **GitLab only:** every push needs an unused approval from `code_request_push` for the same run,
   repository, branch and new commit SHA; the approval is consumed when the push is forwarded.
5. Every decision (allowed or refused, with refs) is written to the audit log.

### Commit authorship

- GitHub, and GitLab with OAuth or a personal token: author is the Rakazo bot's name with a no-reply
  address (`<bot-slug>@bots.noreply.<rakazo-host>`), committer is the token's user, so history shows
  the bot did the work and who pushed it.
- GitLab with a project/group token: author and committer are the token's bot user.

### Configuration

- No new environment variables. Base URLs, auth mode and credentials are per-connection settings.
- The proxy's public URL is derived from the existing API base URL configuration.
- Self-hosted hosts on a private network reuse the deployment's existing private-endpoint escape.

### Security scope

- ✅ Branch, repository and run-lifetime limits enforced server-side
- ✅ No host credential inside the sandbox
- ✅ Audit trail for pushes and PR/MR creation
- ✅ No push reaches GitLab (and so GitLab CI) without the user's approval
- ❌ Protecting CI secrets from code the bot pushes to GitHub. A bot branch triggers CI, which can
  read repository secrets. Documentation will recommend environments with required reviewers
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
POST /code-hosts/github/token
{ "baseUrl": "https://github.com", "token": "<placeholder>" }

200 { "connection": { "id": "chc_123", "provider": "github", "label": "octocat", "authKind": "token" } }
422 { "error": "missing_scopes", "missing": ["repo"] }
422 { "error": "excess_scopes", "excess": ["workflow"] }
```

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
  connectToken(input: { baseUrl: string; token: string }): Promise<VerifiedCodeHostCredential>;
  listRepositories(connection: CodeHostConnectionRef, query?: string): Promise<CodeHostRepository[]>;
  gitCredential(connection: CodeHostConnectionRef): Promise<GitCredential>;
  remoteUrl(connection: CodeHostConnectionRef, repo: CodeHostRepository): string;
  commitIdentity(connection: CodeHostConnectionRef, bot: BotRef): CommitIdentity;
  compare(connection: CodeHostConnectionRef, input: CompareInput): Promise<CompareResult>;
  openChangeRequest(connection: CodeHostConnectionRef, input: ChangeRequestInput): Promise<ChangeRequestResult>;
  revoke?(connection: CodeHostConnectionRef): Promise<void>;
}
```

### Data model (additive)

```prisma
model CodeHostConnection {   // one connected GitHub or GitLab account (separate from `Connection`)
  id, userId, spaceId, provider, baseUrl, authKind, label, ciphertext, metadata, createdAt, updatedAt
}
model BotRepository {        // a repository bound to a bot
  id, botId, connectionId, hostRepoId, fullPath, defaultBranch, createdAt
}
model BotRepositoryBranch {  // branches the bot created, and so may update
  id, botRepositoryId, ref, createdByRunId, createdAt   @@unique([botRepositoryId, ref])
}
model GitProxyGrant {        // per-run credential handed to the sandbox; deleted when the run ends
  id, tokenHash, runId, botRepositoryId, createdAt
}
model GitPushApproval {      // one approved GitLab push: run + repository + branch + commit
  id, runId, botRepositoryId, ref, newSha, effectId, usedAt, createdAt
}
```

`CodeHostConnection` is its own table rather than a row in `Connection`: the run engine reads every
`Connection` row as a Composio-style app, so sharing the table would need exclusions in several paths.

## 11. Success Criteria

**MVP is successful when** a user on each supported host can go from no connection to an approved,
bot-authored PR/MR without touching a terminal, and no path exists for the bot to push outside its
own branches.

### Functional requirements
- ✅ GitHub connect works on github.com and GitHub Enterprise Server, for personal and org repositories the token can reach
- ✅ GitLab connect works with OAuth and with a token, on gitlab.com and self-managed
- ✅ A bot can only clone, fetch and push repositories bound to it
- ✅ Pushes to the default branch, others' branches, tags and deletions are refused with a clear message
- ✅ GitLab pushes are refused unless the exact commit was approved in the same run
- ✅ Opening a PR/MR always shows an approval first, with commits authored by the bot
- ✅ Disconnecting revokes access within the current proxy request
- ✅ Repo tools are hidden when the bot has no computer

### Quality indicators
- Conformance suite passes for both adapters against offline emulators in CI
- Proxy push-policy tests cover every rule, including races (branch created concurrently on the host)
- No host token appears in sandbox environment, files, logs or run transcripts (asserted in tests)
- Second checkout of an unchanged repository does a fetch, not a clone

### User experience goals
- Connecting GitHub takes one pasted token
- Errors from the proxy read as normal git errors the bot can act on
- No new persistent UI beyond the connection, the repository picker and the approval cards

## 12. Implementation Phases

Estimates assume one engineer familiar with the codebase.

### Phase 1 – Contract, data model, token connect (≈1.5 weeks)
**Goal:** a bot can clone and fetch a GitLab or GitHub repository through the proxy using a pasted token.
- ✅ `CodeHostProvider` contract and errors
- ✅ Prisma models and migration
- ✅ GitLab and GitHub adapters: token validation, repository listing, credential
- ✅ Git proxy: grants, upload-pack passthrough, repository binding checks
- ✅ `code_repos` and `code_repo_checkout` tools
- ✅ Offline emulators (REST + `git http-backend`) and the shared conformance suite

**Validation:** conformance and proxy tests pass offline; a manual clone from a dev sandbox works.

### Phase 2 – Push policy and change requests (≈1.5 weeks)
**Goal:** the bot pushes its own branches and opens a PR/MR after approval.
- ✅ Receive-pack parsing and push rules, bot-owned branch tracking
- ✅ GitLab push approvals (`code_request_push`)
- ✅ `code_open_change_request` as an `ExternalEffect` with approval
- ✅ Audit events for push decisions and PR/MR creation

**Validation:** policy tests for every rule; end-to-end offline test from chat to PR/MR in the emulator.

### Phase 3 – GitLab OAuth (≈0.5 weeks)
- ✅ GitLab OAuth with refresh; GitHub Enterprise Server and self-managed base URLs

### Phase 4 – UI on every surface and hardening (≈1.5 weeks)
**Goal:** shippable feature on web, desktop and mobile.
- ✅ Web/desktop: connect flows, bot repository picker
- ✅ Mobile: token connect, native auth session for GitLab OAuth, native picker in bot settings
- ✅ Disconnect and revocation
- ✅ Web e2e test for the connect and bind screens; screenshot for the PR
- ✅ Docs: setup per host, CI secrets guidance

**Validation:** e2e in CI; manual check on iOS; PR description quotes and justifies new copy.

## 13. Future Considerations

- **GitHub App connect** (manifest flow, installation tokens, `[bot]` identity), possibly as an
  instance-wide app registered once by an admin.
- **Webhooks and the PR lifecycle:** review comments, CI results and the fix-and-push loop, with
  server-side checks that the commenter has write access before a run starts.
- **Pushing to a branch the user names**, behind approval, never default or protected branches.
- **Codebase memory:** an inspectable, editable record of what the bot learned about each repository.
- **Shared team spaces** where several people use one repo-bound bot, with roles for who can bind.
- **More hosts:** Bitbucket, Gitea/Forgejo, Azure DevOps on the same contract.
- **Evidence on PRs:** test output, screenshots or video of the bot's desktop attached to the PR body.

## 14. Risks & Mitigations

1. **Fine-grained GitHub tokens can't be inspected.** Rakazo can't confirm a fine-grained token
   lacks Workflows or Administration permissions.
   *Mitigation:* setup docs and the token field point to fine-grained tokens with only the needed
   permissions; branch and binding limits hold at the proxy regardless.

2. **Broad credentials.** Classic GitHub tokens, GitLab OAuth and GitLab personal tokens reach every
   repository the user can, so Rakazo's binding and proxy are the only limits.
   *Mitigation:* recommend fine-grained (GitHub) and project/group (GitLab) tokens; proxy and
   binding checks get the heaviest test coverage; tokens are never sent to the sandbox.

3. **Approval fatigue on GitLab.** Every push needs its own approval.
   *Mitigation:* the card shows commit subjects and a diff stat so it is quick to judge; a later
   version may detect `.gitlab-ci.yml` changes and approve other pushes automatically.

4. **Prompt injection through repository content** (README, comments, issue text pasted in).
   *Mitigation:* the bot can't widen its own reach: repository binding, own-branch pushes, GitLab
   push approval and the PR approval hold even if the model is manipulated.

## 15. Appendix

### Related documents
- [`docs/software-teams-research.md`](docs/software-teams-research.md) – competitor review and the
  repo-owning engineer bot direction
- `AGENTS.md` – provider-neutral adapters, UI copy rules, migration rules, concurrency rules

### Existing code to reuse
- `packages/adapter-kit/src/messaging-installations.ts` – install/exchange pattern to mirror
- `packages/adapters/src/messaging-installations.ts` – OAuth state sessions (GitLab OAuth)
- `packages/adapters/src/cloud-agent-emulator.ts`, `mcp-emulator.ts` – wire and HTTP emulator patterns
- `packages/adapters/src/computer-support.ts` – bot computer workspace paths
- `ExternalEffect` model and approval flow – PR/MR and push approval
- `SecretStore` – credential storage

### Decisions
- Code-host connections get their own `CodeHostConnection` table.
- GitHub connects with a pasted token only in v1; the GitHub App flow is future work.
- Proxy grants last exactly as long as their run.
- Every GitLab push needs approval of the exact commit.

### Key external references
- GitHub: fine-grained personal access tokens – https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens
- GitLab: project access tokens – https://docs.gitlab.com/user/project/settings/project_access_tokens/
- GitLab: merge requests API – https://docs.gitlab.com/api/merge_requests/
- Git smart HTTP protocol – https://git-scm.com/docs/http-protocol
