<?php
/**
 * إرسال إشعار FCM تجريبي لمستخدم محدد (للتشخيص).
 *
 *   docker exec easytech_api_v2 php /var/www/html/backend/fcm_send_test_cli.php 12
 *
 * معرف المستخدم (USER_ID) من جدول users — أو بالإيميل:
 *   docker exec easytech_db_v2 mariadb -uroot -pEasyTech2026 easytech_v2 -N -e "SELECT id,email,role FROM users WHERE email='بريدك';"
 */
declare(strict_types=1);

$base = __DIR__;

if (PHP_SAPI !== 'cli') {
    fwrite(STDERR, "CLI only.\n");
    exit(1);
}

$userId = 0;
if ($argc >= 2 && is_numeric($argv[1])) {
    $userId = (int) $argv[1];
}
if ($userId < 1) {
    fwrite(STDERR, "Usage: php fcm_send_test_cli.php USER_ID\n");
    fwrite(STDERR, "Example: php fcm_send_test_cli.php 5\n");
    exit(1);
}

$dbHost = getenv('EASYTECH_DB_HOST') ?: 'db_host';
$dbName = getenv('EASYTECH_DB_NAME') ?: 'easytech_v2';
$dbUser = getenv('EASYTECH_DB_USER') ?: 'root';
$dbPass = getenv('EASYTECH_DB_PASS');
if ($dbPass === false || $dbPass === '') {
    $dbPass = 'EasyTech2026';
}

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
    fwrite(STDERR, '[FAIL] DB: ' . $e->getMessage() . "\n");
    exit(2);
}

$u = $db->prepare('SELECT id, email, role FROM users WHERE id = ?');
$u->execute([$userId]);
$row = $u->fetch();
if (!$row) {
    fwrite(STDERR, "[FAIL] لا يوجد مستخدم id={$userId}\n");
    exit(3);
}
echo '[INFO] User: id=' . $row['id'] . ' email=' . ($row['email'] ?? '') . ' role=' . ($row['role'] ?? '') . "\n";

$tks = $db->prepare('SELECT platform, LEFT(token, 36) AS tprefix FROM fcm_tokens WHERE user_id = ?');
$tks->execute([$userId]);
$toks = $tks->fetchAll();
if (!$toks) {
    echo "[WARN] لا توجد صفوف في fcm_tokens لهذا المستخدم — لن يُرسل Push (سيُحفظ سطر في notifications فقط).\n";
} else {
    echo "[INFO] توكنات لهذا المستخدم: " . count($toks) . "\n";
    foreach ($toks as $t) {
        echo '       - platform=' . ($t['platform'] ?? '?') . ' token…' . ($t['tprefix'] ?? '') . "\n";
    }
}

if (!is_file($base . '/firebase-service-account.json')) {
    fwrite(STDERR, "[FAIL] Missing backend/firebase-service-account.json\n");
    exit(4);
}

require_once $base . '/notifications_procedures.php';

$title = 'اختبار Easy Tech';
$body = 'إذا ظهر هذا الإشعار فالـ Push من السيرفر يعمل. ' . date('H:i:s');
_notifyUser($userId, $title, $body, 'general');

echo "[OK] تم تنفيذ _notifyUser. راقب الجوال خلال ثوانٍ، وراجع: docker logs easytech_api_v2 2>&1 | tail -20\n";
exit(0);
