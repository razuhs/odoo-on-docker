# delete_all_db.sh

## Purpose
`delete_all_db.sh` removes all non-system PostgreSQL databases from the Docker container named `postgres-container`.

This script is intended for environment reset and cleanup.

## What It Deletes
The script deletes every database that is:
- not a template database (`datistemplate = false`)
- not in this protected list:
  - `postgres`
  - `template0`
  - `template1`

## Safety Behavior
- Requires explicit confirmation (`DELETE ALL`) before destructive execution.
- Supports dry run mode to preview actions.
- Attempts to terminate active client connections before dropping each database.
- Attempts to clear the template flag (`is_template = false`) before drop, in case it was set.

## Requirements
- Docker daemon is running.
- User can access Docker directly or via `sudo docker`.
- Container exists with name: `postgres-container`.
- Base config file exists:
  - `../configs/.base_stack.conf`
- `DB_USER` is defined in that config.

## Usage
Run from project root or scripts directory:

```bash
./scripts/delete_all_db.sh
```

Show help:

```bash
./scripts/delete_all_db.sh --help
```

Dry run (no deletion):

```bash
./scripts/delete_all_db.sh --dry-run
# or
./scripts/delete_all_db.sh -n
```

## Execution Flow
1. Resolves Docker command (`docker` or `sudo docker`).
2. Loads `DB_USER` from `../configs/.base_stack.conf`.
3. Queries database list from PostgreSQL container.
4. Prints target databases.
5. If dry run: prints planned actions and exits.
6. If normal run:
   - asks for `DELETE ALL`
   - terminates active connections per DB
   - clears template flag per DB (best effort)
   - drops each DB

## Exit Conditions
- Exits with error if Docker is inaccessible.
- Exits with error if base config is missing.
- Exits with error if `DB_USER` is missing.
- Exits without changes if no matching user databases are found.
- Exits without changes if confirmation text is not exactly `DELETE ALL`.

## Important Warning
This operation is destructive and irreversible. Use dry run first in shared or production-like environments.
