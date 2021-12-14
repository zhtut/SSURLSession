// Foundation/SSURLSession/SSURLSessionConfiguration.swift - SSURLSession Configuration
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

/// Configuration options for an SSURLSession.
///
/// When a session is
/// created, a copy of the configuration object is made - you cannot
/// modify the configuration of a session after it has been created.
///
/// The shared session uses the global singleton credential, cache
/// and cookie storage objects.
///
/// An ephemeral session has no persistent disk storage for cookies,
/// cache or credentials.
///
/// A background session can be used to perform networking operations
/// on behalf of a suspended application, within certain constraints.
@objc
open class SSURLSessionConfiguration : NSObject, NSCopying {
    // -init is silently incorrect in URLSessionCofiguration on the desktop. Ensure code that relied on swift-corelibs-foundation's init() being functional is redirected to the appropriate cross-platform class property.
    @available(*, deprecated, message: "Use .default instead.", renamed: "SSURLSessionConfiguration.default")
    @objc
    public override init() {
        self.requestCachePolicy = SSURLSessionConfiguration.default.requestCachePolicy
        self.timeoutIntervalForRequest = SSURLSessionConfiguration.default.timeoutIntervalForRequest
        self.timeoutIntervalForResource = SSURLSessionConfiguration.default.timeoutIntervalForResource
        self.networkServiceType = SSURLSessionConfiguration.default.networkServiceType
        self.allowsCellularAccess = SSURLSessionConfiguration.default.allowsCellularAccess
        self.isDiscretionary = SSURLSessionConfiguration.default.isDiscretionary
        self.httpShouldUsePipelining = SSURLSessionConfiguration.default.httpShouldUsePipelining
        self.httpShouldSetCookies = SSURLSessionConfiguration.default.httpShouldSetCookies
        self.httpCookieAcceptPolicy = SSURLSessionConfiguration.default.httpCookieAcceptPolicy
        self.httpMaximumConnectionsPerHost = SSURLSessionConfiguration.default.httpMaximumConnectionsPerHost
        self.httpCookieStorage = SSURLSessionConfiguration.default.httpCookieStorage
        self.urlCredentialStorage = SSURLSessionConfiguration.default.urlCredentialStorage
        self.urlCache = SSURLSessionConfiguration.default.urlCache
        self.shouldUseExtendedBackgroundIdleMode = SSURLSessionConfiguration.default.shouldUseExtendedBackgroundIdleMode
        self.protocolClasses = SSURLSessionConfiguration.default.protocolClasses
        super.init()
    }
    
    internal convenience init(correctly: ()) {
        self.init(identifier: nil,
                  requestCachePolicy: .useProtocolCachePolicy,
                  timeoutIntervalForRequest: 60,
                  timeoutIntervalForResource: 604800,
                  networkServiceType: .default,
                  allowsCellularAccess: true,
                  isDiscretionary: false,
                  connectionProxyDictionary: nil,
                  httpShouldUsePipelining: false,
                  httpShouldSetCookies: true,
                  httpCookieAcceptPolicy: .onlyFromMainDocumentDomain,
                  httpAdditionalHeaders: nil,
                  httpMaximumConnectionsPerHost: 6,
                  httpCookieStorage: .shared,
                  urlCredentialStorage: .shared,
                  urlCache: .shared,
                  shouldUseExtendedBackgroundIdleMode: false,
                  protocolClasses: [_SSHTTPURLProtocol.self])
    }
    
    private init(identifier: String?,
                 requestCachePolicy: URLRequest.CachePolicy,
                 timeoutIntervalForRequest: TimeInterval,
                 timeoutIntervalForResource: TimeInterval,
                 networkServiceType: URLRequest.NetworkServiceType,
                 allowsCellularAccess: Bool,
                 isDiscretionary: Bool,
                 connectionProxyDictionary: [AnyHashable:Any]?,
                 httpShouldUsePipelining: Bool,
                 httpShouldSetCookies: Bool,
                 httpCookieAcceptPolicy: HTTPCookie.AcceptPolicy,
                 httpAdditionalHeaders: [AnyHashable:Any]?,
                 httpMaximumConnectionsPerHost: Int,
                 httpCookieStorage: HTTPCookieStorage?,
                 urlCredentialStorage: URLCredentialStorage?,
                 urlCache: SSURLCache?,
                 shouldUseExtendedBackgroundIdleMode: Bool,
                 protocolClasses: [AnyClass]?)
    {
        self.identifier = identifier
        self.requestCachePolicy = requestCachePolicy
        self.timeoutIntervalForRequest = timeoutIntervalForRequest
        self.timeoutIntervalForResource = timeoutIntervalForResource
        self.networkServiceType = networkServiceType
        self.allowsCellularAccess = allowsCellularAccess
        self.isDiscretionary = isDiscretionary
        self.connectionProxyDictionary = connectionProxyDictionary
        self.httpShouldUsePipelining = httpShouldUsePipelining
        self.httpShouldSetCookies = httpShouldSetCookies
        self.httpCookieAcceptPolicy = httpCookieAcceptPolicy
        self.httpAdditionalHeaders = httpAdditionalHeaders
        self.httpMaximumConnectionsPerHost = httpMaximumConnectionsPerHost
        self.httpCookieStorage = httpCookieStorage
        self.urlCredentialStorage = urlCredentialStorage
        self.urlCache = urlCache
        self.shouldUseExtendedBackgroundIdleMode = shouldUseExtendedBackgroundIdleMode
        self.protocolClasses = protocolClasses
    }
    
    @objc
    open override func copy() -> Any {
        return copy(with: nil)
    }
    
