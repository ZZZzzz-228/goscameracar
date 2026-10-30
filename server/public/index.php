<?php
declare(strict_types=1);
ini_set('display_errors', '0');

try {
    require (getenv('GOSCAMERA_PRIVATE_DIR') ?: __DIR__ . '/.ht-goscameracar') . '/bootstrap.php';
    require (getenv('GOSCAMERA_PRIVATE_DIR') ?: __DIR__ . '/.ht-goscameracar') . '/manage_users.php';
    secure_headers();
    $tab = (($_GET['tab'] ?? '') === 'users' || ($_POST['action'] ?? '') === 'save_user') ? 'users' : 'passes';
    if (!is_https()) {
        header('Location: ' . $config['base_url'] . '/', true, 303);
        exit;
    }
    ini_set('session.use_strict_mode', '1');
    ini_set('session.gc_maxlifetime', '28800');
    session_name('goscamera_admin');
    session_set_cookie_params(['lifetime' => 0, 'path' => '/goscameracar/', 'secure' => true, 'httponly' => true, 'samesite' => 'Lax']);
    session_start();
    $_SESSION['csrf'] ??= bin2hex(random_bytes(32));
    $errorMessage = '';
    $success = $_SESSION['flash'] ?? '';
    unset($_SESSION['flash']);
    $user = null;
    if (isset($_SESSION['user_id']) && ($_SESSION['expires'] ?? 0) > time()) {
        $statement = db()->prepare("SELECT id, username, password_hash FROM users WHERE id = ? AND role = 'admin' AND active = 1");
        $statement->execute([$_SESSION['user_id']]);
        $user = $statement->fetch() ?: null;
        if ($user && !hash_equals(hash('sha256', $user['password_hash']), (string)($_SESSION['auth_hash'] ?? ''))) $user = null;
    }
    if (!$user) unset($_SESSION['user_id'], $_SESSION['expires']);

    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        try {
            if (!is_string($_POST['csrf'] ?? null) || !hash_equals($_SESSION['csrf'], $_POST['csrf'])) {
                throw new RequestError(403, 'Форма устарела. Обновите страницу и повторите действие.');
            }
            $action = $_POST['action'] ?? '';
            if ($action === 'login') {
                $username = is_string($_POST['username'] ?? null) ? $_POST['username'] : '';
                $password = is_string($_POST['password'] ?? null) ? $_POST['password'] : '';
                $account = authenticate($username, $password, 'admin');
                session_regenerate_id(true);
                $_SESSION['user_id'] = $account['id'];
                $_SESSION['auth_hash'] = hash('sha256', $account['password_hash']);
                $_SESSION['expires'] = time() + 8 * 3600;
                $_SESSION['csrf'] = bin2hex(random_bytes(32));
            } elseif ($action === 'logout') {
                $_SESSION = [];
                setcookie(session_name(), '', ['expires' => time() - 3600, 'path' => '/goscameracar/', 'secure' => true, 'httponly' => true, 'samesite' => 'Lax']);
                session_destroy();
            } else {
                if (!$user) throw new RequestError(401, 'Войдите в админку заново.');
                if ($action === 'save_user') {
                    $_SESSION['flash'] = save_user($user, $_POST);
                } elseif ($action === 'add') {
                    $plate = normalize_plate(is_string($_POST['plate'] ?? null) ? $_POST['plate'] : '');
                    $comment = is_string($_POST['comment'] ?? null) ? trim($_POST['comment']) : '';
                    if (mb_strlen($comment) > 255) throw new RequestError(422, 'Комментарий должен быть не длиннее 255 символов.');
                    try {
                        $statement = db()->prepare('INSERT INTO vehicle_passes (plate, comment) VALUES (?, ?)');
                        $statement->execute([$plate, $comment]);
                    } catch (PDOException $error) {
                        if (($error->errorInfo[1] ?? null) === 1062) throw new RequestError(409, 'Этот номер уже есть в базе.');
                        throw $error;
                    }
                    $_SESSION['flash'] = 'Пропуск для ' . display_plate($plate) . ' добавлен.';
                } elseif ($action === 'delete') {
                    $id = filter_var($_POST['id'] ?? '', FILTER_VALIDATE_INT, ['options' => ['min_range' => 1]]);
                    if ($id === false) throw new RequestError(422, 'Некорректный пропуск.');
                    $statement = db()->prepare('DELETE FROM vehicle_passes WHERE id = ?');
                    $statement->execute([$id]);
                    $_SESSION['flash'] = $statement->rowCount() ? 'Пропуск удалён. Номер больше не разрешает въезд.' : 'Пропуск уже удалён.';
                } else {
                    throw new RequestError(400, 'Неизвестное действие.');
                }
            }
            header('Location: ' . $config['base_url'] . '/' . ($tab === 'users' && $action !== 'logout' ? '?tab=users' : ''), true, 303);
            exit;
        } catch (RequestError $error) {
            http_response_code($error->status);
            $errorMessage = $error->getMessage();
        }
    }
    $search = is_string($_GET['q'] ?? null) ? mb_substr(trim($_GET['q']), 0, 64) : '';
    $passes = [];
    $total = 0;
    $page = max(1, min(1000000, (int) ($_GET['page'] ?? 1)));
    $pages = 1;
    if ($user) {
        $where = '';
        $parameters = [];
        if ($search !== '') {
            try {
                $where = ' WHERE plate LIKE ?';
                $parameters[] = substr(normalize_plate($search), 0, 6) . '%';
            } catch (RequestError) {
                $where = ' WHERE 1 = 0';
            }
        }
        $statement = db()->prepare('SELECT COUNT(*) FROM vehicle_passes' . $where);
        $statement->execute($parameters);
        $total = (int) $statement->fetchColumn();
        $pages = max(1, (int) ceil($total / 50));
        $page = min($page, $pages);
        $statement = db()->prepare('SELECT id, plate, comment FROM vehicle_passes' . $where . ' ORDER BY id DESC LIMIT 50 OFFSET ' . (($page - 1) * 50));
        $statement->execute($parameters);
        $passes = $statement->fetchAll();
        $accounts = [];
        if ($tab === 'users') {
            $total = (int)db()->query('SELECT COUNT(*) FROM users')->fetchColumn();
            $pages = max(1, (int)ceil($total / 50));
            $page = min(max(1, (int)($_GET['page'] ?? 1)), $pages);
            $accounts = db()->query('SELECT id, username, role, active FROM users ORDER BY id DESC LIMIT 50 OFFSET ' . (($page - 1) * 50))->fetchAll();
        }
    }
} catch (Throwable $error) {
    error_log('goscameracar admin: ' . get_class($error) . ' code=' . $error->getCode());
    http_response_code(503);
    header('Content-Type: text/html; charset=utf-8');
    echo '<!doctype html><html lang="ru"><meta charset="utf-8"><title>Сервис недоступен</title><p>Не удалось открыть базу пропусков. Повторите позже.</p></html>';
    exit;
}

