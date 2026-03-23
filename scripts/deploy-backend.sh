#!/usr/bin/env bash
# رفع مجلد backend/ إلى السيرفر (router.php، tasks_procedures، cron، إلخ)
# الاستخدام من جذر المشروع: ./scripts/deploy-backend.sh
#
# مثل deploy-web.sh: Cloudflare tunnel أو USE_DIRECT_SSH=1

set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BACKEND_PATH="${BACKEND_DEPLOY_PATH:-/mnt/marichia/files/easytech-new-api/backend}"
SSH_HOST="${SSH_HOST:-${SSH_DEPLOY_HOST:-ssh-deploy.easytecheg.net}}"
SSH_USER="${SSH_USER:-${SSH_DEPLOY_USER:-root}}"
CF_HOST="${CF_TUNNEL_HOST:-ssh-deploy.easytecheg.net}"

if [ ! -f backend/router.php ]; then
  echo "❌ Run from repo root (backend/router.php not found)"
  exit 1
fi

echo "▶ Packaging backend/ → deploy to $BACKEND_PATH ..."

if [ -n "${USE_DIRECT_SSH:-}" ] && [ "$USE_DIRECT_SSH" != "0" ]; then
  USE_TUNNEL=""
else
  if ! command -v cloudflared >/dev/null 2>&1; then
    echo ""
    echo "❌ cloudflared غير مثبّت أو استخدم: USE_DIRECT_SSH=1 ./scripts/deploy-backend.sh"
    exit 1
  fi
  USE_TUNNEL=1
fi

if [ -n "$USE_TUNNEL" ]; then
  tar czf - backend | ssh -o StrictHostKeyChecking=no \
    -o "ProxyCommand=cloudflared access tcp --hostname $CF_HOST" \
    "$SSH_USER@$SSH_HOST" "mkdir -p '$BACKEND_PATH' && cd '$BACKEND_PATH' && tar xzf - --strip-components=1 && echo Backend deployed to $BACKEND_PATH"
else
  tar czf - backend | ssh -o StrictHostKeyChecking=no \
    "$SSH_USER@$SSH_HOST" "mkdir -p '$BACKEND_PATH' && cd '$BACKEND_PATH' && tar xzf - --strip-components=1 && echo Backend deployed to $BACKEND_PATH"
fi

echo "✅ Backend deployed. أضف cron لتذكير المهام المتأخرة إن لم يكن مضافاً (انظر docs/TASK-OVERDUE-CRON-AR.md)."
