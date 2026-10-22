# Diário de Leitura

Script interativo para consultar os formatos usados pelo site e executar ações escolhidas no menu.

## Requisitos

- Bash
- `curl`
- Python 3
- `figlet` para o título grande; o script tenta instalá-lo pelo `pkg` e usa um cabeçalho alternativo se não conseguir.

Ao iniciar, o script verifica `curl` e Python e tenta instalar o que estiver faltando usando `pkg` (Termux). O token é solicitado oculto e não é salvo em arquivo nem incluído nos logs.

## Uso

```sh
bash scripitagoras.sh
```

- **A** consulta a página do diário e os bundles JavaScript atuais. Atualiza `features/fetches-api-atual.txt`, `features/api_leitura_schema.py` e o inventário público em `features/apis-site-publicas.txt`.
- **B** solicita o token e abre um submenu para escolher a ação. Os campos são pedidos na hora. Remoções e o modo `corrigir` pedem confirmação.
- **C** solicita o PIN do relatório de `lugaroriginal.com/parceiros/pitagoras` e oferece resumo geral, nota semanal, adesão, detalhes por série e relatório completo. Os detalhes por série e o relatório completo podem conter nomes de alunos. O conteúdo é exibido no terminal e não é salvo em arquivo; somente o evento de acesso fica no log.
- **D** abre um inventário dos links e formulários públicos encontrados no sitemap, nas páginas e nos bundles JavaScript do site, além das rotas `/api/` citadas nesses bundles. A opção 1 atualiza a lista em `features/apis-site-publicas.txt`, incluindo redirecionamentos públicos como `/leitura` → `/leitura/{token}` sem capturar o token local; a opção 2 permite assinar a newsletter por `/api/subscribe`, pedindo confirmação antes de enviar. O inventário registra rotas e campos identificados, incluindo o formulário público do portal Pitágoras (`POST /parceiros/pitagoras/auth`, campo `pin`); não executa as APIs descobertas. A página autenticada do Pitágoras retorna o relatório em HTML após redirecionamento e não contém scripts, formulários ou chamadas fetch/XHR adicionais; os links são apenas âncoras internas para turmas e séries. O levantamento ampliado, incluindo sitemap, bundles, robots.txt e scripts locais antigos, está em `features/pitagoras-api.txt`.
- Na lista de ações, **8 — Acumular** abre dois modos:
  1. Soma blocos de 60 minutos para o mesmo título, página e data, parando quando a API informa 600 minutos ou quando ocorre erro.
  2. Sorteia a ordem e processa todos os títulos pendentes de `books/livros.txt`, até 750 nomes por execução. Usa o ano local atual e sorteia mês (1–12), páginas (1–3000) e nota (0–10) para cada título. Campos informados no TXT são preservados, exceto o ano, que sempre é o atual.
- **0** volta/sai dos submenus.

Em `books/livros.txt`, use um título por linha para sortear mês, páginas e nota automaticamente. Opcionalmente, informe `titulo|mes|ano|paginas|nota`; os campos mês, páginas e nota informados substituem o sorteio, mas o ano enviado será sempre o ano local atual. Os checkpoints ficam em `logs/livros-enviados.txt` e `logs/livros-pendentes.txt`, permitindo retomar depois sem repetir os títulos já confirmados.

Também é possível atualizar as referências diretamente:

```sh
bash scripitagoras.sh --verificar-fetches
```

## Pastas

- `features/`: relatório TXT dos fetches vistos no site, esquema Python gerado e parser local do relatório Pitágoras.
- `logs/`: ações e status HTTP, além das listas de livros enviados e pendentes. O token não é salvo; algumas entradas incluem título, data ou página para permitir a retomada.

A leitura dos bundles descreve os formatos enviados pela interface e não garante as regras internas do servidor. As ações de avatar e pergunta usam fluxos específicos e não estão no submenu simples.
