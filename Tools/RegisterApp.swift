import Foundation
import CoreServices
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let result = LSRegisterURL(url as CFURL, true)
guard result == noErr else { fputs("Application registration failed: \(result)\n", stderr); exit(1) }
print("Registered app icon and document types")
