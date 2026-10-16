"""PDF ringkasan untuk dokter: penanda triase, tabel hasil terakhir, grafik tren, dan kebiasaan harian.

Semua angka datang dari ringkasan dan tren yang sama dengan layar aplikasi (summary.py, trends.py). Grafik digambar
sebagai vektor dengan reportlab, tanpa LLM. Font bawaan (Helvetica) hanya mendukung Latin: teks dibersihkan dulu.
"""
import io
from datetime import date, datetime

from reportlab.graphics.shapes import Circle, Drawing, Line, PolyLine, Rect
from reportlab.graphics.shapes import String as _String
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import KeepTogether, Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

INK = colors.HexColor("#14201F")
MUTED = colors.HexColor("#4A5C5A")
LINE = colors.HexColor("#D5DEDD")
PRIMARY = colors.HexColor("#0B6E6A")
CORAL = colors.HexColor("#B8492A")
CORAL_SOFT = colors.HexColor("#FFE3D8")
TEAL_SOFT = colors.HexColor("#D6EDEA")
GREY_SOFT = colors.HexColor("#EEF2F2")

CHART_W, CHART_H = 250, 118
KIND_LABEL = {
    "blood_pressure": "Tekanan darah", "fasting_glucose": "Gula darah puasa", "random_glucose": "Gula darah sewaktu",
    "hba1c": "HbA1c", "waist": "Lingkar perut", "resting_heart_rate": "Detak jantung istirahat",
}
UNIT = {"blood_pressure": "mmHg", "fasting_glucose": "mg/dL", "random_glucose": "mg/dL", "hba1c": "%", "waist": "cm",
        "resting_heart_rate": "kali/menit"}
RANGE_ID = {
    "normal": "normal", "prediabetes": "rentang prediabetes", "diabetes_range": "rentang diabetes",
    "below_cutoff": "di bawah ambang", "hypertension": "rentang hipertensi", "prehypertension": "normal-tinggi",
    "below_range": "di bawah 60", "normal_range": "60-100 (normal)", "above_range": "di atas 100",
}
SOURCE_ID = {"ckg": "CKG", "lab": "laboratorium", "self": "ukur sendiri"}


def String(x: float, y: float, text: str, **kw) -> _String:  # noqa: N802
    kw.setdefault("fontName", "Helvetica")
    return _String(x, y, text, **kw)


def clean(value: object) -> str:
    """Helvetica bawaan hanya Latin-1: karakter lain diganti '?' agar pembuatan PDF tidak gagal."""
    text = str(value).replace("≥", ">=").replace("≤", "<=").replace("–", "-").replace("—", "-")
    return text.encode("latin-1", "replace").decode("latin-1")


def _esc(value: object) -> str:
    return clean(value).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def _fmt(v: float) -> str:
    return f"{v:g}"


# ---------- grafik ----------

def _axes(d: Drawing, x0: float, y0: float, w: float, h: float, lo: float, hi: float) -> None:
    for i in range(5):
        v = lo + (hi - lo) * i / 4
        y = y0 + h * i / 4
        d.add(Line(x0, y, x0 + w, y, strokeColor=LINE, strokeWidth=0.4))
        label = f"{v:.0f}" if hi - lo > 10 else f"{v:.1f}"
        d.add(String(x0 - 3, y - 2.5, label, fontSize=6.5, fillColor=MUTED, textAnchor="end"))


def _title(d: Drawing, text: str) -> None:
    d.add(String(0, CHART_H - 9, clean(text), fontSize=8.5, fontName="Helvetica-Bold", fillColor=INK))


