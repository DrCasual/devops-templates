#!/usr/bin/env bash
# Deploy a Docker Compose app to a folder on this machine, with backup,
# health check and automatic rollback to the previous image.
#
# Called by the compose-deploy action; every setting comes from the environment:
#   DEPLOY_DIR        folder with .env, data and the running stack (required)
#   IMAGE             full image reference to deploy, e.g. ghcr.io/me/app:sha-abc123 (required)
#   COMPOSE_SRC       compose file from the repo checkout, copied to DEPLOY_DIR/compose.yaml (required)
#   SERVICE           service in the compose file that runs IMAGE (default: app)
#   HEALTH_URL        URL that must answer 2xx after the deploy (required)
#   HEALTH_EXPECT     text the health response must contain (optional, e.g. the commit sha)
#   HEALTH_TIMEOUT    seconds to wait for a healthy app (default: 120)
#   BACKUP_CMD        command run in DEPLOY_DIR before deploying (optional)
#   KEEP_BACKUPS      number of files to keep in DEPLOY_DIR/backups (default: 14)
set -euo pipefail

: "${DEPLOY_DIR:?DEPLOY_DIR is required}"
: "${IMAGE:?IMAGE is required}"
: "${COMPOSE_SRC:?COMPOSE_SRC is required}"
: "${HEALTH_URL:?HEALTH_URL is required}"
SERVICE="${SERVICE:-app}"
HEALTH_EXPECT="${HEALTH_EXPECT:-}"
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-120}"
BACKUP_CMD="${BACKUP_CMD:-}"
KEEP_BACKUPS="${KEEP_BACKUPS:-14}"

log() { printf '\n==> %s\n' "$*"; }
fail() { printf '::error::%s\n' "$*"; exit 1; }

[ -d "$DEPLOY_DIR" ] || fail "Deploy folder $DEPLOY_DIR does not exist. Prepare the server first (see docs/server-setup.md)."
[ -f "$DEPLOY_DIR/.env" ] || fail "$DEPLOY_DIR/.env is missing. Create it on the server; it is never deployed from git."
[ -f "$COMPOSE_SRC" ] || fail "Compose file $COMPOSE_SRC not found in the checkout."

cp "$COMPOSE_SRC" "$DEPLOY_DIR/compose.yaml"
cd "$DEPLOY_DIR"
mkdir -p .deploy backups

previous="$(cat .deploy/current 2>/dev/null || true)"

write_override() {
  # compose.override.yaml is loaded automatically, so manual commands
  # (docker compose ps / logs / exec) keep using the deployed image.
  cat > compose.override.yaml <<EOF
# Written by the deploy pipeline. Do not edit: the next deploy overwrites it.
services:
  ${SERVICE}:
    image: $1
EOF
}

healthy() {
  local deadline=$((SECONDS + HEALTH_TIMEOUT)) body
  while [ "$SECONDS" -lt "$deadline" ]; do
    if body="$(curl -fsS --max-time 5 "$HEALTH_URL" 2>/dev/null)"; then
      if [ -z "$HEALTH_EXPECT" ] || grep -qF -- "$HEALTH_EXPECT" <<<"$body"; then
        echo "Healthy: $body"
        return 0
      fi
    fi
    sleep 3
  done
  return 1
}

if [ -n "$BACKUP_CMD" ]; then
  log "Backup"
  bash -c "$BACKUP_CMD"
  # keep the newest $KEEP_BACKUPS files
  # shellcheck disable=SC2012
  ls -1t backups | tail -n +"$((KEEP_BACKUPS + 1))" | while read -r old; do rm -f -- "backups/$old"; done
fi

log "Deploying $IMAGE (previous: ${previous:-none})"
write_override "$IMAGE"
docker compose pull "$SERVICE"
docker compose up -d --remove-orphans

log "Health check $HEALTH_URL"
if healthy; then
  echo "$IMAGE" > .deploy/current
  printf '%s\t%s\n' "$(date -u +%FT%TZ)" "$IMAGE" >> .deploy/history
  docker image prune -f >/dev/null || true
  log "Deployed $IMAGE"
  exit 0
fi

echo "::group::Logs of $SERVICE"
docker compose logs --tail 100 "$SERVICE" || true
echo "::endgroup::"

if [ -n "$previous" ] && [ "$previous" != "$IMAGE" ]; then
  log "Rolling back to $previous"
  write_override "$previous"
  docker compose up -d --remove-orphans
  HEALTH_EXPECT="" healthy || echo "::warning::Rollback is up but not healthy either. Check the server."
  fail "Deploy of $IMAGE failed its health check; rolled back to $previous."
fi
fail "Deploy of $IMAGE failed its health check and there is no previous version to roll back to."
