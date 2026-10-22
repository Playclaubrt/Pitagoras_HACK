#!/usr/bin/env bash
set -u

# Menu interativo para consultar e usar a API do Diario de Leitura.
API="https://www.lugaroriginal.com/api/leitura"
TOKEN="${DIARIO_TOKEN:-}"
FETCHES_VERIFICADOS=0
API_MINUTOS=""
INTERVALO=1
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
FEATURES_DIR="$SCRIPT_DIR/features"
LOG_DIR="$SCRIPT_DIR/logs"
FETCHES_ATUAL="$FEATURES_DIR/fetches-api-atual.txt"
FETCHES_CODIGO="$FEATURES_DIR/api_leitura_schema.py"
APIS_PUBLICAS="$FEATURES_DIR/apis-site-publicas.txt"
LOG_FILE="$LOG_DIR/diario-leitura.log"
PYTHON_BIN="${PYTHON_BIN:-$(command -v python3 || command -v python || true)}"

python() { "$PYTHON_BIN" "$@"; }

# Cores opcionais para deixar o menu mais legivel no terminal.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_CYAN=$'\033[36m'
  C_BLUE=$'\033[34m'; C_GREEN=$'\033[32m'; C_DIM=$'\033[2m'
else
  C_RESET=""; C_BOLD=""; C_CYAN=""; C_BLUE=""; C_GREEN=""; C_DIM=""
fi

menu_cabecalho() {
  printf "\n%s╭────────────────────────────────────────────╮%s\n" "$C_CYAN" "$C_RESET"
  printf "%s│  %s%s\n" "$C_BOLD$C_CYAN" "$1" "$C_RESET"
  [ -z "${2:-}" ] || printf "%s│  %s%s\n" "$C_DIM$C_CYAN" "$2" "$C_RESET"
  printf "%s╰────────────────────────────────────────────╯%s\n\n" "$C_CYAN" "$C_RESET"
}

menu_opcao() {
  local cor="$C_GREEN"
  [ "$1" = "0" ] && cor="$C_DIM"
  printf "  %s%-3s%s %s\n" "$cor" "$1" "$C_RESET" "$2"
}

# Consulta a interface atual e atualiza a lista dos payloads vistos nos bundles.
# Esta verificacao usa GET e nao altera registros do diario.
atualizar_fetches_site() {
  python - "$API" "$TOKEN" "$FETCHES_ATUAL" <<'PYFETCH'
import html, os, re, subprocess, sys, tempfile
from urllib.parse import urljoin

api, token, saida = sys.argv[1:]
base = api.rsplit("/api/", 1)[0]

def curl(url):
    p = subprocess.run(["curl", "--http1.1", "-fsSL", "--max-time", "25", url], check=True, capture_output=True, text=True)
    return p.stdout

pagina = curl(base + "/leitura/" + token)
scripts = re.findall(r'<script[^>]+src="([^\"]+\.js[^\"]*)"', pagina)
if not scripts:
    raise SystemExit("ERRO: nao achei scripts JS na pagina do diario.")

achados = {}
for caminho in scripts:
    try:
        js = curl(urljoin(base, html.unescape(caminho)))
    except subprocess.CalledProcessError:
        continue
    for m in re.finditer(r'JSON\.stringify\(\s*\{', js):
        inicio, nivel, aspas, escape, fim = m.end() - 1, 0, None, False, None
        for i in range(inicio, min(len(js), inicio + 3000)):
            ch = js[i]
            if aspas:
                if escape: escape = False
                elif ch == "\\": escape = True
                elif ch == aspas: aspas = None
                continue
            if ch in "'\"`": aspas = ch
            elif ch == "{": nivel += 1
            elif ch == "}":
                nivel -= 1
                if nivel == 0:
                    fim = i + 1
                    break
        if fim is None:
            continue
        objeto = js[inicio:fim]
        campos = set(re.findall(r'(?:^|[,\s])([A-Za-z_$][\w$]*)\s*:', objeto))
        a = re.search(r'acao\s*:\s*["\']([^"\']+)', objeto)
        acao = a.group(1) if a else "(sem acao; registro de leitura)"
        achados.setdefault(acao, set()).update(campos)

if not achados:
    raise SystemExit("ERRO: bundles encontrados, mas nao reconheci payloads JSON.stringify.")
linhas = ["Formatos atuais observados em " + base,
          "Verificado em: " + __import__("datetime").datetime.now().astimezone().isoformat(timespec="seconds"),
          "Fonte: bundles JS da pagina autenticada do diario.",
          "Campos observados na interface; a validacao interna do servidor pode diferir.", ""]
for acao in sorted(achados):
    linhas.append(f"- {acao}: {', '.join(sorted(achados[acao])) or '(campos nao identificados)'}")
conteudo = "\n".join(linhas) + "\n"
os.makedirs(os.path.dirname(saida), exist_ok=True)
def grava_atomico(caminho, texto):
    fd, temporario = tempfile.mkstemp(prefix=".fetches-", dir=os.path.dirname(caminho), text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(texto)
        os.replace(temporario, caminho)
    except Exception:
        try: os.unlink(temporario)
        except OSError: pass
        raise

grava_atomico(saida, conteudo)
codigo = "# Gerado automaticamente; nao edite. Campos vistos nos fetches do site.\nAPI_FETCHES = " + __import__("pprint").pformat({k: sorted(v) for k, v in sorted(achados.items())}, sort_dicts=True) + "\n"
grava_atomico(os.path.join(os.path.dirname(saida), "api_leitura_schema.py"), codigo)
print(conteudo, end="")
print("Relatorio atualizado: " + saida)
print("Esquema de codigo atualizado: " + os.path.join(os.path.dirname(saida), "api_leitura_schema.py"))
PYFETCH
  local status=$?
  if [ "$status" -eq 0 ]; then
    FETCHES_VERIFICADOS=1
    registrar_log "fetches=atualizados"
  fi
  return "$status"
}

atualizar_apis_publicas() {
  python "$FEATURES_DIR/apis_site.py" "$APIS_PUBLICAS" || return 1
  registrar_log "apis-publicas=atualizadas"
}

post_subscribe() {
  local email json resp status body
  read -r -p "E-mail para assinar a newsletter: " email
  if ! printf '%s' "$email" | python -c 'import re,sys; raise SystemExit(0 if re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", sys.stdin.read()) else 1)'; then
    echo "E-mail invalido."
    return 2
  fi
  confirmar_acao "Enviar este e-mail para a newsletter do Lugar Original?" || return 0
  json="$(python -c 'import json,sys; print(json.dumps({"email":sys.argv[1], "website":""}))' "$email")"
  resp="$(curl -sS --http1.1 --fail-with-body -X POST "https://www.lugaroriginal.com/api/subscribe" \
      -H "Content-Type: application/json" --data-raw "$json" \
      -w $'\n__HTTP__%{http_code}')"
  status=$?
  local http="${resp##*__HTTP__}"
  body="${resp%$'\n'__HTTP__*}"
  [ "$http" = "$resp" ] && http=000
  echo "HTTP $http"
  [ -n "$body" ] && echo "$body"
  registrar_log "api=subscribe http=$http curl=$status"
  return "$status"
}

