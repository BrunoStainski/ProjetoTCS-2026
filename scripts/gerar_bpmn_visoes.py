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

RAIZ = Path(__file__).resolve().parents[1]
PASTA = RAIZ / "docs" / "bpmn"

CORES = {"usuario": "#FFF4C2", "servico": "#E3EEFA", "ml": "#DFF3E6", "ia": "#EEE3FA",
         "branco": "#FFFFFF", "pool_servidor": "#F5F8FC", "pool_gemini": "#F8F3FD"}
TAREFAS = {"usuario", "servico", "ml", "ia", "envio", "sub"}
EVENTOS = {"inicio", "inicio_msg", "fim", "fim_msg", "fim_erro", "inter_msg"}
GATEWAYS = {"xor", "and"}
FONTE = "Arial, Helvetica, sans-serif"


def quebrar(texto, largura_px, px_por_letra=6.4):
    return textwrap.wrap(texto, max(6, int(largura_px / px_por_letra)), break_on_hyphens=False) or [""]


class No:
    def __init__(self, id, tipo, nome, cx, cy, pool, w=None, h=None, cor=None, rotulo_baixo=False):
        self.rotulo_baixo = rotulo_baixo
        self.id, self.tipo, self.nome, self.cx, self.cy, self.pool = id, tipo, nome, cx, cy, pool
        if tipo in TAREFAS:
            self.w = w or 150
            linhas = len(quebrar(nome, self.w - 16))
            self.h = h or max(80, linhas * 15 + 26)
            self.cor = cor or {"usuario": "usuario", "envio": "usuario", "sub": "usuario"}.get(tipo, tipo)
        elif tipo in EVENTOS:
            self.w = self.h = 36
            self.cor = "branco"
        elif tipo in GATEWAYS:
            self.w = self.h = 50
            self.cor = "branco"
        elif tipo == "banco":
            self.w, self.h, self.cor = 50, 50, "branco"
        elif tipo == "objeto":
            self.w, self.h, self.cor = 36, 48, "branco"
        self.entradas, self.saidas = [], []

    def borda(self, lado):
        return {"L": (self.cx - self.w / 2, self.cy), "R": (self.cx + self.w / 2, self.cy),
                "T": (self.cx, self.cy - self.h / 2), "B": (self.cx, self.cy + self.h / 2)}[lado]


class Pool:
    def __init__(self, id, nome, x, y, w, h, processo=True, raias=None, cor="branco"):
        self.id, self.nome, self.x, self.y, self.w, self.h = id, nome, x, y, w, h
        self.processo = f"Proc_{id}" if processo else None
        self.raias = raias or []  # [(id, nome, y, h)]
        self.cor = cor


