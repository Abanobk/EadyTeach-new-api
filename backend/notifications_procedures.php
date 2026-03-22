<?php
/**
 * Notifications Module – نظام الإشعارات الفورية
 *
 * Tables:
 *   notifications  – كل الإشعارات المخزنة
 *   fcm_tokens     – توكنات FCM لكل مستخدم
 *
 * Uses Firebase Cloud Messaging HTTP v1 API via Service Account JWT
 */

function _ensureNotificationsSchema() {
    global $db;

    $db->exec("CREATE TABLE IF NOT EXISTS notifications (
        id INT AUTO_INCREMENT PRIMARY KEY,
        user_id INT NOT NULL,
        title VARCHAR(255) NOT NULL,
        body TEXT,
        type VARCHAR(50) DEFAULT 'general',
        ref_id INT DEFAULT NULL,
        ref_type VARCHAR(50) DEFAULT NULL,
        data JSON DEFAULT NULL,
        is_read BOOLEAN DEFAULT FALSE,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_user (user_id),
        INDEX idx_read (is_read),
        INDEX idx_type (type)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    $db->exec("CREATE TABLE IF NOT EXISTS fcm_tokens (
        id INT AUTO_INCREMENT PRIMARY KEY,
        user_id INT NOT NULL,
        token TEXT NOT NULL,
        platform VARCHAR(20) DEFAULT 'web',
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        INDEX idx_user (user_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    $db->exec("CREATE TABLE IF NOT EXISTS notification_campaigns (
        id INT AUTO_INCREMENT PRIMARY KEY,
        title VARCHAR(255) NOT NULL,
        body TEXT,
        target_type VARCHAR(30) DEFAULT 'all',
        target_role VARCHAR(50) DEFAULT NULL,
        link_type VARCHAR(50) DEFAULT NULL,
        link_id INT DEFAULT NULL,
        sent_count INT DEFAULT 0,
        created_by INT DEFAULT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
}

// ─── FCM Sending via HTTP v1 API ──────────────────────────────

function _getFcmAccessToken() {
    $saPath = __DIR__ . '/firebase-service-account.json';
    if (!file_exists($saPath)) {
        error_log('FCM: Service account file not found at ' . $saPath);
        return null;
    }

    $sa = json_decode(file_get_contents($saPath), true);
    if (!$sa || empty($sa['private_key']) || empty($sa['client_email'])) {
        error_log('FCM: Invalid service account JSON');
        return null;
    }

    $now = time();
    $header = base64_encode(json_encode(['alg' => 'RS256', 'typ' => 'JWT']));
    $claim = base64_encode(json_encode([
        'iss' => $sa['client_email'],
        'scope' => 'https://www.googleapis.com/auth/firebase.messaging',
        'aud' => 'https://oauth2.googleapis.com/token',
        'iat' => $now,
        'exp' => $now + 3600,
    ]));

    $header = strtr($header, '+/', '-_');
    $claim = strtr($claim, '+/', '-_');
    $header = rtrim($header, '=');
    $claim = rtrim($claim, '=');

    $signInput = $header . '.' . $claim;
    $key = openssl_pkey_get_private($sa['private_key']);
    if (!$key) {
        error_log('FCM: Failed to load private key');
        return null;
    }
    openssl_sign($signInput, $signature, $key, OPENSSL_ALGO_SHA256);
    $sig = rtrim(strtr(base64_encode($signature), '+/', '-_'), '=');

    $jwt = $signInput . '.' . $sig;

    $ch = curl_init('https://oauth2.googleapis.com/token');
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST => true,
        CURLOPT_POSTFIELDS => http_build_query([
            'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
            'assertion' => $jwt,
        ]),
        CURLOPT_HTTPHEADER => ['Content-Type: application/x-www-form-urlencoded'],
        CURLOPT_TIMEOUT => 10,
    ]);
    $resp = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if ($httpCode !== 200) {
        error_log('FCM: Token exchange failed: ' . $resp);
        return null;
    }

    $data = json_decode($resp, true);
    return $data['access_token'] ?? null;
}

/**
 * @param string $platform من جدول fcm_tokens: android | ios | web
 *
 * أندرويد: نرسل notification + data بأولوية HIGH وقناة easy_tech_v2 — النظام يعرض الإشعار في الشريط
 * حتى والتطبيق مغلق (لا يعتمد على Dart background isolate). رسالة data-only كانت تفشل غالباً
 * في الظهور في الخلفية على كثير من الأجهزة.
 * iOS / Web: notification + data كما سبق.
 *
 * ملاحظة: حقول android.notification في FCM HTTP v1 تستخدم camelCase (channelId، defaultVibrateTimings).
 */
function _sendFcmMessage($token, $title, $body, $data = [], $platform = 'web') {
    static $accessToken = null;
    if ($accessToken === null) {
        $accessToken = _getFcmAccessToken();
    }

    if (!$accessToken) {
        error_log('FCM: No access token, cannot send');
        return false;
    }

    $saPath = __DIR__ . '/firebase-service-account.json';
    $sa = json_decode(file_get_contents($saPath), true);
    $projectId = $sa['project_id'] ?? 'easytech2';

    $platformNorm = strtolower(trim((string)$platform));
    // أجهزة قديمة قد تُحفظ كـ unknown — عاملها مثل أندرويد لعرض الإشعار في الشريط
    if ($platformNorm === 'unknown' || $platformNorm === '') {
        $platformNorm = 'android';
    }

    // دمج العنوان والنص في data (كل القيم نصوص كما يتطلبه FCM)
    $dataMerged = array_merge(is_array($data) ? $data : [], [
        'title' => (string)$title,
        'body' => (string)$body,
    ]);
    $dataStr = [];
    foreach ($dataMerged as $k => $v) {
        $dataStr[(string)$k] = (string)$v;
    }

    // كتلة android.notification المشتركة (FCM v1 JSON = camelCase)
    $androidNotifExtras = [
        'priority' => 'HIGH',
        'notification' => [
            'channelId' => 'easy_tech_v2',
            'sound' => 'default',
            'defaultVibrateTimings' => true,
        ],
    ];

    if ($platformNorm === 'android') {
        $message = [
            'message' => [
                'token' => $token,
                'notification' => [
                    'title' => $title,
                    'body' => $body,
                ],
                'data' => $dataStr,
                'android' => $androidNotifExtras,
            ],
        ];
    } else {
        $message = [
            'message' => [
                'token' => $token,
                'notification' => [
                    'title' => $title,
                    'body' => $body,
                ],
                'data' => $dataStr,
                'android' => $androidNotifExtras,
                'apns' => [
                    'payload' => [
                        'aps' => [
                            'sound' => 'default',
                            'badge' => 1,
                        ],
                    ],
                ],
                'webpush' => [
                    'notification' => [
                        'icon' => '/app/icons/Icon-192.png',
                    ],
                ],
            ],
        ];
    }

    $url = "https://fcm.googleapis.com/v1/projects/{$projectId}/messages:send";
    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST => true,
        CURLOPT_POSTFIELDS => json_encode($message),
        CURLOPT_HTTPHEADER => [
            'Content-Type: application/json',
            'Authorization: Bearer ' . $accessToken,
        ],
        CURLOPT_TIMEOUT => 10,
    ]);
    $resp = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if ($httpCode !== 200) {
        error_log("FCM send failed (HTTP $httpCode): $resp for token: " . substr($token, 0, 20) . '...');
        return false;
    }
    return true;
}

