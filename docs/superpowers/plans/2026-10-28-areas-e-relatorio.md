# Áreas e Relatório: plano de implementação (fase 1 de 4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Criar as áreas grandes (Pessoal, Universidade…) acima das atividades e a tela Relatório que mostra o tempo por área e por atividade em Semana / Mês / Ano / Total.

**Architecture:** Novo tipo `Area` no `OrganizadorCore`; `Activity` ganha `areaID` opcional. Um `TimeReport` puro agrupa os `TimeSpan` existentes por área → atividade num período. O app ganha CRUD de áreas (Ajustes + seletor no editor de atividade), a rota `.report` e a `ReportScreen`. As fases 2–4 do spec (cronômetro agrupado e tempo direto na área, agenda contando sozinha, tela Hoje/Tarefas) terão planos próprios.

**Tech Stack:** Swift 5.10, SwiftUI, macOS 14, XCTest.

**Spec:** `docs/superpowers/specs/2026-10-28-tempo-por-area-design.md` (seções Conceitos, Relatório, Decisões minhas → "Sem área"). Referência visual: projeto Claude Design `e39bb2e9-0e93-460d-8ed4-1a4b02b83227`, arquivos `ui_kits/organizador/ReportScreen.jsx`, `components/time/AreaTimeRow.jsx`, `components/core/SegmentedControl.jsx` (ler com DesignSync `get_file`).

## Global Constraints

- Arquivos antigos de dados têm que continuar abrindo: campos novos com `decodeIfPresent` / opcionais.
- Lógica pura em `Sources/OrganizadorCore` com teste; UI em `Sources/Organizador` sem teste.
- Visual: `Theme` (`Look.swift`), `ScreenHeading`, `PageSection`, Inter, números com `.monospacedDigit()`, nada de emoji na UI.
- Cor nunca é a única informação: toda barra tem o nome escrito ao lado.
- Na UI, **"área"** passa a ser o grupo grande e **"atividade"** o que hoje é `Activity`.
- Commits atômicos, sem linha `Co-Authored-By`.
- Testes: `swift test` na raiz; build do app: `swift build`.

## Review Focus

1. Sessão que atravessa o início/fim do período (ex.: domingo 23h → segunda 1h) deve contar só a parte de dentro. → teste em Task 2.
2. Cronômetro rodando agora entra no relatório (já está em `AppModel.spans`). → teste em Task 2.
3. Atividade arquivada continua contando no relatório (o tempo aconteceu). → teste em Task 2.
4. Apagar uma área não apaga tempo: as atividades dela caem em "Sem área". → teste em Task 2 (área inexistente = Sem área) e comportamento em Task 3.
5. Período sem tempo mostra "Nenhum tempo registrado neste período." e Total sem nenhuma sessão não quebra. → teste em Task 2.

---

### Task 1: Modelo `Area` e `Activity.areaID`

**Files:**
- Modify: `Sources/OrganizadorCore/Models.swift`
- Test: `Tests/OrganizadorCoreTests/OrganizadorCoreTests.swift` (nova classe `AreaModelTests` no fim)

**Interfaces:**
- Produces:
  - `public struct Area: Identifiable, Codable, Hashable, Sendable { id: UUID; name: String; colorHex: String; createdAt: Date }` com `init(id: UUID = UUID(), name: String, colorHex: String, createdAt: Date = Date())`.
  - `Activity.areaID: UUID?` (novo parâmetro `areaID: UUID? = nil` no init, depois de `goalID`).
  - `AppData.areas: [Area]` (parâmetro `areas: [Area] = []` no init, depois de `activities`; CodingKey `areas`; decode com `decodeIfPresent ?? []`).

- [ ] **Step 1: Testes que falham**

