# Tempo por área: agenda, tarefas e cronômetro ligados

Data: 2026-10-28 · Status: rascunho para aprovação

## Por que

Hoje o app tem três coisas soltas que não se conhecem: **compromisso** (vem do iCal, só é mostrado), **tarefa** (checklist ligado a objetivo) e **sessão** (tempo cronometrado numa "área"). Só a sessão conta tempo, e só se o usuário lembrar de dar play. O usuário nunca chegou a contabilizar tempo de verdade por causa disso.

O que ele quer: **uma coisa só vista de vários ângulos.** "Aula de CS229 terça 14h" está na agenda, aparece no dia, conta 1h30 em Universidade › CS229 e soma no objetivo, sem cadastrar nada duas vezes. E, quando quiser, ele mesmo dá play em CS229 (estilo YPT) para ver quanto estudou na semana.

Sucesso = abrir o app de manhã, ver o dia, e no fim da semana saber quanto tempo foi para cada área sem ter feito trabalho de contabilidade.

## Conceitos

- **Área** (nova, grande): criada pelo usuário, com nome e cor. Ex.: Pessoal, Universidade, Trabalho, Desenvolvimento Técnico.
- **Atividade**: o que hoje o app chama de "área" (`Activity`). Passa a pertencer a uma área. Ex.: CS229 dentro de Universidade. Continua ligável a um objetivo, como hoje.
- Tempo pode cair numa **atividade** (sobe para a área dela) ou **direto na área** (aparece como "Sem atividade" no relatório).
- O tempo vem de duas fontes:
  1. **Agenda**: compromisso atribuído conta sozinho a duração quando o horário passa.
  2. **Cronômetro**: play manual numa atividade (ou numa tarefa, que sobe para a atividade dela).

## Comportamento decidido com o usuário

### Agenda contando sozinha
- O usuário atribui um compromisso a uma área **ou** a uma atividade (ele escolhe o nível).
- Compromisso recorrente: atribui uma vez, vale para todas as ocorrências. *(minha decisão)*
- Compromisso atribuído conta a duração planejada quando o horário termina.
- Se não foi assim, o usuário sinaliza naquela ocorrência: **"terminou às HH:MM"** (ajusta o fim) ou **"não fiz"** (zera).
- Compromisso sem atribuição não conta; aparece com o botão "Escolher área".

### Tela Hoje (substitui Início e Agenda)
Mockup aprovado: `.superpowers/brainstorm/86854-1793208995/content/hoje-v3.html`.
1. **Rodando agora** (só quando há cronômetro rodando): nome, "Área › Atividade", tempo grande, botão Pausar.
2. **Agenda** — "Conta sozinho quando o horário passa." Compromissos do dia em ordem de horário: faixa "14:00–15:30", título, "Área › Atividade". À direita: "✓ 1h30" se já contou, "agora" se em andamento, "Escolher área" se sem atribuição, e menu "⋯" (Terminou antes / Não fiz / Mudar área). Compromissos passados ficam esmaecidos. Sem botão de play.
3. **A fazer** — "Mais importante primeiro." Tarefas de hoje (incluindo atrasadas) ordenadas por prioridade. Caixa para concluir, título, "Área › Atividade", tempo acumulado (só se > 0) e botão "Começar". Última linha: "+ Nova tarefa… (Enter)".
4. **Card "Sua semana até agora"** com total, barra dividida pelas cores das áreas, legenda curta e "Ver tudo ›" para o Relatório.

O que a Home atual tem e não aparece acima (frentes/objetivos parados, hábitos do dia, caixa "No que você vai trabalhar agora?") fica a cargo do builder: manter abaixo, de forma compacta, ou mover — sem perder o aviso de objetivos parados.

### Cronômetro (continua, estilo YPT)
O usuário quer o play manual a um clique. A tela continua igual, com uma mudança: as atividades aparecem **agrupadas sob as áreas**, cada área com seu total de hoje. Deve ser possível dar play também direto na área (tempo "Sem atividade"). *(minha decisão, para o caso de compromisso atribuído só à área ter equivalente manual)*

### Relatório (tela nova)
Design pronto no Claude Design, projeto `e39bb2e9-0e93-460d-8ed4-1a4b02b83227` (`ui_kits/organizador/ReportScreen.jsx`, `components/time/AreaTimeRow.jsx`, `components/core/SegmentedControl.jsx`).
- Cabeçalho: "RELATÓRIO" / "Seu tempo" / "27 out – 2 nov · 18h40".
- Seletor Semana / Mês / Ano / Total (padrão Semana). Semana segue a semana do calendário do app (`Stats.week`). Total = desde a primeira sessão.
- Lista de áreas da maior para a menor: bolinha de cor, nome, horas ("18h40", "6h", "30min"), barra proporcional ao total do período. Clicar expande as atividades (maior → menor) com barra fina proporcional à área. "Sem atividade" em texto secundário.
- Vazio: "Nenhum tempo registrado neste período."
- Só leitura: sem editar, sem iniciar.
- O projeto do Claude Design é acessível pela ferramenta DesignSync (`get_file`); a referência visual são esses arquivos, não o mockup local.
- Entra na barra lateral como "Relatório".

