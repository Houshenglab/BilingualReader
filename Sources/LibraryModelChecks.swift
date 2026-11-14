import Foundation
import PDFKit
@main struct LibraryModelChecks {
 @MainActor static func main() async throws {
  precondition(ReaderModel.visibleParagraph(in:[0:CGRect(x:0,y:-100,width:500,height:1000),1:CGRect(x:0,y:900,width:500,height:100)])==0, "Keep the still-visible long paragraph")
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at:root) }
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
  let source=root.appendingPathComponent("Essay.txt")
  try "First English paragraph.\n\nSecond English paragraph.".write(to:source,atomically:true,encoding:.utf8)
  let store=LibraryStore(root:root.appendingPathComponent("Library"))
  let book=try await store.importDocument(source)
  let model=ReaderModel(translator: WebTranslator(cacheDirectory:root.appendingPathComponent("test-cache")), library:store)
  model.openBook(book)
  for _ in 0..<200 where model.importing { try await Task.sleep(nanoseconds:20_000_000) }
  precondition(model.currentBookID==book.id && !model.showingLibrary)
  model.paragraphs[0].translation="第一段";model.paragraphs[0].expanded=true
  model.readingParagraphID=1;model.fontSize=24
  model.returnToLibrary()
  await model.flushLibrarySave()
  let next=ReaderModel(translator: WebTranslator(cacheDirectory:root.appendingPathComponent("test-cache")), library:store);next.openBook(book)
  for _ in 0..<200 where next.importing { try await Task.sleep(nanoseconds:20_000_000) }
  precondition(next.paragraphs[0].translation=="第一段" && next.readingParagraphID==1 && next.fontSize==24)
  next.returnToLibrary();next.openBook(book);next.returnToLibrary()
  try await Task.sleep(nanoseconds:100_000_000)
  precondition(next.showingLibrary && !next.importing, "Late open must not leave bookshelf")
  next.openBook(book)
  for _ in 0..<200 where next.importing { try await Task.sleep(nanoseconds:20_000_000) }
  next.clearTranslationCache()
  for _ in 0..<200 where next.clearingCache { try await Task.sleep(nanoseconds:20_000_000) }
  await next.flushLibrarySave()
  let state=try await store.session(book.id)!
  precondition(state.paragraphs.allSatisfy{$0.translation==nil})
  let oldEngine=UserDefaults.standard.string(forKey:"libraryEngine")
  defer { if let oldEngine {UserDefaults.standard.set(oldEngine,forKey:"libraryEngine")}else{UserDefaults.standard.removeObject(forKey:"libraryEngine")} }
  let word=try await store.importDocument(URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("fixtures/example.docx"))
  var saved=try await store.session(word.id)!
  saved.engine=TranslationEngine.google.rawValue;saved.paragraphs[0].translation="Google only";saved.modifiedAt=Date()
  try await store.save(word.id,session:saved)
  let wordModel=ReaderModel(translator:WebTranslator(cacheDirectory:root.appendingPathComponent("test-cache")),library:store)
  wordModel.engine = .google;wordModel.openBook(word)
  for _ in 0..<200 where wordModel.importing {try await Task.sleep(nanoseconds:20_000_000)}
  wordModel.engine = .bing;wordModel.changeEngine()
  wordModel.acceptWordParagraphs(saved.paragraphs.map(\.text),url:wordModel.documentURL!)
  await wordModel.flushLibrarySave()
  let updated=try await store.session(word.id)!
  precondition(updated.paragraphs[0].translation==nil,"Pending Word translations must belong to current engine")
  let pdfSource = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "fixtures/example.pdf")
  let pdfBook = try await store.importDocument(pdfSource)
  let initialPDF = try await store.session(pdfBook.id)!
  precondition(initialPDF.paragraphs.isEmpty, "Import must publish PDF before whole-document layout")
  let rawSession = try JSONSerialization.jsonObject(with: JSONEncoder().encode(initialPDF)) as! [String: Any]
  precondition(rawSession["layoutPending"] as? Bool == true, "Unanalyzed PDF must persist explicit pending state")
  let pdfModel = ReaderModel(translator: WebTranslator(cacheDirectory:root.appendingPathComponent("test-cache")), library:store)
  pdfModel.openBook(pdfBook)
  for _ in 0..<200 where pdfModel.importing { try await Task.sleep(nanoseconds:5_000_000) }
  precondition(!pdfModel.showingLibrary && pdfModel.documentURL != nil && !pdfModel.documentReady, "Original PDF must appear while paragraph analysis is pending")
  let targetPage = min(2, pdfBook.pageCount)
  pdfModel.pdfVisiblePage = targetPage
  await pdfModel.flushLibrarySave()
  let pendingState = try await store.session(pdfBook.id)!
  precondition(pendingState.page == targetPage, "Page must save even while PDF analysis is pending")
  for _ in 0..<4000 where !pdfModel.documentReady { try await Task.sleep(nanoseconds:5_000_000) }
  precondition(pdfModel.documentReady && !pdfModel.paragraphs.isEmpty, "Background PDF layout must finish")
  await pdfModel.flushLibrarySave()
  let prepared = try await store.session(pdfBook.id)!
  precondition(prepared.layoutPending != true && prepared.page == targetPage && !prepared.paragraphs.isEmpty)
  pdfModel.paragraphs[0].translation = "Saved PDF translation"
  await pdfModel.flushLibrarySave()
  let reopenedPDF = ReaderModel(translator:WebTranslator(cacheDirectory:root.appendingPathComponent("test-cache")),library:store)
  reopenedPDF.openBook(pdfBook)
  for _ in 0..<200 where reopenedPDF.importing { try await Task.sleep(nanoseconds:5_000_000) }
  precondition(reopenedPDF.documentReady && reopenedPDF.paragraphs[0].translation == "Saved PDF translation", "Prepared PDF restores cached layout and translation")
  var pendingAgain = ReadingSession(paragraphs: [], layoutPending: true)
  pendingAgain.modifiedAt = Date()
  try await store.save(pdfBook.id, session:pendingAgain)
  let switched = ReaderModel(translator:WebTranslator(cacheDirectory:root.appendingPathComponent("test-cache")),library:store)
  switched.openBook(pdfBook)
  for _ in 0..<200 where switched.importing { try await Task.sleep(nanoseconds:5_000_000) }
  let oldPreparation = switched.pdfPreparationTask
  switched.pdfVisiblePage = targetPage
  let cancellationStart = Date()
  switched.returnToLibrary()
  switched.openBook(book)
  await oldPreparation?.value
  precondition(Date().timeIntervalSince(cancellationStart) < 0.65, "Leaving a PDF must terminate its parser promptly, not wait for full analysis")
  for _ in 0..<200 where switched.importing { try await Task.sleep(nanoseconds:5_000_000) }
  precondition(switched.currentBookID == book.id && switched.paragraphs[0].text == "First English paragraph.", "Stale PDF completion must not replace another book")
  let interrupted = try await store.session(pdfBook.id)!
  precondition(interrupted.layoutPending == true && interrupted.page == targetPage, "Interrupted PDF must retain pending state and reading page")
  let resumed = ReaderModel(translator:WebTranslator(cacheDirectory:root.appendingPathComponent("test-cache")),library:store)
  resumed.openBook(pdfBook)
  for _ in 0..<200 where resumed.importing { try await Task.sleep(nanoseconds:5_000_000) }
  await resumed.pdfPreparationTask?.value
  precondition(resumed.documentReady && resumed.pdfVisiblePage == targetPage, "Interrupted layout resumes on next open")
  await resumed.flushLibrarySave()
  let blankURL = root.appendingPathComponent("scan.pdf")
  let blank = PDFDocument(); let blankPage = PDFPage()
  blankPage.setBounds(CGRect(x:0,y:0,width:612,height:792), for:.mediaBox)
  blank.insert(blankPage, at:0)
  precondition(blank.write(to:blankURL))
  let blankBook = try await store.importDocument(blankURL)
  let failed = ReaderModel(translator:WebTranslator(cacheDirectory:root.appendingPathComponent("test-cache")),library:store)
  failed.openBook(blankBook)
  for _ in 0..<200 where failed.importing { try await Task.sleep(nanoseconds:5_000_000) }
  await failed.pdfPreparationTask?.value
  precondition(failed.pdfLayoutPending && !failed.preparingPDF && failed.pdfPreparationError != nil && !failed.showingLibrary, "Failed analysis keeps original PDF readable")
  failed.preparePDFLayout()
  precondition(failed.preparingPDF && failed.pdfPreparationError == nil, "Failed analysis can retry")
  await failed.pdfPreparationTask?.value
  precondition(failed.pdfPreparationError != nil)
  await failed.flushLibrarySave()
  let failedState = try await store.session(blankBook.id)!
  precondition(failedState.layoutPending == true, "Failed analysis must remain pending on disk")
  print("PASS: PDF quick import/display, background layout cache, in-flight page save, stale completion guard, restart and retry")
  print("PASS: reader session restores translations/anchor/font, late-open cancellation and clear-cache persistence")
 }
}