class Diagrama:
    def __init__(self, id, largura, altura):
        self.id, self.largura, self.altura = id, largura, altura
        self.pools, self.nos, self.seqs, self.msgs, self.dados, self.notas = [], {}, [], [], [], []

    # construcao ---------------------------------------------------------------------------
    def pool(self, *a, **k):
        p = Pool(*a, **k)
        self.pools.append(p)
        return p

    def no(self, pool, id, tipo, nome, cx, cy, **k):
        n = No(id, tipo, nome, cx, cy, pool, **k)
        self.nos[id] = n
        return n

    def seq(self, a, b, nome=None, pontos=None, rotulo=None):
        a, b = self.nos[a], self.nos[b]
        pts = pontos or self._rota(a, b)
        id = f"F_{a.id}_{b.id}"
        a.saidas.append(id)
        b.entradas.append(id)
        self.seqs.append({"id": id, "a": a, "b": b, "nome": nome, "pts": pts, "rotulo": rotulo})

    def msg(self, origem, destino, x, nome, rotulo):
        """Fluxo de mensagem vertical em x. origem/destino = id de no ou de pool."""
        y1 = self._y_msg(origem, destino)
        y2 = self._y_msg(destino, origem)
        self.msgs.append({"id": f"M_{origem}_{destino}_{int(x)}", "a": origem, "b": destino,
                          "pts": [(x, y1), (x, y2)], "nome": nome, "rotulo": rotulo})

    def dado(self, id, tipo, nome, cx, cy, pool, tarefa, entrada=True, pontos=None):
        n = No(id, tipo, nome, cx, cy, pool)
        t = self.nos[tarefa]
        if pontos is None:
            if abs(n.cx - t.cx) < 1:
                pontos = [n.borda("T" if n.cy > t.cy else "B"), t.borda("B" if n.cy > t.cy else "T")]
            else:
                pontos = [n.borda("T" if n.cy > t.cy else "B"), t.borda("B" if n.cy > t.cy else "T")]
        if not entrada:
            pontos = list(reversed(pontos))
        self.dados.append({"no": n, "tarefa": t, "entrada": entrada, "pts": pontos,
                           "id": f"DA_{id}_{tarefa}"})

    def nota(self, id, texto, x, y, w, h, liga=None):
        self.notas.append({"id": id, "texto": texto, "x": x, "y": y, "w": w, "h": h, "liga": liga})

    # geometria ----------------------------------------------------------------------------
    def _rota(self, a, b):
        if abs(a.cy - b.cy) < 1:
            return [a.borda("R"), b.borda("L")]
        if a.tipo in GATEWAYS:
            ini = a.borda("B" if b.cy > a.cy else "T")
            return [ini, (a.cx, b.cy), b.borda("L")]
        if b.tipo in GATEWAYS:
            fim = b.borda("B" if a.cy > b.cy else "T")
            return [a.borda("R"), (b.cx, a.cy), fim]
        mx = (a.borda("R")[0] + b.borda("L")[0]) / 2
        return [a.borda("R"), (mx, a.cy), (mx, b.cy), b.borda("L")]

    def _caixa(self, id):
        if id in self.nos:
            n = self.nos[id]
            return n.cy - n.h / 2, n.cy + n.h / 2
        p = next(p for p in self.pools if p.id == id)
        return p.y, p.y + p.h

    def _y_msg(self, de, para):
        topo, base = self._caixa(de)
        topo2, _ = self._caixa(para)
        return base if topo2 > topo else topo

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
            ref = f' processRef="{p.processo}"' if p.processo else ""
            add(f'    <bpmn:participant id="{p.id}" name="{escape(p.nome)}"{ref} />')
        for m in self.msgs:
            add(f'    <bpmn:messageFlow id="{m["id"]}" name="{escape(m["nome"])}" '
                f'sourceRef="{m["a"]}" targetRef="{m["b"]}" />')
        for n in self.notas:
            add(f'    <bpmn:textAnnotation id="{n["id"]}"><bpmn:text>{escape(n["texto"])}</bpmn:text>'
                '</bpmn:textAnnotation>')
            if n["liga"]:
                add(f'    <bpmn:association id="A_{n["id"]}" sourceRef="{n["liga"][0]}" targetRef="{n["id"]}" />')
        add('  </bpmn:collaboration>')

        for p in self.pools:
            if not p.processo:
                continue
            add(f'  <bpmn:process id="{p.processo}" isExecutable="false">')
            nos = [n for n in self.nos.values() if n.pool == p.id]
            if p.raias:
                add(f'    <bpmn:laneSet id="LS_{p.id}">')
                for rid, rnome, ry, rh in p.raias:
                    add(f'      <bpmn:lane id="{rid}" name="{escape(rnome)}">')
                    for n in nos:
                        if ry <= n.cy < ry + rh:
                            add(f'        <bpmn:flowNodeRef>{n.id}</bpmn:flowNodeRef>')
                    add('      </bpmn:lane>')
                add('    </bpmn:laneSet>')
            for n in nos:
                add("    " + self._xml_no(n))
            for s in self.seqs:
                if s["a"].pool == p.id:
                    nome = f' name="{escape(s["nome"])}"' if s["nome"] else ""
                    add(f'    <bpmn:sequenceFlow id="{s["id"]}"{nome} sourceRef="{s["a"].id}" targetRef="{s["b"].id}" />')
            for d in self.dados:
                if d["no"].pool != p.id:
                    continue
                n = d["no"]
                if n.tipo == "banco":
                    add(f'    <bpmn:dataStoreReference id="{n.id}" name="{escape(n.nome)}" />')
                elif not any(x["no"].id == n.id for x in self.dados[:self.dados.index(d)]):
                    add(f'    <bpmn:dataObjectReference id="{n.id}" name="{escape(n.nome)}" dataObjectRef="DO_{n.id}" />')
                    add(f'    <bpmn:dataObject id="DO_{n.id}" />')
            add('  </bpmn:process>')

        add(f'  <bpmndi:BPMNDiagram id="Diag_{self.id}">')
        add(f'    <bpmndi:BPMNPlane id="Plane_{self.id}" bpmnElement="Colab_{self.id}">')
        for p in self.pools:
            add(self._shape(p.id, p.x, p.y, p.w, p.h, CORES[p.cor], horizontal=True))
            for rid, _, ry, rh in p.raias:
                add(self._shape(rid, p.x + 30, ry, p.w - 30, rh, None, horizontal=True))
        vistos = set()
        for n in list(self.nos.values()) + [d["no"] for d in self.dados]:
            if n.id in vistos:
                continue
            vistos.add(n.id)
            extra = ' isExpanded="false"' if n.tipo == "sub" else ""
            rotulo = None
            if n.tipo in EVENTOS:
                rotulo = (n.cx - 60, n.cy + n.h / 2 + 4, 120, 40)
            elif n.tipo in GATEWAYS and n.nome:
                rotulo = (n.cx - 70, n.cy + n.h / 2 + 4 if n.rotulo_baixo else n.cy - n.h / 2 - 40, 140, 34)
            elif n.tipo in ("banco", "objeto"):
                rotulo = (n.cx - 60, n.cy + n.h / 2 + 4, 120, 40)
            add(self._shape(n.id, n.cx - n.w / 2, n.cy - n.h / 2, n.w, n.h,
                            CORES[n.cor] if n.cor != "branco" else None, extra=extra, rotulo=rotulo))
        for nota in self.notas:
            add(self._shape(nota["id"], nota["x"], nota["y"], nota["w"], nota["h"], None))
        for s in self.seqs:
            rotulo = None
            if s["nome"]:
                x, y = s["rotulo"] or (s["pts"][0][0] + 8, s["pts"][0][1] - 7)
                rotulo = (x, y - 12, max(30, len(s["nome"]) * 6.5), 16)
            add(self._edge(s["id"], s["pts"], rotulo))
        for m in self.msgs:
            (x, y1), (_, y2) = m["pts"]
            lx, ly, ancora = m["rotulo"]
            add(self._edge(m["id"], m["pts"], (lx - (130 if ancora == "end" else 0), ly - 12, 130, 30)))
        for d in self.dados:
            add(self._edge(d["id"], d["pts"]))
        for nota in self.notas:
            if nota["liga"]:
                add(self._edge(f'A_{nota["id"]}', nota["liga"][1]))
        add('    </bpmndi:BPMNPlane>')
        add('  </bpmndi:BPMNDiagram>')
        add('</bpmn:definitions>')
        xml = "\n".join(X)
        # associacoes de dados ficam dentro das tarefas (padrao do Camunda)
        for d in self.dados:
            t, n = d["tarefa"], d["no"]
            if d["entrada"]:
                trecho = (f'<bpmn:property id="P_{d["id"]}" name="__targetRef_placeholder" />'
                          f'<bpmn:dataInputAssociation id="{d["id"]}"><bpmn:sourceRef>{n.id}</bpmn:sourceRef>'
                          f'<bpmn:targetRef>P_{d["id"]}</bpmn:targetRef></bpmn:dataInputAssociation>')
            else:
                trecho = (f'<bpmn:dataOutputAssociation id="{d["id"]}"><bpmn:targetRef>{n.id}</bpmn:targetRef>'
                          '</bpmn:dataOutputAssociation>')
            xml = xml.replace(f'<!--DADOS_{t.id}-->', trecho + f'<!--DADOS_{t.id}-->', 1)
        return re.sub(r"<!--DADOS_[^>]*-->", "", xml)

    def _xml_no(self, n):
        tag = {"usuario": "userTask", "servico": "serviceTask", "ml": "serviceTask", "ia": "serviceTask",
               "envio": "sendTask", "sub": "subProcess", "inicio": "startEvent", "inicio_msg": "startEvent",
               "fim": "endEvent", "fim_msg": "endEvent", "fim_erro": "endEvent",
               "inter_msg": "intermediateCatchEvent", "xor": "exclusiveGateway", "and": "parallelGateway"}[n.tipo]
        nome = f' name="{escape(n.nome)}"' if n.nome else ""
        corpo = "".join(f"<bpmn:incoming>{f}</bpmn:incoming>" for f in n.entradas)
        corpo += "".join(f"<bpmn:outgoing>{f}</bpmn:outgoing>" for f in n.saidas)
        if n.tipo in TAREFAS:
            corpo += f"<!--DADOS_{n.id}-->"
        if n.tipo in ("inicio_msg", "fim_msg", "inter_msg"):
            corpo += f'<bpmn:messageEventDefinition id="MED_{n.id}" />'
        if n.tipo == "fim_erro":
            corpo += f'<bpmn:errorEventDefinition id="EED_{n.id}" />'
        return f'<bpmn:{tag} id="{n.id}"{nome}>{corpo}</bpmn:{tag}>'

    @staticmethod
    def _shape(id, x, y, w, h, cor, horizontal=False, extra="", rotulo=None):
        hz = ' isHorizontal="true"' if horizontal else ""
        c = f' color:background-color="{cor}" color:border-color="#000000"' if cor else ""
        r = ""
        if rotulo:
            r = (f'<bpmndi:BPMNLabel><dc:Bounds x="{rotulo[0]:.0f}" y="{rotulo[1]:.0f}" '
                 f'width="{rotulo[2]:.0f}" height="{rotulo[3]:.0f}" /></bpmndi:BPMNLabel>')
        return (f'      <bpmndi:BPMNShape id="S_{id}" bpmnElement="{id}"{hz}{extra}{c}>'
                f'<dc:Bounds x="{x:.0f}" y="{y:.0f}" width="{w:.0f}" height="{h:.0f}" />{r}</bpmndi:BPMNShape>')

    @staticmethod
    def _edge(id, pts, rotulo=None):
        wp = "".join(f'<di:waypoint x="{x:.0f}" y="{y:.0f}" />' for x, y in pts)
        r = ""
        if rotulo:
            r = (f'<bpmndi:BPMNLabel><dc:Bounds x="{rotulo[0]:.0f}" y="{rotulo[1]:.0f}" '
                 f'width="{rotulo[2]:.0f}" height="{rotulo[3]:.0f}" /></bpmndi:BPMNLabel>')
        return f'      <bpmndi:BPMNEdge id="E_{id}" bpmnElement="{id}">{wp}{r}</bpmndi:BPMNEdge>'

    # SVG ----------------------------------------------------------------------------------
    def svg(self):
        S = []
        add = S.append
        add(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {self.largura} {self.altura}" '
            f'width="{self.largura}" height="{self.altura}" font-family="{FONTE}" font-size="12">')
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
        add(f'<rect width="{self.largura}" height="{self.altura}" fill="#fff"/>')
        for p in self.pools:
            add(self._svg_pool(p))
        for n in self.notas:
            add(self._svg_nota(n))
        for d in self.dados:
            add(self._linha(d["pts"], 'stroke-dasharray="2 3" stroke-width="1.3"', fim="seta_dado"))
        for s in self.seqs:
            add(self._linha(s["pts"], 'stroke-width="1.6"', fim="seta"))
            if s["nome"]:
                x, y = s["rotulo"] or (s["pts"][0][0] + 8, s["pts"][0][1] - 7)
                add(self._texto(s["nome"], x, y, "start", tamanho=11))
        for m in self.msgs:
            add(self._linha(m["pts"], 'stroke-dasharray="6 4" stroke-width="1.4"', ini="bola_msg", fim="seta_msg"))
            lx, ly, ancora = m["rotulo"]
            for i, linha in enumerate(quebrar(m["nome"], 150)):
                add(self._texto(linha, lx, ly + i * 13, ancora, tamanho=11, estilo="italic"))
        vistos = set()
        for d in self.dados:
            if d["no"].id not in vistos:
                vistos.add(d["no"].id)
                add(self._svg_no(d["no"]))
        for n in self.nos.values():
            add(self._svg_no(n))
        add('</svg>')
        return "\n".join(S)

    @staticmethod
    def _texto(t, x, y, ancora="middle", tamanho=12, peso="normal", estilo="normal"):
        return (f'<text x="{x:.1f}" y="{y:.1f}" text-anchor="{ancora}" font-size="{tamanho}" '
                f'font-weight="{peso}" font-style="{estilo}">{escape(t)}</text>')

    @staticmethod
    def _linha(pts, estilo, ini=None, fim=None):
        p = " ".join(f"{x:.1f},{y:.1f}" for x, y in pts)
        m = (f' marker-start="url(#{ini})"' if ini else "") + (f' marker-end="url(#{fim})"' if fim else "")
        return f'<polyline points="{p}" fill="none" stroke="#000" {estilo}{m}/>'

    def _svg_pool(self, p):
        cor = CORES[p.cor]
        out = [f'<rect x="{p.x}" y="{p.y}" width="{p.w}" height="{p.h}" fill="{cor}" stroke="#000" stroke-width="1.5"/>']
        if p.processo:
            out.append(f'<line x1="{p.x + 30}" y1="{p.y}" x2="{p.x + 30}" y2="{p.y + p.h}" stroke="#000" stroke-width="1.5"/>')
            cx, cy = p.x + 19, p.y + p.h / 2
            out.append(f'<text transform="translate({cx},{cy}) rotate(-90)" text-anchor="middle" '
                       f'font-size="13" font-weight="bold">{escape(p.nome)}</text>')
            for _, rnome, ry, rh in p.raias:
                out.append(f'<rect x="{p.x + 30}" y="{ry}" width="{p.w - 30}" height="{rh}" fill="none" stroke="#000" stroke-width="1"/>')
                out.append(f'<line x1="{p.x + 58}" y1="{ry}" x2="{p.x + 58}" y2="{ry + rh}" stroke="#000" stroke-width="1"/>')
                out.append(f'<text transform="translate({p.x + 48},{ry + rh / 2}) rotate(-90)" '
                           f'text-anchor="middle" font-size="12">{escape(rnome)}</text>')
        else:  # pool caixa-preta: nome no centro
            out.append(self._texto(p.nome, p.x + p.w / 2, p.y + p.h / 2 + 5, tamanho=14, peso="bold"))
        return "\n".join(out)

    def _svg_nota(self, n):
        x, y, w, h = n["x"], n["y"], n["w"], n["h"]
        out = [f'<path d="M{x + 12},{y} L{x},{y} L{x},{y + h} L{x + 12},{y + h}" fill="none" stroke="#000" stroke-width="1.3"/>']
        for i, linha in enumerate(quebrar(n["texto"], w - 12, 6.0)):
            out.append(self._texto(linha, x + 8, y + 16 + i * 14, "start", tamanho=11.5))
        if n["liga"]:
            out.append(self._linha(n["liga"][1], 'stroke-dasharray="2 3" stroke-width="1.2"'))
        return "\n".join(out)

    def _svg_no(self, n):
        x, y, w, h, cx, cy = n.cx - n.w / 2, n.cy - n.h / 2, n.w, n.h, n.cx, n.cy
        out = []
        if n.tipo in TAREFAS:
            out.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="10" fill="{CORES[n.cor]}" stroke="#000" stroke-width="1.8"/>')
            linhas = quebrar(n.nome, w - 16)
            y0 = cy - (len(linhas) - 1) * 15 / 2 + 4 + (4 if n.tipo != "sub" else -2)
            for i, linha in enumerate(linhas):
                out.append(self._texto(linha, cx, y0 + i * 15))
            out.append(self._icone(n.tipo, x, y, w, h))
        elif n.tipo in EVENTOS:
            borda = {"fim": 4, "fim_msg": 4, "fim_erro": 4}.get(n.tipo, 1.8)
            out.append(f'<circle cx="{cx}" cy="{cy}" r="18" fill="#fff" stroke="#000" stroke-width="{borda}"/>')
            if n.tipo == "inter_msg":
                out.append(f'<circle cx="{cx}" cy="{cy}" r="14.5" fill="none" stroke="#000" stroke-width="1.3"/>')
            if n.tipo in ("inicio_msg", "inter_msg", "fim_msg"):
                cheio = n.tipo == "fim_msg"
                out.append(f'<rect x="{cx - 9}" y="{cy - 6}" width="18" height="12" fill="{"#000" if cheio else "#fff"}" stroke="#000" stroke-width="1.2"/>')
                out.append(f'<polyline points="{cx - 9},{cy - 6} {cx},{cy + 1} {cx + 9},{cy - 6}" fill="none" stroke="{"#fff" if cheio else "#000"}" stroke-width="1.2"/>')
            if n.tipo == "fim_erro":
                out.append(f'<polygon points="{cx - 8},{cy + 8} {cx - 3},{cy - 7} {cx + 2},{cy + 1} {cx + 8},{cy - 8} {cx + 3},{cy + 7} {cx - 2},{cy - 1}" fill="#000"/>')
            for i, linha in enumerate(quebrar(n.nome, 112)):
                out.append(self._texto(linha, cx, cy + 32 + i * 13, tamanho=11))
        elif n.tipo in GATEWAYS:
            out.append(f'<polygon points="{cx},{cy - 25} {cx + 25},{cy} {cx},{cy + 25} {cx - 25},{cy}" fill="#fff" stroke="#000" stroke-width="1.8"/>')
            if n.tipo == "xor":
                out.append(f'<path d="M{cx - 8},{cy - 8} L{cx + 8},{cy + 8} M{cx + 8},{cy - 8} L{cx - 8},{cy + 8}" stroke="#000" stroke-width="4"/>')
            else:
                out.append(f'<path d="M{cx - 11},{cy} L{cx + 11},{cy} M{cx},{cy - 11} L{cx},{cy + 11}" stroke="#000" stroke-width="4"/>')
            if n.nome:
                linhas = quebrar(n.nome, 130)
                for i, linha in enumerate(linhas):
                    y = cy + 40 + i * 13 if n.rotulo_baixo else cy - 32 - (len(linhas) - 1 - i) * 13
                    out.append(self._texto(linha, cx, y, tamanho=11))
        elif n.tipo == "banco":
            out.append(f'<path d="M{x},{y + 8} L{x},{y + h - 8} A{w / 2},8 0 0 0 {x + w},{y + h - 8} L{x + w},{y + 8}" fill="#fff" stroke="#000" stroke-width="1.6"/>')
            out.append(f'<ellipse cx="{cx}" cy="{y + 8}" rx="{w / 2}" ry="8" fill="#fff" stroke="#000" stroke-width="1.6"/>')
            out.append(f'<path d="M{x},{y + 15} A{w / 2},8 0 0 0 {x + w},{y + 15}" fill="none" stroke="#000" stroke-width="1.2"/>')
            for i, linha in enumerate(quebrar(n.nome, 130)):
                out.append(self._texto(linha, cx, y + h + 14 + i * 13, tamanho=11))
        elif n.tipo == "objeto":
            out.append(f'<path d="M{x},{y} L{x + w - 10},{y} L{x + w},{y + 10} L{x + w},{y + h} L{x},{y + h} Z" fill="#fff" stroke="#000" stroke-width="1.6"/>')
            out.append(f'<path d="M{x + w - 10},{y} L{x + w - 10},{y + 10} L{x + w},{y + 10}" fill="none" stroke="#000" stroke-width="1.2"/>')
            for i, linha in enumerate(quebrar(n.nome, 130)):
                out.append(self._texto(linha, cx, y + h + 14 + i * 13, tamanho=11))
        return "\n".join(out)

    @staticmethod
    def _icone(tipo, x, y, w, h):
        if tipo == "usuario":
            return (f'<circle cx="{x + 14}" cy="{y + 11}" r="4.5" fill="#fff" stroke="#000" stroke-width="1.2"/>'
                    f'<path d="M{x + 6},{y + 25} Q{x + 6},{y + 16} {x + 14},{y + 16} Q{x + 22},{y + 16} {x + 22},{y + 25} Z" '
                    'fill="#fff" stroke="#000" stroke-width="1.2"/>')
        if tipo in ("servico", "ml", "ia"):
            return (f'<circle cx="{x + 15}" cy="{y + 15}" r="6.5" fill="none" stroke="#000" stroke-width="3.6" stroke-dasharray="2.6 1.9"/>'
                    f'<circle cx="{x + 15}" cy="{y + 15}" r="4.6" fill="#fff" stroke="#000" stroke-width="1"/>'
                    f'<circle cx="{x + 15}" cy="{y + 15}" r="1.8" fill="none" stroke="#000" stroke-width="1"/>')
        if tipo == "envio":
            return (f'<rect x="{x + 7}" y="{y + 8}" width="18" height="12" fill="#000"/>'
                    f'<polyline points="{x + 7},{y + 8} {x + 16},{y + 15} {x + 25},{y + 8}" fill="none" stroke="#fff" stroke-width="1.2"/>')
        if tipo == "sub":
            bx, by = x + w / 2 - 7, y + h - 17
            return (f'<rect x="{bx}" y="{by}" width="14" height="14" fill="#fff" stroke="#000" stroke-width="1.2"/>'
                    f'<path d="M{bx + 3},{by + 7} L{bx + 11},{by + 7} M{bx + 7},{by + 3} L{bx + 7},{by + 11}" stroke="#000" stroke-width="1.6"/>')
        return ""


