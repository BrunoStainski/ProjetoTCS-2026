"""
Gera os diagramas BPMN 2.0 em niveis (visao geral + detalhes) para a documentacao e o deck.

O diagrama completo (docs/bpmn_processo.bpmn) continua sendo a referencia unica e editavel do
processo inteiro, mas e largo demais para ler num slide. Aqui o mesmo processo e dividido do jeito
que o BPMN recomenda para processos grandes:

  0_visao_geral       jornada do usuario com subprocessos [+]; servidor e Gemini como caixas-pretas
  1_calculo           POST /calcular        3_perfil      POST /classificar (K-Means)
  2_troca_payback     POST /sugestoes e /comparar
  4_eco_coach         POST /eco-coach (RAG + Gemini)     5_treino_offline   scripts de dados e ML

Para cada um sai o .bpmn (BPMN 2.0 com diagrama, abre no Camunda Modeler e no demo.bpmn.io) e o
.svg (desenho vetorial na notacao BPMN, nitido em qualquer zoom) em docs/bpmn/. Se o Chrome/Edge
existir, sai tambem um .png (2x) para os slides.

Cores (tambem gravadas no .bpmn, o Camunda mostra): amarelo = acao do usuario, azul = calculo
deterministico em Python, verde = Machine Learning, roxo = IA generativa (RAG + LLM).

Uso (na raiz):  python scripts/gerar_bpmn_visoes.py
"""

import re
import shutil
import subprocess
import textwrap
from html import escape
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FOLDER = ROOT / "docs" / "bpmn"

COLORS = {"usuario": "#FFF4C2", "servico": "#E3EEFA", "ml": "#DFF3E6", "ia": "#EEE3FA",
         "branco": "#FFFFFF", "pool_servidor": "#F5F8FC", "pool_gemini": "#F8F3FD"}
TASKS = {"usuario", "servico", "ml", "ia", "envio", "sub"}
EVENTS = {"inicio", "inicio_msg", "fim", "fim_msg", "fim_erro", "inter_msg"}
GATEWAYS = {"xor", "and"}
SOURCE = "Arial, Helvetica, sans-serif"


def wrap_text(text, width_px, px_per_letter=6.4):
    return textwrap.wrap(text, max(6, int(width_px / px_per_letter)), break_on_hyphens=False) or [""]


class No:
    def __init__(self, id, kind, name, cx, cy, pool, w=None, h=None, cor=None, low_label=False):
        self.low_label = low_label
        self.id, self.kind, self.name, self.cx, self.cy, self.pool = id, kind, name, cx, cy, pool
        if kind in TASKS:
            self.w = w or 150
            lines = len(wrap_text(name, self.w - 16))
            self.h = h or max(80, lines * 15 + 26)
            self.cor = cor or {"usuario": "usuario", "envio": "usuario", "sub": "usuario"}.get(kind, kind)
        elif kind in EVENTS:
            self.w = self.h = 36
            self.cor = "branco"
        elif kind in GATEWAYS:
            self.w = self.h = 50
            self.cor = "branco"
        elif kind == "banco":
            self.w, self.h, self.cor = 50, 50, "branco"
        elif kind == "objeto":
            self.w, self.h, self.cor = 36, 48, "branco"
        self.inputs, self.outputs = [], []

    def border(self, side):
        return {"L": (self.cx - self.w / 2, self.cy), "R": (self.cx + self.w / 2, self.cy),
                "T": (self.cx, self.cy - self.h / 2), "B": (self.cx, self.cy + self.h / 2)}[side]


class Pool:
    def __init__(self, id, name, x, y, w, h, process=True, lanes=None, cor="branco"):
        self.id, self.name, self.x, self.y, self.w, self.h = id, name, x, y, w, h
        self.process = f"Proc_{id}" if process else None
        self.lanes = lanes or []  # [(id, nome, y, h)]
        self.cor = cor


