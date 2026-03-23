<?php
/**
 * تذكير المهام المتأخرة — تشغيل من cron كل 15–30 دقيقة
 *
 * أمثلة:
 *   php /path/to/backend/task_overdue_cron.php
 *   php /path/to/backend/task_overdue_cron.php 120   ← فاصل 120 دقيقة بين تذكيرين لنفس المهمة
 *
 * على TrueNAS/دوكر: طابق host/user/pass مع router.php إن اختلفت.
 */
declare(strict_types=1);

$base = __DIR__;

$dbHost = getenv('EASYTECH_DB_HOST') ?: 'db_host';
$dbName = getenv('EASYTECH_DB_NAME') ?: 'easytech_v2';
$dbUser = getenv('EASYTECH_DB_USER') ?: 'root';
$dbPass = getenv('EASYTECH_DB_PASS') ?: 'EasyTech2026';

try {
    $db = new PDO(
        "mysql:host={$dbHost};dbname={$dbName};charset=utf8mb4",
        $dbUser,
        $dbPass,
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
        ]
    );
} catch (PDOException $e) {
    fwrite(STDERR, "[FAIL] DB: " . $e->getMessage() . "\n");
    exit(1);
}

$GLOBALS['db'] = $db;

require_once $base . '/notifications_procedures.php';
require_once $base . '/tasks_procedures.php';

$interval = isset($argv[1]) ? (int) $argv[1] : 90;
$result = tasks_runOverdueReminders($interval);

echo json_encode($result, JSON_UNESCAPED_UNICODE) . "\n";
// مثال: {"sent":2,"tasks":2} — sent = عدد المهام التي أُرسل لها تذكير في هذه الجولة
