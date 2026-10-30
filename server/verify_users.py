"""Live user-management checks; removes only the randomly named test account."""
import secrets, re, subprocess, shlex
from pathlib import Path
from http.cookiejar import CookieJar
from urllib.request import build_opener, HTTPCookieProcessor
from verify_live import request, form, api, csrf, admin, opener

name='verify_'+secrets.token_hex(6)
password=secrets.token_urlsafe(18)
updated=secrets.token_urlsafe(18)
test_id=None
other=build_opener(HTTPCookieProcessor(CookieJar()))
_,page,_=request('/')
status,page,_=form({'action':'login','csrf':csrf(page),'username':admin['username'],'password':admin['password']})
assert status==200
try:
    _,page,_=request('/?tab=users')
    fields={'action':'save_user','csrf':csrf(page),'id':'0','username':name,'password':password,'role':'guard','active':'1'}
    status,_,_=form({**fields,'csrf':'bad'})
    assert status==403,'User forms must enforce CSRF'
    status,page,_=form(fields)
    assert status==200 and name in page,'Create user failed'
    # Each account is enclosed in its own details element.
    row=next(r for r in re.findall(r'<details class="account">(.*?)</details>',page,re.S) if name in r)
    test_id=re.search(r'name="id" value="(\d+)"',row).group(1)
    status,_,_=form({**fields,'csrf':csrf(page)})
    assert status==409,'Duplicate username accepted'
    status,login=api('login',{'username':name,'password':password})
    assert status==200
    token=login['token']
    _,guest,_=request('/',client=other)
    status,_,_=form({'action':'login','csrf':csrf(guest),'username':name,'password':password},other)
    assert status==401,'Guard entered admin'
    _,page,_=request('/?tab=users')
    fields.update(id=test_id,csrf=csrf(page),password=updated,role='admin')
    status,page,_=form(fields)
    assert status==200,'Edit user failed'
    assert api('check',{'plate':'A123BC'},token)[0]==401,'Old token survived password change'
    assert api('login',{'username':name,'password':password})[0]==401,'Old password survived'
    _,guest,_=request('/',client=other)
    status,guest,_=form({'action':'login','csrf':csrf(guest),'username':name,'password':updated},other)
    assert status==200 and 'Список пропусков' in guest,'New administrator cannot log in'
    _,page,_=request('/?tab=users')
    fields.update(csrf=csrf(page),password=password)
    assert form(fields)[0]==200
    status,guest,_=request('/',client=other)
    assert 'Авторизация' in guest and 'Список пропусков' not in guest,'Password change did not revoke admin session'
    _,page,_=request('/?tab=users')
    fields.update(csrf=csrf(page),password='',role='guard',active='0')
    assert form(fields)[0]==200
    assert api('login',{'username':name,'password':password})[0]==401,'Inactive account logged in'
    _,page,_=request('/?tab=users')
    rootrow=next(r for r in re.findall(r'<details class="account">(.*?)</details>',page,re.S) if '>admin ·' in r)
    root_id=re.search(r'name="id" value="(\d+)"',rootrow).group(1)
    status,_,_=form({'action':'save_user','csrf':csrf(page),'id':root_id,'username':'admin','password':'','role':'guard','active':'1'})
    assert status==422,'Last admin protection missing'
    print('PASS: create, edit, role changes, duplicate protection, CSRF, disabled accounts, token/session revocation, last administrator protection.')
finally:
    # Cleanup through the already-authorized SSH connection, not a public endpoint.
    code="require '/home/c/cv339126/public_html/goscameracar/.ht-goscameracar/bootstrap.php'; $s=db()->prepare('DELETE FROM users WHERE username = ?'); $s->execute(['"+name+"']);"
    subprocess.run(['ssh','-i',str(Path.home()/'.ssh/timeweb_goscameracar'),'-o','BatchMode=yes','-o','StrictHostKeyChecking=yes','cv339126@vh460.timeweb.ru','php -r '+shlex.quote(code)],check=True)
    print('Temporary user removed.')

