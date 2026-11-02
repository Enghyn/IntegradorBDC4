# -*- coding: utf-8 -*-
"""Genera el informe del TP 6 en PDF a partir de los resultados medidos."""

import textwrap
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_JUSTIFY, TA_LEFT, TA_RIGHT
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import cm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (BaseDocTemplate, Frame, HRFlowable, KeepTogether,
                                NextPageTemplate, PageBreak, PageTemplate, Paragraph,
                                Preformatted, Spacer, Table, TableStyle)

BASE = Path(__file__).resolve().parent.parent
RES = BASE / "resultados"
OUT = BASE / "Informe_TP6_FNBC_Desnormalizacion.pdf"

# ---------------------------------------------------------------------------
# Tipografías
# ---------------------------------------------------------------------------
pdfmetrics.registerFont(TTFont("Arial", r"C:\Windows\Fonts\arial.ttf"))
pdfmetrics.registerFont(TTFont("Arial-Bold", r"C:\Windows\Fonts\arialbd.ttf"))
pdfmetrics.registerFont(TTFont("Arial-Italic", r"C:\Windows\Fonts\ariali.ttf"))
pdfmetrics.registerFont(TTFont("Arial-BoldItalic", r"C:\Windows\Fonts\arialbi.ttf"))
pdfmetrics.registerFont(TTFont("Consolas", r"C:\Windows\Fonts\consola.ttf"))
pdfmetrics.registerFont(TTFont("Consolas-Bold", r"C:\Windows\Fonts\consolab.ttf"))
pdfmetrics.registerFontFamily("Arial", normal="Arial", bold="Arial-Bold",
                              italic="Arial-Italic", boldItalic="Arial-BoldItalic")

AZUL = colors.HexColor("#10314f")
AZUL_CLARO = colors.HexColor("#2b6a9b")
GRIS = colors.HexColor("#5b6770")
LINEA = colors.HexColor("#c8d2db")
FONDO_COD = colors.HexColor("#f5f7f9")
FONDO_NOTA = colors.HexColor("#eef4f9")

# ---------------------------------------------------------------------------
# Estilos
# ---------------------------------------------------------------------------
S = {
    "tapa_chico": ParagraphStyle("tapa_chico", fontName="Arial-Bold", fontSize=10,
                                 leading=14, alignment=TA_CENTER, textColor=GRIS,
                                 spaceAfter=2),
    "tapa_titulo": ParagraphStyle("tapa_titulo", fontName="Arial-Bold", fontSize=22,
                                  leading=27, alignment=TA_CENTER, textColor=AZUL,
                                  spaceBefore=18, spaceAfter=10),
    "tapa_sub": ParagraphStyle("tapa_sub", fontName="Arial", fontSize=12.5,
                               leading=17, alignment=TA_CENTER, textColor=AZUL_CLARO,
                               spaceAfter=6),
    "h1": ParagraphStyle("h1", fontName="Arial-Bold", fontSize=15.5, leading=19,
                         textColor=AZUL, spaceBefore=6, spaceAfter=2,
                         keepWithNext=1),
    "h2": ParagraphStyle("h2", fontName="Arial-Bold", fontSize=11.5, leading=15,
                         textColor=AZUL_CLARO, spaceBefore=11, spaceAfter=4,
                         keepWithNext=1),
    "h1_chico": ParagraphStyle("h1_chico", fontName="Arial-Bold", fontSize=13,
                               leading=16, textColor=AZUL, spaceAfter=0),
    "h2_chico": ParagraphStyle("h2_chico", fontName="Arial-Bold", fontSize=10,
                               leading=13, textColor=AZUL_CLARO, spaceBefore=7,
                               spaceAfter=3, keepWithNext=1),
    "h3": ParagraphStyle("h3", fontName="Arial-Bold", fontSize=9.8, leading=13,
                         textColor=AZUL, spaceBefore=7, spaceAfter=3,
                         keepWithNext=1),
    "body": ParagraphStyle("body", fontName="Arial", fontSize=9.5, leading=13.4,
                           alignment=TA_JUSTIFY, spaceAfter=5.5),
    "body_ss": ParagraphStyle("body_ss", fontName="Arial", fontSize=9.5, leading=13.4,
                              alignment=TA_JUSTIFY, spaceAfter=1.5),
    "bullet": ParagraphStyle("bullet", fontName="Arial", fontSize=9.5, leading=13.4,
                             alignment=TA_JUSTIFY, leftIndent=14, bulletIndent=4,
                             spaceAfter=3),
    "nota": ParagraphStyle("nota", fontName="Arial", fontSize=8.8, leading=12.4,
                           alignment=TA_JUSTIFY, textColor=colors.HexColor("#243b4d")),
    "cell": ParagraphStyle("cell", fontName="Arial", fontSize=8.3, leading=10.6),
    "cell_b": ParagraphStyle("cell_b", fontName="Arial-Bold", fontSize=8.3,
                             leading=10.6),
    "th": ParagraphStyle("th", fontName="Arial-Bold", fontSize=8.4, leading=10.6,
                         textColor=colors.white),
    "codigo": ParagraphStyle("codigo", fontName="Consolas", fontSize=6.9, leading=8.4),
    "codigo_plan": ParagraphStyle("codigo_plan", fontName="Consolas", fontSize=6.4, leading=7.0),
    "pie": ParagraphStyle("pie", fontName="Arial", fontSize=7.6, leading=10,
                          textColor=GRIS, alignment=TA_CENTER),
    "ref": ParagraphStyle("ref", fontName="Arial-Italic", fontSize=8.2, leading=11,
                          textColor=GRIS, spaceAfter=4),
}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def p(texto, estilo="body"):
    return Paragraph(texto, S[estilo])


def h1(texto):
    return [Spacer(1, 6), Paragraph(texto, S["h1"]),
            HRFlowable(width="100%", thickness=1.1, color=AZUL_CLARO,
                       spaceBefore=1, spaceAfter=8)]


def h2(texto):
    return Paragraph(texto, S["h2"])


def bullets(items):
    return [Paragraph(t, S["bullet"], bulletText="•") for t in items]


def code_box(texto, maxchars=116, chunk=34, estilo="codigo", indent=6,
             ancho=17.0 * cm):
    """Devuelve una lista de tablas de una celda (permite cortar entre páginas)."""
    lineas = []
    for linea in texto.replace("\t", "    ").splitlines():
        linea = linea.rstrip()
        if not linea:
            lineas.append("")
            continue
        if len(linea) <= maxchars:
            lineas.append(linea)
        else:
            lineas.extend(textwrap.wrap(linea, maxchars, subsequent_indent=" " * indent,
                                        drop_whitespace=False,
                                        replace_whitespace=False) or [""])

    salida = []
    for i in range(0, len(lineas), chunk):
        bloque = "\n".join(lineas[i:i + chunk])
        t = Table([[Preformatted(bloque, S[estilo])]], colWidths=[ancho])
        t.setStyle(TableStyle([
            ("BACKGROUND", (0, 0), (-1, -1), FONDO_COD),
            ("BOX", (0, 0), (-1, -1), 0.5, LINEA),
            ("LEFTPADDING", (0, 0), (-1, -1), 6),
            ("RIGHTPADDING", (0, 0), (-1, -1), 6),
            ("TOPPADDING", (0, 0), (-1, -1), 4),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ]))
        salida.append(t)
        salida.append(Spacer(1, 5))
    return salida


