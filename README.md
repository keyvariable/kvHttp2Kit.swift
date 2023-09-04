# kvServerKit.swift

![Linux](https://img.shields.io/badge/os-linux-green.svg)
![macOS](https://img.shields.io/badge/os-macOS-green.svg)

*kvServerKit* is a framework providing API to implement servers. Some features:

- secure connections over HTTP/1.1 and HTTP/2.0;
- imperative and declarative APIs;
- automatic disconnection of clients exceeding configurable limits (request size, idle time, number of requests per connection).

*kvServerKit* uses [SwiftNIO](https://github.com/apple/swift-nio) framework to manage network connections and HTTP.


## Declarative API

Servers can be implemented with *declarative API* in a declarative way.
*Declarative API* is designed to create compact, easy-to-read server implementations
and to eliminate the need to write complex and boilerplate implementations for common tasks.
Some features:
- fast routing and validation of requests;
- fast parsing of URL query items and request bodies;
- structured URL queries;
- handlers for common request body types;
- support of Punycode and percent-encoding for URLs;
- convenient response content builder;
- JSON for request and response bodies.

Just declare hierarchical list of responses, *kvServerKit* will do the rest. Responses can be declared in any order.
*Declarative API* automatically starts declared network communication channels, builds routing trees to responses and URL query parsers.
*Declarative API* automatically returns 404 (Not Found) response when there is no declared response for a request.

One of *declarative API* key features is structured URL query.
There are modifiers of requests declaring types of URL query item values and optionally custom parsing callbacks.
If structure of URL query is declared then the resulting values are available as a tuple in the response context.

*Declarative API* allows response overloading by URL query.
Any number of responses can be declared at the same routing point: HTTP method, user, host and path.
In this case single unambiguous response matching an URL query will be returned.
If there are two or more matching responses then *declarative API* automatically returns 400 (Bad Request) response. 

*Declarative API* builds fast single-pass URL query parser for several responses with declared structure of URL query at the same routing point.

Below is an example of a server providing simple responses over secure HTTP/2.0 and HTTP/1.1 at all available IP addresses on 8080 port
for both `example.com` and `www.example.com` hosts:
- simple greeting text response at root path;
- echo binary response with *POST* request's body at `/echo` path;
- random boolean text response at `/random/bool` path;
- random integer text response with structured URL query at `/random/int` path.

```swift
@main
struct ExampleServer : KvServer {
    var body: some KvResponseGroup {
        let ssl: KvHttpChannel.Configuration.SSL = loadHttpsCertificate()
    
        KvGroup(http: .v2(ssl: ssl), at: Host.current().addresses, on: [ 8080 ]) {
            KvHttpResponse.static { .string("Hello, client") }

            KvGroup("echo") {
                KvHttpResponse.dynamic
                    .requestBody(.data)
                    .content { .binary($0.requestBody ?? Data()) }
            }
            .httpMethods(.POST)

            KvGroup("random") {
                RandomValueResponseGroup()
            }
        }
        .hosts("example.com")
        .subdomains(optional: "www")
    }
}
    
struct RandomValueResponseGroup : KvResponseGroup {
    var body: KvResponseGroup {
        KvGroup("bool") {
            KvHttpResponse.static { .string("\(Bool.random())") }
        }
        KvGroup("int") {
            KvHttpResponse.dynamic
                .query(.optional("from", of: Int.self))
                .query(.optional("through", of: Int.self))
                .queryFlatMap { from, through -> QueryResult<ClosedRange<Int>> in
                    let lowerBound = from ?? .min, upperBound = through ?? .max
                    return lowerBound <= upperBound ? .success(lowerBound ... upperBound) : .failure
                }
                .content { .string("\(Int.random(in: $0.query))") }
        }
    }
}
```

See well-commented *DeclarativeServer* sample project in `/Samples` directory for more examples.


## Imperative API

Imperative API provides classes and delegate protocols to implement servers in an object-oriented way.

See *ImperativeServer* sample project in `/Samples` directory.


## Supported Platforms

The same as [SwiftNIO](https://github.com/apple/swift-nio).


## Getting Started

#### Package Dependencies:
```swift
dependencies: [ .package(url: "https://github.com/keyvariable/kvServerKit.swift.git", from: "0.2.0") ]
```
#### Target Dependencies:
```swift
dependencies: [ .product(name: "kvServerKit", package: "kvServerKit.swift") ]
```
#### Import:
```swift
import kvServerKit
```


## Authors

- Svyatoslav Popov ([@sdpopov-keyvariable](https://github.com/sdpopov-keyvariable), [info@keyvar.com](mailto:info@keyvar.com)).