class Diagram:
    def __init__(self, id, width, height):
        self.id, self.width, self.height = id, width, height
        self.pools, self.nodes, self.seqs, self.msgs, self.data, self.notes = [], {}, [], [], [], []

    # construcao ---------------------------------------------------------------------------
    def pool(self, *a, **k):
        p = Pool(*a, **k)
        self.pools.append(p)
        return p

    def no(self, pool, id, kind, name, cx, cy, **k):
        n = No(id, kind, name, cx, cy, pool, **k)
        self.nodes[id] = n
        return n

    def seq(self, a, b, name=None, points=None, label=None):
        a, b = self.nodes[a], self.nodes[b]
        pts = points or self._route(a, b)
        id = f"F_{a.id}_{b.id}"
        a.outputs.append(id)
        b.inputs.append(id)
        self.seqs.append({"id": id, "a": a, "b": b, "nome": name, "pts": pts, "rotulo": label})

    def msg(self, origin, destination, x, name, label):
        """Fluxo de mensagem vertical em x. origem/destino = id de no ou de pool."""
        y1 = self._y_msg(origin, destination)
        y2 = self._y_msg(destination, origin)
        self.msgs.append({"id": f"M_{origin}_{destination}_{int(x)}", "a": origin, "b": destination,
                          "pts": [(x, y1), (x, y2)], "nome": name, "rotulo": label})

    def item(self, id, kind, name, cx, cy, pool, task, payload=True, points=None):
        n = No(id, kind, name, cx, cy, pool)
        t = self.nodes[task]
        if points is None:
            if abs(n.cx - t.cx) < 1:
                points = [n.border("T" if n.cy > t.cy else "B"), t.border("B" if n.cy > t.cy else "T")]
            else:
                points = [n.border("T" if n.cy > t.cy else "B"), t.border("B" if n.cy > t.cy else "T")]
        if not payload:
            points = list(reversed(points))
        self.data.append({"no": n, "tarefa": t, "entrada": payload, "pts": points,
                           "id": f"DA_{id}_{task}"})

    def note(self, id, text, x, y, w, h, liga=None):
        self.notes.append({"id": id, "texto": text, "x": x, "y": y, "w": w, "h": h, "liga": liga})

    # geometria ----------------------------------------------------------------------------
    def _route(self, a, b):
        if abs(a.cy - b.cy) < 1:
            return [a.border("R"), b.border("L")]
        if a.kind in GATEWAYS:
            ini = a.border("B" if b.cy > a.cy else "T")
            return [ini, (a.cx, b.cy), b.border("L")]
        if b.kind in GATEWAYS:
            end = b.border("B" if a.cy > b.cy else "T")
            return [a.border("R"), (b.cx, a.cy), end]
        mx = (a.border("R")[0] + b.border("L")[0]) / 2
        return [a.border("R"), (mx, a.cy), (mx, b.cy), b.border("L")]

    def _box(self, id):
        if id in self.nodes:
            n = self.nodes[id]
            return n.cy - n.h / 2, n.cy + n.h / 2
        p = next(p for p in self.pools if p.id == id)
        return p.y, p.y + p.h

    def _y_msg(self, de, to):
        top, base = self._box(de)
        top2, _ = self._box(to)
        return base if top2 > top else top

    # BPMN XML -----------------------------------------------------------------------------
    def bpmn(self):
        X = []
        add = X.append
        add('<?xml version="1.0" encoding="UTF-8"?>')
        add('<bpmn:definitions xmlns:bpmn="http://www.omg.org/spec/BPMN/20100524/MODEL" '
            'xmlns:bpmndi="http://www.omg.org/spec/BPMN/20100524/DI" '
            'xmlns:dc="http://www.omg.org/spec/DD/20100524/DC" xmlns:di="http://www.omg.org/spec/DD/20100524/DI" '
            'xmlns:color="http://www.omg.org/spec/BPMN/non-normative/color/1.0" '
            f'id="Def_{self.id}" targetNamespace="http://iamp.tcs2026/bpmn" '
            'exporter="scripts/gerar_bpmn_visoes.py" exporterVersion="1.0">')
        add(f'  <bpmn:collaboration id="Colab_{self.id}">')
        for p in self.pools:
            ref = f' processRef="{p.process}"' if p.process else ""
            add(f'    <bpmn:participant id="{p.id}" name="{escape(p.name)}"{ref} />')
        for m in self.msgs:
            add(f'    <bpmn:messageFlow id="{m["id"]}" name="{escape(m["nome"])}" '
                f'sourceRef="{m["a"]}" targetRef="{m["b"]}" />')
        for n in self.notes:
            add(f'    <bpmn:textAnnotation id="{n["id"]}"><bpmn:text>{escape(n["texto"])}</bpmn:text>'
                '</bpmn:textAnnotation>')
            if n["liga"]:
                add(f'    <bpmn:association id="A_{n["id"]}" sourceRef="{n["liga"][0]}" targetRef="{n["id"]}" />')
        add('  </bpmn:collaboration>')

        for p in self.pools:
            if not p.process:
                continue
            add(f'  <bpmn:process id="{p.process}" isExecutable="false">')
            nodes = [n for n in self.nodes.values() if n.pool == p.id]
            if p.lanes:
                add(f'    <bpmn:laneSet id="LS_{p.id}">')
                for rid, rname, ry, rh in p.lanes:
                    add(f'      <bpmn:lane id="{rid}" name="{escape(rname)}">')
                    for n in nodes:
                        if ry <= n.cy < ry + rh:
                            add(f'        <bpmn:flowNodeRef>{n.id}</bpmn:flowNodeRef>')
                    add('      </bpmn:lane>')
                add('    </bpmn:laneSet>')
            for n in nodes:
                add("    " + self._xml_node(n))
            for s in self.seqs:
                if s["a"].pool == p.id:
                    name = f' name="{escape(s["nome"])}"' if s["nome"] else ""
                    add(f'    <bpmn:sequenceFlow id="{s["id"]}"{name} sourceRef="{s["a"].id}" targetRef="{s["b"].id}" />')
            for d in self.data:
                if d["no"].pool != p.id:
                    continue
                n = d["no"]
                if n.kind == "banco":
                    add(f'    <bpmn:dataStoreReference id="{n.id}" name="{escape(n.name)}" />')
                elif not any(x["no"].id == n.id for x in self.data[:self.data.index(d)]):
                    add(f'    <bpmn:dataObjectReference id="{n.id}" name="{escape(n.name)}" dataObjectRef="DO_{n.id}" />')
                    add(f'    <bpmn:dataObject id="DO_{n.id}" />')
            add('  </bpmn:process>')

        add(f'  <bpmndi:BPMNDiagram id="Diag_{self.id}">')
        add(f'    <bpmndi:BPMNPlane id="Plane_{self.id}" bpmnElement="Colab_{self.id}">')
        for p in self.pools:
            add(self._shape(p.id, p.x, p.y, p.w, p.h, COLORS[p.cor], horizontal=True))
            for rid, _, ry, rh in p.lanes:
                add(self._shape(rid, p.x + 30, ry, p.w - 30, rh, None, horizontal=True))
        seen = set()
        for n in list(self.nodes.values()) + [d["no"] for d in self.data]:
            if n.id in seen:
                continue
            seen.add(n.id)
            extra = ' isExpanded="false"' if n.kind == "sub" else ""
            label = None
            if n.kind in EVENTS:
                label = (n.cx - 60, n.cy + n.h / 2 + 4, 120, 40)
            elif n.kind in GATEWAYS and n.name:
                label = (n.cx - 70, n.cy + n.h / 2 + 4 if n.low_label else n.cy - n.h / 2 - 40, 140, 34)
            elif n.kind in ("banco", "objeto"):
                label = (n.cx - 60, n.cy + n.h / 2 + 4, 120, 40)
            add(self._shape(n.id, n.cx - n.w / 2, n.cy - n.h / 2, n.w, n.h,
                            COLORS[n.cor] if n.cor != "branco" else None, extra=extra, label=label))
        for note in self.notes:
            add(self._shape(note["id"], note["x"], note["y"], note["w"], note["h"], None))
        for s in self.seqs:
            label = None
            if s["nome"]:
                x, y = s["rotulo"] or (s["pts"][0][0] + 8, s["pts"][0][1] - 7)
                label = (x, y - 12, max(30, len(s["nome"]) * 6.5), 16)
            add(self._edge(s["id"], s["pts"], label))
        for m in self.msgs:
            (x, y1), (_, y2) = m["pts"]
            lx, ly, anchor = m["rotulo"]
            add(self._edge(m["id"], m["pts"], (lx - (130 if anchor == "end" else 0), ly - 12, 130, 30)))
        for d in self.data:
            add(self._edge(d["id"], d["pts"]))
        for note in self.notes:
            if note["liga"]:
                add(self._edge(f'A_{note["id"]}', note["liga"][1]))
        add('    </bpmndi:BPMNPlane>')
        add('  </bpmndi:BPMNDiagram>')
        add('</bpmn:definitions>')
        xml = "\n".join(X)
        # associacoes de dados ficam dentro das tarefas (padrao do Camunda)
        for d in self.data:
            t, n = d["tarefa"], d["no"]
            if d["entrada"]:
                chunk = (f'<bpmn:property id="P_{d["id"]}" name="__targetRef_placeholder" />'
                          f'<bpmn:dataInputAssociation id="{d["id"]}"><bpmn:sourceRef>{n.id}</bpmn:sourceRef>'
                          f'<bpmn:targetRef>P_{d["id"]}</bpmn:targetRef></bpmn:dataInputAssociation>')
            else:
                chunk = (f'<bpmn:dataOutputAssociation id="{d["id"]}"><bpmn:targetRef>{n.id}</bpmn:targetRef>'
                          '</bpmn:dataOutputAssociation>')
            xml = xml.replace(f'<!--DADOS_{t.id}-->', chunk + f'<!--DADOS_{t.id}-->', 1)
        return re.sub(r"<!--DADOS_[^>]*-->", "", xml)

    def _xml_node(self, n):
        tag = {"usuario": "userTask", "servico": "serviceTask", "ml": "serviceTask", "ia": "serviceTask",
               "envio": "sendTask", "sub": "subProcess", "inicio": "startEvent", "inicio_msg": "startEvent",
               "fim": "endEvent", "fim_msg": "endEvent", "fim_erro": "endEvent",
               "inter_msg": "intermediateCatchEvent", "xor": "exclusiveGateway", "and": "parallelGateway"}[n.kind]
        name = f' name="{escape(n.name)}"' if n.name else ""
        body = "".join(f"<bpmn:incoming>{f}</bpmn:incoming>" for f in n.inputs)
        body += "".join(f"<bpmn:outgoing>{f}</bpmn:outgoing>" for f in n.outputs)
        if n.kind in TASKS:
            body += f"<!--DADOS_{n.id}-->"
        if n.kind in ("inicio_msg", "fim_msg", "inter_msg"):
            body += f'<bpmn:messageEventDefinition id="MED_{n.id}" />'
        if n.kind == "fim_erro":
            body += f'<bpmn:errorEventDefinition id="EED_{n.id}" />'
        return f'<bpmn:{tag} id="{n.id}"{name}>{body}</bpmn:{tag}>'

    @staticmethod
    def _shape(id, x, y, w, h, cor, horizontal=False, extra="", label=None):
        hz = ' isHorizontal="true"' if horizontal else ""
        c = f' color:background-color="{cor}" color:border-color="#000000"' if cor else ""
        r = ""
        if label:
            r = (f'<bpmndi:BPMNLabel><dc:Bounds x="{label[0]:.0f}" y="{label[1]:.0f}" '
                 f'width="{label[2]:.0f}" height="{label[3]:.0f}" /></bpmndi:BPMNLabel>')
        return (f'      <bpmndi:BPMNShape id="S_{id}" bpmnElement="{id}"{hz}{extra}{c}>'
                f'<dc:Bounds x="{x:.0f}" y="{y:.0f}" width="{w:.0f}" height="{h:.0f}" />{r}</bpmndi:BPMNShape>')

    @staticmethod
    def _edge(id, pts, label=None):
        wp = "".join(f'<di:waypoint x="{x:.0f}" y="{y:.0f}" />' for x, y in pts)
        r = ""
        if label:
            r = (f'<bpmndi:BPMNLabel><dc:Bounds x="{label[0]:.0f}" y="{label[1]:.0f}" '
                 f'width="{label[2]:.0f}" height="{label[3]:.0f}" /></bpmndi:BPMNLabel>')
        return f'      <bpmndi:BPMNEdge id="E_{id}" bpmnElement="{id}">{wp}{r}</bpmndi:BPMNEdge>'

    # SVG ----------------------------------------------------------------------------------
    def svg(self):
        S = []
        add = S.append
        add(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {self.width} {self.height}" '
            f'width="{self.width}" height="{self.height}" font-family="{SOURCE}" font-size="12">')
        add('<defs>'
            '<marker id="seta" viewBox="0 0 10 10" refX="10" refY="5" markerWidth="9" markerHeight="9" orient="auto">'
            '<path d="M0,1 L10,5 L0,9 z" fill="#000"/></marker>'
            '<marker id="seta_msg" viewBox="0 0 10 10" refX="10" refY="5" markerWidth="10" markerHeight="10" orient="auto">'
            '<path d="M0,1 L10,5 L0,9 z" fill="#fff" stroke="#000" stroke-width="1"/></marker>'
            '<marker id="bola_msg" viewBox="0 0 10 10" refX="5" refY="5" markerWidth="8" markerHeight="8">'
            '<circle cx="5" cy="5" r="4" fill="#fff" stroke="#000" stroke-width="1"/></marker>'
            '<marker id="seta_dado" viewBox="0 0 10 10" refX="10" refY="5" markerWidth="8" markerHeight="8" orient="auto">'
            '<path d="M0,1 L10,5 L0,9" fill="none" stroke="#000" stroke-width="1.2"/></marker>'
            '</defs>')
        add(f'<rect width="{self.width}" height="{self.height}" fill="#fff"/>')
        for p in self.pools:
            add(self._svg_pool(p))
        for n in self.notes:
            add(self._svg_note(n))
        for d in self.data:
            add(self._line(d["pts"], 'stroke-dasharray="2 3" stroke-width="1.3"', end="seta_dado"))
        for s in self.seqs:
            add(self._line(s["pts"], 'stroke-width="1.6"', end="seta"))
            if s["nome"]:
                x, y = s["rotulo"] or (s["pts"][0][0] + 8, s["pts"][0][1] - 7)
                add(self._text(s["nome"], x, y, "start", size=11))
        for m in self.msgs:
            add(self._line(m["pts"], 'stroke-dasharray="6 4" stroke-width="1.4"', ini="bola_msg", end="seta_msg"))
            lx, ly, anchor = m["rotulo"]
            for i, line in enumerate(wrap_text(m["nome"], 150)):
                add(self._text(line, lx, ly + i * 13, anchor, size=11, style="italic"))
        seen = set()
        for d in self.data:
            if d["no"].id not in seen:
                seen.add(d["no"].id)
                add(self._svg_node(d["no"]))
        for n in self.nodes.values():
            add(self._svg_node(n))
        add('</svg>')
        return "\n".join(S)

    @staticmethod
    def _text(t, x, y, anchor="middle", size=12, weight="normal", style="normal"):
        return (f'<text x="{x:.1f}" y="{y:.1f}" text-anchor="{anchor}" font-size="{size}" '
                f'font-weight="{weight}" font-style="{style}">{escape(t)}</text>')

    @staticmethod
    def _line(pts, style, ini=None, end=None):
        p = " ".join(f"{x:.1f},{y:.1f}" for x, y in pts)
        m = (f' marker-start="url(#{ini})"' if ini else "") + (f' marker-end="url(#{end})"' if end else "")
        return f'<polyline points="{p}" fill="none" stroke="#000" {style}{m}/>'

    def _svg_pool(self, p):
        cor = COLORS[p.cor]
        out = [f'<rect x="{p.x}" y="{p.y}" width="{p.w}" height="{p.h}" fill="{cor}" stroke="#000" stroke-width="1.5"/>']
        if p.process:
            out.append(f'<line x1="{p.x + 30}" y1="{p.y}" x2="{p.x + 30}" y2="{p.y + p.h}" stroke="#000" stroke-width="1.5"/>')
            cx, cy = p.x + 19, p.y + p.h / 2
            out.append(f'<text transform="translate({cx},{cy}) rotate(-90)" text-anchor="middle" '
                       f'font-size="13" font-weight="bold">{escape(p.name)}</text>')
            for _, rname, ry, rh in p.lanes:
                out.append(f'<rect x="{p.x + 30}" y="{ry}" width="{p.w - 30}" height="{rh}" fill="none" stroke="#000" stroke-width="1"/>')
                out.append(f'<line x1="{p.x + 58}" y1="{ry}" x2="{p.x + 58}" y2="{ry + rh}" stroke="#000" stroke-width="1"/>')
                out.append(f'<text transform="translate({p.x + 48},{ry + rh / 2}) rotate(-90)" '
                           f'text-anchor="middle" font-size="12">{escape(rname)}</text>')
        else:  # pool caixa-preta: nome no centro
            out.append(self._text(p.name, p.x + p.w / 2, p.y + p.h / 2 + 5, size=14, weight="bold"))
        return "\n".join(out)

    def _svg_note(self, n):
        x, y, w, h = n["x"], n["y"], n["w"], n["h"]
        out = [f'<path d="M{x + 12},{y} L{x},{y} L{x},{y + h} L{x + 12},{y + h}" fill="none" stroke="#000" stroke-width="1.3"/>']
        for i, line in enumerate(wrap_text(n["texto"], w - 12, 6.0)):
            out.append(self._text(line, x + 8, y + 16 + i * 14, "start", size=11.5))
        if n["liga"]:
            out.append(self._line(n["liga"][1], 'stroke-dasharray="2 3" stroke-width="1.2"'))
        return "\n".join(out)

    def _svg_node(self, n):
        x, y, w, h, cx, cy = n.cx - n.w / 2, n.cy - n.h / 2, n.w, n.h, n.cx, n.cy
        out = []
        if n.kind in TASKS:
            out.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="10" fill="{COLORS[n.cor]}" stroke="#000" stroke-width="1.8"/>')
            lines = wrap_text(n.name, w - 16)
            y0 = cy - (len(lines) - 1) * 15 / 2 + 4 + (4 if n.kind != "sub" else -2)
            for i, line in enumerate(lines):
                out.append(self._text(line, cx, y0 + i * 15))
            out.append(self._icon(n.kind, x, y, w, h))
        elif n.kind in EVENTS:
            border = {"fim": 4, "fim_msg": 4, "fim_erro": 4}.get(n.kind, 1.8)
            out.append(f'<circle cx="{cx}" cy="{cy}" r="18" fill="#fff" stroke="#000" stroke-width="{border}"/>')
            if n.kind == "inter_msg":
                out.append(f'<circle cx="{cx}" cy="{cy}" r="14.5" fill="none" stroke="#000" stroke-width="1.3"/>')
            if n.kind in ("inicio_msg", "inter_msg", "fim_msg"):
                full = n.kind == "fim_msg"
                out.append(f'<rect x="{cx - 9}" y="{cy - 6}" width="18" height="12" fill="{"#000" if full else "#fff"}" stroke="#000" stroke-width="1.2"/>')
                out.append(f'<polyline points="{cx - 9},{cy - 6} {cx},{cy + 1} {cx + 9},{cy - 6}" fill="none" stroke="{"#fff" if full else "#000"}" stroke-width="1.2"/>')
            if n.kind == "fim_erro":
                out.append(f'<polygon points="{cx - 8},{cy + 8} {cx - 3},{cy - 7} {cx + 2},{cy + 1} {cx + 8},{cy - 8} {cx + 3},{cy + 7} {cx - 2},{cy - 1}" fill="#000"/>')
            for i, line in enumerate(wrap_text(n.name, 112)):
                out.append(self._text(line, cx, cy + 32 + i * 13, size=11))
        elif n.kind in GATEWAYS:
            out.append(f'<polygon points="{cx},{cy - 25} {cx + 25},{cy} {cx},{cy + 25} {cx - 25},{cy}" fill="#fff" stroke="#000" stroke-width="1.8"/>')
            if n.kind == "xor":
                out.append(f'<path d="M{cx - 8},{cy - 8} L{cx + 8},{cy + 8} M{cx + 8},{cy - 8} L{cx - 8},{cy + 8}" stroke="#000" stroke-width="4"/>')
            else:
                out.append(f'<path d="M{cx - 11},{cy} L{cx + 11},{cy} M{cx},{cy - 11} L{cx},{cy + 11}" stroke="#000" stroke-width="4"/>')
            if n.name:
                lines = wrap_text(n.name, 130)
                for i, line in enumerate(lines):
                    y = cy + 40 + i * 13 if n.low_label else cy - 32 - (len(lines) - 1 - i) * 13
                    out.append(self._text(line, cx, y, size=11))
        elif n.kind == "banco":
            out.append(f'<path d="M{x},{y + 8} L{x},{y + h - 8} A{w / 2},8 0 0 0 {x + w},{y + h - 8} L{x + w},{y + 8}" fill="#fff" stroke="#000" stroke-width="1.6"/>')
            out.append(f'<ellipse cx="{cx}" cy="{y + 8}" rx="{w / 2}" ry="8" fill="#fff" stroke="#000" stroke-width="1.6"/>')
            out.append(f'<path d="M{x},{y + 15} A{w / 2},8 0 0 0 {x + w},{y + 15}" fill="none" stroke="#000" stroke-width="1.2"/>')
            for i, line in enumerate(wrap_text(n.name, 130)):
                out.append(self._text(line, cx, y + h + 14 + i * 13, size=11))
        elif n.kind == "objeto":
            out.append(f'<path d="M{x},{y} L{x + w - 10},{y} L{x + w},{y + 10} L{x + w},{y + h} L{x},{y + h} Z" fill="#fff" stroke="#000" stroke-width="1.6"/>')
            out.append(f'<path d="M{x + w - 10},{y} L{x + w - 10},{y + 10} L{x + w},{y + 10}" fill="none" stroke="#000" stroke-width="1.2"/>')
            for i, line in enumerate(wrap_text(n.name, 130)):
                out.append(self._text(line, cx, y + h + 14 + i * 13, size=11))
        return "\n".join(out)

    @staticmethod
    def _icon(kind, x, y, w, h):
        if kind == "usuario":
            return (f'<circle cx="{x + 14}" cy="{y + 11}" r="4.5" fill="#fff" stroke="#000" stroke-width="1.2"/>'
                    f'<path d="M{x + 6},{y + 25} Q{x + 6},{y + 16} {x + 14},{y + 16} Q{x + 22},{y + 16} {x + 22},{y + 25} Z" '
                    'fill="#fff" stroke="#000" stroke-width="1.2"/>')
        if kind in ("servico", "ml", "ia"):
            return (f'<circle cx="{x + 15}" cy="{y + 15}" r="6.5" fill="none" stroke="#000" stroke-width="3.6" stroke-dasharray="2.6 1.9"/>'
                    f'<circle cx="{x + 15}" cy="{y + 15}" r="4.6" fill="#fff" stroke="#000" stroke-width="1"/>'
                    f'<circle cx="{x + 15}" cy="{y + 15}" r="1.8" fill="none" stroke="#000" stroke-width="1"/>')
        if kind == "envio":
            return (f'<rect x="{x + 7}" y="{y + 8}" width="18" height="12" fill="#000"/>'
                    f'<polyline points="{x + 7},{y + 8} {x + 16},{y + 15} {x + 25},{y + 8}" fill="none" stroke="#fff" stroke-width="1.2"/>')
        if kind == "sub":
            bx, by = x + w / 2 - 7, y + h - 17
            return (f'<rect x="{bx}" y="{by}" width="14" height="14" fill="#fff" stroke="#000" stroke-width="1.2"/>'
                    f'<path d="M{bx + 3},{by + 7} L{bx + 11},{by + 7} M{bx + 7},{by + 3} L{bx + 7},{by + 11}" stroke="#000" stroke-width="1.6"/>')
        return ""


