"""Exercise this project's live install. Removes only its own temporary plate."""
import html
from http.cookiejar import CookieJar
import json
from pathlib import Path
import re
import secrets
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, build_opener, HTTPCookieProcessor

access = json.loads((Path(__file__).resolve().parent.parent / '.local' / 'access.json').read_text())
base = access['base_url']
admin = next(a for a in access['accounts'] if a['role'] == 'admin')
guard = next(a for a in access['accounts'] if a['role'] == 'guard')
opener = build_opener(HTTPCookieProcessor(CookieJar()))
anonymous = build_opener(HTTPCookieProcessor(CookieJar()))

def request(path, body=None, *, client=opener, headers=None, method=None):
    req = Request(base + path, data=body, headers=headers or {}, method=method)
    try:
        response = client.open(req, timeout=20)
    except HTTPError as error:
        response = error
    with response:
        return response.status, response.read().decode('utf-8'), response.headers

def form(values, client=opener):
    return request('/', urlencode(values).encode(), client=client,
                   headers={'Content-Type': 'application/x-www-form-urlencoded'})

def api(action, body, token=None):
    headers = {'Content-Type': 'application/json'}
    if token: headers['Authorization'] = 'Bearer ' + token
    status, text, _ = request('/api.php?action=' + action, json.dumps(body).encode(), headers=headers)
    return status, json.loads(text)

def csrf(text):
    return re.search(r'name="csrf" value="([a-f0-9]+)"', text).group(1)

def verify_passes():
    status, _, _ = request('/api.php?action=health')
    assert status == 200, 'Health endpoint failed'
    status, page, headers = request('/')
    assert status == 200 and 'Авторизация' in page, 'Login page missing'
    cookie = headers.get('Set-Cookie', '').lower()
    assert 'secure' in cookie and 'httponly' in cookie and 'samesite=lax' in cookie, 'Session cookie flags missing'
    assert "frame-ancestors 'none'" in headers['Content-Security-Policy'], 'CSP missing'
    status, page, _ = form({'action': 'login', 'csrf': csrf(page), 'username': admin['username'], 'password': admin['password']})
    assert status == 200 and 'Список пропусков' in page, 'Admin login failed'
    
    status, guest, _ = request('/', client=anonymous)
    status, _, _ = form({'action': 'login', 'csrf': csrf(guest), 'username': guard['username'], 'password': guard['password']}, anonymous)
    assert status == 401, 'Guard must not access admin'
    status, _ = api('check', {'plate': 'A123BC77'})
    assert status == 401, 'Unauthenticated check was accepted'
    status, _ = api('login', {'username': guard['username'], 'password': 'wrong-test-password'})
    assert status == 401, 'Invalid password was accepted'
    status, login = api('login', {'username': guard['username'], 'password': guard['password']})
    assert status == 200, 'API login failed'
    token = login['token']
    test_id = None
    test_plate = None
    try:
        for _ in range(10):
            candidate = secrets.choice('ABEKMHOPCTYX') + str(secrets.randbelow(900) + 100) + ''.join(secrets.choice('ABEKMHOPCTYX') for _ in range(2)) + '199'
            status, result = api('check', {'plate': candidate}, token)
            assert status == 200, 'API check failed'
            if result['decision'] == 'not_found':
                test_plate = candidate
                break
        assert test_plate, 'Could not reserve a temporary test plate'
        status, _, _ = form({'action': 'add', 'csrf': 'invalid', 'plate': test_plate})
        assert status == 403, 'Invalid CSRF was accepted'
        status, result = api('check', {'plate': test_plate}, token)
        assert result['decision'] == 'not_found', 'Failed CSRF request changed data'
        status, page, _ = request('/')
        marker = 'Temporary verification <script>alert(1)</script>'
        status, page, _ = form({'action': 'add', 'csrf': csrf(page), 'plate': test_plate, 'comment': marker})
        assert status == 200 and html.escape(marker) in page and '<script>alert(1)</script>' not in page, 'Add or escaping failed'
        display = test_plate.translate(str.maketrans('ABEKMHOPCTYX', 'АВЕКМНОРСТУХ'))
        row = next(r for r in re.findall(r'<li class="pass">(.*?)</li>', page, re.S) if display in r)
        test_id = re.search(r'name="id" value="(\d+)"', row).group(1)
        status, result = api('check', {'plate': display.lower()}, token)
        assert status == 200 and result['decision'] == 'allowed' and result['plate'] == test_plate, 'Added plate not allowed'
        status, duplicate, _ = form({'action': 'add', 'csrf': csrf(page), 'plate': test_plate})
        assert status == 409, 'Duplicate plate accepted'
        for variant in [test_plate[:6], test_plate[:6] + '77']:
            status, result = api('check', {'plate':variant}, token)
            assert status == 200 and result['decision'] == 'allowed' and result['plate'] == variant, 'Region-independent check failed'
        status, found, _ = request('/?' + urlencode({'q': display}))
        assert status == 200 and display in found and html.escape(marker) in found, 'Search failed'
        status, _ = api('check', {'plate': "A123BC77' OR 1=1"}, token)
        assert status == 422, 'Malformed plate accepted'
        status, _, _ = request('/api.php?action=check')
        assert status == 405, 'Incorrect method accepted'
        status, _, headers = request('/api.php?action=check', headers={'Origin': 'http://127.0.0.1:5180', 'Access-Control-Request-Method': 'POST'}, method='OPTIONS')
        assert status == 204 and headers.get('Access-Control-Allow-Origin') == 'http://127.0.0.1:5180', 'Local preview CORS failed'
        status, _, _ = request('/api.php?action=health', headers={'Origin': 'https://untrusted.example'})
        assert status == 403, 'Unexpected browser origin accepted'
    finally:
        if test_id:
            status, page, _ = request('/')
            status, _, _ = form({'action': 'delete', 'csrf': csrf(page), 'id': test_id})
            assert status == 200, 'Temporary plate cleanup failed'
        if test_plate:
            status, result = api('check', {'plate': test_plate}, token)
            assert status == 200 and result['decision'] == 'not_found', 'Deleted plate still allowed'
        api('logout', {}, token)
    
    status, _ = api('check', {'plate': test_plate}, token)
    assert status == 401, 'Revoked token accepted'
    status, page, _ = request('/')
    status, page, _ = form({'action': 'logout', 'csrf': csrf(page)})
    assert status == 200 and 'Авторизация' in page, 'Admin logout failed'
    for path in ['/config.php', '/schema.sql', '/.env', '/.ht-goscameracar/config.php', '/.ht-goscameracar/bootstrap.php']:
        status, _, _ = request(path)
        assert status in (403, 404), 'Private resource exposed'
    print('PASS: admin login, guard isolation, API authentication, add/check/delete, duplicate protection, search, CSRF, escaping, CORS, malformed input, logout and private-file isolation.')
    print('Temporary verification plate removed. No permanent vehicle records added.')

if __name__ == "__main__":
    verify_passes()
