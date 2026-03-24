<?php
/**
 * TrueNAS / سيرفر: استرجاع إعدادات قاعدة البيانات من نسخة router.php احتياطية إلى router.php الحالي.
 *
 * الاستخدام (كـ root على السيرفر):
 *   php restore_router_db_from_backup.php
 *   php restore_router_db_from_backup.php /root/easytech-local-backup/router.php
 *
 * يعمل نسخة احتياطية من router.php الحالي باسم router.php.bak.YYYYMMDD-HHMMSS ثم يستبدل:
 *   - كتلة $dbHost / $dbName / $dbUser / $dbPass
 *   - سطر PDO داخل كتلة Facebook Webhook
 *
 * ملاحظة: شغّل من نفس المجلد backend/ أو مرّر مسار PHP صحيح للسكربت.
 */
declare(strict_types=1);

$backupPath = $argv[1] ?? '/root/easytech-local-backup/router.php';
$routerPath = __DIR__ . '/router.php';

if (!is_readable($backupPath)) {
    fwrite(STDERR, "[FAIL] ملف النسخة الاحتياطية غير موجود أو غير قابل للقراءة:\n  {$backupPath}\n");
    exit(1);
}
if (!is_readable($routerPath) || !is_writable($routerPath)) {
    fwrite(STDERR, "[FAIL] router.php غير موجود أو غير قابل للكتابة:\n  {$routerPath}\n");
    exit(1);
}

$backup = file_get_contents($backupPath);
if ($backup === false) {
    fwrite(STDERR, "[FAIL] تعذر قراءة النسخة الاحتياطية.\n");
    exit(1);
}

/**
 * @return array{host:string,name:string,user:string,pass:string}|null
 */
function parse_db_assignments(string $php): ?array {
    $host = $name = $user = $pass = null;
    if (preg_match("/\\\$dbHost\s*=\s*'((?:\\\\'|[^'])*)'\s*;/s", $php, $m)) {
        $host = stripcslashes(str_replace("\\'", "'", $m[1]));
    } elseif (preg_match('/\$dbHost\s*=\s*"((?:\\\\.|[^"\\\\])*)"\s*;/s', $php, $m)) {
        $host = stripcslashes($m[1]);
    }
    if (preg_match("/\\\$dbName\s*=\s*'((?:\\\\'|[^'])*)'\s*;/s", $php, $m)) {
        $name = stripcslashes(str_replace("\\'", "'", $m[1]));
    } elseif (preg_match('/\$dbName\s*=\s*"((?:\\\\.|[^"\\\\])*)"\s*;/s', $php, $m)) {
        $name = stripcslashes($m[1]);
    }
    if (preg_match("/\\\$dbUser\s*=\s*'((?:\\\\'|[^'])*)'\s*;/s", $php, $m)) {
        $user = stripcslashes(str_replace("\\'", "'", $m[1]));
    } elseif (preg_match('/\$dbUser\s*=\s*"((?:\\\\.|[^"\\\\])*)"\s*;/s', $php, $m)) {
        $user = stripcslashes($m[1]);
    }
    if (preg_match("/\\\$dbPass\s*=\s*'((?:\\\\'|[^'])*)'\s*;/s", $php, $m)) {
        $pass = stripcslashes(str_replace("\\'", "'", $m[1]));
    } elseif (preg_match('/\$dbPass\s*=\s*"((?:\\\\.|[^"\\\\])*)"\s*;/s', $php, $m)) {
        $pass = stripcslashes($m[1]);
    }
    if ($host === null || $name === null || $user === null || $pass === null) {
        return null;
    }
    return ['host' => $host, 'name' => $name, 'user' => $user, 'pass' => $pass];
}

$creds = parse_db_assignments($backup);
if ($creds === null) {
    fwrite(STDERR, "[FAIL] لم أستطع استخراج \$dbHost / \$dbName / \$dbUser / \$dbPass من النسخة الاحتياطية.\n");
    exit(1);
}

$current = file_get_contents($routerPath);
if ($current === false) {
    fwrite(STDERR, "[FAIL] تعذر قراءة router.php الحالي.\n");
    exit(1);
}

$bak = $routerPath . '.bak.' . date('Ymd-His');
if (!copy($routerPath, $bak)) {
    fwrite(STDERR, "[FAIL] تعذر إنشاء نسخة احتياطية: {$bak}\n");
    exit(1);
}
echo "[OK] نسخة قبل التعديل: {$bak}\n";

$h = addslashes($creds['host']);
$n = addslashes($creds['name']);
$u = var_export($creds['user'], true);
$p = var_export($creds['pass'], true);

$newBlock = <<<PHP
// ─── Database ──────────────────────────────────────────────────
\$dbHost = '{$h}';
\$dbName = '{$n}';
\$dbUser = {$u};
\$dbPass = {$p};

PHP;

$patternMain = '/\/\/ ─── Database ──────────────────────────────────────────────────\s*\n\$dbHost\s*=\s*[^;]+;\s*\n\$dbName\s*=\s*[^;]+;\s*\n\$dbUser\s*=\s*[^;]+;\s*\n\$dbPass\s*=\s*[^;]+;\s*\n/s';
if (!preg_match($patternMain, $current)) {
    fwrite(STDERR, "[FAIL] لم أجد كتلة قاعدة البيانات الرئيسية في router.php الحالي (تغيّر شكل الملف؟).\n");
    copy($bak, $routerPath);
    exit(1);
}
$current = preg_replace($patternMain, rtrim($newBlock) . "\n", $current, 1);

$webhookLine = '        $db = new PDO("mysql:host=' . $h . ';dbname=' . $n . ';charset=utf8mb4", ' . $u . ', ' . $p . ', [';
$patternWebhook = '/\s*\$db\s*=\s*new\s+PDO\s*\(\s*"mysql:host=[^"]+;\s*dbname=[^"]+;\s*charset=utf8mb4"\s*,\s*\'[^\']*\'\s*,\s*\'[^\']*\'\s*,\s*\[/s';
if (!preg_match($patternWebhook, $current)) {
    fwrite(STDERR, "[WARN] لم أجد سطر PDO في Webhook — تم تحديث الكتلة الرئيسية فقط.\n");
} else {
    $current = preg_replace($patternWebhook, "\n" . $webhookLine, $current, 1);
}

if (file_put_contents($routerPath, $current) === false) {
    fwrite(STDERR, "[FAIL] تعذر الكتابة على router.php — استرجاع من النسخة الاحتياطية.\n");
    copy($bak, $routerPath);
    exit(1);
}

echo "[OK] تم تطبيق إعدادات DB من النسخة الاحتياطية على router.php\n";
echo '[INFO] host=' . $creds['host'] . ' db=' . $creds['name'] . ' user=' . $creds['user'] . "\n";
echo "[INFO] جرّب الموقع؛ لو فيه خطأ استرجع: cp '{$bak}' '{$routerPath}'\n";
exit(0);
