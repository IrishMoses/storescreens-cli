import CryptoKit
import XCTest
@testable import StorescreensCore

private final class ProfilesStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, data) = handler(request)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

final class DevPortalAPITests: XCTestCase {
    override func tearDown() {
        ProfilesStub.handler = nil
        super.tearDown()
    }

    private func makeAPI(handler: @escaping @Sendable (URLRequest) -> (Int, Data)) -> DevPortalAPI {
        ProfilesStub.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ProfilesStub.self]
        let credentials = ASCCredentials(
            keyID: "K", issuerID: "I",
            privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation, source: .environment
        )
        return DevPortalAPI(client: ASCClient(
            credentials: credentials, session: URLSession(configuration: config), maxRetries: 0
        ))
    }

    private static func query(_ request: URLRequest) -> [String: String] {
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    private static let mixedProfiles = Data("""
        {
          "data": [
            {"id":"MATCH", "attributes":{"profileType":"IOS_APP_STORE"},
             "relationships":{"bundleId":{"data":{"id":"BUNDLE1","type":"bundleIds"}}}},
            {"id":"OTHER", "relationships":{"bundleId":{"data":{"id":"BUNDLE2","type":"bundleIds"}}}},
            {"id":"NO_RELATIONSHIP"},
            {"id":"NULL_BUNDLE", "relationships":{"bundleId":{"data":null}}},
            {"id":"MISSING_INCLUDED_BUNDLE", "relationships":{"bundleId":{"data":{"id":"BUNDLE3"}}}}
          ],
          "included": [
            {"id":"BUNDLE2", "attributes":{"identifier":"com.example.app.extension"}},
            {"id":"BUNDLE1", "attributes":{"identifier":"com.example.app"}}
          ],
          "links":{"next":"https://api.appstoreconnect.apple.com/v1/profiles?cursor=next%2Bpage%3D"}
        }
        """.utf8)

    func testBundleIDAndTypeUseSupportedQueryAndExactRelationshipMatch() async throws {
        let api = makeAPI { request in
            XCTAssertEqual(request.url?.path, "/v1/profiles")
            let query = Self.query(request)
            XCTAssertNil(query["filter[bundleId]"])
            XCTAssertEqual(query["include"], "bundleId")
            XCTAssertEqual(query["fields[bundleIds]"], "identifier")
            XCTAssertEqual(query["filter[profileType]"], "IOS_APP_STORE")
            XCTAssertEqual(query["limit"], "12")
            XCTAssertEqual(query["cursor"], "current+page=")
            return (200, Self.mixedProfiles)
        }
        let result = try await api.listProfiles(
            type: "IOS_APP_STORE", bundleIDFilter: "com.example.app", limit: 12, cursor: "current+page="
        )
        XCTAssertEqual(result.profiles.map(\.id), ["MATCH"])
        XCTAssertEqual(result.profiles.first?.attributes?.profileType, "IOS_APP_STORE")
        XCTAssertEqual(result.nextCursor, "next+page=")
    }

    func testUnknownBundleReturnsEmptyPageAndPreservesNextCursor() async throws {
        let api = makeAPI { request in
            XCTAssertNil(Self.query(request)["filter[profileType]"])
            return (200, Self.mixedProfiles)
        }
        let result = try await api.listProfiles(bundleIDFilter: "com.example.missing")
        XCTAssertTrue(result.profiles.isEmpty)
        XCTAssertEqual(result.nextCursor, "next+page=")
    }

    func testFilteringCanContinueAfterEmptyPage() async throws {
        let api = makeAPI { request in
            XCTAssertEqual(Self.query(request)["include"], "bundleId")
            if Self.query(request)["cursor"] == nil {
                return (200, Data("""
                    {"data":[],"included":[],
                     "links":{"next":"https://api.appstoreconnect.apple.com/v1/profiles?cursor=second"}}
                    """.utf8))
            }
            XCTAssertEqual(Self.query(request)["cursor"], "second")
            return (200, Self.mixedProfiles)
        }
        let first = try await api.listProfiles(bundleIDFilter: "com.example.app")
        XCTAssertTrue(first.profiles.isEmpty)
        let cursor = try XCTUnwrap(first.nextCursor)
        let second = try await api.listProfiles(bundleIDFilter: "com.example.app", cursor: cursor)
        XCTAssertEqual(second.profiles.map(\.id), ["MATCH"])
    }

    func testUnfilteredListingDoesNotRequireRelationshipsOrIncludes() async throws {
        let api = makeAPI { request in
            let query = Self.query(request)
            XCTAssertNil(query["include"])
            XCTAssertNil(query["fields[bundleIds]"])
            XCTAssertNil(query["filter[bundleId]"])
            XCTAssertEqual(query["filter[profileType]"], "IOS_APP_STORE")
            return (200, Data(#"{"data":[{"id":"PROFILE","attributes":{"name":"App Store"}}]}"#.utf8))
        }
        let result = try await api.listProfiles(type: "IOS_APP_STORE")
        XCTAssertEqual(result.profiles.map(\.id), ["PROFILE"])
        XCTAssertNil(result.nextCursor)
    }

    func testBundleFilterWithNoIncludedResourcesDoesNotReturnUnrelatedProfiles() async throws {
        let api = makeAPI { _ in (200, Data(#"{"data":[{"id":"UNRELATED"}]}"#.utf8)) }
        let result = try await api.listProfiles(bundleIDFilter: "com.example.app")
        XCTAssertTrue(result.profiles.isEmpty)
        XCTAssertNil(result.nextCursor)
    }

    func testAPIErrorsArePropagated() async throws {
        let api = makeAPI { _ in (403, Data(#"{"errors":[]}"#.utf8)) }
        do {
            _ = try await api.listProfiles(bundleIDFilter: "com.example.app")
            XCTFail("Expected API error")
        } catch let error as ASCClient.APIError {
            XCTAssertEqual(error.statusCode, 403)
        }
    }
}
