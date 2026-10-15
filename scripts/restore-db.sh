#!/usr/bin/env sh
# Memulihkan cadangan ke basis data KIRA. MENIMPA isi basis data saat ini.
#   ./scripts/restore-db.sh backups/kira-20261015-030000.dump
# Latih ini sebelum benar-benar membutuhkannya: pulihkan ke mesin lain dan periksa aplikasinya jalan.
set -eu

FILE="${1:?Beri nama berkas cadangan (.dump)}"
[ -s "$FILE" ] || { echo "Berkas tidak ada atau kosong: $FILE" >&2; exit 1; }
COMPOSE="docker compose -f docker-compose.prod.yml"

printf "Ini MENGHAPUS data saat ini lalu memulihkan dari %s. Ketik 'pulihkan' untuk lanjut: " "$FILE"
read -r answer
[ "$answer" = "pulihkan" ] || { echo "Dibatalkan."; exit 1; }

$COMPOSE stop backend
$COMPOSE exec -T db pg_restore -U kira -d kira --clean --if-exists --no-owner < "$FILE"
$COMPOSE start backend
echo "Selesai. Periksa: curl https://\$KIRA_DOMAIN/health/ready"
