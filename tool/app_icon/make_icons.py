"""Regenerates every app icon file from the artwork defined below.

Run from the repository root:  python3 tool/app_icon/make_icons.py
Needs: pip install cairosvg pillow

Design: three task blocks ageing green -> amber -> red, the top one ticked,
on the app's teal. Everything is drawn on a 1024 x 1024 canvas.
"""
import io
import json
import os

import cairosvg
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))

BG_TOP, BG_BOTTOM = '#0f766e', '#134e4a'

# The blocks and tick, without a background. Kept inside the centre of the
# canvas so round and squircle masks never clip them.
ART = '''
<rect x="232" y="262" width="560" height="130" rx="40" fill="#4ade80"/>
<rect x="232" y="447" width="560" height="130" rx="40" fill="#fbbf24"/>
<rect x="232" y="632" width="560" height="130" rx="40" fill="#f87171"/>
<path d="M300 327 l42 42 l84 -84" fill="none" stroke="#14532d" stroke-width="34"
      stroke-linecap="round" stroke-linejoin="round"/>
<rect x="470" y="310" width="260" height="34" rx="17" fill="#14532d" opacity=".35"/>
<rect x="320" y="495" width="380" height="34" rx="17" fill="#78350f" opacity=".35"/>
<rect x="320" y="680" width="300" height="34" rx="17" fill="#7f1d1d" opacity=".35"/>
'''

GRADIENT = (f'<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">'
            f'<stop offset="0" stop-color="{BG_TOP}"/><stop offset="1" stop-color="{BG_BOTTOM}"/>'
            f'</linearGradient></defs>')


def svg(body, size=1024, view='0 0 1024 1024'):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" '
            f'viewBox="{view}">{body}</svg>')


def render(markup, px):
    data = cairosvg.svg2png(bytestring=markup.encode(), output_width=px, output_height=px)
    return Image.open(io.BytesIO(data)).convert('RGBA')


def full_square(px):
    """Edge-to-edge square: iOS masks it itself."""
    return render(svg(GRADIENT + '<rect width="1024" height="1024" fill="url(#g)"/>' + ART), px)


def rounded(px, inset=0, radius=225):
    """Rounded square for places that show the icon as is (legacy Android, web, Windows, macOS)."""
    size = 1024 - 2 * inset
    body = (GRADIENT.replace('id="g"', 'id="g" gradientUnits="userSpaceOnUse" '
                             f'x1="{inset}" y1="{inset}" x2="{1024 - inset}" y2="{1024 - inset}"')
            .replace('x1="0" y1="0" x2="1" y2="1"', '')
            + f'<rect x="{inset}" y="{inset}" width="{size}" height="{size}" rx="{radius * size / 1024}" fill="url(#g)"/>'
            + f'<g transform="translate({inset} {inset}) scale({size / 1024})">{ART}</g>')
    return render(svg(body), px)


def circle(px):
    body = GRADIENT + '<circle cx="512" cy="512" r="512" fill="url(#g)"/>' + ART
    return render(svg(body), px)


def adaptive_layer(px, foreground):
    """108dp adaptive-icon layer: the 1024 artwork fills the middle 72dp."""
    view = '-256 -256 1536 1536'
    if foreground:
        return render(svg(ART, view=view), px)
    return render(svg(GRADIENT.replace('x1="0" y1="0" x2="1" y2="1"',
                                       'gradientUnits="userSpaceOnUse" x1="-256" y1="-256" x2="1280" y2="1280"')
                      + '<rect x="-256" y="-256" width="1536" height="1536" fill="url(#g)"/>', view=view), px)


def save(img, path, rgb=False):
    path = os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if rgb:
        flat = Image.new('RGB', img.size, BG_BOTTOM)
        flat.paste(img, (0, 0), img)
        img = flat
    img.save(path, optimize=True)


