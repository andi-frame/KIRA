from app.tools.faskes import cari_faskes
from app.tools.nutrition import cari_gizi
from app.tools.plan import rencana_hari_ini, rencana_minggu, riwayat_makan
from app.tools.risk import hitung_risiko
from app.tools.targets import sisa_target_harian
from app.tools.whatif import simulasi_whatif

TOOLS = [cari_gizi, sisa_target_harian, hitung_risiko, simulasi_whatif, cari_faskes, rencana_hari_ini, rencana_minggu,
         riwayat_makan]
