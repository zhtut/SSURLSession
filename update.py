import glob
import os.path
import shutil
import subprocess

class File:
    def __init__(self, path: str):
        self.path = path

    def replace(self, origin: str, dest: str):
        with open(self.path, "r") as f:
            content = f.read()
            content = content.replace(origin, dest)
            with open(self.path, "w") as w:
                w.write(content)

    def add_content(self, content: str):
        with open(self.path, "r") as f:
            origin = f.read()
            origin = origin + content
            with open(self.path, "w") as w:
                w.write(origin)

def pull_origin():
    git_url = "https://github.com/apple/swift-corelibs-foundation.git"
    folder = "swiftFoundation"
    if os.path.exists(folder):
        print("已存在，更新一下")
        print(subprocess.getoutput(f"cd {folder} && git pull"))
    else:
        print("开始clone swift corelibs foundation")
        print(subprocess.getoutput(f"git clone {git_url} {folder}"))

    print("开始复制文件")
    foundation_networking = f"{folder}/Sources/FoundationNetworking"
    ssurlsession = "Sources/SSURLSession"
    shutil.copytree(f"{foundation_networking}/URLSession", f"{ssurlsession}/URLSession", dirs_exist_ok=True)
    shutil.copy(f"{foundation_networking}/URLCache.swift", f"{ssurlsession}/")
    shutil.copy(f"{foundation_networking}/URLProtocol.swift", f"{ssurlsession}/")
    shutil.copy(f"{foundation_networking}/DataURLProtocol.swift", f"{ssurlsession}/")
    print("复制文件完成")