# Diagramas ---------------------------------------------------------------------------------

def visao_geral():
    d = Diagrama("visao_geral", 1520, 700)
    d.pool("P_App", "Usuário (app iamp)", 10, 10, 1500, 300)
    d.pool("P_Srv", "Servidor iamp (API FastAPI + PostgreSQL + modelos de ML)", 10, 430, 1500, 70,
           processo=False, cor="pool_servidor")
    d.pool("P_Gem", "Gemini API (Google, serviço externo)", 860, 620, 650, 60, processo=False, cor="pool_gemini")
    Y, Y2 = 120, 225
    d.no("P_App", "ini", "inicio", "Quer reduzir a conta de luz", 100, Y)
    d.no("P_App", "calc", "sub", "Calcular consumo e custo de cada aparelho", 240, Y, w=160)
    d.no("P_App", "g_troca", "xor", "Ver opções de troca?", 400, Y)
    d.no("P_App", "troca", "sub", "Avaliar troca e payback", 540, Y2, w=160)
    d.no("P_App", "g_junta", "xor", "", 680, Y)
    d.no("P_App", "g_mais", "xor", "Mais aparelhos?", 780, Y, rotulo_baixo=True)
    d.no("P_App", "perfil", "sub", "Ver o perfil de consumo da casa", 930, Y, w=160)
    d.no("P_App", "eco", "sub", "Pedir o plano ao Eco-Coach", 1120, Y, w=160)
    d.no("P_App", "ler", "usuario", "Ler o plano e conferir as fontes [n]", 1300, Y, w=150)
    d.no("P_App", "fim", "fim", "Plano de economia pronto", 1440, Y)
    d.seq("ini", "calc")
    d.seq("calc", "g_troca")
    d.seq("g_troca", "troca", "sim", rotulo=(406, Y + 48))
    d.seq("g_troca", "g_junta", "não", rotulo=(470, Y - 8))
    d.seq("troca", "g_junta")
    d.seq("g_junta", "g_mais")
    d.seq("g_mais", "calc", "sim", pontos=[(780, Y - 25), (780, 38), (240, 38), (240, Y - 40)], rotulo=(788, 52))
    d.seq("g_mais", "perfil", "não", rotulo=(812, Y - 8))
    d.seq("perfil", "eco")
    d.seq("eco", "ler")
    d.seq("ler", "fim")
    topo_srv = 430
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
    d.nota("N_privacidade", "O Gemini recebe só números de consumo e trechos de documentos públicos: nenhum dado "
           "pessoal sai do iamp.", 380, 610, 400, 50)
    d.nota("N_legenda", "[+] = subprocesso detalhado nas próximas páginas. Linhas tracejadas = mensagens "
           "(chamadas à API).", 20, 520, 560, 50)
    return d


