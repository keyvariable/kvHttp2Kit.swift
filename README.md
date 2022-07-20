# kvHttp2Kit-Swift

![Swift 5.2](https://img.shields.io/badge/swift-5.2-green.svg)
![Linux](https://img.shields.io/badge/os-linux-green.svg)
![macOS](https://img.shields.io/badge/os-macOS-green.svg)

A collection of auxiliaries for HTTP and HTTP/2 on Swift. It's based on [SwiftNIO](https://github.com/apple/swift-nio).


## Supported Platforms

The same as [SwiftNIO](https://github.com/apple/swift-nio).


## Getting Started

### Swift Tools 5.2+

#### Package Dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/keyvariable/kvHttp2Kit-Swift", from: "0.2.0"),
]
```

#### Target Dependencies:

```swift
dependencies: [
    .product(name: "kvHttp2Kit", package: "kvHttp2Kit-Swift"),
]
```

### Xcode

Documentation: [Adding Package Dependencies to Your App](https://developer.apple.com/documentation/xcode/adding_package_dependencies_to_your_app).


## Authors

- Svyatoslav Popov ([@sdpopov-keyvariable](https://github.com/sdpopov-keyvariable), [info@keyvar.com](mailto:info@keyvar.com)).
