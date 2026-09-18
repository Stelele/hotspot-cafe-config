<?php
// Njeremoto usage lookup (UNTRACKED in rdcore git). Same-origin only.
// GET ?ip=192.168.88.x -> open radacct session (or empty: caller shows login).
declare(strict_types=1);
header('Content-Type: application/json');

$allowedOrigin = 'https://radius.giftmugweni.com';
$origin = $_SERVER['HTTP_ORIGIN'] ?? '';
$referer = $_SERVER['HTTP_REFERER'] ?? '';
// Browser top-level GET navigations send no Origin; allow same-host referer or empty.
if ($origin !== '' && $origin !== $allowedOrigin) { http_response_code(403); echo json_encode(['ok' => false]); exit; }
if ($origin === '' && $referer !== '' && !str_starts_with($referer, $allowedOrigin . '/')) {
    http_response_code(403); echo json_encode(['ok' => false]); exit;
}

$ip = urldecode((string)($_GET['ip'] ?? ''));
if (!filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4) || !str_starts_with($ip, '192.168.88.')) {
    echo json_encode(['ok' => true, 'session' => null]); exit;
}

// Rate limit: 30/min per source (best-effort, file-based).
$srcIp = $_SERVER['HTTP_CF_CONNECTING_IP'] ?? $_SERVER['REMOTE_ADDR'] ?? 'unknown';
$rlDir = sys_get_temp_dir() . '/rd-usage';
if (!is_dir($rlDir)) { @mkdir($rlDir, 0700, true); }
$rlFile = $rlDir . '/' . preg_replace('/[^A-Za-z0-9.:_-]/', '_', (string)$srcIp) . '.count';
$now = time(); $hits = [];
if (is_file($rlFile)) {
    $hits = array_filter(array_map('intval', explode(',', (string)file_get_contents($rlFile))), fn($t) => ($now - $t) < 60);
}
if (count($hits) >= 30) { http_response_code(429); echo json_encode(['ok' => false]); exit; }
$hits[] = $now;
@file_put_contents($rlFile, implode(',', $hits), LOCK_EX);

try {
    // Secret via php-fpm env only (zz-njeremoto.conf) — never in code or repo.
    $dbPass = getenv('RD_DB_PASS');
    if (!$dbPass) { throw new RuntimeException('db env missing'); }
    $db = new PDO('mysql:host=localhost;dbname=rd;charset=utf8mb4', 'rd', $dbPass, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
} catch (\Throwable $e) {
    error_log('[njeremoto-usage] db connect failed');
    echo json_encode(['ok' => true, 'session' => null]); exit;
}

try {
    $st = $db->prepare("SELECT username, acctstarttime, acctsessiontime, acctinputoctets, acctoutputoctets, acctupdatetime FROM radacct WHERE framedipaddress = :ip AND acctstoptime IS NULL ORDER BY acctstarttime DESC LIMIT 1");
    $st->execute([':ip' => $ip]);
    $row = $st->fetch(PDO::FETCH_ASSOC);
    if (!$row) { echo json_encode(['ok' => true, 'session' => null]); exit; }
    $start = strtotime($row['acctstarttime'] ?: 'now');
    $upd = strtotime($row['acctupdatetime'] ?: 'now');
    echo json_encode(['ok' => true, 'session' => [
        'username' => $row['username'],
        // Prefer live clock over interim counters (interim updates land every 10m).
        'online_seconds' => max(0, $now - $start),
        'bytes_in' => (int)$row['acctinputoctets'],
        'bytes_out' => (int)$row['acctoutputoctets'],
        'stale' => ($now - $upd) > 600,
    ]]);
} catch (\Throwable $e) {
    error_log('[njeremoto-usage] query failed');
    echo json_encode(['ok' => true, 'session' => null]);
}