def calculo():
    d = Diagrama("calculo", 1300, 420)
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
    d.seq("g_valido", "erro", "não", rotulo=(338, Y + 50))
    d.seq("g_valido", "g_catalogo", "sim", rotulo=(360, Y - 8))
    d.seq("g_catalogo", "regras", "sim", rotulo=(470, Y - 8))
    d.seq("g_catalogo", "estimar", "não", rotulo=(448, Y + 50))
    d.seq("regras", "g_junta")
    d.seq("estimar", "g_junta")
    d.seq("g_junta", "tarifa")
    d.seq("tarifa", "registrar")
    d.seq("registrar", "fim")
    d.dado("refri", "objeto", "refrigerador.pkl", 760, 335, "P_Srv", "estimar",
           pontos=[(742, 335), (680, 285)])
    d.dado("db", "banco", "PostgreSQL (aparelhos, tarifas, consultas)", 990, 270, "P_Srv", "tarifa",
           pontos=[(975, 245), (920, 160)])
    d.dado("db", "banco", "PostgreSQL (aparelhos, tarifas, consultas)", 990, 270, "P_Srv", "registrar",
           entrada=False, pontos=[(1005, 245), (1060, 160)])
    d.nota("N_impostos", "Valores sem ICMS, PIS/COFINS, bandeira e iluminação pública: o app sempre avisa.",
           1080, 230, 190, 70)
    return d