/**
 * Send notification to a specific user (stores in DB + sends FCM)
 */
function _notifyUser($userId, $title, $body, $type = 'general', $refId = null, $refType = null, $extraData = []) {
    global $db;
    _ensureNotificationsSchema();

    $data = array_merge($extraData, [
        'type' => $type,
        'refId' => $refId ? (string)$refId : '',
        'refType' => $refType ?? '',
    ]);

    $stmt = $db->prepare("INSERT INTO notifications (user_id, title, body, type, ref_id, ref_type, data) VALUES (?, ?, ?, ?, ?, ?, ?)");
    $stmt->execute([$userId, $title, $body, $type, $refId, $refType, json_encode($data)]);

    $tokenStmt = $db->prepare("SELECT token, COALESCE(platform, 'web') AS platform FROM fcm_tokens WHERE user_id = ?");
    $tokenStmt->execute([$userId]);
    $tokens = $tokenStmt->fetchAll();

    if (empty($tokens)) {
        error_log('[FCM] notify skip push: user_id=' . (int)$userId . ' has NO rows in fcm_tokens (DB notification was saved). Title=' . $title);
    }

    foreach ($tokens as $t) {
        $plat = strtolower(trim((string)($t['platform'] ?? 'web')));
        if ($plat === 'unknown' || $plat === '') {
            $plat = 'android';
        }
        $ok = _sendFcmMessage($t['token'], $title, $body, $data, $plat);
        if (!$ok) {
            error_log('[FCM] notify send failed user_id=' . (int)$userId . ' platform=' . $plat);
        }
    }
}