def tabla(cabeceras, filas, anchos, estilo_celdas="cell"):
    data = [[Paragraph(c, S["th"]) for c in cabeceras]]
    for fila in filas:
        data.append([c if isinstance(c, Paragraph) else Paragraph(c, S[estilo_celdas])
                     for c in fila])
    t = Table(data, colWidths=anchos, repeatRows=1, hAlign="LEFT")
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), AZUL),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("GRID", (0, 0), (-1, -1), 0.4, LINEA),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#f8fafc")]),
        ("TOPPADDING", (0, 0), (-1, -1), 4),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ("LEFTPADDING", (0, 0), (-1, -1), 5),
        ("RIGHTPADDING", (0, 0), (-1, -1), 5),
    ]))
    return t


def nota_box(titulo, texto):
    fila = [[Paragraph("<b>%s</b><br/>%s" % (titulo, texto), S["nota"])]]
    t = Table(fila, colWidths=[17.0 * cm])
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), FONDO_NOTA),
        ("BOX", (0, 0), (-1, -1), 0.6, colors.HexColor("#9db8cc")),
        ("LEFTPADDING", (0, 0), (-1, -1), 8),
        ("RIGHTPADDING", (0, 0), (-1, -1), 8),
        ("TOPPADDING", (0, 0), (-1, -1), 6),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
    ]))
    return t


def plan_file(nombre, quitar_pie_filas=True):
    texto = (RES / nombre).read_text(encoding="utf-8-sig")
    lineas = texto.splitlines()
    # Se descarta el encabezado de columna de psql
    if lineas and "QUERY PLAN" in lineas[0]:
        lineas = lineas[1:]
    if lineas and lineas[0].strip() and set(lineas[0].strip()) <= set("-"):
        lineas = lineas[1:]
    while lineas and not lineas[-1].strip():
        lineas.pop()
    # Se descarta el pie "(N filas)" que agrega psql en los planes
    if (quitar_pie_filas and lineas and lineas[-1].strip().startswith("(")
            and "filas" in lineas[-1]):
        lineas.pop()
    return "\n".join(lineas)


def footer(canvas, doc):
    ancho, alto = canvas._pagesize
    canvas.saveState()
    canvas.setStrokeColor(LINEA)
    canvas.setLineWidth(0.5)
    canvas.line(1.8 * cm, 1.5 * cm, ancho - 1.8 * cm, 1.5 * cm)
    canvas.setFont("Arial", 7.4)
    canvas.setFillColor(GRIS)
    canvas.drawString(1.8 * cm, 1.05 * cm,
                      "Base de Datos II · Unidad 4 · FNBC y desnormalización controlada")
    canvas.drawRightString(ancho - 1.8 * cm, 1.05 * cm, "Página %d" % doc.page)
    canvas.restoreState()


# ---------------------------------------------------------------------------
# Documento
# ---------------------------------------------------------------------------
doc = BaseDocTemplate(str(OUT), pagesize=A4,
                      leftMargin=2.0 * cm, rightMargin=2.0 * cm,
                      topMargin=1.8 * cm, bottomMargin=2.0 * cm,
                      title="TP Unidad 4 - FNBC y desnormalización controlada en Food Store",
                      author="Base de Datos II",
                      subject="Forma Normal de Boyce-Codd y desnormalización controlada")
frame = Frame(doc.leftMargin, doc.bottomMargin, doc.width, doc.height, id="normal")
HOJA, ALTO = landscape(A4)
frame_h = Frame(1.8 * cm, 1.8 * cm, HOJA - 3.6 * cm, ALTO - 3.6 * cm, id="ancha")
doc.addPageTemplates([
    PageTemplate(id="todas", frames=[frame], onPage=footer),
    PageTemplate(id="anexos", frames=[frame_h], onPage=footer, pagesize=landscape(A4)),
])

story = []

# ============================ TAPA =========================================
story.append(Spacer(1, 2.2 * cm))
story.append(p("TECNICATURA UNIVERSITARIA EN PROGRAMACIÓN", "tapa_chico"))
story.append(p("BASE DE DATOS II", "tapa_chico"))
story.append(Spacer(1, 0.8 * cm))
story.append(HRFlowable(width="45%", thickness=1.2, color=AZUL_CLARO, hAlign="CENTER"))
story.append(p("Forma Normal de Boyce-Codd<br/>y desnormalización controlada<br/>en Food Store", "tapa_titulo"))
story.append(p("Trabajo Práctico · Unidad 4<br/>Normalización avanzada y redundancia", "tapa_sub"))
story.append(Spacer(1, 1.2 * cm))

ALUMNOS = [
    ("Fernando Torrez", "53.988"),
    ("Ignacio Sánchez", "53.966"),
    ("Agustín Contardi", "53.863"),
    ("Enzo Giaquinta", "53.884"),
    ("Ramiro Salcedo", "53.992"),
]
integrantes = Table(
    [[Paragraph(nombre, S["cell"]), Paragraph(legajo, S["cell"])] for nombre, legajo in ALUMNOS],
    colWidths=[3.9 * cm, 2.4 * cm], hAlign="LEFT")
integrantes.setStyle(TableStyle([
    ("VALIGN", (0, 0), (-1, -1), "TOP"),
    ("LEFTPADDING", (0, 0), (-1, -1), 0),
    ("RIGHTPADDING", (0, 0), (-1, -1), 2),
    ("TOPPADDING", (0, 0), (-1, -1), 0),
    ("BOTTOMPADDING", (0, 0), (-1, -1), 1),
]))

datos = [
    ["Materia", "Base de Datos II"],
    ["Unidad", "Unidad 4 — Forma Normal de Boyce-Codd y Desnormalización Controlada"],
    ["Trabajo", "Parte 1: FNBC sobre ControlLoteAlmacen<br/>Parte 2: reporte top 5 de categorías por monto vendido"],
    ["Integrantes", integrantes],
    ["Fecha de entrega", "28 de octubre de 2026"],
    ["Motor utilizado", "PostgreSQL 17.11 (Windows x64)"],
    ["Entregables", "tp_fnbc_control_lote.sql · tp_desnormalizacion_top_categorias.sql · este informe"],
]
t = Table([[a if not isinstance(a, str) else Paragraph(a, S["cell_b"]),
            b if not isinstance(b, str) else Paragraph(b, S["cell"])] for a, b in datos],
          colWidths=[4.3 * cm, 12.7 * cm], hAlign="CENTER")
t.setStyle(TableStyle([
    ("VALIGN", (0, 0), (-1, -1), "TOP"),
    ("LINEBELOW", (0, 0), (-1, -2), 0.3, LINEA),
    ("TOPPADDING", (0, 0), (-1, -1), 5),
    ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
    ("LEFTPADDING", (0, 0), (-1, -1), 2),
]))
story.append(t)
story.append(Spacer(1, 1.4 * cm))
story.append(nota_box("Alcance",
    "Todas las afirmaciones técnicas de este informe están respaldadas por un artefacto: el script SQL que "
    "las implementa o la salida de <b>EXPLAIN (ANALYZE, BUFFERS)</b> que las mide. Las capturas completas "
    "de los planes de ejecución se incluyen en el Anexo B y, además, como archivos de texto en la carpeta "
    "<i>resultados/</i> de la entrega."))

