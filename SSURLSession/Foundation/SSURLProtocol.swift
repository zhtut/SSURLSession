// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2016 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//

#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
import Foundation
#else
import Foundation
#endif

/*!
    @header SSURLProtocol.h

    This header file describes the constructs used to represent URL
    protocols, and describes the extensible system by which specific
    classes can be made to handle the loading of particular URL types or
    schemes.
    
    <p>SSURLProtocol is an abstract class which provides the
    basic structure for performing protocol-specific loading of URL
    data.
    
    <p>The SSURLProtocolClient describes the integration points a
    protocol implementation can use to hook into the URL loading system.
    SSURLProtocolClient describes the methods a protocol implementation
    needs to drive the URL loading system from a SSURLProtocol subclass.
    
    <p>To support customization of protocol-specific requests,
    protocol implementors are encouraged to provide categories on
    NSURLRequest and NSMutableURLRequest. Protocol implementors who
    need to extend the capabilities of NSURLRequest and
    NSMutableURLRequest in this way can store and retrieve
    protocol-specific request data by using the
    <tt>+propertyForKey:inRequest:</tt> and
    <tt>+setProperty:forKey:inRequest:</tt> class methods on
    SSURLProtocol. See the NSHTTPURLRequest on NSURLRequest and
    NSMutableHTTPURLRequest on NSMutableURLRequest for examples of
    such extensions.
    
    <p>An essential responsibility for a protocol implementor is
    creating a URLResponse for each request it processes successfully.
    A protocol implementor may wish to create a custom, mutable 
    URLResponse class to aid in this work.
*/

/*!
@protocol SSURLProtocolClient
@discussion SSURLProtocolClient provides the interface to the URL
loading system that is intended for use by SSURLProtocol
implementors.
*/
public protocol SSURLProtocolClient : NSObjectProtocol {
    
    
    /*!
     @method SSURLProtocol:wasRedirectedToRequest:
     @abstract Indicates to an SSURLProtocolClient that a redirect has
     occurred.
     @param SSURLProtocol the SSURLProtocol object sending the message.
     @param request the NSURLRequest to which the protocol implementation
     has redirected.
     */
    func urlProtocol(_ protocol: SSURLProtocol, wasRedirectedTo request: URLRequest, redirectResponse: URLResponse)
    
    
    /*!
     @method SSURLProtocol:cachedResponseIsValid:
     @abstract Indicates to an SSURLProtocolClient that the protocol
     implementation has examined a cached response and has
     determined that it is valid.
     @param SSURLProtocol the SSURLProtocol object sending the message.
     @param cachedResponse the NSCachedURLResponse object that has
     examined and is valid.
     */
    func urlProtocol(_ protocol: SSURLProtocol, cachedResponseIsValid cachedResponse: SSCachedURLResponse)
    
    
    /*!
     @method SSURLProtocol:didReceiveResponse:
     @abstract Indicates to an SSURLProtocolClient that the protocol
     implementation has created an URLResponse for the current load.
     @param SSURLProtocol the SSURLProtocol object sending the message.
     @param response the URLResponse object the protocol implementation
     has created.
     @param cacheStoragePolicy The SSURLCache.StoragePolicy the protocol
     has determined should be used for the given response if the
     response is to be stored in a cache.
     */
    func urlProtocol(_ protocol: SSURLProtocol, didReceive response: URLResponse, cacheStoragePolicy policy: SSURLCache.StoragePolicy)
    
    
    /*!
     @method SSURLProtocol:didLoadData:
     @abstract Indicates to an NSURLProtocolClient that the protocol
     implementation has loaded URL data.
     @discussion The data object must contain only new data loaded since
     the previous call to this method (if any), not cumulative data for
     the entire load.
     @param SSURLProtocol the NSURLProtocol object sending the message.
     @param data URL load data being made available.
     */
    func urlProtocol(_ protocol: SSURLProtocol, didLoad data: Data)
    
    
    /*!
     @method URLProtocolDidFinishLoading:
     @abstract Indicates to an NSURLProtocolClient that the protocol
     implementation has finished loading successfully.
     @param SSURLProtocol the NSURLProtocol object sending the message.
     */
    func urlProtocolDidFinishLoading(_ protocol: SSURLProtocol)
    
    
    /*!
     @method SSURLProtocol:didFailWithError:
     @abstract Indicates to an NSURLProtocolClient that the protocol
     implementation has failed to load successfully.
     @param SSURLProtocol the NSURLProtocol object sending the message.
     @param error The error that caused the load to fail.
     */
    func urlProtocol(_ protocol: SSURLProtocol, didFailWithError error: Error)
    
    
    /*!
     @method SSURLProtocol:didReceiveAuthenticationChallenge:
     @abstract Start authentication for the specified request
     @param protocol The protocol object requesting authentication.
     @param challenge The authentication challenge.
     @discussion The protocol client guarantees that it will answer the
     request on the same thread that called this method. It may add a
     default credential to the challenge it issues to the connection delegate,
     if the protocol did not provide one.
     */
    func urlProtocol(_ protocol: SSURLProtocol, didReceive challenge: URLAuthenticationChallenge)
    
    
    /*!
     @method SSURLProtocol:didCancelAuthenticationChallenge:
     @abstract Cancel authentication for the specified request
     @param protocol The protocol object cancelling authentication.
     @param challenge The authentication challenge.
     */
    func urlProtocol(_ protocol: SSURLProtocol, didCancel challenge: URLAuthenticationChallenge)
}

