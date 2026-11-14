import Foundation
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
  print("PASS: reader session restores translations/anchor/font, late-open cancellation and clear-cache persistence")
 }
}
