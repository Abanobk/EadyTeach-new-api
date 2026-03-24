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
 * قائمة الفنيين (للاختيار في تقرير الأداء التفصيلي)
 */
function reports_technicianList($input, $ctx) {
    global $db;
    _reports_checkAccess($ctx);
    try {
        $rows = $db->query("
            SELECT u.id, u.name, u.email, u.phone,
                   (SELECT COUNT(*) FROM tasks t WHERE t.technician_id = u.id) AS total_tasks
            FROM users u
            WHERE LOWER(u.role) IN ('technician', 'admin')
            ORDER BY u.name ASC
        ")->fetchAll(PDO::FETCH_ASSOC);
    } catch (\Exception $e) {
        return ['rows' => []];
    }
    return [
        'rows' => array_map(function ($r) {
            return [
                'id' => (int)($r['id'] ?? 0),
                'name' => $r['name'] ?? '',
                'email' => $r['email'] ?? null,
                'phone' => $r['phone'] ?? null,
                'totalTasks' => (int)($r['total_tasks'] ?? 0),
            ];
        }, $rows),
    ];
}

/**
 * تحليل شامل لأداء فني واحد
 */
function reports_technicianPerformanceDetail($input, $ctx) {
    global $db;
    _reports_checkAccess($ctx);
    _ensureTaskCompletedAtColumn();
    $techId = (int)($input['technicianId'] ?? 0);
    if ($techId <= 0) {
        throw new Exception('technicianId مطلوب');
    }

    $tech = $db->prepare("SELECT id, name, email, phone FROM users WHERE id = ?");
    $tech->execute([$techId]);
    $techRow = $tech->fetch(PDO::FETCH_ASSOC);
    if (!$techRow) {
        throw new Exception('الفني غير موجود');
    }

    $stats = [
        'technicianId' => $techId,
        'technicianName' => $techRow['name'] ?? '',
        'email' => $techRow['email'] ?? null,
        'phone' => $techRow['phone'] ?? null,
        'totalAssigned' => 0,
        'completed' => 0,
        'overdue' => 0,
        'delayedCompleted' => 0,
        'onTimeCompleted' => 0,
        'cancelled' => 0,
        'inProgress' => 0,
        'pending' => 0,
        'onTimeRate' => 0,
        'avgCompletionHours' => null,
        'avgDelayHours' => null,
        'totalCollections' => 0,
        'recentTasks' => [],
    ];

    try {
        $stmt = $db->prepare("SELECT COUNT(*) FROM tasks WHERE technician_id = ?");
        $stmt->execute([$techId]);
        $stats['totalAssigned'] = (int)$stmt->fetchColumn();

        $stmt = $db->prepare("SELECT COUNT(*) FROM tasks WHERE technician_id = ? AND LOWER(TRIM(COALESCE(status,''))) = 'completed'");
        $stmt->execute([$techId]);
        $stats['completed'] = (int)$stmt->fetchColumn();

        $stmt = $db->prepare("SELECT COUNT(*) FROM tasks WHERE technician_id = ? AND LOWER(TRIM(COALESCE(status,''))) = 'cancelled'");
        $stmt->execute([$techId]);
        $stats['cancelled'] = (int)$stmt->fetchColumn();

        $stmt = $db->prepare("SELECT COUNT(*) FROM tasks WHERE technician_id = ? AND LOWER(TRIM(COALESCE(status,''))) = 'in_progress'");
        $stmt->execute([$techId]);
        $stats['inProgress'] = (int)$stmt->fetchColumn();

        $stmt = $db->prepare("SELECT COUNT(*) FROM tasks WHERE technician_id = ? AND LOWER(TRIM(COALESCE(status,''))) IN ('pending','assigned')");
        $stmt->execute([$techId]);
        $stats['pending'] = (int)$stmt->fetchColumn();

        // مهام متأخرة حالياً (لم تُنجز ولم تُلغَ وتجاوزت الموعد)
        $stmt = $db->prepare("
            SELECT COUNT(*) FROM tasks
            WHERE technician_id = ? AND status NOT IN ('completed', 'cancelled')
              AND (
                (estimated_arrival_at IS NOT NULL AND estimated_arrival_at < NOW())
                OR (estimated_arrival_at IS NULL AND scheduled_at IS NOT NULL AND (
                  (TIME(scheduled_at) <> '00:00:00' AND scheduled_at < NOW())
                  OR (TIME(scheduled_at) = '00:00:00' AND DATE(scheduled_at) < CURDATE())
                ))
              )
        ");
        $stmt->execute([$techId]);
        $stats['overdue'] = (int)$stmt->fetchColumn();

        // مهام مُنجزة متأخرة (تم الإنجاز بعد الموعد) + في الموعد
        $completedRows = $db->prepare("
            SELECT id, title, scheduled_at, estimated_arrival_at, completed_at, amount, status
            FROM tasks
            WHERE technician_id = ? AND LOWER(TRIM(COALESCE(status,''))) = 'completed'
        ");
        $completedRows->execute([$techId]);
        $rows = $completedRows->fetchAll(PDO::FETCH_ASSOC);

        $delayedCount = 0;
        $onTimeCount = 0;
        $totalCompletionHours = 0;
        $completionCount = 0;
        $totalDelayHours = 0;
        $delayCount = 0;

        foreach ($rows as $r) {
            $dueTs = null;
            if (!empty($r['estimated_arrival_at'])) {
                $dueTs = strtotime($r['estimated_arrival_at']);
            } elseif (!empty($r['scheduled_at'])) {
                $dueTs = strtotime($r['scheduled_at']);
            }
            $completedTs = !empty($r['completed_at']) ? strtotime($r['completed_at']) : null;

            if ($completedTs && $dueTs) {
                if ($completedTs > $dueTs) {
                    $delayedCount++;
                    $delayH = ($completedTs - $dueTs) / 3600;
                    $totalDelayHours += $delayH;
                    $delayCount++;
                } else {
                    $onTimeCount++;
                }
            } elseif ($completedTs) {
                $onTimeCount++;
            }

            $startTs = !empty($r['scheduled_at']) ? strtotime($r['scheduled_at']) : null;
            if (!$startTs) {
                $chk = $db->prepare("SELECT created_at FROM tasks WHERE id = ?");
                $chk->execute([$r['id']]);
                $cr = $chk->fetch();
                $startTs = $cr && !empty($cr['created_at']) ? strtotime($cr['created_at']) : null;
            }
            if ($completedTs && $startTs && $completedTs >= $startTs) {
                $totalCompletionHours += ($completedTs - $startTs) / 3600;
                $completionCount++;
            }
        }

        $stats['delayedCompleted'] = $delayedCount;
        $stats['onTimeCompleted'] = $onTimeCount;
        if ($stats['completed'] > 0) {
            $stats['onTimeRate'] = round(100 * $onTimeCount / $stats['completed'], 1);
        }
        if ($completionCount > 0) {
            $stats['avgCompletionHours'] = round($totalCompletionHours / $completionCount, 1);
        }
        if ($delayCount > 0) {
            $stats['avgDelayHours'] = round($totalDelayHours / $delayCount, 1);
        }

        // إجمالي التحصيلات
        try {
            $coll = $db->prepare("SELECT COALESCE(SUM(amount), 0) FROM acc_transactions WHERE technician_id = ? AND type = 'collection' AND status = 'approved'");
            $coll->execute([$techId]);
            $stats['totalCollections'] = (float)$coll->fetchColumn();
        } catch (\Exception $e) {}

        // آخر 20 مهمة
        $recent = $db->prepare("
            SELECT t.id, t.title, t.status, t.scheduled_at, t.estimated_arrival_at, t.completed_at, t.amount
            FROM tasks t
            WHERE t.technician_id = ?
            ORDER BY COALESCE(t.completed_at, t.scheduled_at) DESC, t.id DESC
            LIMIT 20
        ");
        $recent->execute([$techId]);
        $stats['recentTasks'] = array_map(function ($r) {
            return [
                'id' => (int)$r['id'],
                'title' => $r['title'] ?? '',
                'status' => $r['status'] ?? '',
                'scheduledAt' => $r['scheduled_at'] ?? null,
                'estimatedArrivalAt' => $r['estimated_arrival_at'] ?? null,
                'completedAt' => $r['completed_at'] ?? null,
                'amount' => (float)($r['amount'] ?? 0),
            ];
        }, $recent->fetchAll(PDO::FETCH_ASSOC));

    } catch (\Exception $e) {
        throw $e;
    }

    return $stats;
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
 * قائمة العملاء (لاختيار في التقرير التفصيلي)
 */
function reports_customerList($input, $ctx) {
    global $db;
    _reports_checkAccess($ctx);
    _ensureOrdersTable();
    try {
        $rows = $db->query("
            SELECT u.id, u.name, u.email, u.phone,
                   (SELECT COUNT(*) FROM orders o WHERE o.user_id = u.id) AS orders_count,
                   (SELECT COUNT(*) FROM tasks t WHERE t.customer_id = u.id) AS tasks_count
            FROM users u
            WHERE LOWER(u.role) IN ('user', 'client')
            ORDER BY u.name ASC
        ")->fetchAll(PDO::FETCH_ASSOC);
    } catch (\Exception $e) {
        return ['rows' => []];
    }
    return [
        'rows' => array_map(function ($r) {
            return [
                'id' => (int)($r['id'] ?? 0),
                'name' => $r['name'] ?? '',
                'email' => $r['email'] ?? null,
                'phone' => $r['phone'] ?? null,
                'ordersCount' => (int)($r['orders_count'] ?? 0),
                'tasksCount' => (int)($r['tasks_count'] ?? 0),
            ];
        }, $rows),
    ];
}

/**
 * تفاصيل عميل واحد — الطلبات، المهام، آخر معاملة، الطلبات الحالية
 */
function reports_customerDetail($input, $ctx) {
    global $db;
    _reports_checkAccess($ctx);
    _ensureOrdersTable();
    $customerId = (int)($input['customerId'] ?? 0);
    if ($customerId <= 0) {
        throw new Exception('customerId مطلوب');
    }

    $user = $db->prepare("SELECT id, name, email, phone, address FROM users WHERE id = ?");
    $user->execute([$customerId]);
    $userRow = $user->fetch(PDO::FETCH_ASSOC);
    if (!$userRow) {
        throw new Exception('العميل غير موجود');
    }

    $result = [
        'customer' => [
            'id' => $customerId,
            'name' => $userRow['name'] ?? '',
            'email' => $userRow['email'] ?? null,
            'phone' => $userRow['phone'] ?? null,
            'address' => $userRow['address'] ?? null,
        ],
        'orders' => [],
        'tasks' => [],
        'lastTransaction' => null,
        'activeRequests' => [],
    ];

    try {
        // الطلبات (orders بالـ user_id)
        $ordersStmt = $db->prepare("
            SELECT id, items, total, status, created_at, shipping_address
            FROM orders WHERE user_id = ?
            ORDER BY created_at DESC
        ");
        $ordersStmt->execute([$customerId]);
        foreach ($ordersStmt->fetchAll(PDO::FETCH_ASSOC) as $r) {
            $items = $r['items'] ? json_decode($r['items'], true) : [];
            $result['orders'][] = [
                'id' => (int)$r['id'],
                'items' => is_array($items) ? $items : [],
                'totalAmount' => (float)($r['total'] ?? 0),
                'status' => $r['status'] ?? 'pending',
                'createdAt' => $r['created_at'] ? strtotime($r['created_at']) * 1000 : null,
                'shippingAddress' => $r['shipping_address'] ?? null,
            ];
        }

        // المهام (tasks بالـ customer_id) — نتحقق من وجود created_at
        $hasCreatedAt = false;
        try {
            $chk = $db->query("SELECT created_at FROM tasks LIMIT 1");
            $hasCreatedAt = (bool)$chk->fetch();
        } catch (\Exception $e) {}
        $tasksCols = $hasCreatedAt ? 't.id, t.title, t.status, t.scheduled_at, t.estimated_arrival_at, t.amount, t.notes, t.created_at' : 't.id, t.title, t.status, t.scheduled_at, t.estimated_arrival_at, t.amount, t.notes';
        $tasksStmt = $db->prepare("
            SELECT $tasksCols, tech.name AS technician_name
            FROM tasks t
            LEFT JOIN users tech ON tech.id = t.technician_id
            WHERE t.customer_id = ?
            ORDER BY t.id DESC
        ");
        $tasksStmt->execute([$customerId]);
        foreach ($tasksStmt->fetchAll(PDO::FETCH_ASSOC) as $r) {
            $createdAt = null;
            if ($hasCreatedAt && isset($r['created_at']) && $r['created_at']) {
                $createdAt = strtotime($r['created_at']) * 1000;
            }
            $result['tasks'][] = [
                'id' => (int)$r['id'],
                'title' => $r['title'] ?? '',
                'status' => $r['status'] ?? 'pending',
                'scheduledAt' => $r['scheduled_at'] ?? null,
                'estimatedArrivalAt' => $r['estimated_arrival_at'] ?? null,
                'amount' => (float)($r['amount'] ?? 0),
                'notes' => $r['notes'] ?? null,
                'technicianName' => $r['technician_name'] ?? null,
                'createdAt' => $createdAt,
            ];
        }

        // آخر معاملة (طلب أو مهمة — الأحدث بتاريخ الإنشاء)
        $lastOrder = $result['orders'][0] ?? null;
        $lastTask = $result['tasks'][0] ?? null;
        $orderTs = $lastOrder && isset($lastOrder['createdAt']) ? (int)$lastOrder['createdAt'] : 0;
        $taskTs = $lastTask && isset($lastTask['createdAt']) ? (int)$lastTask['createdAt'] : 0;
        if ($orderTs >= $taskTs && $lastOrder) {
            $result['lastTransaction'] = ['type' => 'order', 'data' => $lastOrder];
        } elseif ($lastTask) {
            $result['lastTransaction'] = ['type' => 'task', 'data' => $lastTask];
        }

        // الطلبات الحالية (طلبات أو مهام غير منتهية)
        foreach ($result['orders'] as $o) {
            $s = strtolower(trim($o['status'] ?? ''));
            if (!in_array($s, ['delivered', 'cancelled'], true)) {
                $result['activeRequests'][] = ['type' => 'order', 'data' => $o];
            }
        }
        foreach ($result['tasks'] as $t) {
            $s = strtolower(trim($t['status'] ?? ''));
            if (!in_array($s, ['completed', 'cancelled'], true)) {
                $result['activeRequests'][] = ['type' => 'task', 'data' => $t];
            }
        }
    } catch (\Exception $e) {
        throw $e;
    }

    return $result;
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
 * قائمة حسابات العملاء — كل العملاء مع الرصيد (من عليه يظهر باللون الأحمر من الفهرس)
 */
function reports_customerAccountsList($input, $ctx) {
    global $db;
    _reports_checkAccess($ctx);
    _ensureOrdersTable();
    _ensureAccountingSchema();
    try {
        $rows = $db->query("
            SELECT u.id, u.name, u.email, u.phone,
                   COALESCE(o.orders_owed, 0) AS orders_owed,
                   COALESCE(t.due_total, 0) AS tasks_due,
                   COALESCE(c.collected_total, 0) AS collected_total,
                   COALESCE(o.orders_owed, 0) + COALESCE(t.due_total, 0) - COALESCE(c.collected_total, 0) AS balance
            FROM users u
            LEFT JOIN (
                SELECT user_id, COALESCE(SUM(total), 0) AS orders_owed
                FROM orders
                WHERE user_id IS NOT NULL AND LOWER(TRIM(COALESCE(status,''))) NOT IN ('delivered', 'cancelled')
                GROUP BY user_id
            ) o ON o.user_id = u.id
            LEFT JOIN (
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
            WHERE LOWER(u.role) IN ('user', 'client')
              AND (EXISTS (SELECT 1 FROM orders o2 WHERE o2.user_id = u.id) OR EXISTS (SELECT 1 FROM tasks t2 WHERE t2.customer_id = u.id))
            ORDER BY (COALESCE(o.orders_owed, 0) + COALESCE(t.due_total, 0) - COALESCE(c.collected_total, 0)) DESC, u.name ASC
            LIMIT 300
        ")->fetchAll(PDO::FETCH_ASSOC);
    } catch (\Exception $e) {
        return ['rows' => []];
    }
    return [
        'rows' => array_map(function ($r) {
            $balance = (float)($r['orders_owed'] ?? 0) + (float)($r['tasks_due'] ?? 0) - (float)($r['collected_total'] ?? 0);
            return [
                'customerId' => (int)($r['id'] ?? 0),
                'customerName' => $r['name'] ?? '',
                'email' => $r['email'] ?? null,
                'phone' => $r['phone'] ?? null,
                'ordersOwed' => (float)($r['orders_owed'] ?? 0),
                'tasksDue' => (float)($r['tasks_due'] ?? 0),
                'collectedTotal' => (float)($r['collected_total'] ?? 0),
                'balance' => $balance,
                'hasDebt' => $balance > 0,
            ];
        }, $rows),
    ];
}

/**
 * كشف حساب كامل لعميل — طلبات، مهام، تحصيلات، رصيد
 */
function reports_customerAccountStatement($input, $ctx) {
    global $db;
    _reports_checkAccess($ctx);
    _ensureOrdersTable();
    _ensureAccountingSchema();
    $customerId = (int)($input['customerId'] ?? 0);
    if ($customerId <= 0) throw new Exception('customerId مطلوب');

    $user = $db->prepare("SELECT id, name, email, phone, address FROM users WHERE id = ?");
    $user->execute([$customerId]);
    $u = $user->fetch(PDO::FETCH_ASSOC);
    if (!$u) throw new Exception('العميل غير موجود');

    $result = [
        'customer' => ['id' => $customerId, 'name' => $u['name'] ?? '', 'email' => $u['email'] ?? null, 'phone' => $u['phone'] ?? null, 'address' => $u['address'] ?? null],
        'orders' => [],
        'tasks' => [],
        'collections' => [],
        'ordersOwed' => 0,
        'tasksDue' => 0,
        'collectedTotal' => 0,
        'balance' => 0,
    ];

    try {
        $ordersStmt = $db->prepare("
            SELECT id, total, status, created_at, items
            FROM orders WHERE user_id = ?
            ORDER BY created_at DESC
        ");
        $ordersStmt->execute([$customerId]);
        $ordersOwed = 0;
        foreach ($ordersStmt->fetchAll(PDO::FETCH_ASSOC) as $r) {
            $s = strtolower(trim($r['status'] ?? ''));
            $amt = (float)($r['total'] ?? 0);
            if (!in_array($s, ['delivered', 'cancelled'], true)) {
                $ordersOwed += $amt;
            }
            $result['orders'][] = [
                'id' => (int)$r['id'],
                'totalAmount' => $amt,
                'status' => $r['status'] ?? 'pending',
                'createdAt' => $r['created_at'] ? strtotime($r['created_at']) * 1000 : null,
                'items' => $r['items'] ? json_decode($r['items'], true) : [],
            ];
        }
        $result['ordersOwed'] = $ordersOwed;

        $tasksStmt = $db->prepare("
            SELECT t.id, t.title, t.amount, t.status, t.scheduled_at, tech.name AS technician_name
            FROM tasks t
            LEFT JOIN users tech ON tech.id = t.technician_id
            WHERE t.customer_id = ?
            ORDER BY t.id DESC
        ");
        $tasksStmt->execute([$customerId]);
        $tasksDue = 0;
        foreach ($tasksStmt->fetchAll(PDO::FETCH_ASSOC) as $r) {
            $s = strtolower(trim($r['status'] ?? ''));
            $amt = (float)($r['amount'] ?? 0);
            if ($s === 'completed' && $amt > 0) {
                $tasksDue += $amt;
            }
            $result['tasks'][] = [
                'id' => (int)$r['id'],
                'title' => $r['title'] ?? '',
                'amount' => $amt,
                'status' => $r['status'] ?? '',
                'scheduledAt' => $r['scheduled_at'] ?? null,
                'technicianName' => $r['technician_name'] ?? null,
            ];
        }
        $result['tasksDue'] = $tasksDue;

        $collStmt = $db->prepare("
            SELECT acc.id, acc.amount, acc.created_at, acc.description, t.title AS task_title
            FROM acc_transactions acc
            INNER JOIN tasks t ON t.id = acc.task_id
            WHERE acc.type = 'collection' AND t.customer_id = ?
            ORDER BY acc.created_at DESC
        ");
        $collStmt->execute([$customerId]);
        $collectedTotal = 0;
        foreach ($collStmt->fetchAll(PDO::FETCH_ASSOC) as $r) {
            $amt = (float)($r['amount'] ?? 0);
            $collectedTotal += $amt;
            $result['collections'][] = [
                'id' => (int)$r['id'],
                'amount' => $amt,
                'createdAt' => $r['created_at'] ? strtotime($r['created_at']) * 1000 : null,
                'description' => $r['description'] ?? null,
                'taskTitle' => $r['task_title'] ?? null,
            ];
        }
        $result['collectedTotal'] = $collectedTotal;
        $result['balance'] = $ordersOwed + $tasksDue - $collectedTotal;
    } catch (\Exception $e) {
        throw $e;
    }
    return $result;
}

/**
 * تقرير حسابات العملاء — المستحق من المهام، تم تحصيله، المتبقي (للتوافق مع الشاشة القديمة)
 */
function reports_customerAccounts($input, $ctx) {
    $list = reports_customerAccountsList($input, $ctx);
    $list['rows'] = array_filter($list['rows'], fn($r) => ($r['balance'] ?? 0) > 0);
    return $list;
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
