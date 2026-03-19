<?php

// ─── Users Profile Procedures ────────────────────────────────

function users_getProfile(array $ctx): array {
    global $db;
    $userId = (int)($ctx['userId'] ?? 0);
    if (!$userId) throw new Exception('UNAUTHORIZED');

    // Ensure columns exist (some deployments may be missing migrations)
    try { $db->exec('ALTER TABLE users ADD COLUMN IF NOT EXISTS address TEXT NULL'); } catch (\Exception $e) {}
    try { $db->exec('ALTER TABLE users ADD COLUMN IF NOT EXISTS location TEXT NULL'); } catch (\Exception $e) {}

    $stmt = $db->prepare('SELECT id, name, email, phone, address, location, role FROM users WHERE id = ?');
    $stmt->execute([$userId]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$row) throw new Exception('User not found');

    return [
        'id' => (int)($row['id'] ?? 0),
        'name' => $row['name'] ?? '',
        'email' => $row['email'] ?? '',
        'phone' => $row['phone'] ?? null,
        'address' => $row['address'] ?? '',
        'location' => $row['location'] ?? '',
        'role' => $row['role'] ?? 'user',
    ];
}

function users_updateProfile(array $input, array $ctx): array {
    global $db;
    $userId = (int)($ctx['userId'] ?? 0);
    if (!$userId) throw new Exception('UNAUTHORIZED');

    // Ensure columns exist
    try { $db->exec('ALTER TABLE users ADD COLUMN IF NOT EXISTS address TEXT NULL'); } catch (\Exception $e) {}
    try { $db->exec('ALTER TABLE users ADD COLUMN IF NOT EXISTS location TEXT NULL'); } catch (\Exception $e) {}

    $fields = [];
    $params = [];

    foreach (['name', 'phone', 'address', 'location'] as $f) {
        if (array_key_exists($f, $input)) {
            $fields[] = $f . ' = ?';
            $params[] = $input[$f];
        }
    }

    if (empty($fields)) return ['success' => true];

    $params[] = $userId;
    $sql = 'UPDATE users SET ' . implode(', ', $fields) . ' WHERE id = ?';
    $stmt = $db->prepare($sql);
    $stmt->execute($params);

    return ['success' => true];
}

