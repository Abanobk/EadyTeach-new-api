<?php
/**
 * EasyTech tRPC Router – api.easytecheg.net
 * Main entry point for all API requests.
 */

// ─── CORS ──────────────────────────────────────────────────────
// عند استخدام Cookie يجب إرجاع Origin الفعلي وليس * (المتصفح يرفض * مع credentials)
$origin = $_SERVER['HTTP_ORIGIN'] ?? '';
$allowedOrigins = [
    'http://localhost',
    'http://127.0.0.1',
    'https://api.easytecheg.net',
    'https://easytecheg.net',
];
$allowOrigin = '*';
if ($origin !== '') {
    foreach ($allowedOrigins as $allowed) {
        if (strpos($origin, $allowed) === 0) {
            $allowOrigin = $origin;
            break;
        }
    }
}
header('Access-Control-Allow-Origin: ' . $allowOrigin);
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Accept, Cookie, Authorization');
header('Access-Control-Allow-Credentials: true');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

// ─── Image Proxy (before JSON content-type) ──────────────────
$_imgProxyUri = $_SERVER['REQUEST_URI'] ?? '';
if (strpos($_imgProxyUri, '/api/image-proxy') !== false) {
    $imgUrl = $_GET['url'] ?? '';
    if (empty($imgUrl)) {
        http_response_code(400);
        echo 'Missing url parameter';
        exit;
    }
    $streamCtx = stream_context_create([
        'http' => [
            'timeout' => 15,
            'header'  => "Accept: image/*\r\n",
        ],
        'ssl' => ['verify_peer' => false, 'verify_peer_name' => false],
    ]);
    $imgData = @file_get_contents($imgUrl, false, $streamCtx);
    if ($imgData === false) {
        http_response_code(502);
        echo 'Failed to fetch image';
        exit;
    }
    $ct = 'image/jpeg';
    if (isset($http_response_header)) {
        foreach ($http_response_header as $h) {
            if (stripos($h, 'Content-Type:') === 0) {
                $ct = trim(substr($h, 13));
                break;
            }
        }
    }
    header('Content-Type: ' . $ct);
    header('Cache-Control: public, max-age=86400');
    header('Access-Control-Allow-Origin: *');
    echo $imgData;
    exit;
}

// ─── Facebook Webhook (before JSON content-type) ────────────
$_webhookUri = $_SERVER['REQUEST_URI'] ?? '';
if (strpos($_webhookUri, '/api/webhook/meta') !== false) {
    // DB connection needed for webhook
    try {
        $db = new PDO("mysql:host=db_host;dbname=easytech_v2;charset=utf8mb4", 'root', 'EasyTech2026', [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
        ]);
    } catch (PDOException $e) {
        http_response_code(500);
        echo 'DB error';
        exit;
    }
    require_once __DIR__ . '/meta_procedures.php';

    if ($_SERVER['REQUEST_METHOD'] === 'GET') {
        meta_handleWebhookVerify();
    } else {
        meta_handleWebhookPost();
    }
    exit;
}

header('Content-Type: application/json; charset=utf-8');

// ─── Database ──────────────────────────────────────────────────
$dbHost = 'db_host';
$dbName = 'easytech_v2';
$dbUser = 'root';
$dbPass = 'EasyTech2026';

try {
    $db = new PDO(
        "mysql:host={$dbHost};dbname={$dbName};charset=utf8mb4",
        $dbUser, $dbPass,
        [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false,
        ]
    );
} catch (PDOException $e) {
    echo json_encode([['error' => ['json' => [
        'message' => 'Database connection failed',
        'code' => -32603,
    ]]]]);
    exit;
}

// ─── Session ───────────────────────────────────────────────────
$ctx = ['userId' => null];

