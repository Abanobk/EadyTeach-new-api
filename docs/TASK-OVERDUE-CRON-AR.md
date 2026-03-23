# تذكير المهام المتأخرة (إشعارات متكررة)

## السلوك

- إذا كانت المهمة **ليست** `completed` أو `cancelled`، وعليها **فني** (`technician_id`)، و**تجاوز موعدها**:
  - بوجود **`estimated_arrival_at`**: يُعتبر التأخير عندما يصبح الوقت الحالي **بعد** هذا الحقل.
  - بدون **`estimated_arrival_at`** ومع **`scheduled_at`**:
    - إذا كان وقت الجدولة **ليس** منتصف الليل (`00:00:00`)، يُقارن التاريخ/الوقت بـ **الآن**.
    - إذا كان **تاريخ يوم فقط** (وقت `00:00:00`)، تُعتبر متأخرة من **بداية اليوم التالي** لذلك التاريخ.
- يُرسل إشعار إلى **الفني** وإلى **المشرفين/الإداريين/Staff** (نفس منطق `_notifyAdminsAndSupervisors`).
- التكرار **محدود**: لا يُرسل تذكير جديد لنفس المهمة إلا بعد مرور **فترة** (افتراضياً **90 دقيقة**) من آخر إشعار تأخير، حتى يُتخذ إجراء (إنجاز، إلغاء، أو **ترحيل** الموعد).

## قاعدة البيانات

يُضاف تلقائياً عمود (مرة واحدة):

- `tasks.overdue_last_notified_at` — وقت آخر إشعار تأخير.

عند **ترحيل** الموعد (`scheduledAt` / `estimatedArrivalAt`) أو عند **`completed` / `cancelled`** يُصفَّر هذا العمود حتى لا تُمنع التذكيرات بعد موعد جديد.

## التشغيل (Cron)

1. تأكد أن **FCM** يعمل (`firebase-service-account.json` في `backend/`).
2. أضف سطر cron على السيرفر (مثال كل **20 دقيقة**):

```cron
*/20 * * * * /usr/bin/php /المسار/الكامل/backend/task_overdue_cron.php >> /var/log/easytech-overdue.log 2>&1
```

3. لتغيير فاصل التذكير لنفس المهمة (بالدقائق)، مثلاً **120**:

```cron
*/20 * * * * /usr/bin/php /path/backend/task_overdue_cron.php 120 >> /var/log/easytech-overdue.log 2>&1
```

## متغيرات بيئة (اختياري)

إن كان MySQL على host غير `db_host`:

```bash
export EASYTECH_DB_HOST=127.0.0.1
export EASYTECH_DB_NAME=easytech_v2
export EASYTECH_DB_USER=root
export EASYTECH_DB_PASS=كلمة_السر
php task_overdue_cron.php
```

## مخرجات السكربت

سطر JSON، مثال: `{"sent":2,"tasks":2}`

- `tasks`: عدد المهام المؤهلة في هذه الجولة.
- `sent`: عدد المهام التي أُرسل لها تذكير بنجاح (تحديث `overdue_last_notified_at`).
