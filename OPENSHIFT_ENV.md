# Rakazo on OpenShift: environment variables per deployment

Derived from `infra/compose/docker-compose.images.yml`. Every service uses the same app image
(`ghcr.io/elie222/rakazo/app`, mirror it internally); only the command differs.
Use placeholders below. Keep real values in Secrets, not in git.

| Deployment | Image command | Port |
| --- | --- | --- |
| migrate (Job, runs first) | `pnpm db:deploy` in `/app/apps/api` | none |
| api | `node --enable-source-maps dist/index.js` in `/app/apps/api` | 3100 |
| worker | `node --enable-source-maps dist/index.js` in `/app/apps/worker` | none |
| web | `node_modules/.bin/vite preview --host 0.0.0.0 --port 5173` in `/app/apps/web` | 5173 |

Bot computers are not a Deployment. The api and worker create one pod per computer in
`KUBERNETES_SANDBOX_NAMESPACE`.

## 1. migrate (Job)

| Variable | Value |
| --- | --- |
| `DATABASE_URL` | `postgres://rakazo_app:<APP_PASSWORD>@<pg-host>:5432/rakazo` |
| `DATABASE_MIGRATION_URL` | `postgres://<OWNER>:<OWNER_PASSWORD>@<pg-host>:5432/rakazo` (owner login, only this Job gets it) |
| `NODE_TLS_REJECT_UNAUTHORIZED` | `0` (only matters if Postgres uses TLS) |

## 2. api AND worker (shared block)

Set these on both, with identical values.

| Variable | Value | Notes |
| --- | --- | --- |
| `NODE_ENV` | `production` | |
| `NODE_EXTRA_CA_CERTS` | `/etc/corp-ca/ca.pem` | Preferred: mount your corporate root CA from a ConfigMap |
| `NODE_TLS_REJECT_UNAUTHORIZED` | `0` | Fallback only: Node TLS bypass, use instead of the CA |
| `DATABASE_URL` | `postgres://rakazo_app:<APP_PASSWORD>@<pg-host>:5432/rakazo` | App login, not the owner |
| `DATA_DIR` | `/data` | Mount a PVC here (ReadWriteMany if api and worker run on different nodes) |
| `ENCRYPTION_KEY` | 64 hex chars | `openssl rand -hex 32`. Losing it loses stored secrets |
| `CONTENT_ENCRYPTION` | `on` | |
| `WAKEUP_DRIVER` | `graphile` | |
| `AGENT_RUNTIME` | `pi` | |
| `API_URL` | `http://<api-service>:3100` | How worker and web reach the API |
| `SANDBOX_PROVIDER` | `kubernetes` | One pod per bot computer |
| `KUBERNETES_SANDBOX_NAMESPACE` | `rakazo-sandboxes` | Must exist; Role needs pods create/get/delete, pods/exec create/get |
| `KUBERNETES_SANDBOX_COMPUTER_IMAGE` | `<internal-registry>/rakazo/computer@sha256:<digest>` | Mirrored image |
| `SECRET_STORE` | `encrypted` | |
| `HTTP_PROXY` / `HTTPS_PROXY` / `NO_PROXY` | optional | Only if your network needs a proxy; also lowercase variants |

Model access on an offline network (pick what fits your endpoint):

| Variable | Value | Notes |
| --- | --- | --- |
| `RAKAZO_LOCAL_MODELS` | comma-separated model ids | Enables the local provider |
| `RAKAZO_LOCAL_MODELS_URL` | `http://<model-host>:<port>/v1` | OpenAI-compatible endpoint |
| `MCP_ALLOW_PRIVATE_ENDPOINT` | `true` | Needed for private-IP endpoints for non-owner users |
| `RAKAZO_OPENAI_COMPAT_PRIVATE_HOSTS` | your model hostname | When it resolves to private IPs |
| `RAKAZO_LIVE_MODEL_CATALOG` | `off` | Stops probing public catalogs |

Optional, set only when used: `KUBERNETES_SANDBOX_CPU_LIMIT`, `KUBERNETES_SANDBOX_MEMORY_LIMIT`,
`KUBERNETES_SANDBOX_RUNTIME_CLASS_NAME`, `KUBERNETES_SANDBOX_POD_LABELS`,
`KUBERNETES_SANDBOX_POD_ANNOTATIONS`, `KUBERNETES_SANDBOX_READY_TIMEOUT_MS`,
`KUBERNETES_SANDBOX_HOME_CLAIM` (+ `_HOME_COLOCATE_NAMESPACE`, `_HOME_COLOCATE_LABELS`),
`OBJECT_STORAGE_*`, `LOG_LEVEL`, `DB_POOL_MAX`.

Leave unset: `SANDBOX_SUPERVISOR_URL`, `SANDBOX_SUPERVISOR_TOKEN` (Docker only), `SMTP_URL`,
`EMAIL_PROVIDER`, `EMAIL_API_KEY`, `EMAIL_FROM`, `SIGNUP_ALLOWLIST`, analytics, Sentry, Stripe.

## 3. api only (add to the shared block)

