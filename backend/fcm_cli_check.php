<?php
/**
 * تشغيل من SSH على السيرفر:
 *   php /mnt/marichia/files/easytech-new-api/backend/fcm_cli_check.php
 *
 * يتحقق من:
 *   1) وجود firebase-service-account.json (بدونه لن يعمل أي Push)
 *   2) الحصول على access token من Google (صلاحية الإرسال)
 *   3) اتصال MySQL + عدد صفوف fcm_tokens
 */
declare(strict_types=1);

$base = __DIR__;
$saPath = $base . '/firebase-service-account.json';

echo "=== FCM تشخيص سريع ===\n\n";

if (!file_exists($saPath)) {
    echo "[FAIL] الملف غير موجود:\n  $saPath\n\n";
    echo "الحل: من Firebase Console → Project settings → Service accounts → Generate new private key\n";
    echo "احفظ الملف باسم firebase-service-account.json داخل مجلد backend/ على السيرفر.\n";
    echo "(الملف سري — لا ترفعه إلى GitHub)\n";
    exit(1);
}
echo "[OK] ملف الخدمة موجود.\n";

require_once $base . '/notifications_procedures.php';

$access = _getFcmAccessToken();
if (!$access) {
    echo "[FAIL] لم يُحصل على access token من Google (تحقق من صلاحية JSON و openssl في PHP).\n";
    exit(2);
}
echo "[OK] تم الحصول على access token من Google.\n";

// اتصال DB مثل router.php
$dbHost = 'db_host';
$dbName = 'easytech_v2';
$dbUser = 'root';
$dbPass = 'EasyTech2026';

try {
    $db = new PDO(
        "mysql:host={$dbHost};dbname={$dbName};charset=utf8mb4",
        $dbUser,
        $dbPass,
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
    );
} catch (PDOException $e) {
    echo "[FAIL] قاعدة البيانات: " . $e->getMessage() . "\n";
    echo "(على TrueNAS/دوكر قد يكون host مختلفاً عن db_host — انسخ إعدادات الاتصال من نفس مكان router.php)\n";
    exit(3);
}

echo "[OK] اتصال MySQL ناجح.\n";

try {
    $n = (int) $db->query('SELECT COUNT(*) FROM fcm_tokens')->fetchColumn();
} catch (PDOException $e) {
    echo "[WARN] جدول fcm_tokens غير موجود أو خطأ: " . $e->getMessage() . "\n";
    exit(0);
}
echo "[INFO] عدد صفوف fcm_tokens: {$n}\n";
if ($n === 0) {
    echo "       → لا يوجد أي توكن جهاز؛ لن يصل Push لأحد حتى يسجّل المستخدمون دخولاً من التطبيق ويُحفظ التوكن.\n";
}

$nUsers = (int) $db->query('SELECT COUNT(DISTINCT user_id) FROM fcm_tokens')->fetchColumn();
echo "[INFO] مستخدمون لديهم توكن: {$nUsers}\n";

echo "\n=== انتهى. إذا [OK] فوق والعدد > 0 جرّب إشعاراً من التطبيق مرة أخرى ===\n";
exit(0);
