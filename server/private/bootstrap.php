<?php
declare(strict_types=1);

if (PHP_SAPI !== 'cli' && realpath($_SERVER['SCRIPT_FILENAME'] ?? '') === __FILE__) {
    http_response_code(404);
    exit;
}
define('GOSCAMERA_INTERNAL', true);

date_default_timezone_set('UTC');
ini_set('display_errors', '0');
$config = require __DIR__ . '/config.php';

final class RequestError extends RuntimeException
{
    public function __construct(public readonly int $status, string $message)
    {
        parent::__construct($message);
    }
}

function db(): PDO
{
    static $connection;
    global $config;
    if (!$connection) {
        $database = $config['database'];
        $connection = new PDO(
            'mysql:host=' . $database['host'] . ';dbname=' . $database['name'] . ';charset=utf8mb4',
            $database['username'],
            $database['password'],
            [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
             PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
             PDO::ATTR_EMULATE_PREPARES => false]
        );
        $connection->exec("SET time_zone = '+00:00'");
    }
    return $connection;
}

function normalize_plate(string $input): string
{
    if (strlen($input) > 128) {
        throw new RequestError(422, 'Введите номер в формате А123ВС77.');
    }
    $value = mb_strtoupper($input, 'UTF-8');
    $value = preg_replace('/[\s\-]+/u', '', $value);
    $value = strtr($value, [
        'А' => 'A', 'В' => 'B', 'Е' => 'E', 'К' => 'K', 'М' => 'M', 'Н' => 'H',
        'О' => 'O', 'Р' => 'P', 'С' => 'C', 'Т' => 'T', 'У' => 'Y', 'Х' => 'X',
    ]);
    if (!preg_match('/^[ABEKMHOPCTYX][0-9]{3}[ABEKMHOPCTYX]{2}([0-9]{2,3})?$/D', $value)) {
        throw new RequestError(422, 'Введите номер, например А123ВС.');
    }
    return $value;
}

function display_plate(string $value): string
{
    return strtr($value, [
        'A' => 'А', 'B' => 'В', 'E' => 'Е', 'K' => 'К', 'M' => 'М', 'H' => 'Н',
        'O' => 'О', 'P' => 'Р', 'C' => 'С', 'T' => 'Т', 'Y' => 'У', 'X' => 'Х',
    ]);
}

function secure_headers(): void
{
    header('Cache-Control: no-store');
    header('X-Content-Type-Options: nosniff');
    header('Referrer-Policy: no-referrer');
    header('X-Frame-Options: DENY');
    header("Content-Security-Policy: default-src 'self'; script-src 'none'; style-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'");
    if (is_https()) {
        header('Strict-Transport-Security: max-age=86400');
    }
}

function is_https(): bool
{
    return !empty($_SERVER['HTTPS']) && strtolower((string) $_SERVER['HTTPS']) !== 'off';
}

function consume_limit(string $key, int $limit, int $seconds): void
{
    $connection = db();
    $bucket = hash('sha256', $key);
    $now = time();
    $connection->beginTransaction();
    try {
        $statement = $connection->prepare('INSERT IGNORE INTO request_limits (bucket, window_started) VALUES (?, ?)');
        $statement->execute([$bucket, $now]);
        $statement = $connection->prepare('SELECT attempts, window_started FROM request_limits WHERE bucket = ? FOR UPDATE');
        $statement->execute([$bucket]);
        $row = $statement->fetch();
        $attempts = (int) $row['attempts'];
        $start = (int) $row['window_started'];
        if ($now >= $start + $seconds) {
            $attempts = 0;
            $start = $now;
        }
        if ($attempts >= $limit) {
            throw new RequestError(429, 'Слишком много попыток. Повторите позже.');
        }
        $statement = $connection->prepare('UPDATE request_limits SET attempts = ?, window_started = ? WHERE bucket = ?');
        $statement->execute([$attempts + 1, $start, $bucket]);
        $connection->commit();
    } catch (Throwable $error) {
        if ($connection->inTransaction()) $connection->rollBack();
        throw $error;
    }
}

function authenticate(string $username, string $password, ?string $requiredRole = null): array
{
    $username = strtolower(trim($username));
    $ip = $_SERVER['REMOTE_ADDR'] ?? 'unknown';
    consume_limit('login-ip:' . $ip, 100, 900);
    $identity = 'login:' . $ip . ':' . $username;
    consume_limit($identity, 10, 900);
    if (!preg_match('/^[a-z0-9_.-]{1,64}$/D', $username) || strlen($password) > 72) {
        throw new RequestError(401, 'Неверный логин или пароль.');
    }
    $statement = db()->prepare('SELECT id, username, password_hash, role, active FROM users WHERE username = ?');
    $statement->execute([$username]);
    $user = $statement->fetch();
    $dummy = '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2uheWG/igi';
    $validPassword = password_verify($password, $user ? $user['password_hash'] : $dummy);
    if (!$user || !$validPassword || !$user['active'] || ($requiredRole !== null && $user['role'] !== $requiredRole)) {
        throw new RequestError(401, 'Неверный логин или пароль.');
    }
    $statement = db()->prepare('DELETE FROM request_limits WHERE bucket = ?');
    $statement->execute([hash('sha256', $identity)]);
    return $user;
}

function token_user(): array
{
    $authorization = $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '';
    if (!preg_match('/^Bearer ([a-f0-9]{64})$/D', $authorization, $matches)) {
        throw new RequestError(401, 'Войдите в приложение заново.');
    }
    $hash = hash('sha256', $matches[1]);
    $statement = db()->prepare('SELECT u.id, u.username FROM api_tokens t JOIN users u ON u.id = t.user_id WHERE t.token_hash = ? AND t.expires_at > UTC_TIMESTAMP() AND u.active = 1');
    $statement->execute([$hash]);
    $user = $statement->fetch();
    if (!$user) throw new RequestError(401, 'Войдите в приложение заново.');
    $user['token_hash'] = $hash;
    return $user;
}

function cleanup(): void
{
    if (random_int(1, 100) !== 1) return;
    db()->exec('DELETE FROM api_tokens WHERE expires_at < UTC_TIMESTAMP()');
    db()->exec('DELETE FROM request_limits WHERE window_started < UNIX_TIMESTAMP() - 86400');
}

function escape(string $value): string
{
    return htmlspecialchars($value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}