# Diagramas ---------------------------------------------------------------------------------

def general_view():
    d = Diagram("visao_geral", 1520, 700)
    d.pool("P_App", "Usuário (app iamp)", 10, 10, 1500, 300)
    d.pool("P_Srv", "Servidor iamp (API FastAPI + PostgreSQL + modelos de ML)", 10, 430, 1500, 70,
           process=False, cor="pool_servidor")
    d.pool("P_Gem", "Gemini API (Google, serviço externo)", 860, 620, 650, 60, process=False, cor="pool_gemini")
    Y, Y2 = 120, 225
    d.no("P_App", "ini", "inicio", "Quer reduzir a conta de luz", 100, Y)
    d.no("P_App", "calc", "sub", "Calcular consumo e custo de cada aparelho", 240, Y, w=160)
    d.no("P_App", "g_troca", "xor", "Ver opções de troca?", 400, Y)
    d.no("P_App", "troca", "sub", "Avaliar troca e payback", 540, Y2, w=160)
    d.no("P_App", "g_junta", "xor", "", 680, Y)
    d.no("P_App", "g_mais", "xor", "Mais aparelhos?", 780, Y, low_label=True)
    d.no("P_App", "perfil", "sub", "Ver o perfil de consumo da casa", 930, Y, w=160)
    d.no("P_App", "eco", "sub", "Pedir o plano ao Eco-Coach", 1120, Y, w=160)
    d.no("P_App", "ler", "usuario", "Ler o plano e conferir as fontes [n]", 1300, Y, w=150)
    d.no("P_App", "fim", "fim", "Plano de economia pronto", 1440, Y)
    d.seq("ini", "calc")
    d.seq("calc", "g_troca")
    d.seq("g_troca", "troca", "sim", label=(406, Y + 48))
    d.seq("g_troca", "g_junta", "não", label=(470, Y - 8))
    d.seq("troca", "g_junta")
    d.seq("g_junta", "g_mais")
    d.seq("g_mais", "calc", "sim", points=[(780, Y - 25), (780, 38), (240, 38), (240, Y - 40)], label=(788, 52))
    d.seq("g_mais", "perfil", "não", label=(812, Y - 8))
    d.seq("perfil", "eco")
    d.seq("eco", "ler")
    d.seq("ler", "fim")
    srv_top = 430
    d.msg("calc", "P_Srv", 220, "POST /calcular", (214, 350, "end"))
    d.msg("P_Srv", "calc", 260, "kWh, R$ e avisos", (266, 395, "start"))
    d.msg("troca", "P_Srv", 520, "POST /sugestoes e /comparar", (514, 345, "end"))
    d.msg("P_Srv", "troca", 560, "equivalentes, economia e payback", (566, 395, "start"))
    d.msg("perfil", "P_Srv", 910, "POST /classificar", (904, 350, "end"))
    d.msg("P_Srv", "perfil", 950, "perfil e comparação", (956, 395, "start"))
    d.msg("eco", "P_Srv", 1100, "POST /eco-coach", (1094, 350, "end"))
    d.msg("P_Srv", "eco", 1140, "plano com fontes [n]", (1146, 395, "start"))
    d.msg("P_Srv", "P_Gem", 1200, "prompt: regras + dados da casa + trechos oficiais", (1194, 545, "end"))
    d.msg("P_Gem", "P_Srv", 1240, "texto do plano", (1246, 565, "start"))
    d.note("N_privacidade", "O Gemini recebe só números de consumo e trechos de documentos públicos: nenhum dado "
           "pessoal sai do iamp.", 380, 610, 400, 50)
    d.note("N_legenda", "[+] = subprocesso detalhado nas próximas páginas. Linhas tracejadas = mensagens "
           "(chamadas à API).", 20, 520, 560, 50)
    return d


