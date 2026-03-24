<?php
/**
 * Permissions Module – إدارة الصلاحيات والأدوار
 *
 * Tables:
 *   roles             – الأدوار (admin, technician, accountant, ...)
 *   role_permissions   – صلاحيات كل دور
 *
 * Permission keys follow: module.action pattern
 */

function _ensurePermissionsSchema() {
    global $db;

    $db->exec("CREATE TABLE IF NOT EXISTS roles (
        id INT AUTO_INCREMENT PRIMARY KEY,
        slug VARCHAR(50) NOT NULL UNIQUE,
        name VARCHAR(100) NOT NULL,
        name_ar VARCHAR(100) NOT NULL,
        description TEXT DEFAULT NULL,
        color VARCHAR(20) DEFAULT '#607D8B',
        icon VARCHAR(50) DEFAULT 'person',
        is_system BOOLEAN DEFAULT FALSE,
        is_active BOOLEAN DEFAULT TRUE,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    $db->exec("CREATE TABLE IF NOT EXISTS role_permissions (
        id INT AUTO_INCREMENT PRIMARY KEY,
        role_id INT NOT NULL,
        permission_key VARCHAR(100) NOT NULL,
        UNIQUE KEY uniq_role_perm (role_id, permission_key),
        FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    // Seed default roles
    $cnt = (int)$db->query("SELECT COUNT(*) FROM roles")->fetchColumn();
    if ($cnt == 0) {
        $db->exec("INSERT INTO roles (slug, name, name_ar, description, color, icon, is_system) VALUES
            ('admin', 'Admin', 'مسؤول', 'صلاحيات كاملة على النظام', '#F44336', 'admin_panel_settings', TRUE),
            ('staff', 'Staff', 'موظف', 'موظف بصلاحيات محدودة', '#2196F3', 'badge', TRUE),
            ('technician', 'Technician', 'فني', 'إدارة المهام والطلبات المسندة', '#FF9800', 'build', TRUE),
            ('supervisor', 'Supervisor', 'مشرف', 'مشرف على الفنيين والمهام', '#9C27B0', 'supervisor_account', TRUE),
            ('user', 'Client', 'عميل', 'تصفح المنتجات وإنشاء الطلبات', '#4CAF50', 'person', TRUE)
        ");

        // Give admin all permissions
        $adminId = $db->query("SELECT id FROM roles WHERE slug = 'admin'")->fetchColumn();
        if ($adminId) {
            $allPerms = _getAllPermissionKeys();
            $stmt = $db->prepare("INSERT INTO role_permissions (role_id, permission_key) VALUES (?, ?)");
            foreach ($allPerms as $key) {
                $stmt->execute([$adminId, $key]);
            }
        }

        // Give staff some default permissions
        $staffId = $db->query("SELECT id FROM roles WHERE slug = 'staff'")->fetchColumn();
        if ($staffId) {
            $staffPerms = [
                'dashboard.view',
                'orders.view', 'orders.create', 'orders.edit',
                'customers.view',
                'tasks.view', 'tasks.create', 'tasks.edit',
                'quotations.view', 'quotations.create',
                'reports.view',
            ];
            $stmt = $db->prepare("INSERT INTO role_permissions (role_id, permission_key) VALUES (?, ?)");
            foreach ($staffPerms as $key) {
                $stmt->execute([$staffId, $key]);
            }
        }

        // Give supervisor default permissions (لوحة التحكم، المهام، التقارير، إلخ)
        $supervisorId = $db->query("SELECT id FROM roles WHERE slug = 'supervisor'")->fetchColumn();
        if ($supervisorId) {
            $supervisorPerms = [
                'dashboard.view',
                'orders.view', 'orders.edit',
                'customers.view',
                'tasks.view', 'tasks.create', 'tasks.edit', 'tasks.assign',
                'quotations.view', 'quotations.create',
                'reports.view',
            ];
            $stmt = $db->prepare("INSERT INTO role_permissions (role_id, permission_key) VALUES (?, ?)");
            foreach ($supervisorPerms as $key) {
                $stmt->execute([$supervisorId, $key]);
            }
        }
    }

    // migration: تأكد أن المشرف لديه reports.view (للإعدادات القديمة قبل إضافة صلاحيات المشرف)
    try {
        $supervisorId = $db->query("SELECT id FROM roles WHERE slug = 'supervisor'")->fetchColumn();
        if ($supervisorId) {
            $has = $db->prepare("SELECT 1 FROM role_permissions rp JOIN roles r ON r.id = rp.role_id WHERE r.slug = 'supervisor' AND rp.permission_key = 'reports.view'");
            $has->execute();
            if (!$has->fetch()) {
                $db->prepare("INSERT INTO role_permissions (role_id, permission_key) VALUES (?, 'reports.view')")->execute([$supervisorId]);
            }
        }
    } catch (\Exception $e) { /* ignore */ }
}

function _getAllPermissionKeys() {
    return [
        'dashboard.view',
        'orders.view', 'orders.create', 'orders.edit', 'orders.delete',
        'customers.view', 'customers.create', 'customers.edit', 'customers.delete', 'customers.change_role',
        'products.view', 'products.create', 'products.edit', 'products.delete',
        'categories.view', 'categories.create', 'categories.edit', 'categories.delete',
        'tasks.view', 'tasks.create', 'tasks.edit', 'tasks.delete', 'tasks.assign',
        'quotations.view', 'quotations.create', 'quotations.edit', 'quotations.delete', 'quotations.send',
        'accounting.view', 'accounting.create', 'accounting.approve', 'accounting.delete',
        'crm.view', 'crm.create', 'crm.edit', 'crm.delete', 'crm.assign',
        'inbox.view', 'inbox.reply',
        'notifications.view', 'notifications.send',
        'secretary.view', 'secretary.create', 'secretary.delete',
        'reports.view', 'reports.export',
        'surveys.view', 'surveys.create', 'surveys.delete',
        'permissions.view', 'permissions.manage',
    ];
}

function _getPermissionModules() {
    return [
        'dashboard' => [
            'label' => 'لوحة التحكم',
            'icon' => 'dashboard',
            'actions' => [
                'view' => 'عرض لوحة التحكم',
            ],
        ],
        'orders' => [
            'label' => 'الطلبات',
            'icon' => 'shopping_cart',
            'actions' => [
                'view' => 'عرض الطلبات',
                'create' => 'إنشاء طلب',
                'edit' => 'تعديل طلب',
                'delete' => 'حذف طلب',
            ],
        ],
        'customers' => [
            'label' => 'العملاء والمستخدمين',
            'icon' => 'people',
            'actions' => [
                'view' => 'عرض العملاء',
                'create' => 'إضافة عميل',
                'edit' => 'تعديل بيانات عميل',
                'delete' => 'حذف عميل',
                'change_role' => 'تغيير دور المستخدم',
            ],
        ],
        'products' => [
            'label' => 'المنتجات',
            'icon' => 'inventory',
            'actions' => [
                'view' => 'عرض المنتجات',
                'create' => 'إضافة منتج',
                'edit' => 'تعديل منتج',
                'delete' => 'حذف منتج',
            ],
        ],
        'categories' => [
            'label' => 'الفئات',
            'icon' => 'category',
            'actions' => [
                'view' => 'عرض الفئات',
                'create' => 'إضافة فئة',
                'edit' => 'تعديل فئة',
                'delete' => 'حذف فئة',
            ],
        ],
        'tasks' => [
            'label' => 'المهام',
            'icon' => 'task',
            'actions' => [
                'view' => 'عرض المهام',
                'create' => 'إنشاء مهمة',
                'edit' => 'تعديل مهمة',
                'delete' => 'حذف مهمة',
                'assign' => 'تعيين فني للمهمة',
            ],
        ],
        'quotations' => [
            'label' => 'عروض الأسعار',
            'icon' => 'request_quote',
            'actions' => [
                'view' => 'عرض العروض',
                'create' => 'إنشاء عرض',
                'edit' => 'تعديل عرض',
                'delete' => 'حذف عرض',
                'send' => 'إرسال عرض للعميل',
            ],
        ],
        'discounts' => [
            'label' => 'الخصومات الخاصة',
            'icon' => 'percent',
            'actions' => [
                'view' => 'عرض قواعد الخصم',
                'create' => 'إضافة قاعدة خصم',
                'edit' => 'تعديل قاعدة خصم',
                'delete' => 'حذف قاعدة خصم',
            ],
        ],
        'accounting' => [
            'label' => 'الحسابات والعهد',
            'icon' => 'account_balance_wallet',
            'actions' => [
                'view' => 'عرض الحسابات',
                'create' => 'إنشاء حركة مالية',
                'approve' => 'اعتماد المصروفات',
                'delete' => 'حذف حركة',
            ],
        ],
        'crm' => [
            'label' => 'إدارة العملاء (CRM)',
            'icon' => 'handshake',
            'actions' => [
                'view' => 'عرض العملاء المحتملين',
                'create' => 'إضافة عميل محتمل',
                'edit' => 'تعديل بيانات',
                'delete' => 'حذف عميل محتمل',
                'assign' => 'تعيين مسؤول',
            ],
        ],
        'inbox' => [
            'label' => 'الرسائل',
            'icon' => 'message',
            'actions' => [
                'view' => 'عرض الرسائل',
                'reply' => 'الرد على الرسائل',
            ],
        ],
        'notifications' => [
            'label' => 'الإشعارات',
            'icon' => 'notifications',
            'actions' => [
                'view' => 'عرض الإشعارات',
                'send' => 'إرسال إشعار',
            ],
        ],
        'secretary' => [
            'label' => 'السكرتارية',
            'icon' => 'calendar_month',
            'actions' => [
                'view' => 'عرض المواعيد',
                'create' => 'إضافة موعد',
                'delete' => 'حذف موعد',
            ],
        ],
        'reports' => [
            'label' => 'التقارير',
            'icon' => 'bar_chart',
            'actions' => [
                'view' => 'عرض التقارير',
                'export' => 'تصدير التقارير',
            ],
        ],
        'surveys' => [
            'label' => 'الاستبيانات',
            'icon' => 'poll',
            'actions' => [
                'view' => 'عرض الاستبيانات',
                'create' => 'إنشاء استبيان',
                'delete' => 'حذف استبيان',
            ],
        ],
        'permissions' => [
            'label' => 'الصلاحيات',
            'icon' => 'admin_panel_settings',
            'actions' => [
                'view' => 'عرض الصلاحيات',
                'manage' => 'إدارة الأدوار والصلاحيات',
            ],
        ],
    ];
}

// ─── permissions.getRoles ──────────────────────────────────────
function perm_getRoles($input, $ctx) {
    global $db;
    _ensurePermissionsSchema();

    $rows = $db->query("SELECT r.*, COUNT(rp.id) as perm_count,
            (SELECT COUNT(*) FROM users u WHERE u.role = r.slug) as user_count
        FROM roles r
        LEFT JOIN role_permissions rp ON rp.role_id = r.id
        GROUP BY r.id
        ORDER BY r.is_system DESC, r.name_ar")->fetchAll();

    return array_map(function($r) {
        return [
            'id' => (int)$r['id'],
            'slug' => $r['slug'],
            'name' => $r['name'],
            'nameAr' => $r['name_ar'],
            'description' => $r['description'],
            'color' => $r['color'],
            'icon' => $r['icon'],
            'isSystem' => (bool)$r['is_system'],
            'isActive' => (bool)$r['is_active'],
            'permCount' => (int)$r['perm_count'],
            'userCount' => (int)$r['user_count'],
            'createdAt' => $r['created_at'],
        ];
    }, $rows);
}

// ─── permissions.createRole ────────────────────────────────────
function perm_createRole($input, $ctx) {
    global $db;
    _ensurePermissionsSchema();

    $slug = preg_replace('/[^a-z0-9_]/', '', strtolower($input['slug'] ?? ''));
    $name = $input['name'] ?? '';
    $nameAr = $input['nameAr'] ?? '';
    $description = $input['description'] ?? '';
    $color = $input['color'] ?? '#607D8B';
    $icon = $input['icon'] ?? 'person';

    if (empty($slug) || empty($nameAr)) {
        throw new Exception('الاسم والمعرف مطلوبان');
    }

    $exists = $db->prepare("SELECT COUNT(*) FROM roles WHERE slug = ?");
    $exists->execute([$slug]);
    if ($exists->fetchColumn() > 0) {
        throw new Exception('هذا المعرف مستخدم بالفعل');
    }

    $stmt = $db->prepare("INSERT INTO roles (slug, name, name_ar, description, color, icon, is_system)
        VALUES (?, ?, ?, ?, ?, ?, FALSE)");
    $stmt->execute([$slug, $name, $nameAr, $description, $color, $icon]);

    return ['id' => (int)$db->lastInsertId()];
}

// ─── permissions.updateRole ────────────────────────────────────
function perm_updateRole($input, $ctx) {
    global $db;
    _ensurePermissionsSchema();

    $id = (int)($input['id'] ?? 0);
    $nameAr = $input['nameAr'] ?? null;
    $description = $input['description'] ?? null;
    $color = $input['color'] ?? null;
    $icon = $input['icon'] ?? null;

    $sets = [];
    $params = [];

    if ($nameAr !== null) { $sets[] = 'name_ar = ?'; $params[] = $nameAr; }
    if ($description !== null) { $sets[] = 'description = ?'; $params[] = $description; }
    if ($color !== null) { $sets[] = 'color = ?'; $params[] = $color; }
    if ($icon !== null) { $sets[] = 'icon = ?'; $params[] = $icon; }
    if (isset($input['isActive'])) { $sets[] = 'is_active = ?'; $params[] = $input['isActive'] ? 1 : 0; }

    if (empty($sets)) return ['success' => true];

    $params[] = $id;
    $db->prepare("UPDATE roles SET " . implode(', ', $sets) . " WHERE id = ?")->execute($params);
    return ['success' => true];
}

// ─── permissions.deleteRole ────────────────────────────────────
function perm_deleteRole($input, $ctx) {
    global $db;
    _ensurePermissionsSchema();

    $id = (int)($input['id'] ?? 0);

    $role = $db->prepare("SELECT is_system, slug FROM roles WHERE id = ?");
    $role->execute([$id]);
    $r = $role->fetch();
    if (!$r) throw new Exception('الدور غير موجود');
    if ($r['is_system']) throw new Exception('لا يمكن حذف الأدوار الأساسية');

    $userCount = $db->prepare("SELECT COUNT(*) FROM users WHERE role = ?");
    $userCount->execute([$r['slug']]);
    if ($userCount->fetchColumn() > 0) {
        throw new Exception('لا يمكن حذف الدور لأنه مرتبط بمستخدمين');
    }

    $db->prepare("DELETE FROM roles WHERE id = ?")->execute([$id]);
    return ['success' => true];
}

// ─── permissions.getRolePermissions ────────────────────────────
function perm_getRolePermissions($input, $ctx) {
    global $db;
    _ensurePermissionsSchema();

    $roleId = (int)($input['roleId'] ?? 0);
    $stmt = $db->prepare("SELECT permission_key FROM role_permissions WHERE role_id = ?");
    $stmt->execute([$roleId]);
    return array_column($stmt->fetchAll(), 'permission_key');
}

// ─── permissions.updateRolePermissions ─────────────────────────
function perm_updateRolePermissions($input, $ctx) {
    global $db;
    _ensurePermissionsSchema();

    $roleId = (int)($input['roleId'] ?? 0);
    $permissions = $input['permissions'] ?? [];

    $role = $db->prepare("SELECT slug FROM roles WHERE id = ?");
    $role->execute([$roleId]);
    $r = $role->fetch();
    if ($r && $r['slug'] === 'admin') {
        throw new Exception('لا يمكن تعديل صلاحيات المسؤول - لديه كل الصلاحيات تلقائياً');
    }

    $db->prepare("DELETE FROM role_permissions WHERE role_id = ?")->execute([$roleId]);

    $validKeys = _getAllPermissionKeys();
    $stmt = $db->prepare("INSERT INTO role_permissions (role_id, permission_key) VALUES (?, ?)");
    foreach ($permissions as $key) {
        if (in_array($key, $validKeys)) {
            $stmt->execute([$roleId, $key]);
        }
    }

    return ['success' => true, 'count' => count($permissions)];
}

// ─── permissions.getAllPermissions ──────────────────────────────
function perm_getAllPermissions($input, $ctx) {
    _ensurePermissionsSchema();
    return _getPermissionModules();
}

// ─── permissions.getUserPermissions ────────────────────────────
function perm_getUserPermissions($input, $ctx) {
    global $db;
    _ensurePermissionsSchema();

    $userId = (int)($input['userId'] ?? $ctx['userId'] ?? 0);

    $userStmt = $db->prepare("SELECT role FROM users WHERE id = ?");
    $userStmt->execute([$userId]);
    $userRow = $userStmt->fetch();
    if (!$userRow) return ['role' => null, 'permissions' => []];

    $roleSlug = $userRow['role'];

    if ($roleSlug === 'admin') {
        return ['role' => 'admin', 'permissions' => _getAllPermissionKeys()];
    }

    $stmt = $db->prepare("SELECT rp.permission_key
        FROM role_permissions rp
        JOIN roles r ON r.id = rp.role_id
        WHERE r.slug = ? AND r.is_active = TRUE");
    $stmt->execute([$roleSlug]);
    $perms = array_column($stmt->fetchAll(), 'permission_key');

    return ['role' => $roleSlug, 'permissions' => $perms];
}

// ─── permissions.getUsers ──────────────────────────────────────
function perm_getUsers($input, $ctx) {
    global $db;
    _ensurePermissionsSchema();

    $filter = $input['role'] ?? null;

    $sql = "SELECT u.id, u.name, u.email, u.role, u.is_active, u.phone,
                   r.name_ar as role_name_ar, r.color as role_color
            FROM users u
            LEFT JOIN roles r ON r.slug = u.role";
    $params = [];

    if ($filter) {
        $sql .= " WHERE u.role = ?";
        $params[] = $filter;
    }
    $sql .= " ORDER BY u.name";

    $stmt = $db->prepare($sql);
    $stmt->execute($params);
    return array_map(function($r) {
        return [
            'id' => (int)$r['id'],
            'name' => $r['name'],
            'email' => $r['email'],
            'role' => $r['role'],
            'roleNameAr' => $r['role_name_ar'] ?? $r['role'],
            'roleColor' => $r['role_color'] ?? '#607D8B',
            'isActive' => (bool)($r['is_active'] ?? true),
            'phone' => $r['phone'] ?? null,
        ];
    }, $stmt->fetchAll());
}

// ─── permissions.assignRole ────────────────────────────────────
function perm_assignRole($input, $ctx) {
    global $db;
    _ensurePermissionsSchema();

    $userId = (int)($input['userId'] ?? 0);
    $roleSlug = $input['role'] ?? '';

    $roleExists = $db->prepare("SELECT COUNT(*) FROM roles WHERE slug = ? AND is_active = TRUE");
    $roleExists->execute([$roleSlug]);
    if ($roleExists->fetchColumn() == 0) {
        throw new Exception('الدور غير موجود أو غير نشط');
    }

    $db->prepare("UPDATE users SET role = ? WHERE id = ?")->execute([$roleSlug, $userId]);
    return ['success' => true];
}