internal class _SSProtocolClient : NSObject {
    var cachePolicy: SSURLCache.StoragePolicy = .notAllowed
    var cacheableData: [Data]?
    var cacheableResponse: URLResponse?
}

/*!
    @class NSURLProtocol
 
    @abstract NSURLProtocol is an abstract class which provides the
    basic structure for performing protocol-specific loading of URL
    data. Concrete subclasses handle the specifics associated with one
    or more protocols or URL schemes.
*/
open class SSURLProtocol : NSObject {

    private static var _registeredProtocolClasses = [AnyClass]()
    private static var _classesLock = NSLock()

    //TODO: The right way to do this is using SSURLProtocol.property(forKey:in) and SSURLProtocol.setProperty(_:forKey:in)
    var properties: [SSURLProtocol._PropertyKey: Any] = [:]
    /*! 
        @method initWithRequest:cachedResponse:client:
        @abstract Initializes an NSURLProtocol given request, 
        cached response, and client.
        @param request The request to load.
        @param cachedResponse A response that has been retrieved from the
        cache for the given request. The protocol implementation should
        apply protocol-specific validity checks if such tests are
        necessary.
        @param client The NSURLProtocolClient object that serves as the
        interface the protocol implementation can use to report results back
        to the URL loading system.
    */
    public required init(request: URLRequest, cachedResponse: SSCachedURLResponse?, client: SSURLProtocolClient?) {
        self._request = request
        self._cachedResponse = cachedResponse
        self._client = client ?? _SSProtocolClient()
    }

    private var _request : URLRequest
    private var _cachedResponse : SSCachedURLResponse?
    private var _client : SSURLProtocolClient?

    /*! 
        @method client
        @abstract Returns the NSURLProtocolClient of the receiver. 
        @result The NSURLProtocolClient of the receiver.  
    */
    open var client: SSURLProtocolClient? {
        set { self._client = newValue }
        get { return self._client }
    }
    
    /*! 
        @method request
        @abstract Returns the NSURLRequest of the receiver. 
        @result The NSURLRequest of the receiver. 
    */
    /*@NSCopying*/ open var request: URLRequest {
        return _request
     }
    
    /*! 
        @method cachedResponse
        @abstract Returns the NSCachedURLResponse of the receiver.  
        @result The NSCachedURLResponse of the receiver. 
    */
    /*@NSCopying*/ open var cachedResponse: SSCachedURLResponse? {
        return _cachedResponse
     }
    
    /*======================================================================
      Begin responsibilities for protocol implementors
    
      The methods between this set of begin-end markers must be
      implemented in order to create a working protocol.
      ======================================================================*/
    
    /*! 
        @method canInitWithRequest:
        @abstract This method determines whether this protocol can handle
        the given request.
        @discussion A concrete subclass should inspect the given request and
        determine whether or not the implementation can perform a load with
        that request. This is an abstract method. Sublasses must provide an
        implementation. The implementation in this class calls
        NSRequestConcreteImplementation.
        @param request A request to inspect.
        @result YES if the protocol can handle the given request, NO if not.
    */
    open class func canInit(with request: URLRequest) -> Bool {
        NSRequiresConcreteImplementation()
    }
    
    /*! 
        @method canonicalRequestForRequest:
        @abstract This method returns a canonical version of the given
        request.
        @discussion It is up to each concrete protocol implementation to
        define what "canonical" means. However, a protocol should
        guarantee that the same input request always yields the same
        canonical form. Special consideration should be given when
        implementing this method since the canonical form of a request is
        used to look up objects in the URL cache, a process which performs
        equality checks between NSURLRequest objects.
        <p>
        This is an abstract method; sublasses must provide an
        implementation. The implementation in this class calls
        NSRequestConcreteImplementation.
        @param request A request to make canonical.
        @result The canonical form of the given request. 
    */
    open class func canonicalRequest(for request: URLRequest) -> URLRequest {
        NSRequiresConcreteImplementation()
    }
    