def modify():
    print("开始修复文件")
    ssurlsession = "Sources/SSURLSession"
    swift_files = glob.glob(f"{ssurlsession}/**/*.swift", recursive=True)

    def replace(origin: str, dest: str, file_name: str = None):
        for swift in swift_files:
            if file_name:
                if swift.__contains__(file_name):
                    file = File(swift)
                    file.replace(origin, dest)
            else:
                file = File(swift)
                file.replace(origin, dest)

    def file_with_name(name: str) -> File:
        for swift in swift_files:
            if swift.__contains__(name):
                file = File(swift)
                return file

    replace("import SwiftFoundation", "import Foundation")
    replace(
        """open class var ephemeral: URLSessionConfiguration {
        let ephemeralConfiguration = URLSessionConfiguration.default.copy() as! URLSessionConfiguration
        ephemeralConfiguration.httpCookieStorage = .ephemeralStorage()
        ephemeralConfiguration.urlCredentialStorage = URLCredentialStorage(ephemeral: true)
        ephemeralConfiguration.urlCache = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 0, diskPath: nil)
        return ephemeralConfiguration
    }""",
        """//open class var ephemeral: URLSessionConfiguration {
        //let ephemeralConfiguration = URLSessionConfiguration.default.copy() as! URLSessionConfiguration
        //ephemeralConfiguration.httpCookieStorage = .ephemeralStorage()
        //ephemeralConfiguration.urlCredentialStorage = URLCredentialStorage(ephemeral: true)
        //ephemeralConfiguration.urlCache = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 0, diskPath: nil)
        //return ephemeralConfiguration
    //}"""
    )
    replace(
        """
        if request.isTimeoutIntervalSet {
            timeoutInterval = Int(request.timeoutInterval) * 1000
        }
        """,
        """
        let requestTimeOut = request.timeoutInterval
        if !requestTimeOut.isInfinite && !requestTimeOut.isNaN && requestTimeOut > 0 {
            timeoutInterval = Int(request.timeoutInterval) * 1000
        }
        """,
        file_name='HTTPURLProtocol'
    )
    replace("return request.protocolProperties[key]",
            "return Foundation.URLProtocol.property(forKey: key, in: request)",
            file_name="URLProtocol")

    replace("request.protocolProperties[key] = value",
            "Foundation.URLProtocol.setProperty(value, forKey: key, in: request)",
            file_name="URLProtocol")

    replace("request.protocolProperties.removeValue(forKey: key)",
            "Foundation.URLProtocol.removeProperty(forKey: key, in: request)",
            file_name="URLProtocol")

    nativeprotocol = file_with_name("NativeProtocol")
    nativeprotocol.add_content(
        """
// add-
public struct _InputStreamSPIForFoundationNetworkingUseOnly {
    var inputStream: InputStream
    
    public init(_ inputStream: InputStream) {
        self.inputStream = inputStream
    }
    
    public func seek(to position: UInt64) throws {
        try inputStream.seek(to: position)
    }
}

extension InputStream {
    enum _Error: Error {
        case cantSeekInputStream
    }
    
    func seek(to position: UInt64) throws {
        guard position > 0 else {
            return
        }
        
        guard position < Int.max else { throw _Error.cantSeekInputStream }
        
        let bufferSize = 1024
        var remainingBytes = Int(position)
        
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: bufferSize, alignment: MemoryLayout<UInt8>.alignment)
        
        guard let pointer = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
            buffer.deallocate()
            throw _Error.cantSeekInputStream
        }
        
        if self.streamStatus == .notOpen {
            self.open()
        }
        
        while remainingBytes > 0 && self.hasBytesAvailable {
            let read = self.read(pointer, maxLength: min(bufferSize, remainingBytes))
            if read == -1 {
                throw _Error.cantSeekInputStream
            }
            remainingBytes -= read
        }
        
        buffer.deallocate()
        if remainingBytes != 0 {
            throw _Error.cantSeekInputStream
        }
    }
}
        """
    )

    replace("""        guard let authenticateValue = response.value(forHTTPHeaderField: "WWW-Authenticate") else {
            return []
        }
        return challenges(from: authenticateValue)""",
"""        if #available(iOS 13.0, *), #available(macOS 10.15, *) {
            guard let authenticateValue = response.value(forHTTPHeaderField: "WWW-Authenticate") else {
                return []
            }
            return challenges(from: authenticateValue)
        } else {
            // Fallback on earlier versions
            let allHeaders = response.allHeaderFields
            guard let authenticateValue = allHeaders["WWW-Authenticate"] as? String else {
                return []
            }
            return challenges(from: authenticateValue)
        }""", "HTTPMessage")

    NetworkingSpecific = file_with_name("NetworkingSpecific")
    NetworkingSpecific.add_content(
        """
// add-
public protocol _NSNonfileURLContentLoading: AnyObject {
    init()
    func contentsOf(url: URL) throws -> (result: NSData, textEncodingNameIfAvailable: String?)
}"""
    )

    URLSessionTask = file_with_name("URLSessionTask")
    URLSessionTask.add_content(
        """
// add-
extension URLProtectionSpace {
    //an internal helper to create a URLProtectionSpace from a HTTPURLResponse
    static func create(with response: HTTPURLResponse) -> URLProtectionSpace? {
        // Using first challenge, as we don't support multiple challenges yet
        guard let challenge = _HTTPURLProtocol._HTTPMessage._Challenge.challenges(from: response).first else {
            return nil
        }
        guard let url = response.url, let host = url.host, let proto = url.scheme, proto == "http" || proto == "https" else {
            return nil
        }
        let port = url.port ?? (proto == "http" ? 80 : 443)
        return URLProtectionSpace(host: host,
                                  port: port,
                                  protocol: proto,
                                  realm: challenge.parameter(withName: "realm")?.value,
                                  authenticationMethod: challenge.authenticationMethod)
    }
}

extension _HTTPURLProtocol._HTTPMessage._Challenge {
    var authenticationMethod: String? {
        if authScheme.caseInsensitiveCompare(_HTTPURLProtocol._HTTPMessage._Challenge.AuthSchemeBasic) == .orderedSame {
            return NSURLAuthenticationMethodHTTPBasic
        } else if authScheme.caseInsensitiveCompare(_HTTPURLProtocol._HTTPMessage._Challenge.AuthSchemeDigest) == .orderedSame {
            return NSURLAuthenticationMethodHTTPDigest
        } else {
            return nil
        }
    }
}

class URLSessionAuthenticationChallengeSender : NSObject, URLAuthenticationChallengeSender {
    func cancel(_ challenge: URLAuthenticationChallenge) {
        fatalError("swift-corelibs-foundation only supports URLSession; for challenges coming from URLSession, please implement the appropriate URLSessionTaskDelegate methods rather than using the sender argument.")
    }
    
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {
        fatalError("swift-corelibs-foundation only supports URLSession; for challenges coming from URLSession, please implement the appropriate URLSessionTaskDelegate methods rather than using the sender argument.")
    }
    
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {
        fatalError("swift-corelibs-foundation only supports URLSession; for challenges coming from URLSession, please implement the appropriate URLSessionTaskDelegate methods rather than using the sender argument.")
    }
    
    func performDefaultHandling(for challenge: URLAuthenticationChallenge) {
        fatalError("swift-corelibs-foundation only supports URLSession; for challenges coming from URLSession, please implement the appropriate URLSessionTaskDelegate methods rather than using the sender argument.")
    }
    
    func rejectProtectionSpaceAndContinue(with challenge: URLAuthenticationChallenge) {
        fatalError("swift-corelibs-foundation only supports URLSession; for challenges coming from URLSession, please implement the appropriate URLSessionTaskDelegate methods rather than using the sender argument.")
    }
}

extension URLCredentialStorage {

    public func getCredentials(for protectionSpace: URLProtectionSpace, task: URLSessionTask, completionHandler: ([String : URLCredential]?) -> Void) {
        completionHandler(credentials(for: protectionSpace))
    }
    
    public func set(_ credential: URLCredential, for protectionSpace: URLProtectionSpace, task: URLSessionTask) {
        set(credential, for: protectionSpace)
    }
    
    public func remove(_ credential: URLCredential, for protectionSpace: URLProtectionSpace, options: [String : AnyObject]? = [:], task: URLSessionTask) {
        remove(credential, for: protectionSpace, options: options)
    }
    
    public func getDefaultCredential(for space: URLProtectionSpace, task: URLSessionTask, completionHandler: (URLCredential?) -> Void) {
        completionHandler(defaultCredential(for: space))
    }
    
    public func setDefaultCredential(_ credential: URLCredential, for protectionSpace: URLProtectionSpace, task: URLSessionTask) {
        setDefaultCredential(credential, for: protectionSpace)
    }
}
        """
    )

    replace('        webSocketTask.protocolPicked = response.value(forHTTPHeaderField: "Sec-WebSocket-Protocol")',
'''        if #available(iOS 13.0, *), #available(macOS 10.15, *) {
            webSocketTask.protocolPicked = response.value(forHTTPHeaderField: "Sec-WebSocket-Protocol")
        } else {
            webSocketTask.protocolPicked = response.allHeaderFields["Sec-WebSocket-Protocol"] as? String
        }''', "WebSocketURLProtocol")

    replace("fileprivate var headerList: _CurlStringList?",
            """fileprivate var headerList: _CurlStringList?
    fileprivate var resolveList: _CurlStringList?
    fileprivate var connectToList: _CurlStringList?""", "EasyHandle")

    replace("""    func set(customHeaders headers: [String]) {
        let list = _CurlStringList(headers)
        try! CFURLSession_easy_setopt_ptr(rawHandle, CFURLSessionOptionHTTPHEADER, list.asUnsafeMutablePointer).asError()
        // We need to retain the list for as long as the rawHandle is in use.
        headerList = list
    }""", """    func set(customHeaders headers: [String]) {
        let list = _CurlStringList(headers)
        try! CFURLSession_easy_setopt_ptr(rawHandle, CFURLSessionOptionHTTPHEADER, list.asUnsafeMutablePointer).asError()
        // We need to retain the list for as long as the rawHandle is in use.
        headerList = list
    }
    
    func set(resolve: String) {
        let list = _CurlStringList([resolve])
        try! CFURLSession_easy_setopt_ptr(rawHandle, CFURLSessionOptionRESOLVE, list.asUnsafeMutablePointer).asError()
        try! CFURLSession_easy_setopt_long(rawHandle, CFURLSessionOptionIPRESOLVE, 0).asError()
        // We need to retain the list for as long as the rawHandle is in use.
        resolveList = list
    }
    
    func set(connectTo: String) {
        let list = _CurlStringList([connectTo])
        try! CFURLSession_easy_setopt_ptr(rawHandle, CFURLSessionOptionCONNECT_TO, list.asUnsafeMutablePointer).asError()
        // We need to retain the list for as long as the rawHandle is in use.
        connectToList = list
    }
    """, "EasyHandle")

    replace("        if let hh = request.allHTTPHeaderFields {",
            """        if let resolve = request.value(forHTTPHeaderField: "resolve") {
            easyHandle.set(resolve: resolve)
        }
        
        if let connectTo = request.value(forHTTPHeaderField: "connectTo") {
            easyHandle.set(connectTo: connectTo)
        }
        
        if let hh = request.allHTTPHeaderFields?.filter({ (key, _) in
            key != "resolve" && key != "connectTo"
        }) {""", "HTTPURLProtocol")

    print("完成")


if __name__ == "__main__":
    pull_origin()
    modify()