### Tarefas (tela simples, decidida pelo usuário)
O Hoje mostra só o dia. Uma tela de Tarefas enxuta cobre o resto: **Próximas** (com data futura ou sem data) e **Concluídas**, com adição rápida, edição (prazo, prioridade, área/atividade, objetivo) e exclusão. Visual igual ao do Hoje. As tarefas de hoje aparecem só no Hoje.

Compromissos de outros dias *(minha decisão)*: sem tela própria. Compromisso recorrente já vem atribuído pela regra; compromisso avulso futuro é atribuído no dia, pelo Hoje. Compromissos de dias passados já viraram sessões e são corrigidos onde as sessões já são editadas hoje (Cronômetro / página da atividade).

### Barra lateral
Fica: Buscar, Hoje, Cronômetro, Tarefas, Relatório, Hábitos, Notas, Finanças, objetivos, recentes, Ajustes. Saem Início e Agenda.

## Objetivos, não-objetivos, anti-objetivos

**Objetivos**
- Tempo da agenda entra sem ação do usuário além de atribuir uma vez.
- Uma única fonte de verdade de tempo para relatório, objetivos, totais do dia e meta diária.
- App mais conciso: menos telas, cada uma com um papel claro.

**Não-objetivos**
- Tarefas com horário marcado (tarefa continua só com dia). O que tem horário vem da agenda.
- Editar compromissos do Google pelo app.
- "Pretendido" no card da semana — o usuário não decidiu; fica fora.
- Gráficos além de barras simples.

**Anti-objetivos (falha mesmo que funcione)**
- Contar o mesmo tempo duas vezes.
- Exigir que o usuário atribua cada ocorrência de um compromisso recorrente.
- Tela que precisa de explicação: cada controle tem nome, nada de ícone solto sem rótulo.
- Perder dados existentes (sessões, atividades, tarefas, objetivos).

## Restrições

- Swift/SwiftUI, macOS 14, código puro em `OrganizadorCore` com testes; UI em `Organizador`.
- Dados no JSON único (`AppData`); arquivos antigos têm que continuar abrindo (padrão `decodeIfPresent` já usado).
- Visual segue `Theme` em `Look.swift` e o design system do Claude Design (tema escuro, Inter, cartões `#1d2225` raio 14, destaque menta, números tabulares, sem emoji na UI).
- Commits atômicos, sem linha de co-autoria.

## Decisões minhas (o usuário pode trocar)

- **Migração**: atividades existentes ficam numa área "Sem área" até o usuário movê-las; nada some do relatório.
- **Sobreposição**: se o cronômetro rodou durante um compromisso atribuído, a sessão manual vale para aquele trecho e o compromisso conta só o resto. Evita contagem dupla.
- **Eventos exportados pelo próprio app** (prefixo "⏱", criados quando "exportar sessões para o Calendário" está ligado) são ignorados ao ler o iCal, para não voltarem como compromisso e contarem de novo.
- **Tarefa ↔ tempo**: a tarefa ganha área/atividade; "Começar" numa tarefa inicia o cronômetro na atividade (ou área) dela e a sessão guarda a tarefa, para mostrar o tempo acumulado na linha. Tarefa sem área pede para escolher ao começar.
- Tarefas mantêm o vínculo opcional com objetivo que já têm.
- **Tempo da agenda fica congelado**: quando o horário de um compromisso atribuído passa, ele vira uma sessão gravada (marcada como vinda da agenda, com o UID e a data da ocorrência para não duplicar). Se o evento some do feed depois, ou o link do iCal é removido, o tempo continua. "Terminou antes" / "Não fiz" editam ou apagam essa sessão, inclusive em dias passados.
- **Dois compromissos atribuídos ao mesmo tempo**: o que começa primeiro fica com o trecho em comum; em empate, o que aparece primeiro no feed.
- **Hábitos "por cronômetro"** (`Habit.autoActivityID`) contam o tempo da agenda também, já que é a mesma fonte de tempo.
- **Exportar sessões para o Calendário** não exporta sessões vindas da agenda: elas já são um evento lá.
- **"Sem área"** é um grupo fixo, não uma área de verdade: `Activity` tem área opcional, e o grupo só aparece (no relatório e no cronômetro) enquanto houver atividade sem área.

## Fica com o builder

- Modelagem: nome do novo tipo (área grande), como representar tempo direto na área, se o tempo da agenda é calculado na hora ou gravado como sessão, onde ficam atribuições por UID e ajustes por ocorrência.
- Como objetivos passam a somar tempo vindo da agenda (devem somar, via atividade).
- Onde editar áreas (criar, renomear, cor, mover atividade) — o mais simples que caiba no app.
- Ordem de entrega. Sugestão: (1) áreas + relatório, (2) cronômetro agrupado, (3) agenda contando sozinha, (4) tela Hoje, Tarefas enxuta e limpeza da barra lateral.
