# إعداد السيرفر عشان الـ API يشتغل (إزالة 404)

الـ backend عندك في: `/mnt/marichia/files/easytech-new-api/backend/` وفيه `router.php`.

لو الطلبات لـ `https://api.easytecheg.net/trpc/...` أو `/api/trpc/...` راجعة **404**، يبقى الويب سيرفر (Nginx أو Apache) مش موجّه الطلبات لـ `router.php`. لازم تضيف قاعدة (rewrite / location) عشان أي طلب للـ API يروح لـ `router.php`.

---

## لو السيرفر Nginx

في الـ server block بتاع `api.easytecheg.net` ضيف أو تأكد من وجود حاجة زي:

```nginx
server {
    listen 443 ssl;
    server_name api.easytecheg.net;
    root /mnt/marichia/files/easytech-new-api/backend;

    index router.php;

    # توجيه كل الطلبات لـ router.php (ما عدا الملفات الموجودة فعلاً)
    location / {
        try_files $uri $uri/ /router.php?$query_string;
    }

    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_pass unix:/run/php/php-fpm.sock;   # أو 127.0.0.1:9000 حسب إعدادك
    }
}
```

أو لو عايز فقط مسارات الـ trpc:

```nginx
location ~ ^/(api/)?trpc/ {
    rewrite ^/(api/)?trpc/(.*)$ /router.php last;
}
```

---

## لو السيرفر Apache

فعّل `mod_rewrite` ثم في الـ VirtualHost أو في ملف `.htaccess` داخل مجلد الـ backend:

```apache
<IfModule mod_rewrite.c>
    RewriteEngine On
    RewriteBase /
    # لو الطلب مش لملف أو مجلد موجود، إرسله لـ router.php
    RewriteCond %{REQUEST_FILENAME} !-f
    RewriteCond %{REQUEST_FILENAME} !-d
    RewriteRule ^(api/)?trpc/.* router.php [L,QSA]
</IfModule>
```

أو توجيه كل الطلبات:

```apache
RewriteRule ^(.*)$ router.php [L,QSA]
```

---

## بعد التعديل

- أعد تشغيل أو أعد تحميل الويب سيرفر (مثلاً `sudo systemctl reload nginx` أو `sudo systemctl reload apache2`).
- جرّب من المتصفح أو من التطبيق: الطلب لـ `https://api.easytecheg.net/trpc/auth.adminLogin` (أو `/api/trpc/...`) المفروض يروح لـ `router.php` ويُرجع JSON مش 404.

---

## التأكد من الرابط اللي التطبيق بيطلبه

افتح الموقع من المتصفح، اضغط F12 → تبويب **Network**، ثم اعمل محاولة تسجيل دخول. ادوس على الطلب اللي رجع 404 وشوف الـ **Request URL**. ده اللي لازم الويب سيرفر يوجّهه لـ `router.php`.
