# Testing a running app

How an agent starts Rakazo locally and checks behavior end to end. Unit and Postgres tests are
described in [CONTRIBUTING.md](CONTRIBUTING.md).

## Start the app

```bash
cp -n .env.example .env   # once; see README "Local development" for the required secrets
pnpm install
EMAIL_EMULATOR=true pnpm dev
```

`pnpm dev` starts Postgres (Docker), applies migrations, and runs the API, worker, web app and
sandbox supervisor. The web app is at `http://127.0.0.1:5173` unless the default ports are taken;
then `pnpm dev` prints the URL it chose. Use that origin for everything below.

## Accounts

Create test accounts through the auth API. Use fresh addresses on `@rakazo.test` and any password
of 12 or more characters; never use real addresses or real passwords.

```bash
curl -c a.jar -X POST "$WEB/api/auth/sign-up/email" \
  -H "origin: $WEB" -H 'content-type: application/json' \
  -d '{"email":"a-<random>@rakazo.test","password":"<test-password>","name":"Dana"}'
```

Keep one cookie jar per user. Sign-up creates the user's personal organization and default space.

## Calling the API

Every product call is an oRPC procedure at `POST $WEB/rpc/<path>` with the body wrapped in
`json`, for example `spaces/list` or `bots/list`:

```bash
curl -b a.jar -X POST "$WEB/rpc/spaces/list" -H 'content-type: application/json' -d '{"json":{}}'
```

The active space is the `x-rakazo-space-id` header; without it the user's default space is used.
A user who is not a member of the requested space gets 401.

## Email

With `EMAIL_EMULATOR=true` and no email provider configured, sent mail is captured in memory and
listed at `GET $WEB/api/dev/emails` (JSON array of `{ to, subject, text, html }`).

## Models

Without model credentials, bots cannot answer. Tests that need a reply should check that the user
message and run were recorded rather than the reply text, unless `OPENROUTER_API_KEY` or another
provider is configured in `.env`.

## UI

Open `$WEB/sign-in` in a browser and sign in with a test account. The web e2e helpers in
`apps/web/e2e/helpers.ts` (`signup`, `rpc`, `captureScreenshot`) show the flows Playwright uses.
Do not run the desktop Playwright suite locally; it steals focus.
