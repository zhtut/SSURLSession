// Foundation/URLSession/URLSessionTaskMetrics.swift - URLSession API
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
// -----------------------------------------------------------------------------
///
/// URLSession API code.
/// - SeeAlso: URLSession.swift
///
// -----------------------------------------------------------------------------

#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
import Foundation
#else
import Foundation
#endif
@_implementationOnly import CoreFoundation

@objc
open class URLSessionTaskMetrics : NSObject {
    @objc
    public internal(set) var transactionMetrics: [URLSessionTaskTransactionMetrics] = []
//    @objc
//    public internal(set) var taskInterval: DateInterval = .init()
    @objc
    public internal(set) var redirectCount = 0
    
    @objc
    public enum ResourceFetchType: Int {
        case unknown = 0
        case networkLoad = 1
        case serverPush = 2
        case localCache = 3
    }
    
    @objc
    public enum DomainResolutionProtocol: Int {
        case unknown = 0
        case udp = 1
        case tcp = 2
        case tls = 3
        case https = 4
    }
}

@objc
open class URLSessionTaskTransactionMetrics: NSObject {
    @objc
    public let request: URLRequest
    @objc
    public internal(set) var response: URLResponse?
    
    @objc
    public internal(set) var fetchStartDate: Date?
    @objc
    public internal(set) var domainLookupStartDate: Date?
    @objc
    public internal(set) var domainLookupEndDate: Date?
    @objc
    public internal(set) var connectStartDate: Date?
    @objc
    public internal(set) var secureConnectionStartDate: Date?
    @objc
    public internal(set) var secureConnectionEndDate: Date?
    @objc
    public internal(set) var connectEndDate: Date?
    @objc
    public internal(set) var requestStartDate: Date?
    @objc
    public internal(set) var requestEndDate: Date?
    @objc
    public internal(set) var responseStartDate: Date?
    @objc
    public internal(set) var responseEndDate: Date?
    
    @objc
    public internal(set) var countOfRequestBodyBytesBeforeEncoding: Int64 = 0
    @objc
    public internal(set) var countOfRequestBodyBytesSent: Int64 = 0
    @objc
    public internal(set) var countOfRequestHeaderBytesSent: Int64 = 0
    @objc
    public internal(set) var countOfResponseBodyBytesAfterDecoding: Int64 = 0
    @objc
    public internal(set) var countOfResponseBodyBytesReceived: Int64 = 0
    @objc
    public internal(set) var countOfResponseHeaderBytesReceived: Int64 = 0
    
    @objc
    public internal(set) var networkProtocolName: String?
    @objc
    public internal(set) var remoteAddress: String?
    @objc
    public internal(set) var remotePort: String?
    @objc
    public internal(set) var localAddress: String?
    @objc
    public internal(set) var localPort: String?
    public internal(set) var negotiatedTLSCipherSuite: tls_ciphersuite_t?
    public internal(set) var negotiatedTLSProtocolVersion: tls_protocol_version_t?
    @objc
    public internal(set) var isCellular: Bool = false
    @objc
    public internal(set) var isExpensive: Bool = false
    @objc
    public internal(set) var isConstrained: Bool = false
    @objc
    public internal(set) var isProxyConnection: Bool = false
    @objc
    public internal(set) var isReusedConnection: Bool = false
    @objc
    public internal(set) var isMultipath: Bool = false
    @objc
    public internal(set) var resourceFetchType: URLSessionTaskMetrics.ResourceFetchType = .unknown
    @objc
    public internal(set) var domainResolutionProtocol: URLSessionTaskMetrics.DomainResolutionProtocol = .unknown
    
    init(request: URLRequest) {
        self.request = request
    }
}

public enum tls_ciphersuite_t: UInt16 {
    case AES_128_GCM_SHA256 = 4865
    case AES_256_GCM_SHA384 = 4866
    
    case CHACHA20_POLY1305_SHA256 = 4867
    
    case ECDHE_ECDSA_WITH_3DES_EDE_CBC_SHA = 49160
    case ECDHE_ECDSA_WITH_AES_128_CBC_SHA = 49161
    case ECDHE_ECDSA_WITH_AES_128_CBC_SHA256 = 49187
    case ECDHE_ECDSA_WITH_AES_128_GCM_SHA256 = 49195
    case ECDHE_ECDSA_WITH_AES_256_CBC_SHA = 49162
    case ECDHE_ECDSA_WITH_AES_256_CBC_SHA384 = 49188
    case ECDHE_ECDSA_WITH_AES_256_GCM_SHA384 = 49196
    case ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256 = 52393
    case ECDHE_RSA_WITH_3DES_EDE_CBC_SHA = 49170
    case ECDHE_RSA_WITH_AES_128_CBC_SHA = 49171
    case ECDHE_RSA_WITH_AES_128_CBC_SHA256 = 49191
    case ECDHE_RSA_WITH_AES_128_GCM_SHA256 = 49199
    case ECDHE_RSA_WITH_AES_256_CBC_SHA = 49172
    case ECDHE_RSA_WITH_AES_256_CBC_SHA384 = 49192
    case ECDHE_RSA_WITH_AES_256_GCM_SHA384 = 49200
    case ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256 = 52392
    
    case RSA_WITH_3DES_EDE_CBC_SHA = 10
    case RSA_WITH_AES_128_CBC_SHA = 47
    case RSA_WITH_AES_128_CBC_SHA256 = 60
    case RSA_WITH_AES_128_GCM_SHA256 = 156
    case RSA_WITH_AES_256_CBC_SHA = 53
    case RSA_WITH_AES_256_CBC_SHA256 = 61
    case RSA_WITH_AES_256_GCM_SHA384 = 157
}

public enum tls_protocol_version_t: UInt16 {
    case TLSv10 = 769
    case TLSv11 = 770
    case TLSv12 = 771
    case TLSv13 = 772
    case DTLSv10 = 65279
    case DTLSv12 = 65277
}