def calculation():
    d = Diagram("calculo", 1300, 420)
    d.pool("P_Srv", "Servidor iamp: POST /calcular", 10, 10, 1280, 400)
    Y, Y2 = 120, 245
    d.no("P_Srv", "ini", "inicio_msg", "Pedido de cálculo recebido", 90, Y)
    d.no("P_Srv", "validar", "servico", "Validar aparelho, uso e tarifa", 215, Y, w=140)
    d.no("P_Srv", "g_valido", "xor", "Dados válidos?", 330, Y)
    d.no("P_Srv", "erro", "fim_erro", "Erro 404 / 422", 330, Y2)
    d.no("P_Srv", "g_catalogo", "xor", "Aparelho no catálogo?", 440, Y)
    d.no("P_Srv", "regras", "servico", "Calcular kWh pelas regras do Inmetro (kWh/mês, kWh/ciclo ou W × horas)", 610, Y, w=180)
    d.no("P_Srv", "estimar", "ml", "Estimar kWh fora do catálogo (etiqueta, Portaria 2006 ou Random Forest)", 610, Y2, w=180)
    d.no("P_Srv", "g_junta", "xor", "", 780, Y)
    d.no("P_Srv", "tarifa", "servico", "Aplicar a tarifa B1 da ANEEL ou a da conta de luz", 900, Y, w=150)
    d.no("P_Srv", "registrar", "servico", "Registrar a consulta (sem dados pessoais)", 1080, Y, w=150)
    d.no("P_Srv", "fim", "fim_msg", "Resultado enviado (kWh, R$ e avisos)", 1220, Y)
    d.seq("ini", "validar")
    d.seq("validar", "g_valido")
    d.seq("g_valido", "erro", "não", label=(338, Y + 50))
    d.seq("g_valido", "g_catalogo", "sim", label=(360, Y - 8))
    d.seq("g_catalogo", "regras", "sim", label=(470, Y - 8))
    d.seq("g_catalogo", "estimar", "não", label=(448, Y + 50))
    d.seq("regras", "g_junta")
    d.seq("estimar", "g_junta")
    d.seq("g_junta", "tarifa")
    d.seq("tarifa", "registrar")
    d.seq("registrar", "fim")
    d.item("refri", "objeto", "refrigerador.pkl", 760, 335, "P_Srv", "estimar",
           points=[(742, 335), (680, 285)])
    d.item("db", "banco", "PostgreSQL (aparelhos, tarifas, consultas)", 990, 270, "P_Srv", "tarifa",
           points=[(975, 245), (920, 160)])
    d.item("db", "banco", "PostgreSQL (aparelhos, tarifas, consultas)", 990, 270, "P_Srv", "registrar",
           payload=False, points=[(1005, 245), (1060, 160)])
    d.note("N_impostos", "Valores sem ICMS, PIS/COFINS, bandeira e iluminação pública: o app sempre avisa.",
           1080, 230, 190, 70)
    return d


