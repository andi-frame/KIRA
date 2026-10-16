"""Bangun seed/components.json: bahan/komponen sederhana untuk memecah hidangan (ayam geprek = ayam + nasi + timun + sambal).

Dijalankan SEKALI oleh pengembang (butuh internet); hasilnya dikomit. Tidak dipanggil saat runtime atau tes.

    uv run python -m seed.fetch_components

Asal tiap angka (per 100 g bagian yang dapat dimakan):
- TKPI Kemenkes 2017 (panganku.org) bila ada padanan: energi, lemak, karbohidrat, natrium.
- USDA FoodData Central, SR Legacy (domain publik) untuk bahan tanpa padanan TKPI, dan untuk GULA (TKPI tidak memuatnya)
  serta natrium yang tidak tersedia di TKPI. Diambil dari berkas unduhan resmi (bukan API), jadi tanpa kunci dan tanpa batas permintaan.
- ESTIMASI KIRA bila tidak ada padanan sama sekali; nilainya tertulis di bawah dan ditandai di source_note.
Porsi khas (default_portion_g) selalu asumsi KIRA. Alias tidak boleh sama dengan nama/alias di foods.json
(tes seed memeriksanya): "tahu", "tempe", "kangkung", "kerupuk" tetap berarti hidangan jadi yang sudah ada.
"""
import csv
import io
import json
import re
import urllib.parse
import urllib.request
import zipfile
from dataclasses import dataclass, field
from pathlib import Path

SEED_DIR = Path(__file__).resolve().parent
OUT = SEED_DIR / "components.json"
TKPI_URL = "https://www.panganku.org/id-ID/view"
USDA_ZIP = "https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_csv_2018-04.zip"
USDA_NUTRIENTS = {"1008": "kcal", "1004": "fat_g", "1093": "sodium_mg", "2000": "sugar_g", "1005": "carb_g"}
KEYS = ("sugar_g", "sodium_mg", "fat_g", "kcal", "carb_g")


@dataclass
class Spec:
    id: str
    name: str
    aliases: list[str]
    portion_g: float
    tkpi: str | None = None  # kode TKPI: energi/lemak/karbohidrat/natrium
    usda: int | None = None  # fdcId SR Legacy: gula, natrium bila TKPI kosong, atau semua nilai bila tanpa TKPI
    estimate: dict[str, float] = field(default_factory=dict)  # nilai yang tidak bersumber (ESTIMASI KIRA)
    why: str = ""  # alasan estimasi / catatan padanan