function user_form(array $account): void {
?>
<form method="post" class="user-form">
  <input type="hidden" name="csrf" value="<?= escape($_SESSION['csrf']) ?>">
  <input type="hidden" name="action" value="save_user">
  <input type="hidden" name="id" value="<?= (int)$account['id'] ?>">
  <label>Логин<input name="username" value="<?= escape($account['username']) ?>" maxlength="64" autocomplete="off" required></label>
  <label><?= $account['id'] ? 'Новый пароль (пусто — сохранить текущий)' : 'Пароль' ?><input name="password" type="password" autocomplete="new-password" minlength="5" maxlength="72" <?= $account['id'] ? '' : 'required' ?>></label>
  <label>Роль<select name="role"><option value="guard" <?= $account['role'] === 'guard' ? 'selected' : '' ?>>Охрана</option><option value="admin" <?= $account['role'] === 'admin' ? 'selected' : '' ?>>Администратор</option></select></label>
  <label class="check"><input type="checkbox" name="active" value="1" <?= $account['active'] ? 'checked' : '' ?>> Активен</label>
  <button type="submit"><?= $account['id'] ? 'Сохранить' : 'Создать' ?></button>
</form>
<?php
}
?>
<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Автопропуск — админка</title>
  <link rel="stylesheet" href="assets/app.css?v=20261029">
