#!/usr/bin/env bash
# z3wax TV (Telefon TV) — Ubuntu kompyuterga o‘rnatish (sudo shart emas).
#
#   ./install.sh               — o‘rnatish, menyuga “z3wax TV” qo‘shish
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
  echo "z3wax TV o‘chirildi."
  exit 0
fi

# Video, jonli kanallar va musiqa uchun libmpv kerak.
if ! ldconfig -p 2>/dev/null | grep 'libmpv\.so' >/dev/null; then
  echo "Avval video kutubxonasini o‘rnating:"
  echo "  Ubuntu 24.04 va yangisi:  sudo apt install libmpv2"
  echo "  Ubuntu 22.04:             sudo apt install libmpv1"
  exit 1
fi

# Saytlar va YouTube ilovaning o‘zida WebKitGTK orqali ishlaydi.
if ! ldconfig -p 2>/dev/null | grep 'libwebkit2gtk-4\.[01]' >/dev/null; then
  echo "Ichki brauzer kutubxonalarini o‘rnating:"
  echo "  sudo apt install libwebkit2gtk-4.1-0 gstreamer1.0-libav gstreamer1.0-plugins-good gstreamer1.0-plugins-bad"
  exit 1
fi

# AI javobini ovoz chiqarib aytish uchun.
missing=""
command -v espeak-ng >/dev/null 2>&1 || missing="$missing espeak-ng"
if [ -n "$missing" ]; then
  echo "Tavsiya (ovozli javob):  sudo apt install$missing"
fi

rm -rf "$dest"
mkdir -p "$dest" "$apps" "$icons"
cp -r "$here/bundle/." "$dest/"
cp "$here/telefon-tv.png" "$icons/telefon-tv.png"
# Menyudagi belgi darrov yangilansin.
command -v gtk-update-icon-cache >/dev/null 2>&1 &&
  gtk-update-icon-cache -q -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true

cat > "$apps/telefon-tv.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=z3wax TV
GenericName=Smart TV
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
Name=z3wax TV (fonda)
Comment=Televizor ulanganda z3wax TV o‘zi ochiladi
Exec=$dest/telefon_tv --background
Icon=telefon-tv
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
  echo "Kompyuter yoqilganda z3wax TV fonda ishga tushadi."
fi

echo "Tayyor. Menyudan “z3wax TV” ni oching yoki: $dest/telefon_tv"
echo "Televizor qaysi ekranligini qo‘lda tanlash: TELEFON_TV_MONITOR=1 $dest/telefon_tv"