def troca_payback():
    d = Diagrama("troca_payback", 1300, 420)
    d.pool("P_Srv", "Servidor iamp: troca e payback", 10, 10, 1280, 400,
           raias=[("L_sug", "POST /sugestoes", 10, 180), ("L_comp", "POST /comparar", 190, 220)])
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
    d.seq("g_preco", "c_payback", "sim", rotulo=(460, Y2 - 8))
    d.seq("g_preco", "g_junta", "não", pontos=[(430, Y2 + 25), (430, 375), (730, 375), (730, Y2 + 25)],
          rotulo=(438, 368))
    d.seq("c_payback", "g_junta")
    d.seq("g_junta", "c_fim")
    d.nota("N_payback", "Payback simples: sem juros, sem revenda do aparelho antigo e sem reajuste de tarifa. "
           "O catálogo não tem preços: o usuário digita o valor.", 930, 255, 330, 70)
    return d


def perfil():
    d = Diagrama("perfil", 1300, 300)
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
    d.seq("g_valida", "erro", "não", rotulo=(208, Y + 50))
    d.seq("g_valida", "fracoes", "sim", rotulo=(232, Y - 8))
    d.seq("fracoes", "escala")
    d.seq("escala", "centroide")
    d.seq("centroide", "mediana")
    d.seq("mediana", "fim")
    d.dado("kmeans", "objeto", "kmeans.pkl (só números)", 675, 225, "P_Srv", "escala", pontos=[(665, 201), (600, 160)])
    d.dado("kmeans", "objeto", "kmeans.pkl (só números)", 675, 225, "P_Srv", "centroide", pontos=[(685, 201), (750, 160)])
    d.nota("N_sintetico", "Não usa o banco nem grava nada. Treinado com 5.000 casas sintéticas (CTGAN): o perfil é demonstrativo.",
           900, 195, 330, 60)
    return d


