# Organizador

App nativo para macOS para organizar a vida: cronômetro por atividade, metas, tarefas, hábitos, agenda, finanças e notas, num lugar só. O tempo que você cronometra em cada atividade vira progresso nas suas metas.

Open source, feito em Swift (SwiftUI). Os dados ficam só no seu Mac, num arquivo JSON legível.

## O que já funciona

**Cronômetro** (inspirado no Yeolpumta):

- Atividades coloridas; um clique inicia, outro pausa. Trocar de atividade fecha a sessão anterior.
- Tempo do dia sempre na barra de menu, com painel para iniciar e pausar sem abrir a janela.
- Linha do tempo do dia (0 h a 24 h) com um bloco para cada sessão.
- Meta diária de tempo focado, com barra de progresso.
- Pausa automática quando você fica sem usar o Mac (padrão: 10 min) ou quando ele entra em repouso. O tempo parado não conta.
- Histórico por dia, com edição e inclusão manual de sessões.
- Estatísticas de 7 e 30 dias por atividade.

**Metas:**

- Meta com alvo em horas, prazo e data de início.
- Você escolhe quais atividades contam para cada meta; o tempo cronometrado nelas vira progresso.
- Barra de progresso, ritmo semanal necessário para chegar no prazo e quanto você fez nesta semana.

**Tarefas:**

- Listas Hoje (inclui atrasadas), Próximas e Concluídas.
- Adição rápida com Enter, prazo, prioridade, notas e ligação com uma meta.
- O cartão da meta mostra quantas tarefas ligadas já foram concluídas.

**Hábitos:**

- Check diário, sequência atual e taxa dos últimos 30 dias.
- Calendário de constância das últimas 12 semanas; clique num dia para marcar ou desmarcar.
- Marcação automática pelo cronômetro (ex.: "Ler 30 min" fica feito quando Leitura passa de 30 min no dia).

**Hoje e Agenda:**

- Tela "Hoje" com as reuniões do dia, a linha do tempo (reuniões em cima, tempo cronometrado embaixo), tarefas de hoje, hábitos e atividades.
- Tela "Agenda" com os próximos 7 dias.
- Lê o Google Agenda (ou qualquer agenda que exporte iCal) pelo link secreto colado nos Ajustes, com eventos recorrentes, exceções e eventos cancelados. Atualiza a cada 15 min e guarda uma cópia para usar sem internet.

**Finanças:**

- Lançamentos manuais de despesas e receitas, com categoria.
- Resumo do mês (receitas, despesas, saldo) e orçamento mensal por categoria, com aviso quando passa do limite.
- Importação de extrato OFX ou CSV (formato brasileiro ou americano, inclusive o CSV da Nubank). Importar o mesmo arquivo de novo não duplica nada, e a categoria de um lançamento parecido é reaproveitada.

**Notas:**

- Editor Markdown que se formata enquanto você digita (títulos, negrito, itálico, código, citações, listas), com os símbolos apagados, como no Obsidian.
- Digite `/` no começo da linha para inserir título, lista, checklist, citação, código ou divisória. Enter continua a lista; clique no `[ ]` para marcar.
- `[[Nome]]` liga notas entre si e também a metas e tarefas. Clicar no link abre a nota (ou cria, se ainda não existir); embaixo aparece "Mencionada em" com as notas que apontam para esta.
- Grafo de conexões: notas, metas e tarefas ligadas pelos links. Arraste nós, mova o fundo, use pinça para zoom e clique para abrir.
- Exportar a nota em PDF (A4, com a formatação e sem os símbolos de Markdown).
- Cada nota é um arquivo `.md` numa pasta que você escolhe nos Ajustes; dá para abrir a mesma pasta como cofre no Obsidian. Renomear uma nota atualiza os links nas outras.

## Como rodar

Precisa de macOS 14 (Sonoma) ou mais novo e Xcode 16.

- **No Xcode:** abra a pasta do projeto (ou o `Package.swift`), escolha o esquema `Organizador` e aperte ⌘R.
- **No terminal:** `swift run Organizador`
- **Gerar o app:** `./scripts/build-app.sh` cria `dist/Organizador.app`, que você pode arrastar para Aplicativos.

Testes: `swift test`.

## Estrutura

| Pasta | O que tem |
| --- | --- |
| `Sources/OrganizadorCore` | Regras sem interface: modelos, cronômetro, estatísticas, metas, tarefas, hábitos, agenda iCal, finanças, notas e grafo, salvamento em JSON |
| `Sources/Organizador` | O app SwiftUI: janela, barra de menu, ajustes |
| `Tests/OrganizadorCoreTests` | Testes do núcleo |

Os dados ficam em `~/Library/Application Support/Organizador/data.json` e as notas, por padrão, em `~/Library/Application Support/Organizador/Notas/`.

## Licença

[MIT](LICENSE)
