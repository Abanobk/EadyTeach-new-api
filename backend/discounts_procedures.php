<?php

/**
 * Discounts Module – per-client / per-dealer rules
 *
 * Allows defining discount rules:
 *  - target_type: client | dealer
 *  - target_id: user id of the client/dealer
 *  - scope_type: category | product
 *  - category_id / product_id
 *  - discount_percent / discount_amount
 *  - min_stock (optional)
 */

function _ensureDiscountsSchema() {
    global $db;

    $db->exec("CREATE TABLE IF NOT EXISTS discount_rules (
        id INT AUTO_INCREMENT PRIMARY KEY,
        target_type ENUM('client','dealer') NOT NULL,
        target_id INT NOT NULL,
        scope_type ENUM('category','product') NOT NULL,
        category_id INT DEFAULT NULL,
        product_id INT DEFAULT NULL,
        discount_percent DECIMAL(5,2) DEFAULT 0,
        discount_amount DECIMAL(12,2) DEFAULT 0,
        min_stock INT DEFAULT 0,
        is_active TINYINT(1) DEFAULT 1,
        note VARCHAR(255) DEFAULT NULL,
        created_by INT DEFAULT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_target (target_type, target_id),
        INDEX idx_scope_cat (scope_type, category_id),
        INDEX idx_scope_prod (scope_type, product_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
}

function _formatDiscountRule($r) {
    return [
        'id' => (int)$r['id'],
        'targetType' => $r['target_type'],
        'targetId' => (int)$r['target_id'],
        'scopeType' => $r['scope_type'],
        'categoryId' => $r['category_id'] ? (int)$r['category_id'] : null,
        'productId' => $r['product_id'] ? (int)$r['product_id'] : null,
        'discountPercent' => (float)$r['discount_percent'],
        'discountAmount' => (float)$r['discount_amount'],
        'minStock' => (int)$r['min_stock'],
        'isActive' => (bool)$r['is_active'],
        'note' => $r['note'] ?? null,
        'createdBy' => $r['created_by'] ? (int)$r['created_by'] : null,
        'createdAt' => $r['created_at'] ?? null,
    ];
}

// ─── discounts.listRules ─────────────────────────────────────────
function discounts_listRules($input, $ctx) {
    global $db;
    _ensureDiscountsSchema();

    $where = [];
    $params = [];

    if (!empty($input['targetType'])) {
        $where[] = 'target_type = ?';
        $params[] = $input['targetType'];
    }
    if (!empty($input['targetId'])) {
        $where[] = 'target_id = ?';
        $params[] = (int)$input['targetId'];
    }
    if (!empty($input['scopeType'])) {
        $where[] = 'scope_type = ?';
        $params[] = $input['scopeType'];
    }
    if (!empty($input['categoryId'])) {
        $where[] = 'category_id = ?';
        $params[] = (int)$input['categoryId'];
    }
    if (!empty($input['productId'])) {
        $where[] = 'product_id = ?';
        $params[] = (int)$input['productId'];
    }
    if (isset($input['isActive'])) {
        $where[] = 'is_active = ?';
        $params[] = $input['isActive'] ? 1 : 0;
    }

    $sql = "SELECT * FROM discount_rules";
    if ($where) $sql .= ' WHERE ' . implode(' AND ', $where);
    $sql .= ' ORDER BY created_at DESC, id DESC';

    $stmt = $db->prepare($sql);
    $stmt->execute($params);
    $rows = $stmt->fetchAll();
    return array_map('_formatDiscountRule', $rows);
}

// ─── discounts.saveRule ──────────────────────────────────────────
function discounts_saveRule($input, $ctx) {
    global $db;
    _ensureDiscountsSchema();

    $id = isset($input['id']) ? (int)$input['id'] : 0;
    $targetType = $input['targetType'] ?? 'client'; // client | dealer
    $targetId = (int)($input['targetId'] ?? 0);
    $scopeType = $input['scopeType'] ?? 'product'; // product | category
    $categoryId = !empty($input['categoryId']) ? (int)$input['categoryId'] : null;
    $productId = !empty($input['productId']) ? (int)$input['productId'] : null;
    $discountPercent = (float)($input['discountPercent'] ?? 0);
    $discountAmount = (float)($input['discountAmount'] ?? 0);
    $minStock = (int)($input['minStock'] ?? 0);
    $isActive = isset($input['isActive']) ? (int)($input['isActive'] ? 1 : 0) : 1;
    $note = $input['note'] ?? null;
    $createdBy = $ctx['userId'] ?? null;

    if ($targetId <= 0) {
        throw new Exception('targetId is required');
    }
    if ($scopeType === 'category' && !$categoryId) {
        throw new Exception('categoryId is required for category scope');
    }
    if ($scopeType === 'product' && !$productId) {
        throw new Exception('productId is required for product scope');
    }

    // Prefer percent; if zero then use amount
    if ($discountPercent < 0) $discountPercent = 0;
    if ($discountAmount < 0) $discountAmount = 0;

    if ($id > 0) {
        $stmt = $db->prepare("UPDATE discount_rules
            SET target_type = ?, target_id = ?, scope_type = ?, category_id = ?, product_id = ?,
                discount_percent = ?, discount_amount = ?, min_stock = ?, is_active = ?, note = ?
            WHERE id = ?");
        $stmt->execute([$targetType, $targetId, $scopeType, $categoryId, $productId,
            $discountPercent, $discountAmount, $minStock, $isActive, $note, $id]);
        return ['id' => $id];
    } else {
        $stmt = $db->prepare("INSERT INTO discount_rules
            (target_type, target_id, scope_type, category_id, product_id,
             discount_percent, discount_amount, min_stock, is_active, note, created_by)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
        $stmt->execute([$targetType, $targetId, $scopeType, $categoryId, $productId,
            $discountPercent, $discountAmount, $minStock, $isActive, $note, $createdBy]);
        return ['id' => (int)$db->lastInsertId()];
    }
}

// ─── discounts.deleteRule ────────────────────────────────────────
function discounts_deleteRule($input, $ctx) {
    global $db;
    _ensureDiscountsSchema();

    $id = (int)($input['id'] ?? 0);
    if ($id <= 0) throw new Exception('Invalid id');

    $stmt = $db->prepare("DELETE FROM discount_rules WHERE id = ?");
    $stmt->execute([$id]);
    return ['success' => true];
}

