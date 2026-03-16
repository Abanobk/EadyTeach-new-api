<?php
// Simple upload endpoint for task photos / videos.
// Expects multipart/form-data with field name "file".

header('Content-Type: application/json; charset=utf-8');

// Only allow POST
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['error' => 'Method not allowed']);
    exit;
}

if (!isset($_FILES['file']) || $_FILES['file']['error'] !== UPLOAD_ERR_OK) {
    http_response_code(400);
    echo json_encode(['error' => 'No file uploaded or upload error']);
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

