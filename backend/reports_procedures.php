<?php
/**
 * التقارير — واجهات API للتقارير التفصيلية
 * يستخدمها: admin_reports_screen.dart
 */

function _reports_checkAccess($ctx) {
    $userId = (int)($ctx['userId'] ?? 0);
    if ($userId <= 0) {
        throw new Exception('UNAUTHORIZED');
    }
    global $db;
    $roleStmt = $db->prepare("SELECT role FROM users WHERE id = ?");
    $roleStmt->execute([$userId]);
    $role = $roleStmt->fetchColumn();
    $roleLower = $role ? strtolower(trim((string)$role)) : '';
    $allowedRoles = ['admin', 'staff', 'supervisor'];
    if (in_array($roleLower, $allowedRoles, true)) {
        return;
    }
    require_once __DIR__ . '/permissions_procedures.php';
    $permsRes = perm_getUserPermissions(['userId' => $userId], $ctx);
    if (!in_array('reports.view', $permsRes['permissions'] ?? [], true)) {
        throw new Exception('FORBIDDEN');
    }
}

/**
 * تقرير المبيعات الشهري — إجمالي الطلبات وقيمتها لكل شهر
 */
function reports_monthlySales($input, $ctx) {
    global $db;
    _reports_checkAccess($ctx);
    _ensureOrdersTable();
    try {
        $rows = $db->query("
            SELECT YEAR(created_at) AS y, MONTH(created_at) AS m,
                   COUNT(*) AS count, COALESCE(SUM(total), 0) AS total
            FROM orders
            WHERE created_at IS NOT NULL
            GROUP BY YEAR(created_at), MONTH(created_at)
            ORDER BY y DESC, m DESC
            LIMIT 24
        ")->fetchAll(PDO::FETCH_ASSOC);
    } catch (\Exception $e) {
        return ['rows' => []];
    }
    $months = ['', 'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
    return [
        'rows' => array_map(function ($r) use ($months) {
            $m = (int)($r['m'] ?? 0);
            return [
                'year' => (int)($r['y'] ?? 0),
                'month' => $m,
                'monthName' => $months[$m] ?? (string)$m,
                'count' => (int)($r['count'] ?? 0),
                'total' => (float)($r['total'] ?? 0),
            ];
        }, $rows),
    ];
}

/**
 * تقرير العملاء الجدد — عدد العملاء المسجلين لكل شهر
 */
function reports_newCustomers($input, $ctx) {
    global $db;
    _reports_checkAccess($ctx);
    try {
        $rows = $db->query("
            SELECT YEAR(created_at) AS y, MONTH(created_at) AS m, COUNT(*) AS count
            FROM users
            WHERE LOWER(role) IN ('user', 'client') AND created_at IS NOT NULL
            GROUP BY YEAR(created_at), MONTH(created_at)
            ORDER BY y DESC, m DESC
            LIMIT 24
        ")->fetchAll(PDO::FETCH_ASSOC);
    } catch (\Exception $e) {
        return ['rows' => []];
    }
    $months = ['', 'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
    return [
        'rows' => array_map(function ($r) use ($months) {
            $m = (int)($r['m'] ?? 0);
            return [
                'year' => (int)($r['y'] ?? 0),
                'month' => $m,
                'monthName' => $months[$m] ?? (string)$m,
                'count' => (int)($r['count'] ?? 0),
            ];
        }, $rows),
    ];
}

/**
 * تقرير أداء الفنيين — عدد المهام المنجزة لكل فني
 */
function reports_technicianPerformance($input, $ctx) {
    global $db;
    _reports_checkAccess($ctx);
    try {
        $rows = $db->query("
            SELECT t.technician_id, u.name AS technician_name,
                   COUNT(*) AS completed_count
            FROM tasks t
            LEFT JOIN users u ON u.id = t.technician_id
            WHERE LOWER(TRIM(COALESCE(t.status,''))) = 'completed'
              AND t.technician_id IS NOT NULL
            GROUP BY t.technician_id, u.name
            ORDER BY completed_count DESC
        ")->fetchAll(PDO::FETCH_ASSOC);
    } catch (\Exception $e) {
        return ['rows' => []];
    }
    return [
        'rows' => array_map(function ($r) {
            return [
                'technicianId' => (int)($r['technician_id'] ?? 0),
                'technicianName' => $r['technician_name'] ?? 'غير معروف',
                'completedCount' => (int)($r['completed_count'] ?? 0),
            ];
        }, $rows),
    ];
}

/**
 * تقرير المخزون / المنتجات الأكثر مبيعاً — من عناصر الطلبات
 */
function reports_topProducts($input, $ctx) {
    global $db;
    _reports_checkAccess($ctx);
    _ensureOrdersTable();
    try {
        $orderRows = $db->query("SELECT items FROM orders WHERE items IS NOT NULL AND items != '' AND items != '[]'")->fetchAll(PDO::FETCH_COLUMN);
    } catch (\Exception $e) {
        return ['rows' => []];
    }
    $byProduct = [];
    foreach ($orderRows as $json) {
        $items = json_decode($json, true);
        if (!is_array($items)) continue;
        foreach ($items as $it) {
            $pid = (int)($it['productId'] ?? $it['product_id'] ?? 0);
            $qty = (int)($it['quantity'] ?? $it['qty'] ?? 1);
            if ($pid > 0) {
                $byProduct[$pid] = ($byProduct[$pid] ?? 0) + $qty;
            }
        }
    }
    arsort($byProduct);
    $top = array_slice(array_keys($byProduct), 0, 50, true);
    if (empty($top)) {
        return ['rows' => []];
    }
    $placeholders = implode(',', array_fill(0, count($top), '?'));
    $stmt = $db->prepare("SELECT id, name, name_ar, price FROM products WHERE id IN ($placeholders)");
    $stmt->execute(array_values($top));
    $products = [];
    while ($r = $stmt->fetch(PDO::FETCH_ASSOC)) {
        $products[(int)$r['id']] = $r;
    }
    $rows = [];
    foreach ($top as $pid) {
        $p = $products[$pid] ?? null;
        $rows[] = [
            'productId' => $pid,
            'productName' => $p ? ($p['name_ar'] ?: $p['name'] ?: '') : 'غير معروف',
            'soldCount' => $byProduct[$pid] ?? 0,
            'price' => $p ? (float)($p['price'] ?? 0) : 0,
        ];
    }
    return ['rows' => $rows];
}

/**
 * تقرير إجمالي العملاء — قائمة العملاء مع عدد الطلبات والمهام وإجمالياتها
 */
function reports_customerSummary($input, $ctx) {
    global $db;
    _reports_checkAccess($ctx);
    _ensureOrdersTable();
    try {
        $rows = $db->query("
            SELECT u.id, u.name, u.email, u.phone,
                   COALESCE(o.orders_count, 0) AS orders_count,
                   COALESCE(o.orders_total, 0) AS orders_total,
                   COALESCE(t.tasks_count, 0) AS tasks_count,
                   COALESCE(t.tasks_total, 0) AS tasks_total
            FROM users u
            LEFT JOIN (
                SELECT user_id, COUNT(*) AS orders_count, COALESCE(SUM(total), 0) AS orders_total
                FROM orders GROUP BY user_id
            ) o ON o.user_id = u.id
            LEFT JOIN (
                SELECT customer_id, COUNT(*) AS tasks_count, COALESCE(SUM(amount), 0) AS tasks_total
                FROM tasks WHERE customer_id IS NOT NULL GROUP BY customer_id
            ) t ON t.customer_id = u.id
            WHERE LOWER(u.role) IN ('user', 'client')
            ORDER BY (COALESCE(o.orders_total, 0) + COALESCE(t.tasks_total, 0)) DESC
            LIMIT 200
        ")->fetchAll(PDO::FETCH_ASSOC);
    } catch (\Exception $e) {
        return ['rows' => []];
    }
    return [
        'rows' => array_map(function ($r) {
            return [
                'customerId' => (int)($r['id'] ?? 0),
                'customerName' => $r['name'] ?? '',
                'email' => $r['email'] ?? null,
                'phone' => $r['phone'] ?? null,
                'ordersCount' => (int)($r['orders_count'] ?? 0),
                'ordersTotal' => (float)($r['orders_total'] ?? 0),
                'tasksCount' => (int)($r['tasks_count'] ?? 0),
                'tasksTotal' => (float)($r['tasks_total'] ?? 0),
                'totalRevenue' => (float)($r['orders_total'] ?? 0) + (float)($r['tasks_total'] ?? 0),
            ];
        }, $rows),
    ];
}

/**
 * تقرير حسابات العملاء — المستحق من المهام، تم تحصيله، المتبقي
 */
function reports_customerAccounts($input, $ctx) {
    global $db;
    _reports_checkAccess($ctx);
    _ensureAccountingSchema();
    try {
        $rows = $db->query("
            SELECT u.id, u.name, u.email, u.phone,
                   COALESCE(t.due_total, 0) AS due_total,
                   COALESCE(c.collected_total, 0) AS collected_total,
                   (COALESCE(t.due_total, 0) - COALESCE(c.collected_total, 0)) AS balance
            FROM users u
            INNER JOIN (
                SELECT customer_id, SUM(amount) AS due_total
                FROM tasks
                WHERE customer_id IS NOT NULL
                  AND LOWER(TRIM(COALESCE(status,''))) = 'completed'
                  AND amount > 0
                GROUP BY customer_id
            ) t ON t.customer_id = u.id
            LEFT JOIN (
                SELECT ta.customer_id, SUM(acc.amount) AS collected_total
                FROM acc_transactions acc
                INNER JOIN tasks ta ON ta.id = acc.task_id
                WHERE acc.type = 'collection' AND acc.task_id IS NOT NULL
                GROUP BY ta.customer_id
            ) c ON c.customer_id = u.id
            WHERE (COALESCE(t.due_total, 0) - COALESCE(c.collected_total, 0)) > 0
            ORDER BY balance DESC
            LIMIT 200
        ")->fetchAll(PDO::FETCH_ASSOC);
    } catch (\Exception $e) {
        return ['rows' => []];
    }
    return [
        'rows' => array_map(function ($r) {
            return [
                'customerId' => (int)($r['id'] ?? 0),
                'customerName' => $r['name'] ?? '',
                'email' => $r['email'] ?? null,
                'phone' => $r['phone'] ?? null,
                'dueTotal' => (float)($r['due_total'] ?? 0),
                'collectedTotal' => (float)($r['collected_total'] ?? 0),
                'balance' => (float)($r['balance'] ?? 0),
            ];
        }, $rows),
    ];
}

/**
 * تقرير إيرادات العملاء — ترتيب العملاء حسب إجمالي الإنفاق (طلبات + مهام)
 */
function reports_customerRevenue($input, $ctx) {
    global $db;
    _reports_checkAccess($ctx);
    _ensureOrdersTable();
    try {
        $rows = $db->query("
            SELECT u.id, u.name, u.email, u.phone,
                   COALESCE(o.orders_total, 0) AS orders_total,
                   COALESCE(t.tasks_total, 0) AS tasks_total,
                   (COALESCE(o.orders_total, 0) + COALESCE(t.tasks_total, 0)) AS total_revenue
            FROM users u
            LEFT JOIN (
                SELECT user_id, COALESCE(SUM(total), 0) AS orders_total
                FROM orders GROUP BY user_id
            ) o ON o.user_id = u.id
            LEFT JOIN (
                SELECT customer_id, COALESCE(SUM(amount), 0) AS tasks_total
                FROM tasks WHERE customer_id IS NOT NULL AND LOWER(TRIM(COALESCE(status,''))) = 'completed'
                GROUP BY customer_id
            ) t ON t.customer_id = u.id
            WHERE LOWER(u.role) IN ('user', 'client')
              AND (COALESCE(o.orders_total, 0) + COALESCE(t.tasks_total, 0)) > 0
            ORDER BY total_revenue DESC
            LIMIT 100
        ")->fetchAll(PDO::FETCH_ASSOC);
    } catch (\Exception $e) {
        return ['rows' => []];
    }
    return [
        'rows' => array_map(function ($r) {
            return [
                'customerId' => (int)($r['id'] ?? 0),
                'customerName' => $r['name'] ?? '',
                'email' => $r['email'] ?? null,
                'phone' => $r['phone'] ?? null,
                'ordersTotal' => (float)($r['orders_total'] ?? 0),
                'tasksTotal' => (float)($r['tasks_total'] ?? 0),
                'totalRevenue' => (float)($r['total_revenue'] ?? 0),
            ];
        }, $rows),
    ];
}
