# All-in-one deployment

The compose files in this folder are documented on the documentation website:

* [All-in-one deployment](../../docs-website/docs/deployment/all-in-one.md) —
  local testing, HTTPS with certbot, and what to do afterwards
* [Deployment overview](../../docs-website/docs/deployment/overview.md) — how
  this variant compares to the others

Short version, for a local test:

```bash
docker compose up -d --no-build
```

The admin panel is then available at http://localhost/ with the user `admin` and
the password `openmu` — [change that](../../docs-website/docs/admin-panel/users.md)
before the server is reachable from the internet.

## Energy armor variants

The all-in-one deployment applies `energy-armor-variants.sql` automatically at
startup, after OpenMU initializes the database and before its game servers load
configuration. The seed adds Energy-requirement copies of the Vine, Silk, Wind,
and Guardian armor sets and is safe to re-run.

Automatic seeding is enabled by default. To opt out, set this in `.env`:

```dotenv
OPENMU_SEED_ENERGY_ARMOR_VARIANTS=false
```

To apply the seed manually instead, run this after database initialization:

```powershell
Get-Content .\energy-armor-variants.sql -Raw |
  docker compose exec -T database sh -c 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
```

Build and restart the OpenMU image to include the matching Energy requirement
logic:

```powershell
docker compose build openmu-startup
docker compose up -d --no-deps openmu-startup
```

Players also need the matching client build for the Energy item names and
appearance aliases.
