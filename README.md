# deno-pg4e

Self-hosting Deno applications for [PostgreSQL for Everybody](https://www.pg4e.com/) (PG4E).

This repository documents how to install, configure, deploy, and maintain Deno applications on an Ubuntu server using Apache, systemd, and locally hosted Deno KV.

The goal is to replace Deno Deploy with a simple, self-managed installation while preserving the existing PG4E student assignments and APIs.

## Background

In October 2026, Deno announced plans to discontinue Deno Deploy and eventually end official development of the Deno runtime.

PG4E uses Deno to teach non-relational database concepts, particularly through Deno KV. Earlier versions of the course allowed students to deploy their own applications to Deno Deploy, but that requirement was removed.

Students now communicate with centrally hosted APIs.

This makes self-hosting comparatively straightforward. There is no need to reproduce Deno Deploy's deployment management, per-student containers, or serverless infrastructure.

The existing applications can run as ordinary HTTP servers behind Apache.

## Architecture

```text
PG4E Students
      |
      | HTTPS
      v
dnx.pg4e.com
      |
      v
Apache 2.4
      |
      | Reverse Proxy
      v
Deno 2.9.8
      |
      +---- KV Admin API
      |
      +---- Hono Application
      |
      v
Local Deno KV / SQLite
```

Each application can run as an independent systemd service, listening on its own localhost port.

Apache manages HTTPS, virtual hosts, and reverse proxying. Deno manages application logic and database operations.

## Applications

The PG4E Deno environment consists of two existing applications, maintained in separate GitHub repositories.

### Deno KV Admin

Repository: [csev/deno2-kv-admin](https://github.com/csev/deno2-kv-admin)

Deno Deploy application: `deno2-kv-admin`

Previously deployed at:

- `https://deno2-kv-admin.csev.deno.net`
- `https://deno2.pg4e.com`
- `https://deno.pg4e.com`
- `https://kv-admin-api.pg4e.com`

This application provides the KV administration and API functionality used by PG4E.

Its authentication configuration, including `KV_TOKEN_SECRET`, must be preserved during migration.

### Deno Hono

Repository: [csev/deno2-hono](https://github.com/csev/deno2-hono)

Deno Deploy application: `deno2-hono`

Previously deployed at:

- `https://deno2-hono.csev.deno.net`
- `https://hono.pg4e.com`

This application uses the Hono framework.

Both repositories already contain their application source code. There is no need to export the source from Deno Deploy.

## Tested Environment

The initial installation was completed on November 3, 2026.

| Component | Configuration |
|---|---|
| Infrastructure | AWS EC2 |
| Operating system | Ubuntu 18.04 |
| Architecture | x86_64 |
| glibc | 2.27 |
| Deno | 2.9.8 |
| V8 | 15.0.245.2-rusty |
| TypeScript | 6.0.3 |
| Apache | 2.4.43 |
| Public hostname | dnx.pg4e.com |
| Public IP at testing | 3.101.11.254 |
| Local Deno listener | 127.0.0.1:8000 |

Successfully verified:

- Deno executable runs on Ubuntu 18.04.
- Deno KV works with local SQLite-backed persistence.
- `Deno.serve()` handles HTTP requests.
- Apache reverse proxy forwards requests to Deno.
- DreamHost DNS resolves the public hostname.
- Let's Encrypt provides a valid HTTPS certificate.
- The public HTTPS endpoint returns HTTP 200.

The initial public test returned:

```text
$ curl -i https://dnx.pg4e.com/
HTTP/1.1 200 OK
Server: Apache/2.4.43 (Ubuntu)

Hello from PG4E Deno!
```

These tests verify the basic infrastructure. The two production applications must be tested separately after migration.

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

This repository contains deployment documentation, configuration examples, and test scripts.

The two application repositories remain separate.

## 1. Installing Deno

Deno 2.9.8 is preserved in a separate binary archive:

[github.com/csev/deno-archive](https://github.com/csev/deno-archive)

The archive contains Linux and macOS binaries for both x86_64 and ARM64.

For Ubuntu running on x86_64, obtain `deno-x86_64-unknown-linux-gnu.zip`.

Unpack and install:

```bash
unzip deno-x86_64-unknown-linux-gnu.zip
sudo install -m 755 deno /usr/local/bin/deno
```

Verify:

```bash
deno --version
```

Expected output:

```text
deno 2.9.8 (stable, release, x86_64-unknown-linux-gnu)
v8 15.0.245.2-rusty
typescript 6.0.3
```

The original installer was also tested successfully:

```bash
curl -fsSL https://deno.land/install.sh | sh
```

However, that installer depends on upstream download infrastructure. The archived executable is preferred for long-term reproducibility.

The original installer placed the executable in `/home/csev/.deno/bin/deno`, even when invoked from a root shell. Check `$HOME` rather than assuming the install directory.

## 2. Testing Deno KV

Deno KV works with a local persistent database without requiring Deno Deploy.

Run:

```bash
deno eval --unstable-kv 'const kv = await Deno.openKv("/tmp/test.kv"); await kv.set(["hello"], "world"); console.log((await kv.get(["hello"])).value); kv.close();'
```

Expected:

```text
world
```

The repository also contains a test script:

```bash
bash scripts/test-kv.sh
```

The local KV implementation uses SQLite-backed storage.

Production databases should be stored outside the application source directories, with appropriate file permissions and backups.

## 3. Testing the HTTP Server

The repository contains a minimal application:

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

This confirms that Deno is accepting requests on localhost.

The HTTP listener should bind to `127.0.0.1` rather than `0.0.0.0`, preventing direct external access.

Stop the interactive server with Ctrl+C before starting the systemd service on the same port.

## 4. Apache Reverse Proxy

Apache 2.4 is used as the public HTTP and HTTPS server.

Enable the required proxy modules:

```bash
sudo a2enmod proxy proxy_http
sudo apache2ctl configtest
sudo systemctl restart apache2
```

Use a dedicated virtual host for Deno.

The original configuration was stored in:

```text
/etc/apache2/sites-available/deno.pg4e.com.conf
```

Despite the filename, the virtual host uses:

```apache
ServerName dnx.pg4e.com
```

The essential reverse proxy configuration is:

```apache
<VirtualHost *:80>
    ServerName dnx.pg4e.com

    ProxyRequests Off
    ProxyPreserveHost On

    ProxyPass / http://127.0.0.1:8000/
    ProxyPassReverse / http://127.0.0.1:8000/

    ErrorLog ${APACHE_LOG_DIR}/deno-error.log
    CustomLog ${APACHE_LOG_DIR}/deno-access.log combined
</VirtualHost>
```

A configuration template is included under `apache/`.

Enable a new site using `a2ensite`, followed by a configuration test and reload. On an existing installation, edit the active virtual host rather than enabling a duplicate.

The working installation was configured using `vi`.

Test without DNS:

```bash
curl -H "Host: dnx.pg4e.com" http://127.0.0.1/
```

Expected:

```text
Hello from PG4E Deno!
```

## 5. DNS Configuration

DNS is managed through DreamHost.

Create an A record:

```text
Host:  dnx.pg4e.com
Type:  A
Value: 3.101.11.254
```

The IP address was correct on November 3, 2026. Verify the EC2 public IP before reusing it.

Check the authoritative nameserver:

```bash
dig @ns1.dreamhost.com dnx.pg4e.com A +short
```

Check public resolvers:

```bash
dig @1.1.1.1 dnx.pg4e.com A +short
dig @8.8.8.8 dnx.pg4e.com A +short
```

All three returned `3.101.11.254` during testing.

The DNS record points directly to the existing EC2 instance. No separate DreamHost website is required.

## 6. HTTPS with Let's Encrypt

Certbot was used to configure HTTPS:

```bash
sudo certbot --apache -d dnx.pg4e.com
```

The HTTP-to-HTTPS redirect option was selected.

Certbot created:

```text
/etc/apache2/sites-available/deno.pg4e.com-le-ssl.conf
```

Certificate files are stored under:

```text
/etc/letsencrypt/live/dnx.pg4e.com/
```

The initial certificate expires February 1, 2027.

Check renewal:

```bash
sudo certbot renew --dry-run
```

Verify HTTPS:

```bash
curl -i https://dnx.pg4e.com/
```

Certbot-generated SSL configuration and private keys should not be committed to Git.

## 7. Running Deno with systemd

Deno should run independently of any SSH session.

The recommended layout is:

```text
/opt/deno-pg4e/          Application files
/var/lib/deno-pg4e/      Persistent KV storage
/etc/systemd/system/     Service definitions
```

The repository contains a sample systemd service:

```text
systemd/deno-pg4e.service
```

The intended installation uses a dedicated, unprivileged `deno-pg4e` account.

On a fresh host, create the account and directories:

```bash
sudo useradd --system --home /var/lib/deno-pg4e --shell /usr/sbin/nologin deno-pg4e

sudo install -d -o root -g root -m 755 /opt/deno-pg4e

sudo install -d -o deno-pg4e -g deno-pg4e -m 750 /var/lib/deno-pg4e
```

Skip account creation if it already exists.

Install the example application and the supplied service definition:

```bash
sudo install -m 644 examples/hello.ts /opt/deno-pg4e/main.ts

sudo install -m 644 systemd/deno-pg4e.service /etc/systemd/system/deno-pg4e.service
```

Ensure that the entrypoint and permissions in the service definition match the installed application.

Stop any manually started Deno process on port 8000, then:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now deno-pg4e
sudo systemctl status deno-pg4e --no-pager
```

Test:

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

The initial systemd service hosts the hello-world application. The final application services will be configured during migration.

## 8. Cloning the PG4E Applications

The existing application source code is already on GitHub.

Clone both repositories onto the Ubuntu server:

```bash
cd /opt

sudo git clone https://github.com/csev/deno2-kv-admin.git
sudo git clone https://github.com/csev/deno2-hono.git
```

The resulting directories are:

```text
/opt/deno2-kv-admin/
/opt/deno2-hono/
```

These repositories contain the actual application source code and should remain independent of this deployment repository.

For future updates, use Git to obtain changes, then restart the corresponding service after testing.

## 9. Migrating Deno Hono

The Hono application is a reasonable first migration target because it is comparatively simple.

Repository:

[github.com/csev/deno2-hono](https://github.com/csev/deno2-hono)

The application includes `deno.json`, `deno.lock`, and TypeScript source.

Migration procedure:

1. Inspect `deno.json` for tasks, imports, and dependencies.
2. Identify the HTTP server entrypoint and any Deno Deploy-specific APIs.
3. Install or cache the dependencies.
4. Configure the application to listen on localhost using its assigned port.
5. Run it interactively and verify its endpoints.
6. Create a dedicated systemd service.
7. Configure Apache to reverse proxy requests to the service.
8. Validate the public API before redirecting existing traffic.

A possible port allocation is:

```text
Deno test service: 127.0.0.1:8000
Hono service:      127.0.0.1:8002
```

These are proposed assignments, not yet the final production configuration.

The existing `hono.pg4e.com` hostname can be preserved using an additional Apache virtual host once the application works locally.

## 10. Migrating Deno KV Admin

Repository:

[github.com/csev/deno2-kv-admin](https://github.com/csev/deno2-kv-admin)

This application requires additional attention because it provides the KV administration/API interface and uses signed-token authentication.

Migration procedure:

1. Inspect `deno.json`, the server entrypoint, and API routing.
2. Inventory the production environment variables.
3. Preserve the existing `KV_TOKEN_SECRET` securely.
4. Determine whether hosted Deno KV records must be exported.
5. Configure persistent local Deno KV storage.
6. Verify authentication and authorization.
7. Test existing student API requests.
8. Create a dedicated systemd service.
9. Configure Apache and validate the public endpoints.
10. Switch DNS only after the new implementation has been verified.

Example port allocation:

```text
KV Admin service: 127.0.0.1:8001
```

Secrets must not be committed to public Git repositories.

Systemd environment files can be stored outside the application directory, with restrictive permissions.

If existing client tokens are still in use, verify that the same signing configuration preserves compatibility. Avoid changing the secret accidentally during migration.

## 11. Local Deno KV Storage

Local Deno KV provides persistent storage using SQLite.

An application can open a database using:

```typescript
const kv = await Deno.openKv("/var/lib/deno-pg4e/pg4e.kv");
```

The service account must have permission to write to the database directory.

Production data should not be stored in `/tmp`, a Git working tree, or a location that is automatically overwritten during application deployment.

For separate applications, prefer separate KV database files unless sharing is explicitly required.

Before replacing an existing hosted KV database, determine:

- Whether production data must be retained.
- How the application structures its keys.
- Whether values contain data requiring special serialization handling.
- How to export and restore the existing records.
- How authentication and application behavior will be tested after migration.

Use a consistent SQLite backup or snapshot mechanism for live databases. Simply copying a database file while the application is writing may produce an inconsistent backup.

## 12. Migration Without Interrupting Students

Do not immediately repoint the existing PG4E API hostnames.

Initially, keep the Deno Deploy applications active while testing the self-hosted replacements.

The migration sequence is:

1. Clone the application source.
2. Start the new application locally.
3. Verify requests using localhost.
4. Test through `dnx.pg4e.com`.
5. Verify authentication and database behavior.
6. Test representative course assignments.
7. Confirm whether data migration is necessary.
8. Cut over the existing public hostname.
9. Monitor logs and student requests.
10. Retire the corresponding Deno Deploy application only after successful validation.

For live KV data, plan a short write freeze or another mechanism that prevents updates from being lost between the final export and DNS cutover.

Where possible, preserve existing URLs so that student assignment code and autograders do not need to change.

## 13. Security and Maintenance

The self-hosted configuration should follow these practices:

- Keep Deno bound to localhost.
- Expose public HTTP traffic through Apache and HTTPS.
- Use unprivileged systemd service accounts.
- Grant only the runtime permissions required by each application.
- Keep API secrets outside public repositories.
- Back up persistent KV databases.
- Preserve dependency lockfiles and cached packages.
- Pin a tested Deno runtime version.
- Monitor application errors through journald and Apache logs.
- Test course assignments after changing application code or runtime configuration.

Ubuntu 18.04 is beyond its standard security maintenance period. The existing server should receive applicable extended security maintenance or eventually be upgraded.

Archived Deno binaries provide reproducibility but not ongoing security updates.

## 14. Deployment Checklist

### Infrastructure

- [x] Install Deno 2.9.8 on Ubuntu 18.04
- [x] Verify runtime compatibility
- [x] Verify local Deno KV
- [x] Start Deno HTTP server on port 8000
- [x] Enable Apache reverse proxy modules
- [x] Create dedicated Apache virtual host
- [x] Configure DreamHost DNS
- [x] Obtain Let's Encrypt certificate
- [x] Verify public HTTPS endpoint
- [ ] Verify certificate auto-renewal
- [ ] Confirm systemd service behavior across reboot

### Application Migration

- [ ] Clone `deno2-hono` onto the Ubuntu server
- [ ] Run Hono locally
- [ ] Create and test Hono systemd service
- [ ] Configure Hono Apache virtual host
- [ ] Clone `deno2-kv-admin`
- [ ] Inventory KV Admin environment variables and secrets
- [ ] Determine hosted KV data migration requirements
- [ ] Configure persistent local Deno KV
- [ ] Run KV Admin locally
- [ ] Create and test KV Admin systemd service
- [ ] Test authentication and course assignments
- [ ] Switch existing public API domains
- [ ] Establish KV backup procedures
- [ ] Retire Deno Deploy services when safe

## Related Repositories

| Repository | Purpose |
|---|---|
| [csev/deno](https://github.com/csev/deno) | Archived Deno runtime source |
| [csev/deno_install](https://github.com/csev/deno_install) | Archived installation scripts |
| [csev/deno-archive](https://github.com/csev/deno-archive) | Deno 2.9.8 binaries for Linux and macOS |
| [csev/deno-pg4e](https://github.com/csev/deno-pg4e) | Self-hosted deployment documentation |
| [csev/deno2-kv-admin](https://github.com/csev/deno2-kv-admin) | Deno KV Admin application |
| [csev/deno2-hono](https://github.com/csev/deno2-hono) | Deno Hono application |

## About

Maintained by Dr. Charles R. Severance as part of the [PostgreSQL for Everybody](https://www.pg4e.com/) project.

Initial self-hosting work completed November 3, 2026.

The objective is to preserve working educational software and maintain control over its hosting infrastructure, independent of the long-term availability of Deno Deploy.
