# نشر تحديثات الويب (عشان التعديلات تظهر على الموقع)

## نشر تلقائي من GitHub (بعد الإعداد مرة واحدة)

الـ workflow **Remote Update** يبني الويب ويرفعه على السيرفر مع كل **push إلى main**. تحتاج تضبط الـ Secrets مرة واحدة حسب الطريقة اللي عندك:

### خيار أ: عبر Cloudflare Tunnel (الوضع الافتراضي)

1. في **Cloudflare Zero Trust** أنشئ **Service Token** (Access → Service Auth → Create Service Token) واسمح له في سياسة الـ Application الخاصة بـ `ssh-deploy.easytecheg.net`.
2. في **GitHub → Secrets** أضف:
   - `WEB_DEPLOY_PATH` = مسار الـ app (مثلاً `/mnt/marichia/files/easytech-new-api/app`)
   - `SERVER_SSH_KEY` = المفتاح الخاص لـ SSH
   - `CF_SERVICE_TOKEN_ID` = من الـ Service Token
   - `CF_SERVICE_TOKEN_SECRET` = من الـ Service Token
3. **لا تضف** `USE_DIRECT_SSH_FOR_CI` إلا لو تستخدم **خيار ب**. وجود `DIRECT_SSH_HOST` وحده **لا يفعّل** SSH من CI — يُستخدم **Tunnel** فقط.

### خيار ب: SSH مباشر من GitHub Actions (نادر — لازم السيرفر يقبل SSH من الإنترنت على بورت 22)

من **GitHub → Secrets** أضف **كل** التالي:

| Secret | القيمة |
|--------|--------|
| `USE_DIRECT_SSH_FOR_CI` | **`1`** أو **`true`** (بدون هذا الـ Secret لن يُستخدم SSH المباشر حتى لو وُجد `DIRECT_SSH_HOST`) |
| `DIRECT_SSH_HOST` | عنوان السيرفر (دومين أو IP **عام** يصل إليه GitHub) |
| `WEB_DEPLOY_PATH` | مسار مجلد الـ app، مثلاً `/mnt/marichia/files/easytech-new-api/app` |
| `SERVER_SSH_KEY` | المفتاح الخاص (Private Key) |

لو مش `root`: أضف `SSH_DEPLOY_USER`. الـ Public Key المقابل لـ `SERVER_SSH_KEY` لازم يكون في `authorized_keys` على السيرفر.

بعد ضبط الـ Secrets: **push إلى main** → الـ workflow يبني ويرفع تلقائياً.
افتح **https://api.easytecheg.net/app** واعمل Ctrl+F5.

لو الـ workflow فشل، روح **Actions** → آخر run → شوف أي خطوة وقفت ورسالة الخطأ.

### خطأ: `websocket: bad handshake` أو `Connection closed` مع Cloudflare

ده **مش من كود المشروع**؛ يعني `cloudflared access tcp` ما قدرش يكمّل مصادقة **Cloudflare Access** من عند GitHub.

**اعمل بالترتيب:**

1. **Zero Trust → Access → Service Auth**  
   أنشئ **Service Token** جديد (أو تأكد إن القديم لسه صالح)، وانسخ **Client ID** و **Client Secret**.

2. **نفس التطبيق (Application)** اللي مربوط بـ `ssh-deploy.easytecheg.net`  
   في **Policies** لازم يكون مسموح لـ **Service Auth** / الـ token ده (حسب واجهة Cloudflare: تضمين Service Token في السياسة أو تفعيله للتطبيق).

3. **GitHub → Settings → Secrets → Actions**  
   حدّث:
   - `CF_SERVICE_TOKEN_ID` = Client ID  
   - `CF_SERVICE_TOKEN_SECRET` = Client Secret  
   (من غير مسافات زائدة أو أسطر فاضية في آخر القيمة.)

4. **سياسات إضافية**  
   لو عندك **IP Access rules** أو WAF يمنع عناوين **GitHub-hosted runners**، ممكن يفشل الاتصال — راجع السجلات في Cloudflare.

5. **اختبار من جهازك** (بنفس الـ token):
   ```bash
   export TUNNEL_SERVICE_TOKEN_ID="..."   # نفس CF_SERVICE_TOKEN_ID
   export TUNNEL_SERVICE_TOKEN_SECRET="..."
   cloudflared access tcp --hostname ssh-deploy.easytecheg.net
   ```
   لو فشل هنا كمان، المشكلة 100% في Cloudflare/التوكن وليس في GitHub.

