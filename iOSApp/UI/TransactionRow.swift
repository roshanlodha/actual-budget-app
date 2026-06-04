import SwiftUI

struct TransactionRow: View {
    let transaction: Transaction
    let accounts: [Account]
    let payeesById: [String: Payee]
    let categoriesById: [String: Category]
    let currencyCode: String
    var onEdit: ((Transaction) -> Void)?
    var onDelete: ((Transaction) -> Void)?

    var body: some View {
        GlassCard(cornerRadius: 15, isInteractive: true) {
            HStack(spacing: 16) {
                let category = categoriesById[transaction.category ?? ""]
                let iconName = category?.icon ?? ((transaction.amount ?? 0) < 0 ? "arrow.down.left" : "arrow.up.right")
                let iconColor = Color(hex: category?.color ?? "#8D93AB")
                
                Image(systemName: iconName)
                    .font(.footnote.bold())
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(iconColor)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(primaryText())
                        .font(AppTheme.Fonts.headline)
                        .foregroundColor(.primary)
                    Text(secondaryText())
                        .font(AppTheme.Fonts.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(CurrencyFormatter.shared.formatSigned(transaction.amount ?? 0, currencyCode: currencyCode))
                        .font(AppTheme.Fonts.body.monospacedDigit())
                        .foregroundStyle((transaction.amount ?? 0) < 0 ? .primary : AppTheme.positive)
                    Text(transaction.date)
                        .font(AppTheme.Fonts.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onEdit?(transaction) }
        .contextMenu {
            if let onEdit { Button { onEdit(transaction) } label: { Label("Edit", systemImage: "pencil") } }
            if let onDelete { Button(role: .destructive) { onDelete(transaction) } label: { Label("Delete", systemImage: "trash") } }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if let onDelete { Button(role: .destructive) { onDelete(transaction) } label: { Label("Delete", systemImage: "trash") } }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if let onEdit { Button { onEdit(transaction) } label: { Label("Edit", systemImage: "pencil") }.tint(.blue) }
        }
    }

    private func primaryText() -> String {
        if let account = transferDestinationAccount(transaction) {
            return "Transfer \((transaction.amount ?? 0) < 0 ? "to" : "from"): \(account.name)"
        }
        if let payeeId = transaction.payee, let p = payeesById[payeeId] { return p.name }
        if let n = transaction.payee_name, !n.isEmpty { return n }
        return "(No payee)"
    }

    private func secondaryText() -> String {
        if let category = categoriesById[transaction.category ?? ""], !category.name.isEmpty {
            return category.name
        }
        if let accountName = accounts.first(where: { $0.id == transaction.account })?.name {
            return accountName
        }
        return ""
    }

    private func transferDestinationAccount(_ tx: Transaction) -> Account? {
        if let payeeId = tx.payee,
           let p = payeesById[payeeId],
           let destAcctId = p.transfer_acct {
            return accounts.first { $0.id == destAcctId }
        }
        return nil
    }
}