def eco_coach():
    d = Diagrama("eco_coach", 1460, 640)
    d.pool("P_Srv", "Servidor iamp: POST /eco-coach", 10, 10, 1440, 380)
    d.pool("P_Gem", "Gemini API (Google, serviço externo)", 10, 500, 1440, 60, processo=False, cor="pool_gemini")
    Y, Y2 = 115, 275
    d.no("P_Srv", "ini", "inicio_msg", "Casa recebida (consumos, custos e trocas)", 95, Y)
    d.no("P_Srv", "numeros", "servico", "Calcular perfil, totais e os 3 maiores consumos (Python)", 220, Y, w=160)
    d.no("P_Srv", "busca", "ia", "Buscar trechos oficiais sobre esses aparelhos (embeddings locais + pgvector)", 420, Y, w=180)
    d.no("P_Srv", "prompt", "servico", "Montar o prompt: regras + DADOS DA CASA + FONTES [n]", 620, Y, w=160)
    d.no("P_Srv", "gerar", "ia", "Gerar o texto do plano com o Gemini", 820, Y, w=160)
    d.no("P_Srv", "g_ok", "xor", "Resposta completa?", 980, Y)
    d.no("P_Srv", "citas", "servico", "Manter só as citações [n] que existem", 1130, Y, w=150)
    d.no("P_Srv", "fim", "fim_msg", "Plano enviado (texto, fontes e aviso de IA)", 1290, Y)
    d.no("P_Srv", "g_reserva", "xor", "Há modelo reserva?", 980, Y2, rotulo_baixo=True)
    d.no("P_Srv", "erro", "fim_erro", "Erro 503", 1130, Y2)
    for a, b in [("ini", "numeros"), ("numeros", "busca"), ("busca", "prompt"), ("prompt", "gerar"),
                 ("gerar", "g_ok"), ("citas", "fim")]:
        d.seq(a, b)
    d.seq("g_ok", "citas", "sim", rotulo=(1008, Y - 8))
    d.seq("g_ok", "g_reserva", "não", pontos=[(980, Y + 25), (980, Y2 - 25)], rotulo=(988, Y + 52))
    d.seq("g_reserva", "erro", "não", rotulo=(1010, Y2 - 8))
    d.seq("g_reserva", "gerar", "sim", pontos=[(955, Y2), (870, Y2), (870, Y + 40)],
          rotulo=(915, Y2 - 8))
    d.dado("trechos", "banco", "trechos_rag (pgvector): 45 trechos do Inmetro e da Cemig", 420, 255, "P_Srv", "busca")
    d.msg("gerar", "P_Gem", 760, "prompt", (754, 455, "end"))
    d.msg("P_Gem", "gerar", 805, "texto do plano", (811, 455, "start"))
    d.nota("N_regras", "Regras do prompt: usar só os números dados; toda dica com [n]; ignorar instruções "
           "dentro das fontes; não dizer que mudar o horário reduz a conta.", 515, 230, 215, 120,
           liga=("prompt", [(620, 155), (560, 230)]))
    d.nota("N_privacidade", "Vão para o Gemini só números de consumo e trechos de documentos públicos: nenhum "
           "dado pessoal.", 20, 580, 560, 45)
    return d


