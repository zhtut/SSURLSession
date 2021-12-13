// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2015 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//

/*
 
 SSURLSession is a replacement API for URLConnection.  It provides
 options that affect the policy of, and various aspects of the
 mechanism by which NSURLRequest objects are retrieved from the
 network.
 
 An SSURLSession may be bound to a delegate object.  The delegate is
 invoked for certain events during the lifetime of a session, such as
 server authentication or determining whether a resource to be loaded
 should be converted into a download.
 
 SSURLSession instances are threadsafe.
 
 The default SSURLSession uses a system provided delegate and is
 appropriate to use in place of existing code that uses
 +[NSURLConnection sendAsynchronousRequest:queue:completionHandler:]
 
 An SSURLSession creates SSURLSessionTask objects which represent the
 action of a resource being loaded.  These are analogous to
 NSURLConnection objects but provide for more control and a unified
 delegate model.
 
 SSURLSessionTask objects are always created in a suspended state and
 must be sent the -resume message before they will execute.
 
 Subclasses of SSURLSessionTask are used to syntactically
 differentiate between data and file downloads.
 
 An SSURLSessionDataTask receives the resource as a series of calls to
 the SSURLSession:dataTask:didReceiveData: delegate method.  This is type of
 task most commonly associated with retrieving objects for immediate parsing
 by the consumer.
 
 An SSURLSessionUploadTask differs from an SSURLSessionDataTask
 in how its instance is constructed.  Upload tasks are explicitly created
 by referencing a file or data object to upload, or by utilizing the
 -SSURLSession:task:needNewBodyStream: delegate message to supply an upload
 body.
 
 An URLSessionDownloadTask will directly write the response data to
 a temporary file.  When completed, the delegate is sent
 SSURLSession:downloadTask:didFinishDownloadingToURL: and given an opportunity
 to move this file to a permanent location in its sandboxed container, or to
 otherwise read the file. If canceled, an URLSessionDownloadTask can
 produce a data blob that can be used to resume a download at a later
 time.
 
 Beginning with iOS 9 and Mac OS X 10.11, URLSessionStream is
 available as a task type.  This allows for direct TCP/IP connection
 to a given host and port with optional secure handshaking and
 navigation of proxies.  Data tasks may also be upgraded to a
 URLSessionStream task via the HTTP Upgrade: header and appropriate
 use of the pipelining option of SSURLSessionConfiguration.  See RFC
 2817 and RFC 6455 for information about the Upgrade: header, and
 comments below on turning data tasks into stream tasks.
 */

/* DataTask objects receive the payload through zero or more delegate messages */
/* UploadTask objects receive periodic progress updates but do not return a body */
/* DownloadTask objects represent an active download to disk.  They can provide resume data when canceled. */
/* StreamTask objects may be used to create NSInput and OutputStreams, or used directly in reading and writing. */

/*
 
 SSURLSession is not available for i386 targets before Mac OS X 10.10.
 
 */