/**
 * Send notification to all users with a specific role
 */
function _notifyRole($role, $title, $body, $type = 'general', $refId = null, $refType = null, $extraData = []) {
    global $db;
    _ensureNotificationsSchema();

    $stmt = $db->prepare("SELECT id FROM users WHERE role = ? AND is_active = TRUE");
    $stmt->execute([$role]);
    $users = $stmt->fetchAll();

    foreach ($users as $u) {
        _notifyUser((int)$u['id'], $title, $body, $type, $refId, $refType, $extraData);
    }
}

/**
 * Send notification to admins and supervisors
 */
function _notifyAdminsAndSupervisors($title, $body, $type = 'general', $refId = null, $refType = null, $extraData = []) {
    global $db;
    _ensureNotificationsSchema();

    // Use LOWER(role) because roles might be stored with different casing (e.g. Admin/staff).
    // Include staff because some admin accounts use role=staff but can access the admin panel.
    $stmt = $db->query("SELECT id FROM users WHERE LOWER(role) IN ('admin', 'supervisor', 'staff') AND is_active = TRUE");
    $users = $stmt->fetchAll();

    foreach ($users as $u) {
        _notifyUser((int)$u['id'], $title, $body, $type, $refId, $refType, $extraData);
    }
}

/**
 * Send notification to all active users
 */
function _notifyAll($title, $body, $type = 'general', $refId = null, $refType = null, $extraData = []) {
    global $db;
    _ensureNotificationsSchema();

    $stmt = $db->query("SELECT id FROM users WHERE is_active = TRUE");
    $users = $stmt->fetchAll();

    foreach ($users as $u) {
        _notifyUser((int)$u['id'], $title, $body, $type, $refId, $refType, $extraData);
    }
}

// ─── API Endpoints ────────────────────────────────────────────

function notif_list($input, $ctx) {
    global $db;
    _ensureNotificationsSchema();

    $userId = $ctx['userId'] ?? 0;
    $limit = (int)($input['limit'] ?? 50);
    $onlyUnread = !empty($input['onlyUnread']);

    $sql = "SELECT * FROM notifications WHERE user_id = ?";
    $params = [$userId];
    if ($onlyUnread) {
        $sql .= " AND is_read = FALSE";
    }
    $sql .= " ORDER BY created_at DESC LIMIT ?";
    $params[] = $limit;

    $stmt = $db->prepare($sql);
    $stmt->execute($params);
    return array_map(function($r) {
        return [
            'id' => (int)$r['id'],
            'title' => $r['title'],
            'body' => $r['body'],
            'type' => $r['type'],
            'refId' => $r['ref_id'] ? (int)$r['ref_id'] : null,
            'refType' => $r['ref_type'],
            'data' => $r['data'] ? json_decode($r['data'], true) : null,
            'isRead' => (bool)$r['is_read'],
            'createdAt' => $r['created_at'],
        ];
    }, $stmt->fetchAll());
}

