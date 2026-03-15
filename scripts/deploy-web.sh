#!/usr/bin/env bash
# بناء ورفع الويب من جهازك → السيرفر
# الاستخدام: من جذر المشروع شغّل: ./scripts/deploy-web.sh
#
# لو بتصل السيرفر عبر Cloudflare tunnel: ثبّت cloudflared ثم شغّل السكربت:
#   Mac: brew install cloudflared
#   ثم سجّل دخول: cloudflared access login
#
# لو عندك SSH مباشر (بدون tunnel): شغّل بدون cloudflared:
#   USE_DIRECT_SSH=1 ./scripts/deploy-web.sh
#   وضبط SSH_HOST لـ IP أو دومين السيرفر.

set -e
cd "$(dirname "$0")/.."

DEPLOY_PATH="${WEB_DEPLOY_PATH:-/mnt/marichia/files/easytech-new-api/app}"
SSH_HOST="${SSH_DEPLOY_HOST:-ssh-deploy.easytecheg.net}"
SSH_USER="${SSH_DEPLOY_USER:-root}"
CF_HOST="${CF_TUNNEL_HOST:-ssh-deploy.easytecheg.net}"

echo "▶ Building web..."
flutter pub get
flutter build web --release

if [ -n "${USE_DIRECT_SSH:-}" ] && [ "$USE_DIRECT_SSH" != "0" ]; then
  USE_TUNNEL=""
else
  if ! command -v cloudflared >/dev/null 2>&1; then
    echo ""
    echo "❌ cloudflared غير مثبّت. السكربت بيستخدمه للاتصال بالسيرفر."
    echo "   ثبّته ثم جرّب تاني:"
    echo "     Mac:   brew install cloudflared"
    echo "     ثم:   cloudflared access login"
    echo ""
    echo "   لو بتصل السيرفر مباشرة (بدون tunnel) شغّل:"
    echo "     USE_DIRECT_SSH=1 ./scripts/deploy-web.sh"
    exit 1
  fi
  USE_TUNNEL=1
fi

echo "▶ Deploying to $DEPLOY_PATH ..."
if [ -n "$USE_TUNNEL" ]; then
  (cd build && tar czf - web) | ssh -o StrictHostKeyChecking=no \
    -o "ProxyCommand=cloudflared access tcp --hostname $CF_HOST" \
    "$SSH_USER@$SSH_HOST" "mkdir -p '$DEPLOY_PATH' && cd '$DEPLOY_PATH' && tar xzf - --strip-components=1 && echo Deployed to $DEPLOY_PATH"
else
  (cd build && tar czf - web) | ssh -o StrictHostKeyChecking=no \
    "$SSH_USER@$SSH_HOST" "mkdir -p '$DEPLOY_PATH' && cd '$DEPLOY_PATH' && tar xzf - --strip-components=1 && echo Deployed to $DEPLOY_PATH"
fi

echo "✅ Done. Open https://api.easytecheg.net/app and hard refresh (Ctrl+F5)."