story.append(PageBreak())

# ============================ RESUMEN ======================================
story += h1("Resumen ejecutivo")
story.append(p(
    "El trabajo aborda dos decisiones de diseño sobre la base Food Store y, en ambos casos, la decisión se "
    "toma con evidencia y no por intuición: en la Parte 1 se analizan las dependencias funcionales de la "
    "relación <i>control_lote_almacen</i> y se determina, con la definición formal, que el esquema está en "
    "Tercera Forma Normal (3FN) pero <b>no</b> en Forma Normal de Boyce-Codd (FNBC). La dependencia "
    "violatoria es <b>ResponsableControlID → DepositoID</b>, cuyo determinante no es superclave. La relación "
    "se descompone sin pérdida en <i>responsable_deposito</i> y <i>control_lote_responsable</i>; una vista de "
    "compatibilidad reconstruye la relación original por reunión natural y la verificación de equivalencia "
    "devuelve <b>0 diferencias</b> sobre la instancia."))
story.append(p(
    "En la Parte 2 se mide la consulta del panel (top 5 de categorías por monto vendido en el día) sobre una "
    "réplica poblada con 250.000 pedidos y 1.250.000 líneas de detalle. La consulta original tarda una "
    "<b>mediana de 148,46 ms</b> y el nodo que domina el costo es un <b>recorrido secuencial paralelo sobre "
    "detalle_pedido</b> (1,25 millones de filas). Aun agregando el índice sobre la clave foránea que PostgreSQL "
    "no crea por defecto, el tiempo baja sólo a 4,54 ms y el costo sigue creciendo con el volumen del día. "
    "Con una tabla de agregación incremental por fecha y categoría, mantenida por disparadores, la misma "
    "consulta responde en <b>0,075 ms</b> leyendo 12 filas: <b>1.979 veces más rápido</b> que el esquema original y "
    "60 veces más rápido que el esquema indexado."))
story.append(p(
    "El dato redundante no queda librado a la disciplina de la aplicación: cuatro disparadores y una función "
    "de apoyo lo actualizan dentro de la misma transacción, y una vista de auditoría recalcula el agregado "
    "desde la fuente de verdad y compara. La auditoría ejecutada sobre la base migrada devuelve <b>0 filas</b>; "
    "además, se comprueba que no es vacua provocando una desincronización artificial, que la vista detecta de "
    "inmediato."))

story.append(Spacer(1, 6))
story.append(tabla(
    ["Entregable", "Contenido"],
    [["<b>tp_fnbc_control_lote.sql</b>",
      "Esquema original, instancia de ejemplo, demostración de anomalías, tablas descompuestas, vista de "
      "compatibilidad y migración verificada (Parte 1)."],
     ["<b>tp_desnormalizacion_<br/>top_categorias.sql</b>",
      "Esquema y población de la réplica, medición inicial, estructura desnormalizada con sus disparadores, "
      "consulta del panel, auditoría y pruebas del mecanismo (Parte 2)."],
     ["<b>Informe_TP6_FNBC_<br/>Desnormalizacion.pdf</b>",
      "Este documento: análisis, justificaciones, resultados y capturas."],
     ["<b>resultados/</b>",
      "Capturas de EXPLAIN (ANALYZE, BUFFERS) antes y después, salidas de los scripts, auditoría y scripts de "
      "benchmark reproducibles."]],
    [5.2 * cm, 11.8 * cm]))

story.append(PageBreak())

# ============================ PARTE 1 ======================================
story += h1("Parte 1 · Análisis y aplicación de la FNBC: ControlLoteAlmacen")

story.append(h2("1.1 · Contexto de dominio y esquema inicial"))
story.append(p(
    "Food Store extiende su operación hacia la distribución mayorista: incorpora depósitos propios y recibe de "
    "sus proveedores lotes de mercadería que deben pasar un control de calidad antes de ingresar al inventario. "
    "Cuando un lote es de gran volumen se fracciona y se controla simultáneamente desde más de un depósito. Por "
    "cada depósito que interviene en el control de un lote se designa un responsable de control a cargo de esa "
    "fracción. El relevamiento con el área de logística produjo dos reglas:"))
story += bullets([
    "<b>Regla 1.</b> Para un lote y un depósito interviniente dados, el responsable de control queda "
    "unívocamente determinado.",
    "<b>Regla 2.</b> Cada responsable de control pertenece, como dato maestro de la dotación de personal, a un "
    "único depósito: no controla lotes coordinados desde depósitos distintos.",
])
story.append(p(
    "El esquema inicial que traduce ese relevamiento, con la instancia de ejemplo del enunciado, es el siguiente:"))
story += code_box("""CREATE TABLE control_lote_almacen (
    lote_id                 BIGINT NOT NULL REFERENCES lote(id),
    deposito_id             BIGINT NOT NULL REFERENCES deposito(id),
    responsable_control_id  BIGINT NOT NULL REFERENCES usuario(id),
    PRIMARY KEY (lote_id, deposito_id)
);

INSERT INTO control_lote_almacen VALUES
    (501, 30, 801),
    (502, 30, 801),
    (503, 31, 802);""")

story.append(tabla(
    ["lote_id", "deposito_id", "responsable_control_id"],
    [["501", "30", "801"], ["502", "30", "801"], ["503", "31", "802"]],
    [3.6 * cm, 3.6 * cm, 5.0 * cm]))

story.append(h2("1.2 · (a) Dependencias funcionales en notación formal"))
story.append(p("Con los nombres de atributo indicados —LoteID (L), DepositoID (D) y ResponsableControlID (R)—, "
               "las dos reglas de negocio se traducen en:"))
story.append(tabla(
    ["DF", "Expresión formal", "Origen en la regla de negocio"],
    [["DF1", "(LoteID, DepositoID) → ResponsableControlID",
      "Regla 1: para un lote y un depósito interviniente, el responsable queda unívocamente determinado."],
     ["DF2", "ResponsableControlID → DepositoID",
      "Regla 2: cada responsable pertenece a un único depósito."]],
    [1.4 * cm, 7.0 * cm, 8.6 * cm]))
story.append(Spacer(1, 5))
story.append(p(
    "El conjunto de dependencias relevante es <b>F = { (LoteID, DepositoID) → ResponsableControlID ; "
    "ResponsableControlID → DepositoID }</b>. De DF2 se deduce, por aumento (augmentation), la dependencia "
    "(LoteID, ResponsableControlID) → DepositoID, que resultará clave para justificar la reunión sin pérdida. "
    "No existe ninguna dependencia que determine LoteID a partir de DepositoID ni de ResponsableControlID: un "
    "depósito interviene en muchos lotes y un responsable controla muchos lotes."))

story.append(h2("1.3 · (b) Clausuras y conjunto completo de claves candidatas"))
story.append(p(
    "Para determinar las claves se calculan las clausuras de todos los subconjuntos que resultan candidatos "
    "razonables. Un subconjunto X es superclave si X+ contiene los tres atributos; es clave candidata si además "
    "es minimal (ningún subconjunto propio suyo es superclave)."))
