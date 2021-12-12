// Foundation/SSURLSession/SSURLSessionTask.swift - SSURLSession API
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2016 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
// -----------------------------------------------------------------------------
///
/// SSURLSession API code.
/// - SeeAlso: SSURLSession.swift
///
// -----------------------------------------------------------------------------

#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
import Foundation
#else
import Foundation
#endif
@_implementationOnly import CoreFoundation

private class Bag<Element> {
    var values: [Element] = []
}

/// A cancelable object that refers to the lifetime
/// of processing a given request.
@objc
open class SSURLSessionTask : NSObject, NSCopying {
    
    // These properties aren't heeded in swift-corelibs-foundation, but we may heed them in the future. They exist for source compatibility.
    open var countOfBytesClientExpectsToReceive: Int64 = NSURLSessionTransferSizeUnknown {
        didSet { updateProgress() }
    }
    open var countOfBytesClientExpectsToSend: Int64 = NSURLSessionTransferSizeUnknown {
        didSet { updateProgress() }
    }
    
    #if NS_CURL_MISSING_XFERINFOFUNCTION
    @available(*, deprecated, message: "This platform doesn't fully support reporting the progress of a SSURLSessionTask. The progress instance returned will be functional, but may not have continuous updates as bytes are sent or received.")
    open private(set) var progress = Progress(totalUnitCount: -1)
    #else
    open private(set) var progress = Progress(totalUnitCount: -1)
    #endif
    
    func updateProgress() {
        self.workQueue.async {
            let progress = self.progress
            
            switch self.state {
            case .canceling: fallthrough
            case .completed:
                let total = progress.totalUnitCount
                let finalTotal = total < 0 ? 1 : total
                progress.totalUnitCount = finalTotal
                progress.completedUnitCount = finalTotal
                
            default:
                let toBeSent: Int64?
                if let bodyLength = try? self.knownBody?.getBodyLength() {
                    toBeSent = Int64(clamping: bodyLength)
                } else if self.countOfBytesExpectedToSend > 0 {
                    toBeSent = Int64(clamping: self.countOfBytesExpectedToSend)
                } else if self.countOfBytesClientExpectsToSend != NSURLSessionTransferSizeUnknown && self.countOfBytesClientExpectsToSend > 0 {
                    toBeSent = Int64(clamping: self.countOfBytesClientExpectsToSend)
                } else {
                    toBeSent = nil
                }
                
                let sent = self.countOfBytesSent
                
                let toBeReceived: Int64?
                if self.countOfBytesExpectedToReceive > 0 {
                    toBeReceived = Int64(clamping: self.countOfBytesClientExpectsToReceive)
                } else if self.countOfBytesClientExpectsToReceive != NSURLSessionTransferSizeUnknown && self.countOfBytesClientExpectsToReceive > 0 {
                    toBeReceived = Int64(clamping: self.countOfBytesClientExpectsToReceive)
                } else {
                    toBeReceived = nil
                }
                
                let received = self.countOfBytesReceived
                
                progress.completedUnitCount = sent.addingReportingOverflow(received).partialValue
                
                if let toBeSent = toBeSent, let toBeReceived = toBeReceived {
                    progress.totalUnitCount = toBeSent.addingReportingOverflow(toBeReceived).partialValue
                } else {
                    progress.totalUnitCount = -1
                }
                
            }
        }
    }
    
    // We're not going to heed this one. If someone is setting it in Linux code, they may be relying on behavior that isn't there; warn.
    @available(*, deprecated, message: "swift-corelibs-foundation does not support background SSURLSession instances, and this property is documented to have no effect when set on tasks created from non-background SSURLSession instances. Modifying this property has no effect in swift-corelibs-foundation and shouldn't be relied upon; resume tasks at the appropriate time instead.")
    open var earliestBeginDate: Date? = nil
    
    /// How many times the task has been suspended, 0 indicating a running task.
    internal var suspendCount = 1
    
    internal var actualSession: SSURLSession? { return session as? SSURLSession }
    internal var session: SSURLSessionProtocol! //change to nil when task completes

    fileprivate enum ProtocolState {
        case toBeCreated
        case awaitingCacheReply(Bag<(SSURLProtocol?) -> Void>)
        case existing(SSURLProtocol)
        case invalidated
    }
    
    fileprivate let _protocolLock = NSLock() // protects:
    fileprivate var _protocolStorage: ProtocolState = .toBeCreated
    internal    var _lastCredentialUsedFromStorageDuringAuthentication: (protectionSpace: URLProtectionSpace, credential: URLCredential)?
    
