<?php
/**
 * Facebook Messenger & CRM Procedures
 *
 * Handles:
 *  - Facebook Page webhook (receive messages)
 *  - meta.listConversations
 *  - meta.getConversation
 *  - meta.sendReply
 *  - meta.convertToLead
 *  - meta.refreshSenderNames
 *  - crm.getLeads / crm.createLead
 */

define('FB_PAGE_TOKEN', 'EAF1OXEzPDuIBQyF7liL5yNaW8OPdd2jaMMYBfzRZAVJZAjif9umd04fYhvOtuEIWqnmWs8mewVK3uu3W3Y8vQRMWcm5mf2U5HVYAsPWKADlTRhIsvrmc2yG0DI8gpmOOBwGY4HecZCriZBrZBeX8Iz3Hr3pMkLkTu5Ov1A2CEQoohZASZBaf8wVqF9nVa8zENZBNPZC3tjIpPabFTvbctgY6ZBiyH9hBnWpxtzZBy75WYcZD');
define('FB_VERIFY_TOKEN', 'easytech_webhook_2026');
define('FB_GRAPH_URL', 'https://graph.facebook.com/v19.0');

// ═══════════════════════════════════════════════════════════════
// ─── Ensure tables ────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════

function _ensureMetaTables() {
    global $db;

    $db->exec("CREATE TABLE IF NOT EXISTS fb_conversations (
        id INT AUTO_INCREMENT PRIMARY KEY,
        sender_id VARCHAR(100) NOT NULL,
        sender_name VARCHAR(255) DEFAULT '',
        platform VARCHAR(30) DEFAULT 'messenger',
        status ENUM('open','pending','resolved') DEFAULT 'open',
        last_message TEXT,
        last_message_at DATETIME,
        lead_id INT DEFAULT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY uk_sender (sender_id, platform)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    $db->exec("CREATE TABLE IF NOT EXISTS fb_messages (
        id INT AUTO_INCREMENT PRIMARY KEY,
        conversation_id INT NOT NULL,
        fb_message_id VARCHAR(255) DEFAULT NULL,
        content TEXT,
        is_from_page TINYINT(1) DEFAULT 0,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_conv (conversation_id),
        FOREIGN KEY (conversation_id) REFERENCES fb_conversations(id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    $db->exec("CREATE TABLE IF NOT EXISTS crm_leads (
        id INT AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(255) DEFAULT '',
        phone VARCHAR(100) DEFAULT '',
        email VARCHAR(255) DEFAULT '',
        source VARCHAR(50) DEFAULT 'manual',
        status ENUM('new','contacted','converted','lost') DEFAULT 'new',
        notes TEXT,
        assigned_to INT DEFAULT NULL,
        conversation_id INT DEFAULT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
}

// ═══════════════════════════════════════════════════════════════
// ─── Facebook Graph API helpers ──────────────────────────────
// ═══════════════════════════════════════════════════════════════

function _fbGraphGet($endpoint) {
    $url = FB_GRAPH_URL . $endpoint;
    $sep = strpos($url, '?') !== false ? '&' : '?';
    $url .= $sep . 'access_token=' . FB_PAGE_TOKEN;

    $ctx = stream_context_create([
        'http' => ['timeout' => 15, 'header' => "Accept: application/json\r\n"],
        'ssl'  => ['verify_peer' => false, 'verify_peer_name' => false],
    ]);
    $res = @file_get_contents($url, false, $ctx);
    if ($res === false) return null;
    return json_decode($res, true);
}

function _fbGraphPost($endpoint, $payload) {
    $url = FB_GRAPH_URL . $endpoint;
    $sep = strpos($url, '?') !== false ? '&' : '?';
    $url .= $sep . 'access_token=' . FB_PAGE_TOKEN;

    $json = json_encode($payload);
    $ctx = stream_context_create([
        'http' => [
            'method'  => 'POST',
            'timeout' => 15,
            'header'  => "Content-Type: application/json\r\nAccept: application/json\r\n",
            'content' => $json,
        ],
        'ssl' => ['verify_peer' => false, 'verify_peer_name' => false],
    ]);
    $res = @file_get_contents($url, false, $ctx);
    if ($res === false) return null;
    return json_decode($res, true);
}

function _fbGetUserName($psid) {
    $data = _fbGraphGet("/$psid?fields=first_name,last_name,name,profile_pic");
    if ($data && isset($data['name'])) {
        return $data['name'];
    }
    if ($data && isset($data['first_name'])) {
        return trim(($data['first_name'] ?? '') . ' ' . ($data['last_name'] ?? ''));
    }
    return '';
}

// ═══════════════════════════════════════════════════════════════
// ─── Webhook handler (called by Facebook) ────────────────────
// ═══════════════════════════════════════════════════════════════

function meta_handleWebhookVerify() {
    $mode      = $_GET['hub_mode'] ?? '';
    $token     = $_GET['hub_verify_token'] ?? '';
    $challenge = $_GET['hub_challenge'] ?? '';

    if ($mode === 'subscribe' && $token === FB_VERIFY_TOKEN) {
        http_response_code(200);
        echo $challenge;
        exit;
    }
    http_response_code(403);
    echo 'Forbidden';
    exit;
}

function meta_handleWebhookPost() {
    global $db;
    _ensureMetaTables();

    $raw  = file_get_contents('php://input');
    $body = json_decode($raw, true);

    if (!$body || ($body['object'] ?? '') !== 'page') {
        http_response_code(200);
        echo 'EVENT_RECEIVED';
        exit;
    }

    foreach ($body['entry'] ?? [] as $entry) {
        foreach ($entry['messaging'] ?? [] as $event) {
            $senderId = $event['sender']['id'] ?? '';
            $messageText = $event['message']['text'] ?? null;
            $fbMsgId = $event['message']['mid'] ?? null;

            if (empty($senderId) || empty($messageText)) continue;

            // Check if the sender is the page itself (echo)
            $pageId = $entry['id'] ?? '';
            if ($senderId === $pageId) continue;

            // Upsert conversation
            $stmt = $db->prepare("SELECT id, sender_name FROM fb_conversations WHERE sender_id = ? AND platform = 'messenger'");
            $stmt->execute([$senderId]);
            $conv = $stmt->fetch();

            if ($conv) {
                $convId = (int)$conv['id'];
                $db->prepare("UPDATE fb_conversations SET last_message = ?, last_message_at = NOW(), status = 'open' WHERE id = ?")
                   ->execute([$messageText, $convId]);
            } else {
                $name = _fbGetUserName($senderId);
                $db->prepare("INSERT INTO fb_conversations (sender_id, sender_name, platform, last_message, last_message_at) VALUES (?, ?, 'messenger', ?, NOW())")
                   ->execute([$senderId, $name, $messageText]);
                $convId = (int)$db->lastInsertId();
            }

            // Insert message
            $db->prepare("INSERT INTO fb_messages (conversation_id, fb_message_id, content, is_from_page) VALUES (?, ?, ?, 0)")
               ->execute([$convId, $fbMsgId, $messageText]);
        }
    }

    http_response_code(200);
    echo 'EVENT_RECEIVED';
    exit;
}

// ═══════════════════════════════════════════════════════════════
// ─── API: meta.listConversations ─────────────────────────────
// ═══════════════════════════════════════════════════════════════

function meta_listConversations($input, $ctx) {
    global $db;
    _ensureMetaTables();

    $sql = "SELECT * FROM fb_conversations";
    $params = [];

    $status = $input['status'] ?? null;
    if ($status && in_array($status, ['open', 'pending', 'resolved'])) {
        $sql .= " WHERE status = ?";
        $params[] = $status;
    }
    $sql .= " ORDER BY last_message_at DESC";

    $stmt = $db->prepare($sql);
    $stmt->execute($params);
    $rows = $stmt->fetchAll();

    return array_map(function($r) {
        return [
            'id'          => (int)$r['id'],
            'senderId'    => $r['sender_id'],
            'senderName'  => $r['sender_name'] ?: null,
            'platform'    => $r['platform'],
            'status'      => $r['status'],
            'lastMessage' => $r['last_message'] ?? '',
            'lastMessageAt' => $r['last_message_at'],
            'leadId'      => $r['lead_id'] ? (int)$r['lead_id'] : null,
            'createdAt'   => $r['created_at'],
        ];
    }, $rows);
}

// ═══════════════════════════════════════════════════════════════
// ─── API: meta.getConversation ───────────────────────────────
// ═══════════════════════════════════════════════════════════════

function meta_getConversation($input, $ctx) {
    global $db;
    _ensureMetaTables();

    $id = (int)($input['id'] ?? 0);
    if ($id <= 0) throw new Exception('معرف المحادثة غير صالح');

    $conv = $db->prepare("SELECT * FROM fb_conversations WHERE id = ?");
    $conv->execute([$id]);
    $conv = $conv->fetch();
    if (!$conv) throw new Exception('المحادثة غير موجودة');

    $msgs = $db->prepare("SELECT * FROM fb_messages WHERE conversation_id = ? ORDER BY created_at ASC");
    $msgs->execute([$id]);
    $messages = $msgs->fetchAll();

    return [
        'id'         => (int)$conv['id'],
        'senderId'   => $conv['sender_id'],
        'senderName' => $conv['sender_name'] ?: null,
        'platform'   => $conv['platform'],
        'status'     => $conv['status'],
        'leadId'     => $conv['lead_id'] ? (int)$conv['lead_id'] : null,
        'messages'   => array_map(function($m) {
            return [
                'id'         => (int)$m['id'],
                'content'    => $m['content'],
                'isFromPage' => (bool)$m['is_from_page'],
                'createdAt'  => strtotime($m['created_at']) * 1000,
            ];
        }, $messages),
    ];
}

// ═══════════════════════════════════════════════════════════════
// ─── API: meta.sendReply ─────────────────────────────────────
// ═══════════════════════════════════════════════════════════════

function meta_sendReply($input, $ctx) {
    global $db;
    _ensureMetaTables();

    $convId = (int)($input['conversationId'] ?? 0);
    $text   = $input['text'] ?? '';
    if ($convId <= 0 || empty($text)) throw new Exception('بيانات غير مكتملة');

    $conv = $db->prepare("SELECT * FROM fb_conversations WHERE id = ?");
    $conv->execute([$convId]);
    $conv = $conv->fetch();
    if (!$conv) throw new Exception('المحادثة غير موجودة');

    // Send via Facebook Graph API
    $result = _fbGraphPost('/me/messages', [
        'recipient' => ['id' => $conv['sender_id']],
        'message'   => ['text' => $text],
    ]);

    if (!$result || isset($result['error'])) {
        $errMsg = $result['error']['message'] ?? 'فشل إرسال الرسالة عبر فيسبوك';
        throw new Exception($errMsg);
    }

    $fbMsgId = $result['message_id'] ?? null;

    // Save to DB
    $db->prepare("INSERT INTO fb_messages (conversation_id, fb_message_id, content, is_from_page) VALUES (?, ?, ?, 1)")
       ->execute([$convId, $fbMsgId, $text]);

    $db->prepare("UPDATE fb_conversations SET last_message = ?, last_message_at = NOW() WHERE id = ?")
       ->execute([$text, $convId]);

    return ['success' => true];
}

// ═══════════════════════════════════════════════════════════════
// ─── API: meta.convertToLead ─────────────────────────────────
// ═══════════════════════════════════════════════════════════════

function meta_convertToLead($input, $ctx) {
    global $db;
    _ensureMetaTables();

    $convId = (int)($input['conversationId'] ?? 0);
    if ($convId <= 0) throw new Exception('معرف المحادثة غير صالح');

    $conv = $db->prepare("SELECT * FROM fb_conversations WHERE id = ?");
    $conv->execute([$convId]);
    $conv = $conv->fetch();
    if (!$conv) throw new Exception('المحادثة غير موجودة');

    if ($conv['lead_id']) throw new Exception('تم تحويل هذه المحادثة لليد مسبقاً');

    $name = $conv['sender_name'] ?: ('Messenger User ' . $conv['sender_id']);

    $db->prepare("INSERT INTO crm_leads (name, source, conversation_id, notes) VALUES (?, 'messenger', ?, ?)")
       ->execute([$name, $convId, 'تم التحويل من محادثة ماسنجر']);
    $leadId = (int)$db->lastInsertId();

    $db->prepare("UPDATE fb_conversations SET lead_id = ? WHERE id = ?")
       ->execute([$leadId, $convId]);

    return ['success' => true, 'leadId' => $leadId];
}

// ═══════════════════════════════════════════════════════════════
// ─── API: meta.updateConversationName ────────────────────────
// ═══════════════════════════════════════════════════════════════

function meta_updateConversationName($input, $ctx) {
    global $db;
    _ensureMetaTables();

    $convId = (int)($input['conversationId'] ?? 0);
    $name   = trim($input['name'] ?? '');
    if ($convId <= 0 || empty($name)) throw new Exception('بيانات غير مكتملة');

    $stmt = $db->prepare("UPDATE fb_conversations SET sender_name = ? WHERE id = ?");
    $stmt->execute([$name, $convId]);

    if ($stmt->rowCount() === 0) throw new Exception('المحادثة غير موجودة');

    return ['success' => true];
}

// ═══════════════════════════════════════════════════════════════
// ─── API: meta.updateConversationStatus ──────────────────────
// ═══════════════════════════════════════════════════════════════

function meta_updateConversationStatus($input, $ctx) {
    global $db;
    _ensureMetaTables();

    $convId = (int)($input['conversationId'] ?? 0);
    $status = $input['status'] ?? '';
    if ($convId <= 0 || !in_array($status, ['open', 'pending', 'resolved'])) {
        throw new Exception('بيانات غير صالحة');
    }

    $stmt = $db->prepare("UPDATE fb_conversations SET status = ? WHERE id = ?");
    $stmt->execute([$status, $convId]);

    return ['success' => true];
}

// ═══════════════════════════════════════════════════════════════
// ─── API: meta.refreshSenderNames ────────────────────────────
// ═══════════════════════════════════════════════════════════════

function meta_refreshSenderNames($input, $ctx) {
    global $db;
    _ensureMetaTables();

    $rows = $db->query("SELECT id, sender_id FROM fb_conversations WHERE (sender_name IS NULL OR sender_name = '') AND platform = 'messenger'")->fetchAll();

    $updated = 0;
    foreach ($rows as $r) {
        $name = _fbGetUserName($r['sender_id']);
        if (!empty($name)) {
            $db->prepare("UPDATE fb_conversations SET sender_name = ? WHERE id = ?")
               ->execute([$name, (int)$r['id']]);
            $updated++;
        }
    }

    return ['success' => true, 'updated' => $updated];
}

// ═══════════════════════════════════════════════════════════════
// ─── CRM: Ensure enhanced schema ────────────────────────────
// ═══════════════════════════════════════════════════════════════

function _ensureCrmSchema() {
    global $db;
    _ensureMetaTables();

    // Upgrade crm_leads with new columns (safe ALTER – ignores if already exists)
    $cols = [];
    foreach ($db->query("SHOW COLUMNS FROM crm_leads")->fetchAll() as $c) $cols[] = $c['Field'];

    if (!in_array('pipeline_stage', $cols)) {
        $db->exec("ALTER TABLE crm_leads ADD COLUMN pipeline_stage VARCHAR(30) DEFAULT 'new' AFTER status");
    }
    if (!in_array('priority', $cols)) {
        $db->exec("ALTER TABLE crm_leads ADD COLUMN priority VARCHAR(20) DEFAULT 'medium' AFTER pipeline_stage");
    }
    if (!in_array('expected_value', $cols)) {
        $db->exec("ALTER TABLE crm_leads ADD COLUMN expected_value DECIMAL(12,2) DEFAULT 0 AFTER priority");
    }
    if (!in_array('last_activity_at', $cols)) {
        $db->exec("ALTER TABLE crm_leads ADD COLUMN last_activity_at DATETIME DEFAULT NULL AFTER expected_value");
    }
    if (!in_array('address', $cols)) {
        $db->exec("ALTER TABLE crm_leads ADD COLUMN address TEXT DEFAULT NULL AFTER email");
    }
    try {
        $db->exec("ALTER TABLE crm_leads ADD COLUMN location_url TEXT DEFAULT NULL COMMENT 'رابط خرائط' AFTER address");
    } catch (\Exception $e) { /* موجود */ }
    try {
        $db->exec("ALTER TABLE crm_leads ADD COLUMN linked_client_id INT DEFAULT NULL AFTER notes");
    } catch (\Exception $e) { /* موجود */ }

    $db->exec("CREATE TABLE IF NOT EXISTS crm_activities (
        id INT AUTO_INCREMENT PRIMARY KEY,
        lead_id INT NOT NULL,
        user_id INT DEFAULT NULL,
        type VARCHAR(30) NOT NULL DEFAULT 'note',
        title VARCHAR(255) DEFAULT '',
        content TEXT,
        old_value VARCHAR(100) DEFAULT NULL,
        new_value VARCHAR(100) DEFAULT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_lead (lead_id),
        FOREIGN KEY (lead_id) REFERENCES crm_leads(id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    try {
        $db->exec('ALTER TABLE crm_activities ADD COLUMN media_url TEXT DEFAULT NULL AFTER content');
    } catch (\Exception $e) { /* موجود */ }
}

function _formatLead($r) {
    return [
        'id'             => (int)$r['id'],
        'name'           => $r['name'] ?? '',
        'phone'          => $r['phone'] ?? '',
        'email'          => $r['email'] ?? '',
        'address'        => $r['address'] ?? '',
        'locationUrl'    => $r['location_url'] ?? '',
        'linkedClientId' => !empty($r['linked_client_id']) ? (int)$r['linked_client_id'] : null,
        'source'         => $r['source'] ?? 'manual',
        'status'         => $r['status'] ?? 'new',
        'pipelineStage'  => $r['pipeline_stage'] ?? $r['status'] ?? 'new',
        'priority'       => $r['priority'] ?? 'medium',
        'expectedValue'  => (float)($r['expected_value'] ?? 0),
        'notes'          => $r['notes'] ?? '',
        'assignedTo'     => $r['assigned_to'] ? (int)$r['assigned_to'] : null,
        'assigneeName'   => $r['assignee_name'] ?? '',
        'conversationId' => isset($r['conversation_id']) && $r['conversation_id'] ? (int)$r['conversation_id'] : null,
        'lastActivityAt' => $r['last_activity_at'] ?? null,
        'createdAt'      => $r['created_at'],
    ];
}

// ═══════════════════════════════════════════════════════════════
// ─── CRM: crm.getLeads (enhanced with filters) ─────────────
// ═══════════════════════════════════════════════════════════════

function crm_getLeads($input, $ctx) {
    global $db;
    _ensureCrmSchema();

    $sql = "SELECT l.*, u.name AS assignee_name FROM crm_leads l LEFT JOIN users u ON u.id = l.assigned_to";
    $where = [];
    $params = [];

    if (!empty($input['stage'])) {
        $where[] = "l.pipeline_stage = ?";
        $params[] = $input['stage'];
    }
    if (!empty($input['assignedTo'])) {
        $where[] = "l.assigned_to = ?";
        $params[] = (int)$input['assignedTo'];
    }
    if (!empty($input['priority'])) {
        $where[] = "l.priority = ?";
        $params[] = $input['priority'];
    }
    if (!empty($input['search'])) {
        $where[] = "(l.name LIKE ? OR l.phone LIKE ? OR l.email LIKE ?)";
        $s = '%' . $input['search'] . '%';
        $params = array_merge($params, [$s, $s, $s]);
    }

    if ($where) $sql .= " WHERE " . implode(" AND ", $where);
    $sql .= " ORDER BY l.last_activity_at DESC, l.created_at DESC";

    $stmt = $db->prepare($sql);
    $stmt->execute($params);
    return array_map('_formatLead', $stmt->fetchAll());
}

// ═══════════════════════════════════════════════════════════════
// ─── CRM: crm.getLeadById ──────────────────────────────────
// ═══════════════════════════════════════════════════════════════

function crm_getLeadById($input, $ctx) {
    global $db;
    _ensureCrmSchema();

    $id = (int)($input['id'] ?? 0);
    if ($id <= 0) throw new Exception('معرف الليد غير صالح');

    $stmt = $db->prepare("SELECT l.*, u.name AS assignee_name FROM crm_leads l LEFT JOIN users u ON u.id = l.assigned_to WHERE l.id = ?");
    $stmt->execute([$id]);
    $row = $stmt->fetch();
    if (!$row) throw new Exception('الليد غير موجود');

    $lead = _formatLead($row);

    // Fetch activities
    $acts = $db->prepare("SELECT a.*, u.name AS user_name FROM crm_activities a LEFT JOIN users u ON u.id = a.user_id WHERE a.lead_id = ? ORDER BY a.created_at DESC");
    $acts->execute([$id]);
    $lead['activities'] = array_map(function($a) {
        return [
            'id'        => (int)$a['id'],
            'type'      => $a['type'],
            'title'     => $a['title'] ?? '',
            'content'   => $a['content'] ?? '',
            'mediaUrl'  => $a['media_url'] ?? '',
            'oldValue'  => $a['old_value'],
            'newValue'  => $a['new_value'],
            'userName'  => $a['user_name'] ?? 'النظام',
            'createdAt' => $a['created_at'],
        ];
    }, $acts->fetchAll());

    return $lead;
}

/**
 * إنشاء أو ربط عميل (جدول users) من بيانات الليد لاستخدامه في المهام وغيرها.
 */
function _crm_syncClientFromLead($leadId, $ctx) {
    global $db;
    if (!function_exists('clients_create')) {
        require_once __DIR__ . '/surveys_procedures.php';
    }
    $st = $db->prepare('SELECT * FROM crm_leads WHERE id = ?');
    $st->execute([$leadId]);
    $row = $st->fetch(PDO::FETCH_ASSOC);
    if (!$row) {
        return;
    }
    $name = trim((string)($row['name'] ?? ''));
    if ($name === '') {
        return;
    }
    $phone = trim((string)($row['phone'] ?? ''));
    $email = trim((string)($row['email'] ?? ''));
    $address = (string)($row['address'] ?? '');
    $locUrl = trim((string)($row['location_url'] ?? ''));

    $existingId = null;
    if ($phone !== '') {
        $q = $db->prepare("SELECT id FROM users WHERE role = 'user' AND phone = ? LIMIT 1");
        $q->execute([$phone]);
        $found = $q->fetch(PDO::FETCH_ASSOC);
        if ($found) {
            $existingId = (int)$found['id'];
        }
    }

    if ($existingId) {
        $db->prepare('UPDATE crm_leads SET linked_client_id = ? WHERE id = ?')->execute([$existingId, $leadId]);
        $db->prepare('UPDATE users SET name = ?, address = ? WHERE id = ? AND role = ?')
            ->execute([$name, $address !== '' ? $address : null, $existingId, 'user']);
        if ($locUrl !== '') {
            $db->prepare('UPDATE users SET location = ? WHERE id = ?')->execute([$locUrl, $existingId]);
        }
        return;
    }

    $res = clients_create([
        'name'     => $name,
        'email'    => $email !== '' ? $email : null,
        'phone'    => $phone !== '' ? $phone : null,
        'address'  => $address !== '' ? $address : null,
        'location' => $locUrl !== '' ? $locUrl : null,
        'role'     => 'user',
    ], $ctx);
    $newId = (int)($res['id'] ?? 0);
    if ($newId > 0) {
        $db->prepare('UPDATE crm_leads SET linked_client_id = ? WHERE id = ?')->execute([$newId, $leadId]);
    }
}

function _crm_pushLeadToLinkedClient($leadId) {
    global $db;
    $st = $db->prepare('SELECT * FROM crm_leads WHERE id = ?');
    $st->execute([$leadId]);
    $row = $st->fetch(PDO::FETCH_ASSOC);
    if (!$row || empty($row['linked_client_id'])) {
        return;
    }
    $cid = (int)$row['linked_client_id'];
    $name = trim((string)($row['name'] ?? ''));
    $phone = trim((string)($row['phone'] ?? ''));
    $email = trim((string)($row['email'] ?? ''));
    $address = (string)($row['address'] ?? '');
    $locUrl = trim((string)($row['location_url'] ?? ''));
    $db->prepare('UPDATE users SET name = ?, phone = ?, email = ?, address = ?, location = ? WHERE id = ? AND role = ?')
        ->execute([
            $name,
            $phone !== '' ? $phone : null,
            $email !== '' ? $email : null,
            $address !== '' ? $address : null,
            $locUrl !== '' ? $locUrl : null,
            $cid,
            'user',
        ]);
}

// ═══════════════════════════════════════════════════════════════
// ─── CRM: crm.createLead ────────────────────────────────────
// ═══════════════════════════════════════════════════════════════

function crm_createLead($input, $ctx) {
    global $db;
    _ensureCrmSchema();

    $name     = $input['name'] ?? '';
    $phone    = $input['phone'] ?? '';
    $email    = $input['email'] ?? '';
    $address  = $input['address'] ?? '';
    $locationUrl = trim((string)($input['locationUrl'] ?? ''));
    $notes    = $input['notes'] ?? '';
    $source   = $input['source'] ?? 'manual';
    $priority = $input['priority'] ?? 'medium';
    $expectedValue = (float)($input['expectedValue'] ?? 0);
    $assignedTo = !empty($input['assignedTo']) ? (int)$input['assignedTo'] : null;

    if (empty($name)) throw new Exception('اسم العميل المحتمل مطلوب');

    $db->prepare("INSERT INTO crm_leads (name, phone, email, address, location_url, source, notes, pipeline_stage, priority, expected_value, assigned_to, last_activity_at) VALUES (?, ?, ?, ?, ?, ?, ?, 'new', ?, ?, ?, NOW())")
       ->execute([$name, $phone, $email, $address, $locationUrl !== '' ? $locationUrl : null, $source, $notes, $priority, $expectedValue, $assignedTo]);

    $leadId = (int)$db->lastInsertId();

    $db->prepare("INSERT INTO crm_activities (lead_id, user_id, type, title, content) VALUES (?, ?, 'created', 'تم إنشاء الليد', ?)")
       ->execute([$leadId, $ctx['userId'], "مصدر: $source"]);

    if ($assignedTo) {
        $uName = $db->prepare("SELECT name FROM users WHERE id = ?");
        $uName->execute([$assignedTo]);
        $uRow = $uName->fetch();
        $db->prepare("INSERT INTO crm_activities (lead_id, user_id, type, title, content, new_value) VALUES (?, ?, 'assignment', 'تم التوزيع', ?, ?)")
           ->execute([$leadId, $ctx['userId'], 'تم توزيع الليد على ' . ($uRow['name'] ?? ''), (string)$assignedTo]);
    }

    try {
        _crm_syncClientFromLead($leadId, $ctx);
    } catch (\Throwable $e) {
        error_log('[CRM] sync client from lead: ' . $e->getMessage());
    }

    return ['success' => true, 'id' => $leadId];
}

// ═══════════════════════════════════════════════════════════════
// ─── CRM: crm.updateLead ────────────────────────────────────
// ═══════════════════════════════════════════════════════════════

function crm_updateLead($input, $ctx) {
    global $db;
    _ensureCrmSchema();

    $id = (int)($input['id'] ?? 0);
    if ($id <= 0) throw new Exception('معرف الليد غير صالح');

    $old = $db->prepare("SELECT * FROM crm_leads WHERE id = ?");
    $old->execute([$id]);
    $old = $old->fetch();
    if (!$old) throw new Exception('الليد غير موجود');

    $name     = $input['name'] ?? $old['name'];
    $phone    = $input['phone'] ?? $old['phone'];
    $email    = $input['email'] ?? $old['email'];
    $address  = $input['address'] ?? ($old['address'] ?? '');
    $locationUrl = array_key_exists('locationUrl', $input) ? trim((string)$input['locationUrl']) : trim((string)($old['location_url'] ?? ''));
    $notes    = $input['notes'] ?? $old['notes'];
    $priority = $input['priority'] ?? ($old['priority'] ?? 'medium');
    $expectedValue = isset($input['expectedValue']) ? (float)$input['expectedValue'] : (float)($old['expected_value'] ?? 0);

    $db->prepare("UPDATE crm_leads SET name=?, phone=?, email=?, address=?, location_url=?, notes=?, priority=?, expected_value=?, last_activity_at=NOW() WHERE id=?")
       ->execute([$name, $phone, $email, $address, $locationUrl !== '' ? $locationUrl : null, $notes, $priority, $expectedValue, $id]);

    try {
        if (empty($old['linked_client_id'])) {
            _crm_syncClientFromLead($id, $ctx);
        } else {
            _crm_pushLeadToLinkedClient($id);
        }
    } catch (\Throwable $e) {
        error_log('[CRM] update lead client sync: ' . $e->getMessage());
    }

    return ['success' => true];
}

// ═══════════════════════════════════════════════════════════════
// ─── CRM: crm.updateStage ──────────────────────────────────
// ═══════════════════════════════════════════════════════════════

function crm_updateStage($input, $ctx) {
    global $db;
    _ensureCrmSchema();

    $id    = (int)($input['id'] ?? 0);
    $stage = $input['stage'] ?? '';
    $validStages = ['new','contacted','qualified','proposal','negotiation','won','lost'];
    if ($id <= 0 || !in_array($stage, $validStages)) throw new Exception('بيانات غير صالحة');

    $old = $db->prepare("SELECT pipeline_stage FROM crm_leads WHERE id = ?");
    $old->execute([$id]);
    $oldRow = $old->fetch();
    if (!$oldRow) throw new Exception('الليد غير موجود');
    $oldStage = $oldRow['pipeline_stage'] ?? 'new';

    $stageLabels = [
        'new'=>'جديد','contacted'=>'تم التواصل','qualified'=>'مؤهل',
        'proposal'=>'عرض سعر','negotiation'=>'تفاوض','won'=>'تم البيع','lost'=>'مفقود'
    ];

    $statusMap = ['won' => 'converted', 'lost' => 'lost'];
    $newStatus = $statusMap[$stage] ?? 'contacted';

    $db->prepare("UPDATE crm_leads SET pipeline_stage=?, status=?, last_activity_at=NOW() WHERE id=?")
       ->execute([$stage, $newStatus, $id]);

    $db->prepare("INSERT INTO crm_activities (lead_id, user_id, type, title, old_value, new_value) VALUES (?, ?, 'stage_change', ?, ?, ?)")
       ->execute([$id, $ctx['userId'], 'تغيير المرحلة: ' . ($stageLabels[$oldStage] ?? $oldStage) . ' → ' . ($stageLabels[$stage] ?? $stage), $oldStage, $stage]);

    return ['success' => true];
}

// ═══════════════════════════════════════════════════════════════
// ─── CRM: crm.assignLead ────────────────────────────────────
// ═══════════════════════════════════════════════════════════════

function crm_assignLead($input, $ctx) {
    global $db;
    _ensureCrmSchema();

    $id = (int)($input['id'] ?? 0);
    $assignTo = !empty($input['assignedTo']) ? (int)$input['assignedTo'] : null;
    if ($id <= 0) throw new Exception('معرف الليد غير صالح');

    $db->prepare("UPDATE crm_leads SET assigned_to=?, last_activity_at=NOW() WHERE id=?")
       ->execute([$assignTo, $id]);

    $assigneeName = 'غير محدد';
    if ($assignTo) {
        $u = $db->prepare("SELECT name FROM users WHERE id = ?");
        $u->execute([$assignTo]);
        $uRow = $u->fetch();
        $assigneeName = $uRow['name'] ?? '';
    }

    $db->prepare("INSERT INTO crm_activities (lead_id, user_id, type, title, content, new_value) VALUES (?, ?, 'assignment', 'تم التوزيع', ?, ?)")
       ->execute([$id, $ctx['userId'], 'تم توزيع الليد على: ' . $assigneeName, (string)($assignTo ?? 0)]);

    if ($assignTo) {
        try {
            $leadStmt = $db->prepare("SELECT name FROM crm_leads WHERE id = ?");
            $leadStmt->execute([$id]);
            $leadName = $leadStmt->fetchColumn() ?: 'عميل محتمل';
            _notifyUser($assignTo, 'عميل محتمل جديد', "تم توزيع عميل محتمل عليك: {$leadName}", 'crm', $id, 'crm');
        } catch (\Exception $e) { /* ignore */ }
    }

    return ['success' => true];
}

// ═══════════════════════════════════════════════════════════════
// ─── CRM: crm.addActivity ──────────────────────────────────
// ═══════════════════════════════════════════════════════════════

function crm_addActivity($input, $ctx) {
    global $db;
    _ensureCrmSchema();

    $leadId  = (int)($input['leadId'] ?? 0);
    $type    = $input['type'] ?? 'note';
    $title   = trim((string)($input['title'] ?? ''));
    $content = (string)($input['content'] ?? '');
    $mediaUrl = trim((string)($input['mediaUrl'] ?? ''));

    $validTypes = ['note','call','meeting','email','follow_up','other','call_recording'];
    if ($leadId <= 0 || !in_array($type, $validTypes)) {
        throw new Exception('بيانات غير صالحة');
    }

    if ($type === 'call_recording') {
        if ($mediaUrl === '') {
            throw new Exception('ملف التسجيل مطلوب');
        }
        if (trim($content) === '') {
            $content = 'تسجيل صوتي مرفوع يدوياً.';
        }
        if ($title === '') {
            $title = 'تسجيل مكالمة';
        }
    } else {
        if (trim($content) === '') {
            throw new Exception('محتوى النشاط مطلوب');
        }
    }

    $db->prepare('INSERT INTO crm_activities (lead_id, user_id, type, title, content, media_url) VALUES (?, ?, ?, ?, ?, ?)')
       ->execute([$leadId, $ctx['userId'], $type, $title, $content, $mediaUrl !== '' ? $mediaUrl : null]);

    $db->prepare("UPDATE crm_leads SET last_activity_at=NOW() WHERE id=?")
       ->execute([$leadId]);

    return ['success' => true, 'id' => (int)$db->lastInsertId()];
}

/**
 * تسجيل مكالمة من التطبيق (عند الضغط على أيقونة الاتصال) — الوقت يُسجَّل تلقائياً؛ يمكن إضافة تعليق لاحقاً عبر «إضافة نشاط».
 */
function crm_recordCall($input, $ctx) {
    global $db;
    _ensureCrmSchema();

    $leadId = (int)($input['leadId'] ?? 0);
    $note   = trim((string)($input['note'] ?? ''));
    if ($leadId <= 0) {
        throw new Exception('معرف الليد غير صالح');
    }

    $ts = date('Y-m-d H:i:s');
    $content = "[تسجيل تلقائي] تم الضغط على اتصال في: {$ts}";
    if ($note !== '') {
        $content .= "\n\n[تعليق المندوب]\n" . $note;
    } else {
        $content .= "\n\nيمكنك إضافة تفاصيل المكالمة من «إضافة نشاط» أو تعديل هذا السجل لاحقاً.";
    }

    $db->prepare("INSERT INTO crm_activities (lead_id, user_id, type, title, content) VALUES (?, ?, 'call', ?, ?)")
       ->execute([$leadId, $ctx['userId'], 'مكالمة هاتفية', $content]);

    $db->prepare('UPDATE crm_leads SET last_activity_at=NOW() WHERE id=?')->execute([$leadId]);

    return ['success' => true, 'id' => (int)$db->lastInsertId()];
}

// ═══════════════════════════════════════════════════════════════
// ─── CRM: crm.deleteActivity ───────────────────────────────
// ═══════════════════════════════════════════════════════════════

function crm_deleteActivity($input, $ctx) {
    global $db;
    _ensureCrmSchema();

    $id = (int)($input['id'] ?? 0);
    if ($id <= 0) throw new Exception('معرف النشاط غير صالح');

    $db->prepare("DELETE FROM crm_activities WHERE id = ?")->execute([$id]);
    return ['success' => true];
}

// ═══════════════════════════════════════════════════════════════
// ─── CRM: crm.deleteLead ────────────────────────────────────
// ═══════════════════════════════════════════════════════════════

function crm_deleteLead($input, $ctx) {
    global $db;
    _ensureCrmSchema();

    $id = (int)($input['id'] ?? 0);
    if ($id <= 0) throw new Exception('معرف الليد غير صالح');

    $db->prepare("UPDATE fb_conversations SET lead_id = NULL WHERE lead_id = ?")->execute([$id]);
    $db->prepare("DELETE FROM crm_leads WHERE id = ?")->execute([$id]);
    return ['success' => true];
}

// ═══════════════════════════════════════════════════════════════
// ─── CRM: crm.getStats ─────────────────────────────────────
// ═══════════════════════════════════════════════════════════════

function crm_getStats($input, $ctx) {
    global $db;
    _ensureCrmSchema();

    $total = (int)$db->query("SELECT COUNT(*) FROM crm_leads")->fetchColumn();
    $byStage = [];
    foreach ($db->query("SELECT pipeline_stage, COUNT(*) as cnt FROM crm_leads GROUP BY pipeline_stage")->fetchAll() as $r) {
        $byStage[$r['pipeline_stage'] ?? 'new'] = (int)$r['cnt'];
    }
    $byAssignee = [];
    foreach ($db->query("SELECT l.assigned_to, u.name, COUNT(*) as cnt FROM crm_leads l LEFT JOIN users u ON u.id = l.assigned_to GROUP BY l.assigned_to, u.name")->fetchAll() as $r) {
        $byAssignee[] = ['id' => $r['assigned_to'] ? (int)$r['assigned_to'] : null, 'name' => $r['name'] ?? 'غير موزع', 'count' => (int)$r['cnt']];
    }
    $totalValue = (float)$db->query("SELECT COALESCE(SUM(expected_value),0) FROM crm_leads WHERE pipeline_stage NOT IN ('lost')")->fetchColumn();
    $wonValue = (float)$db->query("SELECT COALESCE(SUM(expected_value),0) FROM crm_leads WHERE pipeline_stage = 'won'")->fetchColumn();
    $recentActivities = [];
    $acts = $db->query("SELECT a.*, u.name AS user_name, l.name AS lead_name FROM crm_activities a LEFT JOIN users u ON u.id = a.user_id LEFT JOIN crm_leads l ON l.id = a.lead_id ORDER BY a.created_at DESC LIMIT 20");
    foreach ($acts->fetchAll() as $a) {
        $recentActivities[] = [
            'id' => (int)$a['id'], 'type' => $a['type'], 'title' => $a['title'],
            'content' => $a['content'] ?? '', 'userName' => $a['user_name'] ?? 'النظام',
            'leadName' => $a['lead_name'] ?? '', 'leadId' => (int)$a['lead_id'],
            'createdAt' => $a['created_at'],
        ];
    }

    return [
        'total' => $total, 'byStage' => $byStage, 'byAssignee' => $byAssignee,
        'totalValue' => $totalValue, 'wonValue' => $wonValue,
        'recentActivities' => $recentActivities,
    ];
}

// ═══════════════════════════════════════════════════════════════
// ─── CRM: crm.getStaffList ─────────────────────────────────
// ═══════════════════════════════════════════════════════════════

function crm_getStaffList($ctx) {
    global $db;
    $rows = $db->query("SELECT id, name, email, role FROM users WHERE role IN ('admin','staff','technician') ORDER BY name ASC")->fetchAll();
    return array_map(function($r) {
        return ['id' => (int)$r['id'], 'name' => $r['name'], 'email' => $r['email'], 'role' => $r['role']];
    }, $rows);
}
