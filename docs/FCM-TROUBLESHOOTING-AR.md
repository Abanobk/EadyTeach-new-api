# استكشاف أخطاء إشعارات الخلفية (FCM) — Easy Tech

## أول خطوة على السيرفر (SSH)

بعد `git pull` قد **لا يوجد** ملف `backend/firebase-service-account.json` (ملف سري وغالباً غير مرفوع لـ Git). **بدون هذا الملف لن يُرسل أي Push من السيرفر.**

على السيرفر:

```bash
ls -la /mnt/marichia/files/easytech-new-api/backend/firebase-service-account.json
php /mnt/marichia/files/easytech-new-api/backend/fcm_cli_check.php
```

- إذا `ls` قال **No such file** → ارفع الملف يدوياً من Firebase Console (Project settings → Service accounts → Generate new private key).
- سكربت `fcm_cli_check.php` يتحقق من الملف + token Google + عدد صفوف `fcm_tokens`.

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