$sessionId = $_COOKIE['app_session_id'] ?? null;
if (!$sessionId && isset($_GET['_token'])) {
    $sessionId = $_GET['_token'];
}
if (!$sessionId) {
    $auth = $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '';
    if (preg_match('/Bearer (.+)/', $auth, $am)) $sessionId = $am[1];
}
if (!$sessionId) {
    $raw = $_SERVER['HTTP_COOKIE'] ?? '';
    if (preg_match('/app_session_id=([^;]+)/', $raw, $m)) {
        $sessionId = $m[1];
    }
}

if ($sessionId) {
    $stmt = $db->prepare('SELECT user_id FROM sessions WHERE session_id = ? AND expires_at > NOW()');
    try {
        $stmt->execute([$sessionId]);
        $row = $stmt->fetch();
        if ($row) {
            $ctx['userId'] = (int) $row['user_id'];
        }
    } catch (PDOException $e) {
        // sessions table may not exist yet – ignore
    }
}

// ─── Parse tRPC request ────────────────────────────────────────
$uri = $_SERVER['REQUEST_URI'] ?? '';
$path = parse_url($uri, PHP_URL_PATH);
$procedure = preg_replace('#^.*/api/trpc/(.*)$#', '$1', $path);

$input = null;
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $body = json_decode(file_get_contents('php://input'), true);
    $input = $body['0']['json'] ?? [];
} elseif ($_SERVER['REQUEST_METHOD'] === 'GET') {
    $raw = $_GET['input'] ?? null;
    if ($raw) {
        $decoded = json_decode($raw, true);
        $input = $decoded['0']['json'] ?? [];
    }
}

// ─── Include procedures ────────────────────────────────────────
require_once __DIR__ . '/surveys_procedures.php';
require_once __DIR__ . '/tasks_procedures.php';
require_once __DIR__ . '/meta_procedures.php';
require_once __DIR__ . '/accounting_procedures.php';
require_once __DIR__ . '/permissions_procedures.php';
require_once __DIR__ . '/notifications_procedures.php';

// ─── Helper functions ──────────────────────────────────────────

function formatCategory(array $row): array {
    return [
        'id'          => (int) $row['id'],
        'name'        => $row['name'] ?? '',
        'nameAr'      => $row['name_ar'] ?? null,
        'description' => $row['description'] ?? null,
        'imageUrl'    => $row['image_url'] ?? null,
    ];
}

function formatProduct(array $row): array {
    $images = $row['images'] ? json_decode($row['images'], true) : [];
    $mainImage = $row['main_image_url'] ?? null;
    if (empty($mainImage) && is_array($images) && count($images) > 0) {
        $mainImage = $images[0];
    }
    $variants = ($row['variants'] ?? null) ? json_decode($row['variants'], true) : [];
    $types = ($row['types'] ?? null) ? json_decode($row['types'], true) : [];
    return [
        'id'            => (int) $row['id'],
        'name'          => $row['name'] ?? '',
        'nameAr'        => $row['name_ar'] ?? null,
        'description'   => $row['description'] ?? null,
        'descriptionAr' => $row['description_ar'] ?? null,
        'price'         => $row['price'] ?? '0',
        'originalPrice' => $row['original_price'] ?? null,
        'stock'         => (int) ($row['stock'] ?? 0),
        'isFeatured'    => (bool) ($row['is_featured'] ?? false),
        'isActive'      => (bool) ($row['is_active'] ?? true),
        'categoryId'    => $row['category_id'] ? (int) $row['category_id'] : null,
        'mainImageUrl'  => $mainImage,
        'images'        => $images,
        'variants'      => $variants,
        'types'         => $types,
        'sku'           => $row['sku'] ?? null,
        'serialNumber'  => $row['serial_number'] ?? null,
    ];
}