story.append(tabla(
    ["Subconjunto X", "Clausura X+", "¿Superclave?", "¿Minimal?"],
    [["{L}", "{L}", "No", "—"],
     ["{D}", "{D}", "No", "—"],
     ["{R}", "{R, D}", "No", "—"],
     ["{L, D}", "{L, D, R}", "<b>Sí</b>", "<b>Sí → clave candidata</b>"],
     ["{L, R}", "{L, R, D}", "<b>Sí</b>", "<b>Sí → clave candidata</b>"],
     ["{D, R}", "{D, R}", "No", "—"],
     ["{L, D, R}", "{L, D, R}", "Sí", "No (contiene a {L, D})"]],
    [3.4 * cm, 3.4 * cm, 3.0 * cm, 7.2 * cm]))
story.append(Spacer(1, 5))
story.append(p(
    "El conjunto completo de claves candidatas es <b>{LoteID, DepositoID}</b> y <b>{LoteID, "
    "ResponsableControlID}</b>. La primera es la clave primaria declarada en el esquema; la segunda no está "
    "declarada y, sin embargo, también determina toda la tupla."))
story.append(p(
    "En consecuencia, <b>todos los atributos son primos</b>: LoteID, DepositoID y ResponsableControlID "
    "pertenecen al menos a una clave candidata. <b>No hay atributos no primos</b>. Este detalle es el que "
    "explica por qué la relación cumple 3FN y, aun así, no cumple FNBC."))

story.append(h2("1.4 · (c) Verificación formal de FNBC"))
story.append(p(
    "La definición de FNBC es: una relación R está en FNBC si y sólo si, para toda dependencia funcional no "
    "trivial X → Y en F+, X es una superclave de R. Se analiza cada dependencia de F:"))
story += bullets([
    "<b>DF1: (LoteID, DepositoID) → ResponsableControlID.</b> El determinante es {L, D}, que es clave "
    "candidata y, por lo tanto, superclave. No viola FNBC.",
    "<b>DF2: ResponsableControlID → DepositoID.</b> Es no trivial (el lado derecho no está contenido en el "
    "izquierdo) y su determinante es {R}, cuya clausura es {R, D}: no contiene LoteID, de modo que <b>no es "
    "superclave</b>. Esta dependencia <b>viola FNBC</b>.",
])
story.append(p(
    "La dependencia violatoria es, entonces, <b>ResponsableControlID → DepositoID</b>. El determinante "
    "ResponsableControlID no alcanza para determinar toda la tupla: identifica unívocamente un depósito, pero "
    "no el conjunto de lotes que ese responsable controla."))
story.append(nota_box("Por qué el caso es interesante: 3FN no es FNBC",
    "La relación <b>sí cumple 3FN</b>. En la dependencia ResponsableControlID → DepositoID el atributo "
    "determinado (DepositoID) es primo, y la definición de 3FN admite un determinante que no es superclave "
    "cuando el lado derecho es un atributo primo. La FNBC elimina esa excepción: exige que <i>todo</i> "
    "determinante sea superclave, sin importar si el atributo determinado es primo o no. Este esquema es, "
    "por eso, un contraejemplo mínimo de la diferencia entre ambas formas normales."))
story.append(Spacer(1, 5))
story.append(p(
    "La violación no es sólo teórica: el esquema la acepta. La clave primaria (LoteID, DepositoID) impide "
    "repetir el par lote–depósito, pero no impide que un mismo responsable quede asociado a dos depósitos. El "
    "script de la Parte 1 lo demuestra insertando la fila (504, 32, 801) cuando 801 ya pertenecía al depósito "
    "30: el motor acepta la fila y deja a 801 en dos depósitos, contradiciendo la Regla 2."))

story.append(h2("1.5 · (d) Anomalías que habilita la violación"))
story.append(p(
    "Las tres anomalías clásicas se manifiestan sobre la propia instancia de ejemplo. Cada escenario se "
    "ejecuta en el script dentro de una transacción que se revierte, para no alterar los datos."))
story.append(p(
    "<b>Anomalía de inserción.</b> El esquema no tiene dónde guardar un dato maestro del responsable: sólo "
    "existe la relación de control. Para registrar que el responsable 803 pertenece al depósito 32 hay que "
    "inventar, además, un control sobre un lote que 803 todavía no controló. En la demostración se dio de alta "
    "el lote 504 y se insertó la fila (504, 32, 803): el dato maestro quedó “colgado” de un hecho transitorio "
    "que puede no haber ocurrido. Si el lote 504 no existiera, el alta del responsable sería imposible."))
story.append(p(
    "<b>Anomalía de actualización.</b> El responsable 801 aparece en dos filas —(501, 30, 801) y "
    "(502, 30, 801)— porque controla dos lotes del mismo depósito. Si 801 pasa a pertenecer al depósito 31, la "
    "actualización correcta exige modificar <i>todas</i> las filas donde aparece. El script actualiza una sola "
    "y el resultado es que 801 queda en los depósitos 30 y 31 simultáneamente: la Regla 2 queda violada y el "
    "motor no lo impide, porque el esquema no tiene forma de expresarla."))
story.append(p(
    "<b>Anomalía de borrado.</b> La fila (503, 31, 802) es el único registro que afirma que el responsable 802 "
    "pertenece al depósito 31. Si se da de baja el control de ese lote —un hecho operativo que termina— se "
    "borra también el dato maestro de la dotación: después del DELETE no queda ninguna fila que permita saber a "
    "qué depósito pertenece 802. Se pierde información que no debía depender de ese control."))

story.append(h2("1.6 · (e) Descomposición sin pérdida y DDL resultante"))
story.append(p(
    "Se aplica el algoritmo de descomposición visto en clase: ante una dependencia X → Y que viola FNBC, se "
    "calcula la clausura X+ y se reemplaza R por dos relaciones, R1 = X+ y R2 = U − (X+ − X). Con X = "
    "ResponsableControlID:"))
story += code_box("""X  = ResponsableControlID              (determinante de la DF violatoria)
X+ = {ResponsableControlID, DepositoID}

R1 = X+                        = {ResponsableControlID, DepositoID}
R2 = U - (X+ - X)              = {LoteID, DepositoID, ResponsableControlID} - {DepositoID}
                               = {LoteID, ResponsableControlID}""")
story.append(p("El script completo de las tablas resultantes, con claves primarias y claves foráneas, es:"))
story += code_box("""CREATE TABLE responsable_deposito (
    responsable_control_id BIGINT PRIMARY KEY
        REFERENCES usuario(id),
    deposito_id            BIGINT NOT NULL
        REFERENCES deposito(id)
);

CREATE TABLE control_lote_responsable (
    lote_id                BIGINT NOT NULL
        REFERENCES lote(id),
    responsable_control_id BIGINT NOT NULL
        REFERENCES responsable_deposito(responsable_control_id),
    PRIMARY KEY (lote_id, responsable_control_id)
);

-- Vista de compatibilidad: reconstruye la relación original por reunión natural
CREATE VIEW control_lote_almacen_v AS
SELECT clr.lote_id,
       rd.deposito_id,
       rd.responsable_control_id
FROM control_lote_responsable clr
NATURAL JOIN responsable_deposito rd;""")
story.append(p(
    "Ambas relaciones resultantes están en FNBC. En <i>responsable_deposito</i> el único determinante no "
    "trivial es ResponsableControlID, que es su clave primaria. En <i>control_lote_responsable</i> no hay "
    "dependencias no triviales: un lote puede tener varios responsables y un responsable puede controlar "
    "varios lotes, de modo que ninguno de los dos atributos determina al otro; su única clave, (LoteID, "
    "ResponsableControlID), no compite con ningún determinante."))

