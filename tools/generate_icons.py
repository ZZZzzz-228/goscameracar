from pathlib import Path
from PIL import Image, ImageFont, ImageDraw
import json
root=Path(__file__).resolve().parents[1]
font_path=Path(r'C:/Users/kucer/develop/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
font=ImageFont.truetype(str(font_path),800)
def make_icon(size,foreground=False):
    im=Image.new('RGBA',(1024,1024),(0,0,0,0) if foreground else '#172b35')
    d=ImageDraw.Draw(im)
    bounds=d.textbbox((0,0),chr(0xf379),font=font)
    glyph=Image.new('RGBA',(bounds[2]-bounds[0],bounds[3]-bounds[1]),(0,0,0,0))
    ImageDraw.Draw(glyph).text((-bounds[0],-bounds[1]),chr(0xf379),font=font,fill='#e7be67')
    limit=550 if foreground else 650
    glyph.thumbnail((limit,limit),Image.Resampling.LANCZOS)
    im.alpha_composite(glyph,((1024-glyph.width)//2,(1024-glyph.height)//2))
    return im.resize((size,size),Image.Resampling.LANCZOS)
make_icon(1024).convert('RGB').save(root/'assets/app_icon.png')
res=root/'android/app/src/main/res'
for density,size in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
    folder=res/('mipmap-'+density);folder.mkdir(exist_ok=True)
    make_icon(size).save(folder/'ic_launcher.png')
(res/'drawable').mkdir(exist_ok=True)
make_icon(432,True).save(res/'drawable/ic_launcher_foreground.png')
(res/'mipmap-anydpi-v26').mkdir(exist_ok=True)
(res/'mipmap-anydpi-v26/ic_launcher.xml').write_text('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
<background android:drawable="@color/ic_launcher_background"/>
<foreground android:drawable="@drawable/ic_launcher_foreground"/>
</adaptive-icon>''')
(res/'values/icon_colors.xml').write_text('<resources><color name="ic_launcher_background">#172B35</color></resources>')
folder=root/'ios/Runner/Assets.xcassets/AppIcon.appiconset'
for entry in json.loads((folder/'Contents.json').read_text())['images']:
    size=round(float(entry['size'].split('x')[0])*float(entry['scale'][:-1]))
    make_icon(size).convert('RGB').save(folder/entry['filename'])
for size in [192,512]:
    for name in [f'Icon-{size}.png',f'Icon-maskable-{size}.png']:
        make_icon(size).save(root/'web/icons'/name)
make_icon(32).save(root/'web/favicon.png')
print('Shield icons generated for Android, iOS and web.')