menu_apis_publicas() {
  local escolha
  while :; do
    menu_cabecalho "APIS PUBLICAS" "Consultas e newsletter"
    menu_opcao 1 "Atualizar inventario de APIs"
    menu_opcao 2 "Assinar a newsletter"
    menu_opcao 0 "Voltar"
    read -r -p "› " escolha
    case "$escolha" in
      1)
        atualizar_apis_publicas || continue
        ;;
      2) post_subscribe ;;
      0) return 0 ;;
      *) echo "Opcao invalida." ;;
    esac
  done
}

menu_relatorio_parceiros() {
  local pin opcao serie id cookie_file
  printf "PIN do relatorio Pitagoras: "
  IFS= read -r -s pin || return 1
  printf "\n"
  if [ -z "$pin" ]; then echo "PIN vazio."; return 1; fi

  echo "Autenticando em lugaroriginal.com/parceiros/pitagoras..."
  cookie_file="$(mktemp)" || { unset pin; return 1; }
  if ! RELATORIO_PARCEIROS="$(printf '%s' "$pin" | curl --http1.1 -fsSL --max-time 30 \
      -b "$cookie_file" -c "$cookie_file" --location --data-urlencode 'pin@-' \
      "https://www.lugaroriginal.com/parceiros/pitagoras/auth")"; then
    python -c 'import os,sys; os.unlink(sys.argv[1])' "$cookie_file" 2>/dev/null || true
    unset pin
    echo "Nao consegui acessar o relatorio. Confira a conexao e o PIN."
    registrar_log "parceiros=erro-auth"
    return 1
  fi
  python -c 'import os,sys; os.unlink(sys.argv[1])' "$cookie_file" 2>/dev/null || true
  unset pin
  if ! printf '%s' "$RELATORIO_PARCEIROS" | python -c 'import sys; s=sys.stdin.read(); raise SystemExit(0 if "Prestação de contas da leitura" in s and "Acesso restrito" not in s else 1)'; then
    unset RELATORIO_PARCEIROS
    registrar_log "parceiros=pin-recusado"
    echo "O site nao confirmou o acesso; verifique o PIN."
    return 1
  fi
  registrar_log "parceiros=relatorio-acessado"

  while :; do
    menu_cabecalho "RELATORIO PITAGORAS" "Resumo e dados por turma"
    menu_opcao 1 "Resumo geral da escola"
    menu_opcao 2 "Nota da semana por turma"
    menu_opcao 3 "Adesao por turma"
    menu_opcao 4 "Detalhes de uma serie (inclui alunos)"
    menu_opcao 5 "Relatorio completo (inclui alunos)"
    menu_opcao 0 "Voltar"
    read -r -p "› " opcao
    case "$opcao" in
      1|2|3|5)
        printf '%s' "$RELATORIO_PARCEIROS" | python "$FEATURES_DIR/parceiros_relatorio.py" "$opcao"
        ;;
      4)
        menu_cabecalho "ESCOLHA A SERIE" "Ensino fundamental e medio"
        menu_opcao 1 "6º Ano"
        menu_opcao 2 "7º Ano"
        menu_opcao 3 "8º Ano"
        menu_opcao 4 "9º Ano"
        menu_opcao 5 "1ª Serie"
        menu_opcao 6 "2ª Serie"
        menu_opcao 7 "3ª Serie"
        menu_opcao 0 "Voltar ao relatorio"
        read -r -p "› " serie
        case "$serie" in
          0) continue ;;
          1) id=6ano ;; 2) id=7ano ;; 3) id=8ano ;; 4) id=9ano ;;
          5) id=1serie ;; 6) id=2serie ;; 7) id=3serie ;;
          *) echo "Serie invalida."; continue ;;
        esac
        printf '%s' "$RELATORIO_PARCEIROS" | python "$FEATURES_DIR/parceiros_relatorio.py" 4 "$id"
        ;;
      0) unset RELATORIO_PARCEIROS; return 0 ;;
      *) echo "Opcao invalida." ;;
    esac
  done
}