def treino_offline():
    d = Diagrama("treino_offline", 1420, 520)
    d.pool("P_Off", "Preparação de dados e treino (offline, scripts)", 10, 10, 1400, 430)
    Y = 225
    linhas = {"seed": 70, "rf": 170, "rag": 280, "eda": 380}
    d.no("P_Off", "ini", "inicio", "Novos dados Inmetro / ANEEL / ANP", 100, Y)
    d.no("P_Off", "limpar", "servico", "Limpar e tratar nulos (tratar_dados_*.py, Pandas)", 240, Y, w=160)
    d.no("P_Off", "carregar", "servico", "Carregar no PostgreSQL (criar_banco.py)", 410, Y, w=140)
    d.no("P_Off", "abre", "and", "", 525, Y)
    d.no("P_Off", "seed", "servico", "Gerar 3.000 casas por regras (seed)", 650, linhas["seed"], w=160)
    d.no("P_Off", "ctgan", "ml", "Treinar CTGAN e gerar 5.000 casas sintéticas", 850, linhas["seed"], w=160)
    d.no("P_Off", "kmeans", "ml", "Treinar K-Means com 3 grupos (kmeans.pkl)", 1050, linhas["seed"], w=160)
    d.no("P_Off", "rf", "ml", "Treinar Random Forest de geladeiras (refrigerador.pkl)", 650, linhas["rf"], w=160)
    d.no("P_Off", "emb", "ia", "Gerar embeddings dos documentos (fastembed)", 650, linhas["rag"], w=160)
    d.no("P_Off", "pgv", "servico", "Gravar trechos no pgvector (carregar_rag.py)", 850, linhas["rag"], w=160)
    d.no("P_Off", "eda", "servico", "Gerar os gráficos da EDA (notebook)", 650, linhas["eda"], w=160)
    d.no("P_Off", "junta", "and", "", 1200, Y)
    d.no("P_Off", "fim", "fim", "Dados e modelos atualizados", 1320, Y)
    d.seq("ini", "limpar")
    d.seq("limpar", "carregar")
    d.seq("carregar", "abre")
    for alvo in ("seed", "rf", "emb", "eda"):
        d.seq("abre", alvo)
    d.seq("seed", "ctgan")
    d.seq("ctgan", "kmeans")
    d.seq("emb", "pgv")
    for origem in ("kmeans", "rf", "pgv", "eda"):
        d.seq(origem, "junta")
    d.seq("junta", "fim")
    d.nota("N_saidas", "Roda pelos scripts, não a cada requisição. Os .pkl guardam só números: a imagem da API "
           "não precisa do scikit-learn.", 20, 455, 640, 50)
    return d


