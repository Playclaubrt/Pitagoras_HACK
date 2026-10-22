# Diário de Leitura

Script interativo para consultar os formatos usados pelo site e executar ações escolhidas no menu.

## Requisitos e compatibilidade

- Bash 3.2 ou mais recente
- `curl`
- Python 3

O script usa Bash e caminhos portáveis. Ele funciona em Linux, macOS, Termux/Android e ambientes Bash no Windows, como Git Bash ou WSL. No iPhone/iPad, é necessário um app de terminal que ofereça Bash, Python 3 e `curl`; o terminal padrão do iOS não executa scripts Bash.

No Termux, dependências ausentes podem ser instaladas com `pkg`. Em outros sistemas, instale Bash, `curl` e Python 3 pelo gerenciador do sistema.

## Uso

Abra o menu interativo com:

```sh
./pitagocript
```

Para instalar o comando no PATH do usuário em Linux, macOS ou Termux:

```sh
./install-pitagocript.sh
pitagocript --help
```

No Windows, use `pitagocript.cmd` em um terminal onde `bash` esteja no PATH, ou execute `./pitagocript` pelo Git Bash/WSL.

Opções diretas (também podem ser combinadas, por exemplo `pitagocript -a -b`):

- `-a`: atualizar referências das APIs.
- `-b`: abrir as ações do diário.
- `-c`: abrir o relatório Pitágoras.
- `-d`: abrir APIs públicas e newsletter.
- `-h`: mostrar ajuda.

- **A** consulta a página do diário e os bundles JavaScript atuais. Atualiza `features/fetches-api-atual.txt`, `features/api_leitura_schema.py` e o inventário público em `features/apis-site-publicas.txt`.
- **B** solicita o token e abre um submenu para escolher a ação. Os campos são pedidos na hora. Remoções e o modo `corrigir` pedem confirmação.
- **C** solicita o PIN do relatório de `lugaroriginal.com/parceiros/pitagoras` e oferece resumo geral, nota semanal, adesão, detalhes por série e relatório completo. Os detalhes por série e o relatório completo podem conter nomes de alunos. O conteúdo é exibido no terminal e não é salvo em arquivo; somente o evento de acesso fica no log.
- **D** abre um inventário dos links e formulários públicos encontrados no sitemap, nas páginas e nos bundles JavaScript do site, além das rotas `/api/` citadas nesses bundles. A opção 1 atualiza a lista em `features/apis-site-publicas.txt`, incluindo redirecionamentos públicos como `/leitura` → `/leitura/{token}` sem capturar o token local; a opção 2 permite assinar a newsletter por `/api/subscribe`, pedindo confirmação antes de enviar. O inventário registra rotas e campos identificados, incluindo o formulário público do portal Pitágoras (`POST /parceiros/pitagoras/auth`, campo `pin`); não executa as APIs descobertas. A página autenticada do Pitágoras retorna o relatório em HTML após redirecionamento e não contém scripts, formulários ou chamadas fetch/XHR adicionais; os links são apenas âncoras internas para turmas e séries. O levantamento ampliado, incluindo sitemap, bundles, robots.txt e scripts locais antigos, está em `features/pitagoras-api.txt`.
- Na lista de ações, **8 — Acumular** abre dois modos:
  1. Soma blocos de 60 minutos para o mesmo título, página e data, parando quando a API informa 600 minutos ou quando ocorre erro.
  2. Busca 750 títulos em inglês ou português no catálogo do Project Gutenberg e cria `books/livros-gutenberg-750.txt`. Depois, pede confirmação e processa os títulos ainda não enviados, com mês, páginas e nota sorteados. A ordem é embaralhada e os checkpoints permitem retomar.
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
