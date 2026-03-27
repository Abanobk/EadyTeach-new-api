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
 * عمود آخر إشعار تأخير — يُحدَّث مع التذكيرات (توافق مع إصدارات قديمة).
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

/** تذكيران يوميان: 9 صباحاً و 6 مساءً (بتوقيت EASYTECH_TZ أو Africa/Cairo). */
function _ensureTaskTwiceDailyReminderColumns() {
    global $db;
    static $done = false;
    if ($done) {
        return;
    }
    foreach ([
        'overdue_reminder_am_date' => 'DATE NULL',
        'overdue_reminder_pm_date' => 'DATE NULL',
        'unscheduled_reminder_am_date' => 'DATE NULL',
        'unscheduled_reminder_pm_date' => 'DATE NULL',
    ] as $col => $def) {
        try {
            $db->exec("ALTER TABLE tasks ADD COLUMN {$col} {$def} DEFAULT NULL");
        } catch (\Exception $e) {
            // موجود
        }
    }
    $done = true;
}

/** وقت تسجيل وصول الفني للعميل + آخر إشعار تأخر وصول (كل ساعة). */
function _ensureTaskLateArrivalColumns() {
    global $db;
    static $done = false;
    if ($done) {
        return;
    }
    try {
        $db->exec('ALTER TABLE tasks ADD COLUMN technician_arrived_at DATETIME NULL DEFAULT NULL');
    } catch (\Exception $e) {
    }
    try {
        $db->exec('ALTER TABLE tasks ADD COLUMN late_arrival_last_notified_at DATETIME NULL DEFAULT NULL');
    } catch (\Exception $e) {
    }
    $done = true;
}

function _tasksReminderTimezone(): string {
    $tz = getenv('EASYTECH_TZ');
    if ($tz !== false && $tz !== '') {
        return $tz;
    }
    $def = @date_default_timezone_get();
    if ($def !== false && $def !== '' && $def !== 'UTC') {
        return $def;
    }
    return 'Africa/Cairo';
}

/** ساعة 0–23 بتوقيت التذكيرات (للفترتين 9 و 18). */
function _tasksCurrentLocalHour(): int {
    try {
        $z = new DateTimeZone(_tasksReminderTimezone());
        $now = new DateTime('now', $z);
        return (int) $now->format('G');
    } catch (\Exception $e) {
        return (int) date('G');
    }
}

/** تجاوز موعد المهمة (للمقارنة مع NOW() في MySQL). */
function _tasksSqlAppointmentPassed(): string {
    return "(
            (estimated_arrival_at IS NOT NULL AND estimated_arrival_at < NOW())
            OR (
              estimated_arrival_at IS NULL
              AND scheduled_at IS NOT NULL
              AND (
                (TIME(scheduled_at) <> '00:00:00' AND scheduled_at < NOW())
                OR (TIME(scheduled_at) = '00:00:00' AND DATE(scheduled_at) < CURDATE())
              )
            )
          )";
}

/**
 * مهام تجاوزت الموعد — تذكير الفني والإدارة مرتين يومياً: 9 صباحاً و 6 مساءً فقط.
 *
 * @param int $intervalMinutes مهمل
 * @return array{sent:int,tasks:int,skipped?:string,slot?:string}
 */
function tasks_runOverdueReminders($intervalMinutes = 90) {
    global $db;

    $hour = _tasksCurrentLocalHour();
    if ($hour !== 9 && $hour !== 18) {
        return ['sent' => 0, 'tasks' => 0, 'skipped' => 'not_reminder_slot'];
    }
    $slotAm = $hour === 9;
    $slot = $slotAm ? 'am' : 'pm';

    _ensureTaskOverdueNotifyColumn();
    _ensureTaskTwiceDailyReminderColumns();
    if (!function_exists('_notifyUser')) {
        require_once __DIR__ . '/notifications_procedures.php';
    }
    _ensureNotificationsSchema();

    $appt = _tasksSqlAppointmentPassed();
    $slotSql = $slotAm
        ? '(overdue_reminder_am_date IS NULL OR overdue_reminder_am_date < CURDATE())'
        : '(overdue_reminder_pm_date IS NULL OR overdue_reminder_pm_date < CURDATE())';
    $setCol = $slotAm ? 'overdue_reminder_am_date' : 'overdue_reminder_pm_date';

    $sql = "
        SELECT id, title, technician_id, scheduled_at, estimated_arrival_at
        FROM tasks
        WHERE status NOT IN ('completed', 'cancelled')
          AND technician_id IS NOT NULL
          AND {$appt}
          AND {$slotSql}
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
            $db->prepare("UPDATE tasks SET {$setCol} = CURDATE(), overdue_last_notified_at = NOW() WHERE id = ?")->execute([$tid]);
            $sent++;
        } catch (\Exception $e) {
            error_log('tasks_runOverdueReminders: ' . $e->getMessage());
        }
    }

    return ['sent' => $sent, 'tasks' => count($rows), 'slot' => $slot];
}

function _ensureTaskUnscheduledNotifyColumn() {
    global $db;
    static $done = false;
    if ($done) {
        return;
    }
    try {
        $db->exec('ALTER TABLE tasks ADD COLUMN unscheduled_last_notified_at DATETIME NULL DEFAULT NULL');
    } catch (\Exception $e) {
        // موجود
    }
    $done = true;
}

/**
 * مهام بلا موعد — تذكير الإدارة مرتين يومياً (9 و 18) بعد 24 ساعة من الإنشاء.
 *
 * @return array{sent:int,tasks:int,skipped?:string,slot?:string}
 */
function tasks_runUnscheduledReminders() {
    global $db;

    $hour = _tasksCurrentLocalHour();
    if ($hour !== 9 && $hour !== 18) {
        return ['sent' => 0, 'tasks' => 0, 'skipped' => 'not_reminder_slot'];
    }
    $slotAm = $hour === 9;
    $slot = $slotAm ? 'am' : 'pm';

    _ensureTaskUnscheduledNotifyColumn();
    _ensureTaskTwiceDailyReminderColumns();
    if (!function_exists('_notifyAdminsAndSupervisors')) {
        require_once __DIR__ . '/notifications_procedures.php';
    }
    _ensureNotificationsSchema();

    $slotSql = $slotAm
        ? '(unscheduled_reminder_am_date IS NULL OR unscheduled_reminder_am_date < CURDATE())'
        : '(unscheduled_reminder_pm_date IS NULL OR unscheduled_reminder_pm_date < CURDATE())';
    $setCol = $slotAm ? 'unscheduled_reminder_am_date' : 'unscheduled_reminder_pm_date';

    $sql = "
        SELECT id, title, technician_id
        FROM tasks
        WHERE status NOT IN ('completed', 'cancelled')
          AND scheduled_at IS NULL
          AND estimated_arrival_at IS NULL
          AND created_at < DATE_SUB(NOW(), INTERVAL 24 HOUR)
          AND {$slotSql}
    ";

    $rows = $db->query($sql)->fetchAll(PDO::FETCH_ASSOC);
    $sent = 0;
    foreach ($rows as $r) {
        $tid = (int) $r['id'];
        $title = $r['title'] ?? 'مهمة';
        $techId = !empty($r['technician_id']) ? (int) $r['technician_id'] : null;
        try {
            $extra = $techId
                ? ' يرجى تحديد موعد للمهمة في التطبيق.'
                : ' المهمة بلا فني معيّن — يرجى تعيين فني وتحديد موعد.';
            _notifyAdminsAndSupervisors(
                'مهمة بدون موعد',
                "المهمة \"{$title}\" (#{$tid}) ليس لها تاريخ/وقت محدد بعد.{$extra}",
                'task',
                $tid,
                'task',
                ['reason' => 'task_unscheduled']
            );
            $db->prepare("UPDATE tasks SET {$setCol} = CURDATE(), unscheduled_last_notified_at = NOW() WHERE id = ?")->execute([$tid]);
            $sent++;
        } catch (\Exception $e) {
            error_log('tasks_runUnscheduledReminders: ' . $e->getMessage());
        }
    }

    return ['sent' => $sent, 'tasks' => count($rows), 'slot' => $slot];
}

/**
 * موعد الوصول مضى والفني لم يُسجّل وصولاً — إشعار للفني والإدارة كل ساعة (فاصل ~55 دقيقة بين الإشعارات لنفس المهمة).
 *
 * @return array{sent:int,tasks:int}
 */
