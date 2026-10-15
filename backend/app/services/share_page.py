"""Halaman web ringkasan untuk dokter (dibuka lewat tautan berbatas waktu). HTML statis tanpa skrip dan tanpa sumber luar."""
from html import escape

_STYLE = """
:root{color-scheme:light}*{box-sizing:border-box}
body{margin:0;background:#f6f7f5;color:#1d2a26;font:16px/1.55 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
main{max-width:46rem;margin:0 auto;padding:1.25rem 1rem 3rem}
h1{font-size:1.4rem;margin:0 0 .25rem}h2{font-size:1.05rem;margin:1.6rem 0 .5rem}
p{margin:.35rem 0}.muted{color:#566660;font-size:.9rem}
.card{background:#fff;border:1px solid #dfe4e1;border-radius:12px;padding:.9rem 1rem;margin:.5rem 0}
.flag{border-left:5px solid #9aa7a2}.flag.perhatian{border-left-color:#b3402a}.flag.pantau{border-left-color:#b7791f}
.tag{display:inline-block;font-size:.78rem;font-weight:700;letter-spacing:.02em;padding:.05rem .5rem;border-radius:999px;background:#eef1ef;margin-right:.4rem}
.perhatian .tag{background:#f8e3de;color:#8a2f1d}.pantau .tag{background:#faeccf;color:#7a4d10}
table{width:100%;border-collapse:collapse;font-size:.95rem}th,td{text-align:left;padding:.4rem .3rem;border-bottom:1px solid #e6eae8}
th{color:#566660;font-weight:600}
a.btn{display:inline-block;margin-top:.6rem;padding:.65rem 1rem;background:#1f6f5c;color:#fff;border-radius:10px;text-decoration:none;font-weight:600}
footer{margin-top:2rem;font-size:.85rem;color:#566660}
@media print{body{background:#fff}a.btn{display:none}}
"""

_CATEGORY = {
    "low": "rendah", "slightly_elevated": "sedikit meningkat", "moderate": "sedang",
    "high": "tinggi", "very_high": "sangat tinggi",
}
_LEVEL = {"perhatian": "PERLU PERHATIAN", "pantau": "PANTAU", "info": "INFO"}


def _page(title: str, body: str) -> str:
    return (
        '<!doctype html><html lang="id"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1">'
        '<meta name="robots" content="noindex,nofollow,noarchive">'
        f"<title>{escape(title)}</title><style>{_STYLE}</style></head><body><main>{body}</main></body></html>"
    )


def invalid_page() -> str:
    return _page(
        "Tautan tidak berlaku",
        "<h1>Tautan tidak berlaku</h1>"
        "<p>Tautan ini sudah kedaluwarsa, dicabut oleh pemiliknya, atau tidak dikenal.</p>"
        "<p class='muted'>Minta pemilik data membuat tautan baru dari aplikasi KIRA.</p>",
    )


def summary_page(summary: dict, pdf_path: str, expires_label: str) -> str:
    p, habits, risk = summary["patient"], summary["habits"], summary["risk"]["diabetes"]
    sex = {"male": "laki-laki", "female": "perempuan"}.get(p.get("sex") or "")
    who = escape(p["name"]) + (f" · {p['age']} tahun" if p.get("age") else "") + (f" · {sex}" if sex else "")

    flags = [f for f in summary["triage"] if f["level"] != "info"] or summary["triage"]
    flag_html = "".join(
        f'<div class="card flag {escape(f["level"])}"><span class="tag">{_LEVEL.get(f["level"], "")}</span>'
        f"{escape(f['text'])}</div>"
        for f in flags
    )

    rows = "".join(
        f"<tr><td>{escape(r['label'])}</td><td>{escape(r['display'])}</td>"
        f"<td>{escape(r['measured_on'])}</td><td>{escape(r['source'])}</td></tr>"
        for r in summary["clinical_results"]
    )
    results = (
        f"<table><thead><tr><th>Pemeriksaan</th><th>Hasil</th><th>Tanggal</th><th>Sumber</th></tr></thead>"
        f"<tbody>{rows}</tbody></table>"
        if rows
        else "<p>Belum ada hasil pemeriksaan yang dicatat di KIRA.</p>"
    )

    if habits["days_logged"]:
        sleep = f", tidur rata-rata {habits['sleep_hours_avg']:g} jam" if habits["sleep_hours_avg"] else ""
        habit_html = (
            f"<p>{habits['days_logged']} hari tercatat: gula dari makan dan minum rata-rata "
            f"<b>{habits['sugar_g_per_day']:g} g/hari</b>, minuman manis {habits['sweet_drinks_per_day']:g}/hari, "
            f"aktif {habits['active_minutes_per_day']:g} menit/hari{sleep}.</p>"
        )
    else:
        habit_html = "<p>Belum ada catatan kebiasaan pada periode ini.</p>"

    low, high = _CATEGORY.get(risk["category_low"], ""), _CATEGORY.get(risk["category_high"], "")
    risk_text = f"kategori {low}" + (f" sampai {high}" if high != low else "")
    body = (
        f"<h1>Ringkasan KIRA untuk dokter</h1><p><b>{who}</b></p>"
        f"<p class='muted'>Periode {summary['period_days']} hari. Dibuat otomatis dari catatan pengguna sendiri; "
        "bukan diagnosis dan bukan pengganti pemeriksaan.</p>"
        f"<h2>Penanda untuk perhatian</h2>{flag_html}"
        f"<h2>Hasil pemeriksaan terakhir</h2>{results}"
        f"<h2>Kebiasaan</h2>{habit_html}"
        f"<h2>Skrining diabetes</h2><p>FINDRISC, perkiraan 10 tahun: {escape(risk_text)} "
        f"(skor {risk['score_low']}–{risk['score_high']}).</p>"
        f'<a class="btn" href="{escape(pdf_path)}">Unduh PDF dengan grafik tren</a>'
        f"<footer>Tautan ini berlaku sampai {escape(expires_label)} dan bisa dicabut pemiliknya kapan saja. "
        "Jangan teruskan ke pihak lain tanpa izin pemilik data.</footer>"
    )
    return _page("Ringkasan KIRA untuk dokter", body)