registrar_log() {
  mkdir -p "$LOG_DIR"
  printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >> "$LOG_FILE"
}

post_api() {
  local json resp curl_status http body acao="$1"
  shift
  json="$(python - "$TOKEN" "$acao" "$@" <<'PYJSON'
import json, sys
_, token, acao, *v = sys.argv
if acao == "leitura":
    data, livro, pagina, minutos, trecho, modo = v
    payload = {"token": token, "data": data, "livro": livro,
               "pagina": int(pagina), "minutos": int(minutos),
               "trecho": trecho, "modo": modo}
elif acao == "livro":
    titulo, mes, ano, paginas, nota = v
    payload = {"acao": "livro", "token": token, "titulo": titulo,
               "mes": int(mes), "ano": int(ano),
               "paginas": int(paginas), "nota": int(nota)}
elif acao == "desejo":
    titulo, autor = v
    payload = {"acao": "desejo", "token": token, "titulo": titulo, "autor": autor}
elif acao == "editar-livro":
    ident, paginas, nota = v
    payload = {"acao": acao, "token": token, "id": ident,
               "paginas": int(paginas), "nota": int(nota)}
elif acao in ("remover-livro", "remover-desejo"):
    payload = {"acao": acao, "token": token, "id": v[0]}
elif acao == "remover-registro":
    payload = {"acao": acao, "token": token, "data": v[0]}
else:
    raise SystemExit("Acao nao suportada pelo menu.")
print(json.dumps(payload, ensure_ascii=False))
PYJSON
)" || return 1
  resp="$(curl -sS --http1.1 --fail-with-body -X POST "$API" \
      -H "Content-Type: application/json" --data-raw "$json" \
      -w $'\n__HTTP__%{http_code}')"
  curl_status=$?
  http="${resp##*__HTTP__}"
  body="${resp%$'\n'__HTTP__*}"
  [ "$http" = "$resp" ] && http="000"
  printf 'HTTP %s\n' "$http"
  [ -n "$body" ] && printf '%s\n' "$body"
  API_MINUTOS="$(printf '%s' "$body" | python -c 'import json,sys; d=json.load(sys.stdin); print(d.get("minutos", ""))' 2>/dev/null || true)"
  registrar_log "acao=$acao http=$http curl=$curl_status"
  return "$curl_status"
}

confirmar_acao() {
  local resposta
  read -r -p "$1 [s/N]: " resposta
  case "$resposta" in s|S|sim|SIM) return 0 ;; *) return 1 ;; esac
}

