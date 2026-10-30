<?php
declare(strict_types=1);
ini_set('display_errors', '0');

header('Content-Type: application/json; charset=utf-8');

function reply(array $body, int $status = 200): never
{
    http_response_code($status);
    echo json_encode($body, JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
    exit;
}

try {
    require (getenv('GOSCAMERA_PRIVATE_DIR') ?: __DIR__ . '/.ht-goscameracar') . '/bootstrap.php';
    secure_headers();
    if (!is_https()) throw new RequestError(400, 'Для API требуется HTTPS.');
    $origin = $_SERVER['HTTP_ORIGIN'] ?? '';
    if ($origin !== '') {
        header('Vary: Origin');
        $siteOrigin = parse_url($config['base_url'], PHP_URL_SCHEME) . '://' . parse_url($config['base_url'], PHP_URL_HOST);
        if (!in_array($origin, [...$config['allowed_origins'], $siteOrigin], true)) {
            throw new RequestError(403, 'Источник запроса не разрешён.');
        }
        header('Access-Control-Allow-Origin: ' . $origin);
        header('Access-Control-Allow-Headers: Authorization, Content-Type');
        header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
    }
    $method = $_SERVER['REQUEST_METHOD'];
    if ($method === 'OPTIONS') { http_response_code(204); exit; }
    $action = $_GET['action'] ?? '';
    if ($action === 'health' && $method === 'GET') {
        db()->query('SELECT 1');
        reply(['status' => 'ok']);
    }
    if (!in_array($action, ['login', 'check', 'logout'], true)) throw new RequestError(404, 'Метод API не найден.');
    if ($method !== 'POST') {
        header('Allow: POST');
        throw new RequestError(405, 'Используйте POST.');
    }
    if (!str_starts_with(strtolower($_SERVER['CONTENT_TYPE'] ?? ''), 'application/json')) {
        throw new RequestError(415, 'Ожидается JSON.');
    }
    $raw = file_get_contents('php://input', false, null, 0, 8193);
    if (strlen($raw) > 8192) throw new RequestError(413, 'Запрос слишком большой.');
    try { $body = json_decode($raw, true, 16, JSON_THROW_ON_ERROR); }
    catch (JsonException) { throw new RequestError(400, 'Некорректный JSON.'); }
    if (!is_array($body)) throw new RequestError(400, 'Ожидается объект JSON.');

    if ($action === 'login') {
        if (!is_string($body['username'] ?? null) || !is_string($body['password'] ?? null)) {
            throw new RequestError(422, 'Укажите логин и пароль.');
        }
        $user = authenticate($body['username'], $body['password']);
        $token = bin2hex(random_bytes(32));
        $expires = time() + 8 * 3600;
        $statement = db()->prepare('INSERT INTO api_tokens (token_hash, user_id, expires_at) VALUES (?, ?, ?)');
        $statement->execute([hash('sha256', $token), $user['id'], gmdate('Y-m-d H:i:s', $expires)]);
        cleanup();
        reply(['token' => $token, 'expires_at' => gmdate('c', $expires)]);
    }
    $user = token_user();
    if ($action === 'logout') {
        $statement = db()->prepare('DELETE FROM api_tokens WHERE token_hash = ?');
        $statement->execute([$user['token_hash']]);
        reply(['status' => 'ok']);
    }
    consume_limit('check:' . $user['id'], 180, 60);
    if (!is_string($body['plate'] ?? null)) throw new RequestError(422, 'Укажите номер автомобиля.');
    $plate = normalize_plate($body['plate']);
    $statement = db()->prepare('SELECT id FROM vehicle_passes WHERE plate LIKE ? LIMIT 1');
    $statement->execute([substr($plate, 0, 6) . '%']);
    reply(['plate' => $plate, 'decision' => $statement->fetch() ? 'allowed' : 'not_found']);
} catch (RequestError $error) {
    if ($error->status === 429) header('Retry-After: 900');
    reply(['error' => $error->getMessage()], $error->status);
} catch (Throwable $error) {
    error_log('goscameracar API: ' . get_class($error) . ' code=' . $error->getCode());
    reply(['error' => 'Сервис временно недоступен. Повторите проверку.'], 503);
}