def line_chart(title: str, series: list[dict], refs: list[tuple[str, float]], unit: str) -> Drawing:
    """series: [{label, color, dashed, points: [(date, value)]}]. Sumbu x = waktu sebenarnya."""
    d = Drawing(CHART_W, CHART_H)
    _title(d, f"{title} ({unit})")
    x0, y0, w, h = 30, 22, CHART_W - 36, CHART_H - 42
    pts = [p for s in series for p in s["points"]]
    vals = [v for _, v in pts] + [v for _, v in refs]
    lo, hi = min(vals), max(vals)
    pad = max((hi - lo) * 0.12, 1.0)
    lo, hi = lo - pad, hi + pad
    _axes(d, x0, y0, w, h, lo, hi)
    days = sorted({p[0] for p in pts})
    t0, t1 = days[0], days[-1]
    span = max((t1 - t0).days, 1)

    def X(day: date) -> float:
        return x0 + w / 2 if t0 == t1 else x0 + w * (day - t0).days / span

    def Y(v: float) -> float:
        return y0 + h * (v - lo) / (hi - lo)

    for label, v in refs:
        d.add(Line(x0, Y(v), x0 + w, Y(v), strokeColor=CORAL, strokeWidth=0.7, strokeDashArray=[2, 2]))
        d.add(String(x0 + w, Y(v) + 1.5, clean(f"{label} {_fmt(v)}"), fontSize=5.5, fillColor=CORAL, textAnchor="end"))
    for s in series:
        ordered = sorted(s["points"])
        if len(ordered) > 1:
            d.add(PolyLine([c for day, v in ordered for c in (X(day), Y(v))], strokeColor=s["color"], strokeWidth=1.3,
                           strokeDashArray=[3, 2] if s.get("dashed") else None))
        for day, v in ordered:
            d.add(Circle(X(day), Y(v), 2.2, fillColor=s["color"], strokeColor=colors.white, strokeWidth=0.5))
        last_day, last_v = ordered[-1]
        d.add(String(min(X(last_day) + 1, x0 + w - 8), Y(last_v) + 3.5, _fmt(last_v), fontSize=6.5, fillColor=s["color"],
                     fontName="Helvetica-Bold"))
    d.add(String(x0, 11, t0.strftime("%d/%m/%y"), fontSize=6.5, fillColor=MUTED))
    if t1 != t0:
        d.add(String(x0 + w, 11, t1.strftime("%d/%m/%y"), fontSize=6.5, fillColor=MUTED, textAnchor="end"))
    legend_x = x0
    for s in series:
        d.add(Rect(legend_x, 2, 6, 4, fillColor=s["color"], strokeColor=None))
        d.add(String(legend_x + 8, 1.5, clean(s["label"]), fontSize=6.5, fillColor=MUTED))
        legend_x += 14 + 4.2 * len(s["label"])
    return d


def bar_chart(title: str, days: list[dict], key: str, unit: str, ref: tuple[str, float] | None = None) -> Drawing:
    """Satu batang per hari. Hari tanpa catatan (atau tanpa nilai) tidak diberi batang: bukan nol."""
    d = Drawing(CHART_W, CHART_H)
    _title(d, f"{title} ({unit})")
    x0, y0, w, h = 30, 22, CHART_W - 36, CHART_H - 42
    values = [x[key] for x in days]
    present = [v for v in values if v is not None]
    hi = max([*present, ref[1] if ref else 0, 1.0]) * 1.12
    _axes(d, x0, y0, w, h, 0, hi)
    n = max(len(days), 1)
    slot = w / n
    for i, v in enumerate(values):
        x = x0 + i * slot
        if v is None:
            d.add(Line(x + slot / 2, y0, x + slot / 2, y0 + 2, strokeColor=LINE, strokeWidth=0.8))
            continue
        over = ref is not None and v > ref[1]
        d.add(Rect(x + slot * 0.12, y0, max(slot * 0.76, 0.6), h * v / hi, fillColor=CORAL if over else PRIMARY,
                   strokeColor=None))
    if ref:
        y = y0 + h * ref[1] / hi
        d.add(Line(x0, y, x0 + w, y, strokeColor=INK, strokeWidth=0.8, strokeDashArray=[3, 2]))
        d.add(String(x0 + w, y + 1.5, clean(f"{ref[0]} {_fmt(ref[1])}"), fontSize=5.5, fillColor=INK, textAnchor="end"))
    if days:
        d.add(String(x0, 11, date.fromisoformat(days[0]["date"]).strftime("%d/%m"), fontSize=6.5, fillColor=MUTED))
        d.add(String(x0 + w, 11, date.fromisoformat(days[-1]["date"]).strftime("%d/%m"), fontSize=6.5, fillColor=MUTED,
                     textAnchor="end"))
    note = "batang coral: melewati batas; garis pendek: tidak tercatat" if ref else "garis pendek: tidak tercatat"
    d.add(String(x0, 1.5, clean(note), fontSize=6, fillColor=MUTED))
    return d