```swift
final class AreaModelTests: XCTestCase {
    func testOldFileWithoutAreasStillLoads() throws {
        let json = #"{"schemaVersion":2,"activities":[{"id":"\#(UUID().uuidString)","name":"CS229","colorHex":"#2D98DA","isArchived":false,"createdAt":0}]}"#
        let data = try JSONDecoder().decode(AppData.self, from: Data(json.utf8))
        XCTAssertEqual(data.areas, [])
        XCTAssertNil(data.activities.first?.areaID)
    }

    func testAreaAndActivityLinkRoundTrip() throws {
        let area = Area(name: "Universidade", colorHex: "#2D98DA")
        let original = AppData(activities: [Activity(name: "CS229", colorHex: "#2D98DA", areaID: area.id)], areas: [area])
        let decoded = try JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.areas, [area])
        XCTAssertEqual(decoded.activities.first?.areaID, area.id)
    }
}
```

- [ ] **Step 2:** `swift test --filter AreaModelTests` → FAIL (não compila: `Area` não existe).
- [ ] **Step 3:** Implementar as interfaces acima em `Models.swift`. `Activity` usa Codable sintetizado, então `areaID` opcional já decodifica ausente como `nil`. Doc comment em `Area`: "A big area (`Area`) in the UI, e.g. "Universidade", grouping activities."; atualizar o comentário de `Activity` para dizer que na UI ela é uma "atividade".
- [ ] **Step 4:** `swift test` → todos passam.
- [ ] **Step 5: Commit** — `git commit -m "Áreas grandes no modelo: Area e Activity.areaID"`

---

### Task 2: `TimeReport` e formato compacto de horas

**Files:**
- Create: `Sources/OrganizadorCore/TimeReport.swift`
- Modify: `Sources/OrganizadorCore/DurationFormat.swift`
- Test: `Tests/OrganizadorCoreTests/OrganizadorCoreTests.swift` (classes `TimeReportTests`, e casos novos em `DurationFormat`)

**Interfaces:**
- Consumes: `Area`, `Activity.areaID` (Task 1); `TimeSpan`, `Stats.week`, `Stats.overlap`, `Stats.totalsByActivity` (existentes).
- Produces:
  - `public enum ReportPeriod: String, CaseIterable, Sendable { case week = "Semana", month = "Mês", year = "Ano", total = "Total" }`
  - `public static func interval(_ period: ReportPeriod, spans: [TimeSpan], now: Date, calendar: Calendar) -> DateInterval?` em `enum TimeReport`. Semana = `Stats.week`; Mês/Ano = `calendar.dateInterval(of: .month / .year, for: now)`; Total = do menor `start` dos spans até `now`, `nil` se não há spans.
  - `public struct ActivityTotal: Hashable, Sendable { activity: Activity; seconds: TimeInterval }`
  - `public struct AreaTotal: Hashable, Sendable { area: Area?; seconds: TimeInterval; activities: [ActivityTotal] }` — `area == nil` é o grupo "Sem área".
  - `public static func build(spans: [TimeSpan], activities: [Activity], areas: [Area], in interval: DateInterval) -> [AreaTotal]` — inclui atividades arquivadas; atividade cujo `areaID` não existe em `areas` vai para Sem área; descarta grupos e atividades com 0s; áreas ordenadas por segundos desc, atividades idem; empate pelo nome.
  - `DurationFormat.compact(_ seconds: TimeInterval) -> String` — "18h40", "6h", "30min" (minutos com 2 dígitos).

- [ ] **Step 1: Testes que falham** (datas fixas, `Calendar(identifier: .gregorian)` com `timeZone = TimeZone(identifier: "UTC")!`, `firstWeekday = 2`)
  - `testCompactFormat`: `compact(18*3600 + 40*60) == "18h40"`, `compact(6*3600) == "6h"`, `compact(30*60) == "30min"`, `compact(3600 + 5*60) == "1h05"`.
  - `testGroupsByAreaLargestFirst`: Universidade (CS229 2h, Cálculo 1h), Trabalho (Projeto 4h) → `[Trabalho 4h, Universidade 3h]`, Universidade.activities `[CS229, Cálculo]`.
  - `testActivityWithoutOrMissingAreaGoesToSemArea`: uma atividade com `areaID nil` e outra com `areaID` de área inexistente → um `AreaTotal` com `area == nil` somando as duas.
  - `testArchivedActivityStillCounts`.
  - `testSpanCrossingPeriodStartCountsOnlyInside`: span de domingo 23:00 a segunda 01:00, intervalo da semana que começa segunda → 1h.
  - `testEmptyIntervalReturnsEmpty` e `testTotalIntervalIsNilWithoutSpans`.
  - `testTotalIntervalStartsAtEarliestSpan`.
