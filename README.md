# kvServerKit.swift

*kvServerKit* is a cross-platform framework providing API to implement servers. Some features:

- secure connections over HTTP/1.1 and HTTP/2.0;
- imperative and declarative APIs;
- multithreaded request processing;
- validation of requests and various automatic customizable context-dependent responses, e.g. 400, 404, 413;
- automatic Last-Modified and ETag headers for file responses;
- automatic 304 and 412 responses for preconditions on ETag and modification date;
- automatic handling of HEAD method.

*kvServerKit* uses [SwiftNIO](https://github.com/apple/swift-nio) framework to manage network connections and HTTP.


## Declarative API

Servers can be implemented with *declarative API* in a declarative way.
*Declarative API* is designed to create compact, easy-to-read server implementations
and to eliminate the need to write complex and boilerplate code for common tasks.
Some features:
- fast routing and validation of requests;
- fast parsing of URL query items and request bodies;
- structured URL queries;
- handlers for common request body types;
- support of Punycode and percent-encoding for URLs;
- redirections from alias hosts and optional prefixes.

Just declare hierarchical list of responses, *kvServerKit* will do the rest. Responses can be declared in any order.
*Declarative API* automatically starts declared network communication channels, builds routing trees to responses and URL query parsers.
*Declarative API* automatically returns 404 (Not Found) response when there is no declared response for a request.

One of *declarative API* key features is structured URL query.
There are modifiers of requests declaring types of URL query item values and optionally custom parsing callbacks.
If structure of URL query is declared then the resulting values are available as a tuple in the response's callback.

*Declarative API* allows response overloading by URL query.
Any number of responses can be declared at the same routing point: HTTP method, user, host and path.
In this case single unambiguous response matching an URL query will be returned.
If there are two or more matching responses then *declarative API* automatically returns 400 (Bad Request) response. 

*Declarative API* builds fast single-pass URL query parser for several responses with declared structure of URL query at the same routing point.

Below is an example of a server providing simple responses over secure HTTP/2.0 and HTTP/1.1 at all available IP addresses on 8080 port
on "example.com" host and redirections from "www.example.com", "example.org", "www.example.org", "example.net", "www.example.net" hosts:
- frontend files at "/var/www/example.com" directory with support of index files and status pages named "\(statusCode).html"
  in "Status" or "status" subdirectory;
- echo binary response with *POST* request's body at `/echo` path;
- random boolean text response at `/random/bool` path;
- random integer text response with structured URL query at `/random/int` path;
- usage hint for any unhandled subpath at "/random" path. 

```swift
@main
struct ExampleServer : KvServer {
    var body: some KvResponseRootGroup {
        let ssl: KvHttpChannel.Configuration.SSL = loadHttpsCertificate()

        KvGroup(http: .v2(ssl: ssl), at: Host.current().addresses, on: [ 8080 ]) {
            KvGroup(hosts: "example.com",
                    hostAliases: "example.org", "example.net",
                    optionalSubdomains: "www")
            {
                URL(string: "file:///var/www/example.com/")

                KvGroup("echo") {
                    KvHttpResponse.dynamic
                        .requestBody(.data)
                        .content { input in
                            guard let data: Data = input.requestBody else { return .badRequest }
                            return .binary { data }
                                .contentLength(data.count)
                        }
                }
                .httpMethods(.POST)

                KvGroup("random") {
                    RandomValueResponseGroup()
                }
                .onHttpIncident { incident in
                    guard incident.defaultStatus == .notFound else { return nil }
                    return try .notFound.string {
                        "Usage:\n  /random/bool\n  /random/int[?from=1[&through=9]]"
                    }
                }
            }
        }
    }
}

struct RandomValueResponseGroup : KvResponseGroup {
    var body: some KvResponseGroup {
        KvGroup("bool") {
            KvHttpResponse.static { .string { "\(Bool.random())" } }
        }
        KvGroup("int") {
            KvHttpResponse.dynamic
                .query(.optional("from", of: Int.self))
                .query(.optional("through", of: Int.self))
                .queryFlatMap { from, through -> QueryResult<ClosedRange<Int>> in
                    let lowerBound = from ?? .min, upperBound = through ?? .max
                    return lowerBound <= upperBound ? .success(lowerBound ... upperBound) : .failure
                }
                .content { input in .string { "\(Int.random(in: input.query))" } }
        }
    }
}
```

See well-commented [*DeclarativeServer*](./Samples/DeclarativeServer) sample project in [`Samples`](./Samples) directory for more examples.


## Imperative API

Imperative API provides classes and delegate protocols to implement servers in an object-oriented way.

See [*ImperativeServer*](./Samples/ImperativeServer) sample project in [`Samples`](./Samples) directory.


## Supported Platforms

The same as [SwiftNIO](https://github.com/apple/swift-nio).
Package is built and the unit-tests are passed on macOS and Linux (Ubuntu 22.04).


## Getting Started

#### Package Dependencies:
```swift
.package(url: "https://github.com/keyvariable/kvServerKit.swift.git", from: "0.3.0")
```
#### Target Dependencies:
```swift
.product(name: "kvServerKit", package: "kvServerKit.swift")
```
#### Import:
```swift
import kvServerKit
```


## Authors

- Svyatoslav Popov ([@sdpopov-keyvariable](https://github.com/sdpopov-keyvariable), [info@keyvar.com](mailto:info@keyvar.com)).
