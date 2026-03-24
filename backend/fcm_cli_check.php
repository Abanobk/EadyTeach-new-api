<?php
/**
 * تشغيل من SSH على السيرفر:
 *   php /path/to/backend/fcm_cli_check.php
 *
 * لو اتصال DB فشل لكن router.php شغال: عيّن نفس القيم كمتغيرات بيئة ثم أعد التشغيل:
 *   EASYTECH_DB_HOST EASYTECH_DB_NAME EASYTECH_DB_USER EASYTECH_DB_PASS
 *
 * يتحقق من:
 *   1) وجود firebase-service-account.json
 *   2) access token من Google
 *   3) اتصال MySQL + fcm_tokens + ملخص إشعارات أسبوع
 */
declare(strict_types=1);

$base = __DIR__;
$saPath = $base . '/firebase-service-account.json';

echo "=== FCM / إشعارات — تقرير سيرفر ===\n";
echo '[INFO] PHP ' . PHP_VERSION . ' | curl=' . (extension_loaded('curl') ? 'yes' : 'NO') . ' | openssl=' . (extension_loaded('openssl') ? 'yes' : 'NO') . " | pdo_mysql=" . (extension_loaded('pdo_mysql') ? 'yes' : 'NO') . "\n\n";

if (!file_exists($saPath)) {
    echo "[FAIL] ملف Firebase غير موجود:\n  $saPath\n\n";
    echo "الحل: Firebase Console → Project settings → Service accounts → Generate new private key\n";
    echo "احفظه كـ firebase-service-account.json داخل backend/ على السيرفر (لا ترفعه لـ GitHub).\n";
    exit(1);
}
echo "[OK] firebase-service-account.json موجود.\n";

require_once $base . '/notifications_procedures.php';

$access = _getFcmAccessToken();
if (!$access) {
    echo "[FAIL] لم يُحصل على access token من Google (JSON تالف؟ أو openssl؟ أو الشبكة؟).\n";
    exit(2);
}
echo "[OK] Google access token (Firebase Messaging) — ناجح.\n";

$dbHost = getenv('EASYTECH_DB_HOST') ?: 'db_host';
$dbName = getenv('EASYTECH_DB_NAME') ?: 'easytech_v2';
$dbUser = getenv('EASYTECH_DB_USER') ?: 'root';
$dbPass = getenv('EASYTECH_DB_PASS');
if ($dbPass === false || $dbPass === '') {
    $dbPass = 'EasyTech2026';
}

echo '[INFO] DB: host=' . $dbHost . ' db=' . $dbName . ' user=' . $dbUser;
if (getenv('EASYTECH_DB_HOST') || getenv('EASYTECH_DB_NAME') || getenv('EASYTECH_DB_USER') || getenv('EASYTECH_DB_PASS')) {
    echo ' (من متغيرات البيئة EASYTECH_DB_*)';
}
echo "\n";

try {
    $db = new PDO(
        "mysql:host={$dbHost};dbname={$dbName};charset=utf8mb4",
        $dbUser,
        $dbPass,
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        ]
    );
} catch (PDOException $e) {
    echo '[FAIL] MySQL: ' . $e->getMessage() . "\n";
    echo "جرّب من نفس الجلسة:\n";
    echo "  export EASYTECH_DB_HOST=... EASYTECH_DB_NAME=... EASYTECH_DB_USER=... EASYTECH_DB_PASS=...\n";
    echo "  php " . __FILE__ . "\n";
    exit(3);
}

echo "[OK] اتصال MySQL ناجح.\n";

try {
    $n = (int) $db->query('SELECT COUNT(*) FROM fcm_tokens')->fetchColumn();
} catch (PDOException $e) {
    echo '[WARN] fcm_tokens: ' . $e->getMessage() . "\n";
    exit(0);
}
echo "[INFO] صفوف fcm_tokens (كل التوكنات): {$n}\n";
if ($n === 0) {
    echo "       → مفيش توكن على السيرفر = مفيش Push حتى يفتح المستخدم التطبيق ويسجّل دخول ويسمح بالإشعارات.\n";
}

$nUsers = (int) $db->query('SELECT COUNT(DISTINCT user_id) FROM fcm_tokens')->fetchColumn();
echo "[INFO] مستخدمون لديهم توكن (مميزون): {$nUsers}\n";

try {
    $byPlat = $db->query(
        "SELECT COALESCE(NULLIF(TRIM(platform), ''), 'empty') AS p, COUNT(*) AS c FROM fcm_tokens GROUP BY p ORDER BY c DESC"
    )->fetchAll();
    if ($byPlat) {
        echo "[INFO] توكنات حسب platform:\n";
        foreach ($byPlat as $row) {
            echo "       - {$row['p']}: {$row['c']}\n";
        }
    }
} catch (PDOException $e) {
    echo '[WARN] تجميع platform: ' . $e->getMessage() . "\n";
}

try {
    $w = (int) $db->query(
        "SELECT COUNT(*) FROM notifications WHERE created_at > DATE_SUB(NOW(), INTERVAL 7 DAY)"
    )->fetchColumn();
    echo "[INFO] سجلات notifications (آخر 7 أيام): {$w}\n";
} catch (PDOException $e) {
    echo '[WARN] عدّ notifications: ' . $e->getMessage() . "\n";
}

echo "\n=== انتهى التقرير — انسخ كل النص أعلاه وأرسله للدعم ===\n";
exit(0);
