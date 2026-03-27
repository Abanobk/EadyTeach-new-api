#!/usr/bin/env bash
# رفع مجلد backend/ إلى السيرفر (router.php، tasks_procedures، cron، إلخ)
#
# الطريقة الموحّدة الناجحة (الافتراضية): Cloudflare Access TCP
#   brew install cloudflared && cloudflared access login
#   ./scripts/deploy-backend.sh
#
# لا تستخدم USE_DIRECT_SSH إلا إذا كان SSH على المنفذ 22 يعمل من جهازك؛
# غالباً يفشل بـ "timed out" — استخدم الافتراضي (Tunnel).
#
# التفاصيل: docs/DEPLOY-BACKEND.md

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

echo "[deploy] Packaging backend/ -> $BACKEND_PATH ..."

# macOS: تقليل xattr في الأرشيف (إن وُجد gtar من brew يُفضَّل — أقل تحذيرات على السيرفر)
_pack_backend() {
  if command -v gtar >/dev/null 2>&1; then
    gtar -czf - --format=gnu --owner=0 --group=0 backend
  else
    if [ "$(uname -s 2>/dev/null)" = "Darwin" ]; then
      COPYFILE_DISABLE=1 tar czf - backend
    else
      tar czf - backend
    fi
  fi
}

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
  _pack_backend | ssh -o StrictHostKeyChecking=no \
    -o "ProxyCommand=cloudflared access tcp --hostname $CF_HOST" \
    "$SSH_USER@$SSH_HOST" "mkdir -p '$BACKEND_PATH' && cd '$BACKEND_PATH' && tar xzf - --strip-components=1 && echo Backend deployed to $BACKEND_PATH"
else
  _pack_backend | ssh -o StrictHostKeyChecking=no \
    "$SSH_USER@$SSH_HOST" "mkdir -p '$BACKEND_PATH' && cd '$BACKEND_PATH' && tar xzf - --strip-components=1 && echo Backend deployed to $BACKEND_PATH"
fi

echo "[deploy] OK — Backend deployed. Cron: docs/TASK-OVERDUE-CRON-AR.md"
