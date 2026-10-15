#!/usr/bin/env sh
# Cadangan basis data KIRA (pg_dump format kustom, terkompresi). Jalankan di server produksi:
#   ./scripts/backup-db.sh [folder-tujuan]
# Jadwalkan dengan cron, mis. tiap hari 03.00:  0 3 * * *  cd /opt/kira && ./scripts/backup-db.sh /var/backups/kira
# Simpan salinan DI LUAR server (mis. rclone ke penyimpanan objek): cadangan di mesin yang sama tidak menolong bila mesinnya hilang.
set -eu

DEST="${1:-./backups}"
KEEP_DAYS="${KEEP_DAYS:-14}"
COMPOSE="docker compose -f docker-compose.prod.yml"

mkdir -p "$DEST"
FILE="$DEST/kira-$(date +%Y%m%d-%H%M%S).dump"

$COMPOSE exec -T db pg_dump -U kira -Fc kira > "$FILE"
[ -s "$FILE" ] || { echo "Cadangan kosong, dibatalkan." >&2; rm -f "$FILE"; exit 1; }
chmod 600 "$FILE"
echo "Tersimpan: $FILE ($(wc -c < "$FILE") byte)"

# Hapus yang lebih tua dari KEEP_DAYS hari.
find "$DEST" -name 'kira-*.dump' -mtime +"$KEEP_DAYS" -delete
