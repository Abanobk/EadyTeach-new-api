# دليل النشر — الطريقة الموحّدة

## ما الذي ينجح؟

الاتصال بالسيرفر يتم عبر **Cloudflare Access** على `ssh-deploy.easytecheg.net` (أمر `cloudflared access tcp`). هذه هي **الطريقة الافتراضية** في:

- `scripts/deploy-web.sh`
- `scripts/deploy-backend.sh`

**خطوة واحدة على جهازك (مرة لكل جهاز أو بعد انتهاء الجلسة):**

```bash
brew install cloudflared   # Mac
cloudflared access login
```

ثم من جذر المشروع:

```bash
./scripts/deploy-web.sh      # بناء الويب + رفع
./scripts/deploy-backend.sh  # رفع مجلد backend فقط
```

## ما الذي غالباً يفشل؟

**`USE_DIRECT_SSH=1`** يجبر SSH المباشر على المنفذ **22**. كثير من الشبكات والبيئات (ومنها بيئات CI) **لا تصل** إلى 22 فيظهر `Operation timed out`.  
لا تعتمد على ذلك إلا إذا تأكدت أن SSH المباشر يعمل من **نفس الجهاز** الذي تنشر منه.

## تفاصيل حسب المكوّن

| المكوّن | الملف |
|--------|--------|
| الويب (Flutter web) | [DEPLOY-WEB.md](./DEPLOY-WEB.md) |
| الـ Backend (PHP) | [DEPLOY-BACKEND.md](./DEPLOY-BACKEND.md) |
| Cron المهام | [TASK-OVERDUE-CRON-AR.md](./TASK-OVERDUE-CRON-AR.md) |