// -----------------------------------------------------------------------------
/// # SSURLSession API implementation overview
///
/// ## Design Overview
///
/// This implementation uses libcurl for the HTTP layer implementation. At a
/// high level, the `SSURLSession` keeps a *multi handle*, and each
/// `SSURLSessionTask` has an *easy handle*. This way these two APIs somewhat
/// have a 1-to-1 mapping.
///
/// The `SSURLSessionTask` class is in charge of configuring its *easy handle*
/// and adding it to the owning session’s *multi handle*. Adding / removing
/// the handle effectively resumes / suspends the transfer.
///
/// The `SSURLSessionTask` class has subclasses, but this design puts all the
/// logic into the parent `SSURLSessionTask`.
///
/// Both the `SSURLSession` and `SSURLSessionTask` extensively use helper
/// types to ease testability, separate responsibilities, and improve
/// readability. These types are nested inside the `SSURLSession` and
/// `SSURLSessionTask` to limit their scope. Some of these even have sub-types.
///
/// The session class uses the `SSURLSession.TaskRegistry` to keep track of its
/// tasks.
///
/// The task class uses an `InternalState` type together with `TransferState` to
/// keep track of its state and each transfer’s state -- note that a single task
/// may do multiple transfers, e.g. as the result of a redirect.
///
/// ## Error Handling
///
/// Most libcurl functions either return a `CURLcode` or `CURLMcode` which
/// are represented in Swift as `CFURLSessionEasyCode` and
/// `CFURLSessionMultiCode` respectively. We turn these functions into throwing
/// functions by appending `.asError()` onto their calls. This turns the error
/// code into `Void` but throws the error if it's not `.OK` / zero.
///
/// This is combined with `try!` is almost all places, because such an error
/// indicates a programming error. Hence the pattern used in this code is
///
/// ```
/// try! someFunction().asError()
/// ```
///
/// where `someFunction()` is a function that returns a `CFURLSessionEasyCode`.
///
/// ## Threading
///
/// The SSURLSession has a libdispatch ‘work queue’, and all internal work is
/// done on that queue, such that the code doesn't have to deal with thread
/// safety beyond that. All work inside a `SSURLSessionTask` will run on this
/// work queue, and so will code manipulating the session's *multi handle*.
///
/// Delegate callbacks are, however, done on the passed in
/// `delegateQueue`. And any calls into this API need to switch onto the ‘work
/// queue’ as needed.
///
/// - SeeAlso: https://curl.haxx.se/libcurl/c/threadsafe.html
/// - SeeAlso: SSURLSession+libcurl.swift
///
/// ## HTTP and RFC 2616
///
/// Most of HTTP is defined in [RFC 2616](https://tools.ietf.org/html/rfc2616).
/// While libcurl handles many of these details, some are handled by this
/// SSURLSession implementation.
///
/// ## To Do
///
/// - TODO: Is is not clear if using API that takes a URLRequest will override
/// all settings of the SSURLSessionConfiguration or just those that have not
/// explicitly been set.
/// E.g. creating an URLRequest will cause it to have the default timeoutInterval
/// of 60 seconds, but should this be used in stead of the configuration's
/// timeoutIntervalForRequest even if the request's timeoutInterval has not
/// been set explicitly?
///
/// - TODO: We could re-use EasyHandles once they're complete. That'd be a
/// performance optimization. Not sure how much that'd help. The SSURLSession
/// would have to keep a pool of unused handles.
///
/// - TODO: Could make `workQueue` concurrent and use a multiple reader / single
/// writer approach if it turns out that there's contention.
// -----------------------------------------------------------------------------


#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
import Foundation
#else
import Foundation
#endif
@_implementationOnly import CoreFoundation

extension SSURLSession {
    public enum DelayedRequestDisposition {
        case cancel
        case continueLoading
        case useNewRequest
    }
}

fileprivate let globalVarSyncQ = DispatchQueue(label: "org.swift.Foundation.SSURLSession.GlobalVarSyncQ")
fileprivate var sessionCounter = Int32(0)
fileprivate func nextSessionIdentifier() -> Int32 {
    return globalVarSyncQ.sync {
        sessionCounter += 1
        return sessionCounter
    }
}
public let NSURLSessionTransferSizeUnknown: Int64 = -1

@objc
open class SSURLSession : NSObject {
    internal let _configuration: _Configuration
    fileprivate let multiHandle: _MultiHandle
    fileprivate var nextTaskIdentifier = 1
    internal let workQueue: DispatchQueue 
    internal let taskRegistry = SSURLSession._TaskRegistry()
    fileprivate let identifier: Int32
    fileprivate var invalidated = false
    fileprivate static let registerProtocols: () = {
        // TODO: We register all the native protocols here.
        _ = SSURLProtocol.registerClass(_SSHTTPURLProtocol.self)
    }()
    
    /*
     * The shared session uses the currently set global SSURLCache,
     * HTTPCookieStorage and URLCredential.Storage objects.
     */
    @objc
    open class var shared: SSURLSession {
        return _shared
    }
    
    fileprivate static let _shared: SSURLSession = {
        var configuration = SSURLSessionConfiguration.default
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        configuration.protocolClasses = SSURLProtocol.getProtocols()
        return SSURLSession(configuration: configuration, delegate: nil, delegateQueue: nil)
    }()

    /*
     * Customization of SSURLSession occurs during creation of a new session.
     * If you only need to use the convenience routines with custom
     * configuration options it is not necessary to specify a delegate.
     * If you do specify a delegate, the delegate will be retained until after
     * the delegate has been sent the SSURLSession:didBecomeInvalidWithError: message.
     */
    @objc
    public /*not inherited*/ init(configuration: SSURLSessionConfiguration) {
        initializeLibcurl()
        identifier = nextSessionIdentifier()
        self.workQueue = DispatchQueue(label: "SSURLSession<\(identifier)>")
        self.delegateQueue = OperationQueue()
        self.delegateQueue.maxConcurrentOperationCount = 1
        self.delegate = nil
        //TODO: Make sure this one can't be written to?
        // Could create a subclass of SSURLSessionConfiguration that wraps the
        // SSURLSession._Configuration and with fatalError() in all setters.
        self.configuration = configuration.copy() as! SSURLSessionConfiguration
        let c = SSURLSession._Configuration(SSURLSessionConfiguration: configuration)
        self._configuration = c
        self.multiHandle = _MultiHandle(configuration: c, workQueue: workQueue)
        // registering all the protocol classes with SSURLProtocol
        let _ = SSURLSession.registerProtocols
    }