// ─── Router ────────────────────────────────────────────────────
try {
    $result = null;

    switch ($procedure) {

        // ── Auth ────────────────────────────────────────────────
        case 'auth.adminLogin':
            $email    = $input['email'] ?? '';
            $password = $input['password'] ?? '';

            $stmt = $db->prepare('SELECT id, name, email, password_hash, role FROM users WHERE email = ?');
            $stmt->execute([$email]);
            $user = $stmt->fetch();

            if (!$user || !password_verify($password, $user['password_hash'])) {
                throw new Exception('بيانات الدخول غير صحيحة');
            }
            if ($user['role'] === 'user') {
                throw new Exception('ليس لديك صلاحية الدخول كمسؤول');
            }

            $sid = bin2hex(random_bytes(32));
            $expires = date('Y-m-d H:i:s', strtotime('+30 days'));
            $db->prepare('INSERT INTO sessions (session_id, user_id, expires_at) VALUES (?, ?, ?)')
               ->execute([$sid, $user['id'], $expires]);

            setcookie('app_session_id', $sid, [
                'expires'  => strtotime($expires),
                'path'     => '/',
                'secure'   => true,
                'httponly'  => true,
                'samesite'  => 'None',
            ]);

            $result = [
                'user' => [
                    'id'    => (int) $user['id'],
                    'name'  => $user['name'],
                    'email' => $user['email'],
                    'role'  => $user['role'],
                ],
                'sessionToken' => $sid,
            ];
            break;

        case 'auth.userLogin':
            $email    = $input['email'] ?? '';
            $password = $input['password'] ?? '';

            $stmt = $db->prepare('SELECT id, name, email, password_hash, role FROM users WHERE email = ?');
            $stmt->execute([$email]);
            $user = $stmt->fetch();

            if (!$user || !password_verify($password, $user['password_hash'])) {
                throw new Exception('بيانات الدخول غير صحيحة');
            }

            $sid = bin2hex(random_bytes(32));
            $expires = date('Y-m-d H:i:s', strtotime('+30 days'));
            $db->prepare('INSERT INTO sessions (session_id, user_id, expires_at) VALUES (?, ?, ?)')
               ->execute([$sid, $user['id'], $expires]);

            setcookie('app_session_id', $sid, [
                'expires'  => strtotime($expires),
                'path'     => '/',
                'secure'   => true,
                'httponly'  => true,
                'samesite'  => 'None',
            ]);

            $result = [
                'user' => [
                    'id'    => (int) $user['id'],
                    'name'  => $user['name'],
                    'email' => $user['email'],
                    'role'  => $user['role'],
                ],
                'sessionToken' => $sid,
            ];
            break;

        case 'auth.me':
            if (!$ctx['userId']) {
                throw new Exception('UNAUTHORIZED');
            }
            $stmt = $db->prepare('SELECT id, name, email, role FROM users WHERE id = ?');
            $stmt->execute([$ctx['userId']]);
            $user = $stmt->fetch();
            if (!$user) throw new Exception('UNAUTHORIZED');
            $result = [
                'id'    => (int) $user['id'],
                'name'  => $user['name'],
                'email' => $user['email'],
                'role'  => $user['role'],
            ];
            break;

        case 'auth.logout':
            if ($sessionId) {
                try {
                    $db->prepare('DELETE FROM sessions WHERE session_id = ?')->execute([$sessionId]);
                } catch (PDOException $e) { /* ignore */ }
            }
            setcookie('app_session_id', '', ['expires' => 1, 'path' => '/']);
            $result = ['success' => true];
            break;

        // ── Categories ─────────────────────────────────────────
        case 'products.getCategories':
        case 'categories.list':
            $stmt = $db->query('SELECT * FROM categories ORDER BY id ASC');
            $rows = $stmt->fetchAll();
            $result = array_map('formatCategory', $rows);
            break;

        case 'products.createCategory':
            $name    = $input['name'] ?? '';
            $nameAr  = $input['nameAr'] ?? null;
            $desc    = $input['description'] ?? null;
            $imgUrl  = $input['imageUrl'] ?? null;

            $stmt = $db->prepare('INSERT INTO categories (name, name_ar, description, image_url) VALUES (?, ?, ?, ?)');
            $stmt->execute([$name, $nameAr, $desc, $imgUrl]);
            $result = ['id' => (int) $db->lastInsertId()];
            break;

        case 'products.updateCategory':
            $id      = (int) ($input['id'] ?? 0);
            $name    = $input['name'] ?? '';
            $nameAr  = $input['nameAr'] ?? null;
            $desc    = $input['description'] ?? null;
            $imgUrl  = $input['imageUrl'] ?? null;

            $stmt = $db->prepare('UPDATE categories SET name = ?, name_ar = ?, description = ?, image_url = ? WHERE id = ?');
            $stmt->execute([$name, $nameAr, $desc, $imgUrl, $id]);
            $result = ['success' => true];
            break;

        case 'products.deleteCategory':
            $id = (int) ($input['id'] ?? 0);
            $db->prepare('DELETE FROM categories WHERE id = ?')->execute([$id]);
            $result = ['success' => true];
            break;

        // ── Products ───────────────────────────────────────────
        case 'products.list':
            $sql = 'SELECT * FROM products WHERE is_active = 1';
            $params = [];
            if (!empty($input['categoryId'])) {
                $sql .= ' AND category_id = ?';
                $params[] = (int)$input['categoryId'];
            }
            if (!empty($input['search'])) {
                $sql .= ' AND (name LIKE ? OR name_ar LIKE ? OR serial_number LIKE ? OR sku LIKE ?)';
                $s = '%' . $input['search'] . '%';
                $params = array_merge($params, [$s, $s, $s, $s]);
            }
            $sql .= ' ORDER BY id DESC';
            $stmt = $db->prepare($sql);
            $stmt->execute($params);
            $rows = $stmt->fetchAll();
            $result = array_map('formatProduct', $rows);
            break;

        case 'products.listAdmin':
            $sql = 'SELECT * FROM products';
            $params = [];
            $where = [];
            if (!empty($input['categoryId'])) {
                $where[] = 'category_id = ?';
                $params[] = (int)$input['categoryId'];
            }
            if (!empty($input['search'])) {
                $where[] = '(name LIKE ? OR name_ar LIKE ? OR serial_number LIKE ? OR sku LIKE ?)';
                $s = '%' . $input['search'] . '%';
                $params = array_merge($params, [$s, $s, $s, $s]);
            }
            if ($where) $sql .= ' WHERE ' . implode(' AND ', $where);
            $sql .= ' ORDER BY id DESC';
            $stmt = $db->prepare($sql);
            $stmt->execute($params);
            $rows = $stmt->fetchAll();
            $result = array_map('formatProduct', $rows);
            break;

        case 'products.create':
            $name     = $input['name'] ?? '';
            $nameAr   = $input['nameAr'] ?? null;
            $desc     = $input['description'] ?? null;
            $descAr   = $input['descriptionAr'] ?? null;
            $price    = $input['price'] ?? '0';
            $origPrice= $input['originalPrice'] ?? null;
            $stock    = (int) ($input['stock'] ?? 0);
            $featured = ($input['isFeatured'] ?? false) ? 1 : 0;
            $catId    = isset($input['categoryId']) ? (int) $input['categoryId'] : null;
            $imgUrl   = $input['mainImageUrl'] ?? null;
            $images   = isset($input['images']) ? json_encode($input['images']) : null;
            $variants = isset($input['variants']) ? json_encode($input['variants']) : null;
            $types    = isset($input['types']) ? json_encode($input['types']) : null;
            $sku      = $input['sku'] ?? null;
            $serial   = $input['serialNumber'] ?? null;

            $stmt = $db->prepare('INSERT INTO products (name, name_ar, description, description_ar, price, original_price, stock, is_featured, category_id, main_image_url, images, variants, types, sku, serial_number) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)');
            $stmt->execute([$name, $nameAr, $desc, $descAr, $price, $origPrice, $stock, $featured, $catId, $imgUrl, $images, $variants, $types, $sku, $serial]);
            $result = ['id' => (int) $db->lastInsertId()];
            break;

        case 'products.update':
            $id       = (int) ($input['id'] ?? 0);
            $name     = $input['name'] ?? '';
            $nameAr   = $input['nameAr'] ?? null;
            $desc     = $input['description'] ?? null;
            $descAr   = $input['descriptionAr'] ?? null;
            $price    = $input['price'] ?? '0';
            $origPrice= $input['originalPrice'] ?? null;
            $stock    = (int) ($input['stock'] ?? 0);
            $featured = ($input['isFeatured'] ?? false) ? 1 : 0;
            $catId    = isset($input['categoryId']) ? (int) $input['categoryId'] : null;
            $imgUrl   = $input['mainImageUrl'] ?? null;
            $images   = isset($input['images']) ? json_encode($input['images']) : null;
            $variants = isset($input['variants']) ? json_encode($input['variants']) : null;
            $types    = isset($input['types']) ? json_encode($input['types']) : null;
            $sku      = $input['sku'] ?? null;
            $serial   = $input['serialNumber'] ?? null;

            $stmt = $db->prepare('UPDATE products SET name = ?, name_ar = ?, description = ?, description_ar = ?, price = ?, original_price = ?, stock = ?, is_featured = ?, category_id = ?, main_image_url = ?, images = ?, variants = ?, types = ?, sku = ?, serial_number = ? WHERE id = ?');
            $stmt->execute([$name, $nameAr, $desc, $descAr, $price, $origPrice, $stock, $featured, $catId, $imgUrl, $images, $variants, $types, $sku, $serial, $id]);
            $result = ['success' => true];
            break;

        case 'products.delete':
            $id = (int) ($input['id'] ?? 0);
            $db->prepare('DELETE FROM products WHERE id = ?')->execute([$id]);
            $result = ['success' => true];
            break;

        // ── Store Settings ─────────────────────────────────────
        case 'storeSettings.get':
            $result = [
                'companyName'   => 'Easy Tech',
                'companyNameAr' => 'ايزي تك',
                'bannerTitle'   => '',
                'bannerTitleAr' => 'حلول المنزل الذكي',
                'bannerImageUrl'=> '',
                'showBanner'    => true,
                'showCategories'=> true,
            ];
            break;

        // ── Surveys ────────────────────────────────────────────
        case 'surveys.create':
            $result = surveys_create($input, $ctx);
            break;

        case 'surveys.mySurveys':
            $result = surveys_mySurveys($ctx);
            break;

        case 'surveys.allSurveys':
            $result = surveys_allSurveys($ctx);
            break;

        case 'surveys.update':
            $result = surveys_update($input, $ctx);
            break;

        case 'surveys.delete':
            $result = surveys_delete($input, $ctx);
            break;

        // ── Clients ────────────────────────────────────────────
        case 'clients.allUsers':
            $result = clients_allUsers($ctx);
            break;

        case 'clients.updateUserById':
            $result = clients_updateUserById($input, $ctx);
            break;

        case 'clients.updateRole':
            $result = clients_updateRole($input, $ctx);
            break;

        case 'clients.create':
            $result = clients_create($input, $ctx);
            break;

        case 'clients.delete':
            $result = clients_delete($input, $ctx);
            break;

        case 'clients.list':
            $result = clients_list($ctx);
            break;

        case 'clients.staff':
            $result = clients_staff($ctx);
            break;

        // ── Tasks ─────────────────────────────────────────────
        case 'tasks.list':
            $result = tasks_list($ctx);
            break;

        case 'tasks.getMyTasks':
            $result = tasks_getMyTasks($ctx);
            break;

        case 'tasks.myTasks':
            $result = tasks_myTasks($ctx);
            break;

        case 'tasks.byId':
            $result = tasks_byId($input, $ctx);
            break;

        case 'tasks.items':
            $result = tasks_items($input, $ctx);
            break;

        case 'tasks.create':
            $result = tasks_create($input, $ctx);
            break;

        case 'tasks.update':
            $result = tasks_update($input, $ctx);
            break;

        case 'tasks.updateItem':
            $result = tasks_updateItem($input, $ctx);
            break;

        case 'tasks.addItemMedia':
            $result = tasks_addItemMedia($input, $ctx);
            break;

        case 'tasks.removeItemMedia':
            $result = tasks_removeItemMedia($input, $ctx);
            break;

        // ── Task Notes ────────────────────────────────────────
        case 'taskNotes.list':
            $result = taskNotes_list($input, $ctx);
            break;

        case 'taskNotes.listForClient':
            $result = taskNotes_listForClient($input, $ctx);
            break;

        case 'taskNotes.create':
            $result = taskNotes_create($input, $ctx);
            break;

        case 'taskNotes.delete':
            $result = taskNotes_delete($input, $ctx);
            break;

        // ── Technician Location ───────────────────────────────
        case 'technicianLocation.update':
            $result = technicianLocation_update($input, $ctx);
            break;

        // ── Quotations ────────────────────────────────────────
        case 'quotations.list':
            $result = quotations_list($ctx);
            break;

        case 'quotations.create':
            $result = quotations_create($input, $ctx);
            break;

        case 'quotations.getById':
            $result = quotations_getById($input, $ctx);
            break;

        case 'quotations.getByIdForClient':
            $result = quotations_getByIdForClient($input, $ctx);
            break;

        case 'quotations.myQuotations':
            $result = quotations_myQuotations($ctx);
            break;

        case 'quotations.respond':
            $result = quotations_respond($input, $ctx);
            break;

        case 'quotations.generatePdf':
            $result = quotations_generatePdf($input, $ctx);
            break;

        case 'quotations.send':
            $result = quotations_send($input, $ctx);
            break;

        case 'quotations.delete':
            $result = quotations_delete($input, $ctx);
            break;

        // ── Orders ────────────────────────────────────────────
        case 'orders.create':
            $result = orders_create($input, $ctx);
            break;

        case 'orders.getMyOrders':
            $result = orders_getMyOrders($ctx);
            break;

        // ── Meta / Messenger ──────────────────────────────────────
        case 'meta.listConversations':
            $result = meta_listConversations($input, $ctx);
            break;

        case 'meta.getConversation':
            $result = meta_getConversation($input, $ctx);
            break;

        case 'meta.sendReply':
            $result = meta_sendReply($input, $ctx);
            break;

        case 'meta.convertToLead':
            $result = meta_convertToLead($input, $ctx);
            break;

        case 'meta.refreshSenderNames':
            $result = meta_refreshSenderNames($input, $ctx);
            break;

        case 'meta.updateConversationName':
            $result = meta_updateConversationName($input, $ctx);
            break;

        case 'meta.updateConversationStatus':
            $result = meta_updateConversationStatus($input, $ctx);
            break;

        // ── CRM ────────────────────────────────────────────────────
        case 'crm.getLeads':
            $result = crm_getLeads($input ?? [], $ctx);
            break;

        case 'crm.getLeadById':
            $result = crm_getLeadById($input, $ctx);
            break;

        case 'crm.createLead':
            $result = crm_createLead($input, $ctx);
            break;

        case 'crm.updateLead':
            $result = crm_updateLead($input, $ctx);
            break;

        case 'crm.updateStage':
            $result = crm_updateStage($input, $ctx);
            break;

        case 'crm.assignLead':
            $result = crm_assignLead($input, $ctx);
            break;

        case 'crm.addActivity':
            $result = crm_addActivity($input, $ctx);
            break;

        case 'crm.deleteActivity':
            $result = crm_deleteActivity($input, $ctx);
            break;

        case 'crm.deleteLead':
            $result = crm_deleteLead($input, $ctx);
            break;

        case 'crm.getStats':
            $result = crm_getStats($input ?? [], $ctx);
            break;

        case 'crm.getStaffList':
            $result = crm_getStaffList($ctx);
            break;

        // ── Appointments (السكرتارية) ────────────────────────────
        case 'appointments.list':
            $result = appointments_list($input, $ctx);
            break;

        case 'appointments.create':
            $result = appointments_create($input, $ctx);
            break;

        case 'appointments.delete':
            $result = appointments_delete($input, $ctx);
            break;

        case 'appointments.staffList':
            $result = appointments_staffList($ctx);
            break;

        // ── Accounting (الحسابات والعهد) ───────────────────────
        case 'acc.getTransactions':
            $result = acc_getTransactions($input ?? [], $ctx);
            break;

        case 'acc.createTransaction':
            $result = acc_createTransaction($input, $ctx);
            break;

        case 'acc.approveTransaction':
            $result = acc_approveTransaction($input, $ctx);
            break;

        case 'acc.deleteTransaction':
            $result = acc_deleteTransaction($input, $ctx);
            break;

        case 'acc.getCustodyBalances':
            $result = acc_getCustodyBalances($input ?? [], $ctx);
            break;

        case 'acc.getTechnicianCustody':
            $result = acc_getTechnicianCustody($input ?? [], $ctx);
            break;

        case 'acc.getDashboard':
            $result = acc_getDashboard($input ?? [], $ctx);
            break;

        case 'acc.getExpenseCategories':
            $result = acc_getExpenseCategories($ctx);
            break;

        case 'acc.settleCustody':
            $result = acc_settleCustody($input, $ctx);
            break;

        // ── Permissions ──────────────────────────────────────
        case 'permissions.getRoles':
            $result = perm_getRoles($input, $ctx);
            break;
        case 'permissions.createRole':
            $result = perm_createRole($input, $ctx);
            break;
        case 'permissions.updateRole':
            $result = perm_updateRole($input, $ctx);
            break;
        case 'permissions.deleteRole':
            $result = perm_deleteRole($input, $ctx);
            break;
        case 'permissions.getRolePermissions':
            $result = perm_getRolePermissions($input, $ctx);
            break;
        case 'permissions.updateRolePermissions':
            $result = perm_updateRolePermissions($input, $ctx);
            break;
        case 'permissions.getAllPermissions':
            $result = perm_getAllPermissions($input, $ctx);
            break;
        case 'permissions.getUserPermissions':
            $result = perm_getUserPermissions($input, $ctx);
            break;
        case 'permissions.getUsers':
            $result = perm_getUsers($input, $ctx);
            break;
        case 'permissions.assignRole':
            $result = perm_assignRole($input, $ctx);
            break;

        // ── Notifications ────────────────────────────────────────
        case 'notifications.list':
            $result = notif_list($input, $ctx);
            break;
        case 'notifications.markRead':
            $result = notif_markRead($input, $ctx);
            break;
        case 'notifications.markAllRead':
            $result = notif_markAllRead($input, $ctx);
            break;
        case 'notifications.getUnreadCount':
            $result = notif_getUnreadCount($input, $ctx);
            break;
        case 'notifications.campaigns.create':
            $result = notif_campaignCreate($input, $ctx);
            break;
        case 'notifications.delete':
            $result = notif_delete($input, $ctx);
            break;
        case 'users.saveFcmToken':
            $result = notif_saveFcmToken($input, $ctx);
            break;

        // ── Unknown ────────────────────────────────────────────
        default:
            throw new Exception("Unknown Procedure: {$procedure}");
    }

    echo json_encode([['result' => ['data' => ['json' => $result]]]]);

} catch (Exception $e) {
    $msg = $e->getMessage();
    $code = 'INTERNAL_SERVER_ERROR';
    if (strpos($msg, 'UNAUTHORIZED') !== false) $code = 'UNAUTHORIZED';

    http_response_code(200);
    echo json_encode([['error' => ['json' => [
        'message' => $msg,
        'code'    => -32603,
        'data'    => ['code' => $code],
    ]]]]);
}
