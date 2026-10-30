<?php
declare(strict_types=1);

if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }
umask(0077);
$source = $argv[1] ?? '';
$runtime = $argv[2] ?? __DIR__;
if (!is_file($source) || is_file($runtime . '/config.php')) {
    fwrite(STDERR, "Missing provisioning file or installation already exists.\n");
    exit(1);
}
if (!is_dir($runtime) && !mkdir($runtime, 0700)) {
    throw new RuntimeException('Unable to create the runtime directory.');
}
$input = json_decode(file_get_contents($source), true, 512, JSON_THROW_ON_ERROR);
$configuration = [
    'base_url' => $input['base_url'],
    'allowed_origins' => ['http://127.0.0.1:5180', 'http://localhost:5180'],
    'database' => $input['database'],
];
$database = $configuration['database'];
$connection = new PDO(
    'mysql:host=' . $database['host'] . ';dbname=' . $database['name'] . ';charset=utf8mb4',
    $database['username'], $database['password'], [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
);
$connection->exec(file_get_contents(__DIR__ . '/schema.sql'));
$connection->beginTransaction();
try {
    $insert = $connection->prepare('INSERT INTO users (username, password_hash, role) VALUES (?, ?, ?)');
    foreach ($input['accounts'] as $account) {
        $insert->execute([$account['username'], password_hash($account['password'], PASSWORD_DEFAULT), $account['role']]);
    }
    $connection->commit();
} catch (Throwable $error) {
    $connection->rollBack();
    throw $error;
}
file_put_contents($runtime . '/.htaccess', "Require all denied\nOptions -Indexes\n", LOCK_EX);
chmod($runtime . '/.htaccess', 0644);
file_put_contents($runtime . '/config.php', "<?php\nif (!defined('GOSCAMERA_INTERNAL')) { http_response_code(404); exit; }\nreturn " . var_export($configuration, true) . ";\n", LOCK_EX);
chmod($runtime . '/config.php', 0600);
if (realpath($runtime) !== __DIR__) {
    copy(__DIR__ . '/bootstrap.php', $runtime . '/bootstrap.php');
    chmod($runtime . '/bootstrap.php', 0600);
}
unlink($source);
echo "Database schema and application accounts created. No vehicle passes added.\n";
