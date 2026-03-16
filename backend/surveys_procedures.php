<?php
/**
 * Smart Survey + Clients tRPC procedures for EasyTech backend
 *
 * Endpoints:
 *   surveys.create      – POST – Save a new survey
 *   surveys.mySurveys   – GET  – Surveys for the current user
 *   surveys.allSurveys  – GET  – All surveys (admin)
 *   clients.allUsers    – GET  – All users/clients list
 */

if (!isset($db) || !($db instanceof PDO)) {
    $dbHost = 'db_host';
    $dbName = 'easytech_v2';
    $dbUser = 'root';
    $dbPass = 'EasyTech2026';

    $dsn = "mysql:host={$dbHost};dbname={$dbName};charset=utf8mb4";

    try {
      $db = new PDO($dsn, $dbUser, $dbPass, [
        PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES   => false,
      ]);
    } catch (PDOException $e) {
      throw new Exception('Database connection failed: ' . $e->getMessage());
    }
}

// ─── surveys.create ─────────────────────────────────────────────
function surveys_create(array $input, $ctx): array {
    global $db;

    $projectName   = $input['projectName'] ?? 'مشروع بدون اسم';
    $clientId      = isset($input['clientId']) ? (int) $input['clientId'] : null;
    $clientEmail   = $input['clientEmail'] ?? null;
    $floors        = isset($input['floors']) ? json_encode($input['floors']) : null;
    $rooms         = isset($input['rooms']) ? json_encode($input['rooms']) : null;
    $lightingLines = (int) ($input['lightingLines'] ?? 0);
    $switchGroups  = isset($input['switchGroups']) ? json_encode($input['switchGroups']) : null;
    $acUnits       = (int) ($input['acUnits'] ?? 0);
    $tvUnits       = (int) ($input['tvUnits'] ?? 0);
    $curtains      = (int) ($input['curtains'] ?? 0);
    $curtainMeters = (float) ($input['curtainMeters'] ?? 0);
    $sensors       = isset($input['sensors']) ? json_encode($input['sensors']) : null;
    $notes         = $input['notes'] ?? null;
    $createdBy     = $ctx['userId'] ?? null;

    $stmt = $db->prepare('
        INSERT INTO surveys (
            project_name, client_id, client_email, floors, rooms,
            lighting_lines, switch_groups, ac_units, tv_units,
            curtains, curtain_meters, sensors, notes, created_by
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ');
    $stmt->execute([
        $projectName, $clientId, $clientEmail, $floors, $rooms,
        $lightingLines, $switchGroups, $acUnits, $tvUnits,
        $curtains, $curtainMeters, $sensors, $notes, $createdBy
    ]);

    return ['id' => (int) $db->lastInsertId()];
}

// ─── surveys.mySurveys ─────────────────────────────────────────
function surveys_mySurveys($ctx): array {
    global $db;

    $userId = $ctx['userId'] ?? null;
    if (!$userId) {
        throw new Exception('UNAUTHORIZED');
    }

    $stmt = $db->prepare('
        SELECT id, project_name, client_id, client_email,
               floors, rooms, lighting_lines, switch_groups,
               ac_units, tv_units, curtains, curtain_meters,
               sensors, notes, created_at, created_by
        FROM surveys
        WHERE client_id = ? OR created_by = ?
        ORDER BY created_at DESC
    ');
    $stmt->execute([$userId, $userId]);

    return _formatSurveyRows($stmt->fetchAll(PDO::FETCH_ASSOC));
}

// ─── surveys.allSurveys ────────────────────────────────────────
function surveys_allSurveys($ctx): array {
    global $db;

    $stmt = $db->query('
        SELECT id, project_name, client_id, client_email,
               floors, rooms, lighting_lines, switch_groups,
               ac_units, tv_units, curtains, curtain_meters,
               sensors, notes, created_at, created_by
        FROM surveys
        ORDER BY created_at DESC
    ');

    return _formatSurveyRows($stmt->fetchAll(PDO::FETCH_ASSOC));
}

// ─── clients.allUsers ──────────────────────────────────────────
function clients_allUsers($ctx): array {
    global $db;

    $stmt = $db->query('
        SELECT id, name, email, phone, role, address, location
        FROM users
        ORDER BY name ASC
    ');

    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
    $result = [];
    foreach ($rows as $row) {
        $result[] = [
            'id'       => (int) $row['id'],
            'name'     => $row['name'] ?? '',
            'email'    => $row['email'] ?? '',
            'phone'    => $row['phone'] ?? '',
            'role'     => $row['role'] ?? 'client',
            'address'  => $row['address'] ?? '',
            'location' => $row['location'] ?? '',
        ];
    }
    return $result;
}

// ─── clients.updateUserById ────────────────────────────────────
function clients_updateUserById(array $input, $ctx): array {
    global $db;
    $userId   = (int) ($input['userId'] ?? 0);
    if (!$userId) throw new Exception('userId مطلوب');

    $fields = [];
    $params = [];
    foreach (['name', 'email', 'phone', 'address', 'location'] as $f) {
        if (isset($input[$f])) {
            $col = $f;
            $fields[] = "$col = ?";
            $params[] = $input[$f];
        }
    }
    if (empty($fields)) return ['success' => true];
    $params[] = $userId;
    $db->prepare('UPDATE users SET ' . implode(', ', $fields) . ' WHERE id = ?')->execute($params);
    return ['success' => true];
}

// ─── clients.updateRole ────────────────────────────────────────
function clients_updateRole(array $input, $ctx): array {
    global $db;
    $userId = (int) ($input['userId'] ?? 0);
    $role   = $input['role'] ?? 'user';
    if (!$userId) throw new Exception('userId مطلوب');
    $db->prepare('UPDATE users SET role = ? WHERE id = ?')->execute([$role, $userId]);
    return ['success' => true];
}

// ─── clients.create ────────────────────────────────────────────
function clients_create(array $input, $ctx): array {
    global $db;
    $name     = $input['name'] ?? '';
    $email    = $input['email'] ?? null;
    $phone    = $input['phone'] ?? null;
    $address  = $input['address'] ?? null;
    $location = $input['location'] ?? null;
    $role     = $input['role'] ?? 'user';
    $passHash = password_hash('123456', PASSWORD_DEFAULT);

    if (!$email) {
        $email = 'client_' . time() . '@easytech.local';
    }

    $stmt = $db->prepare('INSERT INTO users (name, email, phone, address, location, role, password_hash) VALUES (?, ?, ?, ?, ?, ?, ?)');
    $stmt->execute([$name, $email, $phone, $address, $location, $role, $passHash]);
    return ['id' => (int) $db->lastInsertId()];
}

// ─── clients.delete ────────────────────────────────────────────
function clients_delete(array $input, $ctx): array {
    global $db;
    $userId = (int) ($input['userId'] ?? 0);
    if (!$userId) throw new Exception('userId مطلوب');
    $db->prepare('DELETE FROM users WHERE id = ?')->execute([$userId]);
    return ['success' => true];
}

// ─── clients.resetPassword ─────────────────────────────────────
function clients_resetPassword(array $input, $ctx): array {
    global $db;
    $userId = (int) ($input['userId'] ?? 0);
    $newPassword = $input['newPassword'] ?? null;
    if (!$userId) {
        throw new Exception('userId مطلوب');
    }
    if (!$newPassword || strlen($newPassword) < 6) {
        throw new Exception('كلمة المرور الجديدة مطلوبة ويجب ألا تقل عن 6 أحرف');
    }
    $hash = password_hash($newPassword, PASSWORD_BCRYPT);
    $db->prepare('UPDATE users SET password_hash = ? WHERE id = ?')->execute([$hash, $userId]);
    return ['success' => true];
}

// ─── surveys.update ─────────────────────────────────────────────
function surveys_update(array $input, $ctx): array {
    global $db;

    $id = (int) ($input['id'] ?? 0);
    if (!$id) throw new Exception('معرف المعاينة مطلوب');

    $projectName   = $input['projectName'] ?? 'مشروع بدون اسم';
    $clientId      = isset($input['clientId']) ? (int) $input['clientId'] : null;
    $clientEmail   = $input['clientEmail'] ?? null;
    $floors        = isset($input['floors']) ? json_encode($input['floors']) : null;
    $rooms         = isset($input['rooms']) ? json_encode($input['rooms']) : null;
    $lightingLines = (int) ($input['lightingLines'] ?? 0);
    $switchGroups  = isset($input['switchGroups']) ? json_encode($input['switchGroups']) : null;
    $acUnits       = (int) ($input['acUnits'] ?? 0);
    $tvUnits       = (int) ($input['tvUnits'] ?? 0);
    $curtains      = (int) ($input['curtains'] ?? 0);
    $curtainMeters = (float) ($input['curtainMeters'] ?? 0);
    $sensors       = isset($input['sensors']) ? json_encode($input['sensors']) : null;
    $notes         = $input['notes'] ?? null;

    $stmt = $db->prepare('
        UPDATE surveys SET
            project_name = ?, client_id = ?, client_email = ?,
            floors = ?, rooms = ?, lighting_lines = ?,
            switch_groups = ?, ac_units = ?, tv_units = ?,
            curtains = ?, curtain_meters = ?, sensors = ?, notes = ?
        WHERE id = ?
    ');
    $stmt->execute([
        $projectName, $clientId, $clientEmail, $floors, $rooms,
        $lightingLines, $switchGroups, $acUnits, $tvUnits,
        $curtains, $curtainMeters, $sensors, $notes, $id
    ]);

    return ['success' => true, 'id' => $id];
}

// ─── surveys.delete ─────────────────────────────────────────────
function surveys_delete(array $input, $ctx): array {
    global $db;

    $id = (int) ($input['id'] ?? 0);
    if (!$id) throw new Exception('معرف المعاينة مطلوب');

    $db->prepare('DELETE FROM surveys WHERE id = ?')->execute([$id]);
    return ['success' => true];
}

// ─── Helper ────────────────────────────────────────────────────
function _formatSurveyRows(array $rows): array {
    $result = [];
    foreach ($rows as $row) {
        $result[] = [
            'id'            => (int) $row['id'],
            'projectName'   => $row['project_name'],
            'clientId'      => $row['client_id'] ? (int) $row['client_id'] : null,
            'clientEmail'   => $row['client_email'],
            'floors'        => $row['floors'] ? json_decode($row['floors'], true) : [],
            'rooms'         => $row['rooms'] ? json_decode($row['rooms'], true) : [],
            'lightingLines' => (int) $row['lighting_lines'],
            'switchGroups'  => $row['switch_groups'] ? json_decode($row['switch_groups'], true) : null,
            'acUnits'       => (int) $row['ac_units'],
            'tvUnits'       => (int) $row['tv_units'],
            'curtains'      => (int) $row['curtains'],
            'curtainMeters' => (float) $row['curtain_meters'],
            'sensors'       => $row['sensors'] ? json_decode($row['sensors'], true) : null,
            'notes'         => $row['notes'],
            'createdAt'     => strtotime($row['created_at']) * 1000,
            'createdBy'     => $row['created_by'] ? (int) $row['created_by'] : null,
        ];
    }
    return $result;
}
