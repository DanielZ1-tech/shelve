import SwiftUI

// MARK: - Dry-Run Sheet

struct DryRunSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var moves: [FileMove] = []
    @State private var loading = true
    @State private var applying = false

    var body: some View {
        VStack(spacing: 0) {

            // Header
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Test Rules")
                        .font(.title3.bold())
                    Text("Preview what would be moved — nothing is changed yet.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            if loading {
                Spacer()
                ProgressView("Scanning files…")
                Spacer()
            } else if moves.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.green)
                    Text("Nothing to move")
                        .font(.system(size: 15, weight: .medium))
                    Text("All files already match your rules, or there are no files to classify.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                Spacer()
            } else {
                // Summary banner
                HStack(spacing: 16) {
                    Label("\(moves.count) file\(moves.count == 1 ? "" : "s") would be moved",
                          systemImage: "arrow.right.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.orange)

                    Spacer()

                    let byDest = Dictionary(grouping: moves, by: \.toFolder)
                    Text("\(byDest.count) destination\(byDest.count == 1 ? "" : "s")")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.orange.opacity(0.08))

                // List
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(moves.enumerated()), id: \.offset) { _, move in
                            DryRunRow(move: move)
                            Divider().padding(.leading, 54)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Divider()

            // Footer
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)

                Spacer()

                if !loading && !moves.isEmpty {
                    Button {
                        apply()
                    } label: {
                        if applying {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Label("Apply Now (\(moves.count))", systemImage: "checkmark")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(applying)
                    .keyboardShortcut(.return)
                }
            }
            .padding(16)
        }
        .frame(width: 580, height: 480)
        .onAppear { runDryRun() }
    }

    private func runDryRun() {
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Classifier.shared.classifyAll(dryRun: true)
            DispatchQueue.main.async {
                moves = result
                loading = false
            }
        }
    }

    private func apply() {
        applying = true
        DispatchQueue.global(qos: .userInitiated).async {
            let moved = Classifier.shared.classifyAll(dryRun: false)
            DispatchQueue.main.async {
                NotificationManager.shared.notifyMoves(moved)
                applying = false
                dismiss()
            }
        }
    }
}

// MARK: - Row

struct DryRunRow: View {
    let move: FileMove
    private var isTrash: Bool { move.toFolder.contains("Trash") }

    var fileExt: String {
        let ext = (move.fileName as NSString).pathExtension.lowercased()
        return ext.isEmpty ? "—" : ext
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isTrash ? Color.red.opacity(0.1) : Color.blue.opacity(0.1))
                    .frame(width: 34, height: 34)
                Text(fileExt == "—" ? "?" : fileExt.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(isTrash ? .red : .blue)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(move.fileName)
                    .font(.system(size: 13))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text((move.fromPath as NSString).abbreviatingWithTildeInPath)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: isTrash ? "trash" : "arrow.right")
                    .font(.system(size: 10))
                    .foregroundColor(isTrash ? .red : .secondary)
                Text(move.toFolder)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isTrash ? .red : .primary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }
}
