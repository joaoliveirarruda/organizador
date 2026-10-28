import OrganizadorCore
import SwiftUI
import UniformTypeIdentifiers

struct FinanceScreen: View {
    @Environment(AppModel.self) private var model
    @State private var monthStart = Date()
    @State private var editingTransaction: MoneyTransaction?
    @State private var addingTransaction = false
    @State private var editingCategories = false
    @State private var choosingFile = false
    @State private var pendingImport: PendingImport?

    var body: some View {
        let month = model.month(containing: monthStart)
        let summary = model.monthSummary(month)
        let transactions = model.transactions(in: month)

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                    Text(month.start.formatted(.dateTime.month(.wide).year()).capitalized)
                        .font(.title2.weight(.semibold))
                        .frame(minWidth: 200)
                    Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                    Spacer()
                }
                .buttonStyle(.borderless)

                HStack(spacing: 12) {
                    SummaryCard(title: "Receitas", cents: summary.incomeCents, color: .green)
                    SummaryCard(title: "Despesas", cents: summary.expenseCents, color: .red)
                    SummaryCard(
                        title: "Saldo",
                        cents: summary.balanceCents,
                        color: summary.balanceCents >= 0 ? .primary : .red
                    )
                }

                BudgetSection(summary: summary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Lançamentos").font(.headline)
                    if transactions.isEmpty {
                        Text("Nenhum lançamento neste mês. Adicione um ou importe o extrato do banco.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(transactions) { transaction in
                        TransactionRow(transaction: transaction)
                            .contentShape(Rectangle())
                            .onTapGesture { editingTransaction = transaction }
                            .contextMenu {
                                Button("Editar") { editingTransaction = transaction }
                                Button("Excluir", role: .destructive) { model.deleteTransaction(transaction.id) }
                            }
                        Divider()
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .navigationTitle("Finanças")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    editingCategories = true
                } label: {
                    Label("Categorias e orçamento", systemImage: "tag")
                }
                Button {
                    choosingFile = true
                } label: {
                    Label("Importar extrato", systemImage: "square.and.arrow.down")
                }
                Button {
                    addingTransaction = true
                } label: {
                    Label("Novo lançamento", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $addingTransaction) {
            TransactionEditor(transaction: nil, defaultDate: defaultDate(in: month))
        }
        .sheet(item: $editingTransaction) { transaction in
            TransactionEditor(transaction: transaction, defaultDate: transaction.date)
        }
        .sheet(isPresented: $editingCategories) {
            CategoriesEditor()
        }
        .sheet(item: $pendingImport) { pending in
            ImportPreview(pending: pending)
        }
        .fileImporter(
            isPresented: $choosingFile,
            allowedContentTypes: [UTType(filenameExtension: "ofx") ?? .data, .commaSeparatedText, .plainText, .data]
        ) { result in
            if case .success(let url) = result { load(url) }
        }
    }

    private func shiftMonth(_ months: Int) {
        monthStart = model.calendar.date(byAdding: .month, value: months, to: monthStart) ?? monthStart
    }

    /// Today when looking at the current month, otherwise the first day of the shown month.
    private func defaultDate(in month: DateInterval) -> Date {
        month.contains(Date()) ? Date() : month.start
    }

    private func load(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            // Brazilian banks often export OFX in Windows-1252.
            let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .windowsCP1252)
                ?? String(data: data, encoding: .isoLatin1)
                ?? ""
            pendingImport = PendingImport(fileName: url.lastPathComponent, text: text)
        } catch {
            model.lastError = "Não foi possível ler o arquivo: \(error.localizedDescription)"
        }
    }
}

private struct SummaryCard: View {
    let title: String
    let cents: Int
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout).foregroundStyle(.secondary)
            Text(Finance.format(cents: cents))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.06)))
    }
}

/// Spending per expense category against its monthly budget.
private struct BudgetSection: View {
    @Environment(AppModel.self) private var model
    let summary: MonthSummary

    var body: some View {
        let rows = model.data.financeCategories
            .filter { !$0.isIncome }
            .map { (category: $0, spent: summary.expenseByCategory[$0.id] ?? 0) }
            .filter { $0.spent > 0 || $0.category.monthlyBudgetCents != nil }
            .sorted { $0.spent > $1.spent }
        let uncategorized = summary.expenseByCategory[nil] ?? 0

        if !rows.isEmpty || uncategorized > 0 {
            VStack(alignment: .leading, spacing: 10) {
                Text("Gastos por categoria").font(.headline)
                ForEach(rows, id: \.category.id) { row in
                    BudgetRow(
                        name: row.category.name,
                        colorHex: row.category.colorHex,
                        spent: row.spent,
                        budget: row.category.monthlyBudgetCents
                    )
                }
                if uncategorized > 0 {
                    BudgetRow(name: "Sem categoria", colorHex: "#778CA3", spent: uncategorized, budget: nil)
                }
            }
        }
    }
}

