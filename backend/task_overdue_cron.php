<?php
/**
 * 1) مهام متأخرة + 2) بلا موعد: تذكيران يوميان — 9 صباحاً و 6 مساءً (EASYTECH_TZ أو Africa/Cairo).
 * 3) تأخر وصول الفني للعميل بعد موعد المهمة: إشعار للفني والإدارة كل ساعة (حتى يُسجَّل وصول أو تُنجَز المهمة).
 * 4) السكرتارية: تذكير قبل الموعد (نافذة 24 ساعة)، تذكير قبل ساعة، وإشعار إن لم يُسجَّل التنفيذ بعد انتهاء الموعد.
 *
 * جدولة cron: كل ساعة (مثلاً 0 * * * *) — يشمل المهام والسكرتارية.
 * متغير اختياري: EASYTECH_TZ=Africa/Cairo
 *
 *   php /path/to/backend/task_overdue_cron.php
 *
 * على TrueNAS/دوكر: طابق host/user/pass مع router.php إن اختلفت.
 */
declare(strict_types=1);

$tz = getenv('EASYTECH_TZ') ?: 'Africa/Cairo';
date_default_timezone_set($tz);

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

$overdue = tasks_runOverdueReminders();
$unscheduled = tasks_runUnscheduledReminders();
$lateArrival = tasks_runLateArrivalReminders();
$appointments = appointments_runReminders();

echo json_encode(['overdue' => $overdue, 'unscheduled' => $unscheduled, 'lateArrival' => $lateArrival, 'appointments' => $appointments], JSON_UNESCAPED_UNICODE) . "\n";
