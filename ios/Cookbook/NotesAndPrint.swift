import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit
import CoreText

struct NoteEditorView: View {
    let recipe: Recipe
    let note: RecipeNote?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var text: String
    @State private var stepID: String?
    init(recipe: Recipe, note: RecipeNote? = nil) {
        self.recipe = recipe
        self.note = note
        _text = State(initialValue: note?.text ?? "")
        _stepID = State(initialValue: note?.stepID)
    }
    var body: some View {
        NavigationStack {
            Form {
                Picker("Related step", selection: $stepID) {
                    Text("Whole recipe").tag(String?.none)
                    ForEach(Array(recipe.steps.enumerated()), id: \.element.id) { index, step in Text("Step \(index + 1)").tag(Optional(step.id)) }
                }
                TextEditor(text: $text).frame(minHeight: 180).accessibilityLabel("Recipe note")
            }
            .navigationTitle("Recipe Note")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") {
                if let note { note.text = text; note.stepID = stepID; note.updatedAt = .now }
                else { context.insert(RecipeNote(recipeID: recipe.id, stepID: stepID, text: text)) }
                dismiss()
            }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } }
        }
    }
}

struct RecipePrintView: View {
    let recipe: Recipe
    @Environment(\.dismiss) private var dismiss
    @State private var shareFile: ShareFile?
    @State private var printError: String?
    var body: some View {
        NavigationStack {
            ScrollView { printContents.padding(24) }
                .navigationTitle("Print Preview").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("PDF / Print") { makePDFAndShare() } } }
                .sheet(item: $shareFile) { file in ActivityView(items: [file.url]) }
                .alert("Could not create recipe PDF", isPresented: Binding(get: { printError != nil }, set: { if !$0 { printError = nil } })) { Button("OK") { printError = nil } } message: { Text(printError ?? "") }
        }
    }
    private var printContents: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(recipe.title).font(.system(size: 30, weight: .semibold, design: .serif))
            if !recipe.introduction.isEmpty { Text(recipe.introduction).foregroundStyle(.secondary) }
            ForEach(recipe.orderedContent) { content in
                if let group = content.group {
                    VStack(alignment: .leading, spacing: 3) {
                        if let title = group.title, !title.isEmpty { Text(title).font(.headline) }
                        ForEach(content.ingredients) { item in Text("\(item.quantity.isEmpty ? "" : item.quantity + "  ")\(item.name)") }
                    }.padding(.vertical, 3)
                } else if let step = content.step, let number = content.stepNumber {
                    Text("\(number + 1).  \(step.originalInstruction)")
                }
            }
            ForEach(recipe.tips, id: \.self) { Text("Tip: \($0)").italic().foregroundStyle(.secondary) }
            ForEach(recipe.healthierOptions, id: \.self) { Text("Healthier option: \($0)").italic().foregroundStyle(.secondary) }
        }.frame(maxWidth: 620, alignment: .leading).frame(maxWidth: .infinity, alignment: .topLeading)
    }
    private func makePDFAndShare() {
        guard let url = createPDF() else { printError = "The PDF could not be written. Check available storage and try again."; return }
        shareFile = ShareFile(url: url)
    }
    private func createPDF() -> URL? {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        let url = UserFiles.directory.appendingPathComponent("\(UUID().uuidString).pdf")
        var failedToPaginate = false
        do {
            try renderer.writePDF(to: url) { context in
                var blocks: [(String, UIFont)] = [(recipe.title, .boldSystemFont(ofSize: 24)), (recipe.introduction, .systemFont(ofSize: 11))]
                for item in recipe.orderedContent {
                    if let group = item.group {
                        if let title = group.title, !title.isEmpty { blocks.append((title, .boldSystemFont(ofSize: 12))) }
                        blocks += item.ingredients.map { ("\($0.quantity)  \($0.name)", .systemFont(ofSize: 11)) }
                    } else if let step = item.step, let number = item.stepNumber {
                        blocks.append(("\(number + 1).  \(step.originalInstruction)", .systemFont(ofSize: 11)))
                    }
                }
                blocks += recipe.tips.map { ("Tip: \($0)", .italicSystemFont(ofSize: 11)) }
                blocks += recipe.healthierOptions.map { ("Healthier option: \($0)", .italicSystemFont(ofSize: 11)) }
                let content = NSMutableAttributedString()
                for (text, font) in blocks where !text.isEmpty {
                    content.append(NSAttributedString(string: text + "\n\n", attributes: [.font: font]))
                }
                guard content.length > 0 else { return }
                let framesetter = CTFramesetterCreateWithAttributedString(content as CFAttributedString)
                var currentRange = CFRange(location: 0, length: 0)
                while currentRange.location < content.length {
                    context.beginPage()
                    let path = CGPath(rect: CGRect(x: 48, y: 48, width: 516, height: 696), transform: nil)
                    let frame = CTFramesetterCreateFrame(framesetter, currentRange, path, nil)
                    context.cgContext.saveGState()
                    context.cgContext.translateBy(x: 0, y: 792)
                    context.cgContext.scaleBy(x: 1, y: -1)
                    CTFrameDraw(frame, context.cgContext)
                    context.cgContext.restoreGState()
                    let visibleRange = CTFrameGetVisibleStringRange(frame)
                    guard visibleRange.length > 0 else { failedToPaginate = true; break }
                    currentRange.location += visibleRange.length
                }
            }
            if failedToPaginate { try? FileManager.default.removeItem(at: url); return nil }
            guard ((try? Data(contentsOf: url).count) ?? 0) > 0 else { try? FileManager.default.removeItem(at: url); return nil }
            return url
        } catch { try? FileManager.default.removeItem(at: url); return nil }
    }
}