    /*
     * A delegate queue should be serial to ensure correct ordering of callbacks.
     * However, if user supplies a concurrent delegateQueue it is not converted to serial.
     */
    public /*not inherited*/ init(configuration: SSURLSessionConfiguration, delegate: SSURLSessionDelegate?, delegateQueue queue: OperationQueue?) {
        initializeLibcurl()
        identifier = nextSessionIdentifier()
        self.workQueue = DispatchQueue(label: "SSURLSession<\(identifier)>")
        if let _queue = queue {
           self.delegateQueue = _queue
        } else {
           self.delegateQueue = OperationQueue()
           self.delegateQueue.maxConcurrentOperationCount = 1
        }
        self.delegate = delegate
        //TODO: Make sure this one can't be written to?
        // Could create a subclass of SSURLSessionConfiguration that wraps the
        // SSURLSession._Configuration and with fatalError() in all setters.
        self.configuration = configuration.copy() as! SSURLSessionConfiguration
        let c = SSURLSession._Configuration(SSURLSessionConfiguration: configuration)
        self._configuration = c
        self.multiHandle = _MultiHandle(configuration: c, workQueue: workQueue)
        // registering all the protocol classes with SSURLProtocol
        let _ = SSURLSession.registerProtocols
    }
    
    open private(set) var delegateQueue: OperationQueue
    open private(set) var delegate: SSURLSessionDelegate?
    open private(set) var configuration: SSURLSessionConfiguration
    
    /*
     * The sessionDescription property is available for the developer to
     * provide a descriptive label for the session.
     */
    open var sessionDescription: String?
    
    /* -finishTasksAndInvalidate returns immediately and existing tasks will be allowed
     * to run to completion.  New tasks may not be created.  The session
     * will continue to make delegate callbacks until SSURLSession:didBecomeInvalidWithError:
     * has been issued.
     *
     * -finishTasksAndInvalidate and -invalidateAndCancel do not
     * have any effect on the shared session singleton.
     *
     * When invalidating a background session, it is not safe to create another background
     * session with the same identifier until SSURLSession:didBecomeInvalidWithError: has
     * been issued.
     */
    @objc
    open func finishTasksAndInvalidate() {
       //we need to return immediately
       workQueue.async {
           //don't allow creation of new tasks from this point onwards
           self.invalidated = true

           let invalidateSessionCallback = { [weak self] in
               //invoke the delegate method and break the delegate link
               guard let strongSelf = self, let sessionDelegate = strongSelf.delegate else { return }
               strongSelf.delegateQueue.addOperation {
                   sessionDelegate.urlSession(strongSelf, didBecomeInvalidWithError: nil)
                   strongSelf.delegate = nil
               }
           }

           //wait for running tasks to finish
           if !self.taskRegistry.isEmpty {
               self.taskRegistry.notify(on: invalidateSessionCallback)
           } else {
               invalidateSessionCallback()
           }
       }
    }
    
    /* -invalidateAndCancel acts as -finishTasksAndInvalidate, but issues
     * -cancel to all outstanding tasks for this session.  Note task
     * cancellation is subject to the state of the task, and some tasks may
     * have already have completed at the time they are sent -cancel.
     */
    @objc
    open func invalidateAndCancel() {
        /*
         As per documentation,
         Calling this method on the session returned by the sharedSession method has no effect.
         */
        guard self !== SSURLSession.shared else { return }
        
        workQueue.sync {
            self.invalidated = true
        }
        
        for task in taskRegistry.allTasks {
            task.cancel()
        }
        
        // Don't allow creation of new tasks from this point onwards
        workQueue.async {
            guard let sessionDelegate = self.delegate else { return }
            
            self.delegateQueue.addOperation {
                sessionDelegate.urlSession(self, didBecomeInvalidWithError: nil)
                self.delegate = nil
            }
        }
    }
    
