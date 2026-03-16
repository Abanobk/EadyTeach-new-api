<?php
// Simple upload endpoint for task photos / videos.
// Expects multipart/form-data with field name "file".

header('Content-Type: application/json; charset=utf-8');

// Allow large uploads (up to ~200MB)
@ini_set('upload_max_filesize', '200M');
@ini_set('post_max_size', '220M');
@ini_set('memory_limit', '256M');
@ini_set('max_execution_time', '300');

// Only allow POST
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['error' => 'Method not allowed']);
    exit;
}

if (!isset($_FILES['file'])) {
    http_response_code(400);
    echo json_encode(['error' => 'No file field']);
    exit;
}

// Handle PHP upload errors explicitly
if ($_FILES['file']['error'] !== UPLOAD_ERR_OK) {
    $err = 'Upload error';
    switch ($_FILES['file']['error']) {
        case UPLOAD_ERR_INI_SIZE:
        case UPLOAD_ERR_FORM_SIZE:
            $err = 'File too large (server limit reached)';
            break;
        case UPLOAD_ERR_PARTIAL:
            $err = 'Partial upload';
            break;
        case UPLOAD_ERR_NO_FILE:
            $err = 'No file sent';
            break;
        case UPLOAD_ERR_NO_TMP_DIR:
            $err = 'Missing temp directory on server';
            break;
        case UPLOAD_ERR_CANT_WRITE:
            $err = 'Failed to write file to disk';
            break;
        case UPLOAD_ERR_EXTENSION:
            $err = 'Upload blocked by PHP extension';
            break;
    }
    http_response_code(400);
    echo json_encode(['error' => $err, 'code' => $_FILES['file']['error']]);
    exit;
}

// Optional manual limit (~180MB) to avoid exhausting disk/memory accidentally
$maxBytes = 180 * 1024 * 1024;
if (!empty($_FILES['file']['size']) && $_FILES['file']['size'] > $maxBytes) {
    http_response_code(400);
    echo json_encode(['error' => 'File too large (max ~180MB). Please compress or split the video.']);
    exit;
}

$uploadDir = realpath(__DIR__ . '/../uploads');
if ($uploadDir === false) {
    $uploadDir = __DIR__ . '/../uploads';
}

if (!is_dir($uploadDir)) {
    mkdir($uploadDir, 0775, true);
}

$originalName = basename($_FILES['file']['name']);
$ext = pathinfo($originalName, PATHINFO_EXTENSION);
$safeExt = preg_replace('/[^a-zA-Z0-9]/', '', $ext);
if ($safeExt === '') {
    $safeExt = 'bin';
}

$fileName = date('Ymd_His') . '_' . bin2hex(random_bytes(4)) . '.' . $safeExt;
$targetPath = rtrim($uploadDir, DIRECTORY_SEPARATOR) . DIRECTORY_SEPARATOR . $fileName;

if (!move_uploaded_file($_FILES['file']['tmp_name'], $targetPath)) {
    http_response_code(500);
    echo json_encode(['error' => 'Failed to move uploaded file']);
    exit;
}

// Build public URL (uploads is at /uploads on the same host).
$scheme = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
$host = $_SERVER['HTTP_HOST'] ?? 'api.easytecheg.net';
$publicUrl = $scheme . '://' . $host . '/uploads/' . $fileName;

echo json_encode([
    'success' => true,
    'url' => $publicUrl,
]);