def payback_swap():
    d = Diagram("troca_payback", 1300, 420)
    d.pool("P_Srv", "Servidor iamp: troca e payback", 10, 10, 1280, 400,
           lanes=[("L_sug", "POST /sugestoes", 10, 180), ("L_comp", "POST /comparar", 190, 220)])
    Y, Y2 = 100, 290
    d.no("P_Srv", "s_ini", "inicio_msg", "Aparelho atual recebido", 125, Y)
    d.no("P_Srv", "s_busca", "servico", "Buscar equivalentes: mesma categoria, medida parecida e mesmo tipo", 270, Y, w=180)
    d.no("P_Srv", "s_descarta", "servico", "Descartar dado imputado e suspeito (consumo < 40% da mediana)", 480, Y, w=180)
    d.no("P_Srv", "s_economia", "servico", "Calcular a economia com o mesmo uso e a mesma tarifa", 690, Y, w=170)
    d.no("P_Srv", "s_filtra", "servico", "Manter economia ≥ 5% e ordenar (uma variação por modelo)", 900, Y, w=170)
    d.no("P_Srv", "s_fim", "fim_msg", "Sugestões enviadas", 1060, Y)
    for a, b in [("s_ini", "s_busca"), ("s_busca", "s_descarta"), ("s_descarta", "s_economia"),
                 ("s_economia", "s_filtra"), ("s_filtra", "s_fim")]:
        d.seq(a, b)
    d.no("P_Srv", "c_ini", "inicio_msg", "Troca escolhida (+ preço opcional)", 125, Y2)
    d.no("P_Srv", "c_economia", "servico", "Economia/mês = (kWh atual − kWh novo) × tarifa", 270, Y2, w=180)
    d.no("P_Srv", "g_preco", "xor", "Preço do novo informado?", 430, Y2)
    d.no("P_Srv", "c_payback", "servico", "Payback = preço ÷ economia/mês", 580, Y2, w=150)
    d.no("P_Srv", "g_junta", "xor", "", 730, Y2)
    d.no("P_Srv", "c_fim", "fim_msg", "Economia e payback enviados", 840, Y2)
    d.seq("c_ini", "c_economia")
    d.seq("c_economia", "g_preco")
    d.seq("g_preco", "c_payback", "sim", label=(460, Y2 - 8))
    d.seq("g_preco", "g_junta", "não", points=[(430, Y2 + 25), (430, 375), (730, 375), (730, Y2 + 25)],
          label=(438, 368))
    d.seq("c_payback", "g_junta")
    d.seq("g_junta", "c_fim")
    d.note("N_payback", "Payback simples: sem juros, sem revenda do aparelho antigo e sem reajuste de tarifa. "
           "O catálogo não tem preços: o usuário digita o valor.", 930, 255, 330, 70)
    return d