    private var _protocolClass: SSURLProtocol.Type {
        guard let request = currentRequest else { fatalError("A protocol class was requested, but we do not have a current request") }
        let protocolClasses = session.configuration.protocolClasses ?? []
        if let urlProtocolClass = SSURLProtocol.getProtocolClass(protocols: protocolClasses, request: request) {
            guard let urlProtocol = urlProtocolClass as? SSURLProtocol.Type else { fatalError("A protocol class specified in the SSURLSessionConfiguration's .protocolClasses array was not a SSURLProtocol subclass: \(urlProtocolClass)") }
            return urlProtocol
        } else {
            let protocolClasses = SSURLProtocol.getProtocols() ?? []
            if let urlProtocolClass = SSURLProtocol.getProtocolClass(protocols: protocolClasses, request: request) {
                guard let urlProtocol = urlProtocolClass as? SSURLProtocol.Type else { fatalError("A protocol class registered with SSURLProtocol.register… was not a SSURLProtocol subclass: \(urlProtocolClass)") }
                return urlProtocol
            }
        }
        
        fatalError("Couldn't find a protocol appropriate for request: \(request)")
    }
    
    func _getProtocol(_ callback: @escaping (SSURLProtocol?) -> Void) {
        _protocolLock.lock() // Must be balanced below, before we call out ⬇
        
        switch _protocolStorage {
        case .toBeCreated:
            if let cache = session.configuration.urlCache, let me = self as? SSURLSessionDataTask {
                let bag: Bag<(SSURLProtocol?) -> Void> = Bag()
                bag.values.append(callback)
                
                _protocolStorage = .awaitingCacheReply(bag)
                _protocolLock.unlock() // Balances above ⬆
                
                cache.getCachedResponse(for: me) { (response) in
                    let urlProtocol = self._protocolClass.init(task: self, cachedResponse: response, client: nil)
                    self._satisfyProtocolRequest(with: urlProtocol)
                }
            } else {
                let urlProtocol = _protocolClass.init(task: self, cachedResponse: nil, client: nil)
                _protocolStorage = .existing(urlProtocol)
                _protocolLock.unlock() // Balances above ⬆
                
                callback(urlProtocol)
            }
            
        case .awaitingCacheReply(let bag):
            bag.values.append(callback)
            _protocolLock.unlock() // Balances above ⬆
        
        case .existing(let urlProtocol):
            _protocolLock.unlock() // Balances above ⬆
            
            callback(urlProtocol)
        
        case .invalidated:
            _protocolLock.unlock() // Balances above ⬆
            
            callback(nil)
        }
    }
    
    func _satisfyProtocolRequest(with urlProtocol: SSURLProtocol) {
        _protocolLock.lock() // Must be balanced below, before we call out ⬇
        switch _protocolStorage {
        case .toBeCreated:
            _protocolStorage = .existing(urlProtocol)
            _protocolLock.unlock() // Balances above ⬆
            
        case .awaitingCacheReply(let bag):
            _protocolStorage = .existing(urlProtocol)
            _protocolLock.unlock() // Balances above ⬆
            
            for callback in bag.values {
                callback(urlProtocol)
            }
            
        case .existing(_): fallthrough
        case .invalidated:
            _protocolLock.unlock() // Balances above ⬆
        }
    }
    
    func _invalidateProtocol() {
        _protocolLock.performLocked {
            _protocolStorage = .invalidated
        }
    }
    
    
    internal var knownBody: _Body?
    func getBody(completion: @escaping (_Body) -> Void) {
        if let body = knownBody {
            completion(body)
            return
        }
        
        if let session = actualSession, let delegate = session.delegate as? SSURLSessionTaskDelegate {
            delegate.urlSession(session, task: self) { (stream) in
                if let stream = stream {
                    completion(.stream(stream))
                } else {
                    completion(.none)
                }
            }
        } else {
            completion(.none)
        }
    }
    
    private let syncQ = DispatchQueue(label: "org.swift.SSURLSessionTask.SyncQ")
    private var hasTriggeredResume: Bool = false
    internal var isSuspendedAfterResume: Bool {
        return self.syncQ.sync { return self.hasTriggeredResume } && self.state == .suspended
    }
    
    /// All operations must run on this queue.
    internal let workQueue: DispatchQueue 
    
    public override init() {
        // Darwin Foundation oddly allows calling this initializer, even though
        // such a task is quite broken -- it doesn't have a session. And calling
        // e.g. `taskIdentifier` will crash.
        //
        // We set up the bare minimum for init to work, but don't care too much
        // about things crashing later.
        session = _SSMissingURLSession()
        taskIdentifier = 0
        originalRequest = nil
        knownBody = SSURLSessionTask._Body.none
        workQueue = DispatchQueue(label: "SSURLSessionTask.notused.0")
        super.init()
    }
    /// Create a data task. If there is a httpBody in the URLRequest, use that as a parameter
    internal convenience init(session: SSURLSession, request: URLRequest, taskIdentifier: Int) {
        if let bodyData = request.httpBody, !bodyData.isEmpty {
            self.init(session: session, request: request, taskIdentifier: taskIdentifier, body: _Body.data(createDispatchData(bodyData)))
        } else if let bodyStream = request.httpBodyStream {
            self.init(session: session, request: request, taskIdentifier: taskIdentifier, body: _Body.stream(bodyStream))
        } else {
            self.init(session: session, request: request, taskIdentifier: taskIdentifier, body: _Body.none)
        }
    }