function tasks_runLateArrivalReminders() {
    global $db;

    _ensureTaskLateArrivalColumns();
    if (!function_exists('_notifyUser')) {
        require_once __DIR__ . '/notifications_procedures.php';
    }
    _ensureNotificationsSchema();

    $appt = _tasksSqlAppointmentPassed();

    $sql = "
        SELECT t.id, t.title, t.technician_id, t.scheduled_at, t.estimated_arrival_at, tech.name AS technician_name
        FROM tasks t
        LEFT JOIN users tech ON tech.id = t.technician_id
        WHERE t.status NOT IN ('completed', 'cancelled')
          AND t.technician_id IS NOT NULL
          AND t.technician_arrived_at IS NULL
          AND {$appt}
          AND (
            t.late_arrival_last_notified_at IS NULL
            OR t.late_arrival_last_notified_at < DATE_SUB(NOW(), INTERVAL 55 MINUTE)
          )
    ";

    $rows = $db->query($sql)->fetchAll(PDO::FETCH_ASSOC);
    $sent = 0;
    foreach ($rows as $r) {
        $tid = (int) $r['id'];
        $title = $r['title'] ?? 'مهمة';
        $techId = (int) $r['technician_id'];
        $techName = trim((string) ($r['technician_name'] ?? '')) ?: 'الفني';
        try {
            _notifyUser(
                $techId,
                'تأخر في الوصول للعميل',
                "أنت متأخر في الوصول إلى العميل — المهمة \"{$title}\" (#{$tid}). يرجى التوجه أو تحديث حالة الوصول.",
                'task',
                $tid,
                'task',
                ['reason' => 'task_late_arrival']
            );
            _notifyAdminsAndSupervisors(
                'تأخر وصول فني',
                "{$techName} متأخر عن موعد الوصول للعميل في المهمة \"{$title}\" (#{$tid}).",
                'task',
                $tid,
                'task',
                ['reason' => 'task_late_arrival']
            );
            $db->prepare('UPDATE tasks SET late_arrival_last_notified_at = NOW() WHERE id = ?')->execute([$tid]);
            $sent++;
        } catch (\Exception $e) {
            error_log('tasks_runLateArrivalReminders: ' . $e->getMessage());
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
                    _ensureTaskTwiceDailyReminderColumns();
                    _ensureTaskUnscheduledNotifyColumn();
                    _ensureTaskLateArrivalColumns();
                    $db->prepare('UPDATE tasks SET overdue_last_notified_at = NULL, unscheduled_last_notified_at = NULL,
                        overdue_reminder_am_date = NULL, overdue_reminder_pm_date = NULL,
                        unscheduled_reminder_am_date = NULL, unscheduled_reminder_pm_date = NULL,
                        technician_arrived_at = NULL, late_arrival_last_notified_at = NULL
                        WHERE id = ?')->execute([$id]);
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

    // إشعار الفني المعيّن والإدارة عند ترحيل الموعد (تغيير scheduled / estimated)
    try {
        if ($prevTask) {
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
                if (!function_exists('_notifyUser')) {
                    require_once __DIR__ . '/notifications_procedures.php';
                }
                // الفني الحالي بعد التحديث (إن وُجد في الطلب وإلا السابق)
                $currentTechId = array_key_exists('technicianId', $input)
                    ? (int)($input['technicianId'] ?: 0)
                    : (int)($prevTask['technician_id'] ?? 0);

                $bodyTech = "تم ترحيل موعد المهمة \"{$taskTitle}\" (#{$id}). راجع التفاصيل في التطبيق.";
                $bodyAdmin = "تم ترحيل موعد المهمة \"{$taskTitle}\" (#{$id}).";

                if ($currentTechId > 0) {
                    _notifyUser(
                        $currentTechId,
                        'تم ترحيل موعد المهمة',
                        $bodyTech,
                        'task',
                        $id,
                        'task',
                        ['reason' => 'task_rescheduled']
                    );
                }
                _notifyAdminsAndSupervisors(
                    'تم ترحيل موعد مهمة',
                    $bodyAdmin,
                    'task',
                    $id,
                    'task',
                    ['reason' => 'task_rescheduled']
                );
                try {
                    _ensureTaskOverdueNotifyColumn();
                    _ensureTaskTwiceDailyReminderColumns();
                    _ensureTaskUnscheduledNotifyColumn();
                    _ensureTaskLateArrivalColumns();
                    $db->prepare('UPDATE tasks SET overdue_last_notified_at = NULL, unscheduled_last_notified_at = NULL,
                        overdue_reminder_am_date = NULL, overdue_reminder_pm_date = NULL,
                        unscheduled_reminder_am_date = NULL, unscheduled_reminder_pm_date = NULL,
                        technician_arrived_at = NULL, late_arrival_last_notified_at = NULL
                        WHERE id = ?')->execute([$id]);
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

        // إشعار الإدارة + الفني المعيّن عند تغيير الحالة (إلغاء / إكمال / …) ما لم يكن المُنفّذ هو نفسه الفني
        if ($newStatus && $newStatus !== $prevStatus) {
            if (!function_exists('_notifyUser')) {
                require_once __DIR__ . '/notifications_procedures.php';
            }
            $statusLabels = ['in_progress' => 'جاري العمل', 'completed' => 'مكتملة', 'cancelled' => 'ملغاة', 'pending' => 'معلقة'];
            $label = $statusLabels[$newStatus] ?? $newStatus;
            $body = "المهمة \"{$taskTitle}\" أصبحت: {$label}";
            _notifyAdminsAndSupervisors('تحديث مهمة', $body, 'task', $id, 'task', ['reason' => 'task_status_change']);

            $techId = (int) ($input['technicianId'] ?? $prevTask['technician_id'] ?? 0);
            $actorId = (int) ($ctx['userId'] ?? 0);
            if ($techId > 0 && $techId !== $actorId) {
                _notifyUser(
                    $techId,
                    'تحديث مهمة',
                    $body,
                    'task',
                    $id,
                    'task',
                    ['reason' => 'task_status_change']
                );
            }
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
function _ensureTechnicianLocationsSchema(): void {
    global $db;
    static $done = false;
    if ($done) return;
    $db->exec("CREATE TABLE IF NOT EXISTS technician_locations (
        id INT AUTO_INCREMENT PRIMARY KEY,
        technician_id INT NOT NULL,
        task_id INT NULL,
        request_id INT NULL,
        latitude DECIMAL(10,7) NOT NULL,
        longitude DECIMAL(10,7) NOT NULL,
        accuracy_m DECIMAL(10,2) NULL,
        is_arrived TINYINT(1) DEFAULT 0,
        source VARCHAR(32) DEFAULT 'mobile',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_tech_time (technician_id, created_at),
        INDEX idx_task_time (task_id, created_at),
        INDEX idx_req_time (request_id, created_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
    // Migrate older deployments
    try { $db->exec("ALTER TABLE technician_locations ADD COLUMN IF NOT EXISTS request_id INT NULL"); } catch (\Exception $e) {}
    try { $db->exec("ALTER TABLE technician_locations ADD INDEX idx_req_time (request_id, created_at)"); } catch (\Exception $e) {}
    $done = true;
}

function _ensureTechnicianLocationRequestsSchema(): void {
    global $db;
    static $done = false;
    if ($done) return;
    $db->exec("CREATE TABLE IF NOT EXISTS technician_location_requests (
        id INT AUTO_INCREMENT PRIMARY KEY,
        requested_by INT NOT NULL,
        technician_id INT NOT NULL,
        task_id INT NULL,
        status VARCHAR(20) DEFAULT 'pending',
        error TEXT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        fulfilled_at DATETIME NULL,
        INDEX idx_tech_status_time (technician_id, status, created_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
    $done = true;
}

function _ensureTechnicianDeviceStatusSchema(): void {
    global $db;
    static $done = false;
    if ($done) return;
    $db->exec("CREATE TABLE IF NOT EXISTS technician_device_status (
        technician_id INT PRIMARY KEY,
        location_permission VARCHAR(32) NULL,
        location_service_enabled TINYINT(1) DEFAULT 0,
        app_version VARCHAR(32) NULL,
        device_platform VARCHAR(16) NULL,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        INDEX idx_updated (updated_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
    $done = true;
}

function _requireAdminStaffSupervisor(array $ctx): void {
    global $db;
    $userId = (int)($ctx['userId'] ?? 0);
    if ($userId <= 0) throw new Exception('UNAUTHORIZED');
    $roleStmt = $db->prepare("SELECT role FROM users WHERE id = ?");
    $roleStmt->execute([$userId]);
    $role = $roleStmt->fetchColumn();
    $roleLower = $role ? strtolower(trim((string)$role)) : '';
    if (!in_array($roleLower, ['admin', 'staff', 'supervisor'], true)) {
        throw new Exception('FORBIDDEN');
    }
}

function technicianLocation_update($input, $ctx) {
    global $db;

    $userId = (int)($ctx['userId'] ?? 0);
    if ($userId <= 0) throw new Exception('UNAUTHORIZED');

    $lat = $input['latitude'] ?? null;
    $lng = $input['longitude'] ?? null;
    $taskId = $input['taskId'] ?? null;
    $arrived = $input['arrived'] ?? false;
    $accuracy = $input['accuracy'] ?? null;
    $source = $input['source'] ?? 'mobile';
    $requestId = $input['requestId'] ?? null;

    if ($lat !== null && $lng !== null) {
        try {
            _ensureTechnicianLocationsSchema();
            $latF = (float)$lat;
            $lngF = (float)$lng;
            $accF = ($accuracy === null || $accuracy === '') ? null : (float)$accuracy;
            $taskIdVal = ($taskId === null || $taskId === '') ? null : (int)$taskId;
            $arr = !empty($arrived) ? 1 : 0;
            $src = trim((string)$source);
            if ($src === '') $src = 'mobile';
            $reqVal = ($requestId === null || $requestId === '') ? null : (int)$requestId;
            $stmt = $db->prepare("INSERT INTO technician_locations
                (technician_id, task_id, request_id, latitude, longitude, accuracy_m, is_arrived, source)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)");
            $stmt->execute([$userId, $taskIdVal, $reqVal, $latF, $lngF, $accF, $arr, $src]);
        } catch (\Exception $e) {
            // ignore location storage errors
        }
    }

    // تسجيل وقت الوصول + إشعار الإدارة
    if ($arrived && $taskId) {
        try {
            _ensureTaskLateArrivalColumns();
            $db->prepare('UPDATE tasks SET technician_arrived_at = NOW(), late_arrival_last_notified_at = NULL WHERE id = ?')->execute([(int) $taskId]);
        } catch (\Exception $e) { /* ignore */ }
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

/**
 * Admin: latest known location for each technician (optionally within last N hours).
 * input: { sinceHours?: number }
 */
function technicianLocation_latest($input, $ctx) {
    global $db;
    _requireAdminStaffSupervisor($ctx);
    _ensureTechnicianLocationsSchema();

    $sinceHours = (int)($input['sinceHours'] ?? 24);
    if ($sinceHours <= 0) $sinceHours = 24;
    if ($sinceHours > 24 * 30) $sinceHours = 24 * 30;

    // Latest row per technician in the last window
    $stmt = $db->prepare("
        SELECT tl.*
        FROM technician_locations tl
        INNER JOIN (
            SELECT technician_id, MAX(id) AS max_id
            FROM technician_locations
            WHERE created_at >= (NOW() - INTERVAL ? HOUR)
            GROUP BY technician_id
        ) x ON x.technician_id = tl.technician_id AND x.max_id = tl.id
        ORDER BY tl.created_at DESC
    ");
    $stmt->execute([$sinceHours]);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    // attach technician names
    $ids = [];
    foreach ($rows as $r) $ids[] = (int)$r['technician_id'];
    $namesById = [];
    if ($ids) {
        $in = implode(',', array_fill(0, count($ids), '?'));
        $u = $db->prepare("SELECT id, name, role FROM users WHERE id IN ($in)");
        $u->execute($ids);
        foreach ($u->fetchAll(PDO::FETCH_ASSOC) as $ur) {
            $namesById[(int)$ur['id']] = ['name' => $ur['name'] ?? '', 'role' => $ur['role'] ?? ''];
        }
    }

    $out = [];
    foreach ($rows as $r) {
        $tid = (int)$r['technician_id'];
        $role = $namesById[$tid]['role'] ?? '';
        $roleLower = strtolower(trim((string)$role));
        // Return technicians only (module is for technicians tracking)
        if ($roleLower !== 'technician') {
            continue;
        }
        $out[] = [
            'technicianId' => $tid,
            'technicianName' => $namesById[$tid]['name'] ?? '',
            'technicianRole' => $namesById[$tid]['role'] ?? '',
            'taskId' => $r['task_id'] !== null ? (int)$r['task_id'] : null,
            'requestId' => $r['request_id'] !== null ? (int)$r['request_id'] : null,
            'latitude' => (float)$r['latitude'],
            'longitude' => (float)$r['longitude'],
            'accuracyM' => $r['accuracy_m'] !== null ? (float)$r['accuracy_m'] : null,
            'isArrived' => (int)($r['is_arrived'] ?? 0) === 1,
            'source' => $r['source'] ?? 'mobile',
            'createdAt' => $r['created_at'] ? (string)$r['created_at'] : null,
        ];
    }
    return $out;
}

/**
 * Admin: track points for a technician on a given day/time window.
 * input: { technicianId: number, date: 'YYYY-MM-DD', fromHour?: number, toHour?: number, intervalMin?: number }
 */
function technicianLocation_track($input, $ctx) {
    global $db;
    _requireAdminStaffSupervisor($ctx);
    _ensureTechnicianLocationsSchema();

    $techId = (int)($input['technicianId'] ?? 0);
    $date = trim((string)($input['date'] ?? ''));
    if ($techId <= 0 || $date === '') throw new Exception('INVALID_ARGUMENT');

    $fromHour = (int)($input['fromHour'] ?? 9);
    $toHour = (int)($input['toHour'] ?? 19);
    if ($fromHour < 0) $fromHour = 0;
    if ($toHour > 23) $toHour = 23;
    if ($toHour < $fromHour) $toHour = $fromHour;

    $intervalMin = (int)($input['intervalMin'] ?? 30);
    if ($intervalMin < 1) $intervalMin = 1;
    if ($intervalMin > 240) $intervalMin = 240;

    $fromTs = "{$date} " . str_pad((string)$fromHour, 2, '0', STR_PAD_LEFT) . ":00:00";
    $toTs = "{$date} " . str_pad((string)$toHour, 2, '0', STR_PAD_LEFT) . ":59:59";

    $stmt = $db->prepare("
        SELECT id, technician_id, task_id, request_id, latitude, longitude, accuracy_m, is_arrived, source, created_at
        FROM technician_locations
        WHERE technician_id = ?
          AND created_at BETWEEN ? AND ?
        ORDER BY created_at ASC, id ASC
    ");
    $stmt->execute([$techId, $fromTs, $toTs]);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    // downsample to one point per interval bucket (keep earliest point in bucket)
    $bucketSec = $intervalMin * 60;
    $seen = [];
    $out = [];
    foreach ($rows as $r) {
        $t = strtotime((string)$r['created_at']);
        if (!$t) continue;
        $b = (int)floor($t / $bucketSec);
        if (isset($seen[$b])) continue;
        $seen[$b] = true;
        $out[] = [
            'id' => (int)$r['id'],
            'technicianId' => (int)$r['technician_id'],
            'taskId' => $r['task_id'] !== null ? (int)$r['task_id'] : null,
            'requestId' => $r['request_id'] !== null ? (int)$r['request_id'] : null,
            'latitude' => (float)$r['latitude'],
            'longitude' => (float)$r['longitude'],
            'accuracyM' => $r['accuracy_m'] !== null ? (float)$r['accuracy_m'] : null,
            'isArrived' => (int)($r['is_arrived'] ?? 0) === 1,
            'source' => $r['source'] ?? 'mobile',
            'createdAt' => $r['created_at'] ? (string)$r['created_at'] : null,
        ];
    }

    return [
        'technicianId' => $techId,
        'date' => $date,
        'fromHour' => $fromHour,
        'toHour' => $toHour,
        'intervalMin' => $intervalMin,
        'points' => $out,
        'rawCount' => count($rows),
    ];
}

/**
 * Admin: manually set a technician location (e.g. overtime / phone check-in).
 * input: { technicianId: number, latitude: number, longitude: number, accuracy?: number, taskId?: number, note?: string }
 */
function technicianLocation_adminSet($input, $ctx) {
    global $db;
    _requireAdminStaffSupervisor($ctx);
    _ensureTechnicianLocationsSchema();

    $techId = (int)($input['technicianId'] ?? 0);
    $lat = $input['latitude'] ?? null;
    $lng = $input['longitude'] ?? null;
    if ($techId <= 0 || $lat === null || $lng === null) {
        throw new Exception('INVALID_ARGUMENT');
    }

    // validate technician exists
    $u = $db->prepare("SELECT id FROM users WHERE id = ? LIMIT 1");
    $u->execute([$techId]);
    if (!$u->fetchColumn()) {
        throw new Exception('INVALID_ARGUMENT');
    }

    $latF = (float)$lat;
    $lngF = (float)$lng;
    $acc = $input['accuracy'] ?? null;
    $accF = ($acc === null || $acc === '') ? null : (float)$acc;
    $taskId = $input['taskId'] ?? null;
    $taskIdVal = ($taskId === null || $taskId === '') ? null : (int)$taskId;

    // Optional note: stored in source field (short) for now without schema changes.
    $note = trim((string)($input['note'] ?? ''));
    $src = 'admin_manual';
    if ($note !== '') {
        $note = preg_replace('/\s+/u', ' ', $note);
        if (mb_strlen($note) > 20) $note = mb_substr($note, 0, 20);
        $src = "admin:$note";
    }

    $stmt = $db->prepare("INSERT INTO technician_locations
        (technician_id, task_id, request_id, latitude, longitude, accuracy_m, is_arrived, source)
        VALUES (?, ?, NULL, ?, ?, ?, 0, ?)");
    $stmt->execute([$techId, $taskIdVal, $latF, $lngF, $accF, $src]);

    return ['success' => true];
}

/**
 * Admin: list technicians for tracking module (independent of saved locations).
 * input: { search?: string }
 */
function technicianLocation_technicians($input, $ctx) {
    global $db;
    _requireAdminStaffSupervisor($ctx);
    _ensureTechnicianDeviceStatusSchema();

    $search = trim((string)($input['search'] ?? ''));
    $params = [];
    $sql = "SELECT u.id, u.name, u.email, u.phone,
                   s.location_permission, s.location_service_enabled, s.app_version, s.device_platform, s.updated_at AS status_updated_at
            FROM users u
            LEFT JOIN technician_device_status s ON s.technician_id = u.id
            WHERE LOWER(TRIM(u.role)) = 'technician'";
    if ($search !== '') {
        $sql .= " AND (u.name LIKE ? OR u.email LIKE ? OR u.phone LIKE ?)";
        $s = '%' . $search . '%';
        $params = [$s, $s, $s];
    }
    $sql .= " ORDER BY u.name ASC";
    $stmt = $db->prepare($sql);
    $stmt->execute($params);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
    $out = [];
    foreach ($rows as $r) {
        $out[] = [
            'id' => (int)($r['id'] ?? 0),
            'name' => $r['name'] ?? '',
            'email' => $r['email'] ?? null,
            'phone' => $r['phone'] ?? null,
            'status' => [
                'locationPermission' => $r['location_permission'] ?? null,
                'locationServiceEnabled' => (int)($r['location_service_enabled'] ?? 0) === 1,
                'appVersion' => $r['app_version'] ?? null,
                'devicePlatform' => $r['device_platform'] ?? null,
                'updatedAt' => $r['status_updated_at'] ?? null,
            ],
        ];
    }
    return ['rows' => $out];
}

/**
 * Technician device: update latest permission/service status for admin monitoring.
 * input: { locationPermission: 'always'|'while_in_use'|'denied'|'denied_forever'|'unknown', locationServiceEnabled: bool, appVersion?: string, devicePlatform?: string }
 */
function technicianStatus_update($input, $ctx) {
    global $db;
    $techId = (int)($ctx['userId'] ?? 0);
    if ($techId <= 0) throw new Exception('UNAUTHORIZED');

    $roleStmt = $db->prepare("SELECT role FROM users WHERE id = ?");
    $roleStmt->execute([$techId]);
    $role = strtolower(trim((string)($roleStmt->fetchColumn() ?? '')));
    if ($role !== 'technician') {
        // allow staff testing, but still restrict to logged-in users
    }

    _ensureTechnicianDeviceStatusSchema();

    $perm = strtolower(trim((string)($input['locationPermission'] ?? 'unknown')));
    $allowed = ['always', 'while_in_use', 'denied', 'denied_forever', 'unknown'];
    if (!in_array($perm, $allowed, true)) $perm = 'unknown';
    $svc = !empty($input['locationServiceEnabled']) ? 1 : 0;
    $appVerRaw = trim((string)($input['appVersion'] ?? ''));
    $appVer = $appVerRaw !== '' ? mb_substr($appVerRaw, 0, 32) : null;
    $platRaw = trim((string)($input['devicePlatform'] ?? ''));
    $plat = $platRaw !== '' ? mb_substr($platRaw, 0, 16) : null;

    $stmt = $db->prepare("
        INSERT INTO technician_device_status (technician_id, location_permission, location_service_enabled, app_version, device_platform)
        VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            location_permission = VALUES(location_permission),
            location_service_enabled = VALUES(location_service_enabled),
            app_version = VALUES(app_version),
            device_platform = VALUES(device_platform),
            updated_at = CURRENT_TIMESTAMP
    ");
    $stmt->execute([$techId, $perm, $svc, $appVer, $plat]);
    return ['success' => true];
}

/**
 * Admin: ask technician device to send location now (via FCM).
 * input: { technicianId: number, taskId?: number }
 */
function technicianLocation_requestNow($input, $ctx) {
    global $db;
    _requireAdminStaffSupervisor($ctx);
    _ensureTechnicianLocationsSchema();
    _ensureTechnicianLocationRequestsSchema();
    require_once __DIR__ . '/notifications_procedures.php';

    $adminId = (int)($ctx['userId'] ?? 0);
    $techId = (int)($input['technicianId'] ?? 0);
    if ($adminId <= 0 || $techId <= 0) throw new Exception('INVALID_ARGUMENT');

    $taskId = $input['taskId'] ?? null;
    $taskIdVal = ($taskId === null || $taskId === '') ? null : (int)$taskId;

    $u = $db->prepare("SELECT id FROM users WHERE id = ? LIMIT 1");
    $u->execute([$techId]);
    if (!$u->fetchColumn()) throw new Exception('INVALID_ARGUMENT');

    $reqStmt = $db->prepare("INSERT INTO technician_location_requests (requested_by, technician_id, task_id, status) VALUES (?, ?, ?, 'pending')");
    $reqStmt->execute([$adminId, $techId, $taskIdVal]);
    $reqId = (int)$db->lastInsertId();

    $extra = [
        'type' => 'location_request',
        'requestId' => (string)$reqId,
    ];
    if ($taskIdVal !== null) $extra['taskId'] = (string)$taskIdVal;

    // IMPORTANT: silent push only (no DB notification for technician)
    $pushQueued = _pushUserFcmOnly(
        $techId,
        'location_request',
        'location_request',
        $extra
    ) ? true : false;

    return ['success' => true, 'requestId' => $reqId, 'pushQueued' => $pushQueued];
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
    try { $db->exec('ALTER TABLE quotations ADD COLUMN IF NOT EXISTS dealer_user_id INT NULL'); } catch(\Exception $e) {}
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
    require_once __DIR__ . '/discounts_procedures.php';

    $createdBy = isset($ctx['userId']) ? (int)$ctx['userId'] : null;
    $clientUserId = isset($input['clientUserId']) ? (int)$input['clientUserId'] : null;
    $dealerUserId = isset($input['dealerUserId']) ? (int)$input['dealerUserId'] : null;
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
        $pid = (int)($item['productId'] ?? 0);

        if ($dealerUserId > 0 && $pid > 0) {
            try { $db->exec('ALTER TABLE products ADD COLUMN IF NOT EXISTS allow_discount_when_stock_zero TINYINT DEFAULT 0'); } catch (\Exception $e) {}
            $pStmt = $db->prepare('SELECT id, category_id, stock, allow_discount_when_stock_zero FROM products WHERE id = ?');
            $pStmt->execute([$pid]);
            $prow = $pStmt->fetch(PDO::FETCH_ASSOC);
            if ($prow) {
                $catId = isset($prow['category_id']) ? (int)$prow['category_id'] : null;
                $stock = (int)($prow['stock'] ?? 0);
                $allowZero = (int)($prow['allow_discount_when_stock_zero'] ?? 0) === 1;
                $rule = discounts_fetchDealerRuleForProduct($db, $dealerUserId, $pid, $catId);
                if ($rule) {
                    $item['officialUnitPrice'] = $unitPrice;
                    $applied = discounts_applyDealerRuleToUnitPrice($unitPrice, $rule, $stock, $allowZero);
                    $unitPrice = $applied['finalUnitPrice'];
                    $item['unitPrice'] = $unitPrice;
                    $item['dealerDiscountPercent'] = $applied['discountPercent'];
                    $item['dealerDiscountValuePerUnit'] = $applied['discountValuePerUnit'];
                    if (!empty($applied['waitingMessage'])) {
                        $item['dealerDiscountWaiting'] = $applied['waitingMessage'];
                    }
                }
            }
        }

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

    $stmt = $db->prepare('INSERT INTO quotations (ref_number, created_by, client_user_id, dealer_user_id, client_name, client_email, client_phone, items, subtotal, installation_percent, installation_amount, discount_percent, discount_amount, total_amount, notes) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)');
    $stmt->execute([$refNumber, $createdBy, $clientUserId, $dealerUserId > 0 ? $dealerUserId : null, $clientName, $clientEmail, $clientPhone, json_encode($items, JSON_UNESCAPED_UNICODE), $subtotal, $installPct, $installAmt, $discountPct, $discountAmt, $totalAmt, $notes]);
    $newId = (int)$db->lastInsertId();

    // إشعار FCM + صف في جدول notifications لكل admin/supervisor/staff عند كل إنشاء عرض سعر
    // (يُسجَّل في DB حتى لو لم يكن للمستخدم توكن FCM — راجع جدول notifications و fcm_tokens على السيرفر)
    try {
        if (!function_exists('_notifyAdminsAndSupervisors')) {
            require_once __DIR__ . '/notifications_procedures.php';
        }
        $creatorId = isset($ctx['userId']) ? (int)$ctx['userId'] : 0;
        $creatorLabel = '';
        if ($creatorId > 0) {
            $cn = $db->prepare('SELECT name, TRIM(LOWER(role)) FROM users WHERE id = ?');
            $cn->execute([$creatorId]);
            $crow = $cn->fetch(PDO::FETCH_ASSOC);
            if ($crow) {
                $creatorLabel = trim((string)($crow['name'] ?? ''));
            }
        }
        $clientLabel = trim((string)($clientName ?? ''));
        if ($clientLabel === '') {
            $clientLabel = trim((string)($clientEmail ?? ''));
        }
        if ($clientLabel === '') {
            $clientLabel = 'عميل';
        }
        $dealerSuffix = '';
        if ($dealerUserId > 0) {
            $ds = $db->prepare('SELECT name FROM users WHERE id = ?');
            $ds->execute([$dealerUserId]);
            $dn = trim((string)($ds->fetchColumn() ?: ''));
            if ($dn !== '') {
                $dealerSuffix = " — الموزع: {$dn}";
            }
        }
        $totalStr = number_format((float)$totalAmt, 2, '.', '');
        $byLine = $creatorLabel !== '' ? " (بواسطة: {$creatorLabel})" : ($creatorId <= 0 ? ' (بدون جلسة مستخدم)' : '');
        $body = "تم إنشاء عرض السعر {$refNumber} للعميل: {$clientLabel}{$dealerSuffix}. الإجمالي: {$totalStr} ج.م{$byLine}";

        $nAdmins = (int)$db->query(
            "SELECT COUNT(*) FROM users WHERE TRIM(LOWER(role)) IN ('admin', 'supervisor', 'staff') AND COALESCE(is_active, 1) = 1"
        )->fetchColumn();
        error_log('[quotations.create] notify admins: quotation_id=' . $newId . ' creator_user_id=' . $creatorId . ' admin_recipients=' . $nAdmins);

        _notifyAdminsAndSupervisors(
            'عرض سعر جديد',
            $body,
            'quotation',
            $newId,
            'quotation',
            ['quotationId' => (string)$newId, 'action' => 'created']
        );
    } catch (\Throwable $e) {
        error_log('[FCM] quotations.create notify admins: ' . $e->getMessage());
    }

    return ['id' => $newId];
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

function quotations_update($input, $ctx) {
    global $db;
    _ensureQuotationsTable();

    $userId = isset($ctx['userId']) ? (int)$ctx['userId'] : 0;
    if ($userId <= 0) throw new Exception('UNAUTHORIZED');

    $id = (int)($input['id'] ?? 0);
    if ($id <= 0) throw new Exception('Invalid quotation id');

    $qStmt = $db->prepare('SELECT * FROM quotations WHERE id = ?');
    $qStmt->execute([$id]);
    $q = $qStmt->fetch();
    if (!$q) throw new Exception('Quotation not found');

    // Only allow owner (created_by) or admin/supervisor/staff to edit.
    $createdBy = isset($q['created_by']) ? (int)$q['created_by'] : 0;
    $roleStmt = $db->prepare('SELECT role FROM users WHERE id = ?');
    $roleStmt->execute([$userId]);
    $role = strtolower(trim((string)($roleStmt->fetchColumn() ?: '')));
    $isAdmin = in_array($role, ['admin', 'supervisor', 'staff'], true);
    if (!$isAdmin && $createdBy !== $userId) throw new Exception('FORBIDDEN');

    // Block editing when purchase flow started/accepted.
    $purchaseStatus = strtolower(trim((string)($q['purchase_request_status'] ?? 'none')));
    if ($purchaseStatus === 'requested' || $purchaseStatus === 'accepted') {
        throw new Exception('لا يمكن تعديل عرض السعر بعد بدء/اعتماد طلب الشراء');
    }

    $items = $input['items'] ?? null;
    if (!is_array($items) || count($items) === 0) {
        throw new Exception('items is required');
    }

    $notes = $input['notes'] ?? null;
    $installPct = (float)($input['installationPercent'] ?? 0);
    $discountPct = (float)($input['discountPercent'] ?? 0);
    $discountAmtInput = (float)($input['discountAmount'] ?? 0);

    // Recompute subtotal/total from items
    $subtotal = 0.0;
    foreach ($items as &$item) {
        if (!is_array($item)) continue;
        $qty = (int)($item['quantity'] ?? $item['qty'] ?? 1);
        if ($qty <= 0) $qty = 1;
        $unitPrice = (float)($item['unitPrice'] ?? 0);
        $item['qty'] = $qty;
        $item['totalPrice'] = $unitPrice * $qty;
        $subtotal += $item['totalPrice'];
    }
    unset($item);

    $installAmt = $installPct > 0 ? $subtotal * $installPct / 100.0 : 0.0;
    $discountAmt = $discountPct > 0 ? $subtotal * $discountPct / 100.0 : $discountAmtInput;
    $totalAmt = $subtotal + $installAmt - $discountAmt;
    if ($totalAmt < 0) $totalAmt = 0.0;

    $dealerUserId = !empty($q['dealer_user_id']) ? (int)$q['dealer_user_id'] : null;
    if (array_key_exists('dealerUserId', $input)) {
        $du = (int)($input['dealerUserId'] ?? 0);
        $dealerUserId = $du > 0 ? $du : null;
    }

    $db->prepare('UPDATE quotations
        SET items = ?,
            subtotal = ?,
            installation_percent = ?,
            installation_amount = ?,
            discount_percent = ?,
            discount_amount = ?,
            total_amount = ?,
            notes = ?,
            dealer_user_id = ?
        WHERE id = ?')
      ->execute([
        json_encode($items, JSON_UNESCAPED_UNICODE),
        $subtotal,
        $installPct,
        $installAmt,
        $discountPct,
        $discountAmt,
        $totalAmt,
        $notes,
        $dealerUserId,
        $id
      ]);

    // إشعار الإدارة/المشرفين/الموظفين عند حفظ (تعديل) عرض السعر
    try {
        if (!function_exists('_notifyAdminsAndSupervisors')) {
            require_once __DIR__ . '/notifications_procedures.php';
        }
        $editorName = '';
        $editorStmt = $db->prepare('SELECT name FROM users WHERE id = ?');
        $editorStmt->execute([$userId]);
        $editorName = trim((string)($editorStmt->fetchColumn() ?: ''));

        $refNumber = trim((string)($q['ref_number'] ?? ''));
        $clientLabel = trim((string)($q['client_name'] ?? ''));
        if ($clientLabel === '') {
            $clientLabel = trim((string)($q['client_email'] ?? ''));
        }
        if ($clientLabel === '') {
            $clientLabel = 'عميل';
        }
        $who = $editorName !== '' ? $editorName : ('مستخدم #' . $userId);
        $refPart = $refNumber !== '' ? " {$refNumber}" : '';
        $totalStr = number_format((float)$totalAmt, 2, '.', '');
        $body = "تم تحديث عرض السعر{$refPart} للعميل: {$clientLabel} بواسطة {$who}. الإجمالي الجديد: {$totalStr} ج.م";

        _notifyAdminsAndSupervisors(
            'تحديث عرض سعر',
            $body,
            'quotation',
            $id,
            'quotation',
            ['quotationId' => (string)$id, 'action' => 'updated']
        );
    } catch (\Throwable $e) {
        error_log('[FCM] quotations.update notify admins: ' . $e->getMessage());
    }

    return ['success' => true];
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

    // When stock/discount is "waiting" we don't want dealer price to become 0.
    // Instead, we distribute quotation-level client revenue (after discount + installation)
    // over items proportionally, so dealer profit becomes ~0 for these waiting items.
    $quoteSubtotal = (float)($q['subtotal'] ?? 0);
    $quoteDiscountAmount = (float)($q['discount_amount'] ?? 0);
    $quoteInstallationAmount = (float)($q['installation_amount'] ?? 0);

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
                } else {
                    // Stock/discount waiting: dealer price must equal "client revenue share" (no fake profit).
                    $itemSubtotal = (float)($item['totalPrice'] ?? 0);
                    if ($itemSubtotal <= 0) {
                        $qUnit = (float)($item['unitPrice'] ?? 0);
                        $itemSubtotal = $qUnit * $qty;
                    }
                    $share = $quoteSubtotal > 0 ? ($itemSubtotal / $quoteSubtotal) : 0.0;
                    // When waiting (e.g. stock = 0 / minStock not met), no discount should be applied
                    // to client nor dealer for this item.
                    $itemClientAfterDiscount = $itemSubtotal;
                    $itemInstallationShare = $quoteInstallationAmount * $share;
                    $targetDealerTotal = $itemClientAfterDiscount + $itemInstallationShare;
                    if ($targetDealerTotal < 0) $targetDealerTotal = 0.0;
                    $dealerUnitPrice = $qty > 0 ? ($targetDealerTotal / $qty) : 0.0;
                    $appliedPercent = 0.0;
                    $appliedAmount = 0.0;
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

    // For "waiting" (e.g. stock/discount not ready), we must avoid fake dealer profit.
    // We'll allocate the dealer unit price proportionally to the client revenue share:
    // (itemSubtotal - clientDiscountShare) + itemInstallationShare.
    $quoteSubtotal = (float)($q['subtotal'] ?? 0);
    $quoteDiscountAmount = (float)($q['discount_amount'] ?? 0);
    $quoteInstallationAmount = (float)($q['installation_amount'] ?? 0);

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
                } else {
                    // waiting item: dealer price should match "client revenue share" (no fake profit)
                    $itemSubtotal = (float)($item['totalPrice'] ?? 0);
                    if ($itemSubtotal <= 0) {
                        $qUnit = (float)($item['unitPrice'] ?? 0);
                        $itemSubtotal = $qUnit * $qty;
                    }
                    $share = $quoteSubtotal > 0 ? ($itemSubtotal / $quoteSubtotal) : 0.0;
                    // When waiting (e.g. stock = 0 / minStock not met), no discount should be applied
                    // to client nor dealer for this item.
                    $itemClientAfterDiscount = $itemSubtotal;
                    $itemInstallationShare = $quoteInstallationAmount * $share;
                    $targetDealerTotal = $itemClientAfterDiscount + $itemInstallationShare;
                    if ($targetDealerTotal < 0) $targetDealerTotal = 0.0;
                    $dealerUnitPrice = $qty > 0 ? ($targetDealerTotal / $qty) : 0.0;
                    $appliedPercent = 0.0;
                    $appliedAmount = 0.0;
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

    // Optional admin overrides for dealer prices:
    // input['purchaseItems'] = [{productId, qty, dealerUnitPrice}, ...]
    $overrideByProductId = [];
    $overrideItems = $input['purchaseItems'] ?? null;
    if (is_array($overrideItems)) {
        foreach ($overrideItems as $it) {
            if (!is_array($it)) continue;
            $pid = (int)($it['productId'] ?? 0);
            if ($pid <= 0) continue;
            $du = (float)($it['dealerUnitPrice'] ?? 0);
            $qQty = (int)($it['qty'] ?? $it['quantity'] ?? 0);
            $overrideByProductId[$pid] = ['dealerUnitPrice' => $du, 'qty' => $qQty];
        }
    }

    // Used for "stock waiting" items: distribute client revenue share so dealer profit isn't fake.
    $quoteSubtotal = (float)($q['subtotal'] ?? 0);
    $quoteDiscountAmount = (float)($q['discount_amount'] ?? 0);
    $quoteInstallationAmount = (float)($q['installation_amount'] ?? 0);

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

                            // Compute waiting/discount rules for this product for this dealer.
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

                            // If admin has provided explicit dealer unit price for this product, use it.
                            // We still keep $waitingMessage (stock=0) so UI/cart treat it as waiting (no discount).
                            if (isset($overrideByProductId[$productId])) {
                                $dealerUnitPrice = (float)($overrideByProductId[$productId]['dealerUnitPrice'] ?? 0);
                                if ($dealerUnitPrice < 0) $dealerUnitPrice = 0.0;
                                $appliedPercent = 0.0;
                                $appliedAmount = 0.0;
                            } else {
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
                                } else {
                                    // Stock/discount waiting: dealer price equals client revenue share (no fake profit).
                                    $itemSubtotal = (float)($item['totalPrice'] ?? 0);
                                    if ($itemSubtotal <= 0) {
                                        $qUnit = (float)($item['unitPrice'] ?? 0);
                                        $itemSubtotal = $qUnit * $qty;
                                    }
                                    $share = $quoteSubtotal > 0 ? ($itemSubtotal / $quoteSubtotal) : 0.0;
                                    // When waiting (e.g. stock = 0 / minStock not met), no discount should be applied
                                    // to client nor dealer for this item.
                                    $itemClientAfterDiscount = $itemSubtotal;
                                    $itemInstallationShare = $quoteInstallationAmount * $share;
                                    $targetDealerTotal = $itemClientAfterDiscount + $itemInstallationShare;
                                    if ($targetDealerTotal < 0) $targetDealerTotal = 0.0;
                                    $dealerUnitPrice = $qty > 0 ? ($targetDealerTotal / $qty) : 0.0;
                                    $appliedPercent = 0.0;
                                    $appliedAmount = 0.0;
                                }
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

function _quotationDealerDisplayName($db, $r) {
    if (!$db || !is_array($r)) {
        return null;
    }
    $tryName = function ($userId) use ($db) {
        if ($userId <= 0) {
            return null;
        }
        try {
            $ds = $db->prepare('SELECT name, role FROM users WHERE id = ?');
            $ds->execute([$userId]);
            $row = $ds->fetch(PDO::FETCH_ASSOC);
            if (!$row) {
                return null;
            }
            $name = trim((string)($row['name'] ?? ''));
            if ($name === '') {
                return null;
            }
            return ['name' => $name, 'role' => strtolower(trim((string)($row['role'] ?? '')))];
        } catch (\Exception $e) {
            return null;
        }
    };

    if (!empty($r['dealer_user_id'])) {
        $got = $tryName((int)$r['dealer_user_id']);
        if ($got !== null) {
            return $got['name'];
        }
    }

    // عروض أنشأها التاجر بدون تعبئة dealer_user_id (لم يُختر موزع من القائمة)
    if (empty($r['dealer_user_id']) && !empty($r['created_by'])) {
        $got = $tryName((int)$r['created_by']);
        if ($got !== null) {
            $role = $got['role'];
            // لا نعرض اسم المسؤول/الموظف كـ "موزع" عند إنشاء العرض من لوحة الإدارة
            if (!in_array($role, ['admin', 'supervisor', 'staff'], true)) {
                return $got['name'];
            }
        }
    }

    return null;
}

function _formatQuotation($r) {
    global $db;
    $items = $r['items'] ? json_decode($r['items'], true) : [];
    foreach ($items as &$item) {
        $qty = (int)($item['quantity'] ?? $item['qty'] ?? 1);
        $unitPrice = (float)($item['unitPrice'] ?? 0);
        $item['qty'] = $qty;
        if (!isset($item['totalPrice'])) $item['totalPrice'] = $unitPrice * $qty;
    }
    unset($item);

    $dealerName = _quotationDealerDisplayName($db, $r);

    return [
        'id' => (int)$r['id'],
        'refNumber' => $r['ref_number'] ?? ('QT-' . $r['id']),
        'createdBy' => isset($r['created_by']) && $r['created_by'] ? (int)$r['created_by'] : null,
        'clientUserId' => isset($r['client_user_id']) && $r['client_user_id'] ? (int)$r['client_user_id'] : null,
        'dealerUserId' => isset($r['dealer_user_id']) && $r['dealer_user_id'] ? (int)$r['dealer_user_id'] : null,
        'dealerName' => $dealerName,
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
        approved_items LONGTEXT NULL,
        total DECIMAL(12,2) DEFAULT 0,
        cart_synced TINYINT(1) DEFAULT 0,
        status VARCHAR(50) DEFAULT "pending",
        payment_method VARCHAR(30) DEFAULT "cash",
        payment_proof_url TEXT NULL,
        shipping_address TEXT NULL,
        notes TEXT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_user (user_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4');

    // Ensure new columns exist for older deployments.
    try { $db->exec('ALTER TABLE orders ADD COLUMN IF NOT EXISTS approved_items LONGTEXT NULL'); } catch (\Exception $e) {}
    try { $db->exec('ALTER TABLE orders ADD COLUMN IF NOT EXISTS cart_synced TINYINT(1) DEFAULT 0'); } catch (\Exception $e) {}
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

    $stmt = $db->prepare('INSERT INTO orders (user_id, items, approved_items, total, cart_synced, status, payment_method, payment_proof_url, shipping_address, notes)
                          VALUES (?, ?, NULL, ?, 0, ?, ?, ?, ?, ?)');
    $stmt->execute([$userId, $items, $total, $status, $paymentMethod, $paymentProofUrl, $address, $notes]);
    $orderId = (int)$db->lastInsertId();

    try {
        _notifyAdminsAndSupervisors('طلب جديد', "طلب جديد رقم #{$orderId} بقيمة {$total}", 'order', $orderId, 'order');
    } catch (\Exception $e) { /* ignore */ }

    return ['id' => $orderId];
}

/**
 * Orders pending cart sync:
 * - For owner (client/dealer) only
 * - Returns confirmed orders that have approved_items and cart_synced = 0
 */
function orders_getPendingCartSync($input, $ctx) {
    global $db;
    _ensureOrdersTable();
    $userId = (int)($ctx['userId'] ?? 0);
    if ($userId <= 0) throw new Exception('UNAUTHORIZED');

    $stmt = $db->prepare("SELECT id, approved_items FROM orders
                          WHERE user_id = ? AND status = 'confirmed' AND cart_synced = 0
                            AND approved_items IS NOT NULL AND TRIM(approved_items) <> ''
                          ORDER BY created_at ASC");
    $stmt->execute([$userId]);
    $rows = $stmt->fetchAll();
    $result = [];
    foreach ($rows as $r) {
        $items = [];
        try { $items = $r['approved_items'] ? json_decode($r['approved_items'], true) : []; } catch (\Exception $e) { $items = []; }
        if (!is_array($items)) $items = [];
        $result[] = ['orderId' => (int)$r['id'], 'items' => $items];
    }
    return $result;
}

function orders_markCartSynced($input, $ctx) {
    global $db;
    _ensureOrdersTable();
    $userId = (int)($ctx['userId'] ?? 0);
    if ($userId <= 0) throw new Exception('UNAUTHORIZED');
    $orderId = (int)($input['orderId'] ?? 0);
    if ($orderId <= 0) throw new Exception('INVALID_ARGUMENT');

    $upd = $db->prepare("UPDATE orders SET cart_synced = 1 WHERE id = ? AND user_id = ?");
    $upd->execute([$orderId, $userId]);
    return ['success' => true];
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
            o.approved_items,
            o.total,
            o.status,
            o.payment_method,
            o.payment_proof_url,
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
            'approvedItems' => $r['approved_items'] ? json_decode($r['approved_items'], true) : null,
            'paymentMethod' => $r['payment_method'] ?? 'cash',
            'paymentProofUrl' => $r['payment_proof_url'] ?? null,
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

/**
 * Admin can override unit prices for preorder orders.
 * input: { orderId, items: [{productId, quantity, unitPrice}] }
 */
function admin_updateOrderPricing($input, $ctx) {
    global $db;
    _ensureOrdersTable();

    $adminId = (int)($ctx['userId'] ?? 0);
    if ($adminId <= 0) throw new Exception('UNAUTHORIZED');

    $roleStmt = $db->prepare("SELECT role FROM users WHERE id = ?");
    $roleStmt->execute([$adminId]);
    $role = $roleStmt->fetchColumn();
    $roleLower = $role ? strtolower(trim((string)$role)) : '';
    if (!in_array($roleLower, ['admin', 'staff', 'supervisor'], true)) {
        throw new Exception('FORBIDDEN');
    }

    $orderId = (int)($input['orderId'] ?? 0);
    if ($orderId <= 0) throw new Exception('INVALID_ARGUMENT');
    $newItems = $input['items'] ?? null;
    if (!is_array($newItems) || count($newItems) === 0) throw new Exception('INVALID_ARGUMENT');

    // Load order to validate status + original lines (للحفاظ على configuration / variant عند حفظ أسعار الطلب المسبق)
    $stmt = $db->prepare("SELECT status, items FROM orders WHERE id = ?");
    $stmt->execute([$orderId]);
    $orderRow = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$orderRow) {
        throw new Exception('INVALID_ARGUMENT');
    }
    $status = $orderRow['status'] ?? null;
    $origItems = [];
    if (!empty($orderRow['items'])) {
        try {
            $decoded = json_decode($orderRow['items'], true);
            $origItems = is_array($decoded) ? $decoded : [];
        } catch (\Exception $e) {
            $origItems = [];
        }
    }
    $statusNorm = $status ? strtolower(trim((string)$status)) : '';
    if ($statusNorm !== 'preorder') {
        throw new Exception('لا يمكن تعديل السعر إلا في حالة طلب مسبق');
    }

    $approvedItems = [];
    $total = 0.0;
    $seq = 0;
    foreach ($newItems as $it) {
        if (!is_array($it)) continue;
        $pid = (int)($it['productId'] ?? 0);
        if ($pid <= 0) continue;
        $qty = (int)($it['quantity'] ?? $it['qty'] ?? 1);
        if ($qty <= 0) $qty = 1;
        $unit = (float)($it['unitPrice'] ?? $it['price'] ?? 0);
        if ($unit < 0) $unit = 0.0;
        $lineTotal = $unit * $qty;
        $total += $lineTotal;
        $origIdx = isset($it['lineIndex']) ? (int)$it['lineIndex'] : $seq;
        $seq++;
        $base = (isset($origItems[$origIdx]) && is_array($origItems[$origIdx])) ? $origItems[$origIdx] : [];
        $approvedItems[] = array_merge($base, [
            'productId' => $pid,
            'quantity' => $qty,
            'unitPrice' => $unit,
        ]);
    }
    if (!$approvedItems) throw new Exception('INVALID_ARGUMENT');

    $upd = $db->prepare("UPDATE orders SET approved_items = ?, total = ? WHERE id = ?");
    $upd->execute([json_encode($approvedItems, JSON_UNESCAPED_UNICODE), $total, $orderId]);

    return ['success' => true, 'totalAmount' => $total];
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

    // When confirming a *preorder* only: require approved_items and reset cart_synced for cart sync.
    // Normal orders (pending / transfer / etc.) can be confirmed without approved_items.
    $curStmt = $db->prepare("SELECT status, approved_items FROM orders WHERE id = ?");
    $curStmt->execute([$orderId]);
    $curRow = $curStmt->fetch(PDO::FETCH_ASSOC);
    if (!$curRow) {
        throw new Exception('INVALID_ARGUMENT');
    }
    $currentStatus = strtolower(trim((string)($curRow['status'] ?? '')));
    $newStatus = strtolower(trim($status));

    if ($newStatus === 'confirmed' && $currentStatus === 'preorder') {
        $approvedRaw = isset($curRow['approved_items']) ? trim((string)$curRow['approved_items']) : '';
        if ($approvedRaw === '') {
            throw new Exception('لا يمكن تأكيد الطلب قبل تحديد أسعار المنتجات (طلب مسبق)');
        }
        $upd = $db->prepare("UPDATE orders SET status = ?, cart_synced = 0 WHERE id = ?");
        $upd->execute([$status, $orderId]);
    } else {
        $upd = $db->prepare("UPDATE orders SET status = ? WHERE id = ?");
        $upd->execute([$status, $orderId]);
    }

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

function _ensureAppointmentReminderColumns() {
    global $db;
    static $done = false;
    if ($done) {
        return;
    }
    foreach ([
        'completed_at' => 'DATETIME NULL DEFAULT NULL',
        'reminder_pref_sent_at' => 'DATETIME NULL DEFAULT NULL',
        'reminder_1h_sent_at' => 'DATETIME NULL DEFAULT NULL',
        'reminder_missed_sent_at' => 'DATETIME NULL DEFAULT NULL',
    ] as $col => $def) {
        try {
            $db->exec("ALTER TABLE appointments ADD COLUMN {$col} {$def}");
        } catch (\Exception $e) {
            // موجود
        }
    }
    $done = true;
}

function _appointmentTypeLabelAr($type) {
    $t = (string) $type;
    $map = [
        'booking' => 'حجز',
        'call' => 'مكالمة',
        'visit' => 'زيارة منزلية',
        'maintenance' => 'صيانة',
        'followup' => 'متابعة طلب',
        'meeting' => 'اجتماع',
    ];
    return $map[$t] ?? $t;
}

/**
 * إشعار المنشئ والمعيّن (الطرفين) دون تكرار لنفس المستخدم.
 */
function _notifyAppointmentParties($appointmentId, $title, $body, $createdBy, $assignedTo, $extraData = []) {
    if (!function_exists('_notifyUser')) {
        require_once __DIR__ . '/notifications_procedures.php';
    }
    $ids = [];
    if (!empty($createdBy)) {
        $ids[] = (int) $createdBy;
    }
    if (!empty($assignedTo)) {
        $ids[] = (int) $assignedTo;
    }
    $ids = array_values(array_unique($ids));
    foreach ($ids as $uid) {
        if ($uid > 0) {
            _notifyUser($uid, $title, $body, 'appointment', $appointmentId, 'appointment', $extraData);
        }
    }
    if (empty($ids) && function_exists('_notifyAdminsAndSupervisors')) {
        _notifyAdminsAndSupervisors($title, $body, 'appointment', $appointmentId, 'appointment', $extraData);
    }
}

function appointments_list($input, $ctx) {
    global $db;
    _ensureAppointmentsTable();
    _ensureAppointmentReminderColumns();

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
            'completedAt'   => $r['completed_at'] ?? null,
        ];
    }, $rows);
}

function appointments_create($input, $ctx) {
    global $db;
    _ensureAppointmentsTable();
    _ensureAppointmentReminderColumns();

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

    // إشعار الطرفين (المنشئ + المعيّن) + الإدارة
    try {
        $dateLabel = strlen($dateStr) > 32 ? substr($dateStr, 0, 32) : $dateStr;
        $typeLabel = _appointmentTypeLabelAr($type);
        if (!function_exists('_notifyUser')) {
            require_once __DIR__ . '/notifications_procedures.php';
        }
        _ensureNotificationsSchema();

        $bodyParties = "موعد سكرتارية ({$typeLabel}): «{$title}» — {$dateLabel}. راجع التقويم.";
        _notifyAppointmentParties(
            $newId,
            'موعد جديد (سكرتارية)',
            $bodyParties,
            $createdBy ? (int) $createdBy : null,
            $assignedTo,
            ['reason' => 'appointment_created']
        );

        $adminBody = $assignedTo
            ? "موعد «{$title}» ({$typeLabel}) — {$dateLabel} — منشئ + معيّن."
            : "موعد «{$title}» ({$typeLabel}) — {$dateLabel}.";
        _notifyAdminsAndSupervisors('موعد جديد في السكرتارية', $adminBody, 'appointment', $newId, 'appointment', ['reason' => 'appointment_created']);
    } catch (\Throwable $e) {
        error_log('[FCM] appointments.create notify: ' . $e->getMessage());
    }

    return ['success' => true, 'id' => $newId];
}

function appointments_complete($input, $ctx) {
    global $db;
    _ensureAppointmentsTable();
    _ensureAppointmentReminderColumns();

    $id = (int)($input['id'] ?? 0);
    if ($id <= 0) {
        throw new Exception('معرف الموعد غير صالح');
    }
    $stmt = $db->prepare('UPDATE appointments SET completed_at = NOW() WHERE id = ? AND completed_at IS NULL');
    $stmt->execute([$id]);
    return ['success' => true];
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

/**
 * تذكيرات السكرتارية — يُستدعى من cron كل 15–60 دقيقة.
 * - قبل الموعد (خلال آخر 24 ساعة وقبل أقل من ساعة من الموعد): تذكير للطرفين.
 * - قبل ساعة من الموعد: تذكير بالموعد/المكالمة.
 * - بعد الموعد + 15 دقيقة بدون تسجيل إنجاز: إشعار بعدم التنفيذ.
 *
 * @return array{pref:int,hour:int,missed:int}
 */
function appointments_runReminders() {
    global $db;
    _ensureAppointmentsTable();
    _ensureAppointmentReminderColumns();
    if (!function_exists('_notifyUser')) {
        require_once __DIR__ . '/notifications_procedures.php';
    }
    _ensureNotificationsSchema();

    $out = ['pref' => 0, 'hour' => 0, 'missed' => 0];

    // 1) تذكير «قبل الموعد» (دخلنا نافذة آخر 24 ساعة وما زال أكثر من ساعة للموعد)
    $prefRows = $db->query("
        SELECT id, title, type, appointment_date, created_by, assigned_to
        FROM appointments
        WHERE completed_at IS NULL
          AND appointment_date > DATE_ADD(NOW(), INTERVAL 60 MINUTE)
          AND NOW() >= DATE_SUB(appointment_date, INTERVAL 24 HOUR)
          AND reminder_pref_sent_at IS NULL
    ")->fetchAll(PDO::FETCH_ASSOC);

    foreach ($prefRows as $r) {
        $aid = (int) $r['id'];
        $title = $r['title'] ?? 'موعد';
        $tl = _appointmentTypeLabelAr($r['type'] ?? 'booking');
        $dt = $r['appointment_date'] ?? '';
        try {
            _notifyAppointmentParties(
                $aid,
                'تذكير: موعد سكرتارية قريب',
                "تذكير: لديك «{$title}» ({$tl}) — الموعد {$dt}.",
                !empty($r['created_by']) ? (int) $r['created_by'] : null,
                !empty($r['assigned_to']) ? (int) $r['assigned_to'] : null,
                ['reason' => 'appointment_reminder_pref']
            );
            $db->prepare('UPDATE appointments SET reminder_pref_sent_at = NOW() WHERE id = ?')->execute([$aid]);
            $out['pref']++;
        } catch (\Exception $e) {
            error_log('appointments_runReminders pref: ' . $e->getMessage());
        }
    }

    // 2) تذكير قبل ساعة من الموعد
    $hRows = $db->query("
        SELECT id, title, type, appointment_date, created_by, assigned_to
        FROM appointments
        WHERE completed_at IS NULL
          AND appointment_date > NOW()
          AND NOW() >= DATE_SUB(appointment_date, INTERVAL 1 HOUR)
          AND reminder_1h_sent_at IS NULL
    ")->fetchAll(PDO::FETCH_ASSOC);

    foreach ($hRows as $r) {
        $aid = (int) $r['id'];
        $title = $r['title'] ?? 'موعد';
        $tl = _appointmentTypeLabelAr($r['type'] ?? 'booking');
        try {
            _notifyAppointmentParties(
                $aid,
                'خلال ساعة: موعد سكرتارية',
                "خلال ساعة: «{$title}» ({$tl}) — تذكير بالموعد أو المكالمة المطلوبة.",
                !empty($r['created_by']) ? (int) $r['created_by'] : null,
                !empty($r['assigned_to']) ? (int) $r['assigned_to'] : null,
                ['reason' => 'appointment_reminder_1h']
            );
            $db->prepare('UPDATE appointments SET reminder_1h_sent_at = NOW() WHERE id = ?')->execute([$aid]);
            $out['hour']++;
        } catch (\Exception $e) {
            error_log('appointments_runReminders 1h: ' . $e->getMessage());
        }
    }

    // 3) انتهى الموعد ولم يُسجَّل إنجاز
    $missRows = $db->query("
        SELECT id, title, type, appointment_date, created_by, assigned_to
        FROM appointments
        WHERE completed_at IS NULL
          AND NOW() >= DATE_ADD(appointment_date, INTERVAL 15 MINUTE)
          AND reminder_missed_sent_at IS NULL
    ")->fetchAll(PDO::FETCH_ASSOC);

    foreach ($missRows as $r) {
        $aid = (int) $r['id'];
        $title = $r['title'] ?? 'موعد';
        $tl = _appointmentTypeLabelAr($r['type'] ?? 'booking');
        try {
            _notifyAppointmentParties(
                $aid,
                'لم يُسجَّل تنفيذ الموعد',
                "لم يُسجَّل أنك نفّذت «{$title}» ({$tl}). يرجى التحديث أو إكمال الموعد من السكرتارية.",
                !empty($r['created_by']) ? (int) $r['created_by'] : null,
                !empty($r['assigned_to']) ? (int) $r['assigned_to'] : null,
                ['reason' => 'appointment_missed']
            );
            $db->prepare('UPDATE appointments SET reminder_missed_sent_at = NOW() WHERE id = ?')->execute([$aid]);
            $out['missed']++;
        } catch (\Exception $e) {
            error_log('appointments_runReminders missed: ' . $e->getMessage());
        }
    }

    return $out;
}