def profile():
    d = Diagram("perfil", 1300, 300)
    d.pool("P_Srv", "Servidor iamp: POST /classificar", 10, 10, 1280, 280)
    Y = 115
    d.no("P_Srv", "ini", "inicio_msg", "Casa recebida (moradores + kWh de cada item)", 95, Y)
    d.no("P_Srv", "g_valida", "xor", "Entrada válida?", 200, Y)
    d.no("P_Srv", "erro", "fim_erro", "Erro 422", 200, 225)
    d.no("P_Srv", "fracoes", "servico", "Calcular kWh por morador e frações (chuveiro, ar, geladeira)", 360, Y, w=180)
    d.no("P_Srv", "escala", "ml", "Aplicar escala e pesos (log kWh/morador × 2; frações × 0,5)", 570, Y, w=180)
    d.no("P_Srv", "centroide", "ml", "Atribuir ao centróide mais próximo (Consciente, Moderado ou Ineficiente)", 780, Y, w=180)
    d.no("P_Srv", "mediana", "servico", "Comparar com a mediana das casas sintéticas", 990, Y, w=170)
    d.no("P_Srv", "fim", "fim_msg", "Perfil enviado (com aviso de dado sintético)", 1170, Y)
    d.seq("ini", "g_valida")
    d.seq("g_valida", "erro", "não", label=(208, Y + 50))
    d.seq("g_valida", "fracoes", "sim", label=(232, Y - 8))
    d.seq("fracoes", "escala")
    d.seq("escala", "centroide")
    d.seq("centroide", "mediana")
    d.seq("mediana", "fim")
    d.item("kmeans", "objeto", "kmeans.pkl (só números)", 675, 225, "P_Srv", "escala", points=[(665, 201), (600, 160)])
    d.item("kmeans", "objeto", "kmeans.pkl (só números)", 675, 225, "P_Srv", "centroide", points=[(685, 201), (750, 160)])
    d.note("N_sintetico", "Não usa o banco nem grava nada. Treinado com 5.000 casas sintéticas (CTGAN): o perfil é demonstrativo.",
           900, 195, 330, 60)
    return d