| Variable | Value | Notes |
| --- | --- | --- |
| `API_HOST` | `0.0.0.0` | |
| `API_PORT` | `3100` | Optional, default |
| `BETTER_AUTH_SECRET` | 32+ random chars | |
| `BETTER_AUTH_URL` | `https://<route-host>` | The public Route URL |
| `WEB_ORIGIN` | `https://<route-host>` | Same Route URL |
| `AUTH_PASSWORD_ENABLED` | `true` | |
| `AUTH_USERNAME_DOMAIN` | `local.invalid` | Username-and-password signup: users type a username, stored as `<username>@local.invalid`. Needs no email provider. Usernames: 3 to 32 of `a-z 0-9 . _ -` |
| `SIGNUPS_ENABLED` | `true` | |
| `SIGNUP_ALLOWLIST` | empty | Non-empty forces email verification |
| `SCREEN_PROXY_SECRET` | 32+ random chars | Must equal web's value |
| `TRUSTED_PROXIES` | the OpenShift router's address or CIDR | So client IPs are read from `X-Forwarded-For` |
| `RAKAZO_ADMIN_EMAILS` | optional | Admin accounts, e.g. `alice@local.invalid` |

## 4. worker only (add to the shared block)

| Variable | Value |
| --- | --- |
| `GRAPHILE_WORKER_CONCURRENCY` | optional |

## 5. web

| Variable | Value | Notes |
| --- | --- | --- |
| `NODE_ENV` | `production` | |
| `NODE_TLS_REJECT_UNAUTHORIZED` | `0` | Applies to its proxy calls |
| `RAYON_NUM_THREADS` | `4` | Keeps thread count fixed |
| `API_PROXY_TARGET` | `http://<api-service>:3100` | |
| `RAKAZO_HOST` | `<route-host>` | |
| `SCREEN_PROXY_SECRET` | same as api | |
| `RAKAZO_IMAGE_TAG` | image tag in use | |

## 6. Bot computer pods

No env vars come from the API except display and cache settings, so TLS trust is set in a derived
computer image built from `infra/sandboxes/computer`.

### Preferred: install the corporate root CA (verification stays on)

- System store (curl, git, apt, Go, most tools): copy the CA to
  `/usr/local/share/ca-certificates/corp-ca.crt`, then run `update-ca-certificates`.
- Node: `ENV NODE_EXTRA_CA_CERTS=/usr/local/share/ca-certificates/corp-ca.crt`.
- pip and Python requests: `ENV PIP_CERT=/etc/ssl/certs/ca-certificates.crt` and
  `ENV REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt`.
- Chrome reads NSS, not the system store. Add the CA to each home at start or in the home template:
  `certutil -d sql:$HOME/.pki/nssdb -A -t "C,," -n corp -i corp-ca.crt`.
- Java, if bots use it: `keytool -importcert` into its keystore.

The sandbox allowlist already forwards `NODE_EXTRA_CA_CERTS`, `SSL_CERT_FILE`, `SSL_CERT_DIR`,
`REQUESTS_CA_BUNDLE`, `CURL_CA_BUNDLE` and `GIT_SSL_CAINFO` into bot commands.

### Fallback: disable verification (only for a cert that cannot be fixed)

Ready-made: `infra/openshift/Dockerfile.computer` sets `NODE_TLS_REJECT_UNAUTHORIZED=0` and
`GIT_SSL_NO_VERIFY=true`; `infra/openshift/Dockerfile.app` sets the Node variable for api, worker and web.
Build each with `--build-arg BASE=<your mirrored image>`, push, and point the Deployments and
`KUBERNETES_SANDBOX_COMPUTER_IMAGE` at the result.

NODE_TLS_REJECT_UNAUTHORIZED and GIT_SSL_NO_VERIFY are blocked as bot secrets on purpose, so they
must come from the image. Other tools have their own switches:

| Tool | Setting |
| --- | --- |
| Node | `ENV NODE_TLS_REJECT_UNAUTHORIZED=0` |
| git | `ENV GIT_SSL_NO_VERIFY=true` |
| Browser | `--ignore-certificate-errors` in `infra/sandboxes/computer/rakazo-browser` (the policy file cannot do it) |
| curl | `insecure` in `/etc/curlrc` |
| pip | `ENV PIP_TRUSTED_HOST=<index hosts>` |
| npm / pnpm | `ENV NPM_CONFIG_STRICT_SSL=false` |
| apt | `Acquire::https::Verify-Peer "false";` in `/etc/apt/apt.conf.d/` |
| Go, Java, Rust | no global switch; use the CA |

Verify any of these reaches commands on a real pod before relying on it.

### Outside the pods

- Postgres: `?sslmode=no-verify` in `DATABASE_URL`, or `sslrootcert` with the CA.
- Model endpoint: use an internal HTTPS or private-IP URL; HTTP to a public host with an API key is refused.
- Kubernetes API: the in-cluster service account CA is used automatically.

## Secrets to generate

`ENCRYPTION_KEY`, `BETTER_AUTH_SECRET`, `SCREEN_PROXY_SECRET`, and the two Postgres passwords.
Use independent random values for each.
