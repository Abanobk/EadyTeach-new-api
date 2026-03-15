#!/usr/bin/env bash
# بناء ورفع الويب من جهازك → السيرفر (عبر Cloudflare tunnel)
# الاستخدام: من جذر المشروع شغّل: ./scripts/deploy-web.sh

set -e
cd "$(dirname "$0")/.."

# ─── إعدادات (عدّلها أو ضعها في .env) ───
DEPLOY_PATH="${WEB_DEPLOY_PATH:-/mnt/marichia/files/easytech-new-api/app}"
SSH_HOST="${SSH_DEPLOY_HOST:-ssh-deploy.easytecheg.net}"
SSH_USER="${SSH_DEPLOY_USER:-root}"
CF_HOST="${CF_TUNNEL_HOST:-ssh-deploy.easytecheg.net}"

echo "▶ Building web..."
flutter pub get
flutter build web --release

echo "▶ Deploying to $DEPLOY_PATH ..."
(cd build && tar czf - web) | ssh -o StrictHostKeyChecking=no \
  -o "ProxyCommand=cloudflared access tcp --hostname $CF_HOST" \
  "$SSH_USER@$SSH_HOST" "mkdir -p '$DEPLOY_PATH' && cd '$DEPLOY_PATH' && tar xzf - --strip-components=1 && echo Deployed to $DEPLOY_PATH"

echo "✅ Done. Open https://api.easytecheg.net/app and hard refresh (Ctrl+F5)."
