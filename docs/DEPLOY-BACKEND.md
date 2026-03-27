# نشر تحديثات الـ Backend (PHP)

## الطريقة الأسهل: File Browser (بدون Terminal)

لو **مش عايز** `cloudflared` ولا SSH، ارفع الملفات من المتصفح — نفس فكرة رفع الـ **app** في `DEPLOY-WEB.md`.

### على جهازك (المشروع)

1. افتح المجلد:
   ```
   .../flutter_app 2/backend/
   ```
2. لازم يكون فيه على الأقل: `router.php` وباقي ملفات الـ PHP (مثل `tasks_procedures.php`, `notifications_procedures.php`, …).

### على السيرفر (File Browser)

1. ادخل على **File Browser** عندكم (مثلاً `files.easytecheg.net` — حسب ما عندكم).
2. تنقّل إلى المسار الذي يضم **الـ API**، غالباً:
   - **data** → **easytech-new-api** → **backend**  
   (نفس المسار اللي السكربت يرفع له: `.../easytech-new-api/backend`).
3. **احذف** محتويات مجلد `backend` القديمة *أو* استبدل الملفات المعدّلة فقط (الأضمن: رفع كل محتويات `backend` من جهازك فوق الموجود).
4. ارفع **كل** الملفات والمجلدات الفرعية من مجلد `backend` على الماك إلى مجلد `backend` على السيرفر (سحب وإفلات أو Upload).

### بعد الرفع

- جرّب الموقع/التطبيق. لو فيه **cache** على السيرفر امسحه أو انتظر دقيقة.
- ملفات الـ **cron** (مثل `task_overdue_cron.php`) لو موجودة في `backend/` تُرفع مع الباقي.

---

## الطريقة التلقائية: سكربت (`deploy-backend.sh`)

السيرفر يُستهدف عبر **Cloudflare Access** على المضيف `ssh-deploy.easytecheg.net` — **ليس** SSH مباشر على المنفذ 22 من كل الشبكات. لذلك:

1. ثبّت `cloudflared` ثم سجّل دخول Access مرة على الأقل:
   ```bash
   brew install cloudflared
   ```
   إذا ظهر **«Please provide the url of the Access application»**، مرّر **رابط تطبيق Access** الخاص بفريقك (من Cloudflare Zero Trust → Access → التطبيق)، مثلاً:
   ```bash
   cloudflared access login "https://YOUR_TEAM.cloudflareaccess.com"
   ```
   (`YOUR_TEAM` = نطاق الفريق الحقيقي من المسؤول — لا تستخدم نصاً عربياً داخل الرابط.)

2. (اختياري لماك) لتقليل تحذيرات `tar` على السيرفر عند استخراج الأرشيف:
   ```bash
   brew install gnu-tar
   ```
   السكربت يستخدم `gtar` تلقائياً إن وُجد.

3. من **جذر المشروع** (بدون `USE_DIRECT_SSH`):
   ```bash
   chmod +x scripts/deploy-backend.sh
   ./scripts/deploy-backend.sh
   ```

يرفع مجلد `backend/` إلى المسار الافتراضي على السيرفر (يمكن تغييره بـ `BACKEND_DEPLOY_PATH`).

### أخطاء شائعة

| المشكلة | السبب | الحل |
|--------|--------|------|
| `command not found: cloudflared` | غير مثبّت أو خارج الـ PATH | `brew install cloudflared` ثم أعد فتح الطرفية |
| `failed to parse as URL` / `https://#` | غالباً لصق سطرين معاً أو تعليق `#` أفسد الأمر | نفّذ `cloudflared access login` **في سطر لوحده** (بدون تعليق عربي بعده في نفس السطر)، ثم في سطر جديد `./scripts/deploy-backend.sh` |
| تحذيرات `tar: LIBARCHIVE.xattr` | macOS يضيف خصائص للملفات | غير ضار؛ ثبّت `gnu-tar` (`gtar`) أو اعتمد على `COPYFILE_DISABLE` في السكربت |
| **`quote>`** أو `command not found: tar` بعد النشر | لصق **مخرجات الطرفية** (أسطر تبدأ بـ `tar:` أو `▶` أو `Backend deployed`) داخل الطرفية كأنها أوامر | **لا تلصق المخرجات.** اضغط **Ctrl+C** لإلغاء السطر؛ اكتب الأمر فقط `./scripts/deploy-backend.sh` |
| `zsh: command not found: ▶` أو `✅` | لصق سطر يبدأ برمز من مخرجات السكربت | السكربت يعرض الآن نصاً ASCII فقط لتقليل الخطأ |

---

## نشر Backend من GitHub Actions (زي الأول)

الـ workflow `Remote Update` يدعم الآن تشغيل يدوي مع اختيار نوع النشر:

1. افتح GitHub → **Actions** → **Remote Update** → **Run workflow**.
2. في `deploy_target` اختَر:
   - `backend` لنشر الـ Backend فقط (بدون Build Web).
   - `both` لنشر الويب + الـ Backend.
3. شغّل الـ workflow.

ملاحظات مهمة:
- لو `BACKEND_DEPLOY_PATH` غير موجود في Secrets، سيتم استخدام الافتراضي:
  `/mnt/marichia/files/easytech-new-api/backend`
- لازم يكون موجود `SERVER_SSH_KEY`.
- لو النشر عبر Tunnel: لازم `CF_SERVICE_TOKEN_ID` و `CF_SERVICE_TOKEN_SECRET`.
- لو SSH مباشر من CI: فعّل `USE_DIRECT_SSH_FOR_CI=1` مع `DIRECT_SSH_HOST`.

---

## متى يُستخدم `USE_DIRECT_SSH=1`؟

فقط إذا كان عندك **SSH مباشر** يعمل من جهازك (دومين أو IP يفتح المنفذ 22):

```bash
USE_DIRECT_SSH=1 SSH_HOST=your-ip-or-host ./scripts/deploy-backend.sh
```

إذا ظهر **`Operation timed out`** على المنفذ 22، فـ SSH المباشر **غير متاح** من شبكتك الحالية — **لا تعتمد عليه**؛ استخدم الطريقة الافتراضية أعلاه (Tunnel).

---

## متغيرات اختيارية

| المتغير | المعنى |
|--------|--------|
| `BACKEND_DEPLOY_PATH` | مسار `backend` على السيرفر (افتراضي: `/mnt/marichia/files/easytech-new-api/backend`) |
| `SSH_HOST` / `SSH_DEPLOY_HOST` | يُستخدم مع Tunnel أو مع SSH المباشر |
| `SSH_USER` / `SSH_DEPLOY_USER` | المستخدم (افتراضي: `root`) |
| `CF_TUNNEL_HOST` | مضيف Cloudflare (افتراضي: `ssh-deploy.easytecheg.net`) |

---

## بعد النشر

- تأكد من **cron** لتشغيل `task_overdue_cron.php` إن لزم (انظر `docs/TASK-OVERDUE-CRON-AR.md`).

---

## ربط مع نشر الويب

نفس فلسفة الاتصال موضّحة في **`docs/DEPLOY-WEB.md`** (Tunnel = الطريقة الموصى بها؛ الرفع اليدوي عبر File Browser بديل عند تعذّر الأدوات).
