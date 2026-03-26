<?php

/**
 * Discounts Module – per-client / per-dealer rules
 *
 * Allows defining discount rules:
 *  - target_type: client | dealer
 *  - target_id: user id of the client/dealer
 *  - scope_type: category | product | product_type
 *  - category_id / product_id / variant_name
 *  - discount_percent / discount_amount
 *  - min_stock (optional)
 */

function _ensureDiscountsSchema() {
    global $db;

    $db->exec("CREATE TABLE IF NOT EXISTS discount_rules (
        id INT AUTO_INCREMENT PRIMARY KEY,
        target_type ENUM('client','dealer') NOT NULL,
        target_id INT NOT NULL,
        scope_type ENUM('category','product','product_type') NOT NULL,
        category_id INT DEFAULT NULL,
        product_id INT DEFAULT NULL,
        variant_name VARCHAR(191) DEFAULT NULL,
        discount_percent DECIMAL(5,2) DEFAULT 0,
        discount_amount DECIMAL(12,2) DEFAULT 0,
        min_stock INT DEFAULT 0,
        is_active TINYINT(1) DEFAULT 1,
        note VARCHAR(255) DEFAULT NULL,
        created_by INT DEFAULT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_target (target_type, target_id),
        INDEX idx_scope_cat (scope_type, category_id),
        INDEX idx_scope_prod (scope_type, product_id),
        INDEX idx_scope_prod_type (scope_type, product_id, variant_name)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    // Backward-compatible upgrades for existing installations.
    try {
        $db->exec("ALTER TABLE discount_rules
                   MODIFY COLUMN scope_type ENUM('category','product','product_type') NOT NULL");
    } catch (\Throwable $e) {}
    try {
        $db->exec("ALTER TABLE discount_rules
                   ADD COLUMN variant_name VARCHAR(191) DEFAULT NULL");
    } catch (\Throwable $e) {}
    try {
        $db->exec("ALTER TABLE discount_rules
                   ADD INDEX idx_scope_prod_type (scope_type, product_id, variant_name)");
    } catch (\Throwable $e) {}
}

function _formatDiscountRule($r) {
    return [
        'id' => (int)$r['id'],
        'targetType' => $r['target_type'],
        'targetId' => (int)$r['target_id'],
        'scopeType' => $r['scope_type'],
        'categoryId' => $r['category_id'] ? (int)$r['category_id'] : null,
        'productId' => $r['product_id'] ? (int)$r['product_id'] : null,
        'variantName' => $r['variant_name'] ?? null,
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
    if (array_key_exists('variantName', $input)) {
        $v = trim((string)($input['variantName'] ?? ''));
        if ($v !== '') {
            $where[] = 'variant_name = ?';
            $params[] = $v;
        } else {
            $where[] = '(variant_name IS NULL OR variant_name = "")';
        }
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
    $scopeType = $input['scopeType'] ?? 'product'; // product | category | product_type
    $categoryId = !empty($input['categoryId']) ? (int)$input['categoryId'] : null;
    $productId = !empty($input['productId']) ? (int)$input['productId'] : null;
    $variantName = trim((string)($input['variantName'] ?? ''));
    $variantName = preg_replace('/\s+/u', ' ', $variantName);
    if ($variantName === '') $variantName = null;
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
    if ($scopeType === 'product_type') {
        if (!$productId) {
            throw new Exception('productId is required for product_type scope');
        }
        if (!$variantName) {
            throw new Exception('variantName is required for product_type scope');
        }
    }

    // Prefer percent; if zero then use amount
    if ($discountPercent < 0) $discountPercent = 0;
    if ($discountAmount < 0) $discountAmount = 0;

    if ($id > 0) {
        $stmt = $db->prepare("UPDATE discount_rules
            SET target_type = ?, target_id = ?, scope_type = ?, category_id = ?, product_id = ?, variant_name = ?,
                discount_percent = ?, discount_amount = ?, min_stock = ?, is_active = ?, note = ?
            WHERE id = ?");
        $stmt->execute([$targetType, $targetId, $scopeType, $categoryId, $productId, $variantName,
            $discountPercent, $discountAmount, $minStock, $isActive, $note, $id]);
        return ['id' => $id];
    } else {
        $stmt = $db->prepare("INSERT INTO discount_rules
            (target_type, target_id, scope_type, category_id, product_id, variant_name,
             discount_percent, discount_amount, min_stock, is_active, note, created_by)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
        $stmt->execute([$targetType, $targetId, $scopeType, $categoryId, $productId, $variantName,
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

/**
 * جلب قاعدة خصم التاجر لمنتج (نفس أولوية المنتج ثم الفئة في router).
 */
function discounts_fetchDealerRuleForProduct(PDO $db, int $dealerId, int $productId, ?int $categoryId, ?string $variantName = null): ?array {
    $variantName = trim((string)($variantName ?? ''));
    $variantName = preg_replace('/\s+/u', ' ', $variantName);
    if ($variantName !== '') {
        $stmt = $db->prepare("SELECT * FROM discount_rules
                              WHERE target_type = 'dealer' AND target_id = ? AND is_active = 1
                                AND scope_type = 'product_type' AND product_id = ?
                                AND (
                                  LOWER(TRIM(variant_name)) = LOWER(TRIM(?))
                                  OR LOWER(TRIM(variant_name)) LIKE CONCAT('%', LOWER(TRIM(?)), '%')
                                )
                              ORDER BY id DESC LIMIT 1");
        $stmt->execute([$dealerId, $productId, $variantName, $variantName]);
        $r = $stmt->fetch(PDO::FETCH_ASSOC);
        if ($r) {
            return $r;
        }
    }

    $stmt = $db->prepare("SELECT * FROM discount_rules
                          WHERE target_type = 'dealer' AND target_id = ? AND is_active = 1
                            AND scope_type = 'product' AND product_id = ?
                          ORDER BY id DESC LIMIT 1");
    $stmt->execute([$dealerId, $productId]);
    $r = $stmt->fetch(PDO::FETCH_ASSOC);
    if ($r) {
        return $r;
    }
    if ($categoryId) {
        $stmt = $db->prepare("SELECT * FROM discount_rules
                              WHERE target_type = 'dealer' AND target_id = ? AND is_active = 1
                                AND scope_type = 'category' AND category_id = ?
                              ORDER BY id DESC LIMIT 1");
        $stmt->execute([$dealerId, $categoryId]);
        $r = $stmt->fetch(PDO::FETCH_ASSOC);
        if ($r) {
            return $r;
        }
    }
    return null;
}

/**
 * تطبيق قاعدة الخصم على سعر وحدة (نفس منطق formatProduct للمستخدم).
 * @return array{finalUnitPrice: float, discountPercent: float, discountValuePerUnit: float, waitingMessage: ?string}
 */
function discounts_applyDealerRuleToUnitPrice(float $officialUnit, array $rule, int $stock): array {
    $minStock = (int)($rule['min_stock'] ?? 0);
    $percent = (float)($rule['discount_percent'] ?? 0);
    $amount = (float)($rule['discount_amount'] ?? 0);
    if ($percent < 0) {
        $percent = 0;
    }
    if ($amount < 0) {
        $amount = 0;
    }

    if ($stock === 0 || ($minStock > 0 && $stock < $minStock)) {
        $msg = $stock === 0
            ? 'كمية الصفر — خصم التاجر معلق حتى توفر المخزون'
            : "المخزون أقل من شرط الخصم ($minStock)";

        return [
            'finalUnitPrice' => $officialUnit,
            'discountPercent' => $percent,
            'discountValuePerUnit' => 0.0,
            'waitingMessage' => $msg,
        ];
    }

    $discountValue = $percent > 0 ? $officialUnit * $percent / 100.0 : $amount;
    if ($discountValue < 0) {
        $discountValue = 0;
    }
    if ($discountValue > $officialUnit) {
        $discountValue = $officialUnit;
    }

    return [
        'finalUnitPrice' => max(0.0, $officialUnit - $discountValue),
        'discountPercent' => $percent,
        'discountValuePerUnit' => $discountValue,
        'waitingMessage' => null,
    ];
}

/**
 * معاينة أسعار بنود عرض السعر بعد خصم التاجر (للواجهة قبل الحفظ).
 * input: { dealerUserId?: int, items: [{ productId, unitPrice, variantName? }] }
 */
function discounts_previewQuotationItems($input, $ctx) {
    global $db;
    _ensureDiscountsSchema();

    $dealerId = isset($input['dealerUserId']) ? (int)$input['dealerUserId'] : 0;
    $lines = $input['items'] ?? [];
    if (!is_array($lines)) {
        $lines = [];
    }

    $out = [];
    foreach ($lines as $ln) {
        if (!is_array($ln)) {
            continue;
        }
        $pid = (int)($ln['productId'] ?? 0);
        $official = (float)($ln['unitPrice'] ?? 0);
        $variantName = trim((string)($ln['variantName'] ?? ''));
        $variantName = preg_replace('/\s+/u', ' ', $variantName);
        if ($pid <= 0) {
            $out[] = [
                'productId' => $pid,
                'officialUnitPrice' => $official,
                'unitPrice' => $official,
                'dealerDiscountPercent' => 0.0,
                'dealerDiscountValuePerUnit' => 0.0,
                'dealerDiscountWaiting' => null,
            ];
            continue;
        }

        if ($dealerId <= 0) {
            $out[] = [
                'productId' => $pid,
                'officialUnitPrice' => $official,
                'unitPrice' => $official,
                'dealerDiscountPercent' => 0.0,
                'dealerDiscountValuePerUnit' => 0.0,
                'dealerDiscountWaiting' => null,
            ];
            continue;
        }

        $pStmt = $db->prepare('SELECT id, category_id, stock FROM products WHERE id = ?');
        $pStmt->execute([$pid]);
        $prow = $pStmt->fetch(PDO::FETCH_ASSOC);
        if (!$prow) {
            $out[] = [
                'productId' => $pid,
                'officialUnitPrice' => $official,
                'unitPrice' => $official,
                'dealerDiscountPercent' => 0.0,
                'dealerDiscountValuePerUnit' => 0.0,
                'dealerDiscountWaiting' => null,
            ];
            continue;
        }

        $catId = isset($prow['category_id']) ? (int)$prow['category_id'] : null;
        $stock = (int)($prow['stock'] ?? 0);
        $rule = discounts_fetchDealerRuleForProduct($db, $dealerId, $pid, $catId, $variantName);
        if (!$rule) {
            $out[] = [
                'productId' => $pid,
                'officialUnitPrice' => $official,
                'unitPrice' => $official,
                'dealerDiscountPercent' => 0.0,
                'dealerDiscountValuePerUnit' => 0.0,
                'dealerDiscountWaiting' => null,
            ];
            continue;
        }

        $applied = discounts_applyDealerRuleToUnitPrice($official, $rule, $stock);
        $out[] = [
            'productId' => $pid,
            'officialUnitPrice' => $official,
            'unitPrice' => $applied['finalUnitPrice'],
            'dealerDiscountPercent' => $applied['discountPercent'],
            'dealerDiscountValuePerUnit' => $applied['discountValuePerUnit'],
            'dealerDiscountWaiting' => $applied['waitingMessage'],
        ];
    }

    return ['items' => $out];
}

