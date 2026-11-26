# devops-templates

Reusable GitHub Actions for Jonc. Studios projects: CI, Docker images on GHCR, and deploys with Docker Compose to the home server through a self-hosted runner.

Projects don't copy these files. They call them in a few lines, so an improvement here reaches every project. Start a new project from [project-template](https://github.com/DrCasual/project-template), which already has the calling workflows.

## The flow

```
feature/… ──PR──▶ main ──────────────────▶ tag v2026.11.0
   │                │                          │
   CI               build image sha-abc1234    promote sha-abc1234 → v2026.11.0 + latest
                    deploy → staging           deploy → production
                                               GitHub Release with notes
```

- **Pull request:** CI runs (lint, typecheck, tests, Docker build with smoke test). Nothing is pushed.
- **Merge to `main`:** the image is built once, tagged `sha-<7 chars>`, pushed to GHCR and deployed to staging.
- **Version tag (`v2026.11.0`, calendar versions):** the exact image that ran on staging gets the version tag and goes to production. No rebuild.

Branching and release conventions are in [docs/conventions.md](docs/conventions.md). Server setup is in [docs/server-setup.md](docs/server-setup.md).

## Reusable workflows

Call them with `uses: DrCasual/devops-templates/.github/workflows/<file>@v1`.

| Workflow | What it does | Main inputs |
|---|---|---|
| `ci-python.yml` | pip install, compile, `ruff check`, tests | `python-version`, `working-directory`, `requirements`, `lint-command`, `test-command` |
| `ci-node.yml` | `npm ci`, typecheck, lint, test, build | `node-version`, `working-directory`, `*-command` |
| `docker-image.yml` | build image, optional smoke test, optional push to GHCR as `sha-<7>` | `push`, `extra-tags`, `smoke-command`, `build-args` |
| `promote-image.yml` | add release tags to the image of this commit (builds it if missing) | `tags` (default: git tag + `latest`) |
| `deploy.yml` | deploy on a self-hosted runner: backup → pull → up → health check → rollback | `environment`, `image`, `deploy-dir`, `health-url`, `backup-command`, `runs-on`, `latest-only` (skip when the branch already moved on) |
| `github-release.yml` | GitHub Release with generated notes; `-rc` tags become pre-releases | `notes-prefix` |
| `pr-labels.yml` | label PRs `feature` / `fix` / `chore` from the branch prefix | — |

The composite action `actions/compose-deploy` does the actual deploy and can also be used on its own. It is tested for first deploy, upgrade, and rollback after a failed health check.

### What the app must provide

- A **Dockerfile** that accepts `ARG APP_COMMIT` and exposes it, for example in the health response. The deploy only counts as done when the health URL answers **and** contains the commit sha, so an old container that happens to be up does not count.
- A **health endpoint**, for example `GET /health` → `{"ok": true, "commit": "<sha>"}`.
- A **compose file** in the repo, by default `deploy/compose.yaml`. Its app service has `image: ghcr.io/<owner>/<repo>:latest` as a placeholder. The deploy writes the real tag to `compose.override.yaml` next to it, so `docker compose ps / logs / exec` keep working by hand on the server.

### What lives only on the server

`<deploy-dir>/.env` (secrets and `COMPOSE_PROJECT_NAME`), `data/` and database folders. The pipeline never writes them. It only writes `compose.yaml`, `compose.override.yaml`, `backups/` and `.deploy/` (current image and history).

## Versioning this repo

Callers use `@v1`. After a backwards-compatible change, move the `v1` tag:

```bash
git tag -f v1 && git push -f origin v1
```

A breaking change gets `v2`, and projects move over when they are ready.

## One-time GitHub settings

- **This repo, Settings → Actions → General → Access:** "Accessible from repositories owned by the user 'DrCasual'". Without this, private projects cannot call these workflows.
- **Each project, Settings → Actions → General → Workflow permissions:** "Read and write permissions".
