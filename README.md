# Diário de Leitura

Script interativo para consultar os formatos usados pelo site e executar ações escolhidas no menu.

## Contato

O Email de contato a nós é: kronozizt@torbox3uiot6wchz.onion


## Requisitos e compatibilidade

Use Bash 3.2+, `curl`, Git, Python 3 e PostgreSQL client (`psql`). O instalador detecta Termux, Debian/Ubuntu, Fedora/RHEL, Arch, openSUSE, macOS com Homebrew e Windows com Git Bash/MSYS/Cygwin. WSL usa o gerenciador Linux da distribuição. Sistemas sem um desses gerenciadores precisam instalar os mesmos requisitos manualmente.

Antes da primeira execução, rode:

```sh
./install-pitagocript.sh
```

O instalador instala os pacotes disponíveis para o sistema, cria um link `pitagocript` no PATH quando possível e cria `.env` a partir de `.env.example` sem substituir um `.env` existente. Edite `.env` e defina `NEON_DATABASE_URL` com a URI do Neon. Esse é o único dado de configuração externo obrigatório. O arquivo `.env` fica privado e ignorado pelo Git. Instalar dependências pode exigir senha de administrador no Linux/macOS; no Termux usa `pkg` sem sudo.

O launcher verifica as dependências e a URI antes de prosseguir; ele não instala pacotes durante a inicialização. A primeira execução pede o nome e salva em `.person-name`, ignorado pelo Git. Execuções posteriores mostram `Hi, {NAME}`. Após clonar o projeto em outra máquina, instale os pacotes, configure novamente o `.env` e informe o nome uma vez naquele clone.

O script pode consultar `origin` ao iniciar e aplicar atualizações fast-forward sem sobrescrever edições locais. A verificação opcional dos fetches usa token do diário somente em memória; pressione Enter para pular.

## Uso

Abra o menu interativo com:

```sh
./pitagocript
```

Depois de concluir a configuração, abra o sistema com:

```sh
pitagocript --help
pitagocript
```

No Windows, rode o instalador pelo Git Bash e use `pitagocript.cmd` em um terminal onde `bash` esteja no PATH, ou execute `./pitagocript` pelo Git Bash/WSL.

Opções diretas (também podem ser combinadas, por exemplo `pitagocript -a -b`):

- `-a`: atualizar referências das APIs.
- `-b`: abrir as ações do diário.
- `-c`: abrir o relatório Pitágoras.
- `-d`: abrir APIs públicas e newsletter.
- `-h`: mostrar ajuda.

Ao iniciar sem opções, o terminal mostra três painéis nesta ordem: **Diário de Leitura**, **Class APP** e **Education 1**. O Diário mantém as opções A–D; no prompt compartilhado, use `D-A` até `D-D` para escolhê-las. Class APP tem apenas `A — Verificar Sistema`, selecionada com `C-A`. Education 1 oferece `E-A`, que abre um submenu: `A — Verificar Sistema` consulta `https://e1.education1.com.br/app_free.php` com HTTP GET e informa o status HTTP; `E — Abrir Education 1` abre esse endereço no navegador padrão. A URL está embutida no APK do Education 1. O status HTTP mede o acesso ao portal, não a saúde interna do Firebase. `0` fecha o script.

A verificação do Class APP envia ping para `classapp-app.firebaseio.com` e informa se o host respondeu. Ping confirma conectividade de rede, não o estado interno do aplicativo.

Dentro do menu Diário de Leitura:

- **A** consulta a página do diário e os bundles JavaScript atuais. Atualiza `features/fetches-api-atual.txt`, `features/api_leitura_schema.py` e o inventário público em `features/apis-site-publicas.txt`.
- **B** solicita o token e abre um submenu para escolher a ação. Os campos são pedidos na hora. Remoções e o modo `corrigir` pedem confirmação.
- **C** solicita o PIN do relatório de `lugaroriginal.com/parceiros/pitagoras` e oferece resumo geral, nota semanal, adesão, detalhes por série e relatório completo. Os detalhes por série e o relatório completo podem conter nomes de alunos. O conteúdo é exibido no terminal e não é salvo em arquivo; somente o evento de acesso fica no log.
- **D** abre um inventário dos links e formulários públicos encontrados no sitemap, nas páginas e nos bundles JavaScript do site, além das rotas `/api/` citadas nesses bundles. A opção 1 atualiza a lista em `features/apis-site-publicas.txt`, incluindo redirecionamentos públicos como `/leitura` → `/leitura/{token}` sem capturar o token local; a opção 2 permite assinar a newsletter por `/api/subscribe`, pedindo confirmação antes de enviar. O inventário registra rotas e campos identificados, incluindo o formulário público do portal Pitágoras (`POST /parceiros/pitagoras/auth`, campo `pin`); não executa as APIs descobertas. A página autenticada do Pitágoras retorna o relatório em HTML após redirecionamento e não contém scripts, formulários ou chamadas fetch/XHR adicionais; os links são apenas âncoras internas para turmas e séries. O levantamento ampliado, incluindo sitemap, bundles, robots.txt e scripts locais antigos, está em `features/pitagoras-api.txt`.
- Na lista de ações, **8 — Acumular** abre dois modos:
  1. Soma blocos de 60 minutos para o mesmo título, página e data, parando quando a API informa 600 minutos ou quando ocorre erro.
  2. Busca 750 títulos em inglês ou português no catálogo do Project Gutenberg e cria `books/livros-gutenberg-750.txt`. Depois, pede confirmação e processa os títulos ainda não enviados, com mês, páginas e nota sorteados. A ordem é embaralhada e os checkpoints permitem retomar.
- **0** volta um nível nos submenus.

Em `books/livros.txt`, use um título por linha para sortear mês, páginas e nota automaticamente. Opcionalmente, informe `titulo|mes|ano|paginas|nota`; os campos mês, páginas e nota informados substituem o sorteio, mas o ano enviado será sempre o ano local atual. Os checkpoints ficam em `logs/livros-enviados.txt` e `logs/livros-pendentes.txt`, permitindo retomar depois sem repetir os títulos já confirmados.

Também é possível atualizar as referências diretamente:

```sh
bash scripitagoras.sh --verificar-fetches
```

## Pastas

- `features/`: relatório TXT dos fetches vistos no site, esquema Python gerado e parser local do relatório Pitágoras.
- `logs/`: ações e status HTTP, além das listas de livros enviados e pendentes. O token não é salvo; algumas entradas incluem título, data ou página para permitir a retomada.

A leitura dos bundles descreve os formatos enviados pela interface e não garante as regras internas do servidor. As ações de avatar e pergunta usam fluxos específicos e não estão no submenu simples.
