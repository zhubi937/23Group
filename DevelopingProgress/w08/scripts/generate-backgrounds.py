"""Original SVG silk folds. No downloaded textures, runtime animation or blur filters."""
from pathlib import Path

PALETTES = {
    'rose': ('#FAF5F3','#E7C0B9','#C9A68F','#FFFDF9'),
    'blue': ('#F4F7FB','#B9CDDF','#8FAABB','#FFFDF9'),
    'matcha': ('#F5F8F1','#C2D1B4','#A4B799','#FFFDF5'),
    'purple': ('#F8F5FB','#D6C7E3','#B7AACB','#FFFDFB'),
    'silver': ('#F5F7FA','#CED8E3','#AEBECB','#FFFFFF'),
    'apricot': ('#FBF6F0','#E7C9AD','#C9B598','#FFFEF9'),
}
DEST = Path(__file__).resolve().parents[1]/'entry/src/main/resources/base/media'
for name, (base, tint, shade, pearl) in PALETTES.items():
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="480" height="1040" viewBox="0 0 480 1040">
<defs>
 <linearGradient id="wash" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="480" y2="1040"><stop stop-color="{pearl}"/><stop offset="47%" stop-color="{base}"/><stop offset="100%" stop-color="{tint}"/></linearGradient>
 <linearGradient id="fold" gradientUnits="userSpaceOnUse" x1="38" y1="312" x2="456" y2="832"><stop stop-color="{base}"/><stop offset="38%" stop-color="{pearl}"/><stop offset="59%" stop-color="{tint}"/><stop offset="72%" stop-color="{shade}" stop-opacity=".55"/><stop offset="86%" stop-color="{pearl}"/><stop offset="100%" stop-color="{base}"/></linearGradient>
 <linearGradient id="light" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="480" y2="1040"><stop stop-color="{pearl}" stop-opacity=".06"/><stop offset="48%" stop-color="{pearl}" stop-opacity=".9"/><stop offset="66%" stop-color="{tint}" stop-opacity=".18"/><stop offset="100%" stop-color="{pearl}" stop-opacity=".76"/></linearGradient>
 <linearGradient id="low" gradientUnits="userSpaceOnUse" x1="0" y1="650" x2="480" y2="1040"><stop stop-color="{tint}" stop-opacity=".08"/><stop offset="52%" stop-color="{shade}" stop-opacity=".36"/><stop offset="63%" stop-color="{pearl}" stop-opacity=".9"/><stop offset="100%" stop-color="{tint}" stop-opacity=".5"/></linearGradient>
</defs>
<path d="M0 0H480V1040H0Z" fill="url(#wash)"/>
<path d="M315 -90C110 110 500 180 410 400S30 615 115 790 420 920 265 1120H580V-90Z" fill="url(#fold)" opacity=".82"/>
<path d="M420 -20C200 155 580 254 390 467S85 603 170 812 480 880 295 1110H520V-20Z" fill="url(#light)"/>
<path d="M-90 560C115 660 300 565 405 707S290 905 565 986V1090H-90Z" fill="url(#low)"/>
<path d="M-80 775C94 906 245 746 407 843S390 984 565 1045V1120H-80Z" fill="url(#light)" opacity=".8"/>
<path d="M315 -90C110 110 500 180 410 400S30 615 115 790 420 920 265 1120" fill="none" stroke="{pearl}" stroke-opacity=".58" stroke-width="1.4"/>
</svg>'''
    (DEST/f'silk_{name}.svg').write_text(svg, encoding='utf-8')
print('Generated six original silk backgrounds.')