private struct ShareFile: Identifiable { let id = UUID(); let url: URL }
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}

struct CameraCaptureView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture, dismiss: dismiss) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.cameraCaptureMode = .photo
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) { }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: (UIImage) -> Void
        private let dismiss: DismissAction
        init(onCapture: @escaping (UIImage) -> Void, dismiss: DismissAction) { self.onCapture = onCapture; self.dismiss = dismiss }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { onCapture(image) }
            dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { dismiss() }
    }
}

enum TimelineChecklistPDF {
    static func render(name: String, dinnerTime: Date, activities: [TimelineActivity]) -> URL? {
        guard !activities.isEmpty else { return nil }
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let margins: CGFloat = 32
        let gap: CGFloat = 24
        let columnWidth = (page.width - margins * 2 - gap) / 2
        let columnX = [margins, margins + columnWidth + gap]
        let top: CGFloat = 82
        let bottom: CGFloat = 758
        let titleFont = UIFont.boldSystemFont(ofSize: 17)
        let headerFont = UIFont.boldSystemFont(ofSize: 10)
        let bodyFont = UIFont.systemFont(ofSize: 8.5)
        let dayFont = UIFont.boldSystemFont(ofSize: 10)
        let url = UserFiles.directory.appendingPathComponent("timeline-\(UUID().uuidString).pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        var overflow = false
        do {
            try renderer.writePDF(to: url) { context in
                context.beginPage()
                (name as NSString).draw(at: CGPoint(x: margins, y: 24), withAttributes: [.font: titleFont])
                ("Dinner: \(dinnerTime.formatted(date: .complete, time: .shortened))" as NSString).draw(at: CGPoint(x: margins, y: 49), withAttributes: [.font: headerFont, .foregroundColor: UIColor.darkGray])
                let dividerX = margins + columnWidth + gap / 2
                context.cgContext.setStrokeColor(UIColor.separator.cgColor)
                context.cgContext.move(to: CGPoint(x: dividerX, y: top))
                context.cgContext.addLine(to: CGPoint(x: dividerX, y: bottom))
                context.cgContext.strokePath()
                var column = 0
                var y = top
                var currentDay: Date?
                let calendar = Calendar.current
                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .full
                dateFormatter.timeStyle = .none
                let ordered = activities.sorted { $0.start < $1.start }
                for activity in ordered {
                    let day = calendar.startOfDay(for: activity.start)
                    let newDay = currentDay.map { !calendar.isDate($0, inSameDayAs: day) } ?? true
                    let title = "\(activity.start.formatted(date: .omitted, time: .shortened))  ·  \(activity.recipeTitle)"
                    let titleRect = (title as NSString).boundingRect(with: CGSize(width: columnWidth - 20, height: 100), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: headerFont], context: nil)
                    let instructionRect = (activity.instruction as NSString).boundingRect(with: CGSize(width: columnWidth - 20, height: 800), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: bodyFont], context: nil)
                    let dayHeight: CGFloat = newDay ? 17 : 0
                    let rowHeight = max(19, titleRect.height + 2 + instructionRect.height + 6)
                    if y + dayHeight + rowHeight > bottom {
                        column += 1
                        y = top
                        currentDay = nil
                        if column > 1 { overflow = true; return }
                    }
                    let needsHeading = currentDay.map { !calendar.isDate($0, inSameDayAs: day) } ?? true
                    if needsHeading {
                        dateFormatter.string(from: day).draw(at: CGPoint(x: columnX[column], y: y), withAttributes: [.font: dayFont])
                        y += 17
                    }
                    let box = CGRect(x: columnX[column], y: y + 1, width: 10, height: 10)
                    context.cgContext.setStrokeColor(UIColor.label.cgColor)
                    context.cgContext.setLineWidth(0.8)
                    context.cgContext.stroke(box)
                    let textX = columnX[column] + 16
                    let titleDraw = CGRect(x: textX, y: y, width: columnWidth - 18, height: titleRect.height + 3)
                    (title as NSString).draw(in: titleDraw, withAttributes: [.font: headerFont])
                    let instructionDraw = CGRect(x: textX, y: y + titleRect.height + 3, width: columnWidth - 18, height: instructionRect.height + 2)
                    (activity.instruction as NSString).draw(in: instructionDraw, withAttributes: [.font: bodyFont])
                    y += rowHeight
                    currentDay = day
                }
            }
            guard !overflow else { try? FileManager.default.removeItem(at: url); return nil }
            // The one-page renderer returns a PDF only when all rows fit in two columns.
            let size = (try? Data(contentsOf: url).count) ?? 0
            return size > 0 ? url : nil
        } catch { return nil }
    }
}
