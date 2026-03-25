<?php
/**
 * Tasks, TaskNotes, TechnicianLocation, Quotations, Orders procedures
 */

function _ensureTaskCompletedAtColumn() {
    global $db;
    static $done = false;
    if ($done) return;
    try {
        $db->exec('ALTER TABLE tasks ADD COLUMN completed_at DATETIME NULL DEFAULT NULL');
    } catch (\Exception $e) { /* موجود */ }
    $done = true;
}

/**
 * عمود آخر إشعار تأخير — يُستخدم لمنع تكرار الإشعارات في نفس الدقيقة.
 */
function _ensureTaskOverdueNotifyColumn() {
    global $db;
    static $done = false;
    if ($done) {
        return;
    }
    try {
        $db->exec('ALTER TABLE tasks ADD COLUMN overdue_last_notified_at DATETIME NULL DEFAULT NULL');
    } catch (\Exception $e) {
        // العمود موجود مسبقاً
    }
    $done = true;
}

/**
 * مهام تجاوزت الموعد (لم تُنجز / لم تُلغَ) مع فني معيّن — تذكير الفني والمشرفين بفاصل زمني.
 * يُستدعى من task_overdue_cron.php عبر cron كل 15–30 دقيقة.
 *
 * @param int $intervalMinutes أقل فاصل بين تذكيرين لنفس المهمة (افتراضي 90 دقيقة)
 * @return array{sent:int,tasks:int}
 */
function tasks_runOverdueReminders($intervalMinutes = 90) {
    global $db;
    $intervalMinutes = max(15, min(1440, (int) $intervalMinutes));

    _ensureTaskOverdueNotifyColumn();
    if (!function_exists('_notifyUser')) {
        require_once __DIR__ . '/notifications_procedures.php';
    }
    _ensureNotificationsSchema();

    // موعد نهائي: estimated_arrival أولاً؛ وإلا scheduled_at (يوم كامل إن كان الوقت 00:00:00، وإلا مقارنة فورية)
    $sql = "
        SELECT id, title, technician_id, scheduled_at, estimated_arrival_at
        FROM tasks
        WHERE status NOT IN ('completed', 'cancelled')
          AND technician_id IS NOT NULL
          AND (
            (estimated_arrival_at IS NOT NULL AND estimated_arrival_at < NOW())
            OR (
              estimated_arrival_at IS NULL
              AND scheduled_at IS NOT NULL
              AND (
                (TIME(scheduled_at) <> '00:00:00' AND scheduled_at < NOW())
                OR (TIME(scheduled_at) = '00:00:00' AND DATE(scheduled_at) < CURDATE())
              )
            )
          )
          AND (
            overdue_last_notified_at IS NULL
            OR overdue_last_notified_at < DATE_SUB(NOW(), INTERVAL " . (int) $intervalMinutes . " MINUTE)
          )
    ";

    $rows = $db->query($sql)->fetchAll(PDO::FETCH_ASSOC);
    $sent = 0;
    foreach ($rows as $r) {
        $tid = (int) $r['id'];
        $title = $r['title'] ?? 'مهمة';
        $techId = (int) $r['technician_id'];
        try {
            _notifyUser(
                $techId,
                'مهمة متأخرة',
                "تجاوزت المهمة \"{$title}\" الموعد المحدد. يرجى الإنجاز أو طلب ترحيل الموعد من المشرف.",
                'task',
                $tid,
                'task',
                ['reason' => 'task_overdue']
            );
            _notifyAdminsAndSupervisors(
                'مهمة متأخرة',
                "المهمة \"{$title}\" (#{$tid}) تجاوزت الموعد ولم تُنجَز بعد. يرجى المتابعة أو الترحيل.",
                'task',
                $tid,
                'task',
                ['reason' => 'task_overdue']
            );
            $db->prepare('UPDATE tasks SET overdue_last_notified_at = NOW() WHERE id = ?')->execute([$tid]);
            $sent++;
        } catch (\Exception $e) {
            error_log('tasks_runOverdueReminders: ' . $e->getMessage());
        }
    }

    return ['sent' => $sent, 'tasks' => count($rows)];
}