story.append(h2("1.7 · (f) Por qué la reunión es sin pérdida"))
story.append(p(
    "El teorema de descomposición sin pérdida establece que una descomposición de R en R1 y R2 es sin pérdida "
    "si el atributo común de ambas relaciones es superclave de al menos una de ellas. En este caso:"))
story += code_box("""R1 = responsable_deposito       = {ResponsableControlID, DepositoID}
R2 = control_lote_responsable    = {LoteID, ResponsableControlID}

R1 ∩ R2 = {ResponsableControlID}

Como ResponsableControlID -> DepositoID pertenece a F+,
ResponsableControlID es superclave de R1 (de hecho, es su clave primaria).
=> La reunión natural de R1 y R2 es sin pérdida.""")
story.append(p(
    "La verificación empírica confirma la demostración: la vista de compatibilidad reconstruye las tres filas "
    "de la instancia original y la diferencia simétrica entre ambas relaciones es vacía (0 filas)."))
story.append(nota_box("Una observación de rigor: preservación de dependencias",
    "Las proyecciones de F sobre las dos tablas son F1 = {ResponsableControlID → DepositoID} y F2 = {}. Su "
    "unión no implica (LoteID, DepositoID) → ResponsableControlID, es decir, la descomposición <b>no preserva</b> "
    "esa dependencia. Es un resultado conocido: no toda relación admite una descomposición en FNBC que sea a la "
    "vez sin pérdida y preservadora de dependencias. Como el objetivo de la Parte 1 es la FNBC, se acepta esa "
    "pérdida y se recupera la regla de negocio con un trigger de restricción diferido sobre "
    "<i>control_lote_responsable</i>, incluido en el script (sección 5.7): impide que un mismo lote tenga dos "
    "responsables en el mismo depósito."))

story.append(h2("1.8 · (f) Migración de datos y verificación de equivalencia"))
story.append(p(
    "La migración proyecta la instancia original sobre cada tabla resultante. En R1 se usa DISTINCT porque la "
    "proyección elimina, precisamente, la redundancia que el esquema original almacenaba: 801 aparecía dos "
    "veces asociado al depósito 30."))
story += code_box("""INSERT INTO responsable_deposito (responsable_control_id, deposito_id)
SELECT DISTINCT responsable_control_id, deposito_id
FROM control_lote_almacen;

INSERT INTO control_lote_responsable (lote_id, responsable_control_id)
SELECT lote_id, responsable_control_id
FROM control_lote_almacen;""")
story.append(p("Resultado de la verificación ejecutada por el script:"))
story += code_box("""          verificacion           |     resultado     | diferencias
---------------------------------+-------------------+-------------
 equivalencia vista vs. original | OK: 0 diferencias |           0

            objeto            | filas
------------------------------+-------
 control_lote_almacen_orig    |     3
 responsable_deposito         |     2
 control_lote_responsable     |     3
 vista control_lote_almacen_v |     3""")
story.append(p(
    "La vista reconstruye exactamente el ejemplo del enunciado: (501, 30, 801), (502, 30, 801) y "
    "(503, 31, 802). La relación original se conserva como <i>control_lote_almacen_orig</i> sólo como "
    "evidencia de la verificación; el estado final del esquema son las dos tablas en FNBC más la vista de "
    "compatibilidad."))

story.append(PageBreak())

# ============================ PARTE 2 ======================================
story += h1("Parte 2 · Consulta con desnormalización controlada")

story.append(h2("2.1 · (a) Medición inicial con EXPLAIN ANALYZE"))
story.append(nota_box("Sobre la instancia utilizada",
    "La Parte 2 se resuelve sobre una réplica de Food Store construida para este trabajo, con las mismas cuatro "
    "tablas del proyecto (<i>categoria</i>, <i>producto</i>, <i>pedido</i> y <i>detalle_pedido</i>). El script "
    "incluye el DDL y la población para que la medición sea reproducible; la sección 1 puede omitirse si se "
    "ejecuta sobre una copia real. La población es determinista (semilla fija y hashes) y tiene 250.000 "
    "pedidos distribuidos en 730 días, 800 productos y 1.250.000 líneas de detalle. El día de la medición "
    "registró 323 pedidos y 1.615 líneas."))
story.append(Spacer(1, 5))

story.append(tabla(
    ["Magnitud", "Valor"],
    [["Pedidos", "250.000 (730 días; ~342 por día)"],
     ["Líneas de detalle", "1.250.000 (5 por pedido)"],
     ["Productos / categorías", "800 / 12"],
     ["Pedidos y líneas del día medido", "323 / 1.615"],
     ["Tamaño de detalle_pedido", "132 MB"],
     ["Tamaño del resumen desnormalizado", "1.072 kB (8.760 filas = 730 días × 12 categorías)"],
     ["Configuración", "shared_buffers 128 MB · work_mem 4 MB · 2 workers paralelos"]],
    [6.6 * cm, 10.4 * cm]))
story.append(Spacer(1, 8))

story.append(p("La consulta del panel, tal como figura en el enunciado, produjo el siguiente plan (extracto; el plan completo está en el Anexo B.1):"))
story += code_box(""" Limit  (cost=20155.98..20155.99 rows=5 width=41) (actual time=120.162..129.587 rows=5 loops=1)
   Buffers: shared hit=12641
   ->  Sort  (cost=20155.98..20156.01 rows=12 width=41) (actual time=120.159..129.583 rows=5 loops=1)
         Sort Key: (sum(dp.subtotal)) DESC
         ->  Finalize GroupAggregate  ...
               ->  Gather Merge  ...
                     Workers Launched: 2
                     ->  Partial GroupAggregate  ...
                           ->  Hash Join  (Hash Cond: (pr.categoria_id = c.id))
                                 ->  Hash Join  (Hash Cond: (dp.producto_id = pr.id))
                                       ->  Hash Join  (Hash Cond: (dp.pedido_id = ped.id))
                                             ->  Parallel Seq Scan on detalle_pedido dp
                                                   (actual time=0.013..60.776 rows=412494 loops=3)
                                                   Filter: (NOT eliminado)
                                                   Buffers: shared hit=11678
                                             ->  Hash  (rows=316)
                                                   ->  Bitmap Heap Scan on pedido ped
                                                         ->  Bitmap Index Scan on ix_pedido_fecha
 Planning Time: 1.936 ms
 Execution Time: 129.817 ms""")
story.append(p(
    "<b>Tiempo de ejecución:</b> 129,82 ms en la captura de referencia; <b>mediana de 148,46 ms</b> sobre cinco "
    "ejecuciones. <b>Nodo que domina el costo:</b> el <i>Parallel Seq Scan</i> sobre <i>detalle_pedido</i>, que "
    "recorre las 1.250.000 filas (≈412.494 por worker) y consume 11.678 de los 12.641 buffers del plan."))
