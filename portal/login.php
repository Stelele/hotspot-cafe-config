<?php
session_start();

$radius_server = '127.0.0.1';
$radius_port = 1812;
$radius_secret = getenv('RADIUS_SECRET') ?: 'v4.fgjBQEBTqpejX-Nfk';
$cudy_gateway = '192.168.10.1';

$error = '';
$username = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $username = trim($_POST['username'] ?? '');
    $password = trim($_POST['password'] ?? '');

    if ($username && $password) {
        $radtest_cmd = sprintf(
            'radtest %s %s %s %d %s 2>&1',
            escapeshellarg($username),
            escapeshellarg($password),
            escapeshellarg($radius_server),
            $radius_port,
            escapeshellarg($radius_secret)
        );

        $output = shell_exec($radtest_cmd);

        if (strpos($output, 'Access-Accept') !== false) {
            // Authentication successful - redirect to Cudy success URL
            $mac = $_SERVER['HTTP_X_FORWARDED_FOR'] ?? $_SERVER['REMOTE_ADDR'] ?? '';
            $success_url = sprintf(
                'http://%s/cgi-bin/luci/admin/network/captive_portal/login_success?username=%s&mac=%s',
                $cudy_gateway,
                urlencode($username),
                urlencode($mac)
            );
            header('Location: ' . $success_url);
            exit;
        } else {
            $error = 'Invalid username or password';
        }
    } else {
        $error = 'Please enter both username and password';
    }
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>WiFi Login - Njeremoto Internet Cafe</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }
        .login-card {
            background: white;
            border-radius: 16px;
            padding: 40px 32px;
            width: 100%;
            max-width: 400px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
        }
        .logo {
            text-align: center;
            margin-bottom: 32px;
        }
        .logo h1 {
            font-size: 24px;
            color: #333;
            margin-bottom: 8px;
        }
        .logo p {
            color: #666;
            font-size: 14px;
        }
        .form-group {
            margin-bottom: 20px;
        }
        .form-group label {
            display: block;
            margin-bottom: 8px;
            font-weight: 500;
            color: #333;
            font-size: 14px;
        }
        .form-group input {
            width: 100%;
            padding: 12px 16px;
            border: 2px solid #e0e0e0;
            border-radius: 8px;
            font-size: 16px;
            transition: border-color 0.2s;
        }
        .form-group input:focus {
            outline: none;
            border-color: #667eea;
        }
        .btn-login {
            width: 100%;
            padding: 14px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            border-radius: 8px;
            font-size: 16px;
            font-weight: 600;
            cursor: pointer;
            transition: transform 0.2s, box-shadow 0.2s;
        }
        .btn-login:hover {
            transform: translateY(-2px);
            box-shadow: 0 4px 12px rgba(102, 126, 234, 0.4);
        }
        .error {
            background: #fee;
            color: #c00;
            padding: 12px;
            border-radius: 8px;
            margin-bottom: 20px;
            font-size: 14px;
            text-align: center;
        }
        .footer {
            text-align: center;
            margin-top: 24px;
            color: #999;
            font-size: 12px;
        }
    </style>
</head>
<body>
    <div class="login-card">
        <div class="logo">
            <h1>Njeremoto Internet Cafe</h1>
            <p>Enter your credentials to connect</p>
        </div>

        <?php if ($error): ?>
            <div class="error"><?= htmlspecialchars($error) ?></div>
        <?php endif; ?>

        <form method="POST" action="">
            <div class="form-group">
                <label for="username">Username</label>
                <input type="text" id="username" name="username" value="<?= htmlspecialchars($username) ?>" required autocomplete="username">
            </div>
            <div class="form-group">
                <label for="password">Password</label>
                <input type="password" id="password" name="password" required autocomplete="current-password">
            </div>
            <button type="submit" class="btn-login">Connect</button>
        </form>

        <div class="footer">
            Need a voucher? Ask at the counter.
        </div>
    </div>
</body>
</html>
