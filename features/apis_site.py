#!/usr/bin/env python3
"""Inventaria links, formularios e rotas referenciadas em paginas publicas."""
import html
import os
import re
import subprocess
import sys
import tempfile
from collections import deque
from urllib.parse import urljoin, urlsplit, urlunsplit

saida = sys.argv[1]
base = "https://www.lugaroriginal.com"
hosts = {"www.lugaroriginal.com", "lugaroriginal.com"}
max_paginas = 100


def curl(url):
    p = subprocess.run(
        ["curl", "--http1.1", "-fsSL", "--max-time", "25", url],
        capture_output=True, text=True, errors="replace", check=True,
    )
    return p.stdout


def path_url(url):
    p = urlsplit(url)
    return urlunsplit((p.scheme, p.netloc, p.path or "/", p.query, ""))


def interno(url):
    p = urlsplit(url)
    return p.scheme in ("http", "https") and p.hostname in hosts

# Obedece o robots.txt: /api/ e descartado do crawler. A busca por rotas
# e feita nas referencias de paginas/bundles publicos, sem sondar endpoints.
robots = curl(base + "/robots.txt")
blocked = []
for line in robots.splitlines():
    m = re.match(r"\s*Disallow:\s*(\S+)", line, re.I)
    if m:
        blocked.append(m.group(1))

sitemap = curl("https://lugaroriginal.com/sitemap.xml")
sitemap_urls = re.findall(r"<loc>([^<]+)</loc>", sitemap)
queue = deque(sitemap_urls)
queue.extend((base + "/leitura", base + "/parceiros/pitagoras"))
visitadas = set()
paginas_html = set()
links_publicos = set()
bundles = set()
formularios = set()

while queue and len(visitadas) < max_paginas:
    url = path_url(queue.popleft())
    p = urlsplit(url)
    if not interno(url) or any(p.path.startswith(x) for x in blocked):
        continue
    if re.search(r"\.(?:png|jpe?g|gif|svg|webp|ico|pdf|woff2?|ttf|css|xml)$", p.path, re.I):
        continue
    if url in visitadas:
        continue
    visitadas.add(url)
    try:
        corpo = curl(url)
    except subprocess.CalledProcessError:
        continue
    if not re.search(r"<html|<!doctype", corpo[:2000], re.I):
        continue
    paginas_html.add(p.path)

    for href in re.findall(r"\bhref=[\"']([^\"']+)", corpo, re.I):
        destino = path_url(urljoin(url, html.unescape(href)))
        if not interno(destino):
            continue
        dp = urlsplit(destino)
        if any(dp.path.startswith(x) for x in blocked):
            continue
        if dp.path.startswith("/_next/") or dp.path in ("/icon", "/apple-icon") or re.search(r"\.(?:png|jpe?g|gif|svg|webp|ico|pdf|woff2?|ttf|css|xml)$", dp.path, re.I):
            continue
        links_publicos.add(dp.path + (("?" + dp.query) if dp.query else ""))
        queue.append(destino)

    for src in re.findall(r"<script\b[^>]*\bsrc=[\"']([^\"']+)", corpo, re.I):
        asset = urljoin(url, html.unescape(src))
        if interno(asset):
            bundles.add(asset)

    for form in re.findall(r"<form\b[^>]*>[\s\S]*?</form>", corpo, re.I):
        action = re.search(r"\baction=[\"']([^\"']+)", form, re.I)
        method = re.search(r"\bmethod=[\"']([^\"']+)", form, re.I)
        fields = sorted(set(re.findall(r"<(?:input|select|textarea|button)\b[^>]*\bname=[\"']([^\"']+)", form, re.I)))
        destino = path_url(urljoin(url, html.unescape(action.group(1)))) if action else url
        if interno(destino):
            tipo = method.group(1).upper() if method else "JS/default GET"
            formularios.add((urlsplit(url).path, tipo, urlsplit(destino).path, ", ".join(fields) or "campos sem nome"))

rotas = {}
comportamentos = set()
for bundle in sorted(bundles):
    try:
        js = curl(bundle)
    except subprocess.CalledProcessError:
        continue
    if re.search(r'localStorage\.getItem\(["\']leitura:token["\']\)', js) and re.search(r'location\.replace\(["\']/leitura/', js):
        comportamentos.add("GET /leitura le a chave localStorage `leitura:token` e redireciona para /leitura/{token}; nenhum valor de token e coletado.")
    endpoints = set(re.findall(r"[\"'`]((?:/api/)[A-Za-z0-9_./?&=${}-]*)[\"'`]", js))
    for endpoint in endpoints:
        endpoint = endpoint.split("?", 1)[0]
        contexto = " ".join(js[max(0, m.start() - 300):m.start() + 900] for m in list(re.finditer(re.escape(endpoint), js))[:3])
        methods = sorted(set(x.upper() for x in re.findall(r"\bmethod\s*:\s*[\"'](GET|POST|PUT|PATCH|DELETE)[\"']", contexto, re.I)))
        rotas.setdefault(endpoint, {"methods": set(), "fields": set()})
        rotas[endpoint]["methods"].update(methods)
        for payload in re.findall(r"JSON\.stringify\s*\(\s*\{([^{}]{1,1200})\}", contexto):
            rotas[endpoint]["fields"].update(re.findall(r"([A-Za-z_$][\w$]*)\s*:", payload))

linhas = [
    "Inventario publico de lugaroriginal.com",
    "Paginas HTML visitadas: " + str(len(paginas_html)),
    "Bundles JS publicos analisados: " + str(len(bundles)),
    "Rotas /api/ disallowed pelo robots.txt: " + (", ".join(blocked) or "nenhuma declarada"),
    "Escopo: somente GET de paginas/bundles; formularios nao foram enviados.",
    "",
    "Paginas do sitemap e entradas inspecionadas:",
]
linhas.extend("- " + (urlsplit(u).path or "/") for u in sorted(set(sitemap_urls + [base + "/leitura", base + "/parceiros/pitagoras"])))
linhas.extend(("", "Links internos para outras paginas HTML:"))
linhas.extend("- " + x for x in sorted(links_publicos))
linhas.extend(("", "Comportamentos de rota observados no codigo publico:"))
linhas.extend("- " + x for x in sorted(comportamentos))
if not comportamentos:
    linhas.append("- Nenhum")
linhas.extend(("", "Rotas /api/ citadas literalmente em bundles:"))
if rotas:
    for endpoint, info in sorted(rotas.items()):
        metodo = ", ".join(sorted(info["methods"])) or "metodo nao identificado"
        campos = ", ".join(sorted(info["fields"])) or "campos nao identificados"
        linhas.append(f"- {metodo} {endpoint} | campos observados: {campos}")
else:
    linhas.append("- Nenhuma")
linhas.extend(("", "Formularios publicos encontrados (destinos; nenhum foi enviado):"))
if formularios:
    for origem, method, destino, fields in sorted(formularios):
        linhas.append(f"- pagina {origem}: {method} {destino} | campos: {fields}")
else:
    linhas.append("- Nenhum")
linhas.extend(("", "Este inventario nao identifica rotas administrativas sem link publico, nem chamadas que exijam autenticacao."))
conteudo = "\n".join(linhas) + "\n"
os.makedirs(os.path.dirname(saida), exist_ok=True)
fd, tmp = tempfile.mkstemp(prefix=".apis-", dir=os.path.dirname(saida), text=True)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(conteudo)
    os.replace(tmp, saida)
except Exception:
    try:
        os.unlink(tmp)
    except OSError:
        pass
    raise
print(conteudo, end="")
print("Inventario atualizado: " + saida)