    internal init(session: SSURLSession, request: URLRequest, taskIdentifier: Int, body: _Body?) {
        self.session = session
        /* make sure we're actually having a serial queue as it's used for synchronization */
        self.workQueue = DispatchQueue.init(label: "org.swift.SSURLSessionTask.WorkQueue", target: session.workQueue)
        self.taskIdentifier = taskIdentifier
        self.originalRequest = request
        self.knownBody = body
        super.init()
        self.currentRequest = request
        self.progress.cancellationHandler = { [weak self] in
            self?.cancel()
        }
    }
    deinit {
        //TODO: Do we remove the EasyHandle from the session here? This might run on the wrong thread / queue.
    }
    
    open override func copy() -> Any {
        return copy(with: nil)
    }
    
    open func copy(with zone: NSZone?) -> Any {
        return self
    }
    
    /// An identifier for this task, assigned by and unique to the owning session
    open internal(set) var taskIdentifier: Int
    
    /// May be nil if this is a stream task
    
    /*@NSCopying*/ open private(set) var originalRequest: URLRequest?

    /// If there's an authentication failure, we'd need to create a new request with the credentials supplied by the user
    var authRequest: URLRequest? = nil

    /// Authentication failure count
    fileprivate var previousFailureCount = 0
    
    /// May differ from originalRequest due to http server redirection
    /*@NSCopying*/ open internal(set) var currentRequest: URLRequest? {
        get {
            return self.syncQ.sync { return self._currentRequest }
        }
        set {
            self.syncQ.sync { self._currentRequest = newValue }
        }
    }
    fileprivate var _currentRequest: URLRequest? = nil
    /*@NSCopying*/ open internal(set) var response: URLResponse? {
        get {
            return self.syncQ.sync { return self._response }
        }
        set {
            self.syncQ.sync { self._response = newValue }
        }
    }
    fileprivate var _response: URLResponse? = nil
    
    /* Byte count properties may be zero if no body is expected,
     * or URLSessionTransferSizeUnknown if it is not possible
     * to know how many bytes will be transferred.
     */
    
    /// Number of body bytes already received
    open internal(set) var countOfBytesReceived: Int64 {
        get {
            return self.syncQ.sync { return self._countOfBytesReceived }
        }
        set {
            self.syncQ.sync { self._countOfBytesReceived = newValue }
            updateProgress()
        }
    }
    fileprivate var _countOfBytesReceived: Int64 = 0
    
    /// Number of body bytes already sent */
    open internal(set) var countOfBytesSent: Int64 {
        get {
            return self.syncQ.sync { return self._countOfBytesSent }
        }
        set {
            self.syncQ.sync { self._countOfBytesSent = newValue }
            updateProgress()
        }
    }
    
    fileprivate var _countOfBytesSent: Int64 = 0
    
    /// Number of body bytes we expect to send, derived from the Content-Length of the HTTP request */
    open internal(set) var countOfBytesExpectedToSend: Int64 = 0 {
        didSet { updateProgress() }
    }
    
    /// Number of bytes we expect to receive, usually derived from the Content-Length header of an HTTP response. */
    open internal(set) var countOfBytesExpectedToReceive: Int64 = 0 {
        didSet { updateProgress() }
    }
    
    /// The taskDescription property is available for the developer to
    /// provide a descriptive label for the task.
    open var taskDescription: String?
    
