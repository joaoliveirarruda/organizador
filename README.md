# Organizador

App nativo para macOS para organizar a vida: cronômetro por área, objetivos, tarefas, hábitos, agenda, finanças e notas, num lugar só. O tempo que você cronometra em cada área vira progresso nos seus objetivos, e o app avisa quando alguma frente fica parada.

Open source, feito em Swift (SwiftUI). Os dados ficam só no seu Mac, num arquivo JSON legível.

## O que já funciona

O app é um *second brain*: você pensa (notas), planeja (objetivos, tarefas, hábitos, agenda) e executa (cronômetro) num lugar só, com tudo medido em tempo e ligado entre si.

**Visual e navegação** (inspirados no Notion):

- Barra lateral clara com Buscar, Home, Cronômetro, Nova nota, os **Objetivos** ativos e as notas **Recentes**. Objetivos pausados e encerrados ficam recolhidos embaixo. O cronômetro que está rodando aparece sempre na barra.
- Segue o modo claro e escuro do macOS.
- Notas, objetivos e áreas têm ícone (emoji ou foto) e capa. A capa só aparece na página aberta, nunca nas listas. As fotos são copiadas para dentro do app (ou para `anexos/` na pasta de notas).
- Busca que encontra notas, objetivos, áreas e tarefas.

**Home:**

- Saudação e a caixa "No que você vai trabalhar agora?": digite, escolha uma área e o cronômetro começa (Enter cria a área se ela não existir).
- O seu dia: reuniões, tarefas de hoje e hábitos.
- Frentes: progresso de cada objetivo ativo, com destaque para os parados e botões para retomar, pausar ou encerrar.
- Esta semana, pretendido × real, por objetivo e para as áreas soltas.

**Cronômetro** (inspirado no Yeolpumta):

- Total do dia em destaque, na cor da área que está rodando, com o D-dia do prazo do objetivo e quanto da meta diária já foi.
- Lista de áreas com ▶ e o tempo de hoje; áreas ligadas a um objetivo mostram o objetivo e uma barrinha de progresso. Áreas podem ser soltas (ex.: "E-mails").
- Calendário do dia ao lado, com reuniões e blocos cronometrados; clique num bloco para editar ou use + para incluir uma sessão à mão.
- Tempo do dia sempre na barra de menu, com painel para iniciar e pausar sem abrir a janela.
- Pausa automática quando você fica sem usar o Mac (padrão: 10 min) ou quando ele entra em repouso.
- Página de cada área com capa, tempo de hoje e da semana e as sessões dos últimos 7 dias.

**Objetivos como projetos:**

- Crie só com o nome; alvo em horas, prazo, ritmo semanal pretendido e o limite de dias para contar como parado (padrão: 7) são opcionais.
- A página do objetivo mostra progresso, prazo e D-dia, ritmo necessário, a semana contra o pretendido, o botão para trabalhar nele e "onde parei" (último bloco de tempo, última nota, próxima tarefa).
- Notas ligadas (as que têm `[[Nome do objetivo]]`), mais recentes primeiro, com "Nova nota" já ligada; tarefas, hábitos e áreas do objetivo.

**Fio da meada:**

- Um objetivo é mexido quando você cronometra numa área dele, edita uma nota ligada ou conclui uma tarefa ligada.
- Ativo e sem mexer pelo limite de dias, ele fica parado: aparece na Home até você retomar, pausar ou encerrar. Pausados e encerrados nunca contam como parados.
- No máximo um aviso do macOS por dia juntando todos os parados (desligável nos Ajustes). Clicar no aviso abre a Home.

**Calendário de fora:**

- Ligue nos Ajustes e cada sessão cronometrada vira um evento no Calendário do macOS, como "⏱ Penal · Passar na OAB", no calendário que você escolher. Com a conta Google adicionada no Mac, aparece também no Google Agenda.
- Editar a sessão atualiza o evento e apagar a sessão apaga o evento. A mesma sessão nunca vira dois eventos.
- Funciona no app gerado por `./scripts/build-app.sh` (o macOS pede a permissão de acesso ao Calendário).

**Tarefas:**

- Listas Hoje (inclui atrasadas), Próximas e Concluídas.
- Adição rápida com Enter, prazo, prioridade, notas e ligação com um objetivo.

**Hábitos:**

- Check diário, sequência atual e taxa dos últimos 30 dias.
- Calendário de constância das últimas 12 semanas; clique num dia para marcar ou desmarcar.
- Marcação automática pelo cronômetro (ex.: "Ler 30 min" fica feito quando Leitura passa de 30 min no dia).

**Agenda:**

- Lê o Google Agenda (ou qualquer agenda que exporte iCal) pelo link secreto colado nos Ajustes, com eventos recorrentes, exceções e eventos cancelados. Atualiza a cada 15 min e guarda uma cópia para usar sem internet.

**Finanças** (em "Mais", na barra lateral):

- Lançamentos manuais de despesas e receitas, com categoria.
- Resumo do mês (receitas, despesas, saldo) e orçamento mensal por categoria, com aviso quando passa do limite.
- Importação de extrato OFX ou CSV (formato brasileiro ou americano, inclusive o CSV da Nubank). Importar o mesmo arquivo de novo não duplica nada, e a categoria de um lançamento parecido é reaproveitada.

**Notas:**

- Editor Markdown que se formata enquanto você digita (títulos, negrito, itálico, código, citações, listas), com os símbolos apagados, como no Obsidian.
- Digite `/` no começo da linha para inserir título, lista, checklist, citação, código ou divisória. Enter continua a lista; clique no `[ ]` para marcar.
- `[[Nome]]` liga notas entre si e também a objetivos e tarefas. Clicar no link abre a nota (ou cria, se ainda não existir); embaixo aparece "Mencionada em" com as notas que apontam para esta.
- Grafo de conexões: notas, objetivos e tarefas ligadas pelos links. Arraste nós, mova o fundo, use pinça para zoom e clique para abrir.
- Exportar a nota em PDF (A4, com a formatação e sem os símbolos de Markdown).
- Cada nota é um arquivo `.md` numa pasta que você escolhe nos Ajustes; dá para abrir a mesma pasta como cofre no Obsidian. Ícone e capa ficam no bloco de *front matter* (`icon`, `cover`), que o Obsidian também entende. Renomear uma nota atualiza os links nas outras.

## Como rodar

Precisa de macOS 14 (Sonoma) ou mais novo e Xcode 16.

- **No Xcode:** abra a pasta do projeto (ou o `Package.swift`), escolha o esquema `Organizador` e aperte ⌘R.
- **No terminal:** `swift run Organizador`
- **Gerar o app:** `./scripts/build-app.sh` cria `dist/Organizador.app`, que você pode arrastar para Aplicativos.

Testes: `swift test`.

## Estrutura

| Pasta | O que tem |
| --- | --- |
| `Sources/OrganizadorCore` | Regras sem interface: modelos, cronômetro, estatísticas, objetivos e fio da meada, tarefas, hábitos, agenda iCal, finanças, notas, front matter e grafo, salvamento em JSON |
| `Sources/Organizador` | O app SwiftUI: janela, barra de menu, ajustes |
| `Tests/OrganizadorCoreTests` | Testes do núcleo |

Os dados ficam em `~/Library/Application Support/Organizador/data.json` (imagens em `Imagens/` ao lado) e as notas, por padrão, em `~/Library/Application Support/Organizador/Notas/`.

## Licença

[MIT](LICENSE)