    /* empty all cookies, cache and credential stores, removes disk files, issues -flushWithCompletionHandler:. Invokes completionHandler() on the delegate queue. */
    @objc
    open func reset(completionHandler: @escaping () -> Void) {
        let configuration = self.configuration
        
        DispatchQueue.global(qos: .background).async {
            configuration.urlCache?.removeAllCachedResponses()
            if let storage = configuration.urlCredentialStorage {
                for credentialEntry in storage.allCredentials {
                    for credential in credentialEntry.value {
                        storage.remove(credential.value, for: credentialEntry.key)
                    }
                }
            }
            
            self.flush(completionHandler: completionHandler)
        }
    }
    
     /* flush storage to disk and clear transient network caches.  Invokes completionHandler() on the delegate queue. */
    @objc
    open func flush(completionHandler: @escaping () -> Void) {
        // We create new CURL handles every request.
        delegateQueue.addOperation {
            completionHandler()
        }
    }

    /* invokes completionHandler with outstanding data, upload and download tasks. */
    @objc
    open func getTasksWithCompletionHandler(_ completionHandler: @escaping ([SSURLSessionDataTask], [SSURLSessionUploadTask], [URLSessionDownloadTask]) -> Void)  {
        workQueue.async {
            self.delegateQueue.addOperation {
                var dataTasks = [SSURLSessionDataTask]()
                var uploadTasks = [SSURLSessionUploadTask]()
                var downloadTasks = [URLSessionDownloadTask]()

                for task in self.taskRegistry.allTasks {
                    guard task.state == .running || task.isSuspendedAfterResume else { continue }

                    if let uploadTask = task as? SSURLSessionUploadTask {
                        uploadTasks.append(uploadTask)
                    } else if let dataTask = task as? SSURLSessionDataTask {
                        dataTasks.append(dataTask)
                    } else if let downloadTask = task as? URLSessionDownloadTask {
                        downloadTasks.append(downloadTask)
                    } else {
                        // Above three are the only required tasks to be returned from this API, so we can ignore any other types of tasks.
                    }
                }
                completionHandler(dataTasks, uploadTasks, downloadTasks)
            }
        }
    }
    
    /* invokes completionHandler with all outstanding tasks. */
    @objc
    open func getAllTasks(completionHandler: @escaping ([SSURLSessionTask]) -> Void)  {
        workQueue.async {
            self.delegateQueue.addOperation {
                completionHandler(self.taskRegistry.allTasks.filter { $0.state == .running || $0.isSuspendedAfterResume })
            }
        }
    }
    
    /*
     * SSURLSessionTask objects are always created in a suspended state and
     * must be sent the -resume message before they will execute.
     */
    
    /* Creates a data task with the given request.  The request may have a body stream. */
    @objc
    open func dataTask(with request: URLRequest) -> SSURLSessionDataTask {
        return dataTask(with: _Request(request), behaviour: .callDelegate)
    }
    
    /* Creates a data task to retrieve the contents of the given URL. */
    open func dataTask(with url: URL) -> SSURLSessionDataTask {
        return dataTask(with: _Request(url), behaviour: .callDelegate)
    }