// ─── tasks.list ────────────────────────────────────────────────
function tasks_list($ctx) {
    global $db;
    $rows = $db->query('
        SELECT t.*,
               c.name AS customer_name, c.phone AS customer_phone, c.address AS customer_address, c.location AS customer_location,
               tech.name AS technician_name
        FROM tasks t
        LEFT JOIN users c ON c.id = t.customer_id
        LEFT JOIN users tech ON tech.id = t.technician_id
        ORDER BY t.created_at DESC
    ')->fetchAll();

    _ensureItemProgressColumns();
    $result = [];
    foreach ($rows as $r) {
        $items = $db->prepare('SELECT id, description, is_completed, progress FROM task_items WHERE task_id = ?');
        $items->execute([$r['id']]);
        $itemRows = $items->fetchAll();

        $totalProgress = 0;
        $itemCount = count($itemRows);
        foreach ($itemRows as $i) {
            $totalProgress += (int)($i['progress'] ?? ($i['is_completed'] ? 100 : 0));
        }
        $overallProgress = $itemCount > 0 ? round($totalProgress / $itemCount) : 0;

        $result[] = [
            'id' => (int)$r['id'],
            'title' => $r['title'] ?? '',
            'status' => $r['status'] ?? 'pending',
            'customerId' => $r['customer_id'] ? (int)$r['customer_id'] : null,
            'technicianId' => $r['technician_id'] ? (int)$r['technician_id'] : null,
            'customerName' => $r['customer_name'] ?? null,
            'customerPhone' => $r['customer_phone'] ?? null,
            'customerAddress' => $r['customer_address'] ?? null,
            'customerLocation' => $r['customer_location'] ?? null,
            'technicianName' => $r['technician_name'] ?? null,
            'technician' => $r['technician_id'] ? ['id' => (int)$r['technician_id'], 'name' => $r['technician_name'] ?? ''] : null,
            'scheduledAt' => $r['scheduled_at'] ?? null,
            'estimatedArrivalAt' => $r['estimated_arrival_at'] ?? null,
            'amount' => $r['amount'] ?? null,
            'collectionType' => $r['collection_type'] ?? null,
            'notes' => $r['notes'] ?? null,
            'createdAt' => $r['created_at'] ?? null,
            'overallProgress' => (int)$overallProgress,
            'items' => array_map(function($i) {
                return [
                    'id' => (int)$i['id'],
                    'description' => $i['description'],
                    'isCompleted' => (bool)$i['is_completed'],
                    'progress' => (int)($i['progress'] ?? ($i['is_completed'] ? 100 : 0)),
                ];
            }, $itemRows),
        ];
    }
    return $result;
}

// ─── tasks.getMyTasks (technician) ─────────────────────────────
function tasks_getMyTasks($ctx) {
    global $db;
    if (!$ctx['userId']) throw new Exception('UNAUTHORIZED');
    $stmt = $db->prepare('
        SELECT t.*,
               c.name AS customer_name, c.phone AS customer_phone, c.address AS customer_address, c.location AS customer_location,
               tech.name AS technician_name
        FROM tasks t
        LEFT JOIN users c ON c.id = t.customer_id
        LEFT JOIN users tech ON tech.id = t.technician_id
        WHERE t.technician_id = ?
        ORDER BY t.created_at DESC
    ');
    $stmt->execute([$ctx['userId']]);
    $rows = $stmt->fetchAll();

    _ensureItemProgressColumns();
    $result = [];
    foreach ($rows as $r) {
        $items = $db->prepare('SELECT id, description, is_completed, progress FROM task_items WHERE task_id = ?');
        $items->execute([$r['id']]);
        $result[] = _formatTaskRow($r, $items->fetchAll());
    }
    return $result;
}

// ─── tasks.myTasks (client) ────────────────────────────────────
function tasks_myTasks($ctx) {
    global $db;
    if (!$ctx['userId']) throw new Exception('UNAUTHORIZED');
    $stmt = $db->prepare('
        SELECT t.*, tech.name AS technician_name
        FROM tasks t
        LEFT JOIN users tech ON tech.id = t.technician_id
        WHERE t.customer_id = ?
        ORDER BY t.created_at DESC
    ');
    $stmt->execute([$ctx['userId']]);
    $rows = $stmt->fetchAll();

    $result = [];
    foreach ($rows as $r) {
        $result[] = [
            'id' => (int)$r['id'],
            'title' => $r['title'] ?? '',
            'status' => $r['status'] ?? 'pending',
            'scheduledAt' => $r['scheduled_at'] ? strtotime($r['scheduled_at']) * 1000 : null,
            'technicianName' => $r['technician_name'] ?? null,
            'notes' => $r['notes'] ?? null,
            'amount' => $r['amount'] ?? null,
        ];
    }
    return $result;
}

// ─── tasks.byId ────────────────────────────────────────────────
function tasks_byId($input, $ctx) {
    global $db;
    $id = (int)($input['id'] ?? 0);
    $stmt = $db->prepare('
        SELECT t.*,
               c.name AS customer_name, c.phone AS customer_phone, c.address AS customer_address, c.location AS customer_location,
               tech.name AS technician_name
        FROM tasks t
        LEFT JOIN users c ON c.id = t.customer_id
        LEFT JOIN users tech ON tech.id = t.technician_id
        WHERE t.id = ?
    ');
    $stmt->execute([$id]);
    $r = $stmt->fetch();
    if (!$r) throw new Exception('Task not found');

    return [
        'id' => (int)$r['id'],
        'title' => $r['title'] ?? '',
        'status' => $r['status'] ?? 'pending',
        'scheduledAt' => $r['scheduled_at'] ?? null,
        'estimatedArrivalAt' => $r['estimated_arrival_at'] ?? null,
        'amount' => $r['amount'] ?? null,
        'collectionType' => $r['collection_type'] ?? null,
        'notes' => $r['notes'] ?? null,
        'createdAt' => $r['created_at'] ?? null,
        'customerName' => $r['customer_name'] ?? null,
        'customerPhone' => $r['customer_phone'] ?? null,
        'customerAddress' => $r['customer_address'] ?? null,
        'customerLocation' => $r['customer_location'] ?? null,
        'technicianName' => $r['technician_name'] ?? null,
        'customer' => $r['customer_id'] ? [
            'name' => $r['customer_name'] ?? '',
            'phone' => $r['customer_phone'] ?? '',
            'address' => $r['customer_address'] ?? '',
            'location' => $r['customer_location'] ?? '',
        ] : null,
        'technician' => $r['technician_id'] ? ['name' => $r['technician_name'] ?? ''] : null,
    ];
}

// ─── tasks.items ───────────────────────────────────────────────
function _ensureItemProgressColumns() {
    global $db;
    $cols = [];
    try {
        foreach ($db->query("SHOW COLUMNS FROM task_items")->fetchAll() as $c) $cols[] = $c['Field'];
    } catch (\Exception $e) { return; }
    if (!in_array('progress', $cols)) {
        $db->exec("ALTER TABLE task_items ADD COLUMN progress INT DEFAULT 0 AFTER is_completed");
    }
    if (!in_array('progress_note', $cols)) {
        $db->exec("ALTER TABLE task_items ADD COLUMN progress_note TEXT DEFAULT NULL AFTER progress");
    }
}

function _formatTaskItem($r) {
    return [
        'id' => (int)$r['id'],
        'description' => $r['description'] ?? '',
        'isCompleted' => (bool)($r['is_completed'] ?? false),
        'progress' => (int)($r['progress'] ?? ($r['is_completed'] ? 100 : 0)),
        'progressNote' => $r['progress_note'] ?? '',
        'mediaUrls' => isset($r['media_urls']) && $r['media_urls'] ? json_decode($r['media_urls'], true) : [],
        'mediaTypes' => isset($r['media_types']) && $r['media_types'] ? json_decode($r['media_types'], true) : [],
    ];
}

function tasks_items($input, $ctx) {
    global $db;
    _ensureItemProgressColumns();
    $taskId = (int)($input['taskId'] ?? 0);
    $stmt = $db->prepare('SELECT * FROM task_items WHERE task_id = ? ORDER BY id ASC');
    $stmt->execute([$taskId]);
    return array_map('_formatTaskItem', $stmt->fetchAll());
}

// ─── tasks.create ──────────────────────────────────────────────
function tasks_create($input, $ctx) {
    global $db;
    $title = $input['title'] ?? '';
    $customerId = isset($input['customerId']) ? (int)$input['customerId'] : null;
    $technicianId = isset($input['technicianId']) ? (int)$input['technicianId'] : null;
    $scheduledAt = $input['scheduledAt'] ?? null;
    $estimatedArrivalAt = $input['estimatedArrivalAt'] ?? null;
    $amount = $input['amount'] ?? null;
    $collectionType = $input['collectionType'] ?? null;
    $notes = $input['notes'] ?? null;
    $status = $technicianId ? 'assigned' : 'pending';

    $stmt = $db->prepare('INSERT INTO tasks (title, customer_id, technician_id, status, collection_type, amount, notes, scheduled_at, estimated_arrival_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)');
    $stmt->execute([$title, $customerId, $technicianId, $status, $collectionType, $amount, $notes, $scheduledAt, $estimatedArrivalAt]);
    $taskId = (int)$db->lastInsertId();

    $items = $input['items'] ?? [];
    if (!empty($items)) {
        $ins = $db->prepare('INSERT INTO task_items (task_id, description, is_completed) VALUES (?, ?, 0)');
        foreach ($items as $desc) {
            $ins->execute([$taskId, $desc]);
        }
    }

    // Notify technician about new task assignment
    if ($technicianId) {
        try {
            _notifyUser($technicianId, 'مهمة جديدة', "تم تعيينك لمهمة: {$title}", 'task', $taskId, 'task');
        } catch (\Throwable $e) {
            error_log('[FCM] tasks.create notify technician: ' . $e->getMessage());
        }
    }

    // إشعار الإدارة/المشرفين/الموظفين بأي مهمة جديدة.
    // سابقاً: إذا أُنشئت المهمة من الويب بدون فني لم يُرسل أي FCM — فيظن المستخدم أن الإشعارات معطلة.
    try {
        $adminBody = $technicianId
            ? "تم إنشاء المهمة «{$title}» وتم تعيين فني لها."
            : "تم إنشاء المهمة «{$title}» وهي في انتظار تعيين فني.";
        _notifyAdminsAndSupervisors('مهمة جديدة في النظام', $adminBody, 'task', $taskId, 'task');
    } catch (\Throwable $e) {
        error_log('[FCM] tasks.create notify admins: ' . $e->getMessage());
    }

    return ['id' => $taskId];
}

// ─── tasks.update ──────────────────────────────────────────────
function tasks_update($input, $ctx) {
    global $db;
    $id = (int)($input['id'] ?? 0);
    if (!$id) throw new Exception('Task ID required');

    // Check previous status before updating (نحتاج مواعيد سابقة لمقارنة الترحيل)
    $prevStmt = $db->prepare('SELECT status, technician_id, amount, title, scheduled_at, estimated_arrival_at FROM tasks WHERE id = ?');
    $prevStmt->execute([$id]);
    $prevTask = $prevStmt->fetch();
    $prevStatus = $prevTask ? $prevTask['status'] : null;

    $fields = [];
    $params = [];
    $map = [
        'title' => 'title', 'status' => 'status', 'collectionType' => 'collection_type',
        'amount' => 'amount', 'notes' => 'notes', 'scheduledAt' => 'scheduled_at',
        'estimatedArrivalAt' => 'estimated_arrival_at', 'customerId' => 'customer_id',
        'technicianId' => 'technician_id',
    ];
    foreach ($map as $jsKey => $dbCol) {
        if (array_key_exists($jsKey, $input)) {
            $fields[] = "$dbCol = ?";
            $params[] = $input[$jsKey];
        }
    }
    if (!empty($fields)) {
        $params[] = $id;
        $db->prepare('UPDATE tasks SET ' . implode(', ', $fields) . ' WHERE id = ?')->execute($params);
        if (array_key_exists('status', $input)) {
            $st = (string) ($input['status'] ?? '');
            if ($st === 'completed' || $st === 'cancelled') {
                try {
                    _ensureTaskOverdueNotifyColumn();
                    $db->prepare('UPDATE tasks SET overdue_last_notified_at = NULL WHERE id = ?')->execute([$id]);
                } catch (\Exception $e) { /* ignore */ }
                if ($st === 'completed') {
                    try {
                        _ensureTaskCompletedAtColumn();
                        $db->prepare('UPDATE tasks SET completed_at = NOW() WHERE id = ? AND completed_at IS NULL')->execute([$id]);
                    } catch (\Exception $e) { /* ignore */ }
                }
            }
        }
    }

    // إشعار الفني عند تغيير تاريخ/وقت المهمة (ترحيل)
    try {
        if ($prevTask && !empty($prevTask['technician_id'])) {
            $techId = (int)$prevTask['technician_id'];
            $taskTitle = $prevTask['title'] ?? 'مهمة';
            $schedChanged = false;
            $estChanged = false;
            if (array_key_exists('scheduledAt', $input)) {
                $tOld = !empty($prevTask['scheduled_at']) ? strtotime((string)$prevTask['scheduled_at']) : null;
                $tNew = ($input['scheduledAt'] !== null && $input['scheduledAt'] !== '')
                    ? strtotime((string)$input['scheduledAt']) : null;
                if ($tNew !== false && $tNew !== null && $tOld !== $tNew) {
                    $schedChanged = true;
                }
            }
            if (array_key_exists('estimatedArrivalAt', $input)) {
                $tOld = !empty($prevTask['estimated_arrival_at']) ? strtotime((string)$prevTask['estimated_arrival_at']) : null;
                $tNew = ($input['estimatedArrivalAt'] !== null && $input['estimatedArrivalAt'] !== '')
                    ? strtotime((string)$input['estimatedArrivalAt']) : null;
                if ($tNew !== false && $tNew !== null && $tOld !== $tNew) {
                    $estChanged = true;
                }
            }
            if ($schedChanged || $estChanged) {
                _notifyUser(
                    $techId,
                    'تم ترحيل موعد المهمة',
                    "تم تحديد موعد جديد لمهمة: {$taskTitle}. راجع التفاصيل في التطبيق.",
                    'task',
                    $id,
                    'task'
                );
                try {
                    _ensureTaskOverdueNotifyColumn();
                    $db->prepare('UPDATE tasks SET overdue_last_notified_at = NULL WHERE id = ?')->execute([$id]);
                } catch (\Exception $e) { /* ignore */ }
            }
        }
    } catch (\Exception $e) { /* ignore */ }

    if (isset($input['items']) && is_array($input['items'])) {
        $db->prepare('DELETE FROM task_items WHERE task_id = ?')->execute([$id]);
        $ins = $db->prepare('INSERT INTO task_items (task_id, description, is_completed) VALUES (?, ?, 0)');
        foreach ($input['items'] as $desc) {
            $ins->execute([$id, $desc]);
        }
    }

    // ── Notification triggers ──
    try {
        $taskTitle = $input['title'] ?? $prevTask['title'] ?? 'مهمة';
        $newStatus = $input['status'] ?? null;

        // Notify technician if newly assigned
        if (isset($input['technicianId']) && $input['technicianId'] && $input['technicianId'] != ($prevTask['technician_id'] ?? 0)) {
            _notifyUser((int)$input['technicianId'], 'مهمة جديدة', "تم تعيينك لمهمة: {$taskTitle}", 'task', $id, 'task');
        }

        // Notify admins on status change
        if ($newStatus && $newStatus !== $prevStatus) {
            $statusLabels = ['in_progress' => 'جاري العمل', 'completed' => 'مكتملة', 'cancelled' => 'ملغاة', 'pending' => 'معلقة'];
            $label = $statusLabels[$newStatus] ?? $newStatus;
            _notifyAdminsAndSupervisors("تحديث مهمة", "المهمة \"{$taskTitle}\" أصبحت: {$label}", 'task', $id, 'task');
        }
    } catch (\Exception $e) { /* ignore */ }

    // Auto-create accounting transaction on task completion
    if ($newStatus === 'completed' && $prevStatus !== 'completed' && $prevTask) {
        $techId = (int)($input['technicianId'] ?? $prevTask['technician_id'] ?? 0);
        $amount = (float)($input['amount'] ?? $prevTask['amount'] ?? 0);
        $taskTitle = $input['title'] ?? $prevTask['title'] ?? '';

        if ($techId > 0 && $amount > 0) {
            require_once __DIR__ . '/accounting_procedures.php';
            _ensureAccountingSchema();

            // Check if collection already exists for this task
            $chk = $db->prepare("SELECT id FROM acc_transactions WHERE task_id = ? AND type = 'collection'");
            $chk->execute([$id]);
            if (!$chk->fetch()) {
                $db->prepare("INSERT INTO acc_transactions
                    (type, technician_id, task_id, amount, description, status, approved_by, approved_at, created_by)
                    VALUES ('collection', ?, ?, ?, ?, 'approved', ?, NOW(), ?)")
                   ->execute([
                       $techId, $id, $amount,
                       "تحصيل من مهمة: $taskTitle",
                       $ctx['userId'], $ctx['userId']
                   ]);
            }
        }
    }

    return ['success' => true];
}

// ─── tasks.updateItem ──────────────────────────────────────────
function tasks_updateItem($input, $ctx) {
    global $db;
    _ensureItemProgressColumns();
    $id = (int)($input['id'] ?? 0);

    $fields = [];
    $params = [];

    if (array_key_exists('isCompleted', $input)) {
        $fields[] = 'is_completed = ?';
        $params[] = $input['isCompleted'] ? 1 : 0;
    }
    if (array_key_exists('progress', $input)) {
        $progress = max(0, min(100, (int)$input['progress']));
        $fields[] = 'progress = ?';
        $params[] = $progress;
        if ($progress >= 100) {
            $fields[] = 'is_completed = 1';
        }
    }
    if (array_key_exists('progressNote', $input)) {
        $fields[] = 'progress_note = ?';
        $params[] = $input['progressNote'];
    }

    if (!empty($fields)) {
        $params[] = $id;
        $db->prepare('UPDATE task_items SET ' . implode(', ', $fields) . ' WHERE id = ?')->execute($params);
    }

    // Notify admins about progress update
    try {
        $progress = isset($input['progress']) ? (int)$input['progress'] : null;
        if ($progress !== null) {
            $itemStmt = $db->prepare("SELECT ti.description, ti.task_id, t.title as task_title
                FROM task_items ti JOIN tasks t ON t.id = ti.task_id WHERE ti.id = ?");
            $itemStmt->execute([$id]);
            $item = $itemStmt->fetch();
            if ($item) {
                $techName = '';
                if ($ctx['userId']) {
                    $uStmt = $db->prepare("SELECT name FROM users WHERE id = ?");
                    $uStmt->execute([$ctx['userId']]);
                    $techName = $uStmt->fetchColumn() ?: '';
                }
                $msg = $techName ? "{$techName} أنجز {$progress}%" : "تم إنجاز {$progress}%";
                $msg .= " من: {$item['description']}";
                if ($input['progressNote'] ?? '') {
                    $msg .= " - {$input['progressNote']}";
                }
                _notifyAdminsAndSupervisors("تقدم في مهمة", $msg, 'task', (int)$item['task_id'], 'task');
            }
        }
    } catch (\Exception $e) { /* ignore */ }

    return ['success' => true];
}

// ─── tasks.addItemMedia ────────────────────────────────────────
function tasks_addItemMedia($input, $ctx) {
    global $db;
    $itemId = (int)($input['itemId'] ?? 0);
    $url = $input['url'] ?? '';
    $type = $input['type'] ?? 'image';

    $stmt = $db->prepare('SELECT media_urls, media_types FROM task_items WHERE id = ?');
    $stmt->execute([$itemId]);
    $row = $stmt->fetch();
    if (!$row) throw new Exception('Item not found');

    $urls = $row['media_urls'] ? json_decode($row['media_urls'], true) : [];
    $types = $row['media_types'] ? json_decode($row['media_types'], true) : [];
    $urls[] = $url;
    $types[] = $type;

    $db->prepare('UPDATE task_items SET media_urls = ?, media_types = ? WHERE id = ?')
       ->execute([json_encode($urls), json_encode($types), $itemId]);
    return ['success' => true];
}

// ─── tasks.removeItemMedia ─────────────────────────────────────
function tasks_removeItemMedia($input, $ctx) {
    global $db;
    $itemId = (int)($input['itemId'] ?? 0);
    $index = (int)($input['index'] ?? -1);

    $stmt = $db->prepare('SELECT media_urls, media_types FROM task_items WHERE id = ?');
    $stmt->execute([$itemId]);
    $row = $stmt->fetch();
    if (!$row) throw new Exception('Item not found');

    $urls = $row['media_urls'] ? json_decode($row['media_urls'], true) : [];
    $types = $row['media_types'] ? json_decode($row['media_types'], true) : [];

    if ($index >= 0 && $index < count($urls)) {
        array_splice($urls, $index, 1);
        array_splice($types, $index, 1);
    }

    $db->prepare('UPDATE task_items SET media_urls = ?, media_types = ? WHERE id = ?')
       ->execute([json_encode($urls), json_encode($types), $itemId]);
    return ['success' => true];
}

// ─── clients.list (for task creation dropdown) ─────────────────
function clients_list($ctx) {
    global $db;
    $rows = $db->query("SELECT id, name, phone FROM users WHERE role = 'user' ORDER BY name ASC")->fetchAll();
    $result = [];
    foreach ($rows as $r) {
        $result[] = ['id' => (int)$r['id'], 'name' => $r['name'] ?? '', 'phone' => $r['phone'] ?? ''];
    }
    return $result;
}

// ─── clients.staff (technicians dropdown) ──────────────────────
function clients_staff($ctx) {
    global $db;
    $rows = $db->query("SELECT id, name FROM users WHERE role IN ('technician','admin') ORDER BY name ASC")->fetchAll();
    $result = [];
    foreach ($rows as $r) {
        $result[] = ['id' => (int)$r['id'], 'name' => $r['name'] ?? ''];
    }
    return $result;
}

// ─── taskNotes ─────────────────────────────────────────────────
function _ensureTaskNotesTable() {
    global $db;
    $db->exec('CREATE TABLE IF NOT EXISTS task_notes (
        id INT AUTO_INCREMENT PRIMARY KEY,
        task_id INT NOT NULL,
        author_id INT NULL,
        content TEXT,
        media_urls LONGTEXT NULL,
        media_types LONGTEXT NULL,
        is_visible_to_client TINYINT(1) DEFAULT 1,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_task (task_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4');
}

function taskNotes_list($input, $ctx) {
    global $db;
    _ensureTaskNotesTable();
    $taskId = (int)($input['taskId'] ?? 0);
    $stmt = $db->prepare('
        SELECT n.*, u.name AS author_name, u.role AS author_role
        FROM task_notes n
        LEFT JOIN users u ON u.id = n.author_id
        WHERE n.task_id = ?
        ORDER BY n.created_at ASC
    ');
    $stmt->execute([$taskId]);
    $rows = $stmt->fetchAll();
    $result = [];
    foreach ($rows as $r) {
        $result[] = [
            'id' => (int)$r['id'],
            'authorId' => $r['author_id'] ? (int)$r['author_id'] : null,
            'authorName' => $r['author_name'] ?? null,
            'authorRole' => $r['author_role'] ?? null,
            'content' => $r['content'] ?? '',
            'mediaUrls' => $r['media_urls'] ? json_decode($r['media_urls'], true) : [],
            'mediaTypes' => $r['media_types'] ? json_decode($r['media_types'], true) : [],
            'isVisibleToClient' => (bool)($r['is_visible_to_client'] ?? true),
            'createdAt' => $r['created_at'] ?? '',
        ];
    }
    return $result;
}

function taskNotes_listForClient($input, $ctx) {
    global $db;
    _ensureTaskNotesTable();
    $taskId = (int)($input['taskId'] ?? 0);
    $stmt = $db->prepare('
        SELECT n.*, u.name AS author_name
        FROM task_notes n
        LEFT JOIN users u ON u.id = n.author_id
        WHERE n.task_id = ? AND n.is_visible_to_client = 1
        ORDER BY n.created_at ASC
    ');
    $stmt->execute([$taskId]);
    $rows = $stmt->fetchAll();
    $result = [];
    foreach ($rows as $r) {
        $result[] = [
            'id' => (int)$r['id'],
            'content' => $r['content'] ?? '',
            'authorName' => $r['author_name'] ?? null,
            'mediaUrls' => $r['media_urls'] ? json_decode($r['media_urls'], true) : [],
            'mediaTypes' => $r['media_types'] ? json_decode($r['media_types'], true) : [],
            'createdAt' => $r['created_at'] ? strtotime($r['created_at']) * 1000 : null,
        ];
    }
    return $result;
}

function taskNotes_create($input, $ctx) {
    global $db;
    _ensureTaskNotesTable();
    $taskId = (int)($input['taskId'] ?? 0);
    $content = $input['content'] ?? '';
    $mediaUrls = isset($input['mediaUrls']) ? json_encode($input['mediaUrls']) : null;
    $mediaTypes = isset($input['mediaTypes']) ? json_encode($input['mediaTypes']) : null;
    $visible = ($input['isVisibleToClient'] ?? true) ? 1 : 0;
    $authorId = $ctx['userId'] ?? null;

    $stmt = $db->prepare('INSERT INTO task_notes (task_id, author_id, content, media_urls, media_types, is_visible_to_client) VALUES (?, ?, ?, ?, ?, ?)');
    $stmt->execute([$taskId, $authorId, $content, $mediaUrls, $mediaTypes, $visible]);
    $noteId = (int)$db->lastInsertId();

    try {
        $techName = '';
        if ($authorId) {
            $uStmt = $db->prepare("SELECT name, role FROM users WHERE id = ?");
            $uStmt->execute([$authorId]);
            $uRow = $uStmt->fetch();
            $techName = $uRow['name'] ?? '';
            $role = $uRow['role'] ?? '';
        }
        $taskStmt = $db->prepare("SELECT title, technician_id FROM tasks WHERE id = ?");
        $taskStmt->execute([$taskId]);
        $task = $taskStmt->fetch();
        $taskTitle = $task['title'] ?? 'مهمة';

        if (isset($role) && $role === 'technician') {
            _notifyAdminsAndSupervisors('ملاحظة جديدة', "{$techName} أضاف ملاحظة على: {$taskTitle}", 'task', $taskId, 'task');
        } elseif ($task && $task['technician_id']) {
            _notifyUser((int)$task['technician_id'], 'ملاحظة على مهمتك', "تم إضافة ملاحظة على: {$taskTitle}", 'task', $taskId, 'task');
        }
    } catch (\Exception $e) { /* ignore */ }

    return ['id' => $noteId];
}

function taskNotes_delete($input, $ctx) {
    global $db;
    _ensureTaskNotesTable();
    $id = (int)($input['id'] ?? 0);
    $db->prepare('DELETE FROM task_notes WHERE id = ?')->execute([$id]);
    return ['success' => true];
}

// ─── taskItemMessages (محادثة تعليقات التقدم لكل بند) ───────────

function _ensureTaskItemMessagesTable() {
    global $db;
    $db->exec('CREATE TABLE IF NOT EXISTS task_item_messages (
        id INT AUTO_INCREMENT PRIMARY KEY,
        task_item_id INT NOT NULL,
        author_id INT NOT NULL,
        body TEXT NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_task_item_messages_item (task_item_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4');
}

function _taskAccessForTaskId($db, $taskId, $userId) {
    if (!$taskId || !$userId) {
        return null;
    }
    $stmt = $db->prepare('SELECT technician_id FROM tasks WHERE id = ?');
    $stmt->execute([$taskId]);
    $t = $stmt->fetch();
    if (!$t) {
        return null;
    }
    $stmt = $db->prepare('SELECT role FROM users WHERE id = ?');
    $stmt->execute([$userId]);
    $role = $stmt->fetchColumn();
    if (!$role) {
        return null;
    }
    $techId = !empty($t['technician_id']) ? (int)$t['technician_id'] : null;
    $ok = in_array($role, ['admin', 'staff'], true)
        || ($role === 'technician' && $techId && (int)$userId === $techId);
    if (!$ok) {
        return null;
    }
    return ['technicianId' => $techId, 'role' => $role];
}

function _taskAccessForItemId($db, $itemId, $userId) {
    $stmt = $db->prepare('SELECT task_id FROM task_items WHERE id = ?');
    $stmt->execute([$itemId]);
    $row = $stmt->fetch();
    if (!$row) {
        return null;
    }
    return _taskAccessForTaskId($db, (int)$row['task_id'], $userId);
}

function taskItemMessages_listByTask($input, $ctx) {
    global $db;
    _ensureTaskItemMessagesTable();
    $taskId = (int)($input['taskId'] ?? 0);
    $userId = $ctx['userId'] ?? null;
    if (!_taskAccessForTaskId($db, $taskId, $userId)) {
        throw new Exception('غير مصرح بعرض محادثة البنود');
    }

    $stmt = $db->prepare('
        SELECT m.id, m.task_item_id, m.author_id, m.body, m.created_at,
               u.name AS author_name, u.role AS author_role
        FROM task_item_messages m
        INNER JOIN task_items ti ON ti.id = m.task_item_id
        LEFT JOIN users u ON u.id = m.author_id
        WHERE ti.task_id = ?
        ORDER BY m.created_at ASC
    ');
    $stmt->execute([$taskId]);
    $rows = $stmt->fetchAll();

    $byItem = [];
    foreach ($rows as $r) {
        $iid = (int)$r['task_item_id'];
        if (!isset($byItem[$iid])) {
            $byItem[$iid] = [];
        }
        $byItem[$iid][] = [
            'id' => (int)$r['id'],
            'itemId' => $iid,
            'authorId' => (int)$r['author_id'],
            'authorName' => $r['author_name'] ?? '',
            'authorRole' => $r['author_role'] ?? '',
            'body' => $r['body'] ?? '',
            'createdAt' => $r['created_at'] ?? '',
        ];
    }

    $legacyStmt = $db->prepare('SELECT id, progress_note FROM task_items WHERE task_id = ?');
    $legacyStmt->execute([$taskId]);
    $legacyByItem = [];
    foreach ($legacyStmt->fetchAll() as $row) {
        $pn = trim((string)($row['progress_note'] ?? ''));
        if ($pn !== '') {
            $legacyByItem[(int)$row['id']] = $pn;
        }
    }

    return ['byItem' => $byItem, 'legacyByItem' => $legacyByItem];
}

function taskItemMessages_add($input, $ctx) {
    global $db;
    _ensureTaskItemMessagesTable();
    $itemId = (int)($input['itemId'] ?? 0);
    $body = trim((string)($input['body'] ?? ''));
    $userId = (int)($ctx['userId'] ?? 0);
    if ($itemId <= 0 || $body === '' || !$userId) {
        throw new Exception('بيانات الرسالة غير كافية');
    }
    $acc = _taskAccessForItemId($db, $itemId, $userId);
    if (!$acc) {
        throw new Exception('غير مصرح بإرسال رسالة على هذا البند');
    }

    $stmt = $db->prepare('INSERT INTO task_item_messages (task_item_id, author_id, body) VALUES (?, ?, ?)');
    $stmt->execute([$itemId, $userId, $body]);

    try {
        $stmt = $db->prepare("SELECT ti.description, t.id AS task_id, t.title AS task_title, t.technician_id
            FROM task_items ti JOIN tasks t ON t.id = ti.task_id WHERE ti.id = ?");
        $stmt->execute([$itemId]);
        $row = $stmt->fetch();
        if ($row) {
            $uStmt = $db->prepare('SELECT name, role FROM users WHERE id = ?');
            $uStmt->execute([$userId]);
            $u = $uStmt->fetch();
            $name = $u['name'] ?? '';
            $role = $u['role'] ?? '';
            $taskId = (int)$row['task_id'];
            $snippet = mb_strlen($body) > 120 ? mb_substr($body, 0, 120) . '…' : $body;
            if ($role === 'technician') {
                _notifyAdminsAndSupervisors(
                    'تعليق على بند مهمة',
                    "{$name}: {$snippet}",
                    'task',
                    $taskId,
                    'task'
                );
            } elseif (!empty($row['technician_id'])) {
                _notifyUser(
                    (int)$row['technician_id'],
                    'رد على تعليقك',
                    "{$name}: {$snippet}",
                    'task',
                    $taskId,
                    'task'
                );
            }
        }
    } catch (\Exception $e) { /* ignore */ }

    return ['success' => true];
}

// ─── technicianLocation.update ─────────────────────────────────
function technicianLocation_update($input, $ctx) {
    global $db;

    $lat = $input['latitude'] ?? null;
    $lng = $input['longitude'] ?? null;
    $taskId = $input['taskId'] ?? null;
    $arrived = $input['arrived'] ?? false;

    // Notify admins when technician arrives at location
    if ($arrived && $taskId) {
        try {
            $techName = '';
            if ($ctx['userId']) {
                $uStmt = $db->prepare("SELECT name FROM users WHERE id = ?");
                $uStmt->execute([$ctx['userId']]);
                $techName = $uStmt->fetchColumn() ?: 'الفني';
            }
            $taskStmt = $db->prepare("SELECT title FROM tasks WHERE id = ?");
            $taskStmt->execute([(int)$taskId]);
            $taskTitle = $taskStmt->fetchColumn() ?: 'مهمة';

            _notifyAdminsAndSupervisors(
                'وصول فني',
                "{$techName} وصل لموقع المهمة: {$taskTitle}",
                'task', (int)$taskId, 'task'
            );
        } catch (\Exception $e) { /* ignore */ }
    }

    return ['success' => true];
}

// ─── Quotations ────────────────────────────────────────────────
function _ensureQuotationsTable() {
    global $db;
    $db->exec('CREATE TABLE IF NOT EXISTS quotations (
        id INT AUTO_INCREMENT PRIMARY KEY,
        ref_number VARCHAR(50) NULL,
        created_by INT NULL,
        client_user_id INT NULL,
        client_name VARCHAR(255) NULL,
        client_email VARCHAR(255) NULL,
        client_phone VARCHAR(50) NULL,
        items LONGTEXT,
        subtotal DECIMAL(12,2) DEFAULT 0,
        installation_percent DECIMAL(5,2) DEFAULT 0,
        installation_amount DECIMAL(12,2) DEFAULT 0,
        total_amount DECIMAL(12,2) DEFAULT 0,
        status VARCHAR(50) DEFAULT "draft",
        notes TEXT,
        client_note TEXT NULL,
        pdf_url TEXT NULL,
        sent_at DATETIME NULL,
        purchase_request_status VARCHAR(30) DEFAULT "none",
        purchase_items LONGTEXT NULL,
        purchase_total_amount DECIMAL(12,2) DEFAULT 0,
        purchase_accepted_at DATETIME NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_client (client_user_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4');
    // migrate old table if needed
    try { $db->exec('ALTER TABLE quotations ADD COLUMN IF NOT EXISTS ref_number VARCHAR(50) NULL'); } catch(\Exception $e) {}
    try { $db->exec('ALTER TABLE quotations ADD COLUMN IF NOT EXISTS created_by INT NULL'); } catch(\Exception $e) {}
    try { $db->exec('ALTER TABLE quotations ADD COLUMN IF NOT EXISTS client_user_id INT NULL'); } catch(\Exception $e) {}
    try { $db->exec('ALTER TABLE quotations ADD COLUMN IF NOT EXISTS client_name VARCHAR(255) NULL'); } catch(\Exception $e) {}
    try { $db->exec('ALTER TABLE quotations ADD COLUMN IF NOT EXISTS client_email VARCHAR(255) NULL'); } catch(\Exception $e) {}
    try { $db->exec('ALTER TABLE quotations ADD COLUMN IF NOT EXISTS client_phone VARCHAR(50) NULL'); } catch(\Exception $e) {}
    try { $db->exec('ALTER TABLE quotations ADD COLUMN IF NOT EXISTS subtotal DECIMAL(12,2) DEFAULT 0'); } catch(\Exception $e) {}
    try { $db->exec('ALTER TABLE quotations ADD COLUMN IF NOT EXISTS installation_percent DECIMAL(5,2) DEFAULT 0'); } catch(\Exception $e) {}
    try { $db->exec('ALTER TABLE quotations ADD COLUMN IF NOT EXISTS installation_amount DECIMAL(12,2) DEFAULT 0'); } catch(\Exception $e) {}
    try { $db->exec('ALTER TABLE quotations ADD COLUMN IF NOT EXISTS total_amount DECIMAL(12,2) DEFAULT 0'); } catch(\Exception $e) {}
    try { $db->exec('ALTER TABLE quotations ADD COLUMN IF NOT EXISTS client_note TEXT NULL'); } catch(\Exception $e) {}
    try { $db->exec('ALTER TABLE quotations ADD COLUMN IF NOT EXISTS sent_at DATETIME NULL'); } catch(\Exception $e) {}
    try { $db->exec('ALTER TABLE quotations ADD COLUMN IF NOT EXISTS purchase_request_status VARCHAR(30) DEFAULT "none"'); } catch(\Exception $e) {}
    try { $db->exec('ALTER TABLE quotations ADD COLUMN IF NOT EXISTS purchase_items LONGTEXT NULL'); } catch(\Exception $e) {}
    try { $db->exec('ALTER TABLE quotations ADD COLUMN IF NOT EXISTS purchase_total_amount DECIMAL(12,2) DEFAULT 0'); } catch(\Exception $e) {}
    try { $db->exec('ALTER TABLE quotations ADD COLUMN IF NOT EXISTS purchase_accepted_at DATETIME NULL'); } catch(\Exception $e) {}
}

function quotations_list($ctx) {
    global $db;
    _ensureQuotationsTable();
    $rows = $db->query('SELECT * FROM quotations ORDER BY created_at DESC')->fetchAll();
    $result = [];
    foreach ($rows as $r) {
        $result[] = _formatQuotation($r);
    }
    return $result;
}

function quotations_create($input, $ctx) {
    global $db;
    _ensureQuotationsTable();

    $createdBy = isset($ctx['userId']) ? (int)$ctx['userId'] : null;
    $clientUserId = isset($input['clientUserId']) ? (int)$input['clientUserId'] : null;
    $clientName = $input['clientName'] ?? null;
    $clientEmail = $input['clientEmail'] ?? null;
    $clientPhone = $input['clientPhone'] ?? null;
    $notes = $input['notes'] ?? null;
    $installPct = (float)($input['installationPercent'] ?? 0);
    $discountPct = (float)($input['discountPercent'] ?? 0);
    $discountFixedInput = (float)($input['discountAmount'] ?? 0);

    $items = $input['items'] ?? [];
    $subtotal = 0;
    foreach ($items as &$item) {
        $qty = (int)($item['quantity'] ?? $item['qty'] ?? 1);
        $unitPrice = (float)($item['unitPrice'] ?? 0);
        $item['qty'] = $qty;
        $item['totalPrice'] = $unitPrice * $qty;
        $subtotal += $item['totalPrice'];
    }
    unset($item);

    $installAmt = $installPct > 0 ? $subtotal * $installPct / 100.0 : 0;
    $discountAmt = $discountPct > 0 ? $subtotal * $discountPct / 100.0 : $discountFixedInput;
    $totalAmt = $subtotal + $installAmt - $discountAmt;
    if ($totalAmt < 0) $totalAmt = 0;

    $year = date('Y');
    $cnt = $db->query("SELECT COUNT(*) FROM quotations WHERE YEAR(created_at) = $year")->fetchColumn();
    $refNumber = 'QT-' . $year . '-' . str_pad($cnt + 1, 4, '0', STR_PAD_LEFT);

    // Ensure discount columns exist
    try { $db->exec('ALTER TABLE quotations ADD COLUMN discount_percent DECIMAL(10,2) DEFAULT 0'); } catch (\Exception $e) {}
    try { $db->exec('ALTER TABLE quotations ADD COLUMN discount_amount DECIMAL(10,2) DEFAULT 0'); } catch (\Exception $e) {}

    $stmt = $db->prepare('INSERT INTO quotations (ref_number, created_by, client_user_id, client_name, client_email, client_phone, items, subtotal, installation_percent, installation_amount, discount_percent, discount_amount, total_amount, notes) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)');
    $stmt->execute([$refNumber, $createdBy, $clientUserId, $clientName, $clientEmail, $clientPhone, json_encode($items), $subtotal, $installPct, $installAmt, $discountPct, $discountAmt, $totalAmt, $notes]);
    return ['id' => (int)$db->lastInsertId()];
}

function quotations_getById($input, $ctx) {
    global $db;
    _ensureQuotationsTable();
    $id = (int)($input['id'] ?? 0);
    $stmt = $db->prepare('SELECT * FROM quotations WHERE id = ?');
    $stmt->execute([$id]);
    $r = $stmt->fetch();
    if (!$r) throw new Exception('Quotation not found');
    return _formatQuotation($r);
}

function quotations_getByIdForClient($input, $ctx) {
    return quotations_getById($input, $ctx);
}

function quotations_myQuotations($ctx) {
    global $db;
    _ensureQuotationsTable();
    if (!$ctx['userId']) throw new Exception('UNAUTHORIZED');
    $stmt = $db->prepare('SELECT * FROM quotations WHERE client_user_id = ? ORDER BY created_at DESC');
    $stmt->execute([$ctx['userId']]);
    $result = [];
    foreach ($stmt->fetchAll() as $r) $result[] = _formatQuotation($r);
    return $result;
}

function quotations_myDealerQuotations($ctx) {
    global $db;
    _ensureQuotationsTable();
    if (!$ctx['userId']) throw new Exception('UNAUTHORIZED');
    $stmt = $db->prepare('SELECT * FROM quotations WHERE created_by = ? ORDER BY created_at DESC');
    $stmt->execute([$ctx['userId']]);
    $result = [];
    foreach ($stmt->fetchAll() as $r) $result[] = _formatQuotation($r);
    return $result;
}

function quotations_requestPurchase($input, $ctx) {
    global $db;
    _ensureQuotationsTable();

    $dealerId = isset($ctx['userId']) ? (int)$ctx['userId'] : 0;
    if ($dealerId <= 0) throw new Exception('UNAUTHORIZED');

    $id = (int)($input['id'] ?? 0);
    if ($id <= 0) throw new Exception('Invalid quotation id');

    $qStmt = $db->prepare('SELECT * FROM quotations WHERE id = ?');
    $qStmt->execute([$id]);
    $q = $qStmt->fetch();
    if (!$q) throw new Exception('Quotation not found');

    $createdBy = isset($q['created_by']) ? (int)$q['created_by'] : 0;
    if ($createdBy !== $dealerId) throw new Exception('FORBIDDEN');

    $items = $q['items'] ? json_decode($q['items'], true) : [];
    if (!is_array($items)) $items = [];

    // We'll compute dealer prices using the dealer-specific discount rule only,
    // applied on top of the "official" unitPrice currently stored in the quote.
    $purchaseItems = [];
    $purchaseTotal = 0.0;

    $prodStmt = $db->prepare('SELECT id, category_id, stock, price, original_price, main_image_url, images FROM products WHERE id = ?');

    foreach ($items as $item) {
        if (!is_array($item)) continue;

        $productId = (int)($item['productId'] ?? 0);
        $productName = $item['productName'] ?? null;
        $qty = (int)($item['quantity'] ?? $item['qty'] ?? 1);
        $officialUnitPrice = 0.0;

        $dealerUnitPrice = $officialUnitPrice;
        $appliedPercent = 0.0;
        $appliedAmount = 0.0;
        $waitingMessage = null;
        $imageUrl = null;

        if ($productId > 0) {
            $prodStmt->execute([$productId]);
            $pr = $prodStmt->fetch();

            if ($pr) {
                // Dealer purchase pricing must be based on the official product base price
                // (ignore quotation-level installation/discount that may affect item totals).
                $officialUnitPrice = (float)($pr['original_price'] ?? $pr['price'] ?? 0);
                // ImageUrl for dealer cart sync.
                $imageUrl = $pr['main_image_url'] ?? null;
                if (empty($imageUrl) && !empty($pr['images'])) {
                    $imgs = json_decode($pr['images'], true);
                    if (is_array($imgs) && count($imgs) > 0) $imageUrl = $imgs[0];
                }

                $rowForDiscount = [
                    'id' => $pr['id'],
                    'category_id' => $pr['category_id'] ?? null,
                    'stock' => $pr['stock'] ?? 0,
                ];

                $userRule = _applyUserDiscount($rowForDiscount, $ctx);
                $waitingMessage = $userRule['waitingMessage'] ?? null;
                $appliedPercent = (float)($userRule['percent'] ?? 0);
                $appliedAmount = (float)($userRule['amount'] ?? 0);

                if ($waitingMessage == null) {
                    // Convert percent rule to money based on the current official unit price.
                    $discountValue = 0.0;
                    if ($appliedPercent > 0) {
                        $discountValue = $officialUnitPrice * $appliedPercent / 100.0;
                    } elseif ($appliedAmount > 0) {
                        $discountValue = $appliedAmount;
                    }
                    $dealerUnitPrice = $officialUnitPrice - $discountValue;
                    if ($dealerUnitPrice < 0) $dealerUnitPrice = 0.0;
                    $appliedAmount = $discountValue; // store applied money discount
                }
            }
        }

        $dealerTotal = $dealerUnitPrice * $qty;
        $purchaseTotal += $dealerTotal;

        $purchaseItems[] = [
            'productId' => $productId,
            'productName' => $productName,
            'imageUrl' => $imageUrl,
            'qty' => $qty,
            'officialUnitPrice' => $officialUnitPrice,
            'dealerUnitPrice' => $dealerUnitPrice,
            'dealerTotalPrice' => $dealerTotal,
            'discountPercent' => $appliedPercent,
            'discountAmount' => $appliedAmount, // applied money discount
            'discountWaitingMessage' => $waitingMessage,
        ];
    }

    $db->prepare('UPDATE quotations
        SET purchase_request_status = ?, purchase_items = ?, purchase_total_amount = ?
        WHERE id = ?')
        ->execute([
            'requested',
            json_encode($purchaseItems, JSON_UNESCAPED_UNICODE),
            $purchaseTotal,
            $id
        ]);

    try {
        if (!function_exists('_notifyAdminsAndSupervisors')) {
            require_once __DIR__ . '/notifications_procedures.php';
        }
        $ref = $q['ref_number'] ?? ('QT-' . $id);
        $dealerStmt = $db->prepare('SELECT name FROM users WHERE id = ?');
        $dealerStmt->execute([$dealerId]);
        $dealerName = trim((string)($dealerStmt->fetchColumn() ?: ''));
        if ($dealerName === '') {
            $dealerName = 'تاجر';
        }
        _notifyAdminsAndSupervisors(
            'طلب شراء جديد من تاجر',
            "{$dealerName} أرسل طلب شراء لعرض السعر {$ref}. المجموع: {$purchaseTotal} ج.م",
            'quotation',
            $id,
            'quotation',
            ['purchaseRequest' => 'requested', 'quotationId' => (string)$id]
        );

        // إشعار للتاجر أنه في انتظار موافقة الإدارة
        _notifyUser(
            $dealerId,
            'في انتظار تأكيد الإدارة',
            "{$dealerName} أرسل طلب شراء لعرض السعر {$ref}. سيتم إشعارك عند تأكيد الإدارة.",
            'quotation',
            $id,
            'quotation',
            ['purchaseRequest' => 'requested', 'quotationId' => (string)$id]
        );

        // إشعار للعميل بوجود طلب شراء قيد المراجعة (إذا كان Client موجوداً)
        $clientUserId = isset($q['client_user_id']) ? (int)$q['client_user_id'] : 0;
        if ($clientUserId > 0) {
            _notifyUser(
                (int)$clientUserId,
                'طلب شراء قيد المراجعة',
                "تم إرسال طلب شراء لعرض السعر {$ref} من تاجر. سيتم إشعارك عند تحديث الحالة.",
                'quotation',
                $id,
                'quotation',
                ['purchaseRequest' => 'requested', 'quotationId' => (string)$id]
            );
        }
    } catch (\Throwable $e) {
        error_log('[FCM] quotations.requestPurchase notify admins: ' . $e->getMessage());
    }

    return ['success' => true, 'purchaseTotalAmount' => $purchaseTotal];
}

function quotations_previewDealerPurchase($input, $ctx) {
    global $db;
    _ensureQuotationsTable();

    $dealerId = isset($ctx['userId']) ? (int)$ctx['userId'] : 0;
    if ($dealerId <= 0) throw new Exception('UNAUTHORIZED');

    $id = (int)($input['id'] ?? 0);
    if ($id <= 0) throw new Exception('Invalid quotation id');

    $qStmt = $db->prepare('SELECT * FROM quotations WHERE id = ?');
    $qStmt->execute([$id]);
    $q = $qStmt->fetch();
    if (!$q) throw new Exception('Quotation not found');

    $createdBy = isset($q['created_by']) ? (int)$q['created_by'] : 0;
    if ($createdBy !== $dealerId) throw new Exception('FORBIDDEN');

    $items = $q['items'] ? json_decode($q['items'], true) : [];
    if (!is_array($items)) $items = [];

    $purchaseItems = [];
    $purchaseTotal = 0.0;

    $prodStmt = $db->prepare('SELECT id, category_id, stock, price, original_price, main_image_url, images FROM products WHERE id = ?');

    foreach ($items as $item) {
        if (!is_array($item)) continue;

        $productId = (int)($item['productId'] ?? 0);
        $productName = $item['productName'] ?? null;
        $qty = (int)($item['quantity'] ?? $item['qty'] ?? 1);
        $officialUnitPrice = 0.0;

        $dealerUnitPrice = $officialUnitPrice;
        $appliedPercent = 0.0;
        $appliedAmount = 0.0;
        $waitingMessage = null;
        $imageUrl = null;

        if ($productId > 0) {
            $prodStmt->execute([$productId]);
            $pr = $prodStmt->fetch();

            if ($pr) {
                // Dealer purchase pricing must be based on the official product base price.
                $officialUnitPrice = (float)($pr['original_price'] ?? $pr['price'] ?? 0);
                // ImageUrl for dealer cart sync.
                $imageUrl = $pr['main_image_url'] ?? null;
                if (empty($imageUrl) && !empty($pr['images'])) {
                    $imgs = json_decode($pr['images'], true);
                    if (is_array($imgs) && count($imgs) > 0) $imageUrl = $imgs[0];
                }

                $rowForDiscount = [
                    'id' => $pr['id'],
                    'category_id' => $pr['category_id'] ?? null,
                    'stock' => $pr['stock'] ?? 0,
                ];

                $userRule = _applyUserDiscount($rowForDiscount, $ctx);
                $waitingMessage = $userRule['waitingMessage'] ?? null;
                $appliedPercent = (float)($userRule['percent'] ?? 0);
                $appliedAmount = (float)($userRule['amount'] ?? 0);

                if ($waitingMessage == null) {
                    $discountValue = 0.0;
                    if ($appliedPercent > 0) {
                        $discountValue = $officialUnitPrice * $appliedPercent / 100.0;
                    } elseif ($appliedAmount > 0) {
                        $discountValue = $appliedAmount;
                    }
                    $dealerUnitPrice = $officialUnitPrice - $discountValue;
                    if ($dealerUnitPrice < 0) $dealerUnitPrice = 0.0;
                    $appliedAmount = $discountValue; // store applied money discount
                }
            }
        }

        $dealerTotal = $dealerUnitPrice * $qty;
        $purchaseTotal += $dealerTotal;

        $purchaseItems[] = [
            'productId' => $productId,
            'productName' => $productName,
            'imageUrl' => $imageUrl,
            'qty' => $qty,
            'officialUnitPrice' => $officialUnitPrice,
            'dealerUnitPrice' => $dealerUnitPrice,
            'dealerTotalPrice' => $dealerTotal,
            'discountPercent' => $appliedPercent,
            'discountAmount' => $appliedAmount,
            'discountWaitingMessage' => $waitingMessage,
        ];
    }

    return [
        'success' => true,
        'purchaseTotalAmount' => $purchaseTotal,
        'purchaseItems' => $purchaseItems,
    ];
}

function quotations_acceptPurchaseRequest($input, $ctx) {
    global $db;
    _ensureQuotationsTable();

    $adminId = isset($ctx['userId']) ? (int)$ctx['userId'] : 0;
    if ($adminId <= 0) throw new Exception('UNAUTHORIZED');

    $id = (int)($input['id'] ?? 0);
    if ($id <= 0) throw new Exception('Invalid quotation id');

    $qStmt = $db->prepare('SELECT * FROM quotations WHERE id = ?');
    $qStmt->execute([$id]);
    $q = $qStmt->fetch();
    if (!$q) throw new Exception('Quotation not found');

    $status = $q['purchase_request_status'] ?? 'none';
    $statusNorm = strtolower(trim((string)$status));
    if ($statusNorm !== 'requested' && $statusNorm !== 'accepted') {
        return ['success' => true];
    }

    // Basic admin check (by role from DB)
    $roleStmt = $db->prepare('SELECT role FROM users WHERE id = ?');
    $roleStmt->execute([$adminId]);
    $role = $roleStmt->fetchColumn();
    $role = $role ? strtolower(trim((string)$role)) : '';
    if (!in_array($role, ['admin', 'supervisor', 'staff'], true)) throw new Exception('FORBIDDEN');

    $dealerId = isset($q['created_by']) ? (int)$q['created_by'] : 0;

    // If purchase_items weren't stored during requestPurchase (or were empty),
    // compute them now using the dealer's discount rules so the dealer can sync cart.
    $purchaseItemsExisting = $q['purchase_items'] ?? null;
    $needComputeItems = true;
    if ($purchaseItemsExisting !== null) {
        try {
            $tmp = json_decode($purchaseItemsExisting, true);
            if (is_array($tmp) && count($tmp) > 0) {
                // Recompute if any item is missing imageUrl (older rows before this fix).
                $missingImage = false;
                foreach ($tmp as $it) {
                    if (!is_array($it)) continue;
                    $img = $it['imageUrl'] ?? null;
                    if ($img === null || $img === '') {
                        $missingImage = true;
                        break;
                    }
                }
                if (!$missingImage) $needComputeItems = false;
            }
        } catch (\Exception $e) { /* ignore */ }
    }

    // Always recompute on accept to ensure correct official base pricing
    // (independent from quotation-level installation/discount and from older stored payloads).
    $needComputeItems = true;

    $purchaseItems = null;
    $purchaseTotal = (float)($q['purchase_total_amount'] ?? 0);

    // If already accepted and we don't need to recompute (e.g. imageUrl missing isn't present),
    // just exit without changing anything.
    if ($statusNorm === 'accepted' && $needComputeItems === false) {
        return ['success' => true];
    }

    if ($needComputeItems) {
        $items = $q['items'] ? json_decode($q['items'], true) : [];
        if (!is_array($items)) $items = [];

        $purchaseItems = [];
        $purchaseTotal = 0.0;

        $prodStmt = $db->prepare('SELECT id, category_id, stock, price, original_price, main_image_url, images FROM products WHERE id = ?');

        foreach ($items as $item) {
            if (!is_array($item)) continue;

            $productId = (int)($item['productId'] ?? 0);
            $productName = $item['productName'] ?? null;
            $qty = (int)($item['quantity'] ?? $item['qty'] ?? 1);
            $officialUnitPrice = 0.0;

            $dealerUnitPrice = $officialUnitPrice;
            $appliedPercent = 0.0;
            $appliedAmount = 0.0;
            $waitingMessage = null;
            $imageUrl = null;

            if ($productId > 0) {
                $prodStmt->execute([$productId]);
                $pr = $prodStmt->fetch();

                if ($pr) {
                    // Official base must come from products table.
                    $officialUnitPrice = (float)($pr['original_price'] ?? $pr['price'] ?? 0);
                    // ImageUrl for dealer cart sync.
                    $imageUrl = $pr['main_image_url'] ?? null;
                    if (empty($imageUrl) && !empty($pr['images'])) {
                        $imgs = json_decode($pr['images'], true);
                        if (is_array($imgs) && count($imgs) > 0) $imageUrl = $imgs[0];
                    }

                    $rowForDiscount = [
                        'id' => $pr['id'],
                        'category_id' => $pr['category_id'] ?? null,
                        'stock' => $pr['stock'] ?? 0,
                    ];

                    // IMPORTANT: calculate using the dealer as ctx.userId
                    $dealerCtx = ['userId' => $dealerId];
                    $userRule = _applyUserDiscount($rowForDiscount, $dealerCtx);
                    $waitingMessage = $userRule['waitingMessage'] ?? null;
                    $appliedPercent = (float)($userRule['percent'] ?? 0);
                    $appliedAmount = (float)($userRule['amount'] ?? 0);

                    if ($waitingMessage == null) {
                        $discountValue = 0.0;
                        if ($appliedPercent > 0) {
                            $discountValue = $officialUnitPrice * $appliedPercent / 100.0;
                        } elseif ($appliedAmount > 0) {
                            $discountValue = $appliedAmount;
                        }
                        $dealerUnitPrice = $officialUnitPrice - $discountValue;
                        if ($dealerUnitPrice < 0) $dealerUnitPrice = 0.0;
                        $appliedAmount = $discountValue; // store applied money discount
                    }
                }
            }

            $dealerTotal = $dealerUnitPrice * $qty;
            $purchaseTotal += $dealerTotal;

            $purchaseItems[] = [
                'productId' => $productId,
                'productName' => $productName,
                'imageUrl' => $imageUrl,
                'qty' => $qty,
                'officialUnitPrice' => $officialUnitPrice,
                'dealerUnitPrice' => $dealerUnitPrice,
                'dealerTotalPrice' => $dealerTotal,
                'discountPercent' => $appliedPercent,
                'discountAmount' => $appliedAmount,
                'discountWaitingMessage' => $waitingMessage,
            ];
        }
    } else {
        // If items exist, use them for saving.
        try {
            $purchaseItems = json_decode($purchaseItemsExisting, true);
        } catch (\Exception $e) {
            $purchaseItems = null;
        }
    }

    $purchaseItemsJson = $purchaseItems !== null ? json_encode($purchaseItems, JSON_UNESCAPED_UNICODE) : ($q['purchase_items'] ?? '[]');

    $db->prepare("UPDATE quotations
        SET purchase_request_status = 'accepted',
            purchase_accepted_at = NOW(),
            purchase_items = ?,
            purchase_total_amount = ?
        WHERE id = ?")
        ->execute([
            $purchaseItemsJson,
            $purchaseTotal,
            $id
        ]);

    if ($dealerId > 0) {
        $ref = $q['ref_number'] ?? ('QT-' . $id);
        // $purchaseTotal has been re-computed above after re-building purchaseItems.
        _notifyUser(
            $dealerId,
            'تم تأكيد طلب الشراء',
            "تم قبول طلب الشراء لعرض السعر رقم {$ref}. المجموع: {$purchaseTotal} ج.م",
            'quotation',
            $id,
            'quotation',
            ['purchaseRequest' => 'accepted', 'quotationId' => (string)$id]
        );

        // إشعار للعميل عند تأكيد طلب الشراء
        $clientUserId = isset($q['client_user_id']) ? (int)$q['client_user_id'] : 0;
        if ($clientUserId > 0) {
            _notifyUser(
                (int)$clientUserId,
                'تم تأكيد طلب الشراء',
                "تم تأكيد طلب الشراء لعرض السعر رقم {$ref}.",
                'quotation',
                $id,
                'quotation',
                ['purchaseRequest' => 'accepted', 'quotationId' => (string)$id]
            );
        }
    }

    return ['success' => true];
}

function quotations_respond($input, $ctx) {
    global $db;
    _ensureQuotationsTable();
    $id = (int)($input['id'] ?? 0);
    $response = $input['response'] ?? '';
    $status = in_array($response, ['accepted','rejected']) ? $response : 'sent';
    $db->prepare('UPDATE quotations SET status = ?, client_note = ? WHERE id = ?')->execute([$status, $response, $id]);

    try {
        $qStmt = $db->prepare("SELECT ref_number, client_name FROM quotations WHERE id = ?");
        $qStmt->execute([$id]);
        $q = $qStmt->fetch();
        $ref = $q['ref_number'] ?? "#{$id}";
        $client = $q['client_name'] ?? 'عميل';
        $label = $status === 'accepted' ? 'قبل' : ($status === 'rejected' ? 'رفض' : 'رد على');
        _notifyAdminsAndSupervisors("رد على عرض سعر", "{$client} {$label} عرض السعر {$ref}", 'quotation', $id, 'quotation');
    } catch (\Exception $e) { /* ignore */ }

    return ['success' => true];
}

function quotations_generatePdf($input, $ctx) {
    global $db;
    _ensureQuotationsTable();
    $id = (int)($input['id'] ?? 0);
    $stmt = $db->prepare('SELECT * FROM quotations WHERE id = ?');
    $stmt->execute([$id]);
    $r = $stmt->fetch();
    if (!$r) throw new Exception('Quotation not found');
    return ['url' => $r['pdf_url'] ?? null, 'refNumber' => $r['ref_number'] ?? '', 'clientPhone' => $r['client_phone'] ?? ''];
}

function quotations_send($input, $ctx) {
    global $db;
    _ensureQuotationsTable();
    $id = (int)($input['id'] ?? 0);
    $db->prepare("UPDATE quotations SET status = 'sent', sent_at = NOW() WHERE id = ?")->execute([$id]);
    return ['success' => true];
}

function quotations_delete($input, $ctx) {
    global $db;
    _ensureQuotationsTable();
    $id = (int)($input['id'] ?? 0);
    $db->prepare('DELETE FROM quotations WHERE id = ?')->execute([$id]);
    return ['success' => true];
}

function _formatQuotation($r) {
    $items = $r['items'] ? json_decode($r['items'], true) : [];
    foreach ($items as &$item) {
        $qty = (int)($item['quantity'] ?? $item['qty'] ?? 1);
        $unitPrice = (float)($item['unitPrice'] ?? 0);
        $item['qty'] = $qty;
        if (!isset($item['totalPrice'])) $item['totalPrice'] = $unitPrice * $qty;
    }
    unset($item);

    return [
        'id' => (int)$r['id'],
        'refNumber' => $r['ref_number'] ?? ('QT-' . $r['id']),
        'createdBy' => isset($r['created_by']) && $r['created_by'] ? (int)$r['created_by'] : null,
        'clientUserId' => isset($r['client_user_id']) && $r['client_user_id'] ? (int)$r['client_user_id'] : null,
        'clientName' => $r['client_name'] ?? null,
        'clientEmail' => $r['client_email'] ?? null,
        'clientPhone' => $r['client_phone'] ?? null,
        'items' => $items,
        'subtotal' => (float)($r['subtotal'] ?? 0),
        'installationPercent' => (float)($r['installation_percent'] ?? 0),
        'installationAmount' => (float)($r['installation_amount'] ?? 0),
        'discountPercent' => (float)($r['discount_percent'] ?? 0),
        'discountAmount' => (float)($r['discount_amount'] ?? 0),
        'totalAmount' => (float)($r['total_amount'] ?? 0),
        'status' => $r['status'] ?? 'draft',
        'notes' => $r['notes'] ?? null,
        'clientNote' => $r['client_note'] ?? null,
        'pdfUrl' => $r['pdf_url'] ?? null,
        'purchaseRequestStatus' => $r['purchase_request_status'] ?? 'none',
        'purchaseItems' => $r['purchase_items'] ? json_decode($r['purchase_items'], true) : null,
        'purchaseTotalAmount' => (float)($r['purchase_total_amount'] ?? 0),
        'purchaseAcceptedAt' => isset($r['purchase_accepted_at']) && $r['purchase_accepted_at'] ? strtotime($r['purchase_accepted_at']) * 1000 : null,
        'createdAt' => isset($r['created_at']) ? strtotime($r['created_at']) * 1000 : null,
        'sentAt' => isset($r['sent_at']) && $r['sent_at'] ? strtotime($r['sent_at']) * 1000 : null,
    ];
}

// ─── Admin Dashboard Stats ───────────────────────────────────
// Used by: lib/screens/admin/admin_home_screen.dart + lib/screens/admin/admin_reports_screen.dart
function admin_getDashboardStats($input, $ctx) {
    global $db;

    $userId = (int)($ctx['userId'] ?? 0);
    if ($userId <= 0) {
        throw new Exception('UNAUTHORIZED');
    }

    // السماح لمن لديه reports.view أو لدور مسؤول
    $roleStmt = $db->prepare("SELECT role FROM users WHERE id = ?");
    $roleStmt->execute([$userId]);
    $role = $roleStmt->fetchColumn();
    $roleLower = $role ? strtolower(trim((string)$role)) : '';
    $allowedRoles = ['admin', 'staff', 'supervisor'];
    $hasRole = in_array($roleLower, $allowedRoles, true);
    $hasPerm = false;
    if (!$hasRole) {
        require_once __DIR__ . '/permissions_procedures.php';
        $permsRes = perm_getUserPermissions(['userId' => $userId], $ctx);
        $hasPerm = in_array('reports.view', $permsRes['permissions'] ?? [], true);
    }
    if (!$hasRole && !$hasPerm) {
        throw new Exception('FORBIDDEN');
    }

    // Orders table is needed by the mobile/clients flow too.
    try { _ensureOrdersTable(); } catch (\Exception $e) {}

    $totalOrders = 0;
    try {
        $totalOrders = (int)$db->query("SELECT COUNT(*) FROM orders")->fetchColumn();
    } catch (\Exception $e) {}

    $totalTasks = 0;
    $tasksCompleted = 0;
    $tasksActive = 0;
    $tasksCancelled = 0;
    try {
        $totalTasks = (int)$db->query("SELECT COUNT(*) FROM tasks")->fetchColumn();
        $tasksCompleted = (int)$db->query("SELECT COUNT(*) FROM tasks WHERE LOWER(TRIM(COALESCE(status,''))) = 'completed'")->fetchColumn();
        $tasksCancelled = (int)$db->query("SELECT COUNT(*) FROM tasks WHERE LOWER(TRIM(COALESCE(status,''))) = 'cancelled'")->fetchColumn();
        $tasksActive = (int)$db->query("SELECT COUNT(*) FROM tasks WHERE LOWER(TRIM(COALESCE(status,''))) NOT IN ('completed','cancelled')")->fetchColumn();
    } catch (\Exception $e) {}

    $ordersPending = 0;
    try {
        $ordersPending = (int)$db->query("SELECT COUNT(*) FROM orders WHERE LOWER(TRIM(COALESCE(status,''))) IN ('pending','processing','new','preparing')")->fetchColumn();
    } catch (\Exception $e) {}

    $totalProducts = 0;
    try {
        $totalProducts = (int)$db->query("SELECT COUNT(*) FROM products")->fetchColumn();
    } catch (\Exception $e) {}

    $totalCustomers = 0;
    try {
        $stmt = $db->query("SELECT COUNT(*) FROM users WHERE LOWER(role) IN ('user', 'client')");
        $totalCustomers = (int)$stmt->fetchColumn();
    } catch (\Exception $e) {}

    return [
        'totalOrders' => $totalOrders,
        'ordersPending' => $ordersPending,
        'totalCustomers' => $totalCustomers,
        'totalProducts' => $totalProducts,
        'totalTasks' => $totalTasks,
        'tasksCompleted' => $tasksCompleted,
        'tasksActive' => $tasksActive,
        'tasksCancelled' => $tasksCancelled,
    ];
}

// ─── Orders ────────────────────────────────────────────────────
function _ensureOrdersTable() {
    global $db;
    $db->exec('CREATE TABLE IF NOT EXISTS orders (
        id INT AUTO_INCREMENT PRIMARY KEY,
        user_id INT NULL,
        items LONGTEXT,
        total DECIMAL(12,2) DEFAULT 0,
        status VARCHAR(50) DEFAULT "pending",
        payment_method VARCHAR(30) DEFAULT "cash",
        payment_proof_url TEXT NULL,
        shipping_address TEXT NULL,
        notes TEXT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_user (user_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4');
}

function orders_create($input, $ctx) {
    global $db;
    _ensureOrdersTable();
    $userId = $ctx['userId'] ?? null;
    $items = isset($input['items']) ? json_encode($input['items']) : '[]';
    // نحاول قراءة totalAmount أولاً لأنها المستخدمة من تطبيق العميل، ثم نرجع إلى total إن لم تكن موجودة
    $total = $input['totalAmount'] ?? ($input['total'] ?? 0);
    $address = $input['shippingAddress'] ?? null;
    $notes = $input['notes'] ?? null;
    $status = $input['status'] ?? 'pending';
    $paymentMethod = $input['paymentMethod'] ?? 'cash';
    $paymentProofUrl = $input['paymentProofUrl'] ?? null;

    // Ensure new columns exist for older deployments.
    try { $db->exec('ALTER TABLE orders ADD COLUMN IF NOT EXISTS payment_method VARCHAR(30) DEFAULT "cash"'); } catch (\Exception $e) {}
    try { $db->exec('ALTER TABLE orders ADD COLUMN IF NOT EXISTS payment_proof_url TEXT NULL'); } catch (\Exception $e) {}

    $stmt = $db->prepare('INSERT INTO orders (user_id, items, total, status, payment_method, payment_proof_url, shipping_address, notes) VALUES (?, ?, ?, ?, ?, ?, ?, ?)');
    $stmt->execute([$userId, $items, $total, $status, $paymentMethod, $paymentProofUrl, $address, $notes]);
    $orderId = (int)$db->lastInsertId();

    try {
        _notifyAdminsAndSupervisors('طلب جديد', "طلب جديد رقم #{$orderId} بقيمة {$total}", 'order', $orderId, 'order');
    } catch (\Exception $e) { /* ignore */ }

    return ['id' => $orderId];
}

function orders_getMyOrders($ctx) {
    global $db;
    _ensureOrdersTable();
    if (!$ctx['userId']) throw new Exception('UNAUTHORIZED');
    $stmt = $db->prepare('SELECT * FROM orders WHERE user_id = ? ORDER BY created_at DESC');
    $stmt->execute([$ctx['userId']]);
    $result = [];
    foreach ($stmt->fetchAll() as $r) {
        $result[] = [
            'id' => (int)$r['id'],
            'items' => $r['items'] ? json_decode($r['items'], true) : [],
            'total' => $r['total'] ?? 0,
            'status' => $r['status'] ?? 'pending',
            'paymentMethod' => $r['payment_method'] ?? 'cash',
            'paymentProofUrl' => $r['payment_proof_url'] ?? null,
            'shippingAddress' => $r['shipping_address'] ?? null,
            'notes' => $r['notes'] ?? null,
            'createdAt' => $r['created_at'] ? strtotime($r['created_at']) * 1000 : null,
        ];
    }
    return $result;
}

// ─── Admin Orders ──────────────────────────────────────────────
function admin_getAllOrders($input, $ctx) {
    global $db;
    _ensureOrdersTable();

    $userId = (int)($ctx['userId'] ?? 0);
    if ($userId <= 0) throw new Exception('UNAUTHORIZED');

    $roleStmt = $db->prepare("SELECT role FROM users WHERE id = ?");
    $roleStmt->execute([$userId]);
    $role = $roleStmt->fetchColumn();
    $roleLower = $role ? strtolower(trim((string)$role)) : '';
    if (!in_array($roleLower, ['admin', 'staff', 'supervisor'], true)) {
        throw new Exception('FORBIDDEN');
    }

    $stmt = $db->query("
        SELECT
            o.id,
            o.items,
            o.total,
            o.status,
            o.created_at,
            u.name AS customer_name,
            u.phone AS customer_phone,
            u.address AS customer_address
        FROM orders o
        LEFT JOIN users u ON u.id = o.user_id
        ORDER BY o.created_at DESC
    ");

    $result = [];
    foreach ($stmt->fetchAll() as $r) {
        $result[] = [
            'id' => (int)$r['id'],
            'items' => $r['items'] ? json_decode($r['items'], true) : [],
            // UI expects totalAmount key
            'totalAmount' => (float)($r['total'] ?? 0),
            'status' => $r['status'] ?? 'pending',
            'customerName' => $r['customer_name'] ?? null,
            'customerPhone' => $r['customer_phone'] ?? null,
            'customerAddress' => $r['customer_address'] ?? null,
            'createdAt' => $r['created_at'] ? strtotime($r['created_at']) * 1000 : null,
        ];
    }

    return $result;
}

function admin_updateOrderStatus($input, $ctx) {
    global $db;
    _ensureOrdersTable();

    $userId = (int)($ctx['userId'] ?? 0);
    if ($userId <= 0) throw new Exception('UNAUTHORIZED');

    $orderId = (int)($input['orderId'] ?? 0);
    $status = (string)($input['status'] ?? 'pending');
    if ($orderId <= 0) throw new Exception('INVALID_ARGUMENT');

    $roleStmt = $db->prepare("SELECT role FROM users WHERE id = ?");
    $roleStmt->execute([$userId]);
    $role = $roleStmt->fetchColumn();
    $roleLower = $role ? strtolower(trim((string)$role)) : '';
    if (!in_array($roleLower, ['admin', 'staff', 'supervisor'], true)) {
        throw new Exception('FORBIDDEN');
    }

    // Update status
    $upd = $db->prepare("UPDATE orders SET status = ? WHERE id = ?");
    $upd->execute([$status, $orderId]);

    // Notify order owner (if available)
    try {
        $stmt = $db->prepare("SELECT user_id FROM orders WHERE id = ?");
        $stmt->execute([$orderId]);
        $ownerId = $stmt->fetchColumn();
        if ($ownerId) {
            _notifyUser((int)$ownerId, 'تحديث حالة الطلب', "تم تحديث حالة الطلب #{$orderId} إلى: {$status}", 'order', $orderId, 'order', [
                'orderId' => $orderId,
                'status' => $status,
            ]);
        }
    } catch (\Exception $e) {
        // Optional, don't fail status update if notification fails
    }

    return ['success' => true];
}

// ─── Helper ────────────────────────────────────────────────────
function _formatTaskRow($r, $itemRows = []) {
    $totalProgress = 0;
    $itemCount = count($itemRows);
    foreach ($itemRows as $i) {
        $totalProgress += (int)($i['progress'] ?? ($i['is_completed'] ? 100 : 0));
    }
    $overallProgress = $itemCount > 0 ? round($totalProgress / $itemCount) : 0;

    return [
        'id' => (int)$r['id'],
        'title' => $r['title'] ?? '',
        'status' => $r['status'] ?? 'pending',
        'customerId' => $r['customer_id'] ? (int)$r['customer_id'] : null,
        'technicianId' => $r['technician_id'] ? (int)$r['technician_id'] : null,
        'customerName' => $r['customer_name'] ?? null,
        'customerPhone' => $r['customer_phone'] ?? null,
        'customerAddress' => $r['customer_address'] ?? null,
        'customerLocation' => $r['customer_location'] ?? null,
        'technicianName' => $r['technician_name'] ?? null,
        'technician' => $r['technician_id'] ? ['id' => (int)$r['technician_id'], 'name' => $r['technician_name'] ?? ''] : null,
        'scheduledAt' => $r['scheduled_at'] ?? null,
        'estimatedArrivalAt' => $r['estimated_arrival_at'] ?? null,
        'amount' => $r['amount'] ?? null,
        'collectionType' => $r['collection_type'] ?? null,
        'notes' => $r['notes'] ?? null,
        'createdAt' => $r['created_at'] ?? null,
        'overallProgress' => (int)$overallProgress,
        'items' => array_map(function($i) {
            return [
                'id' => (int)$i['id'],
                'description' => $i['description'],
                'isCompleted' => (bool)$i['is_completed'],
                'progress' => (int)($i['progress'] ?? ($i['is_completed'] ? 100 : 0)),
            ];
        }, $itemRows),
    ];
}

// ═══════════════════════════════════════════════════════════════
// ─── Appointments (السكرتارية) ────────────────────────────────
// ═══════════════════════════════════════════════════════════════

function _ensureAppointmentsTable() {
    global $db;
    // ملاحظة: لتجنب مشاكل الـ foreign key في بعض إصدارات MySQL/SQLite
    // نستخدم أعمدة عادية بدون قيود FK، ونربط في التطبيق فقط.
    $db->exec("CREATE TABLE IF NOT EXISTS appointments (
        id INT AUTO_INCREMENT PRIMARY KEY,
        title VARCHAR(255) NOT NULL,
        type VARCHAR(50) DEFAULT 'booking',
        appointment_date DATETIME NOT NULL,
        notes TEXT,
        created_by INT NULL,
        assigned_to INT NULL,
        color VARCHAR(30) DEFAULT 'blue',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
}

function appointments_list($input, $ctx) {
    global $db;
    _ensureAppointmentsTable();

    $userId = $ctx['userId'] ?? null;
    $month  = (int)($input['month'] ?? date('n'));
    $year   = (int)($input['year']  ?? date('Y'));

    $startDate = sprintf('%04d-%02d-01 00:00:00', $year, $month);
    $endMonth  = $month == 12 ? 1 : $month + 1;
    $endYear   = $month == 12 ? $year + 1 : $year;
    $endDate   = sprintf('%04d-%02d-01 00:00:00', $endYear, $endMonth);

    $sql = "SELECT a.*, 
                   creator.name AS creator_name,
                   assignee.name AS assignee_name
            FROM appointments a
            LEFT JOIN users creator  ON creator.id  = a.created_by
            LEFT JOIN users assignee ON assignee.id = a.assigned_to
            WHERE a.appointment_date >= ? AND a.appointment_date < ?
            ORDER BY a.appointment_date ASC";
    $stmt = $db->prepare($sql);
    $stmt->execute([$startDate, $endDate]);
    $rows = $stmt->fetchAll();

    return array_map(function($r) {
        return [
            'id'            => (int)$r['id'],
            'title'         => $r['title'],
            'type'          => $r['type'],
            'appointmentDate' => $r['appointment_date'],
            'notes'         => $r['notes'] ?? '',
            'createdBy'     => $r['created_by'] ? (int)$r['created_by'] : null,
            'creatorName'   => $r['creator_name'] ?? '',
            'assignedTo'    => $r['assigned_to'] ? (int)$r['assigned_to'] : null,
            'assigneeName'  => $r['assignee_name'] ?? '',
            'color'         => $r['color'] ?? 'blue',
            'createdAt'     => $r['created_at'],
        ];
    }, $rows);
}

function appointments_create($input, $ctx) {
    global $db;
    _ensureAppointmentsTable();

    $title   = $input['title'] ?? '';
    $type    = $input['type'] ?? 'booking';
    $dateStr = $input['appointmentDate'] ?? '';
    $notes   = $input['notes'] ?? '';
    $assignedTo = !empty($input['assignedTo']) ? (int)$input['assignedTo'] : null;
    $color   = $input['color'] ?? 'blue';
    $createdBy = $ctx['userId'] ?? null;

    if (empty($title) || empty($dateStr)) {
        throw new Exception('العنوان والتاريخ مطلوبان');
    }

    $stmt = $db->prepare("INSERT INTO appointments (title, type, appointment_date, notes, created_by, assigned_to, color) VALUES (?, ?, ?, ?, ?, ?, ?)");
    $stmt->execute([$title, $type, $dateStr, $notes, $createdBy, $assignedTo, $color]);

    $newId = (int)$db->lastInsertId();

    // إشعارات FCM + سجل notifications (نفس سلوك المهام)
    try {
        $dateLabel = strlen($dateStr) > 32 ? substr($dateStr, 0, 32) : $dateStr;
        if ($assignedTo) {
            _notifyUser(
                $assignedTo,
                'موعد جديد (سكرتارية)',
                "تم تعيينك لموعد: {$title} — {$dateLabel}",
                'appointment',
                $newId,
                'appointment'
            );
        }
        $adminBody = $assignedTo
            ? "موعد «{$title}» — {$dateLabel} (معيّن لموظف)."
            : "موعد «{$title}» — {$dateLabel}.";
        _notifyAdminsAndSupervisors('موعد جديد في السكرتارية', $adminBody, 'appointment', $newId, 'appointment');
    } catch (\Throwable $e) {
        error_log('[FCM] appointments.create notify: ' . $e->getMessage());
    }

    return ['success' => true, 'id' => $newId];
}

function appointments_delete($input, $ctx) {
    global $db;
    _ensureAppointmentsTable();

    $id = (int)($input['id'] ?? 0);
    if ($id <= 0) throw new Exception('معرف الموعد غير صالح');

    $stmt = $db->prepare("DELETE FROM appointments WHERE id = ?");
    $stmt->execute([$id]);

    return ['success' => true];
}

function appointments_staffList($ctx) {
    global $db;
    $rows = $db->query("SELECT id, name, email, role FROM users WHERE role IN ('admin', 'staff', 'technician') ORDER BY name ASC")->fetchAll();
    return array_map(function($r) {
        return [
            'id'    => (int)$r['id'],
            'name'  => $r['name'],
            'email' => $r['email'],
            'role'  => $r['role'],
        ];
    }, $rows);
}
