import Testing
import Foundation
@testable import Fiber

@Suite("FiberRequest")
struct RequestTests {

    @Test("Chainable combinators produce new values")
    func chainableCombinators() throws {
        let base = FiberRequest(url: "https://example.com")

        let modified = try base
            .method(.post)
            .header("Authorization", "Bearer tok")
            .header("Content-Type", "application/json")
            .query("page", "1")
            .query("limit", "20")
            .timeout(30)
            .meta("retry", "true")
            .jsonBody(["key": "value"])

        // Original is unchanged (value type)
        #expect(base.httpMethod == .get)
        #expect(base.headers.isEmpty)
        #expect(base.queryItems.isEmpty)

        // Modified has all changes
        #expect(modified.httpMethod == .post)
        #expect(modified.headers["Authorization"] == "Bearer tok")
        #expect(modified.headers["Content-Type"] == "application/json")
        #expect(modified.queryItems.count == 2)
        #expect(modified.timeoutInterval == 30)
        #expect(modified.metadata["retry"] == "true")
        #expect(modified.body != nil)
    }

    @Test("toURLRequest conversion")
    func toURLRequest() {
        let req = FiberRequest(url: "https://example.com/api")
            .method(.post)
            .header("X-Custom", "value")
            .query("q", "test")
            .body(Data("hello".utf8))
            .timeout(15)

        let urlReq = req.toURLRequest()
        #expect(urlReq.httpMethod == "POST")
        #expect(urlReq.value(forHTTPHeaderField: "X-Custom") == "value")
        #expect(urlReq.url?.absoluteString.contains("q=test") == true)
        #expect(urlReq.httpBody == Data("hello".utf8))
        #expect(urlReq.timeoutInterval == 15)
    }

    @Test("map combinator")
    func mapCombinator() {
        let req = FiberRequest(url: "https://example.com")
            .map { $0.header("X-Added", "byMap") }

        #expect(req.headers["X-Added"] == "byMap")
    }

    @Test("headers merge")
    func headersMerge() {
        let req = FiberRequest(url: "https://example.com")
            .header("A", "1")
            .headers(["B": "2", "A": "overwritten"])

        #expect(req.headers["A"] == "overwritten")
        #expect(req.headers["B"] == "2")
    }
}