menu_acoes_api() {
  local escolha data livro pagina minutos trecho modo titulo mes ano paginas nota autor ident
  while :; do
    menu_cabecalho "ACOES DO DIARIO" "Registros e livros"
    menu_opcao 1 "Registrar leitura do dia"
    menu_opcao 2 "Cadastrar livro terminado"
    menu_opcao 3 "Adicionar livro desejado"
    menu_opcao 4 "Editar paginas e nota de um livro"
    menu_opcao 5 "Remover livro terminado"
    menu_opcao 6 "Remover registro por data"
    menu_opcao 7 "Remover livro desejado"
    menu_opcao 8 "Acumular leituras e livros"
    menu_opcao 0 "Voltar ao menu principal"
    read -r -p "› " escolha
    case "$escolha" in
      1)
        read -r -p "Data (AAAA-MM-DD): " data
        read -r -p "Livro: " livro
        read -r -p "Pagina atual: " pagina
        read -r -p "Minutos (10, 15, 20, 30, 45 ou 60): " minutos
        read -r -p "Frase sobre a leitura: " trecho
        read -r -p "Modo (somar/corrigir): " modo
        case "$modo" in somar) ;; corrigir) confirmar_acao "Corrigir substitui o registro desse dia. Continuar?" || continue ;; *) echo "Modo invalido."; continue ;; esac
        post_api leitura "$data" "$livro" "$pagina" "$minutos" "$trecho" "$modo"
        ;;
      2)
        read -r -p "Titulo: " titulo
        read -r -p "Mes em que terminou (1-12): " mes
        read -r -p "Ano: " ano
        read -r -p "Numero de paginas: " paginas
        read -r -p "Nota (0-10): " nota
        post_api livro "$titulo" "$mes" "$ano" "$paginas" "$nota"
        ;;
      3)
        read -r -p "Titulo: " titulo
        read -r -p "Autor (pode deixar vazio): " autor
        post_api desejo "$titulo" "$autor"
        ;;
      4)
        read -r -p "ID do livro: " ident
        read -r -p "Numero de paginas: " paginas
        read -r -p "Nota (0-10): " nota
        post_api editar-livro "$ident" "$paginas" "$nota"
        ;;
      5)
        read -r -p "ID do livro terminado: " ident
        confirmar_acao "Remover este livro do diario?" && post_api remover-livro "$ident"
        ;;
      6)
        read -r -p "Data do registro (AAAA-MM-DD): " data
        confirmar_acao "Remover o registro dessa data?" && post_api remover-registro "$data"
        ;;
      7)
        read -r -p "ID do livro desejado: " ident
        confirmar_acao "Remover este livro desejado?" && post_api remover-desejo "$ident"
        ;;
      8) menu_acumular ;;
      0) return 0 ;;
      *) echo "Opcao invalida." ;;
    esac
  done
}

remover_livro_pendente() {
  python - "$LOG_DIR/livros-pendentes.txt" "$1" <<'PYPENDING'
import os, sys, tempfile
path, titulo = sys.argv[1:]
try:
    with open(path, encoding="utf-8") as f:
        linhas = f.readlines()
except FileNotFoundError:
    linhas = []
fd, tmp = tempfile.mkstemp(prefix=".pendentes-", dir=os.path.dirname(path), text=True)
with os.fdopen(fd, "w", encoding="utf-8") as f:
    f.writelines(x for x in linhas if x.rstrip("\n") != titulo)
os.replace(tmp, path)
PYPENDING
}

menu_acumular() {
  local escolha data livro pagina i atual
  menu_cabecalho "ACUMULAR" "Leituras e livros"
  menu_opcao 1 "Somar leituras ate 600 minutos"
  menu_opcao 2 "Buscar 750 titulos no Project Gutenberg"
  menu_opcao 0 "Voltar as acoes do diario"
  read -r -p "› " escolha
  case "$escolha" in
    1)
      read -r -p "Data (AAAA-MM-DD): " data
      read -r -p "Titulo do livro: " livro
      read -r -p "Pagina especifica: " pagina
      case "$data" in ????-??-??) ;; *) echo "Data deve estar no formato AAAA-MM-DD."; return 2 ;; esac
      case "$pagina" in ''|*[!0-9]*) echo "Pagina invalida."; return 2 ;; esac
      confirmar_acao "Serão somadas leituras de 60 min nessa data ate o retorno indicar 600 min. Continuar?" || return 0
      for i in 1 2 3 4 5 6 7 8 9 10; do
        echo "[$i/10] Somando 60 min: $livro, pagina $pagina ($data)"
        if ! post_api leitura "$data" "$livro" "$pagina" 60 "Li $livro ate a pagina $pagina." somar; then
          registrar_log "acumular=erro data=$data titulo=$livro pagina=$pagina tentativa=$i"
          echo "Parando no primeiro erro; confira a resposta da API e os logs."
          return 1
        fi
        atual="${API_MINUTOS:-}"
        if ! [[ "$atual" =~ ^[0-9]+$ ]]; then
          registrar_log "acumular=sem-total data=$data titulo=$livro pagina=$pagina tentativa=$i"
          echo "A API nao retornou o total de minutos; parei para evitar novas somas incertas."
          return 1
        fi
        registrar_log "acumular=data-$data titulo=$livro pagina=$pagina tentativa=$i minutos=$atual"
        if [ "$atual" -ge 600 ]; then
          echo "Meta alcancada: API informou $atual minutos em $data."
          return 0
        fi
        sleep "$INTERVALO"
      done
      echo "Foram feitas 10 tentativas. Total informado pela API: ${API_MINUTOS:-desconhecido}."
      ;;
    2)
      local lista_gutenberg="$SCRIPT_DIR/books/livros-gutenberg-750.txt"
      gerar_lista_gutenberg_750 "$lista_gutenberg" || return 1
      processar_livros_em_sequencia "$lista_gutenberg"
      ;;
    0) return 0 ;;
    *) echo "Opcao invalida."; return 2 ;;
  esac
}

