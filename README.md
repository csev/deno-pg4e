# deno-pg4e

Self-hosting notes and configuration for the Deno HTTP/KV service used by [PostgreSQL for Everybody](https://www.pg4e.com/).

This repository documents how to reproduce the self-hosted Deno setup on an existing Ubuntu/Apache server. It is **not** a fork of Deno, a copy of Deno Deploy, or an archive of runtime binaries. The deployed PG4E application can be added separately once it is ready.

## Tested setup (November 3, 2026)

- Ubuntu 18.04, Linux `x86_64`, glibc 2.27 (existing EC2 host)
- Deno **2.9.8**, installed as `/usr/local/bin/deno`
- Deno KV tested with a local SQLite-backed file
- Apache **2.4.43** acting as a reverse proxy
- Public host: **https://dnx.pg4e.com**
- Apache proxies to **127.0.0.1:8000**
- Let's Encrypt certificate issued using `certbot --apache`; HTTP redirects to HTTPS

Successfully tested from a separate Mac:

```text
$ curl -i https://dnx.pg4e.com/
HTTP/1.1 200 OK
...
Hello from PG4E Deno!
```

**Current status:** DNS, TLS, Apache proxy, Deno runtime, and local Deno KV were tested successfully. The `systemd` unit below is a proposed next step, **not yet confirmed deployed**. The running application at the time of the test was a temporary hello-world server started interactively.

## Repository layout

```text
deno-pg4e/
  README.md
  apache/dnx.pg4e.com.conf  # HTTP template; Certbot can create HTTPS vhost
  systemd/deno-pg4e.service
  examples/hello.ts
  scripts/test-kv.sh
  .gitignore
```

## 1. Install Deno

Preferred for long-term reproducibility: use a **verified, archived Deno 2.9.8 binary** from the separate [csev/deno-archive](https://github.com/csev/deno-archive) repository. On Linux x86_64:

```bash
unzip deno-x86_64-unknown-linux-gnu.zip
sudo install -m 755 deno /usr/local/bin/deno
deno --version
```

The original network installer worked on this host too:

```bash
curl -fsSL https://deno.land/install.sh | sh
sudo install -m 755 "$HOME/.deno/bin/deno" /usr/local/bin/deno
```

The installer may install under a different home directory if `$HOME` differs from the current login name. It also depends on upstream servers being available. For production, **pin the runtime to 2.9.8** rather than silently upgrading it.

## 2. Test runtime and KV

```bash
deno --version
bash scripts/test-kv.sh
```

The expected KV output is `world`. This exercise uses a temporary `/tmp` database; production persistence belongs in `/var/lib/deno-pg4e/`.

## 3. Test the HTTP app locally

```bash
deno run --allow-net=127.0.0.1:8000 examples/hello.ts
```

From another shell:

```bash
curl http://127.0.0.1:8000/
# Hello from PG4E Deno!
```

Stop the interactive process before enabling `systemd`, since both cannot listen on port 8000.

## 4. Configure Apache

Install/enable Apache if it is not already present and running. Check that ports 80 and 443 are not held by another service before starting it.

```bash
sudo a2enmod proxy proxy_http
sudo systemctl start apache2
sudo apache2ctl configtest
```

For a new server, copy the checked-in HTTP vhost template:

```bash
sudo install -m 644 apache/dnx.pg4e.com.conf /etc/apache2/sites-available/dnx.pg4e.com.conf
sudo a2ensite dnx.pg4e.com.conf
sudo apache2ctl configtest
sudo systemctl reload apache2
```

**Existing PG4E host:** Its live HTTP vhost file was named `/etc/apache2/sites-available/deno.pg4e.com.conf`, despite containing `ServerName dnx.pg4e.com`. The name of the file is not important; **do not install a duplicate enabled vhost** when updating that server. Edit the existing file with `sudo vi` instead.

Test Apache's host routing before DNS changes:

```bash
curl -H 'Host: dnx.pg4e.com' http://127.0.0.1/
```

## 5. DNS and HTTPS

Create an **A record** for `dnx.pg4e.com` pointing to the server's public IP. On November 3, 2026, the tested address was `3.101.11.254`; verify the current EC2 public IP before reusing it.

```bash
dig @ns1.dreamhost.com dnx.pg4e.com A +short
dig @1.1.1.1 dnx.pg4e.com A +short
dig @8.8.8.8 dnx.pg4e.com A +short
```

Once the name resolves and port 80 is reachable externally:

```bash
sudo certbot --apache -d dnx.pg4e.com
```

Select the HTTP-to-HTTPS redirect option. On the tested host, Certbot generated `/etc/apache2/sites-available/deno.pg4e.com-le-ssl.conf`. **Do not overwrite Certbot-generated certificate directives with the HTTP template.** Check renewal using:

```bash
sudo certbot renew --dry-run
```

Then test from outside the EC2 instance:

```bash
curl -i https://dnx.pg4e.com/
```

## 6. Install as a persistent systemd service (next step)

The checked-in unit runs an app as a separate, unprivileged `deno-pg4e` service user and stores KV under `/var/lib/deno-pg4e`. Commands below prepare a **fresh installation** and assume `examples/hello.ts` is the service's initial application.

```bash
sudo useradd --system --home /var/lib/deno-pg4e --shell /usr/sbin/nologin deno-pg4e
sudo install -d -o root -g root -m 755 /opt/deno-pg4e
sudo install -d -o deno-pg4e -g deno-pg4e -m 750 /var/lib/deno-pg4e
sudo install -m 644 examples/hello.ts /opt/deno-pg4e/main.ts
sudo install -m 644 systemd/deno-pg4e.service /etc/systemd/system/deno-pg4e.service
sudo systemctl daemon-reload
sudo systemctl enable --now deno-pg4e
sudo systemctl status deno-pg4e --no-pager
curl http://127.0.0.1:8000/
```

If the service account already exists, skip `useradd`. **Stop the manually started Deno server before starting the service.** The eventual PG4E application will need to replace `/opt/deno-pg4e/main.ts` and may require different file/network permissions in the unit.

Useful operations:

```bash
sudo journalctl -u deno-pg4e -f
sudo systemctl restart deno-pg4e
sudo systemctl status deno-pg4e --no-pager
```

## 7. Deno KV persistence

Local `Deno.openKv('/var/lib/deno-pg4e/pg4e.kv')` uses an on-disk SQLite-backed KV store. Grant the service account write access to the database directory, not to the code directory. **Back up the real database** using a SQLite-aware backup procedure or a consistent snapshot; do not assume copying a live database file is safe. If there are multiple server processes, do not assume independent processes can safely share a KV database file without testing.

The checked-in hello-world example intentionally does not create a database. It is only a server/proxy smoke test.

## 8. Security and longevity

- Ubuntu 18.04 is past standard security support; use Ubuntu Pro/ESM where applicable or plan to upgrade the host.
- Keep the Deno listener bound to **127.0.0.1**; expose only Apache's HTTPS listener to the internet.
- Run the production app without root privileges and grant only the permissions it needs.
- Review authentication, rate limits, and request validation before connecting student assignments.
- Back up KV data, pin dependencies, and retain the matching Deno runtime binary.
- Deno 2.9.8 is archived for reproducibility, not a promise of future security updates.

## 9. Things to do

- [x] Deno 2.9.8 starts on Ubuntu 18.04
- [x] Local Deno KV round-trip works
- [x] Deno HTTP server responds on localhost:8000
- [x] Apache proxies its own `dnx.pg4e.com` vhost
- [x] DNS, TLS, and public HTTPS smoke test work
- [ ] Check automatic Let's Encrypt renewal with `certbot renew --dry-run`
- [ ] Enable and test the `systemd` unit
- [ ] Migrate PG4E's real Deno app and its KV storage
- [ ] Validate auth, persistence, load handling, and backups

## Related archives

- [csev/deno-archive](https://github.com/csev/deno-archive) — preserved Deno runtime binaries
- [csev/deno](https://github.com/csev/deno) — runtime source fork
- [csev/deno_install](https://github.com/csev/deno_install) — installer scripts fork
