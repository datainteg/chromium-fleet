# Security Policy

## Reporting Vulnerabilities

**Do not open a public GitHub issue for security vulnerabilities.**

Email: `support@datainteg.io`

Include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Any proof-of-concept (redact real credentials)

We aim to acknowledge reports within 3 business days and provide a fix timeline within 14 days depending on severity.

---

## Known Risks and Required Mitigations

### 1. Docker Socket Exposure — CRITICAL

`docker-compose.fleet.yml` mounts `/var/run/docker.sock` into the API container:

```yaml
volumes:
  - /var/run/docker.sock:/var/run/docker.sock
```

**Risk:** This grants the API container host-level Docker control, equivalent to root access on the VM. Any remote code execution vulnerability in the API would allow full host compromise.

**Required mitigations:**
- Never expose port `8787` directly to the internet (see below).
- Protect the API exclusively through Nginx basic auth + JWT.
- Set `ALLOW_INSTALL=false` and `ALLOW_UNINSTALL=false` in `api/.env` once all browser instances are provisioned.
- Restrict SSH access and Docker group membership to trusted operators only.
- Deploy only on single-tenant VMs controlled by your team.

---

### 2. API Port 8787 — Never Expose Publicly

The API listens on `127.0.0.1:8787` by default (`HOST=127.0.0.1`).

**Never change `HOST=0.0.0.0` unless you have a specific, secured reason.**

The API is designed to be accessed only through the Nginx reverse proxy at `/api/...`, which enforces:
1. Nginx basic auth (username/password)
2. API JWT auth (`Authorization: Bearer <token>`)

**Recommended firewall rules (UFW example):**
```bash
# Allow HTTP/HTTPS from internet
ufw allow 80/tcp
ufw allow 443/tcp

# Allow Chromium ports only from trusted IP ranges (adjust as needed)
# ufw allow from YOUR_OFFICE_IP to any port 3000:3099 proto tcp

# Block direct API port access from internet
ufw deny 8787/tcp

# Enable firewall
ufw enable
```

**GCP / AWS equivalent:** Set VPC firewall rules to block port 8787 from `0.0.0.0/0`. Only allow it from localhost or your internal subnet.

---

### 3. JWT and Refresh Token Secrets

`JWT_SECRET` and `REFRESH_TOKEN_SECRET` must be long, random, and unique per deployment.

**Requirements:**
- Minimum 64 random characters.
- Never reuse across deployments or environments.
- Store only in `api/.env` (mode 600, never committed to git).

**Generate:**
```bash
openssl rand -base64 48   # for JWT_SECRET
openssl rand -base64 48   # for REFRESH_TOKEN_SECRET (use a different value)
```

**Never use:**
- Default values from `.env.example`
- Simple strings like `changeme`, `secret`, or any dictionary words

---

### 4. proxy.env — Proxy Credential Protection

Proxy credentials (host, port, username, password) are stored in:
```
/opt/<seller>-browser/proxy.env
```

**Security properties:**
- File permissions: `chmod 600` (readable only by root)
- Never written into `docker-compose.yml` (prevents exposure via `docker inspect`, git history, or backups)
- Docker Compose reads credentials at runtime via `env_file` directive
- File is excluded from git via `.gitignore`

**Operator responsibilities:**
- Ensure VM disk encryption is enabled if proxies contain sensitive credentials.
- Do not include `/opt/<seller>-browser/` in public VM snapshots or backups.
- Rotate proxy credentials periodically and update via `proxy-rotate` action.

**Note:** `docker inspect <container>` will still show HTTP_PROXY in the container's environment variables (Docker has no mechanism to hide `env_file` values from inspect without Docker Secrets + Swarm mode). This is a known limitation. Restrict Docker group membership accordingly.

---

### 5. Nginx Basic Auth

Browser access and API calls are protected by Nginx HTTP basic auth (`htpasswd`).

**Security properties:**
- htpasswd file created atomically with `umask 077` (no world-readable window).
- Final permissions: `640 root:www-data`.
- Directory permissions: `750 root:www-data`.
- Hash algorithm: bcrypt (via `htpasswd -B` if available, MD5 otherwise — depends on system `htpasswd` version).

**Recommendation:** Use a strong password (minimum 16 characters, mixed case, numbers, symbols). The Nginx basic auth password is the outermost authentication layer for browser access.

---

### 6. API Authentication Defaults

Review these settings before production:

| Setting | Default | Production recommendation |
|---|---|---|
| `DISABLE_AUTH` | `false` | Keep `false` |
| `ALLOW_INSTALL` | `true` | Set `false` after provisioning |
| `ALLOW_UNINSTALL` | `true` | Set `false` after provisioning |
| `ALLOW_ACTIONS` | `true` | Keep `true` (lifecycle actions) |
| `ALLOW_API_KEY_AUTH` | `false` | Keep `false` unless legacy clients need it |
| `JWT_EXPIRES_IN` | `15m` | Reduce to `5m` for high-security environments |
| `REFRESH_TOKEN_EXPIRES_IN` | `7d` | Acceptable; reduce for high-security environments |

---

### 7. Session and Browser Profile Security

Each browser profile is stored as a bind-mount at `/opt/<seller>-browser/profile/`. This directory contains:
- Login cookies for all websites
- Saved passwords and autofill
- Browser extensions and their data
- localStorage and sessionStorage

**Operator responsibilities:**
- Restrict access to `/opt/<seller>-browser/profile/` to root only.
- Enable VM disk encryption.
- Do not make VM snapshots publicly accessible.
- Daily backups (stored in `/opt/<seller>-browser/backups/`) contain full session data — protect them equally.

---

## Deployment Scope

`chromium-fleet` is designed for:
- Single-team or internal use on trusted VMs.
- Scenarios where VM access is restricted to a small group of trusted operators.

It is **not designed for**:
- Multi-tenant SaaS deployments with untrusted users.
- Public-facing APIs without strong network perimeter controls.
- Environments where the VM is shared with other untrusted workloads.