gerar_lista_gutenberg_750() {
  local destino="$1"
  python - "$destino" <<'PYGUTENBERG'
import csv, gzip, io, re, sys, tempfile, urllib.request, os

destino = sys.argv[1]
url = "https://www.gutenberg.org/cache/epub/feeds/pg_catalog.csv.gz"
print("Buscando catalogo do Project Gutenberg...")
try:
    with urllib.request.urlopen(url, timeout=45) as response:
        dados = gzip.decompress(response.read()).decode("utf-8", "replace")
except Exception as exc:
    raise SystemExit(f"ERRO ao baixar o catalogo: {exc}")

titulos, vistos = [], set()
for row in csv.DictReader(io.StringIO(dados)):
    if row.get("Type", "").strip().lower() != "text":
        continue
    if not {x.strip().lower() for x in row.get("Language", "").split(";")} & {"en", "pt"}:
        continue
    titulo = re.sub(r"\s+", " ", row.get("Title", "")).strip()
    chave = titulo.casefold()
    if not titulo or len(titulo) > 160 or chave in vistos:
        continue
    vistos.add(chave)
    titulos.append(titulo.replace("|", " "))
    if len(titulos) == 750:
        break

if len(titulos) < 750:
    raise SystemExit(f"ERRO: catalogo retornou apenas {len(titulos)} titulos validos.")
os.makedirs(os.path.dirname(destino), exist_ok=True)
fd, temporario = tempfile.mkstemp(prefix=".livros-gutenberg-", dir=os.path.dirname(destino), text=True)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as arquivo:
        arquivo.write("# 750 titulos do catalogo do Project Gutenberg; um por linha.\n")
        arquivo.writelines(titulo + "\n" for titulo in titulos)
    os.replace(temporario, destino)
except Exception:
    try: os.unlink(temporario)
    except OSError: pass
    raise
print(f"TXT criado com 750 titulos: {destino}")
PYGUTENBERG
}

