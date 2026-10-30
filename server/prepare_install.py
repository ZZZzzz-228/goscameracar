"""Prepare an initial install. Run locally in a private, interactive terminal."""
import getpass
import json
from pathlib import Path
import secrets

root = Path(__file__).resolve().parent.parent
local = root / '.local'
local.mkdir(exist_ok=True)
if any((local / name).exists() for name in ('access.json', 'access.txt', 'provision.json')):
    raise SystemExit('Local credentials already exist; refusing to overwrite them.')

password = getpass.getpass('MySQL password (not displayed): ')
if not password:
    raise SystemExit('An empty MySQL password is not allowed.')

base_url = 'https://cv339126.tw1.ru/goscameracar'
accounts = [
    {'username': 'admin', 'password': secrets.token_urlsafe(18), 'role': 'admin'},
    {'username': 'guard', 'password': secrets.token_urlsafe(18), 'role': 'guard'},
]
provision = {
    'base_url': base_url,
    'database': {'host': 'localhost', 'name': 'cv339126_camera',
                 'username': 'cv339126_camera', 'password': password},
    'accounts': accounts,
}
(local / 'provision.json').write_text(json.dumps(provision), encoding='utf-8')
(local / 'access.json').write_text(json.dumps({'base_url': base_url, 'accounts': accounts}), encoding='utf-8')
lines = ['Автопропуск — доступ к приложению', '', f'Админка: {base_url}/', '']
for account in accounts:
    lines.extend(['Администратор' if account['role'] == 'admin' else 'Вход в мобильное приложение',
                  'Логин: ' + account['username'], 'Пароль: ' + account['password'], ''])
lines.append('Файл содержит пароли. Храните его на своём компьютере, не публикуйте.')
(local / 'access.txt').write_text('\n'.join(lines), encoding='utf-8')
print('Provisioning data and application credentials saved in .local (excluded from Git).')
