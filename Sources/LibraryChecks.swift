import Foundation
@main struct LibraryChecks {
 static func check(_ value: Bool, _ message: String = "Library check failed") { if !value { fatalError(message) } }
 static func main() async throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  let original=root.appendingPathComponent("original.txt")
  try "First paragraph.\n\nSecond paragraph.".write(to: original, atomically: true, encoding: .utf8)
  let store=LibraryStore(root: root.appendingPathComponent("library"))
  let book=try await store.importDocument(original)
  let duplicate=try await store.importDocument(original)
  check(book.id == duplicate.id)
  try FileManager.default.removeItem(at: original)
  let copied=await store.documentURL(book)
  check(try String(contentsOf: copied, encoding: .utf8) == "First paragraph.\n\nSecond paragraph.")
  try "Different content.".write(to: original, atomically: true, encoding: .utf8)
  let second=try await store.importDocument(original)
  check(second.id != book.id)
  var session=try await store.session(book.id)!
  session.page=2;session.paragraphID=1;session.paragraphs[0].translation="已保存";session.paragraphs[0].expanded=true
  session.modifiedAt=Date();try await store.save(book.id, session:session)
  let reloaded=LibraryStore(root:root.appendingPathComponent("library"))
  let restored=try await reloaded.session(book.id)!
  check(restored.page==2 && restored.paragraphID==1 && restored.paragraphs[0].translation=="已保存")
  try await store.clearTranslations()
  let cleared=try await store.session(book.id)!
  check(cleared.paragraphs[0].translation==nil)
  try await store.save(book.id,session:session)
  check(try await store.session(book.id)!.paragraphs[0].translation==nil, "Stale save after clear must not restore translations")
  try await store.remove(book.id)
  try await store.save(book.id,session:session)
  check(try await store.list().count==1)
  check(FileManager.default.fileExists(atPath:original.path))
  let bad=root.appendingPathComponent("bad.pdf");try Data("not a pdf".utf8).write(to:bad)
  do { _=try await store.importDocument(bad);fatalError("Invalid PDF was imported") } catch {}
  check(try await store.list().count==1)
  let index=root.appendingPathComponent("library/index.json")
  try Data("broken".utf8).write(to:index)
  do { _=try await LibraryStore(root:root.appendingPathComponent("library")).list();fatalError("Corrupt index silently reset") } catch {}
  check(try String(contentsOf:index, encoding:.utf8)=="broken")
  print("PASS: managed copies, duplicate/same-name import, session restore, cache-clear barrier, safe removal, invalid PDF rollback and corrupt-index protection")
 }
}