processar_livros_em_sequencia() {
  local arquivo enviados pendentes ordem total titulo mes ano paginas nota data_atual ano_atual sorteados mes_sorteado paginas_sorteadas nota_sorteada
  arquivo="${1:-$SCRIPT_DIR/books/livros.txt}"
  enviados="$LOG_DIR/livros-enviados.txt"
  pendentes="$LOG_DIR/livros-pendentes.txt"
  mkdir -p "$SCRIPT_DIR/books" "$LOG_DIR"
  touch "$enviados"
  if [ ! -f "$arquivo" ]; then
    cat > "$arquivo" <<'BOOKS'
# Um titulo por linha, ou: titulo|mes|ano|paginas|nota
BOOKS
  fi
  total=0
  while IFS= read -r titulo || [ -n "$titulo" ]; do
    case "$titulo" in ''|\#*) continue ;; esac
    total=$((total + 1))
  done < "$arquivo"
  if [ "$total" -eq 0 ]; then
    echo "Adicione titulos em $arquivo e tente novamente."
    return 1
  fi
  if [ "$total" -gt 750 ]; then
    echo "O arquivo tem $total titulos; o limite por execucao e 750."
    return 2
  fi
  ordem="$LOG_DIR/.livros-ordem.txt"
  restantes="$(python - "$arquivo" "$enviados" "$pendentes" "$ordem" <<'PYQUEUE'
import os, random, sys, tempfile
src, enviados, pendentes, ordem = sys.argv[1:]
try:
    with open(enviados, encoding="utf-8") as f:
        done = {x.rstrip("\n") for x in f}
except FileNotFoundError:
    done = set()
with open(src, encoding="utf-8") as f:
    linhas = []
    for raw in f:
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        linhas.append("|".join(part.strip() for part in raw.rstrip("\n").split("|")))
queue = [line for line in linhas if line.partition("|")[0].strip() not in done]
random.SystemRandom().shuffle(queue)
for path, values in ((ordem, queue), (pendentes, [x.partition("|")[0].strip() for x in queue])):
    fd, tmp = tempfile.mkstemp(prefix=".livros-", dir=os.path.dirname(path), text=True)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        for value in values: f.write(value + "\n")
    os.replace(tmp, path)
print(len(queue))
PYQUEUE
)" || return 1
  if [ "$restantes" -eq 0 ]; then echo "Todos os titulos ja estao no checkpoint de enviados."; return 0; fi
  echo "Titulos ainda nao enviados: $restantes (de $total)."
  echo "A ordem dos titulos pendentes sera sorteada nesta execucao."
  confirmar_acao "Processar a lista inteira?" || return 0
  ano_atual="$(python -c 'from datetime import datetime; print(datetime.now().year)')"

  exec 3< "$ordem"
  while IFS='|' read -r titulo mes ano paginas nota <&3 || [ -n "${titulo:-}" ]; do
    case "${titulo:-}" in ''|\#*) continue ;; esac
    if grep -Fqx -- "$titulo" "$enviados"; then
      continue
    fi
    sorteados="$(python -c 'import secrets; r=secrets.SystemRandom(); print(r.randint(1, 12), r.randint(1, 3000), r.randint(0, 10))')"
    read -r mes_sorteado paginas_sorteadas nota_sorteada <<< "$sorteados"
    if [ -z "${mes:-}" ]; then mes="$mes_sorteado"; fi
    ano="$ano_atual"
    if [ -z "${paginas:-}" ]; then paginas="$paginas_sorteadas"; fi
    if [ -z "${nota:-}" ]; then nota="$nota_sorteada"; fi
    if ! [[ "$mes" =~ ^([1-9]|1[0-2])$ && "$ano" =~ ^[0-9]{4}$ && "$paginas" =~ ^[1-9][0-9]*$ && "$nota" =~ ^(10|[0-9])$ ]]; then
      registrar_log "livro=pendente titulo=$titulo motivo=metadados-invalidos"
      echo "Metadados invalidos; deixei $titulo pendente."
      continue
    fi
    if post_api livro "$titulo" "$mes" "$ano" "$paginas" "$nota"; then
      echo "$titulo" >> "$enviados"
      remover_livro_pendente "$titulo"
      registrar_log "livro=enviado titulo=$titulo mes=$mes ano=$ano paginas=$paginas nota=$nota"
      sleep "$INTERVALO"
    else
      registrar_log "livro=erro titulo=$titulo; restante permanece em livros-pendentes.txt"
      echo "Erro no envio; interrompi a sequencia. Confira os logs e retome depois."
      exec 3<&-
      return 1
    fi
    unset mes ano paginas nota
  done
  exec 3<&-
  rm -f "$ordem"
  echo "Lista processada. Enviados: $enviados | Pendentes: $pendentes"
}

garantir_dependencias() {
  local essenciais=""
  command -v curl >/dev/null 2>&1 || essenciais="$essenciais curl"
  command -v git >/dev/null 2>&1 || essenciais="$essenciais git"
  if [ -z "$PYTHON_BIN" ]; then
    if command -v pkg >/dev/null 2>&1; then
      echo "Instalando Python no Termux..."
      pkg install -y python || return 1
      PYTHON_BIN="$(command -v python3 || command -v python || true)"
    fi
    [ -n "$PYTHON_BIN" ] || essenciais="$essenciais Python 3"
  fi
  if [ -n "$essenciais" ]; then
    if command -v pkg >/dev/null 2>&1; then
      echo "Instalando dependencias:$essenciais"
      pkg install -y $essenciais || return 1
    else
      echo "ERRO: faltam dependencias:$essenciais (instale-as e tente novamente)."
      return 1
    fi
  fi
}

pedir_token() {
  if [ -z "$TOKEN" ]; then
    printf "Token do diario: "
    IFS= read -r -s TOKEN || return 1
    printf "\n"
  fi
  [ -n "$TOKEN" ] || { echo "ERRO: token vazio."; return 1; }
}

rodar_verificacao() {
  pedir_token || return 1
  if [ "$FETCHES_VERIFICADOS" -ne 1 ]; then atualizar_fetches_site || return 1; fi
  atualizar_apis_publicas
}

