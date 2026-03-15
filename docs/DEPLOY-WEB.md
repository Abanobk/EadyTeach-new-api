# نشر تحديثات الويب (عشان التعديلات تظهر على الموقع)

## الطريقة 1: GitHub يعمل كل حاجة (مفضّلة)

### خطوة واحدة في GitHub (مرة واحدة فقط)

1. افتح الريبو على GitHub: **EadyTeach-new-api**
2. من فوق: **Settings** ← **Secrets and variables** ← **Actions**
3. اضغط **New repository secret**
4. **Name:** `WEB_DEPLOY_PATH`  
   **Value:** مسار مجلد الـ app على السيرفر، مثلاً:
   ```text
   /mnt/marichia/files/easytech-new-api/app
   ```
5. اضغط **Add secret**

### بعد كده

- أي مرة تعمل **push** لفرع `main`، GitHub هيعمل:
  - بناء الويب (Flutter)
  - رفع الملفات على مجلد الـ app
  - تحديث الكود على السيرفر
- افتح الموقع وحدّث الصفحة (Ctrl+F5): `https://api.easytecheg.net/app`

---

## الطريقة 2: أوامر يدوية من جهازك (بدون GitHub)

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