    /* -cancel returns immediately, but marks a task as being canceled.
     * The task will signal -SSURLSession:task:didCompleteWithError: with an
     * error value of { NSURLErrorDomain, NSURLErrorCancelled }.  In some
     * cases, the task may signal other work before it acknowledges the
     * cancellation.  -cancel may be sent to a task that has been suspended.
     */
    open func cancel() {
        workQueue.sync {
            let canceled = self.syncQ.sync { () -> Bool in
                guard self._state == .running || self._state == .suspended else { return true }
                self._state = .canceling
                return false
            }
            guard !canceled else { return }
            self._getProtocol { (urlProtocol) in
                self.workQueue.async {
                    var info = [NSLocalizedDescriptionKey: "\(URLError.Code.cancelled)" as Any]
                    if let url = self.originalRequest?.url {
                        info[NSURLErrorFailingURLErrorKey] = url
                        info[NSURLErrorFailingURLStringErrorKey] = url.absoluteString
                    }
                    let urlError = URLError(_nsError: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled, userInfo: info))
                    self.error = urlError
                    if let urlProtocol = urlProtocol {
                        urlProtocol.stopLoading()
                        urlProtocol.client?.urlProtocol(urlProtocol, didFailWithError: urlError)
                    }
                }
            }
        }
    }
    
    /*
     * The current state of the task within the session.
     */
    open fileprivate(set) var state: SSURLSessionTask.State {
        get {
            return self.syncQ.sync { self._state }
        }
        set {
            self.syncQ.sync { self._state = newValue }
        }
    }
    fileprivate var _state: SSURLSessionTask.State = .suspended
    
    /*
     * The error, if any, delivered via -SSURLSession:task:didCompleteWithError:
     * This property will be nil in the event that no error occurred.
     */
    /*@NSCopying*/ open internal(set) var error: Error?
    
    /// Suspend the task.
    ///
    /// Suspending a task will prevent the SSURLSession from continuing to
    /// load data.  There may still be delegate calls made on behalf of
    /// this task (for instance, to report data received while suspending)
    /// but no further transmissions will be made on behalf of the task
    /// until -resume is sent.  The timeout timer associated with the task
    /// will be disabled while a task is suspended. -suspend and -resume are
    /// nestable.
    open func suspend() {
        // suspend / resume is implemented simply by adding / removing the task's
        // easy handle fromt he session's multi-handle.
        //
        // This might result in slightly different behaviour than the Darwin Foundation
        // implementation, but it'll be difficult to get complete parity anyhow.
        // Too many things depend on timeout on the wire etc.
        //
        // TODO: It may be worth looking into starting over a task that gets
        // resumed. The Darwin Foundation documentation states that that's what
        // it does for anything but download tasks.
        
        // We perform the increment and call to `updateTaskState()`
        // synchronous, to make sure the `state` is updated when this method
        // returns, but the actual suspend will be done asynchronous to avoid
        // dead-locks.
        workQueue.sync {
            guard self.state != .canceling && self.state != .completed else { return }
            self.suspendCount += 1
            guard self.suspendCount < Int.max else { fatalError("Task suspended too many times \(Int.max).") }
            self.updateTaskState()
            
            if self.suspendCount == 1 {
                self._getProtocol { (urlProtocol) in
                    self.workQueue.async {
                        urlProtocol?.stopLoading()
                    }
                }
            }
        }
    }
    /// Resume the task.
    ///
    /// - SeeAlso: `suspend()`
    @objc
    open func resume() {
        workQueue.sync {
            guard self.state != .canceling && self.state != .completed else { return }
            if self.suspendCount > 0 { self.suspendCount -= 1 }
            self.updateTaskState()
            if self.suspendCount == 0 {
                self.hasTriggeredResume = true
                self._getProtocol { (urlProtocol) in
                    self.workQueue.async {
                        if let _protocol = urlProtocol {
                            _protocol.startLoading()
                        }
                        else if self.error == nil {
                            var userInfo: [String: Any] = [NSLocalizedDescriptionKey: "unsupported URL"]
                            if let url = self.originalRequest?.url {
                                userInfo[NSURLErrorFailingURLErrorKey] = url
                                userInfo[NSURLErrorFailingURLStringErrorKey] = url.absoluteString
                            }
                            let urlError = URLError(_nsError: NSError(domain: NSURLErrorDomain,
                                                                      code: NSURLErrorUnsupportedURL,
                                                                      userInfo: userInfo))
                            self.error = urlError
                            _SSProtocolClient().urlProtocol(task: self, didFailWithError: urlError)
                        }
                    }
                }
            }
        }
    }
    
    /// The priority of the task.
    ///
    /// Sets a scaling factor for the priority of the task. The scaling factor is a
    /// value between 0.0 and 1.0 (inclusive), where 0.0 is considered the lowest
    /// priority and 1.0 is considered the highest.
    ///
    /// The priority is a hint and not a hard requirement of task performance. The
    /// priority of a task may be changed using this API at any time, but not all
    /// protocols support this; in these cases, the last priority that took effect
    /// will be used.
    ///
    /// If no priority is specified, the task will operate with the default priority
    /// as defined by the constant SSURLSessionTask.defaultPriority. Two additional
    /// priority levels are provided: SSURLSessionTask.lowPriority and
    /// SSURLSessionTask.highPriority, but use is not restricted to these.
    open var priority: Float {
        get {
            return self.workQueue.sync { return self._priority }
        }
        set {
            self.workQueue.sync { self._priority = newValue }
        }
    }
    fileprivate var _priority: Float = SSURLSessionTask.defaultPriority
}

extension SSURLSessionTask {
    public enum State : Int {
        /// The task is currently being serviced by the session
        case running
        case suspended
        /// The task has been told to cancel.  The session will receive a SSURLSession:task:didCompleteWithError: message.
        case canceling
        /// The task has completed and the session will receive no more delegate notifications
        case completed
    }
}

extension SSURLSessionTask : ProgressReporting {}

extension SSURLSessionTask {
    /// Updates the (public) state based on private / internal state.
    ///
    /// - Note: This must be called on the `workQueue`.
    internal func updateTaskState() {
        func calculateState() -> SSURLSessionTask.State {
            if suspendCount == 0 {
                return .running
            } else {
                return .suspended
            }
        }
        state = calculateState()
    }
}