    /*
     * data task convenience methods.  These methods create tasks that
     * bypass the normal delegate calls for response and data delivery,
     * and provide a simple cancelable asynchronous interface to receiving
     * data.  Errors will be returned in the NSURLErrorDomain,
     * see <Foundation/NSURLError.h>.  The delegate, if any, will still be
     * called for authentication challenges.
     */
    @objc
    open func dataTask(with request: URLRequest, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> SSURLSessionDataTask {
        return dataTask(with: _Request(request), behaviour: .dataCompletionHandler(completionHandler))
    }

    open func dataTask(with url: URL, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> SSURLSessionDataTask {
        return dataTask(with: _Request(url), behaviour: .dataCompletionHandler(completionHandler))
    }
    
    /* Creates an upload task with the given request.  The body of the request will be created from the file referenced by fileURL */
    @objc
    open func uploadTask(with request: URLRequest, fromFile fileURL: URL) -> SSURLSessionUploadTask {
        let r = SSURLSession._Request(request)
        return uploadTask(with: r, body: .file(fileURL), behaviour: .callDelegate)
    }
    
    /* Creates an upload task with the given request.  The body of the request is provided from the bodyData. */
    @objc
    open func uploadTask(with request: URLRequest, from bodyData: Data) -> SSURLSessionUploadTask {
        let r = SSURLSession._Request(request)
        return uploadTask(with: r, body: .data(createDispatchData(bodyData)), behaviour: .callDelegate)
    }
    
    /* Creates an upload task with the given request.  The previously set body stream of the request (if any) is ignored and the SSURLSession:task:needNewBodyStream: delegate will be called when the body payload is required. */
    @objc
    open func uploadTask(withStreamedRequest request: URLRequest) -> SSURLSessionUploadTask {
        let r = SSURLSession._Request(request)
        return uploadTask(with: r, body: nil, behaviour: .callDelegate)
    }

    /*
     * upload convenience method.
     */
    @objc
    open func uploadTask(with request: URLRequest, fromFile fileURL: URL, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> SSURLSessionUploadTask {
        let r = SSURLSession._Request(request)
        return uploadTask(with: r, body: .file(fileURL), behaviour: .dataCompletionHandler(completionHandler))
    }

    @objc
    open func uploadTask(with request: URLRequest, from bodyData: Data?, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> SSURLSessionUploadTask {
        return uploadTask(with: _Request(request), body: .data(createDispatchData(bodyData!)), behaviour: .dataCompletionHandler(completionHandler))
    }
    
    /* Creates a download task with the given request. */
    @objc
    open func downloadTask(with request: URLRequest) -> URLSessionDownloadTask {
        let r = SSURLSession._Request(request)
        return downloadTask(with: r, behavior: .callDelegate)
    }
    
    /* Creates a download task to download the contents of the given URL. */
    open func downloadTask(with url: URL) -> URLSessionDownloadTask {
        return downloadTask(with: _Request(url), behavior: .callDelegate)
    }
    
    /* Creates a download task with the resume data.  If the download cannot be successfully resumed, SSURLSession:task:didCompleteWithError: will be called. */
    @objc
    open func downloadTask(withResumeData resumeData: Data) -> URLSessionDownloadTask {
        return invalidDownloadTask(behavior: .callDelegate)
    }

    /*
     * download task convenience methods.  When a download successfully
     * completes, the URL will point to a file that must be read or
     * copied during the invocation of the completion routine.  The file
     * will be removed automatically.
     */
    @objc
    open func downloadTask(with request: URLRequest, completionHandler: @escaping (URL?, URLResponse?, Error?) -> Void) -> URLSessionDownloadTask {
        return downloadTask(with: _Request(request), behavior: .downloadCompletionHandler(completionHandler))
    }

    open func downloadTask(with url: URL, completionHandler: @escaping (URL?, URLResponse?, Error?) -> Void) -> URLSessionDownloadTask {
       return downloadTask(with: _Request(url), behavior: .downloadCompletionHandler(completionHandler))
    }

    @objc
    open func downloadTask(withResumeData resumeData: Data, completionHandler: @escaping (URL?, URLResponse?, Error?) -> Void) -> URLSessionDownloadTask {
        return invalidDownloadTask(behavior: .downloadCompletionHandler(completionHandler))
    }
}


// Helpers
fileprivate extension SSURLSession {
    enum _Request {
        case request(URLRequest)
        case url(URL)
    }
    func createConfiguredRequest(from request: SSURLSession._Request) -> URLRequest {
        let r = request.createMutableURLRequest()
        return _configuration.configure(request: r)
    }
}
extension SSURLSession._Request {
    init(_ url: URL) {
        self = .url(url)
    }
    init(_ request: URLRequest) {
        self = .request(request)
    }
}
extension SSURLSession._Request {
    func createMutableURLRequest() -> URLRequest {
        switch self {
        case .url(let url): return URLRequest(url: url)
        case .request(let r): return r
        }
    }
}

fileprivate extension SSURLSession {
    func createNextTaskIdentifier() -> Int {
        return workQueue.sync {
            let i = nextTaskIdentifier
            nextTaskIdentifier += 1
            return i
        }
    }
}

fileprivate extension SSURLSession {
    /// Create a data task.
    ///
    /// All public methods funnel into this one.
    func dataTask(with request: _Request, behaviour: _TaskRegistry._Behaviour) -> SSURLSessionDataTask {
        guard !self.invalidated else { fatalError("Session invalidated") }
        let r = createConfiguredRequest(from: request)
        let i = createNextTaskIdentifier()
        let task = SSURLSessionDataTask(session: self, request: r, taskIdentifier: i)
        workQueue.async {
            self.taskRegistry.add(task, behaviour: behaviour)
        }
        return task
    }
    
    /// Create an upload task.
    ///
    /// All public methods funnel into this one.
    func uploadTask(with request: _Request, body: SSURLSessionTask._Body?, behaviour: _TaskRegistry._Behaviour) -> SSURLSessionUploadTask {
        guard !self.invalidated else { fatalError("Session invalidated") }
        let r = createConfiguredRequest(from: request)
        let i = createNextTaskIdentifier()
        let task = SSURLSessionUploadTask(session: self, request: r, taskIdentifier: i, body: body)
        workQueue.async {
            self.taskRegistry.add(task, behaviour: behaviour)
        }
        return task
    }
    
    /// Create a download task
    func downloadTask(with request: _Request, behavior: _TaskRegistry._Behaviour) -> URLSessionDownloadTask {
        guard !self.invalidated else { fatalError("Session invalidated") }
        let r = createConfiguredRequest(from: request)
        let i = createNextTaskIdentifier()
        let task = URLSessionDownloadTask(session: self, request: r, taskIdentifier: i)
        workQueue.async {
            self.taskRegistry.add(task, behaviour: behavior)
        }
        return task
    }
    
    /// Create a download task that is marked invalid.
    func invalidDownloadTask(behavior: _TaskRegistry._Behaviour) -> URLSessionDownloadTask {
        /* We do not support resume data in swift-corelibs-foundation, so whatever we are passed, we should just behave as Darwin does in the presence of invalid data. */
        
        guard !self.invalidated else { fatalError("Session invalidated") }
        let task = URLSessionDownloadTask()
        task.createdFromInvalidResumeData = true
        task.taskIdentifier = createNextTaskIdentifier()
        task.session = self
        workQueue.async {
            self.taskRegistry.add(task, behaviour: behavior)
        }
        return task
    }
}

internal extension SSURLSession {
    /// The kind of callback / delegate behaviour of a task.
    ///
    /// This is similar to the `SSURLSession.TaskRegistry.Behaviour`, but it
    /// also encodes the kind of delegate that the session has.
    enum _TaskBehaviour {
        /// The session has no delegate, or just a plain `SSURLSessionDelegate`.
        case noDelegate
        /// The session has a delegate of type `SSURLSessionTaskDelegate`
        case taskDelegate(SSURLSessionTaskDelegate)
        /// Default action for all events, except for completion.
        /// - SeeAlso: SSURLSession.TaskRegistry.Behaviour.dataCompletionHandler
        case dataCompletionHandler(SSURLSession._TaskRegistry.DataTaskCompletion)
        /// Default action for all events, except for completion.
        /// - SeeAlso: SSURLSession.TaskRegistry.Behaviour.downloadCompletionHandler
        case downloadCompletionHandler(SSURLSession._TaskRegistry.DownloadTaskCompletion)
    }

    func behaviour(for task: SSURLSessionTask) -> _TaskBehaviour {
        switch taskRegistry.behaviour(for: task) {
        case .dataCompletionHandler(let c): return .dataCompletionHandler(c)
        case .downloadCompletionHandler(let c): return .downloadCompletionHandler(c)
        case .callDelegate:
            guard let d = delegate as? SSURLSessionTaskDelegate else {
                return .noDelegate
            }
            return .taskDelegate(d)
        }
    }
}


internal protocol SSURLSessionProtocol: AnyObject {
    func add(handle: _SSEasyHandle)
    func remove(handle: _SSEasyHandle)
    func behaviour(for: SSURLSessionTask) -> SSURLSession._TaskBehaviour
    var configuration: SSURLSessionConfiguration { get }
    var delegate: SSURLSessionDelegate? { get }
}
extension SSURLSession: SSURLSessionProtocol {
    func add(handle: _SSEasyHandle) {
        multiHandle.add(handle)
    }
    func remove(handle: _SSEasyHandle) {
        multiHandle.remove(handle)
    }
}
/// This class is only used to allow `SSURLSessionTask.init()` to work.
///
/// - SeeAlso: SSURLSessionTask.init()
final internal class _SSMissingURLSession: SSURLSessionProtocol {
    var delegate: SSURLSessionDelegate? {
        fatalError()
    }
    var configuration: SSURLSessionConfiguration {
        fatalError()
    }
    func add(handle: _SSEasyHandle) {
        fatalError()
    }
    func remove(handle: _SSEasyHandle) {
        fatalError()
    }
    func behaviour(for: SSURLSessionTask) -> SSURLSession._TaskBehaviour {
        fatalError()
    }
}