    @objc
    open func copy(with zone: NSZone?) -> Any {
        return SSURLSessionConfiguration(
            identifier: identifier,
            requestCachePolicy: requestCachePolicy,
            timeoutIntervalForRequest: timeoutIntervalForRequest,
            timeoutIntervalForResource: timeoutIntervalForResource,
            networkServiceType: networkServiceType,
            allowsCellularAccess: allowsCellularAccess,
            isDiscretionary: isDiscretionary,
            connectionProxyDictionary: connectionProxyDictionary,
            httpShouldUsePipelining: httpShouldUsePipelining,
            httpShouldSetCookies: httpShouldSetCookies,
            httpCookieAcceptPolicy: httpCookieAcceptPolicy,
            httpAdditionalHeaders: httpAdditionalHeaders,
            httpMaximumConnectionsPerHost: httpMaximumConnectionsPerHost,
            httpCookieStorage: httpCookieStorage,
            urlCredentialStorage: urlCredentialStorage,
            urlCache: urlCache,
            shouldUseExtendedBackgroundIdleMode: shouldUseExtendedBackgroundIdleMode,
            protocolClasses: protocolClasses)
    }
    
    @objc
    open class var `default`: SSURLSessionConfiguration {
        return SSURLSessionConfiguration(correctly: ())
    }
    
    /* identifier for the background session configuration */
    @objc
    open var identifier: String?
    
    /* default cache policy for requests */
    @objc
    open var requestCachePolicy: URLRequest.CachePolicy
    
    /* default timeout for requests.  This will cause a timeout if no data is transmitted for the given timeout value, and is reset whenever data is transmitted. */
    @objc
    open var timeoutIntervalForRequest: TimeInterval
    
    /* default timeout for requests.  This will cause a timeout if a resource is not able to be retrieved within a given timeout. */
    @objc
    open var timeoutIntervalForResource: TimeInterval
    
    /* type of service for requests. */
    @objc
    open var networkServiceType: URLRequest.NetworkServiceType
    
    /* allow request to route over cellular. */
    @objc
    open var allowsCellularAccess: Bool
    
    /* allows background tasks to be scheduled at the discretion of the system for optimal performance. */
    @objc
    open var isDiscretionary: Bool
    
    /* The identifier of the shared data container into which files in background sessions should be downloaded.
     * App extensions wishing to use background sessions *must* set this property to a valid container identifier, or
     * all transfers in that session will fail with NSURLErrorBackgroundSessionRequiresSharedContainer.
     */
    @objc
    open var sharedContainerIdentifier: String? { return nil }
    
    /*
     * Allows the app to be resumed or launched in the background when tasks in background sessions complete
     * or when auth is required. This only applies to configurations created with +backgroundSessionConfigurationWithIdentifier:
     * and the default value is YES.
     */
    
    /* The proxy dictionary, as described by <CFNetwork/CFHTTPStream.h> */
    @objc
    open var connectionProxyDictionary: [AnyHashable : Any]? = nil
    
    // TODO: We don't have the SSLProtocol type from Security
    /*
     /* The minimum allowable versions of the TLS protocol, from <Security/SecureTransport.h> */
     open var TLSMinimumSupportedProtocol: SSLProtocol
     
     /* The maximum allowable versions of the TLS protocol, from <Security/SecureTransport.h> */
     open var TLSMaximumSupportedProtocol: SSLProtocol
     */
    
    /* Allow the use of HTTP pipelining */
    @objc
    open var httpShouldUsePipelining: Bool
    
    /* Allow the session to set cookies on requests */
    @objc
    open var httpShouldSetCookies: Bool
    
    /* Policy for accepting cookies.  This overrides the policy otherwise specified by the cookie storage. */
    @objc
    open var httpCookieAcceptPolicy: HTTPCookie.AcceptPolicy
    
    /* Specifies additional headers which will be set on outgoing requests.
     Note that these headers are added to the request only if not already present. */
    @objc
    open var httpAdditionalHeaders: [AnyHashable : Any]? = nil
    
    #if NS_CURL_MISSING_MAX_HOST_CONNECTIONS
    /* The maximum number of simultaneous persistent connections per host */
    @available(*, deprecated, message: "This platform doles not support selecting the maximum number of simultaneous persistent connections per host. This property is ignored.")
    @objc
    open var httpMaximumConnectionsPerHost: Int
    #else
    /* The maximum number of simultaneous persistent connections per host */
    @objc
    open var httpMaximumConnectionsPerHost: Int
    #endif
    
    /* The cookie storage object to use, or nil to indicate that no cookies should be handled */
    @objc
    open var httpCookieStorage: HTTPCookieStorage?
    
    /* The credential storage object, or nil to indicate that no credential storage is to be used */
    @objc
    open var urlCredentialStorage: URLCredentialStorage?
    
    /* The URL resource cache, or nil to indicate that no caching is to be performed */
    @objc
    open var urlCache: SSURLCache?
    
    /* Enable extended background idle mode for any tcp sockets created.    Enabling this mode asks the system to keep the socket open
     *  and delay reclaiming it when the process moves to the background (see https://developer.apple.com/library/ios/technotes/tn2277/_index.html)
     */
    @objc
    open var shouldUseExtendedBackgroundIdleMode: Bool
    
    /* An optional array of Class objects which subclass SSURLProtocol.
     The Class will be sent +canInitWithRequest: when determining if
     an instance of the class can be used for a given URL scheme.
     You should not use +[SSURLProtocol registerClass:], as that
     method will register your class with the default session rather
     than with an instance of SSURLSession.
     Custom SSURLProtocol subclasses are not available to background
     sessions.
     */
    @objc
    open var protocolClasses: [AnyClass]?

}

@available(*, unavailable, message: "Not available on non-Darwin platforms")
extension SSURLSessionConfiguration {
    public enum MultipathServiceType {
        case none
        case handover
        case interactive
        case aggregate
    }
}