story.append(p(
    "La causa es estructural: el filtro por fecha está en <i>pedido</i>, no en <i>detalle_pedido</i>. El índice "
    "sobre <i>pedido(fecha)</i> reduce el lado del pedido a 325 filas, pero el motor no tiene forma de saber "
    "qué líneas pertenecen al día sin recorrer todas las líneas y unirlas con <i>pedido</i>. El agregado en sí "
    "es barato (1.567 filas sobreviven a los filtros y se agrupan en 12); lo caro es <i>encontrar</i> esas 1.567 "
    "filas dentro de 1,25 millones."))
story.append(p(
    "Para no atribuir a la desnormalización una mejora que en realidad produce un índice, se midió también el "
    "esquema con el índice sobre la clave foránea <i>detalle_pedido(pedido_id)</i>, que PostgreSQL no crea "
    "automáticamente. El plan cambia a un <i>Nested Loop</i> con 316 recorridos de índice y el tiempo baja a "
    "<b>4,54 ms</b> (mediana). Es una mejora de 32,7 veces, pero el costo sigue siendo proporcional a las ventas "
    "del día —se leen 1.567 líneas y 2.858 buffers por refresco— y se paga completo en cada actualización del "
    "panel."))

story.append(h2("2.2 · (b) Patrón elegido y justificación"))
story.append(p(
    "Se eligió una <b>tabla de agregación incremental por fecha y categoría, mantenida por disparadores</b> "
    "(el equivalente a una columna precalculada, pero al grano exacto del reporte) y no una vista materializada: "
    "la evidencia de 2.1 muestra que el costo no está en acceder a una fila sino en recorrer y agregar ~1.600 "
    "líneas por refresco, de modo que lo que hay que evitar es la reagregación, no el acceso; el panel exige el "
    "dato del día en tiempo real, y una vista materializada sólo se actualiza al refrescarse (o exige "
    "<i>REFRESH ... CONCURRENTLY</i>, que recalcula el histórico completo o requiere un planificador externo), "
    "mientras que los disparadores aplican un delta sobre una única fila por operación, dentro de la misma "
    "transacción, con lo cual el resumen nunca queda desincronizado; y el patrón es reversible sin pérdida "
    "porque la tabla es 100 % derivada: puede reconstruirse desde la fuente de verdad con "
    "<i>fs_resumen_reconstruir()</i> o descartarse por completo sin perder un solo dato original."))

story.append(h2("2.3 · (c) Implementación"))
story.append(p("La estructura desnormalizada y su clave son:"))
story += code_box("""CREATE TABLE resumen_venta_categoria_dia (
    fecha          DATE   NOT NULL,
    categoria_id   BIGINT NOT NULL REFERENCES categoria(id),
    total_vendido  NUMERIC(14,2) NOT NULL DEFAULT 0,
    cantidad_items BIGINT NOT NULL DEFAULT 0,
    actualizado_en TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (fecha, categoria_id)
);""")
story.append(p(
    "El grano de la tabla es exactamente el del reporte: una fila por día y categoría. Es deliberado que "
    "<b>no</b> se copie el nombre de la categoría: se guarda <i>categoria_id</i> y el reporte une con "
    "<i>categoria</i> (12 filas). Así, un cambio de nombre no exige sincronizar nada y no se introduce una "
    "segunda fuente de verdad para el nombre."))
story.append(p("La sincronización se reparte en cinco objetos, todos dentro de la misma transacción que la operación que los dispara:"))
story.append(tabla(
    ["Objeto", "Evento", "Qué hace"],
    [["<i>fs_resumen_aplicar</i>", "—",
      "Upsert atómico: inserta o suma el delta sobre (fecha, categoría) con <i>ON CONFLICT</i>."],
     ["<i>trg_detalle_resumen</i>", "INSERT / UPDATE / DELETE en detalle_pedido",
      "Resta el aporte del estado anterior y suma el del estado nuevo, sólo si ni la línea ni el pedido están "
      "eliminados."],
     ["<i>trg_pedido_resumen</i>", "UPDATE de fecha o eliminado en pedido",
      "Resta el aporte del pedido en su estado anterior y suma el del nuevo (cambio de día o baja lógica)."],
     ["<i>trg_pedido_borrado</i>", "BEFORE DELETE en pedido",
      "Resta el aporte antes de la cascada. Es BEFORE porque, cuando corre el borrado en cascada de "
      "detalle_pedido, el pedido ya no existe y el disparador de detalle no podría resolver la fecha."],
     ["<i>trg_producto_categoria</i>", "UPDATE de categoria_id en producto",
      "Mueve el histórico del producto: resta de la categoría anterior y suma en la nueva, por fecha."]],
    [3.9 * cm, 4.4 * cm, 8.7 * cm]))
story.append(Spacer(1, 6))
story.append(p(
    "La carga inicial (y la reconciliación) se resuelve con <i>fs_resumen_reconstruir()</i>, que trunca la tabla "
    "y la recalcula desde <i>detalle_pedido</i>, <i>producto</i> y <i>pedido</i>. La función es también el "
    "camino previsto para cargas masivas: <i>TRUNCATE</i> no dispara triggers de fila y un <i>COPY</i> histórico "
    "pagaría el costo de sincronización fila por fila, por lo que conviene deshabilitar los disparadores, cargar "
    "y reconstruir."))
story.append(p(
    "Para el mantenimiento del histórico se define además el procedimiento "
    "<i>fs_reconstruir_resumen(p_desde, p_hasta, p_commit, p_lote_dias)</i>, invocado con <b>CALL</b>. La "
    "diferencia con la función no es cosmética: el procedimiento recorre el rango en lotes —borra y recalcula "
    "cada bloque de días— y, si se le pide, confirma al terminar cada uno, de modo que una interrupción no "
    "obliga a empezar de nuevo. Sobre la base poblada, el histórico completo (730 días) se reconstruye en nueve "
    "lotes de 90 días en <b>2,55 s</b> y la auditoría vuelve a quedar en 0 filas "
    "(<i>resultados/call_procedimiento.txt</i>). El parámetro <i>p_commit</i> es <i>false</i> por omisión por una "
    "razón concreta: PostgreSQL no admite un <i>COMMIT</i> dentro de la transacción de otro, y un <i>CALL</i> con "
    "<i>p_commit = true</i> ejecutado dentro de un bloque <i>BEGIN</i> falla con «invalid transaction "
    "termination». La prueba de ambos comportamientos está en la misma captura. El procedimiento queda fuera del "
    "camino caliente: no interviene en las ventas, sólo en las tareas de reconciliación."))

story.append(h2("2.4 · (d) Consulta sobre la estructura desnormalizada y comparación"))
story.append(p("La consulta del panel se reescribe para leer el agregado del día y unir sólo con la tabla de categorías:"))
story += code_box("""SELECT c.nombre AS categoria,
       r.total_vendido
FROM resumen_venta_categoria_dia r
JOIN categoria c ON c.id = r.categoria_id
WHERE r.fecha = CURRENT_DATE
ORDER BY r.total_vendido DESC
LIMIT 5;""")
story.append(p(
    "El plan resultante es un <i>Bitmap Index Scan</i> sobre la clave primaria del resumen (12 filas), un "
    "<i>Hash Join</i> con las 12 categorías y un <i>top-N heapsort</i>. No se toca <i>detalle_pedido</i>."))