# Check origin on every launch. Fast-forward only; Git refuses if local edits
# would be overwritten, so a user's work is kept intact.
atualizar_codigo_remoto() {
  local branch remoto contagens frente atras
  command -v git >/dev/null 2>&1 || { echo "Git indisponivel; pulei a verificacao do origin."; return 0; }
  git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  branch="$(git -C "$SCRIPT_DIR" branch --show-current 2>/dev/null)"
  [ -n "$branch" ] || { echo "Branch local nao identificada; pulei a atualizacao."; return 0; }
  remoto="origin/$branch"
  if ! git -C "$SCRIPT_DIR" fetch --quiet --no-tags origin "$branch"; then
    echo "Nao consegui consultar origin; vou continuar com o codigo local."
    return 0
  fi
  git -C "$SCRIPT_DIR" show-ref --verify --quiet "refs/remotes/$remoto" || {
    echo "origin/$branch nao encontrado; vou continuar com o codigo local."
    return 0
  }
  contagens="$(git -C "$SCRIPT_DIR" rev-list --left-right --count "HEAD...$remoto" 2>/dev/null)" || return 0
  read -r frente atras <<< "$contagens"
  if [ "${atras:-0}" -gt 0 ]; then
    if git -C "$SCRIPT_DIR" merge --ff-only --quiet "$remoto"; then
      echo "Codigo atualizado de origin/$branch. A nova versao sera usada na proxima execucao."
    else
      echo "origin/$branch tem atualizacoes, mas ha edicoes locais que impedem o avanco seguro. Mantive seus arquivos locais."
    fi
  elif [ "${frente:-0}" -gt 0 ]; then
    echo "Codigo local tem commits que ainda nao estao em origin/$branch."
  fi
}

atualizar_esquema_no_inicio() {
  if [ -z "$TOKEN" ]; then
    printf "Token do diario para verificar os fetches do site (Enter para pular): "
    IFS= read -r -s TOKEN || TOKEN=""
    printf "\n"
  fi
  if [ -z "$TOKEN" ]; then
    echo "Verificacao dos fetches do site pulada; nenhum token foi informado."
    return 0
  fi
  if atualizar_fetches_site; then
    echo "Esquema local atualizado com os fetches atuais do site."
  else
    echo "Nao consegui ler os fetches do site; mantive o ultimo esquema salvo."
  fi
}

verificar_classapp() {
  local host="classapp-app.firebaseio.com" status
  if ! command -v ping >/dev/null 2>&1; then
    echo "Nao encontrei o comando ping neste sistema."
    return 1
  fi
  echo "Verificando Class APP: $host"
  case "$(uname -s 2>/dev/null)" in
    Darwin*) ping -c 1 -W 5000 "$host" >/dev/null 2>&1; status=$? ;;
    MINGW*|MSYS*|CYGWIN*) ping -n 1 -w 5000 "$host" >/dev/null 2>&1; status=$? ;;
    *) ping -c 1 -W 5 "$host" >/dev/null 2>&1; status=$? ;;
  esac
  if [ "$status" -eq 0 ]; then
    echo "Class APP esta acessivel pela rede (ping respondeu)."
  else
    echo "Class APP nao respondeu ao ping. Verifique DNS, conexao ou disponibilidade do host."
  fi
  return "$status"
}

# Allow only coordinates inside an approximate outline of Brazil. Location is
# based on the public IP's latitude/longitude, not country or continent labels.
verificar_geolocalizacao() {
  local resposta localizacao estado latitude longitude
  if ! resposta="$(curl --http1.1 -fsSL --max-time 10 https://ipwho.is/)"; then
    echo "Nao consegui verificar as coordenadas. Por seguranca, o script nao vai continuar."
    return 1
  fi
  localizacao="$(printf '%s' "$resposta" | python -c '
import json, math, sys
try:
    d = json.load(sys.stdin)
    if d.get("success") is not True:
        raise ValueError("lookup failed")
    lat, lon = float(d["latitude"]), float(d["longitude"])
    if not math.isfinite(lat) or not math.isfinite(lon):
        raise ValueError("invalid coordinates")
except Exception:
    raise SystemExit(1)

# Approximate Brazil border, as (latitude, longitude) pairs.
polygon = [
    (1.0,-69.5), (4.0,-64.0), (5.3,-60.2), (4.0,-58.0),
    (2.0,-52.0), (0.0,-50.0), (-1.0,-46.0), (-3.0,-44.0),
    (-2.0,-42.0), (-4.0,-40.0), (-6.0,-36.0), (-7.2,-34.7),
    (-10.0,-35.0), (-13.0,-38.0), (-16.0,-39.5), (-19.0,-40.5),
    (-22.0,-41.5), (-24.0,-46.0), (-26.0,-48.5), (-29.0,-49.5),
    (-32.0,-52.0), (-33.8,-53.5), (-32.0,-55.5), (-29.0,-57.5),
    (-25.0,-58.0), (-22.0,-57.0), (-19.0,-54.0), (-16.0,-58.0),
    (-13.0,-60.5), (-10.0,-65.0), (-8.0,-70.0), (-7.5,-74.0),
    (-4.0,-74.0), (-1.0,-72.0), (1.0,-69.5),
]
inside = False
j = len(polygon) - 1
for i, (yi, xi) in enumerate(polygon):
    yj, xj = polygon[j]
    crosses = ((yi > lat) != (yj > lat)) and (lon < (xj - xi) * (lat - yi) / (yj - yi) + xi)
    if crosses:
        inside = not inside
    j = i
print(("BR" if inside else "OUT") + "\t" + str(lat) + "\t" + str(lon))
' 2>/dev/null)" || {
    echo "Resposta de coordenadas invalida. Por seguranca, o script nao vai continuar."
    return 1
  }
  IFS=$'\t' read -r estado latitude longitude <<< "$localizacao"
  if [ "$estado" != "BR" ]; then
    echo "Acesso bloqueado: coordenadas fora da area permitida do Brasil ($latitude, $longitude)."
    return 1
  fi
  echo "Localizacao permitida no Brasil ($latitude, $longitude)."
}

