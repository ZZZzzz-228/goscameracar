<?php
declare(strict_types=1);
if (!defined('GOSCAMERA_INTERNAL')) { http_response_code(404); exit; }

function save_user(array $actor, array $input): string
{
    $id = filter_var($input['id'] ?? 0, FILTER_VALIDATE_INT, ['options' => ['min_range' => 0]]);
    $username = is_string($input['username'] ?? null) ? strtolower(trim($input['username'])) : '';
    $password = is_string($input['password'] ?? null) ? $input['password'] : '';
    $role = $input['role'] ?? '';
    $active = ($input['active'] ?? '') === '1' ? 1 : 0;
    if ($id === false || !preg_match('/^[a-z0-9_.-]{1,64}$/D', $username)) {
        throw new RequestError(422, 'Логин: латинские буквы, цифры, точка, дефис или подчёркивание.');
    }
    if (!in_array($role, ['admin', 'guard'], true)) throw new RequestError(422, 'Выберите роль.');
    if ((!$id && $password === '') || ($password !== '' && (strlen($password) < 5 || strlen($password) > 72))) {
        throw new RequestError(422, 'Пароль должен содержать от 5 до 72 байт.');
    }
    $pdo = db();
    $pdo->beginTransaction();
    try {
        // Serialize role changes to prevent concurrent removal of the last admin.
        $admins = $pdo->query("SELECT id FROM users WHERE role = 'admin' AND active = 1 ORDER BY id FOR UPDATE")->fetchAll(PDO::FETCH_COLUMN);
        $old = null;
        if ($id) {
            $statement = $pdo->prepare('SELECT * FROM users WHERE id = ? FOR UPDATE');
            $statement->execute([$id]);
            $old = $statement->fetch();
            if (!$old) throw new RequestError(404, 'Пользователь не найден.');
            if ($old['role'] === 'admin' && $old['active'] && ($role !== 'admin' || !$active) && count($admins) <= 1) {
                throw new RequestError(422, 'Нельзя отключить последнего администратора.');
            }
            if ((int)$actor['id'] === $id && ($role !== 'admin' || !$active)) {
                throw new RequestError(422, 'Нельзя отключить собственный доступ.');
            }
        }
        $hash = $password !== '' ? password_hash($password, PASSWORD_DEFAULT) : $old['password_hash'];
        if ($id) {
            $statement = $pdo->prepare('UPDATE users SET username = ?, password_hash = ?, role = ?, active = ? WHERE id = ?');
            $statement->execute([$username, $hash, $role, $active, $id]);
            $statement = $pdo->prepare('DELETE FROM api_tokens WHERE user_id = ?');
            $statement->execute([$id]);
        } else {
            $statement = $pdo->prepare('INSERT INTO users (username, password_hash, role, active) VALUES (?, ?, ?, ?)');
            $statement->execute([$username, $hash, $role, $active]);
        }
        $pdo->commit();
        if ((int)$actor['id'] === $id) $_SESSION['auth_hash'] = hash('sha256', $hash);
        return $id ? 'Пользователь сохранён.' : 'Пользователь создан.';
    } catch (Throwable $error) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        if ($error instanceof PDOException && ($error->errorInfo[1] ?? null) === 1062) {
            throw new RequestError(409, 'Этот логин уже занят.');
        }
        throw $error;
    }
}