function notif_markRead($input, $ctx) {
    global $db;
    _ensureNotificationsSchema();

    $id = (int)($input['id'] ?? 0);
    $userId = $ctx['userId'] ?? 0;

    $db->prepare("UPDATE notifications SET is_read = TRUE WHERE id = ? AND user_id = ?")->execute([$id, $userId]);
    return ['success' => true];
}

function notif_markAllRead($input, $ctx) {
    global $db;
    _ensureNotificationsSchema();

    $userId = $ctx['userId'] ?? 0;
    $db->prepare("UPDATE notifications SET is_read = TRUE WHERE user_id = ? AND is_read = FALSE")->execute([$userId]);
    return ['success' => true];
}

function notif_getUnreadCount($input, $ctx) {
    global $db;
    _ensureNotificationsSchema();

    $userId = $ctx['userId'] ?? 0;
    $stmt = $db->prepare("SELECT COUNT(*) FROM notifications WHERE user_id = ? AND is_read = FALSE");
    $stmt->execute([$userId]);
    return ['count' => (int)$stmt->fetchColumn()];
}

function notif_campaignCreate($input, $ctx) {
    global $db;
    _ensureNotificationsSchema();

    $title = $input['title'] ?? '';
    $body = $input['body'] ?? '';
    $targetType = $input['targetType'] ?? 'all';
    $targetRole = $input['targetRole'] ?? null;
    $linkType = $input['linkType'] ?? null;
    $linkId = !empty($input['linkId']) ? (int)$input['linkId'] : null;
    $sendNow = $input['sendNow'] ?? true;
    $createdBy = $ctx['userId'] ?? null;

    $stmt = $db->prepare("INSERT INTO notification_campaigns (title, body, target_type, target_role, link_type, link_id, created_by)
        VALUES (?, ?, ?, ?, ?, ?, ?)");
    $stmt->execute([$title, $body, $targetType, $targetRole, $linkType, $linkId, $createdBy]);
    $campaignId = (int)$db->lastInsertId();

    if ($sendNow) {
        $sentCount = 0;
        if ($targetType === 'role' && $targetRole) {
            $users = $db->prepare("SELECT id FROM users WHERE role = ? AND is_active = TRUE");
            $users->execute([$targetRole]);
        } else {
            $users = $db->query("SELECT id FROM users WHERE is_active = TRUE");
        }
        foreach ($users->fetchAll() as $u) {
            _notifyUser((int)$u['id'], $title, $body, $linkType ?? 'campaign', $linkId, $linkType, [
                'campaignId' => (string)$campaignId,
            ]);
            $sentCount++;
        }
        $db->prepare("UPDATE notification_campaigns SET sent_count = ? WHERE id = ?")->execute([$sentCount, $campaignId]);
    }

    return ['id' => $campaignId, 'sentCount' => $sentCount ?? 0];
}

function notif_saveFcmToken($input, $ctx) {
    global $db;
    _ensureNotificationsSchema();

    $userId = $ctx['userId'] ?? 0;
    $token = $input['fcmToken'] ?? $input['token'] ?? '';
    $platform = $input['platform'] ?? 'web';

    if (empty($token) || $userId == 0) {
        return ['success' => false];
    }

    $db->prepare("DELETE FROM fcm_tokens WHERE token = ?")->execute([$token]);

    $stmt = $db->prepare("INSERT INTO fcm_tokens (user_id, token, platform) VALUES (?, ?, ?)");
    $stmt->execute([$userId, $token, $platform]);

    return ['success' => true];
}

function notif_delete($input, $ctx) {
    global $db;
    _ensureNotificationsSchema();

    $id = (int)($input['id'] ?? 0);
    $userId = $ctx['userId'] ?? 0;
    $db->prepare("DELETE FROM notifications WHERE id = ? AND user_id = ?")->execute([$id, $userId]);
    return ['success' => true];
}