SPECS = [
    # Makanan pokok
    Spec("nasi_merah", "Nasi merah", ["nasi beras merah"], 150, tkpi="AP005", usda=169704),
    Spec("mi_basah", "Mi basah", ["mie basah", "mi kuning", "mie kuning"], 150, tkpi="AP021", usda=168919),
    Spec("bihun_rebus", "Bihun rebus", ["bihun"], 100, usda=168914, why="padanan USDA: rice noodles, cooked"),
    Spec("kentang_rebus", "Kentang rebus", ["kentang"], 100, usda=170440),
    # Lauk
    Spec("ayam_goreng_tepung", "Ayam goreng tepung", ["ayam krispi", "ayam crispy", "ayam tepung", "fried chicken"], 100,
         usda=172374, estimate={"sugar_g": 0.5},
         why="padanan USDA: drumstick, meat and skin, fried, batter; USDA tidak memuat gula, gula estimasi"),
    Spec("ayam_rebus", "Ayam rebus/suwir", ["ayam suwir", "suwiran ayam", "ayam rebus"], 50, usda=171451),
    Spec("lele_goreng", "Lele goreng", ["lele"], 100, usda=174187, estimate={"sugar_g": 0.5},
         why="padanan USDA: channel catfish, breaded and fried; gula estimasi"),
    Spec("nila_goreng", "Nila/mujair goreng", ["nila goreng", "mujair goreng", "ikan nila"], 100, tkpi="GP020", usda=175177,
         why="TKPI: ikan mujahir goreng; gula dari tilapia USDA"),
    Spec("tahu_putih", "Tahu putih", ["tahu mentah", "tahu kukus"], 50, tkpi="CP061", usda=172476),
    Spec("tempe_mentah", "Tempe mentah", ["tempe kedelai"], 50, tkpi="CP077", usda=174272, estimate={"sugar_g": 0.5},
         why="USDA tempeh tidak memuat gula; gula estimasi"),
    Spec("telur_ayam", "Telur ayam", ["telur"], 55, tkpi="HR002", usda=171287),
    Spec("daging_sapi_masak", "Daging sapi masak", ["daging sapi", "daging"], 50, usda=169488,
         why="padanan USDA: brisket, braised (tanpa bumbu)"),
    Spec("udang_rebus", "Udang", ["udang"], 50, usda=171971),
    # Sayur dan lalapan
    Spec("timun", "Timun", ["ketimun", "mentimun"], 30, tkpi="DR109", usda=168409),
    Spec("tomat", "Tomat", [], 30, tkpi="DR161", usda=170457),
    Spec("kol", "Kol", ["kubis"], 30, tkpi="DR044", usda=169975),
    Spec("selada", "Selada", [], 15, tkpi="DR145", usda=169249),
    Spec("kemangi", "Kemangi", [], 5, usda=172232, why="padanan USDA: basil, fresh"),
    Spec("tauge", "Tauge", ["toge", "kecambah"], 30, tkpi="DR002", usda=169957),
    Spec("daun_singkong_rebus", "Daun singkong rebus", ["daun singkong"], 50, tkpi="DP008", usda=169304,
         why="gula dari daun ubi jalar kukus USDA (tidak ada daun singkong di SR Legacy)"),
    Spec("kangkung_rebus", "Kangkung rebus", ["kangkung kukus"], 50, tkpi="DP014", usda=168463,
         why="gula dari bayam rebus USDA (tidak ada kangkung rebus di SR Legacy)"),
    Spec("bayam_rebus", "Bayam rebus", ["bayam"], 50, tkpi="DP002", usda=168463),
    Spec("wortel_rebus", "Wortel rebus", ["wortel"], 30, tkpi="DP020", usda=170394),
    Spec("kacang_panjang_rebus", "Kacang panjang rebus", ["kacang panjang"], 30, tkpi="DP012", usda=169141),
    Spec("buncis_rebus", "Buncis rebus", ["buncis"], 30, tkpi="DP003", usda=169141),
    Spec("labu_siam", "Labu siam", [], 50, tkpi="DR123", usda=170402),
    Spec("terong", "Terong", ["terung"], 50, tkpi="DR154", usda=169228),
    Spec("sawi", "Sawi", ["sawi hijau", "caisim"], 50, tkpi="DR141", usda=169256),
    # Sambal, saus, bumbu, lemak
    Spec("sambal_bawang", "Sambal bawang", ["sambal", "sambel", "sambel bawang"], 20,
         estimate={"sugar_g": 4, "sodium_mg": 900, "fat_g": 10, "kcal": 130, "carb_g": 9},
         why="resep rumahan: cabai, bawang, minyak, garam; tidak ada padanan TKPI/USDA"),
    Spec("sambal_terasi", "Sambal terasi", ["sambel terasi"], 20,
         estimate={"sugar_g": 5, "sodium_mg": 1100, "fat_g": 6, "kcal": 100, "carb_g": 10},
         why="resep rumahan: cabai, tomat, terasi, minyak, garam; tidak ada padanan TKPI/USDA"),
    Spec("kecap_manis", "Kecap manis", ["kecap"], 10,
         estimate={"sugar_g": 55, "sodium_mg": 3000, "fat_g": 0.5, "kcal": 280, "carb_g": 66},
         why="kecap manis tidak ada di TKPI (NP005 adalah kecap biasa, karbohidrat 9 g) maupun USDA; semua nilai estimasi"),
    Spec("saus_tomat", "Saus tomat", ["saos tomat", "saus"], 15, tkpi="NP009", usda=168556),
    Spec("saus_sambal", "Saus sambal botol", ["saos sambal", "saus cabai"], 15, usda=171186,
         why="padanan USDA: sauce, hot chile, sriracha"),
    Spec("mayones", "Mayones", ["mayonnaise", "mayo"], 15, usda=171009),
    Spec("bumbu_kacang", "Bumbu kacang", ["saus kacang", "bumbu pecel", "bumbu gado-gado"], 50, usda=171575,
         why="padanan USDA: peanut sauce made from coconut, water, sugar, peanuts"),
    Spec("santan", "Santan", ["kuah santan"], 50, tkpi="KP003", usda=170172),
    Spec("kuah_kaldu", "Kuah kaldu", ["kuah soto", "kuah bakso", "kaldu", "kuah"], 250, usda=174536,
         why="padanan USDA: chicken broth, ready-to-serve"),
    Spec("gula_pasir", "Gula pasir", ["gula"], 10, tkpi="MP007", usda=169655),
    Spec("gula_aren", "Gula aren", ["gula merah", "gula jawa"], 10, tkpi="MP005", usda=168833,
         why="gula dari brown sugar USDA"),
    Spec("minyak_goreng", "Minyak goreng", ["minyak sawit", "minyak"], 10, tkpi="KR012", usda=171015),
    Spec("margarin", "Margarin", ["mentega"], 10, tkpi="KP001", usda=172346),
    Spec("bawang_goreng", "Bawang goreng", [], 5,
         estimate={"sugar_g": 20, "sodium_mg": 30, "fat_g": 30, "kcal": 480, "carb_g": 50},
         why="bawang merah digoreng; tidak ada padanan TKPI/USDA"),
    # Pelengkap
    Spec("kerupuk_udang", "Kerupuk udang", ["krupuk udang"], 15, tkpi="BP045", estimate={"sugar_g": 3},
         why="gula estimasi (TKPI tidak memuat gula; kerupuk udang USDA bergaya camilan manis, tidak sepadan)"),
    Spec("emping", "Emping", ["emping melinjo"], 15, tkpi="CP024", estimate={"sugar_g": 1, "sodium_mg": 300},
         why="gula dan natrium estimasi"),
    Spec("kacang_tanah_goreng", "Kacang tanah goreng", ["kacang goreng", "kacang"], 15, tkpi="CP012", usda=174261),
    Spec("keju", "Keju", ["keju cheddar"], 15, tkpi="JP003", usda=173414),
    Spec("susu_kental_manis", "Susu kental manis", ["skm"], 20, tkpi="JP007", usda=171275),
    Spec("cabai_rawit", "Cabai rawit", ["cabe rawit", "cengek"], 5, tkpi="NR015", usda=170106),
]


