# SSURLSession
对swift的URLSession进行拆分，增加支持设置resolve和connectTo的能力

使用的时候，对URLRequest设定Header
```swift
let resolve = "\(host):443:\(ip)"
setValue(resolve, forHTTPHeaderField: "resolve")
```
connectTo:
```swift
let connectTo = "\(host):443:\(ip):443"
setValue(connectTo, forHTTPHeaderField: "connectTo")
```
支持SNI功能，用于IP直连

目前发现上面两个字段都可以实现强制解析的功能
所以用上面那个字段就可以实现需求了
需要注意的是，ip服务器需要包含host域名的证书，这样才能认证通过

## 安装
### SPM
```swift
.package(url: "https://github.com/zhtut/SSURLSession.git", from: "0.1.0")
```

### Cocoapods

```ruby
pod 'SSURLSession'
```

## 使用
```swift
import SSURLSession

let host = "www.baidu.com"
let urlStr = "https://\(host)"
let url = URL(string: urlStr)!
var req = URLRequest(url: url)
// direct ip
let ip = "14.119.104.254"
let resolve = "\(host):443:\(ip)"
// add dns resolve
req.setValue(resolve, forHTTPHeaderField: "resolve")
let task = SSURLSession.URLSession.shared.dataTask(with: req, completionHandler: { data, resp, error in
    if let data {
        print("success")
    } else {
        if let error {
            print("error: \(error)")
        }
    }
})
task.resume()
```

## 问题
由于swift foundation core lib 未完全完成，有部分功能是不正常的，
但至少比CFNetwork和直接使用libcurl更成熟

https://github.com/apple/swift-corelibs-foundation/blob/main/Docs/Status.md

* **URL**: Networking primitives

    The classes in this group provide functionality for manipulating URLs and paths via a common model object. The group also has classes for creating and receiving network connections.

    | Entity Name                  | Status          | Test Coverage | Notes                                                                                                              |
    |------------------------------|-----------------|---------------|--------------------------------------------------------------------------------------------------------------------|
    | `URLAuthenticationChallenge` | Unimplemented   | None          |                                                                                                                    |
    | `URLCache`                   | Unimplemented   | None          |                                                                                                                    |
    | `URLCredential`              | Complete        | Incomplete    |                                                                                                                    |
    | `URLCredentialStorage`       | Unimplemented   | None          |                                                                                                                    |
    | `NSURLError*`                | Complete        | N/A           |                                                                                                                    |
    | `URLProtectionSpace`         | Unimplemented   | None          |                                                                                                                    |
    | `URLProtocol`                | Unimplemented   | None          |                                                                                                                    |
    | `URLProtocolClient`          | Unimplemented   | None          |                                                                                                                    |
    | `NSURLRequest`               | Complete        | Incomplete    |                                                                                                                    |
    | `NSMutableURLRequest`        | Complete        | Incomplete    |                                                                                                                    |
    | `URLResponse`                | Complete        | Substantial   |                                                                                                                    |
    | `NSHTTPURLResponse`          | Complete        | Substantial   |                                                                                                                    |
    | `NSURL`                      | Mostly Complete | Substantial   | Resource values remain unimplemented                                                                               |
    | `NSURLQueryItem`             | Complete        | N/A           |                                                                                                                    |
    | `URLResourceKey`             | Complete        | N/A           |                                                                                                                    |
    | `URLFileResourceType`        | Complete        | N/A           |                                                                                                                    |
    | `URL`                        | Complete        | Incomplete    |                                                                                                                    |
    | `URLResourceValues`          | Complete        | N/A           |                                                                                                                    |
    | `URLComponents`              | Complete        | Incomplete    |                                                                                                                    |
    | `URLRequest`                 | Complete        | None          |                                                                                                                    |
    | `HTTPCookie`                 | Complete        | Incomplete    |                                                                                                                    |
    | `HTTPCookiePropertyKey`      | Complete        | N/A           |                                                                                                                    |
    | `HTTPCookieStorage`          | Mostly Complete | Substantial   |                                                                                                                    |
    | `Host`                       | Complete        | None          |                                                                                                                    |
    | `Configuration`              | N/A             | N/A           | For internal use only                                                                                              |
    | `EasyHandle`                 | N/A             | N/A           | For internal use only                                                                                              |
    | `HTTPBodySource`             | N/A             | N/A           | For internal use only                                                                                              |
    | `HTTPMessage`                | N/A             | N/A           | For internal use only                                                                                              |
    | `libcurlHelpers`             | N/A             | N/A           | For internal use only                                                                                              |
    | `MultiHandle`                | N/A             | N/A           | For internal use only                                                                                              |
    | `URLSession`                 | Mostly Complete | Incomplete    | invalidation, resetting, flushing, getting tasks, and others remain unimplemented                                  |
    | `URLSessionConfiguration`    | Mostly Complete | Incomplete    | `ephemeral` and `background(withIdentifier:)` remain unimplemented                                                 |
    | `URLSessionDelegate`         | Complete        | N/A           |                                                                                                                    |
    | `URLSessionTask`             | Mostly Complete | Incomplete    | `cancel()`, `createTransferState(url:)` with streams, and others remain unimplemented                              |
    | `URLSessionDataTask`         | Complete        | Incomplete    |                                                                                                                    |
    | `URLSessionUploadTask`       | Complete        | None          |                                                                                                                    |
    | `URLSessionDownloadTask`     | Incomplete      | Incomplete    |                                                                                                                    |
    | `URLSessionStreamTask`       | Unimplemented   | None          |                                                                                                                    |
    | `TaskRegistry`               | N/A             | N/A           | For internal use only                                                                                              |
    | `TransferState`              | N/A             | N/A           | For internal use only                                                                                              |