internal extension SSURLSessionTask {
    enum _Body {
        case none
        case data(DispatchData)
        /// Body data is read from the given file URL
        case file(URL)
        case stream(InputStream)
    }
}
internal extension SSURLSessionTask._Body {
    enum _Error : Error {
        case fileForBodyDataNotFound
    }
    /// - Returns: The body length, or `nil` for no body (e.g. `GET` request).
    func getBodyLength() throws -> UInt64? {
        switch self {
        case .none:
            return 0
        case .data(let d):
            return UInt64(d.count)
        /// Body data is read from the given file URL
        case .file(let fileURL):
            guard let s = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber else {
                throw _Error.fileForBodyDataNotFound
            }
            return s.uint64Value
        case .stream:
            return nil
        }
    }
}


fileprivate func errorCode(fileSystemError error: Error) -> Int {
    func fromCocoaErrorCode(_ code: Int) -> Int {
        switch code {
        case CocoaError.fileReadNoSuchFile.rawValue:
            return NSURLErrorFileDoesNotExist
        case CocoaError.fileReadNoPermission.rawValue:
            return NSURLErrorNoPermissionsToReadFile
        default:
            return NSURLErrorUnknown
        }
    }
    switch error {
    case let e as NSError where e.domain == NSCocoaErrorDomain:
        return fromCocoaErrorCode(e.code)
    default:
        return NSURLErrorUnknown
    }
}

extension SSURLSessionTask {
    /// The default URL session task priority, used implicitly for any task you
    /// have not prioritized. The floating point value of this constant is 0.5.
    public static let defaultPriority: Float = 0.5
    
    /// A low URL session task priority, with a floating point value above the
    /// minimum of 0 and below the default value.
    public static let lowPriority: Float = 0.25
    
    /// A high URL session task priority, with a floating point value above the
    /// default value and below the maximum of 1.0.
    public static let highPriority: Float = 0.75
}

/*
 * An SSURLSessionDataTask does not provide any additional
 * functionality over an SSURLSessionTask and its presence is merely
 * to provide lexical differentiation from download and upload tasks.
 */
open class SSURLSessionDataTask : SSURLSessionTask {
}

/*
 * An SSURLSessionUploadTask does not currently provide any additional
 * functionality over an SSURLSessionDataTask.  All delegate messages
 * that may be sent referencing an SSURLSessionDataTask equally apply
 * to URLSessionUploadTasks.
 */
open class SSURLSessionUploadTask : SSURLSessionDataTask {
}

/*
 * URLSessionDownloadTask is a task that represents a download to
 * local storage.
 */
open class URLSessionDownloadTask : SSURLSessionTask {
    
    var createdFromInvalidResumeData = false
    
    // If a task is created from invalid resume data, prevent attempting creation of the protocol object.
    override func _getProtocol(_ callback: @escaping (SSURLProtocol?) -> Void) {
        if createdFromInvalidResumeData {
            callback(nil)
        } else {
            super._getProtocol(callback)
        }
    }
    
    internal var fileLength = -1.0
    
    /* Cancel the download (and calls the superclass -cancel).  If
     * conditions will allow for resuming the download in the future, the
     * callback will be called with an opaque data blob, which may be used
     * with -downloadTaskWithResumeData: to attempt to resume the download.
     * If resume data cannot be created, the completion handler will be
     * called with nil resumeData.
     */
    open func cancel(byProducingResumeData completionHandler: @escaping (Data?) -> Void) {
        super.cancel()
        
        /*
         * In Objective-C, this method relies on an Apple-maintained XPC process
         * to manage the bookmarking of partially downloaded data. Therefore, the
         * original behavior cannot be directly ported, here.
         *
         * Instead, we just call the completionHandler directly.
         */
        completionHandler(nil)
    }
}

/* Key in the userInfo dictionary of an NSError received during a failed download. */
public let URLSessionDownloadTaskResumeData: String = "NSURLSessionDownloadTaskResumeData"

extension _SSProtocolClient : SSURLProtocolClient {

    func urlProtocol(_ protocol: SSURLProtocol, didReceive response: URLResponse, cacheStoragePolicy policy: SSURLCache.StoragePolicy) {
        guard let task = `protocol`.task else { fatalError("Received response, but there's no task.") }
        task.response = response
        let session = task.session as! SSURLSession
        guard let dataTask = task as? SSURLSessionDataTask else { return }
        
        // Only cache data tasks:
        self.cachePolicy = policy
        
        if session.configuration.urlCache != nil {
            switch policy {
            case .allowed: fallthrough
            case .allowedInMemoryOnly:
                cacheableData = []
                cacheableResponse = response
                
            case .notAllowed:
                break
            }
        }
        
        switch session.behaviour(for: task) {
        case .taskDelegate(let delegate as SSURLSessionDataDelegate):
            session.delegateQueue.addOperation {
                delegate.urlSession(session, dataTask: dataTask, didReceive: response, completionHandler: { _ in
                    SSURLSession.printDebug("warning: Ignoring disposition from completion handler.")
                })
            }
        case .noDelegate, .taskDelegate, .dataCompletionHandler, .downloadCompletionHandler:
            break
        }
    }