def _num(text: str) -> float | None:
    """Angka TKPI memakai titik sebagai desimal dan koma sebagai pemisah ribuan ("1,114 mg" = 1114 mg)."""
    m = re.search(r"-?\d+(?:,\d{3})*(?:\.\d+)?", text)
    return float(m.group(0).replace(",", "")) if m else None


def fetch_tkpi(code: str) -> dict:
    """Baca halaman detail TKPI (POST view, field haha=kode). Nilai per 100 g bagian yang dapat dimakan."""
    req = urllib.request.Request(TKPI_URL, data=urllib.parse.urlencode({"haha": code}).encode(),
                                 headers={"User-Agent": "KIRA-seed/1.0"})
    html = urllib.request.urlopen(req, timeout=60).read().decode("utf-8", "ignore")
    text = re.sub(r"<script.*?</script>|<style.*?</style>", "", html, flags=re.S)
    text = re.sub(r"<[^>]+>", "|", text)
    text = re.sub(r"\s+|&nbsp;", " ", text)
    if code not in text:
        raise RuntimeError(f"TKPI {code}: halaman tidak memuat kode")

    def field_(label: str) -> float | None:
        m = re.search(label + r"[^:]*:\s*([^|]*)", text)
        return _num(m.group(1)) if m else None

    name = re.search(r"\|Nama[|\s]*:[|\s]*([^|]+)", text)
    return {"name": name.group(1).strip() if name else code, "kcal": field_(r"Energi \(\|Energy\|\)"),
            "fat_g": field_(r"Lemak \(\|Fat\|\)"), "carb_g": field_(r"Karbohidrat \(\|CHO\|\)"),
            "sodium_mg": field_(r"Natrium \(\|Na\|\)")}


