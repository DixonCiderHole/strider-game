"""Inventory icons for the newer items, in the same style as the others
(icons/items/source_svg: 128 px SVG, dark outline, gradient fills, glow),
rendered to icons/items/<id>.png at 256 px.

python3 tools/icon_gen.py
"""
import os, re, subprocess

ROOT = os.path.join(os.path.dirname(__file__), "..", "icons", "items")
SRC = os.path.join(ROOT, "source_svg")
HEAD = open(os.path.join(SRC, "grenade.svg")).read().split("</defs>")[0] + \
    '<linearGradient id="teal" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#a8fff0"/><stop offset="1" stop-color="#1f9a8a"/></linearGradient>' \
    '<linearGradient id="blue" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#cfe9ff"/><stop offset="1" stop-color="#2f78d8"/></linearGradient>' \
    '<linearGradient id="orange" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffb070"/><stop offset="1" stop-color="#d4570c"/></linearGradient>' \
    '<linearGradient id="white" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff"/><stop offset="1" stop-color="#bfc6cc"/></linearGradient>' \
    '</defs><g filter="url(#shadow)">'
TAIL = "</g></svg>"
K = 'stroke="#0b0d10" stroke-width="3" stroke-linejoin="round"'
K5 = 'stroke="#0b0d10" stroke-width="5" stroke-linejoin="round"'


def module(col, glyph):
    gear = ("M110.0 64.0 L98.2 75.1 L101.2 91.0 L85.2 93.1 L78.2 107.7 L64.0 100.0 L49.8 107.7 L42.8 93.1 L26.8 91.0 "
            "L29.8 75.1 L18.0 64.0 L29.8 52.9 L26.8 37.0 L42.8 34.9 L49.8 20.3 L64.0 28.0 L78.2 20.3 L85.2 34.9 L101.2 37.0 L98.2 52.9 Z")
    return (f'<path d="{gear}" fill="url(#metal)" {K}/><circle cx="64" cy="64" r="24" fill="url(#dark)" {K}/>'
            f'<g filter="url(#glow)" stroke="{col}" fill="none" stroke-width="4" stroke-linecap="round">{glyph}</g>')


def grenade_body(fill, band, glow_col, mark=""):
    if not mark:
        mark = '<circle cx="66" cy="74" r="6" fill="%s"/>' % glow_col
    return (f'<rect x="54" y="16" width="24" height="16" rx="3" fill="url(#metal)" {K}/>'
            '<path d="M76 24 C96 22 104 34 98 46" fill="none" stroke="#0b0d10" stroke-width="7" stroke-linecap="round"/>'
            '<path d="M76 24 C96 22 104 34 98 46" fill="none" stroke="#cfd6dd" stroke-width="3" stroke-linecap="round"/>'
            f'<rect x="38" y="30" width="56" height="80" rx="10" fill="{fill}" {K}/>'
            f'<rect x="38" y="52" width="56" height="10" fill="{band}" {K}/><rect x="38" y="86" width="56" height="10" fill="{band}" {K}/>'
            f'<g filter="url(#glow)">{mark}</g>')