def eco_coach():
    d = Diagram("eco_coach", 1460, 640)
    d.pool("P_Srv", "Servidor iamp: POST /eco-coach", 10, 10, 1440, 380)
    d.pool("P_Gem", "Gemini API (Google, serviço externo)", 10, 500, 1440, 60, process=False, cor="pool_gemini")
    Y, Y2 = 115, 275
    d.no("P_Srv", "ini", "inicio_msg", "Casa recebida (consumos, custos e trocas)", 95, Y)
    d.no("P_Srv", "numeros", "servico", "Calcular perfil, totais e os 3 maiores consumos (Python)", 220, Y, w=160)
    d.no("P_Srv", "busca", "ia", "Buscar trechos oficiais sobre esses aparelhos (embeddings locais + pgvector)", 420, Y, w=180)
    d.no("P_Srv", "prompt", "servico", "Montar o prompt: regras + DADOS DA CASA + FONTES [n]", 620, Y, w=160)
    d.no("P_Srv", "gerar", "ia", "Gerar o texto do plano com o Gemini", 820, Y, w=160)
    d.no("P_Srv", "g_ok", "xor", "Resposta completa?", 980, Y)
    d.no("P_Srv", "citas", "servico", "Manter só as citações [n] que existem", 1130, Y, w=150)
    d.no("P_Srv", "fim", "fim_msg", "Plano enviado (texto, fontes e aviso de IA)", 1290, Y)
    d.no("P_Srv", "g_reserva", "xor", "Há modelo reserva?", 980, Y2, low_label=True)
    d.no("P_Srv", "erro", "fim_erro", "Erro 503", 1130, Y2)
    for a, b in [("ini", "numeros"), ("numeros", "busca"), ("busca", "prompt"), ("prompt", "gerar"),
                 ("gerar", "g_ok"), ("citas", "fim")]:
        d.seq(a, b)
    d.seq("g_ok", "citas", "sim", label=(1008, Y - 8))
    d.seq("g_ok", "g_reserva", "não", points=[(980, Y + 25), (980, Y2 - 25)], label=(988, Y + 52))
    d.seq("g_reserva", "erro", "não", label=(1010, Y2 - 8))
    d.seq("g_reserva", "gerar", "sim", points=[(955, Y2), (870, Y2), (870, Y + 40)],
          label=(915, Y2 - 8))
    d.item("trechos", "banco", "trechos_rag (pgvector): 45 trechos do Inmetro e da Cemig", 420, 255, "P_Srv", "busca")
    d.msg("gerar", "P_Gem", 760, "prompt", (754, 455, "end"))
    d.msg("P_Gem", "gerar", 805, "texto do plano", (811, 455, "start"))
    d.note("N_regras", "Regras do prompt: usar só os números dados; toda dica com [n]; ignorar instruções "
           "dentro das fontes; não dizer que mudar o horário reduz a conta.", 515, 230, 215, 120,
           liga=("prompt", [(620, 155), (560, 230)]))
    d.note("N_privacidade", "Vão para o Gemini só números de consumo e trechos de documentos públicos: nenhum "
           "dado pessoal.", 20, 580, 560, 45)
    return d