    func urlProtocolDidFinishLoading(_ urlProtocol: SSURLProtocol) {
        guard let task = urlProtocol.task else { fatalError() }
        guard let session = task.session as? SSURLSession else { fatalError() }
        let urlResponse = task.response
        if let response = urlResponse as? HTTPURLResponse, response.statusCode == 401 {
            if let protectionSpace = URLProtectionSpace.create(with: response) {

                func proceed(proposing credential: URLCredential?) {
                    let proposedCredential: URLCredential?
                    let last = task._protocolLock.performLocked { task._lastCredentialUsedFromStorageDuringAuthentication }
                    
                    if last?.credential != credential {
                        proposedCredential = credential
                    } else {
                        proposedCredential = nil
                    }
                    
                    let authenticationChallenge = URLAuthenticationChallenge(protectionSpace: protectionSpace, proposedCredential: proposedCredential,
                                                                             previousFailureCount: task.previousFailureCount, failureResponse: response, error: nil,
                                                                             sender: URLSessionAuthenticationChallengeSender())
                    task.previousFailureCount += 1
                    self.urlProtocol(urlProtocol, didReceive: authenticationChallenge)
                }
                
                if let storage = session.configuration.urlCredentialStorage {
                    storage.getCredentials(for: protectionSpace, task: task) { (credentials) in
                        if let credentials = credentials,
                            let firstKeyLexicographically = credentials.keys.sorted().first {
                            proceed(proposing: credentials[firstKeyLexicographically])
                        } else {
                            storage.getDefaultCredential(for: protectionSpace, task: task) { (credential) in
                                proceed(proposing: credential)
                            }
                        }
                    }
                } else {
                    proceed(proposing: nil)
                }
                
                return
            }
        }
        
        if let storage = session.configuration.urlCredentialStorage,
           let last = task._protocolLock.performLocked({ task._lastCredentialUsedFromStorageDuringAuthentication }) {
            storage.set(last.credential, for: last.protectionSpace, task: task)
        }
        
        if let cache = session.configuration.urlCache,
           let data = cacheableData,
           let response = cacheableResponse,
           let task = task as? SSURLSessionDataTask {
            
            let cacheable = SSCachedURLResponse(response: response, data: Data(data.joined()), storagePolicy: cachePolicy)
            let protocolAllows = (urlProtocol as? _SSNativeProtocol)?.canCache(cacheable) ?? false
            if protocolAllows {
                if let delegate = task.session.delegate as? SSURLSessionDataDelegate {
                    delegate.urlSession(task.session as! SSURLSession, dataTask: task, willCacheResponse: cacheable) { (actualCacheable) in
                        if let actualCacheable = actualCacheable {
                            cache.storeCachedResponse(actualCacheable, for: task)
                        }
                    }
                } else {
                    cache.storeCachedResponse(cacheable, for: task)
                }
            }
        }
        
        switch session.behaviour(for: task) {
        case .taskDelegate(let delegate):
            if let downloadDelegate = delegate as? SSURLSessionDownloadDelegate, let downloadTask = task as? URLSessionDownloadTask {
                session.delegateQueue.addOperation {
                    downloadDelegate.urlSession(session, downloadTask: downloadTask, didFinishDownloadingTo: urlProtocol.properties[SSURLProtocol._PropertyKey.temporaryFileURL] as! URL)
                }
            }
            session.delegateQueue.addOperation {
                guard task.state != .completed else { return }
                delegate.urlSession(session, task: task, didCompleteWithError: nil)
                task.state = .completed
                session.workQueue.async {
                    session.taskRegistry.remove(task)
                }
            }
        case .noDelegate:
            guard task.state != .completed else { break }
            task.state = .completed
            session.workQueue.async {
                session.taskRegistry.remove(task)
            }
        case .dataCompletionHandler(let completion):
            session.delegateQueue.addOperation {
                guard task.state != .completed else { return }
                completion(urlProtocol.properties[SSURLProtocol._PropertyKey.responseData] as? Data ?? Data(), task.response, nil)
                task.state = .completed
                session.workQueue.async {
                    session.taskRegistry.remove(task)
                }
            }
        case .downloadCompletionHandler(let completion):
            session.delegateQueue.addOperation {
                guard task.state != .completed else { return }
                completion(urlProtocol.properties[SSURLProtocol._PropertyKey.temporaryFileURL] as? URL, task.response, nil)
                task.state = .completed
                session.workQueue.async {
                    session.taskRegistry.remove(task)
                }
            }
        }
        task._invalidateProtocol()
    }

    func urlProtocol(_ protocol: SSURLProtocol, didCancel challenge: URLAuthenticationChallenge) {
        guard let task = `protocol`.task else { fatalError() }
        // Fail with a cancellation error, for now.
        urlProtocol(task: task, didFailWithError: NSError(domain: NSCocoaErrorDomain, code: CocoaError.userCancelled.rawValue))
    }

