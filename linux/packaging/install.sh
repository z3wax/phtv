#!/usr/bin/env bash
# Telefon TV — Ubuntu kompyuterga o‘rnatish (sudo shart emas).
#
#   ./install.sh               — o‘rnatish, menyuga “Telefon TV” qo‘shish
#   ./install.sh --autostart   — kompyuter yoqilganda fonda ishga tushsin:
#                                televizor (HDMI) ulanganda o‘zi paydo bo‘ladi
#   ./install.sh --remove      — o‘chirish
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
dest="$HOME/.local/opt/telefon-tv"
apps="$HOME/.local/share/applications"
icons="$HOME/.local/share/icons/hicolor/256x256/apps"
autostart="$HOME/.config/autostart"

if [ "${1:-}" = "--remove" ]; then
  rm -rf "$dest" "$apps/telefon-tv.desktop" "$icons/telefon-tv.png" "$autostart/telefon-tv.desktop"
  echo "Telefon TV o‘chirildi."
  exit 0
fi

# Video, jonli kanallar va musiqa uchun libmpv kerak.
if ! ldconfig -p 2>/dev/null | grep -q 'libmpv\.so'; then
  echo "Avval video kutubxonasini o‘rnating:"
  echo "  Ubuntu 24.04 va yangisi:  sudo apt install libmpv2"
  echo "  Ubuntu 22.04:             sudo apt install libmpv1"
  exit 1
fi

# Ixtiyoriy, lekin tavsiya: YouTube va saytlar Chrome’da televizorda ochilib,
# telefondagi pult bilan boshqarilishi uchun (xdotool), AI javobini ovoz
# chiqarib aytish uchun (espeak-ng).
missing=""
command -v xdotool >/dev/null 2>&1 || missing="$missing xdotool"
command -v espeak-ng >/dev/null 2>&1 || missing="$missing espeak-ng"
if ! command -v google-chrome >/dev/null 2>&1 && ! command -v chromium >/dev/null 2>&1 \
  && ! command -v chromium-browser >/dev/null 2>&1; then
  missing="$missing chromium-browser"
fi
if [ -n "$missing" ]; then
  echo "Tavsiya (YouTube pult bilan, ovozli javob):  sudo apt install$missing"
fi

rm -rf "$dest"
mkdir -p "$dest" "$apps" "$icons"
cp -r "$here/bundle/." "$dest/"
cp "$here/telefon-tv.png" "$icons/telefon-tv.png"

cat > "$apps/telefon-tv.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Telefon TV
Comment=Televizorni Smart TV ga aylantiradi (HDMI)
Exec=$dest/telefon_tv
Icon=telefon-tv
Terminal=false
Categories=AudioVideo;Video;Player;TV;
StartupWMClass=uz.telefontv.telefon_tv
EOF

if [ "${1:-}" = "--autostart" ]; then
  mkdir -p "$autostart"
  cat > "$autostart/telefon-tv.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Telefon TV (fonda)
Comment=Televizor ulanganda Telefon TV o‘zi ochiladi
Exec=$dest/telefon_tv --background
Icon=telefon-tv
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
  echo "Kompyuter yoqilganda Telefon TV fonda ishga tushadi."
fi

echo "Tayyor. Menyudan “Telefon TV” ni oching yoki: $dest/telefon_tv"
echo "Televizor qaysi ekranligini qo‘lda tanlash: TELEFON_TV_MONITOR=1 $dest/telefon_tv"
