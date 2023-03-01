import XCTest
@testable import SSURLSession

final class SSURLSessionTests: XCTestCase {
    
    func testRequest() async {
        if #available(iOS 13.0, *) {
            var response = await withCheckedContinuation({ continuation in
                let urlStr = "https://www.baidu.com"
                let url = URL(string: urlStr)!
                let req = URLRequest(url: url)
                let task = SSURLSession.shared.dataTask(with: req, completionHandler: { data, resp, error in
                    continuation.resume(returning: resp as? HTTPURLResponse)
                })
                task.resume()
            })
            XCTAssertEqual(response?.statusCode, 200)
        } else {
            // Fallback on earlier versions
        }
    }
}
