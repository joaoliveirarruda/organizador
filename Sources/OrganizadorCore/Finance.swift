import Foundation

public struct FinanceCategory: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var colorHex: String
    public var isIncome: Bool
    /// Monthly spending limit in cents, for expense categories.
    public var monthlyBudgetCents: Int?

    public init(
        id: UUID = UUID(),
        name: String,
        colorHex: String,
        isIncome: Bool = false,
        monthlyBudgetCents: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.isIncome = isIncome
        self.monthlyBudgetCents = monthlyBudgetCents
    }
}

/// Money in or out. Amounts are integer cents so they never pick up rounding errors;
/// negative means an expense.
public struct MoneyTransaction: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    /// Start of the day the transaction happened.
    public var date: Date
    public var amountCents: Int
    public var description: String
    public var categoryID: UUID?
    /// Identifies a line imported from a bank statement, so importing the same file twice adds nothing.
    public var importKey: String?

    public init(
        id: UUID = UUID(),
        date: Date,
        amountCents: Int,
        description: String,
        categoryID: UUID? = nil,
        importKey: String? = nil
    ) {
        self.id = id
        self.date = date
        self.amountCents = amountCents
        self.description = description
        self.categoryID = categoryID
        self.importKey = importKey
    }

    public var isExpense: Bool { amountCents < 0 }
}

public struct MonthSummary: Hashable, Sendable {
    public var incomeCents: Int
    /// Total spent, as a positive number.
    public var expenseCents: Int
    /// Spent per category (positive), `nil` key for uncategorized.
    public var expenseByCategory: [UUID?: Int]

    public var balanceCents: Int { incomeCents - expenseCents }
}

public enum Finance {
    public static func month(containing date: Date, calendar: Calendar) -> DateInterval {
        calendar.dateInterval(of: .month, for: date) ?? Stats.day(containing: date, calendar: calendar)
    }

    public static func transactions(_ all: [MoneyTransaction], in interval: DateInterval) -> [MoneyTransaction] {
        all.filter { $0.date >= interval.start && $0.date < interval.end }
            .sorted { ($0.date, $0.description) > ($1.date, $1.description) }
    }

    public static func summary(_ all: [MoneyTransaction], in interval: DateInterval) -> MonthSummary {
        var income = 0
        var expense = 0
        var byCategory: [UUID?: Int] = [:]
        for transaction in all where transaction.date >= interval.start && transaction.date < interval.end {
            if transaction.isExpense {
                expense -= transaction.amountCents
                byCategory[transaction.categoryID, default: 0] -= transaction.amountCents
            } else {
                income += transaction.amountCents
            }
        }
        return MonthSummary(incomeCents: income, expenseCents: expense, expenseByCategory: byCategory)
    }

    public static func defaultCategories() -> [FinanceCategory] {
        [
            FinanceCategory(name: "Alimentação", colorHex: "#FA8231"),
            FinanceCategory(name: "Moradia", colorHex: "#8854D0"),
            FinanceCategory(name: "Transporte", colorHex: "#2D98DA"),
            FinanceCategory(name: "Saúde", colorHex: "#20BF6B"),
            FinanceCategory(name: "Lazer", colorHex: "#F7B731"),
            FinanceCategory(name: "Assinaturas", colorHex: "#0FB9B1"),
            FinanceCategory(name: "Educação", colorHex: "#EB3B5A"),
            FinanceCategory(name: "Outros gastos", colorHex: "#778CA3"),
            FinanceCategory(name: "Salário", colorHex: "#20BF6B", isIncome: true),
            FinanceCategory(name: "Outras receitas", colorHex: "#26DE81", isIncome: true),
        ]
    }

    /// "R$ 1.234,56" style text for cents.
    public static func format(cents: Int, locale: Locale = Locale(identifier: "pt_BR")) -> String {
        let value = Decimal(cents) / 100
        return value.formatted(.currency(code: "BRL").locale(locale))
    }
}