def android():
    densities = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
    for name, scale in densities.items():
        res = f'android/app/src/main/res/mipmap-{name}/'
        save(rounded(int(48 * scale), inset=40, radius=200), res + 'ic_launcher.png')
        save(circle(int(48 * scale)), res + 'ic_launcher_round.png')
        save(adaptive_layer(int(108 * scale), True), res + 'ic_launcher_foreground.png')
        save(adaptive_layer(int(108 * scale), False), res + 'ic_launcher_background.png')


def ios_and_mac():
    for folder, maker, rgb in (
            ('ios/Runner/Assets.xcassets/AppIcon.appiconset', full_square, True),
            # macOS icons carry their own rounded shape with a margin around it.
            ('macos/Runner/Assets.xcassets/AppIcon.appiconset',
             lambda px: rounded(px, inset=100, radius=185), False)):
        contents = json.load(open(os.path.join(ROOT, folder, 'Contents.json')))
        for image in contents['images']:
            if 'filename' not in image:
                continue
            points = float(image['size'].split('x')[0])
            px = round(points * int(image['scale'].rstrip('x')))
            save(maker(px), f'{folder}/{image["filename"]}', rgb=rgb)


def web_and_windows():
    for px in (192, 512):
        save(rounded(px), f'web/icons/Icon-{px}.png')
        save(full_square(px), f'web/icons/Icon-maskable-{px}.png')
    save(rounded(32), 'web/favicon.png')
    rounded(256, inset=16, radius=200).save(
        os.path.join(ROOT, 'windows/runner/resources/app_icon.ico'),
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])


def _rrect(x, y, w, h, r):
    return (f'M{x + r},{y}h{w - 2 * r}a{r},{r} 0 0 1 {r},{r}v{h - 2 * r}a{r},{r} 0 0 1 -{r},{r}'
            f'h-{w - 2 * r}a{r},{r} 0 0 1 -{r},-{r}v-{h - 2 * r}a{r},{r} 0 0 1 {r},-{r}z')


# One-colour version (Android themed icons and the notification icon): the tick
# sits beside a shorter top block so the shape still reads in a single colour.
MONO_BARS = _rrect(472, 262, 320, 130, 40) + _rrect(232, 447, 560, 130, 40) + _rrect(232, 632, 560, 130, 40)
MONO_TICK = 'M262,327 l52,52 l104,-104'


def _vector(size_dp, view, pad):
    return f'''<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by tool/app_icon/make_icons.py -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="{size_dp}dp"
    android:height="{size_dp}dp"
    android:viewportWidth="{view}"
    android:viewportHeight="{view}">
    <group android:translateX="{pad}" android:translateY="{pad}">
        <path android:fillColor="#FFFFFFFF" android:pathData="{MONO_BARS}" />
        <path android:strokeColor="#FFFFFFFF" android:strokeWidth="48"
            android:strokeLineCap="round" android:strokeLineJoin="round"
            android:pathData="{MONO_TICK}" />
    </group>
</vector>
'''


def android_xml():
    res = os.path.join(ROOT, 'android/app/src/main/res')
    os.makedirs(f'{res}/mipmap-anydpi-v26', exist_ok=True)
    adaptive = '''<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by tool/app_icon/make_icons.py -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />
</adaptive-icon>
'''
    for name in ('ic_launcher', 'ic_launcher_round'):
        open(f'{res}/mipmap-anydpi-v26/{name}.xml', 'w').write(adaptive)
    # 108dp layer, artwork in the middle 72dp (viewport 1536 = 1024 * 108 / 72).
    open(f'{res}/drawable/ic_launcher_monochrome.xml', 'w').write(_vector(108, 1536, 256))
    # Status-bar icon: artwork spans x/y 232-792, so a 680 viewport fills 24dp with a small margin.
    open(f'{res}/drawable/ic_notification.xml', 'w').write(_vector(24, 680, -172))


def main():
    android()
    android_xml()
    ios_and_mac()
    web_and_windows()
    print('Icons written.')


if __name__ == '__main__':
    main()
