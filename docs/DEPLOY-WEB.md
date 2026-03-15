# نشر تحديثات الويب (عشان التعديلات تظهر على الموقع)

## الطريقة 1: سكربت من جهازك (مضمونة)

من جذر المشروع شغّل:

```bash
chmod +x scripts/deploy-web.sh
./scripts/deploy-web.sh
```

السكربت يعمل: بناء الويب ثم رفعها للسيرفر عبر SSH (Cloudflare tunnel).  
مطلوب: `cloudflared` و SSH مضبوطين (نفس الاتصال اللي بتستخدمه للسيرفر).  
لو المسار مختلف، قبل التشغيل: `export WEB_DEPLOY_PATH=/مسار/مجلد/app`

بعدها افتح **https://api.easytecheg.net/app** واعمل Ctrl+F5.

---

## الطريقة 2: أوامر يدوية من جهازك (بدون سكربت)

### على جهازك (في مجلد المشروع)

```bash
# 1. بناء الويب
flutter pub get
flutter build web --release
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
   - على جهازك: من مجلد المشروع شغّل `flutter build web --release`.
   - افتح المجلد **build/web** (فيه index.html و main.dart.js و assets).
   - من **File Browser** على السيرفر: ادخل مجلد **app** (تحت easytech-new-api)، **احذف كل الملفات** من جوه app، ثم **ارفع كل محتويات build/web** (السحب والإفلات أو Upload).
   - افتح `https://api.easytecheg.net/app` واعمل **Ctrl+F5** (تحديث قوي).