# ---------- dokumen ----------

def _styles() -> dict[str, ParagraphStyle]:
    base = getSampleStyleSheet()["Normal"]
    return {
        "title": ParagraphStyle("t", parent=base, fontName="Helvetica-Bold", fontSize=17, leading=20, textColor=INK),
        "sub": ParagraphStyle("s", parent=base, fontSize=9, leading=12, textColor=MUTED),
        "h": ParagraphStyle("h", parent=base, fontName="Helvetica-Bold", fontSize=10.5, leading=13, textColor=PRIMARY,
                            spaceBefore=9, spaceAfter=3),
        "p": ParagraphStyle("p", parent=base, fontSize=8.8, leading=11.5, textColor=INK),
        "small": ParagraphStyle("sm", parent=base, fontSize=7.2, leading=9.2, textColor=MUTED),
    }


def _triage_table(flags: list[dict], st: dict) -> Table:
    label = {"perhatian": "PERLU PERHATIAN", "pantau": "PANTAU", "info": "INFO"}
    fill = {"perhatian": CORAL_SOFT, "pantau": TEAL_SOFT, "info": GREY_SOFT}
    rows = [[Paragraph(f"<b>{label[f['level']]}</b>", st["small"]), Paragraph(_esc(f["text"]), st["p"])] for f in flags]
    t = Table(rows, colWidths=[33 * mm, 144 * mm])
    t.setStyle(TableStyle(
        [("VALIGN", (0, 0), (-1, -1), "TOP"), ("BOX", (0, 0), (-1, -1), 0.4, LINE), ("LINEBELOW", (0, 0), (-1, -2), 0.3, LINE),
         ("TOPPADDING", (0, 0), (-1, -1), 3), ("BOTTOMPADDING", (0, 0), (-1, -1), 3)]
        + [("BACKGROUND", (0, i), (0, i), fill[f["level"]]) for i, f in enumerate(flags)]
    ))
    return t


def _latest_results_table(clinical: dict, st: dict) -> Table | None:
    header = ["Pemeriksaan", "Terakhir", "Tanggal", "Sumber", "Rentang", "Tren"]
    rows = [header]
    for kind in ("blood_pressure", "fasting_glucose", "random_glucose", "hba1c", "waist", "resting_heart_rate"):
        c = clinical[kind]
        p = c["latest"]
        if p is None:
            continue
        value = f"{p['sys']}/{p['dia']}" if kind == "blood_pressure" else _fmt(p["value"])
        rng = RANGE_ID.get(p.get("category") or p.get("range") or "", "-")
        trend = f"{c['trend']} ({c['count']}x)" if c["trend"] else f"{c['count']}x"
        rows.append([KIND_LABEL[kind], f"{value} {UNIT[kind]}", p["date"], SOURCE_ID.get(p["source"], p["source"]), rng, trend])
    if len(rows) == 1:
        return None
    t = Table([[Paragraph(_esc(c), st["p"]) for c in r] for r in rows], colWidths=[34 * mm, 28 * mm, 24 * mm, 28 * mm, 38 * mm, 25 * mm])
    t.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, 0), GREY_SOFT), ("LINEBELOW", (0, 0), (-1, -1), 0.3, LINE),
                           ("VALIGN", (0, 0), (-1, -1), "TOP"), ("TOPPADDING", (0, 0), (-1, -1), 2.5),
                           ("BOTTOMPADDING", (0, 0), (-1, -1), 2.5)]))
    return t


def _pair(left: Drawing | None, right: Drawing | None) -> Table:
    t = Table([[left or "", right or ""]], colWidths=[CHART_W + 4, CHART_W + 4])
    t.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"), ("LEFTPADDING", (0, 0), (-1, -1), 0)]))
    return t


def _parse(day: str) -> date:
    return date.fromisoformat(day)


