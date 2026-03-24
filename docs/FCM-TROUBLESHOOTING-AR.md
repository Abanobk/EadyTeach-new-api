# استكشاف أخطاء إشعارات الخلفية (FCM) — Easy Tech

## أول خطوة على السيرفر (SSH)

بعد `git pull` قد **لا يوجد** ملف `backend/firebase-service-account.json` (ملف سري وغالباً غير مرفوع لـ Git). **بدون هذا الملف لن يُرسل أي Push من السيرفر.**

على السيرفر (عدّل المسار لو مختلف):

```bash
cd /mnt/marichia/files/easytech-new-api/backend
php fcm_cli_check.php
```

- إذا فشل اتصال MySQL رغم أن الـ API شغال: عيّن نفس قيم `router.php` كمتغيرات بيئة ثم أعد التشغيل، مثلاً:
  `EASYTECH_DB_HOST` `EASYTECH_DB_NAME` `EASYTECH_DB_USER` `EASYTECH_DB_PASS`
- إذا **لا يوجد** `firebase-service-account.json` → ارفعه يدوياً من Firebase (Service accounts → Generate new private key)، ولا ترفعه لـ GitHub.

**لو حابب حد يراجع معاك:** انسخ **كل مخرجات** `php fcm_cli_check.php` والصقها (من غير محتوى ملف JSON ولا كلمات مرور).

### بعد `git pull` على TrueNAS: استرجاع إعدادات DB في `router.php` بدون مقارنة يدوية

لو عندك نسخة احتياطية في `/root/easytech-local-backup/router.php` (زي ما اتعمل قبل الـ pull):

```bash
cd /mnt/marichia/files/easytech-new-api/backend
php restore_router_db_from_backup.php
```

السكربت ينسخ `router.php` الحالي إلى `router.php.bak.TIMESTAMP` ثم ينسخ من النسخة الاحتياطية قيم `$dbHost` / `$dbName` / `$dbUser` / `$dbPass` وسطر الـ Webhook.

### إرسال Push تجريبي لمستخدم واحد (بعد ما التقرير العام كان [OK])

1. اعرف `USER_ID` (من الإيميل — غيّر الباسورد إن لزم):

```bash
docker exec easytech_db_v2 mariadb -uroot -p'EasyTech2026' easytech_v2 -e "SELECT id,email,role FROM users WHERE email='ضع_إيميل_حساب_الموبايل';"
```

2. أرسل اختبار:

```bash
docker exec easytech_api_v2 php /var/www/html/backend/fcm_send_test_cli.php USER_ID
```

3. لو **ما ظهرش** على الموبايل لكن السكربت قال [OK]: راجع لوج الكونتينر:

```bash
docker logs easytech_api_v2 2>&1 | tail -50
```

ابحث عن `FCM send failed` أو `skip push`.

---

## مهم: الفرق بين «ظهر في التطبيق» و«Push في الشريط»

- **ظهر داخل التطبيق** = السيرفر سجّل الإشعار في جدول `notifications` بنجاح.
- **Push في الشريط** = يحتاج **توكن FCM** محفوظ في `fcm_tokens` لنفس **المستخدم** + إرسال FCM ناجح من السيرفر.

إذا ظهر الإشعار داخل التطبيق فقط، غالباً **لا يوجد توكن** أو **FCM فشل** أو **المستخدم المستهدف ليس هو الحساب على الموبايل**.

---

## 1) من يستقبل إشعار عند إنشاء مهمة؟

| الحالة | من يستقبل Push |
|--------|----------------|
| مهمة **بدون** فني | **فقط** مستخدمون بدور `admin` أو `supervisor` أو `staff` |
| مهمة **مع** فني معيّن | **الفني المعيّن** + **كل** admin/supervisor/staff |

لو الموبايل مسجّل دخول كـ **عميل** أو **فني غير معيّن** للمهمة، **لن يصله** إشعار «مهمة جديدة في النظام».

---

## 2) التحقق من توكن FCM في قاعدة البيانات

على السيرفر (MySQL)، استبدل البريد أو `id`:

```sql
SELECT u.id, u.email, u.role, u.is_active,
       f.platform, LEFT(f.token, 40) AS token_prefix, f.updated_at
FROM users u
LEFT JOIN fcm_tokens f ON f.user_id = u.id
WHERE u.email = 'your@email.com';
```

- **لا صف في `fcm_tokens`** → الموبايل لم يحفظ التوكن (سجّل دخولاً من التطبيق بعد السماح بالإشعارات).
- **`platform` = web** → حدّث التطبيق وأسجّل دخولاً مرة أخرى (النسخ الحديثة ترسل `android`).

---

## 3) هل الموقع يخدم نفس الملفات التي حدّثتها؟

على TrueNAS قد يكون المشروع في أكثر من مسار، والـ **Nginx / Docker** يشير لمسار **آخر**.

```bash
# قارن محتوى الملفين — لازم يكونوا متطابقين لو الاثنين مستخدمين
md5sum /mnt/marichia/files/easytech-new-api/backend/notifications_procedures.php
md5sum /mnt/pool/projects/easy-tech/backend/notifications_procedures.php
```

إذا اختلف الـ hash، انسخ الملف المحدّث إلى المسار الذي يخدم `api.easytecheg.net`.

---

## 4) سجلات PHP عند فشل FCM

بعد محاولة إنشاء مهمة، راجع `error_log` (مسار يختلف حسب الإعداد):

```bash
grep FCM /var/log/nginx/error.log
grep FCM /var/log/php*-fpm.log
```

رسائل مفيدة:

- `[FCM] notify skip push: user_id=... has NO rows in fcm_tokens` → لا توكن لهذا المستخدم.
- `FCM send failed (HTTP ...)` → مشروع Firebase غير مطابق، توكن منتهي، أو `firebase-service-account.json` خاطئ.

---

## 5) تطابق مشروع Firebase

- ملف **`backend/firebase-service-account.json`** على السيرفر يجب أن يكون من **نفس مشروع** `google-services.json` في تطبيق الأندرويد.
- إذا كان المشروع مختلفاً، FCM يرجع خطأ (مثل NOT_FOUND للتوكن).

---

## 6) أندرويد — إعدادات الجهاز

- **الإشعارات** مفعّلة للتطبيق (خاصة أندرويد 13+).
- تعطيل **توفير البطارية** / **التحسين** للتطبيق (شاومي، سامسونج، هواوي).
- فتح التطبيق مرة بعد تثبيته حتى تُنشأ قناة `easy_tech_v2`.

---

## 7) اختبار منطقي سريع

1. موبايل **admin** (أو staff) — سجّل دخولاً، انتظر ثوانٍ.
2. من الويب أنشئ مهمة **بدون** فني.
3. المفروض يصل Push لذلك الحساب فقط إن وُجد `fcm_tokens` له.

4. لمّا تعيّن فنياً: لازم الموبايل المفتوح بحساب **ذلك الفني** وليس حساباً آخر.
