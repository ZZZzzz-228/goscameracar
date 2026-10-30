# SSH уже настроен

Подключение проверено к `vh460.timeweb.ru` под пользователем `cv339126` (порт 22).
Используется отдельный ключ:

- закрытый: `C:\Users\kucer\.ssh\timeweb_goscameracar`;
- открытый: `C:\Users\kucer\.ssh\timeweb_goscameracar.pub`.

Закрытый ключ остаётся на этом компьютере. Права файла ограничены текущим
пользователем Windows. Открытый ключ добавлен в `~/.ssh/authorized_keys` на хостинге;
существующие строки сохраняются. Ключ сервера сохранён OpenSSH в known_hosts.

В PowerShell:

```powershell
ssh -i "$env:USERPROFILE\.ssh\timeweb_goscameracar" cv339126@vh460.timeweb.ru
```

Для команды без интерактивного запроса пароля:

```powershell
ssh -i "$env:USERPROFILE\.ssh\timeweb_goscameracar" -o BatchMode=yes -o StrictHostKeyChecking=yes cv339126@vh460.timeweb.ru "php -v"
```

Дополнительный плагин не требуется: серверные команды выполняются через установленный
OpenSSH. Пароль хостинга не сохранён в проекте. Пароль MySQL находится только
в закрытой конфигурации сервера.

Чтобы отозвать этот доступ, удалите на сервере строку с пометкой
`goscameracar-timeweb` из `~/.ssh/authorized_keys`, сохранив остальные ключи.