## التحقق من الاتصال والمسار (قبل أي تعديل)

لو حابب تتأكد إن الاتصال بالسيرفر ومسار الـ app شغالين، شغّل من جذر المشروع:

```bash
# تحقق فقط (ما يرفعش أي ملفات)
DEPLOY_PATH="${WEB_DEPLOY_PATH:-/mnt/marichia/files/easytech-new-api/app}"
ssh -o StrictHostKeyChecking=no -o "ProxyCommand=cloudflared access tcp --hostname ssh-deploy.easytecheg.net" root@ssh-deploy.easytecheg.net "mkdir -p '$DEPLOY_PATH' && ls -la '$DEPLOY_PATH' && echo 'OK: path ready'"
```

لو طلع `OK: path ready` يبقى الاتصال والمسار مضبوطين. لو استخدمت SSH مباشر بدل cloudflared، استبدل الأمر بـ:

```bash
ssh -o StrictHostKeyChecking=no root@YOUR_SERVER_IP "mkdir -p '$DEPLOY_PATH' && ls -la '$DEPLOY_PATH' && echo 'OK'"
```

---

## الطريقة 1: سكربت من جهازك (مضمونة)

من جذر المشروع شغّل:

```bash
chmod +x scripts/deploy-web.sh
./scripts/deploy-web.sh
```

السكربت يعمل: بناء الويب ثم رفعها للسيرفر عبر SSH.

- **لو بتصل السيرفر عبر Cloudflare tunnel:** ثبّت `cloudflared` ثم سجّل دخول:
  ```bash
  # Mac
  brew install cloudflared
  cloudflared access login
  ```
  بعدها شغّل السكربت كالعادة.
- **لو عندك SSH مباشر (IP أو دومين):** شغّل بدون cloudflared:
  ```bash
  USE_DIRECT_SSH=1 SSH_HOST=your-server-ip ./scripts/deploy-web.sh
  ```
- لو المسار مختلف: `export WEB_DEPLOY_PATH=/مسار/مجلد/app` قبل التشغيل.

بعدها افتح **https://api.easytecheg.net/app** واعمل Ctrl+F5.

---

## الطريقة 2: رفع يدوي (لو SSH أو cloudflared مش شغال)

لو السكربت فشل (cloudflared غير مثبّت أو `Operation timed out`)، اعمل البناء ثم ارفع من **File Browser**:

### على جهازك (في مجلد المشروع)

```bash
# 1. بناء الويب (مهم: --base-href=/app/ عشان الروابط على الدومين)
flutter pub get
flutter build web --release --base-href=/app/
```

بعدها محتاج ترفع محتويات مجلد **build/web** على السيرفر لمجلد الـ app. حسب طريقة الاتصال:

### لو عندك SSH على السيرفر (مع Cloudflared أو مباشر)

```bash
# استبدل مسار المجلد بالمسار الصحيح لمجلد app على السيرفر
rsync -avz --delete build/web/ user@server:/mnt/marichia/files/easytech-new-api/app/
```

### لو بتستخدم File Browser (مثل الصورة اللي عندك)

1. على جهازك: افتح مجلد المشروع ثم **build/web**
2. انسخ **كل** الملفات والملفات الفرعية (index.html و main.dart.js و assets و غيره)
3. في المتصفح: روح `files.easytecheg.net` → **data** → **easytech-new-api** → **app**
4. احذف محتويات مجلد **app** القديمة (أو امسحهم) ثم الصق المحتوى الجديد من **build/web**

بعدها حدّث الموقع (Ctrl+F5).

---

## لو التعديلات لسه مش ظاهرة

1. **تأكد من Actions:** روح GitHub → تبويب **Actions** → شغّل **Remote Update** الأخير. لو فشل (علامة حمراء)، افتح الـ run واقرأ الخطوة اللي فشلت.
2. **نشر يدوي (مضمون):**
   - على جهازك: من مجلد المشروع شغّل `flutter build web --release --base-href=/app/`.
   - افتح المجلد **build/web** (فيه index.html و main.dart.js و assets).
   - من **File Browser** على السيرفر: ادخل مجلد **app** (تحت easytech-new-api)، **احذف كل الملفات** من جوه app، ثم **ارفع كل محتويات build/web** (السحب والإفلات أو Upload).
   - افتح `https://api.easytecheg.net/app` واعمل **Ctrl+F5** (تحديث قوي).