    /*!
        @method requestIsCacheEquivalent:toRequest:
        @abstract Compares two requests for equivalence with regard to caching.
        @discussion Requests are considered equivalent for cache purposes
        if and only if they would be handled by the same protocol AND that
        protocol declares them equivalent after performing 
        implementation-specific checks.
        @result YES if the two requests are cache-equivalent, NO otherwise.
    */
    open class func requestIsCacheEquivalent(_ a: URLRequest, to b: URLRequest) -> Bool {
        NSRequiresConcreteImplementation()
    }
    
    /*! 
        @method startLoading
        @abstract Starts protocol-specific loading of a request. 
        @discussion When this method is called, the protocol implementation
        should start loading a request.
    */
    open func startLoading() {
        NSRequiresConcreteImplementation()
    }
    
    /*! 
        @method stopLoading
        @abstract Stops protocol-specific loading of a request. 
        @discussion When this method is called, the protocol implementation
        should end the work of loading a request. This could be in response
        to a cancel operation, so protocol implementations must be able to
        handle this call while a load is in progress.
    */
    open func stopLoading() {
        NSRequiresConcreteImplementation()
    }
    
    /*======================================================================
      End responsibilities for protocol implementors
      ======================================================================*/
    
    /*! 
        @method registerClass:
        @abstract This method registers a protocol class, making it visible
        to several other NSURLProtocol class methods.
        @discussion When the URL loading system begins to load a request,
        each protocol class that has been registered is consulted in turn to
        see if it can be initialized with a given request. The first
        protocol handler class to provide a YES answer to
        <tt>+canInitWithRequest:</tt> "wins" and that protocol
        implementation is used to perform the URL load. There is no
        guarantee that all registered protocol classes will be consulted.
        Hence, it should be noted that registering a class places it first
        on the list of classes that will be consulted in calls to
        <tt>+canInitWithRequest:</tt>, moving it in front of all classes
        that had been registered previously.
        <p>A similar design governs the process to create the canonical form
        of a request with the <tt>+canonicalRequestForRequest:</tt> class
        method.
        @param protocolClass the class to register.
        @result YES if the protocol was registered successfully, NO if not.
        The only way that failure can occur is if the given class is not a
        subclass of NSURLProtocol.
    */
    open class func registerClass(_ protocolClass: AnyClass) -> Bool {
        if protocolClass is SSURLProtocol.Type {
            _classesLock.lock()
            guard !_registeredProtocolClasses.contains(where: { $0 === protocolClass }) else {
                _classesLock.unlock()
                return true
            }
            _registeredProtocolClasses.append(protocolClass)
            _classesLock.unlock()
            return true
        }
        return false
    }

    internal class func getProtocolClass(protocols: [AnyClass], request: URLRequest) -> AnyClass? {
        // Registered protocols are consulted in reverse order.
        // This behaviour makes the latest registered protocol to be consulted first
        _classesLock.lock()
        let protocolClasses = protocols
        for protocolClass in protocolClasses {
            let urlProtocolClass: AnyClass = protocolClass
            guard let urlProtocol = urlProtocolClass as? SSURLProtocol.Type else { fatalError() }
            if urlProtocol.canInit(with: request) {
                _classesLock.unlock()
                return urlProtocol
            }
        }
        _classesLock.unlock()
        return nil
    }

    internal class func getProtocols() -> [AnyClass]? {
        _classesLock.lock()
        defer { _classesLock.unlock() }
        return _registeredProtocolClasses
    }
    /*! 
        @method unregisterClass:
        @abstract This method unregisters a protocol. 
        @discussion After unregistration, a protocol class is no longer
        consulted in calls to NSURLProtocol class methods.
        @param protocolClass The class to unregister.
    */
    open class func unregisterClass(_ protocolClass: AnyClass) {
        _classesLock.lock()
        if let idx = _registeredProtocolClasses.firstIndex(where: { $0 === protocolClass }) {
            _registeredProtocolClasses.remove(at: idx)
        }
        _classesLock.unlock()
    }

    open class func canInit(with task: SSURLSessionTask) -> Bool {
        guard let request = task.currentRequest else { return false }
        return canInit(with: request)
    }
    public required convenience init(task: SSURLSessionTask, cachedResponse: SSCachedURLResponse?, client: SSURLProtocolClient?) {
        let urlRequest = task.originalRequest
        self.init(request: urlRequest!, cachedResponse: cachedResponse, client: client)
        self.task = task
    }
    /*@NSCopying*/ open var task: SSURLSessionTask? {
        set { self._task = newValue }
        get { return self._task }
    }

    private var _task : SSURLSessionTask? = nil
}