def _clinical_charts(clinical: dict) -> list[Drawing]:
    charts: list[Drawing] = []
    bp = clinical["blood_pressure"]
    if bp["points"]:
        refs = {r["label"]: r["value"] for r in bp["references"]}
        charts.append(line_chart(
            "Tren tekanan darah",
            [{"label": "Sistolik", "color": CORAL, "points": [(_parse(p["date"]), p["sys"]) for p in bp["points"]]},
             {"label": "Diastolik", "color": PRIMARY, "dashed": True, "points": [(_parse(p["date"]), p["dia"]) for p in bp["points"]]}],
            [("Hipertensi sis.", refs["Hipertensi (sistolik)"]), ("Hipertensi dia.", refs["Hipertensi (diastolik)"])],
            "mmHg",
        ))
    for kind, title in (("fasting_glucose", "Tren gula darah puasa"), ("random_glucose", "Tren gula darah sewaktu"), ("hba1c", "Tren HbA1c")):
        c = clinical[kind]
        if c["points"]:
            refs = [(r["label"].replace("Rentang diabetes mulai", "Diabetes").replace("Prediabetes mulai", "Prediabetes"), r["value"]) for r in c["references"]]
            charts.append(line_chart(title, [{"label": KIND_LABEL[kind], "color": CORAL, "points": [(_parse(p["date"]), p["value"]) for p in c["points"]]}],
                                     refs, UNIT[kind]))
    return charts


