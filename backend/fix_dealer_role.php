<?php
// سكربت لمرة واحدة لتكبير حقل role في users وإضافة/تحديث دور dealer في جدول roles

$dbHost = 'db_host';
$dbName = 'easytech_v2';
$dbUser = 'root';
$dbPass = 'EasyTech2026';

try {
    $db = new PDO(
        "mysql:host={$dbHost};dbname={$dbName};charset=utf8mb4",
        $dbUser,
        $dbPass,
        [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false,
        ]
    );
} catch (PDOException $e) {
    http_response_code(500);
    echo 'DB connection failed: ' . htmlspecialchars($e->getMessage());
    exit;
}

try {
    // 1) تكبير عمود role في users
    $db->exec("ALTER TABLE users MODIFY COLUMN role VARCHAR(50) NOT NULL");

    // 2) إضافة / تحديث دور dealer في جدول roles
    $sql = "INSERT INTO roles (slug, name, name_ar, color, is_active)
            VALUES ('dealer', 'Dealer', 'تاجر', '#FF9800', 1)
            ON DUPLICATE KEY UPDATE
              name    = VALUES(name),
              name_ar = VALUES(name_ar),
              color   = VALUES(color),
              is_active = VALUES(is_active)";
    $db->exec($sql);

    echo 'OK: role column updated and dealer role ensured.';
} catch (PDOException $e) {
    http_response_code(500);
    echo 'Migration error: ' . htmlspecialchars($e->getMessage());
}