mostrar_ajuda() {
  cat <<'HELP'
Uso: pitagocript [opcoes]

Sem opcoes, abre o menu interativo. Opcoes podem ser combinadas e executam
na ordem informada:
  -a, --atualizar, --verificar-fetches  Atualiza referencias das APIs
  -b, --diario                          Abre as acoes do diario
  -c, --pitagoras                       Abre o relatorio Pitagoras
  -d, --apis                            Abre APIs publicas e newsletter
  -h, --help                            Mostra esta ajuda

Exemplos:
  pitagocript
  pitagocript -a
  pitagocript -a -b
  pitagocript -cd
HELP
}

declare -a ACOES=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) mostrar_ajuda; exit 0 ;;
    -a|--atualizar|--verificar-fetches) ACOES+=(a) ;;
    -b|--diario) ACOES+=(b) ;;
    -c|--pitagoras) ACOES+=(c) ;;
    -d|--apis) ACOES+=(d) ;;
    -[abcd][abcd]*)
      flags="${1#-}"
      while [ -n "$flags" ]; do
        flag="${flags:0:1}"
        case "$flag" in a|b|c|d) ACOES+=("$flag") ;; *) echo "Opcao invalida: -$flag" >&2; exit 2 ;; esac
        flags="${flags:1}"
      done
      ;;
    *) echo "Opcao nao reconhecida: $1" >&2; echo "Use pitagocript --help." >&2; exit 2 ;;
  esac
  shift
done

garantir_dependencias || exit 1
verificar_geolocalizacao || exit 1
atualizar_codigo_remoto
atualizar_esquema_no_inicio

if [ "${#ACOES[@]}" -eq 0 ]; then
  while :; do
    menu_cabecalho "DIÁRIO DE LEITURA" "Seu painel de leitura"
    printf "%s  PRINCIPAL%s\n" "$C_BOLD$C_BLUE" "$C_RESET"
    menu_opcao A "Atualizar verificacao e esquema de API"
    menu_opcao B "Abrir ferramentas do diario"
    printf "\n%s  CONSULTAS%s\n" "$C_BOLD$C_BLUE" "$C_RESET"
    menu_opcao C "Relatorio Pitagoras"
    menu_opcao D "APIs publicas e newsletter"

    menu_cabecalho "Class APP" "Verificacao do sistema"
    menu_opcao A "Verificar Sistema"

    menu_cabecalho "Education 1" "Em breve"
    printf "  %sNovas opcoes estarao disponiveis em breve.%s\n\n" "$C_DIM" "$C_RESET"
    printf "Use D-A, D-B, D-C ou D-D para o Diario; C-A para Class APP; 0 para fechar.\n"
    menu_opcao 0 "Fechar"
    read -r -p "› " escolha || exit 0
    case "$escolha" in
      D-A|d-a|D:A|d:a|DIARIO:A|diario:a) rodar_verificacao || echo "A verificacao falhou." ;;
      D-B|d-b|D:B|d:b|DIARIO:B|diario:b)
        if pedir_token; then
          if [ "$FETCHES_VERIFICADOS" -eq 1 ] || atualizar_fetches_site; then
            menu_acoes_api
          else
            echo "Nao foi possivel atualizar as referencias."
          fi
        fi
        ;;
      D-C|d-c|D:C|d:c|DIARIO:C|diario:c) menu_relatorio_parceiros || echo "Nao foi possivel abrir o relatorio." ;;
      D-D|d-d|D:D|d:d|DIARIO:D|diario:d) menu_apis_publicas || echo "Nao foi possivel abrir as APIs publicas." ;;
      C-A|c-a|C:A|c:a|CLASS:A|class:a) verificar_classapp || true ;;
      0) exit 0 ;;
      *) echo "Opcao invalida. Use D-A, D-B, D-C, D-D, C-A ou 0." ;;
    esac
  done
fi

for acao in "${ACOES[@]}"; do
  case "$acao" in
    a) rodar_verificacao || exit $? ;;
    b) pedir_token || exit 1; if [ "$FETCHES_VERIFICADOS" -ne 1 ]; then atualizar_fetches_site || exit 1; fi; menu_acoes_api || exit $? ;;
    c) menu_relatorio_parceiros || exit $? ;;
    d) menu_apis_publicas || exit $? ;;
  esac
done