def offline_training():
    d = Diagram("treino_offline", 1420, 520)
    d.pool("P_Off", "Preparação de dados e treino (offline, scripts)", 10, 10, 1400, 430)
    Y = 225
    lines = {"seed": 70, "rf": 170, "rag": 280, "eda": 380}
    d.no("P_Off", "ini", "inicio", "Novos dados Inmetro / ANEEL / ANP", 100, Y)
    d.no("P_Off", "limpar", "servico", "Limpar e tratar nulos (tratar_dados_*.py, Pandas)", 240, Y, w=160)
    d.no("P_Off", "carregar", "servico", "Carregar no PostgreSQL (criar_banco.py)", 410, Y, w=140)
    d.no("P_Off", "abre", "and", "", 525, Y)
    d.no("P_Off", "seed", "servico", "Gerar 3.000 casas por regras (seed)", 650, lines["seed"], w=160)
    d.no("P_Off", "ctgan", "ml", "Treinar CTGAN e gerar 5.000 casas sintéticas", 850, lines["seed"], w=160)
    d.no("P_Off", "kmeans", "ml", "Treinar K-Means com 3 grupos (kmeans.pkl)", 1050, lines["seed"], w=160)
    d.no("P_Off", "rf", "ml", "Treinar Random Forest de geladeiras (refrigerador.pkl)", 650, lines["rf"], w=160)
    d.no("P_Off", "emb", "ia", "Gerar embeddings dos documentos (fastembed)", 650, lines["rag"], w=160)
    d.no("P_Off", "pgv", "servico", "Gravar trechos no pgvector (carregar_rag.py)", 850, lines["rag"], w=160)
    d.no("P_Off", "eda", "servico", "Gerar os gráficos da EDA (notebook)", 650, lines["eda"], w=160)
    d.no("P_Off", "junta", "and", "", 1200, Y)
    d.no("P_Off", "fim", "fim", "Dados e modelos atualizados", 1320, Y)
    d.seq("ini", "limpar")
    d.seq("limpar", "carregar")
    d.seq("carregar", "abre")
    for target in ("seed", "rf", "emb", "eda"):
        d.seq("abre", target)
    d.seq("seed", "ctgan")
    d.seq("ctgan", "kmeans")
    d.seq("emb", "pgv")
    for origin in ("kmeans", "rf", "pgv", "eda"):
        d.seq(origin, "junta")
    d.seq("junta", "fim")
    d.note("N_saidas", "Roda pelos scripts, não a cada requisição. Os .pkl guardam só números: a imagem da API "
           "não precisa do scikit-learn.", 20, 455, 640, 50)
    return d


DIAGRAMS = [("0_visao_geral", general_view), ("1_calculo", calculation), ("2_troca_payback", payback_swap),
             ("3_perfil", profile), ("4_eco_coach", eco_coach), ("5_treino_offline", offline_training)]

NAVIGATORS = [r"C:\Program Files\Google\Chrome\Application\chrome.exe",
               r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
               "google-chrome", "chromium", "microsoft-edge"]


def png_from_svg(svg_path, width, height):
    nav = next((n if Path(n).exists() else shutil.which(n) for n in NAVIGATORS
                if Path(n).exists() or shutil.which(n)), None)
    if not nav:
        return False
    subprocess.run([nav, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=2",
                    f"--window-size={width},{height}", f"--screenshot={svg_path.with_suffix('.png')}",
                    svg_path.as_uri()], check=True, capture_output=True, timeout=60)
    return True


def main():
    FOLDER.mkdir(parents=True, exist_ok=True)
    for name, factory in DIAGRAMS:
        d = factory()
        (FOLDER / f"{name}.bpmn").write_text(d.bpmn(), encoding="utf-8")
        svg = FOLDER / f"{name}.svg"
        svg.write_text(d.svg(), encoding="utf-8")
        png = png_from_svg(svg, d.width, d.height)
        print(f"{name}: .bpmn + .svg" + (" + .png" if png else ""))


if __name__ == "__main__":
    main()