private struct BudgetRow: View {
    let name: String
    let colorHex: String
    let spent: Int
    let budget: Int?

    var body: some View {
        let over = budget.map { spent > $0 } ?? false
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle().fill(Color(hex: colorHex)).frame(width: 10, height: 10)
                Text(name)
                Spacer()
                Text(budget.map { "\(Finance.format(cents: spent)) de \(Finance.format(cents: $0))" }
                    ?? Finance.format(cents: spent))
                    .monospacedDigit()
                    .foregroundStyle(over ? Color.red : Color.secondary)
            }
            if let budget, budget > 0 {
                ProgressView(value: min(1, Double(spent) / Double(budget)))
                    .tint(over ? Color.red : Color(hex: colorHex))
            }
        }
    }
}

private struct TransactionRow: View {
    @Environment(AppModel.self) private var model
    let transaction: MoneyTransaction

    var body: some View {
        HStack(spacing: 12) {
            Text(transaction.date.formatted(.dateTime.day().month(.abbreviated)))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(transaction.description)
                .lineLimit(1)
            Spacer()
            Menu {
                Button("Sem categoria") { model.setCategory(nil, forTransaction: transaction.id) }
                ForEach(model.data.financeCategories.filter { $0.isIncome == !transaction.isExpense }) { category in
                    Button(category.name) { model.setCategory(category.id, forTransaction: transaction.id) }
                }
            } label: {
                Text(model.financeCategory(transaction.categoryID)?.name ?? "Categorizar")
                    .foregroundStyle(transaction.categoryID == nil ? Color.orange : Color.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Text(Finance.format(cents: transaction.amountCents))
                .monospacedDigit()
                .foregroundStyle(transaction.isExpense ? Color.primary : Color.green)
                .frame(minWidth: 110, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }
}

private struct TransactionEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let transaction: MoneyTransaction?
    @State private var description: String
    @State private var amountText: String
    @State private var isExpense: Bool
    @State private var date: Date
    @State private var categoryID: UUID?

    init(transaction: MoneyTransaction?, defaultDate: Date) {
        self.transaction = transaction
        _description = State(initialValue: transaction?.description ?? "")
        _amountText = State(initialValue: transaction.map {
            String(format: "%.2f", Double(abs($0.amountCents)) / 100).replacingOccurrences(of: ".", with: ",")
        } ?? "")
        _isExpense = State(initialValue: transaction?.isExpense ?? true)
        _date = State(initialValue: transaction?.date ?? defaultDate)
        _categoryID = State(initialValue: transaction?.categoryID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(transaction == nil ? "Novo lançamento" : "Editar lançamento").font(.headline)
            Form {
                Picker("Tipo", selection: $isExpense) {
                    Text("Despesa").tag(true)
                    Text("Receita").tag(false)
                }
                .pickerStyle(.segmented)
                TextField("Descrição", text: $description)
                TextField("Valor (R$)", text: $amountText)
                DatePicker("Data", selection: $date, displayedComponents: .date)
                Picker("Categoria", selection: $categoryID) {
                    Text("Sem categoria").tag(UUID?.none)
                    ForEach(model.data.financeCategories.filter { $0.isIncome == !isExpense }) { category in
                        Text(category.name).tag(Optional(category.id))
                    }
                }
            }
            HStack {
                if let transaction {
                    Button("Excluir", role: .destructive) {
                        model.deleteTransaction(transaction.id)
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Salvar") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(cents == nil || description.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onChange(of: isExpense) {
            if let category = model.financeCategory(categoryID), category.isIncome == isExpense {
                categoryID = nil
            }
        }
    }

    /// The typed value as positive cents.
    private var cents: Int? {
        guard let value = StatementImporter.parseAmountCents(amountText), value != 0 else { return nil }
        return abs(value)
    }

    private func save() {
        guard let cents else { return }
        var saved = transaction ?? MoneyTransaction(date: date, amountCents: 0, description: "")
        saved.description = description.trimmingCharacters(in: .whitespaces)
        saved.amountCents = isExpense ? -cents : cents
        saved.date = model.calendar.startOfDay(for: date)
        saved.categoryID = categoryID
        model.saveTransaction(saved)
        dismiss()
    }
}

private struct CategoriesEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [CategoryDraft] = []

    struct CategoryDraft: Identifiable {
        var category: FinanceCategory
        var budgetText: String
        var id: UUID { category.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Categorias e orçamento mensal").font(.headline)
            List {
                Section("Despesas") {
                    ForEach(drafts.filter { $0.category.isIncome == false }) { draft in
                        HStack {
                            Circle().fill(Color(hex: draft.category.colorHex)).frame(width: 10, height: 10)
                            TextField("Nome", text: binding(draft.id).category.name)
                            TextField("Orçamento (R$)", text: binding(draft.id).budgetText)
                                .frame(width: 130)
                                .multilineTextAlignment(.trailing)
                            removeButton(draft.id)
                        }
                    }
                    Button("Nova categoria de despesa") { add(isIncome: false) }
                }
                Section("Receitas") {
                    ForEach(drafts.filter { $0.category.isIncome == true }) { draft in
                        HStack {
                            Circle().fill(Color(hex: draft.category.colorHex)).frame(width: 10, height: 10)
                            TextField("Nome", text: binding(draft.id).category.name)
                            removeButton(draft.id)
                        }
                    }
                    Button("Nova categoria de receita") { add(isIncome: true) }
                }
            }
            .frame(minHeight: 420)
            Text("Deixe o orçamento em branco para não ter limite. Lançamentos de uma categoria removida ficam sem categoria.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Salvar") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            drafts = model.data.financeCategories.map { category in
                CategoryDraft(
                    category: category,
                    budgetText: category.monthlyBudgetCents.map {
                        String(format: "%.2f", Double($0) / 100).replacingOccurrences(of: ".", with: ",")
                    } ?? ""
                )
            }
        }
    }

    /// A binding to one draft by id, so removing a row never leaves a stale index behind.
    private func binding(_ id: UUID) -> Binding<CategoryDraft> {
        Binding(
            get: { drafts.first { $0.id == id } ?? CategoryDraft(category: FinanceCategory(id: id, name: "", colorHex: ""), budgetText: "") },
            set: { value in
                if let index = drafts.firstIndex(where: { $0.id == id }) { drafts[index] = value }
            }
        )
    }

    private func removeButton(_ id: UUID) -> some View {
        Button {
            drafts.removeAll { $0.id == id }
        } label: {
            Image(systemName: "minus.circle")
        }
        .buttonStyle(.borderless)
        .help("Remover categoria")
    }

    private func add(isIncome: Bool) {
        let color = Palette.colors[drafts.count % Palette.colors.count]
        drafts.append(CategoryDraft(
            category: FinanceCategory(name: isIncome ? "Nova receita" : "Nova categoria", colorHex: color, isIncome: isIncome),
            budgetText: ""
        ))
    }

    private func save() {
        let categories = drafts.map { draft -> FinanceCategory in
            var category = draft.category
            category.name = category.name.trimmingCharacters(in: .whitespaces)
            let budget = StatementImporter.parseAmountCents(draft.budgetText).map(abs)
            category.monthlyBudgetCents = category.isIncome ? nil : (budget == 0 ? nil : budget)
            return category
        }
        .filter { !$0.name.isEmpty }
        model.saveFinanceCategories(categories)
        dismiss()
    }
}

struct PendingImport: Identifiable {
    let id = UUID()
    let fileName: String
    let text: String
}

/// Shows what a statement will add before importing it.
private struct ImportPreview: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let pending: PendingImport
    @State private var invertSigns = false

    var body: some View {
        let parsed = Result { try StatementImporter.parse(pending.text, invertSigns: invertSigns, calendar: model.calendar) }
        let lines = (try? parsed.get()) ?? []
        let preview = StatementImporter.newTransactions(from: lines, existing: model.data.transactions)

        VStack(alignment: .leading, spacing: 14) {
            Text("Importar \(pending.fileName)").font(.headline)

            if case .failure(let error) = parsed {
                Text(error.localizedDescription).foregroundStyle(.red)
            } else if lines.isEmpty {
                Text("Não encontrei lançamentos neste arquivo.").foregroundStyle(.secondary)
            } else {
                Text("\(preview.transactions.count) lançamentos novos · \(preview.duplicates) já importados antes")
                Toggle("Inverter sinais (fatura de cartão que lista compras como valor positivo)", isOn: $invertSigns)
                List(preview.transactions.prefix(50)) { transaction in
                    HStack {
                        Text(transaction.date.formatted(.dateTime.day().month(.abbreviated)))
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .leading)
                        Text(transaction.description).lineLimit(1)
                        Spacer()
                        if let category = model.financeCategory(transaction.categoryID) {
                            Text(category.name).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(Finance.format(cents: transaction.amountCents))
                            .monospacedDigit()
                            .foregroundStyle(transaction.isExpense ? Color.primary : Color.green)
                    }
                }
                .frame(minHeight: 260)
            }

            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Importar \(preview.transactions.count)") {
                    model.importStatement(lines)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(preview.transactions.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 620)
    }
}