DIAGRAMAS = [("0_visao_geral", visao_geral), ("1_calculo", calculo), ("2_troca_payback", troca_payback),
             ("3_perfil", perfil), ("4_eco_coach", eco_coach), ("5_treino_offline", treino_offline)]

NAVEGADORES = [r"C:\Program Files\Google\Chrome\Application\chrome.exe",
               r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
               "google-chrome", "chromium", "microsoft-edge"]


def png_do_svg(svg_path, largura, altura):
    nav = next((n if Path(n).exists() else shutil.which(n) for n in NAVEGADORES
                if Path(n).exists() or shutil.which(n)), None)
    if not nav:
        return False
    subprocess.run([nav, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=2",
                    f"--window-size={largura},{altura}", f"--screenshot={svg_path.with_suffix('.png')}",
                    svg_path.as_uri()], check=True, capture_output=True, timeout=60)
    return True


def main():
    PASTA.mkdir(parents=True, exist_ok=True)
    for nome, fabrica in DIAGRAMAS:
        d = fabrica()
        (PASTA / f"{nome}.bpmn").write_text(d.bpmn(), encoding="utf-8")
        svg = PASTA / f"{nome}.svg"
        svg.write_text(d.svg(), encoding="utf-8")
        png = png_do_svg(svg, d.largura, d.altura)
        print(f"{nome}: .bpmn + .svg" + (" + .png" if png else ""))


if __name__ == "__main__":
    main()