story.append(Spacer(1, 4))
story.append(tabla(
    ["Métrica", "Antes (consulta normalizada)", "Después (consulta desnormalizada)"],
    [["Tiempo de ejecución<br/>(mediana de 5 ejecuciones)",
      "<b>148,46 ms</b> con el esquema original<br/><b>4,54 ms</b> agregando el índice sobre la FK",
      "<b>0,075 ms</b>"],
     ["Nodo dominante",
      "<i>Parallel Seq Scan</i> sobre detalle_pedido (1,25 M de filas)<br/>"
      "<i>Nested Loop</i> + <i>Index Scan</i> sobre detalle_pedido (316 iteraciones) en la variante indexada",
      "<i>Bitmap Index Scan</i> sobre la PK del resumen (12 filas) + <i>Hash Join</i> con categoria"],
     ["Filas leídas del detalle", "1.250.000 (original) · 1.567 (indexada)", "0"],
     ["Buffers del plan", "12.641 · 2.858", "<b>19</b>"],
     ["Mejora vs. esquema original", "1×", "<b>1.979×</b>"]],
    [4.4 * cm, 6.8 * cm, 5.8 * cm], "cell"))
story.append(Spacer(1, 4))
story.append(p(
    "La tabla reporta la mediana de cinco ejecuciones para amortiguar el ruido del sistema operativo; las "
    "capturas completas de una ejecución representativa (129,82 ms / 10,48 ms / 0,16 ms) están en el Anexo B. "
    "La comparación más exigente es contra el esquema indexado, porque aísla el efecto de la desnormalización "
    "del efecto de un índice: aun así, el resumen es <b>60 veces</b> más rápido y lee 150 veces menos buffers."))

story.append(p("La consulta desnormalizada devuelve exactamente los mismos totales que la normalizada, para las 12 categorías del día:"))
story.append(tabla(
    ["Categoría", "Total normalizado", "Total del resumen", "¿Coincide?"],
    [["Panadería", "225.409,65", "225.409,65", "Sí"],
     ["Limpieza", "205.812,50", "205.812,50", "Sí"],
     ["Lácteos", "197.032,69", "197.032,69", "Sí"],
     ["Frutas y Verduras", "181.256,67", "181.256,67", "Sí"],
     ["Congelados", "178.898,80", "178.898,80", "Sí"],
     ["… (7 categorías restantes)", "…", "…", "Sí (12/12)"]],
    [5.4 * cm, 3.9 * cm, 3.9 * cm, 3.8 * cm]))
story.append(Spacer(1, 4))
story.append(p("Los tipos NUMERIC hacen que la suma sea exacta: no hay diferencias por redondeo de punto flotante."))

story.append(h2("2.5 · (e) Auditoría de sincronización"))
story.append(p(
    "La auditoría recalcula el agregado desde la fuente de verdad y lo compara con el resumen mediante un "
    "<i>FULL OUTER JOIN</i>, de modo que detecta tanto diferencias de monto como filas faltantes de un lado o "
    "del otro. Se implementó como vista para poder ejecutarla cuando haga falta:"))
story += code_box("""CREATE OR REPLACE VIEW v_auditoria_resumen AS
WITH esperado AS (
    SELECT p.fecha, pr.categoria_id,
           SUM(dp.subtotal) AS total_vendido, SUM(dp.cantidad) AS cantidad_items
      FROM detalle_pedido dp
      JOIN producto pr ON pr.id = dp.producto_id
      JOIN pedido p    ON p.id  = dp.pedido_id
     WHERE NOT dp.eliminado AND NOT p.eliminado
     GROUP BY p.fecha, pr.categoria_id
)
SELECT COALESCE(e.fecha, r.fecha)               AS fecha,
       COALESCE(e.categoria_id, r.categoria_id) AS categoria_id,
       COALESCE(e.total_vendido, 0)             AS total_esperado,
       COALESCE(r.total_vendido, 0)             AS total_resumen,
       COALESCE(e.total_vendido, 0) - COALESCE(r.total_vendido, 0) AS diferencia,
       COALESCE(e.cantidad_items, 0)            AS items_esperados,
       COALESCE(r.cantidad_items, 0)            AS items_resumen
  FROM esperado e
  FULL OUTER JOIN resumen_venta_categoria_dia r
    ON r.fecha = e.fecha AND r.categoria_id = e.categoria_id
 WHERE COALESCE(e.total_vendido, 0) <> COALESCE(r.total_vendido, 0)
    OR COALESCE(e.cantidad_items, 0) <> COALESCE(r.cantidad_items, 0);""")
story.append(p("Ejecutada sobre la base ya migrada, la auditoría devuelve el resultado esperado:"))
story += code_box(""" fecha | categoria_id | total_esperado | total_resumen | diferencia | items_esperados | items_resumen
-------+--------------+----------------+---------------+------------+-----------------+---------------
(0 filas)""")
story.append(p(
    "Una auditoría que siempre devuelve vacío no demuestra nada por sí sola; por eso el script incluye una "
    "prueba de que <b>no es vacua</b>: dentro de una transacción se suma 1 al total de una categoría del día y "
    "la vista detecta exactamente una diferencia, que se revierte al hacer ROLLBACK. También se probaron las "
    "operaciones que mantienen el resumen (alta de línea, baja lógica de un pedido y recategorización de un "
    "producto): después de cada una, la auditoría sigue devolviendo 0 filas."))

story.append(h2("2.6 · Costo de escritura y operación"))
story.append(p(
    "La desnormalización no es gratuita: cada línea escrita paga un upsert al resumen. Se midió insertando las "
    "1.615 líneas del día con y sin el disparador, alternando el orden y repitiendo tres veces:"))
story.append(tabla(
    ["Operación (1.615 líneas)", "Mediana", "Por línea"],
    [["INSERT con sincronización", "179,0 ms", "≈ 111 µs"],
     ["INSERT con el disparador deshabilitado", "31,7 ms", "≈ 20 µs"],
     ["Sobrecosto", "≈ 5,6×", "≈ 91 µs"]],
    [8.4 * cm, 4.3 * cm, 4.3 * cm]))
story.append(Spacer(1, 5))
story.append(p(
    "Ese sobrecosto es aceptable para la relación lectura/escritura del panel: el reporte se ejecuta muchas "
    "veces por minuto y cada venta se escribe una vez. Para una carga histórica masiva, en cambio, conviene "
    "deshabilitar los disparadores, cargar y reconstruir con <i>fs_resumen_reconstruir()</i>."))
story.append(p(
    "En concurrencia, el <i>ON CONFLICT</i> toma un lock de fila sobre (fecha, categoría): dos ventas "
    "simultáneas de la misma categoría se serializan sólo en esa fila, no en toda la tabla. El resumen es, "
    "además, completamente reversible: <i>DROP TABLE resumen_venta_categoria_dia CASCADE</i> elimina la tabla y "
    "sus disparadores sin afectar un solo dato de la fuente de verdad."))

# ============================ CONCLUSIONES =================================
story.append(PageBreak())
story += h1("Conclusiones")
story.append(p(
    "El caso de <i>control_lote_almacen</i> muestra con precisión dónde está la frontera entre 3FN y FNBC: "
    "como el atributo determinado por la dependencia violatoria es primo, la relación cumple 3FN y no cumple "
    "FNBC. La descomposición en <i>responsable_deposito</i> y <i>control_lote_responsable</i> elimina la "
    "redundancia y es sin pérdida —el atributo común es superclave de R1—, y la verificación sobre la instancia "
    "reconstruye las tres filas originales sin diferencias. El precio es que la dependencia (LoteID, "
    "DepositoID) → ResponsableControlID no se preserva; el trigger de restricción diferido la recupera a nivel "
    "de motor, lo que deja explícito el trade-off en lugar de esconderlo."))
