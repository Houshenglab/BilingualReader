import Foundation
@main struct CategoryChecks {
 static func check(_ condition: Bool, _ message: String) { precondition(condition,message) }
 @MainActor static func main() async throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at:root) }
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
  let store=LibraryStore(root:root.appendingPathComponent("Library"))
  let first=root.appendingPathComponent("Climate.txt"), second=root.appendingPathComponent("Methods.txt")
  try "Climate paragraph.".write(to:first,atomically:true,encoding:.utf8)
  try "Methods paragraph.".write(to:second,atomically:true,encoding:.utf8)
  let a=try await store.importDocument(first), b=try await store.importDocument(second)
  let initial=try await store.organization()
  check(initial.categories.isEmpty && initial.assignments.isEmpty,"Legacy library starts uncategorized")
  let climate=try await store.createCategory("  气候文献  ")
  let methods=try await store.createCategory("Methods")
  check(climate.name=="气候文献","Names are trimmed")
  try await store.assignCategory([a.id,b.id],to:climate.id)
  let indexPath=root.appendingPathComponent("Library/index.json")
  let originalIndex=try Data(contentsOf:indexPath)
  let sessionPath=root.appendingPathComponent("Library/\(a.id)/session.json")
  let bytes=try Data(contentsOf:sessionPath)
  try await store.renameCategory(climate.id,name:"气候研究")
  let restored=try await LibraryStore(root:root.appendingPathComponent("Library")).organization()
  check(restored.categories.first?.name=="气候研究" && restored.assignments[a.id]==climate.id,"Rename preserves category identity and survives restart")
  try await store.assignCategory([b.id],to:methods.id)
  let assigned=try await store.organization()
  check(assigned.assignments[a.id]==climate.id && assigned.assignments[b.id]==methods.id,"Only selected documents move")
  for invalid in ["", "   ", "全部", "未分类", "methods", String(repeating:"x",count:41)] {
   do { _=try await store.createCategory(invalid);fatalError("Invalid category accepted: \(invalid)") } catch {}
  }
  do { try await store.assignCategory([a.id,b.id],to:"missing");fatalError("Unknown category accepted") } catch {}
  do { try await store.assignCategory([a.id,"missing"],to:methods.id);fatalError("Partial batch accepted") } catch {}
  let intact=try await store.organization()
  check(intact.assignments[a.id]==climate.id,"Rejected assignment is atomic")
  check(try Data(contentsOf:indexPath)==originalIndex,"Categorization must not change reading order or index bytes")
  try FileManager.default.removeItem(at:indexPath)
  try FileManager.default.createDirectory(at:indexPath,withIntermediateDirectories:false)
  try Data("block".utf8).write(to:indexPath.appendingPathComponent("blocker"))
  do { try await store.remove(a.id);fatalError("Removal should fail when index cannot be written") } catch {}
  let afterFailedRemoval=try await store.organization()
  check(afterFailedRemoval.assignments[a.id]==climate.id,"Failed removal must preserve original category")
  check(try await store.list().contains{$0.id==a.id},"Failed removal must keep document indexed")
  try FileManager.default.removeItem(at:indexPath)
  try originalIndex.write(to:indexPath)
  try await store.deleteCategory(climate.id)
  let deleted=try await store.organization()
  check(deleted.assignments[a.id]==nil && deleted.assignments[b.id]==methods.id,"Delete only clears matching assignments")
  check(try Data(contentsOf:sessionPath)==bytes,"Categorization must not change reading session")
  check(try await store.list().count==2,"Deleting category retains every document")
  check(FileManager.default.fileExists(atPath:await store.documentURL(a).path),"Managed PDF/Word files retained")
  try await store.remove(b.id)
  let removed=try await store.organization()
  check(removed.assignments[b.id]==nil,"Removing book clears its assignment")
  let model=ReaderModel(translator:WebTranslator(cacheDirectory:root.appendingPathComponent("cache")),library:store)
  await model.refreshLibrary()
  let papers=try await model.createLibraryCategory("文献")
  let notes=try await model.createLibraryCategory("笔记")
  model.libraryFilter = .category(papers.id)
  model.importDocuments([first,second])
  model.libraryFilter = .category(notes.id)
  for _ in 0..<300 where model.libraryBusy { try await Task.sleep(nanoseconds:10_000_000) }
  check(!model.libraryBusy && model.libraryOrganization.assignments[a.id]==papers.id && model.libraryOrganization.assignments[b.id]==papers.id,"Import target must be captured before filter changes")
  check(model.matchingBooks(query: "").isEmpty,"Category filter hides other documents")
  model.libraryFilter = .category(papers.id)
  check(model.matchingBooks(query:"climate").map(\.id)==[a.id],"Search composes with category filter")
  model.libraryFilter = .all
  model.importDocuments([first])
  for _ in 0..<300 where model.libraryBusy { try await Task.sleep(nanoseconds:10_000_000) }
  check(model.libraryOrganization.assignments[a.id]==papers.id,"Duplicate import from All preserves existing category")
  model.libraryFilter = .uncategorized
  model.importDocuments([first])
  for _ in 0..<300 where model.libraryBusy { try await Task.sleep(nanoseconds:10_000_000) }
  check(model.libraryOrganization.assignments[a.id]==papers.id,"Duplicate import from Uncategorized preserves existing category")
  try await model.assignLibraryCategory([b.id],to:nil)
  model.libraryFilter = .uncategorized
  check(model.matchingBooks(query: "").map(\.id)==[b.id],"Uncategorized excludes categorized documents")
  model.libraryFilter = .category(papers.id)
  try await model.deleteLibraryCategory(papers.id)
  check(model.libraryFilter == .all && model.matchingBooks(query: "").count==2,"Deleting active category returns to All without losing documents")
  let sidecar=root.appendingPathComponent("Library/organization.json")
  try Data("broken".utf8).write(to:sidecar)
  let corrupt=LibraryStore(root:root.appendingPathComponent("Library"))
  do { _=try await corrupt.createCategory("New");fatalError("Corrupt organization overwritten") } catch {}
  check(try String(contentsOf:sidecar,encoding:.utf8)=="broken","Corrupt data remains recoverable")
  print("PASS: category migration, validation, persistence, atomic assignments, rename/delete, preserved reading data and corruption protection")
 }
}