</head>
<body>
<main class="shell <?= $user ? '' : 'shell-login' ?>">
  <?php if ($user): ?><header class="header"><nav class="tabs"><a href="./" class="<?= $tab === 'passes' ? 'selected' : '' ?>">Пропуска</a><a href="?tab=users" class="<?= $tab === 'users' ? 'selected' : '' ?>">Пользователи</a></nav>
    <form method="post"><input type="hidden" name="csrf" value="<?= escape($_SESSION['csrf']) ?>"><input type="hidden" name="action" value="logout"><button class="secondary" type="submit">Выйти</button></form>
  </header><?php endif; ?>
  <?php if ($errorMessage): ?><div role="alert" class="notice error"><?= escape($errorMessage) ?></div><?php endif; ?>
  <?php if ($success): ?><div role="status" class="notice success"><?= escape($success) ?></div><?php endif; ?>

  <?php if (!$user): ?>
    <form method="post" class="card login-form">
      <h2>Авторизация</h2>
      <input type="hidden" name="csrf" value="<?= escape($_SESSION['csrf']) ?>">
      <input type="hidden" name="action" value="login">
      <label>Логин<input name="username" autocomplete="username" maxlength="64" required autofocus></label>
      <label>Пароль<input name="password" type="password" autocomplete="current-password" maxlength="72" required></label>
      <button type="submit">Войти</button>
    </form>
  <?php else: ?>
    <?php if ($tab === 'users'): ?>
    <div class="workspace">
      <section class="card add-card"><h2>Создать пользователя</h2>
        <?php user_form(['id'=>0,'username'=>'','role'=>'guard','active'=>1]); ?>
      </section>
      <section class="card"><h2>Пользователи</h2>
        <?php foreach ($accounts as $account): ?><details class="account"><summary><?= escape($account['username']) ?> · <?= $account['role'] === 'admin' ? 'Администратор' : 'Охрана' ?><?= $account['active'] ? '' : ' · Отключён' ?></summary>
          <?php user_form($account); ?>
        </details><?php endforeach; ?>
        <?php if ($pages > 1): ?><nav class="pagination"><?php if ($page > 1): ?><a href="?tab=users&amp;page=<?= $page-1 ?>">← Назад</a><?php endif; ?><span><?= $page ?> / <?= $pages ?></span><?php if ($page < $pages): ?><a href="?tab=users&amp;page=<?= $page+1 ?>">Далее →</a><?php endif; ?></nav><?php endif; ?>
      </section>
    </div>
    <?php else: ?>
    <div class="workspace">
      <section class="card add-card">
        <span class="badge">Новый пропуск</span><h2>Добавить автомобиль</h2>
        <form method="post">
          <input type="hidden" name="csrf" value="<?= escape($_SESSION['csrf']) ?>">
          <input type="hidden" name="action" value="add">
          <label>Государственный номер<input class="plate-input" name="plate" placeholder="А123ВС" maxlength="32" required autocomplete="off" aria-describedby="plate-help"></label>
          <p class="field-help" id="plate-help">Регион необязателен. Проверка выполняется по основной части номера.</p>
          <label>Комментарий <span class="optional">необязательно</span><input name="comment" placeholder="Например, служебный автомобиль" maxlength="255"></label>
          <button type="submit">Добавить пропуск <span aria-hidden="true">+</span></button>
        </form>
      </section>
      <section class="card list-card">
        <div class="section-heading"><h2>Список пропусков</h2><span class="count"><?= $total ?></span></div>
        <form method="get" class="search"><label class="sr-only" for="search">Поиск по номеру</label><input id="search" name="q" placeholder="Поиск по номеру" value="<?= escape($search) ?>" maxlength="32"><button class="secondary" type="submit">Найти</button></form>
        <?php if ($search !== ''): ?><a class="clear-search" href="./">Сбросить поиск</a><?php endif; ?>
        <?php if (!$passes): ?>
          <div class="empty"><span aria-hidden="true">▤</span><h3><?= $search !== '' ? 'Номер не найден' : 'Здесь появятся автомобили' ?></h3><p><?= $search !== '' ? 'Проверьте номер.' : 'Добавьте первый номер с помощью формы. В приложении у него появится пропуск.' ?></p></div>
        <?php else: ?>
          <ul class="passes">
          <?php foreach ($passes as $pass): ?>
            <li class="pass"><div><strong class="plate"><?= escape(display_plate($pass['plate'])) ?></strong><span class="allowed">Пропуск есть</span><?php if ($pass['comment'] !== ''): ?><p class="comment"><?= escape($pass['comment']) ?></p><?php endif; ?></div>
              <details class="delete"><summary>Удалить</summary><form method="post"><p>Отозвать пропуск<br><strong><?= escape(display_plate($pass['plate'])) ?></strong>?</p><input type="hidden" name="csrf" value="<?= escape($_SESSION['csrf']) ?>"><input type="hidden" name="action" value="delete"><input type="hidden" name="id" value="<?= $pass['id'] ?>"><button class="danger" type="submit">Да, удалить</button></form></details>
            </li>
          <?php endforeach; ?>
          </ul>
          <?php if ($pages > 1): ?><nav class="pagination" aria-label="Страницы списка">
            <?php if ($page > 1): ?><a href="?<?= escape(http_build_query(['q' => $search, 'page' => $page - 1])) ?>">← Назад</a><?php endif; ?>
            <span><?= $page ?> / <?= $pages ?></span>
            <?php if ($page < $pages): ?><a href="?<?= escape(http_build_query(['q' => $search, 'page' => $page + 1])) ?>">Далее →</a><?php endif; ?>
          </nav><?php endif; ?>
        <?php endif; ?>
      </section>
    </div>
    <?php endif; ?>
  <?php endif; ?>
</main>
</body>
</html>
