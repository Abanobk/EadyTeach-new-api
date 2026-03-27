#!/usr/bin/env bash
# بناء ورفع الويب من جهازك → السيرفر (build/web بعد flutter build ناجح)
#
# الطريقة الموحّدة الناجحة (الافتراضية): Cloudflare Access TCP
#   brew install cloudflared && cloudflared access login
#   ./scripts/deploy-web.sh
#
# USE_DIRECT_SSH=1 فقط إذا كان SSH المباشر على 22 يعمل — وإلا استخدم الافتراضي.
#
# التفاصيل: docs/DEPLOY-WEB.md

set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DEPLOY_PATH="${WEB_DEPLOY_PATH:-/mnt/marichia/files/easytech-new-api/app}"
# SSH_HOST أو SSH_DEPLOY_HOST (الأول له الأولوية)
SSH_HOST="${SSH_HOST:-${SSH_DEPLOY_HOST:-ssh-deploy.easytecheg.net}}"
SSH_USER="${SSH_USER:-${SSH_DEPLOY_USER:-root}}"
CF_HOST="${CF_TUNNEL_HOST:-ssh-deploy.easytecheg.net}"
BASE_HREF="${WEB_BASE_HREF:-/app/}"

echo "▶ Building web (base-href=$BASE_HREF)..."
flutter pub get
flutter build web --release --base-href="$BASE_HREF"

if [ ! -f build/web/index.html ]; then
  echo "❌ Build failed: build/web/index.html not found"
  exit 1
fi
echo "▶ Build OK. Deploying latest build/web to $DEPLOY_PATH ..."

if [ "$(uname -s 2>/dev/null)" = "Darwin" ]; then
  export COPYFILE_DISABLE=1
fi

if [ -n "${USE_DIRECT_SSH:-}" ] && [ "$USE_DIRECT_SSH" != "0" ]; then
  USE_TUNNEL=""
else
  if ! command -v cloudflared >/dev/null 2>&1; then
    echo ""
    echo "❌ cloudflared غير مثبّت. ثبّته ثم: cloudflared access login"
    echo "   أو شغّل: USE_DIRECT_SSH=1 ./scripts/deploy-web.sh"
    exit 1
  fi
  USE_TUNNEL=1
fi

if [ -n "$USE_TUNNEL" ]; then
  (cd build && tar czf - web) | ssh -o StrictHostKeyChecking=no \
    -o "ProxyCommand=cloudflared access tcp --hostname $CF_HOST" \
    "$SSH_USER@$SSH_HOST" "mkdir -p '$DEPLOY_PATH' && cd '$DEPLOY_PATH' && tar xzf - --strip-components=1 && echo Deployed to $DEPLOY_PATH"
else
  (cd build && tar czf - web) | ssh -o StrictHostKeyChecking=no \
    "$SSH_USER@$SSH_HOST" "mkdir -p '$DEPLOY_PATH' && cd '$DEPLOY_PATH' && tar xzf - --strip-components=1 && echo Deployed to $DEPLOY_PATH"
fi

echo "✅ Done. Open https://api.easytecheg.net/app and hard refresh (Ctrl+F5)."
