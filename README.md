# deno-pg4e

Self-hosted Deno applications for [PostgreSQL for Everybody](https://www.pg4e.com/) (PG4E).

This repository documents the installation, configuration, deployment, and maintenance of Deno applications on Ubuntu using Apache, systemd, and local Deno KV.

The goal is to replace Deno Deploy with a simple, self-managed installation while preserving the existing PG4E student assignments and APIs.

## Background

In October 2026, Deno announced plans to discontinue Deno Deploy and eventually end official development of the Deno runtime.

PG4E uses Deno to teach non-relational database concepts, particularly through Deno KV.

Earlier versions of the course allowed students to deploy applications to Deno Deploy, but that requirement was removed. Students now communicate with centrally hosted APIs.

This makes self-hosting straightforward. There is no need to reproduce Deno Deploy's deployment management or serverless infrastructure.

The existing applications can run as ordinary HTTP servers behind Apache.

## Architecture

```text
PG4E Students
      |
      | HTTPS
      v
Apache 2.4
      |
      +---- dnx.pg4e.com ------> localhost:8000
      |                           Hello World
      |
      +---- hono.pg4e.com -----> localhost:8001
      |                           deno2-hono
      |
      +---- KV Admin domains --> localhost:8003
                                  deno2-kv-admin
                                        |
                                        v
                                  Deno KV / SQLite
```

Each application runs as an independent systemd service.

Apache handles HTTPS, virtual hosts, and reverse proxying. Deno handles application logic and database operations.

### Port assignments

| Port | Application | systemd service |
|---|---|---|
| 8000 | Hello World | `deno-pg4e` |
| 8001 | deno2-hono | `deno2-hono` |
| 8002 | Reserved | — |
| 8003 | deno2-kv-admin | `deno2-kv-admin` |

All applications bind to `127.0.0.1` and are exposed publicly only through Apache.

## Repository Structure

```text
deno-pg4e/
    README.md
    apache/
        dnx.pg4e.com.conf
    systemd/
        deno-pg4e.service
    examples/
        hello.ts
    scripts/
        test-kv.sh
```

This repository contains deployment documentation, Apache configuration, systemd definitions, and test scripts.

Application source code is maintained in separate GitHub repositories.

Additional systemd and Apache configuration files will be added as each application is successfully migrated.

## Tested Environment

Initial installation: November 3, 2026.

| Component | Configuration |
|---|---|
| Infrastructure | AWS EC2 |
| Operating system | Ubuntu 18.04 |
| CPU | x86_64 |
| glibc | 2.27 |
| Deno | 2.9.8 |
| V8 | 15.0.245.2-rusty |
| TypeScript | 6.0.3 |
| Apache | 2.4.43 |
| Public hostname | dnx.pg4e.com |
| Public IP at testing | 3.101.11.254 |

The initial installation successfully demonstrated Deno, Deno KV, HTTP serving, Apache reverse proxying, DNS, and HTTPS.

The two production application migrations are documented below as subsequent steps.

# Part 1 — Installing the Deno Runtime

## 1. Install Deno

Deno 2.9.8 has been preserved in a separate repository:

[github.com/csev/deno-archive](https://github.com/csev/deno-archive)

The archive contains precompiled binaries for:

- Linux x86_64
- Linux ARM64
- macOS Intel
- macOS Apple Silicon

For the Ubuntu x86_64 server, obtain:

`deno-x86_64-unknown-linux-gnu.zip`

Extract and install the executable:

```bash
unzip deno-x86_64-unknown-linux-gnu.zip
sudo install -m 755 deno /usr/local/bin/deno
```

Verify:

```bash
deno --version
```

Expected:

```text
deno 2.9.8 (stable, release, x86_64-unknown-linux-gnu)
v8 15.0.245.2-rusty
typescript 6.0.3
```

The original Deno installer was also tested:

```bash
curl -fsSL https://deno.land/install.sh | sh
```

However, the installer depends on upstream download infrastructure. The archived binary is preferred for long-term reproducibility.

## 2. Test Deno KV

Deno KV can use local SQLite-backed persistent storage.

Run:

```bash
deno eval --unstable-kv 'const kv = await Deno.openKv("/tmp/test.kv"); await kv.set(["hello"], "world"); console.log((await kv.get(["hello"])).value); kv.close();'
```

Expected:

```text
world
```

Alternatively, use the repository test script:

```bash
bash scripts/test-kv.sh
```

This confirms that Deno KV works without Deno Deploy.

# Part 2 — Hello World HTTP Server

The first goal is to establish a working Deno HTTP application on port 8000 before introducing the production applications.

## 3. Run Hello World interactively

The example application is in:

`examples/hello.ts`

Run:

```bash
deno run --allow-net=127.0.0.1:8000 examples/hello.ts
```

In another terminal:

```bash
curl http://127.0.0.1:8000/
```

Expected:

```text
Hello from PG4E Deno!
```

Stop the interactive server with Ctrl+C before moving it under systemd.

## 4. Configure Apache

Enable Apache proxy modules:

```bash
sudo a2enmod proxy proxy_http
sudo apache2ctl configtest
```

If Apache is running, reload it:

```bash
sudo systemctl reload apache2
```

If Apache is inactive, first investigate whether another server is using ports 80 or 443. On the original EC2 installation, Apache was inactive and was started using:

```bash
sudo systemctl start apache2
```

Create a virtual host using `vi`:

```bash
sudo vi /etc/apache2/sites-available/deno.pg4e.com.conf
```

Initial configuration:

```apache
<VirtualHost *:80>
    ServerName dnx.pg4e.com

    ProxyPreserveHost On
    ProxyRequests Off

    ProxyPass / http://127.0.0.1:8000/
    ProxyPassReverse / http://127.0.0.1:8000/

    ErrorLog ${APACHE_LOG_DIR}/deno-error.log
    CustomLog ${APACHE_LOG_DIR}/deno-access.log combined
</VirtualHost>
```

Enable the site:

```bash
sudo a2ensite deno.pg4e.com.conf
sudo apache2ctl configtest
sudo systemctl reload apache2
```

Test locally:

```bash
curl -H "Host: dnx.pg4e.com" http://127.0.0.1/
```

Expected:

```text
Hello from PG4E Deno!
```

The configuration filename can differ from the hostname. The `ServerName` directive determines which hostname Apache handles.

## 5. Configure DNS

DNS is managed through DreamHost.

The initial A record was:

```text
Host:  dnx.pg4e.com
Type:  A
Value: 3.101.11.254
```

Verify the EC2 public IP before reusing this configuration.

Check the authoritative DNS server:

```bash
dig @ns1.dreamhost.com dnx.pg4e.com A +short
```

Check public resolvers:

```bash
dig @1.1.1.1 dnx.pg4e.com A +short
dig @8.8.8.8 dnx.pg4e.com A +short
```

All three returned the correct address on November 3, 2026.

No separate DreamHost-hosted website is needed.

## 6. Configure HTTPS

Install or use the existing Certbot installation:

```bash
sudo certbot --apache -d dnx.pg4e.com
```

Choose the HTTP-to-HTTPS redirect option.

Certbot created:

```text
/etc/apache2/sites-available/deno.pg4e.com-le-ssl.conf
```

The certificate is stored under:

```text
/etc/letsencrypt/live/dnx.pg4e.com/
```

The original certificate expires February 1, 2027.

Test renewal:

```bash
sudo certbot renew --dry-run
```

Verify the public endpoint:

```bash
curl -i https://dnx.pg4e.com/
```

The original test returned HTTP 200 and:

```text
Hello from PG4E Deno!
```

Do not commit private keys or Certbot-generated SSL credentials to Git.

## 7. Run Hello World under systemd

The Hello World application should run independently of an SSH session and restart automatically after failures or reboots.

Use this layout:

```text
/opt/deno-pg4e/          Hello World application
/var/lib/deno-pg4e/      Persistent application data
/etc/systemd/system/     Service definitions
```

Create a dedicated service account if it does not already exist:

```bash
sudo useradd --system \
    --home /var/lib/deno-pg4e \
    --shell /usr/sbin/nologin \
    deno-pg4e
```

Create directories:

```bash
sudo install -d -o root -g root -m 755 /opt/deno-pg4e

sudo install -d -o deno-pg4e -g deno-pg4e \
    -m 750 /var/lib/deno-pg4e
```

Install the Hello World application:

```bash
sudo install -m 644 examples/hello.ts /opt/deno-pg4e/main.ts
```

Create the systemd service using `vi` or install the supplied service template after verifying its paths and permissions:

```bash
sudo vi /etc/systemd/system/deno-pg4e.service
```

Service definition:

```ini
[Unit]
Description=PG4E Deno Hello World
After=network.target

[Service]
Type=simple
User=deno-pg4e
Group=deno-pg4e
WorkingDirectory=/opt/deno-pg4e

ExecStart=/usr/local/bin/deno run --allow-net=127.0.0.1:8000 /opt/deno-pg4e/main.ts

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Make sure no interactive Deno process is still using port 8000:

```bash
sudo ss -ltnp | grep :8000
```

Then enable and start the service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now deno-pg4e
sudo systemctl status deno-pg4e --no-pager
```

Test both direct and proxied access:

```bash
curl http://127.0.0.1:8000/
curl https://dnx.pg4e.com/
```

Useful maintenance commands:

```bash
sudo systemctl restart deno-pg4e
sudo systemctl status deno-pg4e --no-pager
sudo journalctl -u deno-pg4e -f
```

At this point, Hello World should survive SSH disconnects and machine reboots.

Keep this service as a permanent diagnostic endpoint while migrating the other applications.

# Part 3 — Deploying the Real Applications

The next step is to check out the application source code and independently verify each application before creating its systemd service.

Both applications are already stored in GitHub.

## 8. Clone the application repositories

Clone the repositories into `/opt`:

```bash
cd /opt

sudo git clone https://github.com/csev/deno2-hono.git
sudo git clone https://github.com/csev/deno2-kv-admin.git
```

This creates:

```text
/opt/deno2-hono/
/opt/deno2-kv-admin/
```

The repositories contain application source code, not deployment secrets or databases.

For production operation, use dedicated unprivileged service accounts and ensure they can read application files.

A practical approach is to keep the Git checkouts owned by root and provide separate writable data directories for each service.

## 9. Inspect the application configurations

Before starting either application, inspect:

```bash
cd /opt/deno2-hono

cat deno.json
ls -la
```

Then:

```bash
cd /opt/deno2-kv-admin

cat deno.json
ls -la
```

Determine:

- Which TypeScript file is the entrypoint.
- Whether `deno task` commands exist.
- Which environment variables are required.
- Whether the code uses Deno Deploy-specific APIs.
- Whether any dependencies require network access.
- How each application selects its listening port.
- Whether KV storage needs a fixed local path.

The production services should not be started until these requirements are understood.

## 10. Run deno2-hono on port 8001

Repository:

[github.com/csev/deno2-hono](https://github.com/csev/deno2-hono)

Existing endpoints:

- `https://deno2-hono.csev.deno.net`
- `https://hono.pg4e.com`

Configure the application to listen on:

```text
127.0.0.1:8001
```

If its entrypoint uses `Deno.serve()`, the server should use something equivalent to:

```typescript
const hostname = Deno.env.get("HOST") ?? "127.0.0.1";
const port = Number(Deno.env.get("PORT") ?? "8001");

Deno.serve({ hostname, port }, app.fetch);
```

This is a suggested adaptation, not a claim about the application's current source code. It requires `--allow-env=HOST,PORT` when using these environment variables.

Run the application interactively using the actual entrypoint and permissions identified in `deno.json`.

For example, if the entrypoint is `main.ts` and the code supports these environment variables:

```bash
cd /opt/deno2-hono

HOST=127.0.0.1 PORT=8001 \
    deno run --allow-net=127.0.0.1:8001 \
    --allow-env=HOST,PORT main.ts
```

Add any permissions required by the real application.

Verify:

```bash
curl -i http://127.0.0.1:8001/
```

Test the application's actual API routes, not just its root path.

Only proceed after the application is working locally.

## 11. Add systemd for deno2-hono

Create a dedicated service account:

```bash
sudo useradd --system \
    --home /var/lib/deno2-hono \
    --shell /usr/sbin/nologin \
    deno2-hono

sudo install -d -o deno2-hono -g deno2-hono \
    -m 750 /var/lib/deno2-hono
```

Create:

```bash
sudo vi /etc/systemd/system/deno2-hono.service
```

Service template:

```ini
[Unit]
Description=PG4E Deno Hono Application
After=network.target

[Service]
Type=simple
User=deno2-hono
Group=deno2-hono
WorkingDirectory=/opt/deno2-hono

Environment=HOST=127.0.0.1
Environment=PORT=8001
Environment=DENO_DIR=/var/lib/deno2-hono/cache

ExecStart=/usr/local/bin/deno run --allow-net=127.0.0.1:8001 --allow-env=HOST,PORT,DENO_DIR /opt/deno2-hono/main.ts

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

The `ExecStart` line is a starting template. Adjust the entrypoint, permissions, environment variables, and dependency access to match the tested application. Populate and test the dependency cache under the service account before relying on offline operation.

Stop the interactive Hono process before activating systemd.

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now deno2-hono
sudo systemctl status deno2-hono --no-pager
```

Verify:

```bash
curl -i http://127.0.0.1:8001/
```

Inspect logs if necessary:

```bash
sudo journalctl -u deno2-hono -n 50 --no-pager
```

Once Hono works under systemd, create an Apache HTTPS virtual host for `hono.pg4e.com` with:

```apache
ProxyPass / http://127.0.0.1:8001/
ProxyPassReverse / http://127.0.0.1:8001/
```

Reuse the existing domain only after validating the new service.

# Part 4 — Deploying KV Admin

## 12. Prepare deno2-kv-admin

Repository:

[github.com/csev/deno2-kv-admin](https://github.com/csev/deno2-kv-admin)

Existing endpoints:

- `https://deno2-kv-admin.csev.deno.net`
- `https://deno2.pg4e.com`
- `https://deno.pg4e.com`
- `https://kv-admin-api.pg4e.com`

The local service will listen on:

```text
127.0.0.1:8003
```

KV Admin requires additional migration work because it uses persistent data and signed-token authentication.

Before starting it, examine the current source to determine:

- How its Deno KV database is opened.
- How its current database is organized.
- Which environment variables it expects.
- How it validates authentication tokens.
- Whether existing hosted KV records need to be exported.
- Whether Deno Deploy-specific functionality must be replaced.

In particular, preserve the correct `KV_TOKEN_SECRET` securely.

Do not use development fallback secrets in production.

## 13. Configure persistent KV storage

Create a dedicated application account:

```bash
sudo useradd --system \
    --home /var/lib/deno2-kv-admin \
    --shell /usr/sbin/nologin \
    deno2-kv-admin
```

Create persistent storage:

```bash
sudo install -d -o deno2-kv-admin -g deno2-kv-admin \
    -m 750 /var/lib/deno2-kv-admin
```

An example local KV database path is:

```text
/var/lib/deno2-kv-admin/admin.kv
```

The application can open it using:

```typescript
const kv = await Deno.openKv(
    "/var/lib/deno2-kv-admin/admin.kv"
);
```

The actual code may require adapting its existing `Deno.openKv()` call.

Keep database files outside the Git repository.

If using an environment variable such as `KV_PATH`, implement and test that behavior explicitly in the application.

Before changing any existing production database, determine whether a data export is required.

## 14. Run deno2-kv-admin interactively

After configuring its entrypoint, port, environment variables, authentication, and database location, run KV Admin manually on:

```text
127.0.0.1:8003
```

Use the actual command and permissions required by its source code.

Verify connectivity:

```bash
curl -i http://127.0.0.1:8003/
```

An HTTP 401 or 403 response may be expected for an authenticated API route.

The important checks are that the process listens successfully, the correct authentication behavior is enforced, and the API works with the PG4E clients.

Test representative read and write operations against a test KV database before connecting production data.

## 15. Add systemd for deno2-kv-admin

Once the interactive version works, create:

```bash
sudo vi /etc/systemd/system/deno2-kv-admin.service
```

Use the following starting template:

```ini
[Unit]
Description=PG4E Deno KV Admin API
After=network.target

[Service]
Type=simple
User=deno2-kv-admin
Group=deno2-kv-admin
WorkingDirectory=/opt/deno2-kv-admin

Environment=HOST=127.0.0.1
Environment=PORT=8003
Environment=DENO_DIR=/var/lib/deno2-kv-admin/cache

EnvironmentFile=/etc/deno2-kv-admin.env

ExecStart=/usr/local/bin/deno run --unstable-kv --allow-net=127.0.0.1:8003 --allow-env=HOST,PORT,DENO_DIR,KV_TOKEN_SECRET,KV_PATH /opt/deno2-kv-admin/main.ts

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

This template assumes the application has been adapted to read `HOST`, `PORT`, and optionally `KV_PATH`. Adjust the entrypoint and permissions after inspecting the real application.

Create a root-owned environment file:

```bash
sudo vi /etc/deno2-kv-admin.env
```

It should contain the actual production configuration, for example:

```text
KV_TOKEN_SECRET=<production-secret>
KV_PATH=/var/lib/deno2-kv-admin/admin.kv
```

Do not commit that file or its contents to Git.

Restrict access:

```bash
sudo chown root:root /etc/deno2-kv-admin.env
sudo chmod 600 /etc/deno2-kv-admin.env
```

systemd reads the environment file as part of starting the service.

Deno KV itself requires the `--unstable-kv` flag. Add any other Deno permissions required by the application, and ensure the source code uses the configured KV path.

After testing:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now deno2-kv-admin
sudo systemctl status deno2-kv-admin --no-pager
```

Verify the service:

```bash
curl -i http://127.0.0.1:8003/
```

Inspect logs:

```bash
sudo journalctl -u deno2-kv-admin -n 50 --no-pager
```

After verifying the API, configure an Apache reverse proxy for its public hostnames using:

```apache
ProxyPass / http://127.0.0.1:8003/
ProxyPassReverse / http://127.0.0.1:8003/
```

Do not switch existing production domains until authentication, database operations, and course assignments have been tested.

# Part 5 — Production Cutover

## 16. Final service layout

Once all services are working:

```text
/opt/
    deno-pg4e/
        main.ts
    deno2-hono/
        main.ts
        deno.json
        ...
    deno2-kv-admin/
        main.ts
        deno.json
        ...

/var/lib/
    deno-pg4e/
    deno2-hono/
    deno2-kv-admin/
        admin.kv

/etc/systemd/system/
    deno-pg4e.service
    deno2-hono.service
    deno2-kv-admin.service
```

The actual entrypoint filenames and application-specific files should reflect the checked-out repositories.

Check all listeners:

```bash
sudo ss -ltnp | grep -E ':(8000|8001|8003)\b'
```

Expected:

```text
127.0.0.1:8000  Hello World
127.0.0.1:8001  Hono
127.0.0.1:8003  KV Admin
```

There should be no public listener on these ports.

Apache provides public HTTPS access.

## 17. Migrate production traffic

Keep the original Deno Deploy applications running during testing.

For each application:

1. Confirm the service runs under systemd.
2. Verify Apache forwarding and HTTPS.
3. Confirm authentication and authorization.
4. Test the relevant PG4E assignments and autograders.
5. Determine whether hosted Deno KV data must be transferred.
6. Migrate data using a process that prevents lost writes.
7. Switch the public hostname to the new server.
8. Monitor service logs and API errors.
9. Retain the old service temporarily for rollback.
10. Retire Deno Deploy only after a successful migration.

Preserve existing public API URLs wherever possible.

This minimizes changes to student code and course materials.

For KV Admin, use a consistent database backup strategy and plan a final write freeze or equivalent synchronization mechanism during cutover.

## 18. Operations

### Service status

```bash
sudo systemctl status deno-pg4e --no-pager
sudo systemctl status deno2-hono --no-pager
sudo systemctl status deno2-kv-admin --no-pager
```

### Restart services

```bash
sudo systemctl restart deno-pg4e
sudo systemctl restart deno2-hono
sudo systemctl restart deno2-kv-admin
```

### Inspect logs

```bash
sudo journalctl -u deno-pg4e -n 50 --no-pager
sudo journalctl -u deno2-hono -n 50 --no-pager
sudo journalctl -u deno2-kv-admin -n 50 --no-pager
```

### Verify HTTP listeners

```bash
curl -i http://127.0.0.1:8000/
curl -i http://127.0.0.1:8001/
curl -i http://127.0.0.1:8003/
```

The production services may require API paths or authorization headers rather than `/`.

### Update application source

After reviewing upstream changes, update each application independently:

```bash
cd /opt/deno2-hono
sudo git pull --ff-only
sudo systemctl restart deno2-hono
```

And:

```bash
cd /opt/deno2-kv-admin
sudo git pull --ff-only
sudo systemctl restart deno2-kv-admin
```

Run any required tests and dependency-cache preparation before restarting a production service.

## 19. Security and Backups

The self-hosted deployment should follow these practices:

- Run each application as an unprivileged account.
- Bind Deno HTTP listeners to localhost.
- Terminate public HTTPS traffic in Apache.
- Keep secrets outside public repositories.
- Give each service only the Deno permissions it requires.
- Store KV databases on persistent storage.
- Back up KV databases consistently, including any required SQLite journal files or snapshots.
- Preserve Deno runtime binaries and application lockfiles.
- Monitor systemd and Apache logs.
- Test after software updates.
- Review authentication before switching production endpoints.

Ubuntu 18.04 is beyond its standard security maintenance period. Appropriate extended security maintenance or an eventual operating system upgrade is recommended.

The archived Deno runtime provides reproducibility, but does not automatically receive security updates.

# Deployment Checklist

## Phase 1 — Runtime and infrastructure

- [x] Install Deno 2.9.8
- [x] Verify runtime on Ubuntu 18.04
- [x] Test local Deno KV
- [x] Run Hello World on port 8000
- [x] Enable Apache proxy modules
- [x] Configure `dnx.pg4e.com` virtual host
- [x] Configure DreamHost DNS
- [x] Install Let's Encrypt certificate
- [x] Verify public HTTPS endpoint
- [ ] Verify automated certificate renewal

## Phase 2 — Hello World systemd

- [ ] Install application under `/opt/deno-pg4e`
- [ ] Create or verify unprivileged service account
- [ ] Install systemd service
- [ ] Stop interactive port 8000 process
- [ ] Verify service starts and restarts
- [ ] Confirm HTTPS still works
- [ ] Verify service survives a reboot

## Phase 3 — Clone applications

- [ ] Clone `deno2-hono`
- [ ] Clone `deno2-kv-admin`
- [ ] Inspect application entrypoints
- [ ] Inspect environment variables and dependencies

## Phase 4 — Hono

- [ ] Configure localhost port 8001
- [ ] Run Hono interactively
- [ ] Verify API routes
- [ ] Add Hono systemd service
- [ ] Test service restart
- [ ] Configure Apache virtual host
- [ ] Verify HTTPS
- [ ] Test course clients

## Phase 5 — KV Admin

- [ ] Configure localhost port 8003
- [ ] Configure persistent KV storage
- [ ] Preserve production authentication secret
- [ ] Determine hosted KV migration requirements
- [ ] Run KV Admin interactively
- [ ] Verify token authentication
- [ ] Verify KV reads and writes
- [ ] Add KV Admin systemd service
- [ ] Configure Apache virtual host
- [ ] Test PG4E assignments
- [ ] Establish KV backups

## Phase 6 — Cutover

- [ ] Migrate required production data
- [ ] Switch existing API hostnames
- [ ] Monitor requests and errors
- [ ] Confirm student assignments work
- [ ] Confirm database backups
- [ ] Retire old Deno Deploy applications

# Related Repositories

| Repository | Purpose |
|---|---|
| [csev/deno](https://github.com/csev/deno) | Archived Deno runtime source |
| [csev/deno_install](https://github.com/csev/deno_install) | Archived installation scripts |
| [csev/deno-archive](https://github.com/csev/deno-archive) | Deno 2.9.8 executable archives |
| [csev/deno-pg4e](https://github.com/csev/deno-pg4e) | Server deployment and operations |
| [csev/deno2-hono](https://github.com/csev/deno2-hono) | Hono application |
| [csev/deno2-kv-admin](https://github.com/csev/deno2-kv-admin) | KV administration/API application |

# About

Maintained by Dr. Charles R. Severance as part of the [PostgreSQL for Everybody](https://www.pg4e.com/) project.

Initial self-hosting work: November 3, 2026.

The purpose of this repository is to preserve a reproducible deployment process and maintain control over the infrastructure supporting PG4E, independently of the long-term availability of Deno Deploy.