def build_doctor_pdf(summary: dict, trends: dict) -> bytes:
    st = _styles()
    buf = io.BytesIO()
    doc = SimpleDocTemplate(buf, pagesize=A4, leftMargin=16 * mm, rightMargin=16 * mm, topMargin=14 * mm, bottomMargin=16 * mm,
                            title="Ringkasan KIRA untuk dokter", author="KIRA")
    p = summary["patient"]
    who = _esc(p["name"]) + (f", {p['age']} tahun" if p.get("age") else "") + (
        ", laki-laki" if p.get("sex") == "male" else ", perempuan" if p.get("sex") == "female" else "")
    habits = summary["habits"]
    generated = datetime.fromisoformat(summary["generated_at"]).strftime("%d/%m/%Y")
    story: list = [
        Paragraph("Ringkasan KIRA untuk dokter", st["title"]),
        Paragraph(f"{who} &nbsp;|&nbsp; periode {summary['period_days']} hari &nbsp;|&nbsp; dibuat {generated}", st["sub"]),
        Paragraph("Dibuat otomatis dari catatan pengguna sendiri; bukan diagnosis dan bukan pengganti pemeriksaan.", st["small"]),
    ]

    story += [Paragraph("Penanda untuk perhatian", st["h"])]
    flags = [f for f in trends["triage"]] or [{"level": "info", "text": "Tidak ada penanda dari data yang ada."}]
    story += [_triage_table(flags, st), Paragraph("Penanda adalah aturan terhadap ambang pedoman (KMK 303/2026 untuk tekanan darah; PERKENI 2021 untuk gula darah), bukan diagnosis.", st["small"])]

    story += [Paragraph("Hasil pemeriksaan terakhir", st["h"])]
    table = _latest_results_table(trends["clinical"], st)
    story += [table] if table else [Paragraph("Belum ada hasil pemeriksaan yang dicatat di KIRA.", st["p"])]

    charts = _clinical_charts(trends["clinical"])
    if charts:
        story += [Paragraph("Tren hasil pemeriksaan (180 hari terakhir)", st["h"])]
        for i in range(0, len(charts), 2):
            story.append(KeepTogether(_pair(charts[i], charts[i + 1] if i + 1 < len(charts) else None)))

    daily = trends["daily"]
    refs = trends["references"]
    story += [Paragraph(f"Kebiasaan harian ({summary['period_days']} hari terakhir)", st["h"])]
    if habits["days_logged"] == 0:
        story.append(Paragraph("Belum ada catatan kebiasaan pada periode ini.", st["p"]))
    else:
        story.append(Paragraph(
            f"{habits['days_logged']} hari tercatat dari {summary['period_days']}. Rata-rata gula dari makan dan minum "
            f"{_fmt(habits['sugar_g_per_day'])} g/hari, minuman manis {_fmt(habits['sweet_drinks_per_day'])}/hari, aktif "
            f"{_fmt(habits['active_minutes_per_day'])} menit/hari"
            + (f", tidur rata-rata {_fmt(habits['sleep_hours_avg'])} jam." if habits["sleep_hours_avg"] else "."), st["p"]))
        story.append(KeepTogether(_pair(
            bar_chart("Gula dari makan dan minum per hari", daily, "sugar_g", "g", ("Batas 50 g", refs["sugar_g"])),
            bar_chart("Jam tidur per malam", daily, "sleep_hours", "jam"))))
        story.append(KeepTogether(_pair(
            bar_chart("Menit aktif per hari", daily, "active_minutes", "menit", ("Target 30", refs["active_minutes"])), None)))

    if summary["top_foods"]:
        story += [Paragraph("Makanan yang paling sering dicatat", st["h"]),
                  Paragraph(_esc(", ".join(f"{f['name']} ({f['count']}x)" for f in summary["top_foods"])), st["p"])]

    records = summary.get("medical_records") or []
    if records:
        story += [Paragraph("Rekam medis yang dicatat pasien", st["h"])]
        rows = [["Tanggal", "Jenis", "Catatan"]]
        for r in records:
            values = "; ".join(f"{v['name']} {v['value']}{(' ' + v['unit']) if v.get('unit') else ''}" for v in r["values"])
            note = r["title"] + (f" ({values})" if values else "") + (f" - {r['provider']}" if r.get("provider") else "")
            rows.append([r["recorded_on"], r["kind_label"], note])
        table_r = Table([[Paragraph(_esc(c), st["p"]) for c in row] for row in rows], colWidths=[24 * mm, 36 * mm, 117 * mm])
        table_r.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, 0), GREY_SOFT), ("LINEBELOW", (0, 0), (-1, -1), 0.3, LINE),
                                     ("VALIGN", (0, 0), (-1, -1), "TOP"), ("TOPPADDING", (0, 0), (-1, -1), 2.5),
                                     ("BOTTOMPADDING", (0, 0), (-1, -1), 2.5)]))
        story += [table_r, Paragraph("Ditulis sendiri oleh pasien dan tidak diverifikasi KIRA.", st["small"])]

    d = summary["risk"]["diabetes"]
    cat = {"low": "rendah", "slightly_elevated": "sedikit meningkat", "moderate": "sedang", "high": "tinggi", "very_high": "sangat tinggi"}
    lo, hi = cat.get(d["category_low"], ""), cat.get(d["category_high"], "")
    story += [Paragraph("Skrining risiko", st["h"]),
              Paragraph(f"Diabetes (FINDRISC, perkiraan 10 tahun): kategori {lo}" + (f" sampai {hi}" if hi != lo else "")
                        + f", skor {d['score_low']}-{d['score_high']}. Ini skrining dari kebiasaan dan profil, bukan hasil pemeriksaan.", st["p"])]

    story += [Spacer(1, 6), Paragraph(
        "Sumber: ambang tekanan darah KMK HK.01.07/MENKES/303/2026; kriteria gula darah dan HbA1c PERKENI 2021; batas gula harian "
        "Permenkes 30/2013; skor FINDRISC (Lindstrom dan Tuomilehto, Diabetes Care 2003). Data kebiasaan adalah laporan pengguna "
        "sendiri dan bisa kurang akurat; nilai gula makanan sebagian adalah estimasi. KIRA tidak memberi saran obat atau dosis.", st["small"])]

    def footer(canvas, document) -> None:
        canvas.saveState()
        canvas.setFont("Helvetica", 7)
        canvas.setFillColor(MUTED)
        canvas.drawString(16 * mm, 9 * mm, "KIRA - ringkasan otomatis, bukan diagnosis")
        canvas.drawRightString(A4[0] - 16 * mm, 9 * mm, f"Halaman {document.page}")
        canvas.restoreState()

    doc.build(story, onFirstPage=footer, onLaterPages=footer)
    return buf.getvalue()
