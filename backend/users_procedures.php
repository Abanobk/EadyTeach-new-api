<?php

// ─── Users Profile Procedures ────────────────────────────────

function _users_ensureHomeAssistantColumns(): void {
    global $db;
    // Ensure columns exist (some deployments may be missing migrations)
    try { $db->exec('ALTER TABLE users ADD COLUMN IF NOT EXISTS ha_url TEXT NULL'); } catch (\Exception $e) {}
    try { $db->exec('ALTER TABLE users ADD COLUMN IF NOT EXISTS ha_token TEXT NULL'); } catch (\Exception $e) {}
}

function _users_getRoleById(int $userId): string {
    global $db;
    $stmt = $db->prepare('SELECT role FROM users WHERE id = ?');
    $stmt->execute([$userId]);
    $role = $stmt->fetchColumn();
    return trim(strtolower((string)($role ?? 'user')));
}

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

// ─── Home Assistant provisioning (Silent) ─────────────────────

function homeAssistant_getCredentials(array $ctx): array {
    global $db;
    $userId = (int)($ctx['userId'] ?? 0);
    if (!$userId) throw new Exception('UNAUTHORIZED');

    _users_ensureHomeAssistantColumns();

    $stmt = $db->prepare('SELECT ha_url, ha_token FROM users WHERE id = ?');
    $stmt->execute([$userId]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC) ?: [];

    $url = trim((string)($row['ha_url'] ?? ''));
    $token = trim((string)($row['ha_token'] ?? ''));

    return [
        'enabled' => ($url !== '' && $token !== ''),
        'haUrl' => $url,
        'haToken' => $token,
    ];
}

function admin_homeAssistantProvision(array $input, array $ctx): array {
    global $db;
    $userId = (int)($ctx['userId'] ?? 0);
    if (!$userId) throw new Exception('UNAUTHORIZED');

    $role = _users_getRoleById($userId);
    if (!in_array($role, ['admin', 'staff', 'supervisor'], true)) {
        throw new Exception('FORBIDDEN');
    }

    _users_ensureHomeAssistantColumns();

    $email = trim((string)($input['email'] ?? ''));
    $haUrl = trim((string)($input['haUrl'] ?? ''));
    $haToken = trim((string)($input['haToken'] ?? ''));

    if ($email === '') throw new Exception('email is required');
    if ($haUrl === '') throw new Exception('haUrl is required');
    if ($haToken === '') throw new Exception('haToken is required');

    // Normalize HA URL
    $haUrl = rtrim($haUrl, '/');
    // If user pasted "ha.domain:8123" without scheme, default to https
    if (!preg_match('/^https?:\/\//i', $haUrl)) {
        $haUrl = 'https://' . $haUrl;
    }

    $stmt = $db->prepare('SELECT id, email FROM users WHERE LOWER(email) = LOWER(?) LIMIT 1');
    $stmt->execute([$email]);
    $u = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$u) throw new Exception('User not found');

    $targetId = (int)($u['id'] ?? 0);
    if ($targetId <= 0) throw new Exception('User not found');

    $upd = $db->prepare('UPDATE users SET ha_url = ?, ha_token = ? WHERE id = ?');
    $upd->execute([$haUrl, $haToken, $targetId]);

    return ['success' => true, 'userId' => $targetId];
}

function admin_homeAssistantGetProvision(array $input, array $ctx): array {
    global $db;
    $userId = (int)($ctx['userId'] ?? 0);
    if (!$userId) throw new Exception('UNAUTHORIZED');

    $role = _users_getRoleById($userId);
    if (!in_array($role, ['admin', 'staff', 'supervisor'], true)) {
        throw new Exception('FORBIDDEN');
    }

    _users_ensureHomeAssistantColumns();

    $email = trim((string)($input['email'] ?? ''));
    if ($email === '') throw new Exception('email is required');

    $stmt = $db->prepare('SELECT id, email, ha_url, ha_token FROM users WHERE LOWER(email) = LOWER(?) LIMIT 1');
    $stmt->execute([$email]);
    $u = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$u) throw new Exception('User not found');

    $url = trim((string)($u['ha_url'] ?? ''));
    $token = trim((string)($u['ha_token'] ?? ''));
    $masked = $token === '' ? '' : ('…' . substr($token, max(0, strlen($token) - 6)));

    return [
        'userId' => (int)($u['id'] ?? 0),
        'email' => (string)($u['email'] ?? ''),
        'enabled' => ($url !== '' && $token !== ''),
        'haUrl' => $url,
        'tokenMasked' => $masked,
    ];
}

function admin_homeAssistantListClients(array $input, array $ctx): array {
    global $db;
    $userId = (int)($ctx['userId'] ?? 0);
    if (!$userId) throw new Exception('UNAUTHORIZED');

    $role = _users_getRoleById($userId);
    if (!in_array($role, ['admin', 'staff', 'supervisor'], true)) {
        throw new Exception('FORBIDDEN');
    }

    _users_ensureHomeAssistantColumns();

    $q = trim((string)($input['q'] ?? ''));
    $limit = (int)($input['limit'] ?? 200);
    if ($limit <= 0) $limit = 200;
    if ($limit > 500) $limit = 500;

    $params = [];
    $where = "WHERE COALESCE(role, 'user') = 'user'";
    if ($q !== '') {
        $where .= " AND (LOWER(email) LIKE LOWER(?) OR LOWER(name) LIKE LOWER(?))";
        $like = '%' . $q . '%';
        $params[] = $like;
        $params[] = $like;
    }

    $sql = "SELECT id, name, email, ha_url, ha_token FROM users $where ORDER BY id DESC LIMIT $limit";
    $stmt = $db->prepare($sql);
    $stmt->execute($params);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC) ?: [];

    $out = [];
    foreach ($rows as $r) {
        $url = trim((string)($r['ha_url'] ?? ''));
        $token = trim((string)($r['ha_token'] ?? ''));
        $masked = $token === '' ? '' : ('…' . substr($token, max(0, strlen($token) - 6)));
        $out[] = [
            'id' => (int)($r['id'] ?? 0),
            'name' => (string)($r['name'] ?? ''),
            'email' => (string)($r['email'] ?? ''),
            'enabled' => ($url !== '' && $token !== ''),
            'haUrl' => $url,
            'tokenMasked' => $masked,
        ];
    }

    return ['items' => $out];
}