story.append(p(
    "En la Parte 2, la medición desarma la intuición: la consulta no era lenta por el <i>GROUP BY</i> —agrupa "
    "12 filas— sino por el recorrido secuencial de 1,25 millones de líneas para encontrar 1.567. Un índice sobre "
    "la clave foránea mejora 32,7 veces, pero no cambia la naturaleza del problema: el costo sigue creciendo "
    "con el volumen del día y se paga en cada refresco. El resumen por fecha y categoría desacopla el costo del "
    "volumen histórico y del volumen diario: 12 filas, 19 buffers, 0,075 ms."))
story.append(p(
    "La desnormalización se eligió con tres condiciones que el trabajo deja explícitas: está motivada por una "
    "medición, tiene un mecanismo de sincronización transaccional (no una ventana de inconsistencia), y es "
    "auditable y reversible. La auditoría devuelve vacío sobre la base migrada y, cuando se provoca una "
    "desincronización artificial, la detecta: el dato redundante no es una copia ciega, es un dato derivado con "
    "fuente de verdad, mecanismo de actualización y control de integridad."))

# ============================ ANEXO A ======================================
story += h1("Anexo A · Reproducción")
story.append(p("Los scripts son idempotentes. La Parte 2 recrea el esquema base, por lo que debe ejecutarse sobre una copia o sobre una base vacía:"))
story += code_box("""# 1) Base de trabajo
createdb -h localhost food_store_tp6

# 2) Parte 1: FNBC
psql -h localhost -d food_store_tp6 -v ON_ERROR_STOP=1 -f tp_fnbc_control_lote.sql

# 3) Parte 2: desnormalización (crea y puebla la réplica; ~30 s)
psql -h localhost -d food_store_tp6 -v ON_ERROR_STOP=1 -f tp_desnormalizacion_top_categorias.sql

# 4) Capturas y benchmark (opcional)
psql -h localhost -d food_store_tp6 -f resultados/benchmark.sql
psql -h localhost -d food_store_tp6 -f resultados/benchmark_explain.sql
psql -h localhost -d food_store_tp6 -f resultados/call_procedimiento.sql""")
story.append(Spacer(1, 4))
story.append(tabla(
    ["Elemento", "Detalle"],
    [["Motor", "PostgreSQL 17.11, Windows x64"],
     ["Instancia usada para las mediciones", "Clúster local aislado, puerto 55432, autenticación local"],
     ["shared_buffers / work_mem", "128 MB / 4 MB"],
     ["Paralelismo", "máximo 2 workers por consulta"],
     ["Población", "semilla 0.42 y hashes deterministas (reproducible)"],
     ["Archivos de resultados", "resultados/explain_antes.txt · explain_antes_optimizado.txt · explain_despues.txt · auditoria_final.txt · call_procedimiento.txt · benchmark_*.txt"]],
    [6.2 * cm, 10.8 * cm]))

# ============================ ANEXO B ======================================
story.append(NextPageTemplate("anexos"))
story.append(PageBreak())
story.append(Paragraph("Anexo B · Capturas de EXPLAIN (ANALYZE, BUFFERS)", S["h1_chico"]))
story.append(HRFlowable(width="100%", thickness=1.1, color=AZUL_CLARO,
                        spaceBefore=1, spaceAfter=6))
story.append(Paragraph("B.1 · Antes: consulta original sobre el esquema normalizado (sin índice sobre la FK)",
                       S["h2_chico"]))
story += code_box(plan_file("explain_antes.txt"), maxchars=198, chunk=500,
                  estilo="codigo_plan", indent=8, ancho=HOJA - 3.6 * cm)

story.append(PageBreak())
story.append(Paragraph("B.2 · Antes optimizado: el mismo esquema con índice sobre detalle_pedido(pedido_id)",
                       S["h2_chico"]))
story += code_box(plan_file("explain_antes_optimizado.txt"), maxchars=198, chunk=500,
                  estilo="codigo_plan", indent=8, ancho=HOJA - 3.6 * cm)

story.append(PageBreak())
story.append(Paragraph("B.3 · Después: consulta sobre la estructura desnormalizada", S["h2_chico"]))
story += code_box(plan_file("explain_despues.txt"), maxchars=198, chunk=500,
                  estilo="codigo_plan", indent=8, ancho=HOJA - 3.6 * cm)
story.append(Paragraph("B.4 · Auditoría de sincronización sobre la base migrada", S["h2_chico"]))
story += code_box(plan_file("auditoria_final.txt", quitar_pie_filas=False), maxchars=198, chunk=500,
                  estilo="codigo_plan", indent=8, ancho=HOJA - 3.6 * cm)

# ============================ ANEXO C ======================================
story.append(NextPageTemplate("todas"))
story.append(PageBreak())
story += h1("Anexo C · Trazabilidad de la consigna")
story.append(h2("Parte 1 — 4.2"))
story.append(tabla(
    ["Punto", "Dónde se responde", "Evidencia en el script"],
    [["a) Dependencias funcionales", "§1.2", "Comentario y sección 2"],
     ["b) Clausuras y claves candidatas", "§1.3", "Consultas 2.1 a 2.4"],
     ["c) Definición formal de FNBC", "§1.4", "Sección 3.4 (el motor acepta la violación)"],
     ["d) Anomalías de inserción, borrado y actualización", "§1.5", "Sección 3.1 a 3.3"],
     ["e) Descomposición, DDL y vista", "§1.6", "Secciones 4 y 5.3"],
     ["f) Reunión sin pérdida y migración", "§1.7 y §1.8", "Secciones 5.1, 5.2 y 5.4"]],
    [6.6 * cm, 4.4 * cm, 6.0 * cm]))
story.append(Spacer(1, 8))
story.append(h2("Parte 2 — 5.2"))
story.append(tabla(
    ["Punto", "Dónde se responde", "Evidencia en el script"],
    [["a) EXPLAIN ANALYZE inicial", "§2.1", "Sección 3; resultados/explain_antes.txt"],
     ["b) Patrón y justificación", "§2.2", "Sección 5"],
     ["c) Implementación del patrón", "§2.3", "Sección 5 (tabla, disparadores y procedimiento de mantenimiento)"],
     ["d) Consulta desnormalizada y comparación", "§2.4", "Sección 7; resultados/explain_despues.txt"],
     ["e) Script de auditoría", "§2.5", "Sección 8 (v_auditoria_resumen)"]],
    [6.6 * cm, 4.4 * cm, 6.0 * cm]))
story.append(Spacer(1, 10))
story.append(nota_box("Nota sobre el formato de entrega",
    "El repositorio incluye los dos scripts SQL, este informe y la carpeta <i>resultados/</i> con las capturas "
    "completas y los scripts de benchmark. Las cifras del informe se obtuvieron de esas capturas; las medianas "
    "se calcularon sobre cinco ejecuciones para reducir el efecto del ruido del sistema operativo."))

doc.build(story)
print("OK:", OUT)
