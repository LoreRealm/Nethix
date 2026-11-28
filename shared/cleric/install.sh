# install.sh — install cleric universally.
# Copies the dispatcher to /usr/local/bin, runes to /usr/local/lib/cleric,
# and spells to /usr/local/lib/cleric.d.
# Run: sudo ./install.sh   (chmod +x install.sh first)
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "run as root: sudo ./install.sh" >&2; exit 1; }

BIN=/usr/local/bin/cleric
LIBDIR=/usr/local/lib/cleric.d
RUNEDIR=/usr/local/lib/cleric

install -Dm755 cleric "$BIN"
mkdir -p "$LIBDIR" "$RUNEDIR"
for f in cleric.d/*.sh; do
    install -m755 "$f" "$LIBDIR/$(basename "$f")"
done
install -m755 runebar.sh "$RUNEDIR/runebar.sh"

if [[ ! -f /etc/cleric.conf ]]; then
    install -m644 cleric.conf.example /etc/cleric.conf
    echo "installed default config to /etc/cleric.conf"
fi

echo "installed: $BIN"
echo "spells:    $LIBDIR"
echo "runes:     $RUNEDIR/runebar.sh"
echo "run 'cleric --list' to verify."
