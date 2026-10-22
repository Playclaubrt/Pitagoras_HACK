#!/usr/bin/env python3
"""Seleciona trechos textuais do relatorio autenticado sem gravar o HTML."""
from html.parser import HTMLParser
import sys

modo = sys.argv[1]
serie = sys.argv[2] if len(sys.argv) > 2 else ""

class Relatorio(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.top = []
        self.turmas = {}
        self.atual = None
        self.ignore = 0

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag in ("script", "style"):
            self.ignore += 1
        if tag == "section" and attrs.get("id"):
            self.atual = attrs["id"]
            self.turmas.setdefault(self.atual, [])

    def handle_endtag(self, tag):
        if tag in ("script", "style") and self.ignore:
            self.ignore -= 1
        if tag == "section":
            self.atual = None

    def handle_data(self, data):
        if self.ignore:
            return
        text = " ".join(data.split())
        if text:
            (self.turmas[self.atual] if self.atual else self.top).append(text)

page = Relatorio()
page.feed(sys.stdin.read())
top = "\n".join(page.top)

if modo == "1":
    cut = top.find("Nota da semana por turma")
    print(top[:cut] if cut >= 0 else top)
elif modo == "2":
    start = top.find("Nota da semana por turma")
    end = top.find("Adesão por turma", start + 1)
    print(top[start:end if end >= 0 else None] if start >= 0 else "Secao de nota semanal nao encontrada.")
elif modo == "3":
    start = top.find("Adesão por turma")
    print(top[start:] if start >= 0 else "Secao de adesao nao encontrada.")
elif modo == "4":
    content = page.turmas.get(serie, [])
    print("\n".join(content) if content else "Nao encontrei essa serie no relatorio.")
else:
    print(top)
    for serie_id in ("6ano", "7ano", "8ano", "9ano", "1serie", "2serie", "3serie"):
        print("\n".join(page.turmas.get(serie_id, [])))
