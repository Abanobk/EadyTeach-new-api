<?php
/**
 * مدخل مباشر للـ tRPC بدون اعتماد على mod_rewrite.
 * الطلب: /trpc.php/auth.adminLogin أو /trpc.php?procedure=auth.adminLogin
 */
$pathInfo = $_SERVER['PATH_INFO'] ?? '';
if ($pathInfo !== '') {
    $_SERVER['REQUEST_URI'] = '/trpc/' . ltrim($pathInfo, '/');
} elseif (!empty($_GET['procedure'])) {
    $_SERVER['REQUEST_URI'] = '/trpc/' . $_GET['procedure'];
}
require __DIR__ . '/router.php';
