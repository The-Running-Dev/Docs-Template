API for serving site data

- Tech: Fastify + TypeScript, run via `tsx`.
- Purpose: Serve JSON for all data currently authored in `../config/*.yml`.

Quick start

- Dev: `pnpm --dir api dev` (serves on http://localhost:4000/api)
- Docs: http://localhost:4000/api/docs

Endpoints

- `GET /api/health` – health check
- `GET /api/v1` – list resources
- `GET /api/v1/themes` – derived from `static/themes/*.css` headers
- `GET /api/v1/nav` – derived from `src/pages/demos/*.tsx`
- `GET /api/v1/{key}` – returns JSON for a YAML key
  - keys: badges, cvData, giscus, gitHub, gitHubLinks, globalConfig, navBarLinks, portfolioData, projects, version

Projects (editable storage)

- `GET /api/v1/projects` – combined nested structure from storage if present, else YAML fallback
- `GET /api/v1/projects/raw` – flat list of stored projects with `category`, `subCategory`, `slug`
- `GET /api/v1/projects/:category/:sub/:slug` – read one project file
- `PUT /api/v1/projects/:category/:sub/:slug?` – create/update one project (requires `x-admin-token` if `ADMIN_TOKEN` is set); if `:slug` omitted, derived from title
- `DELETE /api/v1/projects/:category/:sub/:slug` – delete one project (requires token)

Storage

- Set `PROJECT_REPOSITORY` to `database` and configure `DATABASE_URL` to use the TypeORM-backed repository.
- Files under `api/storage/projects/<category>/<subCategory>/<slug>.json`
- Atomic writes with timestamped backups (`.bak`)

Auth

- Set env `ADMIN_TOKEN` to require `x-admin-token` header for write/delete.

Hand-testing auth (`/api/auth/login`, distinct from `ADMIN_TOKEN` above)

- Don't write the request body or the cookie jar to a tracked path -- a
  cookie jar and a login payload were committed here before, holding a real
  (if expired) JWT and hardcoded `admin`/`admin` credentials.
- Pass the body inline, and write the cookie jar somewhere untracked
  (`api/*.local.json` is gitignored, or use `/dev/null` if you don't need the
  cookie):

  ```bash
  curl -c api/cookies.local.json -H "Content-Type: application/json" \
    -d '{"username":"admin","password":"admin"}' \
    http://localhost:4000/api/auth/login
  ```

Environment

- `PORT` (default 4000)
- `BASE_PATH` (default `/api`)
- `CORS_ORIGIN` (default `*`)

Notes

- Phase 1 reads directly from `../config/*.yml`. We can extend with derived resources (themes, nav) by refactoring shared logic from `scripts/pre-build.ts` into reusable modules and exposing `/api/v1/themes`, `/api/v1/nav`.
  API and Admin Editor

Overview

- Fastify + TypeScript server that serves configuration data previously authored as YAML and exposes editable projects storage.
- Admin editor page in the Docusaurus app at /admin/projects provides a polished UI to browse, filter, import/export, and edit per‑project JSON files.

Run

- API dev: pnpm --dir api dev (http://localhost:4000/api)
- Docs + API: pnpm dev:with-api
- Swagger UI: http://localhost:4000/api/docs
- Protect writes: set ADMIN_TOKEN before starting the API, and use the same token inside the Admin page’s Settings (gear icon).

Security

- Env ADMIN_TOKEN: if set, PUT/DELETE endpoints require header x-admin-token: <token>.
- CORS: enabled for all origins by default; adjust with CORS_ORIGIN.

Environment

- PORT: API port (default 4000)
- BASE_PATH: API base path (default /api)
- CORS_ORIGIN: CORS origin(s) (default \*)
- ADMIN_TOKEN: write protection token (optional but recommended)

Endpoints

- GET /api/health: Service health
- GET /api/v1: List available resources
- GET /api/v1/{key}: Raw YAML-backed JSON (badges, cvData, giscus, gitHub, gitHubLinks, globalConfig, navBarLinks, portfolioData, projects, version)
- GET /api/v1/themes: Derived from static/themes/\*.css header comments (@theme-id, @theme-name)
- GET /api/v1/nav: Derived from src/pages/demos/\*.tsx

Projects Storage (editable)

- Layout: api/storage/projects/<category>/<subCategory>/<slug>.json
- Each file contains a single project object:
  {
  "title": "My Project",
  "summary": "Short summary...",
  "lastModified": "2025-01-23T14:23:00.000Z",
  "link": "https://...",
  "tags": ["TypeScript", "Fastify"]
  }

Project Endpoints

- GET /api/v1/projects: Combined nested categories/subCategories/projects from storage if present; falls back to config/projects.yml.
- GET /api/v1/projects/raw: Flat list with category, subCategory, slug, and project.
- GET /api/v1/projects/:category/:sub/:slug: Read a single project file.
- PUT /api/v1/projects/:category/:sub/:slug: Create/update a project (requires x-admin-token if ADMIN_TOKEN is set).
- DELETE /api/v1/projects/:category/:sub/:slug: Delete a project (requires x-admin-token if ADMIN_TOKEN is set).

Validation

- Payloads validated with a relaxed schema: title (required), summary (required), tags (string[]), lastModified (string | Date), link (optional string).
- PUT normalizes lastModified to ISO string.

Migration

- Split config/projects.yml into per‑project files under storage.
- Command: pnpm --dir api migrate:projects [-- --overwrite]

Examples

- Read combined projects: curl http://localhost:4000/api/v1/projects
- Read one: curl http://localhost:4000/api/v1/projects/Frontend/React/portfolio
- Save: curl -X PUT -H "Content-Type: application/json" -H "x-admin-token: <token>" \
  -d '{"title":"Demo","summary":"...","tags":["TS"],"lastModified":"2025-01-01T00:00:00.000Z"}' \
  http://localhost:4000/api/v1/projects/Demos/General/demo
- Delete: curl -X DELETE -H "x-admin-token: <token>" http://localhost:4000/api/v1/projects/Demos/General/demo

Admin Editor (/admin/projects)

Tabs

- Projects: full‑width card grid with powerful filters and bulk actions.
- Edit Project: full‑page editor for creating or updating a project.

Filters

- Search: centered search box (sticky under navbar).
- Date: Most Recent by default; switches to All Time when searching.
- Category & Tags: same UX as the Projects page with tiered tags.
- Active Chips: compact chips show active Search/Filter/Date; “Clear All” resets.

Selection & Bulk

- Actions: Select All (filtered), Clear Selection, Delete Selected (with count).
- Sticky: actions bar stays visible while scrolling.
- Keyboard:
  - / focuses Search
  - A selects all filtered
  - C clears selection
  - Delete deletes selected
  - E edits first selected

Cards

- Layout: same look as the Projects page cards; hover lift.
- Badges: category, sub‑category, and Updated for recent changes.
- Quick menu (⋮): Edit, Copy Slug, Copy Link, Delete.
- Skeletons: animated placeholders while loading.

Import/Export

- Export (Filtered): downloads a JSON containing only visible projects (by current filters).
- Import JSON: uploads JSON [{ category, subCategories: [{ name, projects: [...] }] }]; all projects are PUT to the API.

Editor

- Category/Sub‑Category: select existing or choose “+ Add new…” to provide a new value.
- Slug: editable with a live computed preview and “Generate” button from Title.
- Title: auto‑focus on entering the Edit tab.
- Link: inline validator and “Test” button to open in new tab.
- Last Modified: datetime‑local picker; stored as ISO string (previewed inline).
- Tags: chip editor (Enter/comma/Add to add; × to remove).
- Validation: inline hints for URL format and date parsing.
- Save: PUTs to /api/v1/projects/:category/:sub/:slug; requires x-admin-token if ADMIN_TOKEN is set.

Settings (Gear)

- Adjust API Base and Admin Token from the modal (saved to localStorage).

Notes

- The Projects tab displays only items that pass current filters; the Edit tab reads/writes per‑file JSON and the combined API reflects changes immediately.
- Undo: bulk delete actions surface a toast with Undo to restore deleted items.