    func urlProtocol(_ protocol: SSURLProtocol, didReceive challenge: URLAuthenticationChallenge) {
        guard let task = `protocol`.task else { fatalError("Received response, but there's no task.") }
        guard let session = task.session as? SSURLSession else { fatalError("Task not associated with SSURLSession.") }
        
        func proceed(using credential: URLCredential?) {
            let protectionSpace = challenge.protectionSpace
            let authScheme = protectionSpace.authenticationMethod

            task.suspend()
            
            guard let handler = SSURLSessionTask.authHandler(for: authScheme) else {
                fatalError("\(authScheme) is not supported")
            }
            handler(task, .useCredential, credential)

            task._protocolLock.performLocked {
                if let credential = credential {
                    task._lastCredentialUsedFromStorageDuringAuthentication = (protectionSpace: protectionSpace, credential: credential)
                } else {
                    task._lastCredentialUsedFromStorageDuringAuthentication = nil
                }
                task._protocolStorage = .existing(_SSHTTPURLProtocol(task: task, cachedResponse: nil, client: nil))
            }
            
            task.resume()
        }
        
        func attemptProceedingWithDefaultCredential() {
            if let credential = challenge.proposedCredential {
                let last = task._protocolLock.performLocked { task._lastCredentialUsedFromStorageDuringAuthentication }
                
                if last?.credential != credential {
                    proceed(using: credential)
                } else {
                    task.cancel()
                }
            }
        }
        
        if let delegate = session.delegate as? SSURLSessionTaskDelegate {
            session.delegateQueue.addOperation {
                delegate.urlSession(session, task: task, didReceive: challenge) { disposition, credential in
                    
                    switch disposition {
                    case .useCredential:
                        proceed(using: credential!)
                        
                    case .performDefaultHandling:
                        attemptProceedingWithDefaultCredential()
                        
                    case .rejectProtectionSpace:
                        // swift-corelibs-foundation currently supports only a single protection space per request.
                        fallthrough
                    case .cancelAuthenticationChallenge:
                        task.cancel()
                    }
                    
                }
            }
        } else {
            attemptProceedingWithDefaultCredential()
        }
    }

    func urlProtocol(_ protocol: SSURLProtocol, didLoad data: Data) {
        `protocol`.properties[.responseData] = data
        guard let task = `protocol`.task else { fatalError() }
        guard let session = task.session as? SSURLSession else { fatalError() }
        
        switch cachePolicy {
        case .allowed: fallthrough
        case .allowedInMemoryOnly:
            cacheableData?.append(data)

        case .notAllowed:
            break
        }
        
        switch session.behaviour(for: task) {
        case .taskDelegate(let delegate):
            let dataDelegate = delegate as? SSURLSessionDataDelegate
            let dataTask = task as? SSURLSessionDataTask
            session.delegateQueue.addOperation {
                dataDelegate?.urlSession(session, dataTask: dataTask!, didReceive: data)
            }
        default: return
        }
    }

    func urlProtocol(_ protocol: SSURLProtocol, didFailWithError error: Error) {
        guard let task = `protocol`.task else { fatalError() }
        urlProtocol(task: task, didFailWithError: error)
    }

    func urlProtocol(task: SSURLSessionTask, didFailWithError error: Error) {
        guard let session = task.session as? SSURLSession else { fatalError() }
        switch session.behaviour(for: task) {
        case .taskDelegate(let delegate):
            session.delegateQueue.addOperation {
                guard task.state != .completed else { return }
                delegate.urlSession(session, task: task, didCompleteWithError: error as Error)
                task.state = .completed
                session.workQueue.async {
                    session.taskRegistry.remove(task)
                }
            }
        case .noDelegate:
            guard task.state != .completed else { break }
            task.state = .completed
            session.workQueue.async {
                session.taskRegistry.remove(task)
            }
        case .dataCompletionHandler(let completion):
            session.delegateQueue.addOperation {
                guard task.state != .completed else { return }
                completion(nil, nil, error)
                task.state = .completed
                session.workQueue.async {
                    session.taskRegistry.remove(task)
                }
            }
        case .downloadCompletionHandler(let completion):
            session.delegateQueue.addOperation {
                guard task.state != .completed else { return }
                completion(nil, nil, error)
                task.state = .completed
                session.workQueue.async {
                    session.taskRegistry.remove(task)
                }
            }
        }
        task._invalidateProtocol()
    }

    func urlProtocol(_ protocol: SSURLProtocol, cachedResponseIsValid cachedResponse: SSCachedURLResponse) {}

    func urlProtocol(_ protocol: SSURLProtocol, wasRedirectedTo request: URLRequest, redirectResponse: URLResponse) {
        fatalError("The SSURLSession swift-corelibs-foundation implementation doesn't currently handle redirects directly.")
    }
}
extension SSURLSessionTask {
    typealias _AuthHandler = ((SSURLSessionTask, SSURLSession.AuthChallengeDisposition, URLCredential?) -> ())

