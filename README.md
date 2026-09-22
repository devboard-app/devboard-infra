# devboard-infra

**The control room.** It runs the shared parts of DevBoard (Postgres, Redis, MongoDB, MinIO). It also has the scripts that start, stop, update and reset the whole stack.

There is no app code here. Only Docker files and `.bat` scripts (Windows).

---

## Start here (about 10 minutes the first time)

**Before you begin:** all repos must sit side by side in one folder (`devboard-auth`, `devboard-core`, ...). The scripts use `..\devboard-*` paths. Docker Desktop must be running.

1. Copy `.env.example` to `.env` in this folder. Fill in the passwords.
2. Run:

```bat
setup.bat
```

3. Wait for the closing banner. It lists every service and its port.
4. Open `http://localhost:8008` (the web app).

`setup.bat` also copies `.env.example` to `.env` in any repo that has no `.env` yet. **Then fill them in** and run `setup.bat` again.

---

## What runs where

| Service | Port | What it is |
|---|---|---|
| devboard-auth | 8001 | Login, sign-up, tokens. |
| devboard-email | 8002 | Sends emails. |
| devboard-core | 8003 | User profiles. |
| devboard-work | 8004 | Teams, projects, tickets, sprints. Plus an outbox relay container. |
| devboard-integrations | 8005 | Slack, Discord, GitHub, notifications. Plus a worker container. |
| devboard-analytics | 8006 | Activity log and reports. Plus a worker container. |
| devboard-attachments | 8007 | File uploads. |
| devboard-web | 8008 | The web app. |

Shared parts (started by this folder's `docker-compose.yml`):

| Container | Port | What it holds |
|---|---|---|
| `devboard-db` (Postgres 18) | 5432 | Five databases, see below. |
| `devboard-redis` (Redis 7) | 6379 | The event stream `devboard:events`. Saved to disk (AOF), so events survive a restart. |
| `devboard-mongo` (MongoDB 7) | 27017 | `activity_db`, the activity log. |
| `devboard-minio` | 9000 API, 9001 console | Uploaded files. |

One Postgres container, five databases. Each service has its own user and database:

| Service | Database | User |
|---|---|---|
| auth | `auth_db` | `auth_user` |
| core | `core_db` | `core_user` |
| work | `work_db` | `work_user` |
| integrations | `integrations_db` | `integrations_user` |
| attachments | `attachments_db` | `attachments_user` |

All containers share one Docker network: `devboard-network`.

---

## Scripts

Run them from this folder.

| Script | What it does | When to use it |
|---|---|---|
| `setup.bat` | Starts infra, creates users and databases, builds and starts every service, runs migrations. | First run. Or after a reset. |
| `redeploy.bat` | Menu. Rebuilds and restarts one service (`1` to `8`) or all (`0`). | After you change code. |
| `migrate.bat` | Menu. Runs migrations: `0` all, `1` auth, `2` core, `3` work, `4` integrations, `5` attachments. | After you change a model. |
| `stop.bat` | Saves a Postgres backup to `backups\devboard_all.sql`, then stops everything. Data stays in the volumes. | End of the day. |
| `reset-db.bat` | **Deletes all data** and rebuilds. Backs up first. | When the data is broken and you want a clean start. |

Menu for `redeploy.bat`: `1` core, `2` auth, `3` email, `4` work, `5` integrations, `6` analytics, `7` attachments, `8` web.

`redeploy.bat` does not run migrations. Run `migrate.bat` after it if models changed.

---

## Another way: one command

Run from the DevBoard root (the folder that holds all repos):

```bat
docker network create devboard-network
docker compose -f devboard-infra/stack.yml up -d --build
```

| Goal | Command |
|---|---|
| See all containers | `docker compose -f devboard-infra/stack.yml ps` |
| Follow one log | `docker compose -f devboard-infra/stack.yml logs -f devboard-work` |
| Stop, keep data | `docker compose -f devboard-infra/stack.yml down` |

Create the network only the first time.

Good to know:

- Everything starts at once. App containers may restart a few times until Postgres is healthy. That is normal.
- `stack.yml` **does not run migrations.** Run `migrate.bat` after.
- Postgres roles and databases are created by `init-db\01-init.sh`. It runs only when the Postgres volume is **empty**.
- The MongoDB `analytics_user` is created only by `setup.bat`.

---

## Settings

`.env` in this folder:

| Variable | What it is |
|---|---|
| `POSTGRES_USER` `POSTGRES_PASSWORD` | Postgres admin login. |
| `MONGO_ROOT_USER` `MONGO_ROOT_PASSWORD` | MongoDB admin login. |
| `MINIO_ROOT_USER` `MINIO_ROOT_PASSWORD` | MinIO admin login. |
| `AUTH_DB_PASSWORD` `CORE_DB_PASSWORD` `WORK_DB_PASSWORD` `INTEGRATIONS_DB_PASSWORD` `ATTACHMENTS_DB_PASSWORD` | Passwords for the five service users. Used by `init-db` on a fresh volume. |

**Each service password must match the password in that service's own `.env`.** A mismatch is the most common reason a migration fails.

Fix a wrong password:

```bat
docker exec devboard-db psql -U <admin> -c "ALTER USER <role> WITH PASSWORD '<password>';"
```

Then run `migrate.bat`.

---

## Backups and reset

| What | Where | Notes |
|---|---|---|
| Postgres, on `stop.bat` | `backups\devboard_all.sql` | All five databases and roles (`pg_dumpall`). |
| Everything, on `reset-db.bat` | `backups\<timestamp>\` | Postgres (`postgres_all.sql`) and MongoDB (`mongo.archive`). |

**`reset-db.bat` deletes:**

1. All five Postgres databases.
2. The MongoDB activity log.
3. Redis: the event stream, consumer offsets, and web login sessions.
4. **Every uploaded file in MinIO. MinIO is not backed up.**

It asks you to type `DESTROY` to continue. If a backup fails, it asks again.

After a reset the databases are empty. To bring the old data back, use the restore commands printed at the end of the script.

---

## If something breaks

| Problem | Try |
|---|---|
| `network devboard-network not found` | `docker network create devboard-network` |
| Migration failed | Check the password in the service `.env` against the Postgres user. See "Settings". |
| Service keeps restarting right after start | Wait 30 seconds. Postgres may not be healthy yet. |
| Container name already in use | Another DevBoard project is running. Run `stop.bat` first. |
| Analytics cannot reach Redis | In its `.env`, `REDIS_URL` must be `redis://devboard-redis:6379/0`. |