- [ ] **Step 2:** `swift test --filter TimeReportTests` → FAIL (não compila).
- [ ] **Step 3:** Implementar as interfaces acima. `build` usa `Stats.totalsByActivity` e agrupa por `areaID` válido.
- [ ] **Step 4:** `swift test` → todos passam.
- [ ] **Step 5: Commit** — `git commit -m "Relatório de tempo por área e atividade no core"`

---

### Task 3: Áreas no app (criar, editar, apagar, ligar atividade)

**Files:**
- Modify: `Sources/Organizador/AppModel.swift` (nova seção `// MARK: - Areas` depois de Activities)
- Create: `Sources/Organizador/AreaEditor.swift`
- Modify: `Sources/Organizador/TimerScreen.swift` (`ActivityEditor`: seletor de área)
- Modify: `Sources/Organizador/PreferencesView.swift` (linha "Áreas" em Preferências + seção)

**Interfaces:**
- Consumes: `Area`, `Activity.areaID`, `AppData.areas` (Task 1).
- Produces (em `AppModel`):
  - `var areas: [Area]` — ordenadas por nome.
  - `func area(_ id: UUID?) -> Area?`
  - `@discardableResult func addArea(name: String, colorHex: String) -> Area`
  - `func updateArea(_ area: Area)`
  - `func deleteArea(_ id: UUID)` — remove a área e põe `areaID = nil` nas atividades dela; não toca em sessões.
  - `struct AreaEditor: View { init(area: Area?, onSave: ((Area) -> Void)? = nil) }` — sheet igual ao `ActivityEditor`: título "Nova área"/"Editar área", campo Nome, as 8 cores de `Palette.colors`, Cancelar/Salvar; `onSave` recebe a área salva.

- [ ] **Step 1:** Implementar os métodos de `AppModel` (cada um chama `persist()`).
- [ ] **Step 2:** Criar `AreaEditor`.
- [ ] **Step 3:** No `ActivityEditor`, adicionar `Picker("Área", selection: $areaID)` com "Sem área", as áreas e uma opção "Nova área…" que abre `AreaEditor` e seleciona a área criada. `save()` grava `areaID`.
- [ ] **Step 4:** Em Ajustes › Preferências, nova linha "Áreas" (abre a seção, como as outras). A seção lista as áreas (bolinha de cor + nome + "N atividades"), clique abre `AreaEditor`, menu de contexto "Apagar" com `confirmationDialog` "Apagar Universidade?" / mensagem "As atividades ficam sem área. O tempo registrado não muda.", e botão "Nova área".
- [ ] **Step 5:** `swift build` → sem erros. Abrir o app (`./scripts/build-app.sh && open dist/Organizador.app`), criar Universidade, ligar CS229 a ela, apagar a área e ver CS229 voltar para "Sem área" no editor.
- [ ] **Step 6: Commit** — `git commit -m "Criar, editar e apagar áreas e ligar atividades a elas"`

---

### Task 4: Tela Relatório

**Files:**
- Create: `Sources/Organizador/ReportScreen.swift`
- Modify: `Sources/Organizador/AppModel.swift` (`func report(_ period: ReportPeriod) -> (interval: DateInterval?, areas: [AreaTotal])`)
- Modify: `Sources/Organizador/ContentView.swift` (`Route.report`, `detail`, linha na barra lateral)

**Interfaces:**
- Consumes: `ReportPeriod`, `TimeReport.interval`, `TimeReport.build`, `AreaTotal`, `ActivityTotal`, `DurationFormat.compact` (Task 2); `areas` (Task 3); `spans`, `calendar`, `now` (existentes).
- Produces: `Route.report`; `struct ReportScreen: View`.