    static func authHandler(for authScheme: String) -> _AuthHandler? {
        let handlers: [String : _AuthHandler] = [
            NSURLAuthenticationMethodHTTPBasic : basicAuth,
            NSURLAuthenticationMethodHTTPDigest: digestAuth
        ]
        return handlers[authScheme]
    }

    //Authentication handlers
    static func basicAuth(_ task: SSURLSessionTask, _ disposition: SSURLSession.AuthChallengeDisposition, _ credential: URLCredential?) {
        //TODO: Handle disposition. For now, we default to .useCredential
        let user = credential?.user ?? ""
        let password = credential?.password ?? ""
        let encodedString = "\(user):\(password)".data(using: .utf8)?.base64EncodedString()
        task.authRequest = task.originalRequest
        task.authRequest?.setValue("Basic \(encodedString!)", forHTTPHeaderField: "Authorization")
    }

    static func digestAuth(_ task: SSURLSessionTask, _ disposition: SSURLSession.AuthChallengeDisposition, _ credential: URLCredential?) {
        fatalError("The SSURLSession swift-corelibs-foundation implementation doesn't currently handle digest authentication.")
    }
}

extension SSURLProtocol {
    enum _PropertyKey: String {
        case responseData
        case temporaryFileURL
    }
}

extension URLProtectionSpace {
    //an internal helper to create a URLProtectionSpace from a HTTPURLResponse
    static func create(with response: HTTPURLResponse) -> URLProtectionSpace? {
        // Using first challenge, as we don't support multiple challenges yet
        guard let challenge = _SSHTTPURLProtocol._HTTPMessage._Challenge.challenges(from: response).first else {
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

extension _SSHTTPURLProtocol._HTTPMessage._Challenge {
    var authenticationMethod: String? {
        if authScheme.caseInsensitiveCompare(_SSHTTPURLProtocol._HTTPMessage._Challenge.AuthSchemeBasic) == .orderedSame {
            return NSURLAuthenticationMethodHTTPBasic
        } else if authScheme.caseInsensitiveCompare(_SSHTTPURLProtocol._HTTPMessage._Challenge.AuthSchemeDigest) == .orderedSame {
            return NSURLAuthenticationMethodHTTPDigest
        } else {
            return nil
        }
    }
}

class URLSessionAuthenticationChallengeSender : NSObject, URLAuthenticationChallengeSender {
    func cancel(_ challenge: URLAuthenticationChallenge) {
        fatalError("swift-corelibs-foundation only supports SSURLSession; for challenges coming from SSURLSession, please implement the appropriate SSURLSessionTaskDelegate methods rather than using the sender argument.")
    }
    
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {
        fatalError("swift-corelibs-foundation only supports SSURLSession; for challenges coming from SSURLSession, please implement the appropriate SSURLSessionTaskDelegate methods rather than using the sender argument.")
    }
    
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {
        fatalError("swift-corelibs-foundation only supports SSURLSession; for challenges coming from SSURLSession, please implement the appropriate SSURLSessionTaskDelegate methods rather than using the sender argument.")
    }
    
    func performDefaultHandling(for challenge: URLAuthenticationChallenge) {
        fatalError("swift-corelibs-foundation only supports SSURLSession; for challenges coming from SSURLSession, please implement the appropriate SSURLSessionTaskDelegate methods rather than using the sender argument.")
    }
    
    func rejectProtectionSpaceAndContinue(with challenge: URLAuthenticationChallenge) {
        fatalError("swift-corelibs-foundation only supports SSURLSession; for challenges coming from SSURLSession, please implement the appropriate SSURLSessionTaskDelegate methods rather than using the sender argument.")
    }
}

extension URLCredentialStorage {
    public func getCredentials(for protectionSpace: URLProtectionSpace, task: SSURLSessionTask, completionHandler: ([String : URLCredential]?) -> Void) {
        completionHandler(credentials(for: protectionSpace))
    }
    
    public func set(_ credential: URLCredential, for protectionSpace: URLProtectionSpace, task: SSURLSessionTask) {
        set(credential, for: protectionSpace)
    }
    
    public func remove(_ credential: URLCredential, for protectionSpace: URLProtectionSpace, options: [String : AnyObject]? = [:], task: SSURLSessionTask) {
        remove(credential, for: protectionSpace, options: options)
    }
    
    public func getDefaultCredential(for space: URLProtectionSpace, task: SSURLSessionTask, completionHandler: (URLCredential?) -> Void) {
        completionHandler(defaultCredential(for: space))
    }
    
    public func setDefaultCredential(_ credential: URLCredential, for protectionSpace: URLProtectionSpace, task: SSURLSessionTask) {
        setDefaultCredential(credential, for: protectionSpace)
    }
}