def load_usda(ids: set[int]) -> dict[int, dict]:
    raw = urllib.request.urlopen(urllib.request.Request(USDA_ZIP, headers={"User-Agent": "KIRA-seed/1.0"}),
                                 timeout=300).read()
    zf = zipfile.ZipFile(io.BytesIO(raw))
    base = next(n for n in zf.namelist() if n.endswith("food.csv")).rsplit("/", 1)[0]
    want = {str(i) for i in ids}
    out: dict[int, dict] = {}
    with zf.open(f"{base}/food.csv") as f:
        for r in csv.DictReader(io.TextIOWrapper(f, "utf-8")):
            if r["fdc_id"] in want:
                out[int(r["fdc_id"])] = {"description": r["description"]}
    with zf.open(f"{base}/food_nutrient.csv") as f:
        for r in csv.DictReader(io.TextIOWrapper(f, "utf-8")):
            if r["fdc_id"] in want and r["nutrient_id"] in USDA_NUTRIENTS:
                out[int(r["fdc_id"])][USDA_NUTRIENTS[r["nutrient_id"]]] = float(r["amount"])
    missing = want - {str(i) for i in out}
    if missing:
        raise RuntimeError(f"fdcId tidak ada di SR Legacy: {sorted(missing)}")
    return out


def build(spec: Spec, tkpi: dict | None, usda: dict | None) -> list:
    values: dict[str, float] = {}
    origin: dict[str, str] = {}
    if tkpi:
        for k in ("kcal", "fat_g", "carb_g", "sodium_mg"):
            if tkpi.get(k) is not None:
                values[k], origin[k] = tkpi[k], f"TKPI {spec.tkpi}"
    if usda:
        for k in KEYS:
            if k not in values and usda.get(k) is not None:
                values[k], origin[k] = usda[k], f"USDA {spec.usda}"
    for k, v in spec.estimate.items():
        if k not in values:
            values[k], origin[k] = v, "estimasi KIRA"
    missing = [k for k in KEYS if k not in values]
    if missing:
        raise RuntimeError(f"{spec.id}: nilai {missing} tidak bersumber dan tidak diestimasi")
    source = f"TKPI:{spec.tkpi}" if spec.tkpi else f"USDA:{spec.usda}" if spec.usda else "ESTIMASI"
    groups: dict[str, list[str]] = {}
    for k in KEYS:
        groups.setdefault(origin[k], []).append({"sugar_g": "gula", "sodium_mg": "natrium", "fat_g": "lemak",
                                                 "kcal": "energi", "carb_g": "karbohidrat"}[k])
    label = {o: (f"TKPI Kemenkes 2017 ({spec.tkpi}, {tkpi['name']})" if o.startswith("TKPI")
                 else f"USDA FoodData Central SR Legacy ({spec.usda}, {usda['description']})" if o.startswith("USDA")
                 else "Estimasi KIRA") for o in groups}
    note = "; ".join(f"{label[o]}: {', '.join(ks)}" for o, ks in groups.items()) + "; porsi: estimasi"
    if spec.why:
        note += f" ({spec.why})"
    return [spec.id, spec.name, spec.aliases, *(round(values[k], 2) for k in KEYS), spec.portion_g, source, note]


def main() -> None:
    usda = load_usda({s.usda for s in SPECS if s.usda})
    rows = []
    for spec in SPECS:
        tkpi = fetch_tkpi(spec.tkpi) if spec.tkpi else None
        rows.append(build(spec, tkpi, usda.get(spec.usda) if spec.usda else None))
        print(rows[-1][:9])
    OUT.write_text(json.dumps({
        "_note": ("Komponen sederhana untuk memecah hidangan. Nilai per 100 g. Dibuat oleh seed/fetch_components.py "
                  "dari TKPI Kemenkes 2017 (panganku.org) dan USDA FoodData Central SR Legacy (domain publik); "
                  "sumber tiap angka ada di source_note. Porsi khas selalu estimasi KIRA."),
        "_columns": ["id", "name", "aliases", *KEYS, "default_portion_g", "source", "source_note"],
        "rows": rows,
    }, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"{len(rows)} komponen ditulis ke {OUT}")


if __name__ == "__main__":
    main()
