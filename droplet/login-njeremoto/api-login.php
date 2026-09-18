<?php
// Njeremoto portal server-side login endpoint (UNTRACKED in rdcore git).
// Browser (https, same origin) -> here -> RouterOS API over WG -> RADIUS.
// Never touched by upstream pulls. Secret comes from php-fpm env, never disk/webroot.
declare(strict_types=1);
header('Content-Type: application/json');

function fail(string $public, int $code = 200, string $priv = ''): void {
    if ($priv !== '') { error_log('[njeremoto-login] ' . $priv); }
    http_response_code($code);
    echo json_encode(['ok' => false, 'error' => $public]);
    exit;
}

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') { fail('Method not allowed.', 405); }

// Same-origin only.
$origin = $_SERVER['HTTP_ORIGIN'] ?? '';
$referer = $_SERVER['HTTP_REFERER'] ?? '';
$allowedOrigin = 'https://radius.giftmugweni.com';
$okOrigin = ($origin === $allowedOrigin) || ($origin === '' && str_starts_with($referer, $allowedOrigin . '/'));
if (!$okOrigin) { fail('Forbidden.', 403, 'origin check failed'); }

$in = json_decode(file_get_contents('php://input'), true);
if (!is_array($in)) { fail('Bad request.', 400); }
$user = substr((string)($in['user'] ?? ''), 0, 64);
$pass = substr((string)($in['pass'] ?? ''), 0, 128);
$ip = (string)($in['ip'] ?? '');
$mac = strtoupper((string)($in['mac'] ?? ''));

if (!preg_match('/^[A-Za-z0-9_.@+-]{1,64}$/', $user)) { fail('Invalid voucher or username/password.'); }
if ($pass === '' || preg_match('/[\x00-\x1F\x7F]/', $pass)) { fail('Invalid voucher or username/password.'); }
if (!filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4) || !str_starts_with($ip, '192.168.88.')) {
    fail('Invalid voucher or username/password.', 200, 'bad client ip');
}
if (!preg_match('/^([0-9A-F]{2}:){5}[0-9A-F]{2}$/', $mac)) { fail('Invalid voucher or username/password.', 200, 'bad mac'); }

// Rate limit: 10 attempts/min per source IP (best-effort, file-based).
$srcIp = $_SERVER['HTTP_CF_CONNECTING_IP'] ?? $_SERVER['REMOTE_ADDR'] ?? 'unknown';
$rlDir = sys_get_temp_dir() . '/rd-login';
if (!is_dir($rlDir)) { @mkdir($rlDir, 0700, true); }
$rlFile = $rlDir . '/' . preg_replace('/[^A-Za-z0-9.:_-]/', '_', (string)$srcIp) . '.count';
$now = time();
$window = 60; $limit = 10;
$hits = [];
if (is_file($rlFile)) {
    $hits = array_filter(
        array_map('intval', explode(',', (string)file_get_contents($rlFile))),
        fn($t) => ($now - $t) < $window
    );
}
if (count($hits) >= $limit) { fail('Too many attempts. Please wait a minute and try again.', 429, 'rate limited ' . $srcIp); }
$hits[] = $now;
@file_put_contents($rlFile, implode(',', $hits), LOCK_EX);

$apiPass = getenv('HOTSPOT_API_PASS');
if (!$apiPass) { fail('Login service unavailable.', 500, 'HOTSPOT_API_PASS env missing'); }

$autoload = '/var/www/rdcore/cake4/rd_cake/vendor/autoload.php';
if (!is_file($autoload)) { fail('Login service unavailable.', 500, 'vendor autoload missing'); }
require $autoload;

try {
    $client = new \RouterOS\Client([
        'host' => '10.10.10.2', 'user' => 'hotspot-api', 'pass' => $apiPass,
        'port' => 8728, 'timeout' => 8,
    ]);
    $q = (new \RouterOS\Query('/ip/hotspot/active/login'))
        ->equal('user', $user)
        ->equal('password', $pass)
        ->equal('ip', $ip)
        ->equal('mac-address', $mac);
    $res = $client->query($q)->read();
    $arr = $res instanceof \Traversable ? iterator_to_array($res) : (array)$res;
    $trap = '';
    array_walk_recursive($arr, function ($v, $k) use (&$trap) {
        if (is_string($v) && (str_contains($v, 'failure') || str_contains($v, 'invalid') || str_contains($v, 'reject'))) { $trap = $v; }
    });
    if ($trap !== '') {
        fail('Invalid voucher or username/password.', 200, 'router trap for ' . $ip . ': ' . $trap);
    }
    echo json_encode(['ok' => true]);
} catch (\Throwable $e) {
    fail('Invalid voucher or username/password.', 200, 'api exception for ' . $ip . ': ' . get_class($e));
}