- [ ] **Step 1:** `AppModel.report(_:)` = `TimeReport.interval` + `TimeReport.build(spans: spans, activities: data.activities, areas: data.areas, in:)`; intervalo `nil` → lista vazia.
- [ ] **Step 2:** `ReportScreen`, seguindo `ReportScreen.jsx` / `AreaTimeRow.jsx`:
  - Topo em `HStack(alignment: .bottom)`: `ScreenHeading(section: "Relatório", title: "Seu tempo", subtitle: "<período> · <total compacto>")` e à direita `Picker` `.segmented` com `ReportPeriod.allCases` (padrão `.week`, `@State`).
  - Rótulo do período: Semana "27 out – 2 nov" (dia + mês abreviado minúsculo, `pt_BR`, fim = último dia incluso), Mês "1 – 31 out", Ano "2026", Total "Desde mar 2025".
  - Um `PageSection` sem título com as linhas. Linha de área: chevron (escondido se sem atividades), bolinha 10pt da cor, nome 15/500 ("Sem área" quando `area == nil`, cor `Theme.secondaryText`), horas 15/500 à direita; embaixo barra de 6pt na cor, largura = segundos da área / total do período, recuada sob o nome. Clique expande (uma por vez); expandida ganha fundo `Theme.hover`, raio 10. Atividades: nome 13 + horas 13 secundárias, barra de 3pt proporcional à área, separador `Theme.border` entre elas.
  - Sem linhas: "Nenhum tempo registrado neste período." em `Theme.secondaryText`.
  - Expandir/recolher com animação ease-out de no máximo 0,24s.
  - Cor da área sem área: `Theme.secondaryText`.
- [ ] **Step 3:** `Route.report` → `ReportScreen()`; na barra lateral `SidebarRow(title: "Relatório", symbol: "chart.bar", route: .report)` logo abaixo de Cronômetro.
- [ ] **Step 4:** `swift build`; abrir o app e conferir com dados reais: troca de período, expandir área, estado vazio (Ano anterior não existe; testar Semana sem sessões criando um arquivo de dados vazio ou só olhando com tudo zerado).
- [ ] **Step 5: Commit** — `git commit -m "Tela Relatório com tempo por área e atividade"`

---

### Task 5: "Área" vira "atividade" nos textos de hoje

**Files:**
- Modify: `Sources/Organizador/TimerScreen.swift`, `HomeScreen.swift`, `GoalPage.swift`, `AreaPage.swift`, `Agenda.swift`, `HabitsScreen.swift`, `SearchScreen.swift`, `AppModel.swift`, `PreferencesView.swift`

**Interfaces:** nenhuma; só textos.

- [ ] **Step 1:** Trocar nos textos visíveis toda referência a `Activity` de "área" para "atividade", com o gênero certo. Ex.: "Nova área" → "Nova atividade" (no `ActivityEditor`, `TimerScreen`, `GoalPage`), "Trocar de área" → "Trocar de atividade", "Área removida" → "Atividade removida", "Nenhum (área solta)" → "Nenhum (atividade solta)", "Área solta" → "Atividade solta", "Arquivar área?" → "Arquivar atividade?", `PageSection(title: "Áreas")` do Cronômetro/GoalPage/Busca → "Atividades", "Crie uma área para começar a cronometrar." → "Crie uma atividade para começar a cronometrar.", "Buscar notas, objetivos, áreas e tarefas" → "…atividades e tarefas". Lista completa: `grep -n '"[^"]*[áÁ]rea[^"]*"' Sources/Organizador/*.swift`. Ficam como estão só os textos novos das Tasks 3–4, que falam de áreas grandes.
- [ ] **Step 2:** `swift build`; o grep acima só deve achar textos de `AreaEditor`, da seção Áreas em Ajustes, do seletor "Área" no `ActivityEditor` e do Relatório.
- [ ] **Step 3: Commit** — `git commit -m "Textos: o que era área passa a se chamar atividade"`