ICONS = {
    "heavy_cell": (f'<rect x="22" y="34" width="84" height="60" rx="10" fill="url(#dark)" {K}/>'
                   f'<rect x="16" y="46" width="10" height="36" rx="3" fill="url(#metal)" {K}/><rect x="102" y="46" width="10" height="36" rx="3" fill="url(#metal)" {K}/>'
                   '<g filter="url(#glow)"><rect x="32" y="44" width="64" height="40" rx="6" fill="url(#red)"/></g>'
                   '<path d="M40 54 L88 54 M40 64 L88 64 M40 74 L88 74" stroke="#5a0a05" stroke-width="2" opacity=".6"/>'
                   '<path d="M66 46 L56 64 L64 64 L58 82 L72 58 L64 58 L70 46 Z" fill="#fff0e8"/>'),
    "fuel": (f'<rect x="56" y="12" width="16" height="12" rx="2" fill="url(#metal)" {K}/>'
             f'<path d="M40 30 Q40 22 50 22 L78 22 Q88 22 88 30 L92 104 Q92 114 82 114 L46 114 Q36 114 36 104 Z" fill="url(#orange)" {K}/>'
             f'<rect x="36" y="48" width="56" height="8" fill="#2b2d31" {K}/><rect x="36" y="92" width="56" height="8" fill="#2b2d31" {K}/>'
             '<g filter="url(#glow)"><path d="M64 60 C56 70 54 76 58 82 C61 86 67 86 70 82 C74 76 70 70 64 60 Z" fill="#ffe39a"/></g>'
             '<path d="M64 68 C60 74 60 78 62 80" stroke="#f08a1c" stroke-width="2" fill="none"/>'),
    "crystal": ('<g filter="url(#glow)">'
                f'<path d="M64 10 L80 40 L74 112 L54 112 L48 40 Z" fill="url(#cyan)" {K}/>'
                f'<path d="M38 44 L50 60 L48 112 L34 112 L28 62 Z" fill="url(#blue)" {K}/>'
                f'<path d="M92 50 L102 66 L96 112 L80 112 L82 66 Z" fill="url(#blue)" {K}/></g>'
                '<path d="M64 16 L64 106 M56 44 L60 100" stroke="#ffffff" stroke-width="2" opacity=".6"/>'
                f'<path d="M20 112 L108 112" {K} stroke-linecap="round"/>'),
    "flashbang": grenade_body("url(#white)", "#5a616b", "#ffffff",
                              '<circle cx="66" cy="74" r="9" fill="#ffffff"/><path d="M66 56 L66 64 M66 84 L66 92 M48 74 L56 74 M76 74 L84 74" stroke="#fff6c0" stroke-width="3"/>'),
    "smoke_grenade": grenade_body("#7e8580", "#3b3f3d", "#d0d4d0",
                                  '<circle cx="54" cy="22" r="8" fill="#c9cdc9" opacity=".8"/><circle cx="44" cy="14" r="6" fill="#c9cdc9" opacity=".6"/><circle cx="66" cy="74" r="6" fill="#e0e4e0"/>'),
    "stun_grenade": grenade_body("#2d4f7c", "#162638", "#7fd0ff",
                                 '<path d="M70 58 L58 76 L66 76 L60 92 L76 70 L68 70 L74 58 Z" fill="#bfeaff"/>'),
    "thermal": (f'<circle cx="64" cy="66" r="42" fill="url(#metal)" {K}/>'
                f'<path d="M22 66 L106 66" {K}/><circle cx="64" cy="66" r="16" fill="url(#dark)" {K}/>'
                '<g filter="url(#glow)"><circle cx="64" cy="66" r="9" fill="url(#cyan)"/>'
                '<rect x="36" y="44" width="10" height="6" rx="2" fill="#ff5a3d"/><rect x="82" y="44" width="10" height="6" rx="2" fill="#ff5a3d"/></g>'
                '<path d="M34 86 L46 86 M82 86 L94 86" stroke="#0b0d10" stroke-width="3"/>'),
    "trauma_kit": (f'<rect x="16" y="36" width="96" height="70" rx="10" fill="url(#white)" {K}/>'
                   f'<path d="M48 36 L48 26 Q48 20 54 20 L74 20 Q80 20 80 26 L80 36" fill="none" {K5}/>'
                   f'<rect x="16" y="54" width="96" height="10" fill="url(#orange)" {K}/>'
                   '<g filter="url(#glow)"><circle cx="64" cy="82" r="15" fill="#1f9a8a"/>'
                   '<path d="M64 72 L64 92 M54 82 L74 82" stroke="#ffffff" stroke-width="6"/></g>'),
    "antivenom": (f'<rect x="52" y="10" width="24" height="14" rx="3" fill="url(#metal)" {K}/>'
                  f'<rect x="44" y="22" width="40" height="70" rx="8" fill="url(#dark)" {K}/>'
                  '<g filter="url(#glow)"><rect x="52" y="32" width="24" height="50" rx="4" fill="url(#teal)"/></g>'
                  f'<path d="M64 92 L64 116" {K5}/><path d="M64 92 L64 116" stroke="#cfd6dd" stroke-width="2"/>'
                  '<path d="M58 44 L70 44 M58 56 L70 56 M58 68 L70 68" stroke="#0b5a50" stroke-width="2"/>'),
    "coagulant": (f'<rect x="40" y="18" width="48" height="16" rx="4" fill="url(#metal)" {K}/>'
                  f'<path d="M36 34 L92 34 L88 108 Q88 114 82 114 L46 114 Q40 114 40 108 Z" fill="url(#dark)" {K}/>'
                  '<g filter="url(#glow)"><path d="M44 62 L84 62 L82 104 L46 104 Z" fill="url(#green)"/></g>'
                  '<circle cx="56" cy="80" r="4" fill="#efffd8" opacity=".8"/><circle cx="70" cy="90" r="3" fill="#efffd8" opacity=".7"/>'),
    "control_chip": (f'<rect x="30" y="30" width="68" height="68" rx="6" fill="url(#dark)" {K}/>'
                     + "".join(f'<path d="M{x} 30 L{x} 18 M{x} 98 L{x} 110" {K}/>' for x in (42, 56, 70, 84))
                     + "".join(f'<path d="M30 {y} L18 {y} M98 {y} L110 {y}" {K}/>' for y in (42, 56, 70, 84))
                     + '<g filter="url(#glow)"><rect x="46" y="46" width="36" height="36" rx="4" fill="url(#red)"/></g>'
                     '<path d="M52 56 L76 56 M52 64 L70 64 M52 72 L76 72" stroke="#ffd6cf" stroke-width="3"/>'),
    "glowcap": (f'<path d="M64 112 Q30 96 22 70 Q44 78 60 102 Z" fill="#1f4a38" {K}/>'
                f'<path d="M64 112 Q98 96 106 70 Q84 78 68 102 Z" fill="#1f4a38" {K}/>'
                f'<path d="M64 112 L54 60 M64 112 L66 48 M64 112 L80 64" {K5} fill="none"/>'
                '<path d="M64 112 L54 60 M64 112 L66 48 M64 112 L80 64" stroke="#7aa05a" stroke-width="2" fill="none"/>'
                '<g filter="url(#glow)"><circle cx="54" cy="54" r="10" fill="url(#green)"/><circle cx="66" cy="40" r="12" fill="url(#green)"/><circle cx="82" cy="58" r="9" fill="url(#green)"/></g>'),
    "medpack": (f'<rect x="22" y="34" width="84" height="70" rx="16" fill="#4b5a3c" {K}/>'
                f'<path d="M22 56 Q64 66 106 56" fill="none" {K}/>'
                f'<rect x="40" y="24" width="48" height="14" rx="5" fill="url(#orange)" {K}/>'
                '<g filter="url(#glow)"><circle cx="64" cy="80" r="15" fill="#1f9a8a"/>'
                '<path d="M64 70 L64 90 M54 80 L74 80" stroke="#ffffff" stroke-width="6"/></g>'),
    "tissue": (f'<rect x="46" y="12" width="36" height="14" rx="3" fill="url(#metal)" {K}/>'
               f'<rect x="48" y="26" width="32" height="76" rx="6" fill="#cfe9f0" fill-opacity=".35" {K}/>'
               f'<rect x="46" y="102" width="36" height="14" rx="3" fill="url(#metal)" {K}/>'
               '<g filter="url(#glow)"><path d="M64 34 L72 60 L66 94 L58 92 L56 58 Z" fill="url(#cyan)"/></g>'
               '<path d="M58 70 Q50 76 56 84" stroke="#b33a3a" stroke-width="4" fill="none"/>'),
    "mod_nanite": module("#5cf08a", '<circle cx="64" cy="64" r="11"/><path d="M64 56 L64 72 M56 64 L72 64"/>'),
    "mod_armor": module("#e0b070", '<path d="M64 50 L76 55 L76 66 Q76 76 64 80 Q52 76 52 66 L52 55 Z"/>'),
    "mod_crit": module("#5fd0ff", '<circle cx="64" cy="64" r="11"/><path d="M64 48 L64 56 M64 72 L64 80 M48 64 L56 64 M72 64 L80 64"/>'),
    "mod_loader": module("#ffb050", '<path d="M54 56 L74 56 M54 64 L74 64 M54 72 L74 72"/><path d="M72 50 L80 56 L72 62" />'),
    "mod_cooling": module("#8fd8ff", '<path d="M64 50 L64 78 M52 57 L76 71 M52 71 L76 57"/>'),
}


def main():
    for k, body in ICONS.items():
        svg = HEAD + body + TAIL
        p = os.path.join(SRC, k + ".svg")
        open(p, "w").write(svg)
        subprocess.run(["rsvg-convert", "-w", "256", "-h", "256", p, "-o", os.path.join(ROOT, k + ".png")], check=True)
    print("wrote", len(ICONS), "icons")


if __name__ == "__main__":
    main()
