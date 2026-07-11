import Foundation
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct PublicExchangeRateClientTests {
    private final class StubURLProtocol: URLProtocol {
        nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

        override class func canInit(with request: URLRequest) -> Bool {
            true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            guard let handler = Self.requestHandler else {
                fatalError("Missing URLProtocol handler")
            }

            do {
                let (response, data) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}
    }

    private func makeSession(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        StubURLProtocol.requestHandler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    @Test func monobankDecodesNumericRatesAndCrossOnlyRows() async throws {
        let session = makeSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data("""
            [
              {"currencyCodeA":840,"currencyCodeB":980,"rateBuy":41.10,"rateSell":41.90},
              {"currencyCodeA":978,"currencyCodeB":980,"rateCross":44.50}
            ]
            """.utf8)
            return (response, data)
        }
        defer { StubURLProtocol.requestHandler = nil }

        let client = MonobankPublicRateClient(urlSession: session, dateProvider: { Date(timeIntervalSince1970: 1_800_000_000) })
        let rates = try await client.fetchRates(baseCurrency: .uah, date: nil)

        #expect(rates.count == 4)
        #expect(rates.map(\.source) == ["monobank-buy", "monobank-sell", "monobank-midpoint", "monobank-cross"])
        #expect(Decimal(string: rates[0].rateDecimal) == Decimal(string: "41.1"))
        #expect(Decimal(string: rates[2].rateDecimal) == Decimal(string: "41.5"))
        #expect(Decimal(string: rates[3].rateDecimal) == Decimal(string: "44.5"))
    }

    @Test func monobankThrowsOnHTTPStatus() async throws {
        let session = makeSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        defer { StubURLProtocol.requestHandler = nil }

        let client = MonobankPublicRateClient(urlSession: session, dateProvider: Date.init)
        await #expect(throws: ExchangeRateClientError.httpStatus(404)) {
            _ = try await client.fetchRates(baseCurrency: .uah, date: nil)
        }
    }

    @Test func nbuDecodesNumericRateAndEffectiveDate() async throws {
        let session = makeSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data("""
            [
              {"r030":840,"txt":"US Dollar","rate":38.75,"cc":"USD","exchangedate":"15.07.2026"}
            ]
            """.utf8)
            return (response, data)
        }
        defer { StubURLProtocol.requestHandler = nil }

        let expectedDate = DateKeys.calendar.date(from: DateComponents(year: 2026, month: 7, day: 15))!
        let client = NBUOfficialRateClient(urlSession: session, dateProvider: { Date(timeIntervalSince1970: 1_800_000_000) })
        let rates = try await client.fetchRates(baseCurrency: .uah, date: nil)

        #expect(rates.count == 1)
        #expect(rates[0].source == "nbu-official")
        #expect(Decimal(string: rates[0].rateDecimal) == Decimal(string: "38.75"))
        #expect(DateKeys.calendar.isDate(rates[0].effectiveDate, inSameDayAs: expectedDate))
    }

    @Test func nbuThrowsOnHTTPStatus() async throws {
        let session = makeSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        defer { StubURLProtocol.requestHandler = nil }

        let client = NBUOfficialRateClient(urlSession: session, dateProvider: Date.init)
        await #expect(throws: ExchangeRateClientError.httpStatus(500)) {
            _ = try await client.fetchRates(baseCurrency: .uah, date: nil)
        }
    }

    @Test func privatBankDecodesBaseCurrencyAndMidpoint() async throws {
        let session = makeSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data("""
            [
              {"ccy":"USD","base_ccy":"UAH","buy":"41.10","sale":"41.90"}
            ]
            """.utf8)
            return (response, data)
        }
        defer { StubURLProtocol.requestHandler = nil }

        let client = PrivatBankPublicRateClient(urlSession: session, dateProvider: { Date(timeIntervalSince1970: 1_800_000_000) })
        let rates = try await client.fetchRates(baseCurrency: .uah, date: nil)

        #expect(rates.count == 3)
        #expect(rates.map(\.source) == ["privatbank-buy", "privatbank-sell", "privatbank-midpoint"])
        #expect(Decimal(string: rates[0].rateDecimal) == Decimal(string: "41.1"))
        #expect(Decimal(string: rates[2].rateDecimal) == Decimal(string: "41.5"))
    }

    @Test func privatBankThrowsOnHTTPStatus() async throws {
        let session = makeSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        defer { StubURLProtocol.requestHandler = nil }

        let client = PrivatBankPublicRateClient(urlSession: session, dateProvider: Date.init)
        await #expect(throws: ExchangeRateClientError.httpStatus(503)) {
            _ = try await client.fetchRates(baseCurrency: .uah, date: nil)
        }
    }
}
