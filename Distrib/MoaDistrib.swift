//
// Image downloader written in Swift for iOS and OS X.
//
// https://github.com/evgenyneu/moa
//
// This file was automatically generated by combining multiple Swift source files.
//


// ----------------------------
//
// MoaHttp.swift
//
// ----------------------------

import Foundation

/**

Shortcut function for creating NSURLSessionDataTask.

*/
struct MoaHttp {
  static func createDataTask(url: String,
    onSuccess: (NSData?, NSHTTPURLResponse)->(),
    onError: (NSError?, NSHTTPURLResponse?)->()) -> NSURLSessionDataTask? {
      
    if let nsUrl = NSURL(string: url) {
      return createDataTask(nsUrl, onSuccess: onSuccess, onError: onError)
    }
    
    // Error converting string to NSURL
    onError(MoaHttpErrors.InvalidUrlString.new, nil)
    return nil
  }
  
  private static func createDataTask(nsUrl: NSURL,
    onSuccess: (NSData?, NSHTTPURLResponse)->(),
    onError: (NSError?, NSHTTPURLResponse?)->()) -> NSURLSessionDataTask? {
      
    return MoaHttpSession.session?.dataTaskWithURL(nsUrl) { (data, response, error) in
      if let httpResponse = response as? NSHTTPURLResponse {
        if error == nil {
          onSuccess(data, httpResponse)
        } else {
          onError(error, httpResponse)
        }
      } else {
        onError(error, nil)
      }
    }
  }
}


// ----------------------------
//
// MoaHttpErrors.swift
//
// ----------------------------

import Foundation

/**

Http error types.

*/
public enum MoaHttpErrors: Int {
  /// Incorrect URL is supplied.
  case InvalidUrlString = -1
  
  internal var new: NSError {
    return NSError(domain: "MoaHttpErrorDomain", code: rawValue, userInfo: nil)
  }
}


// ----------------------------
//
// MoaHttpImage.swift
//
// ----------------------------


import Foundation

/**

Helper functions for downloading an image and processing the response.

*/
struct MoaHttpImage {
  static func createDataTask(url: String,
    onSuccess: (MoaImage)->(),
    onError: (NSError?, NSHTTPURLResponse?)->()) -> NSURLSessionDataTask? {
    
    return MoaHttp.createDataTask(url,
      onSuccess: { data, response in
        self.handleSuccess(data, response: response, onSuccess: onSuccess, onError: onError)
      },
      onError: onError
    )
  }
  
  static func handleSuccess(data: NSData?,
    response: NSHTTPURLResponse,
    onSuccess: (MoaImage)->(),
    onError: (NSError, NSHTTPURLResponse?)->()) {
      
    // Show error if response code is not 200
    if response.statusCode != 200 {
      onError(MoaHttpImageErrors.HttpStatusCodeIsNot200.new, response)
      return
    }
    
    // Ensure response has the valid MIME type
    if let mimeType = response.MIMEType {
      if !validMimeType(mimeType) {
        // Not an image Content-Type http header
        let error = MoaHttpImageErrors.NotAnImageContentTypeInResponseHttpHeader.new
        onError(error, response)
        return
      }
    } else {
      // Missing Content-Type http header
      let error = MoaHttpImageErrors.MissingResponseContentTypeHttpHeader.new
      onError(error, response)
      return
    }
      
    if let data = data, image = MoaImage(data: data) {
      onSuccess(image)
    } else {
      // Failed to convert response data to UIImage
      let error = MoaHttpImageErrors.FailedToReadImageData.new
      onError(error, response)
    }
  }
  
  private static func validMimeType(mimeType: String) -> Bool {
    let validMimeTypes = ["image/jpeg", "image/pjpeg", "image/png"]
    return validMimeTypes.contains(mimeType)
  }
}


// ----------------------------
//
// MoaHttpImageDownloader.swift
//
// ----------------------------

import Foundation

final class MoaHttpImageDownloader: MoaImageDownloader {
  var task: NSURLSessionDataTask?
  var cancelled = false
  
  deinit {
    cancel()
  }
  
  func startDownload(url: String, onSuccess: (MoaImage)->(),
    onError: (NSError?, NSHTTPURLResponse?)->()) {
    
    cancelled = false
  
    task = MoaHttpImage.createDataTask(url,
      onSuccess: onSuccess,
      onError: { [weak self] error, response in
        if let currentSelf = self
          where !currentSelf.cancelled { // Do not report error if task was manually cancelled
    
          onError(error, response)
        }
      }
    )
      
    task?.resume()
  }
  
  func cancel() {
    task?.cancel()
    cancelled = true
  }
}


// ----------------------------
//
// MoaHttpImageErrors.swift
//
// ----------------------------

import Foundation

/**

Image download error types.

*/
public enum MoaHttpImageErrors: Int {
  /// Response HTTP status code is not 200.
  case HttpStatusCodeIsNot200 = -1
  
  /// Response is missing Content-Type http header.
  case MissingResponseContentTypeHttpHeader = -2
  
  /// Response Content-Type http header is not an image type.
  case NotAnImageContentTypeInResponseHttpHeader = -3
  
  /// Failed to convert response data to UIImage.
  case FailedToReadImageData = -4
  
  /// Simulated error used in unit tests
  case SimulatedError = -5

  internal var new: NSError {
    return NSError(domain: "MoaHttpImageErrorDomain", code: rawValue, userInfo: nil)
  }
}


// ----------------------------
//
// MoaHttpSession.swift
//
// ----------------------------

import Foundation

struct MoaHttpSession {
  private static var currentSession: NSURLSession?
  
  static var session: NSURLSession? {
    get {
      if currentSession == nil {
        currentSession = createNewSession()
      }
    
      return currentSession
    }
    
    set {
      currentSession = newValue
    }
  }
  
  private static func createNewSession() -> NSURLSession {
    let configuration = NSURLSessionConfiguration.defaultSessionConfiguration()
    
    configuration.requestCachePolicy = Moa.settings.cache.requestCachePolicy
    
    #if os(iOS)
      // Cache path is a directory name in iOS
      let cachePath = Moa.settings.cache.diskPath
    #elseif os(OSX)
      // Cache path is a disk path in OSX
      let cachePath = osxCachePath(Moa.settings.cache.diskPath)
    #endif
    
    let cache = NSURLCache(
      memoryCapacity: Moa.settings.cache.memoryCapacityBytes,
      diskCapacity: Moa.settings.cache.diskCapacityBytes,
      diskPath: cachePath)
    
    configuration.URLCache = cache
    
    return NSURLSession(configuration: configuration)
  }
  
  // Returns the cache path for OSX.
  private static func osxCachePath(dirName: String) -> String {
    var basePath = NSTemporaryDirectory()
    let paths = NSSearchPathForDirectoriesInDomains(NSSearchPathDirectory.ApplicationSupportDirectory,
      NSSearchPathDomainMask.UserDomainMask, true)
    
    if paths.count > 0 {
      basePath = paths[0]
    }
    
    return basePath.stringByAppendingPathComponent(dirName)
  }
  
  static func cacheSettingsChanged(oldSettings: MoaSettingsCache) {
    if oldSettings != Moa.settings.cache {
      session = nil
    }
  }
}


// ----------------------------
//
// ImageView+moa.swift
//
// ----------------------------

import Foundation

private var xoAssociationKey: UInt8 = 0

/**

Image view extension for downloading images.

    let imageView = UIImageView()
    imageView.moa.url = "http://site.com/image.jpg"

*/
public extension MoaImageView {
  /**
  
  Image download extension.
  Assign its `url` property to download and show the image in the image view.
  
      // iOS
      let imageView = UIImageView()
      imageView.moa.url = "http://site.com/image.jpg"
  
      // OS X
      let imageView = NSImageView()
      imageView.moa.url = "http://site.com/image.jpg"
  
  */
  public var moa: Moa {
    get {
      if let value = objc_getAssociatedObject(self, &xoAssociationKey) as? Moa {
        return value
      } else {
        let moa = Moa(imageView: self)
        objc_setAssociatedObject(self, &xoAssociationKey, moa, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN)
        return moa
      }
    }
    
    set {
      objc_setAssociatedObject(self, &xoAssociationKey, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN)
    }
  }
}


// ----------------------------
//
// Moa.swift
//
// ----------------------------

#if os(iOS)
  import UIKit
  public typealias MoaImage = UIImage
  public typealias MoaImageView = UIImageView
#elseif os(OSX)
  import AppKit
  public typealias MoaImage = NSImage
  public typealias MoaImageView = NSImageView
#endif

/**
Downloads an image by url.

Setting `moa.url` property of an image view instance starts asynchronous image download using NSURLSession class.
When download is completed the image is automatically shown in the image view.

    // iOS
    let imageView = UIImageView()
    imageView.moa.url = "http://site.com/image.jpg"

    // OS X
    let imageView = NSImageView()
    imageView.moa.url = "http://site.com/image.jpg"


The class can be instantiated and used without an image view:

    let moa = Moa()
    moa.onSuccessAsync = { image in
      return image
    }
    moa.url = "http://site.com/image.jpg"

*/
public final class Moa {
  private var imageDownloader: MoaImageDownloader?
  private weak var imageView: MoaImageView?

  /// Image download settings.
  public static var settings = MoaSettings()

  /**

  Instantiate Moa when used without an image view.

      let moa = Moa()
      moa.onSuccessAsync = { image in }
      moa.url = "http://site.com/image.jpg"

  */
  public init() { }

  init(imageView: MoaImageView) {
    self.imageView = imageView
  }

  /**

  Assign an image URL to start the download.
  When download is completed the image is automatically shown in the image view.

      imageView.moa.url = "http://mysite.com/image.jpg"

  Supply `onSuccessAsync` closure to receive an image when used without an image view:

      moa.onSuccessAsync = { image in
        return image
      }

  */
  public var url: String? {
    didSet {
      cancel()

      if let url = url {
        startDownload(url)
      }
    }
  }

  /**

  Cancels image download.

  Ongoing image download for the image view is *automatically* cancelled when:

  1. Image view is deallocated.
  2. New image download is started: `imageView.moa.url = ...`.

  Call this method to manually cancel the download.

      imageView.moa.cancel()

  */
  public func cancel() {
    imageDownloader?.cancel()
    imageDownloader = nil
  }
  
  /**
  
  The closure will be called after download finishes and before the image
  is assigned to the image view. The closure is called in the main queue.
  
  The closure returns an image that will be shown in the image view.
  Return nil if you do not want the image to be shown.
  
      moa.onSuccess = { image in
        // Image is received
        return image
      }
  
  */
  public var onSuccess: ((MoaImage)->(MoaImage?))?

  /**

  The closure will be called *asynchronously* after download finishes and before the image
  is assigned to the image view.

  This is a good place to manipulate the image before it is shown.

  The closure returns an image that will be shown in the image view.
  Return nil if you do not want the image to be shown.

      moa.onSuccessAsync = { image in
        // Manipulate the image
        return image
      }

  */
  public var onSuccessAsync: ((MoaImage)->(MoaImage?))?

  /**
  
  The closure is called in the main queue if image download fails.
  [See Wiki](https://github.com/evgenyneu/moa/wiki/Moa-errors) for the list of possible error codes.
  
      onError = { error, httpUrlResponse in
        // Report error
      }
  
  */
  public var onError: ((NSError?, NSHTTPURLResponse?)->())?
  
  /**

  The closure is called *asynchronously* if image download fails.
  [See Wiki](https://github.com/evgenyneu/moa/wiki/Moa-errors) for the list of possible error codes.

      onErrorAsync = { error, httpUrlResponse in
        // Report error
      }

  */
  public var onErrorAsync: ((NSError?, NSHTTPURLResponse?)->())?

  private func startDownload(url: String) {
    cancel()
    
    let simulatedDownloader = MoaSimulator.createDownloader(url)
    imageDownloader = simulatedDownloader ?? MoaHttpImageDownloader()

    imageDownloader?.startDownload(url,
      onSuccess: { [weak self] image in
        let simulated = simulatedDownloader != nil
        self?.onHandleSuccessAsync(image, isSimulated: simulated)
      },
      onError: { [weak self] error, response in
        self?.onHandleErrorAsync(error, response: response)
      }
    )
  }

  /**

  Called asynchronously by image downloader when image is received.
  
  - parameter image: Image received by the downloader.
  - parameter isSimulated: True if the image was supplied by moa simulator rather than real network.

  */
  private func onHandleSuccessAsync(image: MoaImage, isSimulated: Bool) {
    var imageForView: MoaImage? = image

    if let onSuccessAsync = onSuccessAsync {
      imageForView = onSuccessAsync(image)
    }

    if isSimulated {
      // Assign image in the same queue for simulated download to make unit testing simpler with synchronous code
      onHandleSuccessMainQueue(imageForView)
    } else {
      dispatch_async(dispatch_get_main_queue()) { [weak self] in
        self?.onHandleSuccessMainQueue(imageForView)
      }
    }
  }
  
  /**
  
  Called by image downloader in the main queue when image is received.
  
  - parameter image: Image received by the downloader.
  
  */
  private func onHandleSuccessMainQueue(image: MoaImage?) {
    var imageForView: MoaImage? = image
    
    if let onSuccess = onSuccess, image = image {
      imageForView = onSuccess(image)
    }
    
    imageView?.image = imageForView
  }
  
  /**
  
  Called asynchronously by image downloader if imaged download fails.
  
  - parameter error: Error object.
  - parameter response: HTTP response object, can be useful for getting HTTP status code.
  
  */
  private func onHandleErrorAsync(error: NSError?, response: NSHTTPURLResponse?) {
    onErrorAsync?(error, response)
    
    if let onError = onError {
      dispatch_async(dispatch_get_main_queue()) {
        onError(error, response)
      }
    }
  }
}


// ----------------------------
//
// MoaImageDownloader.swift
//
// ----------------------------

import Foundation

/// Downloads an image.
protocol MoaImageDownloader {
  func startDownload(url: String, onSuccess: (MoaImage)->(),
    onError: (NSError?, NSHTTPURLResponse?)->())
  
  func cancel()
}


// ----------------------------
//
// MoaSettings.swift
//
// ----------------------------


/**

Settings for Moa image downloader.

*/
public struct MoaSettings {
  /// Settings for caching of the images.
  public var cache = MoaSettingsCache() {
    didSet {
      MoaHttpSession.cacheSettingsChanged(oldValue)
    }
  }
}


// ----------------------------
//
// MoaSettingsCache.swift
//
// ----------------------------

import Foundation

/**

Specify settings for caching of downloaded images.

*/
public struct MoaSettingsCache {
  /// The memory capacity of the cache, in bytes. Default value is 20 MB.
  public var memoryCapacityBytes: Int = 20 * 1024 * 1024
  
  /// The disk capacity of the cache, in bytes. Default value is 100 MB.
  public var diskCapacityBytes: Int = 100 * 1024 * 1024
  
  /**

  The caching policy for the image downloads. The default value is .UseProtocolCachePolicy.
  
  * .UseProtocolCachePolicy - Images are cached according to the the response HTTP headers, such as age and expiration date. This is the default cache policy.
  * .ReloadIgnoringLocalCacheData - Do not cache images locally. Always downloads the image from the source.
  * .ReturnCacheDataElseLoad - Loads the image from local cache regardless of age and expiration date. If there is no existing image in the cache, the image is loaded from the source.
  * .ReturnCacheDataDontLoad - Load the image from local cache only and do not attempt to load from the source.

  */
  public var requestCachePolicy: NSURLRequestCachePolicy = .UseProtocolCachePolicy
  
  /**
  
  The name of a subdirectory of the application’s default cache directory
  in which to store the on-disk cache.
  
  */
  var diskPath = "moaImageDownloader"
}

func ==(lhs: MoaSettingsCache, rhs: MoaSettingsCache) -> Bool {
  return lhs.memoryCapacityBytes == rhs.memoryCapacityBytes
    && lhs.diskCapacityBytes == rhs.diskCapacityBytes
    && lhs.requestCachePolicy == rhs.requestCachePolicy
    && lhs.diskPath == rhs.diskPath
}

func !=(lhs: MoaSettingsCache, rhs: MoaSettingsCache) -> Bool {
  return !(lhs == rhs)
}


// ----------------------------
//
// MoaSimulatedImageDownloader.swift
//
// ----------------------------

import Foundation

/**

Simulates download of images in unit test. This downloader is used instead of the HTTP downloaded when the moa simulator is started: MoaSimulator.start().

*/
public final class MoaSimulatedImageDownloader: MoaImageDownloader {
  
  /// Url of the downloader.
  public let url: String
  
  /// Indicates if the request was cancelled.
  public var cancelled = false
  
  var autorespondWithImage: MoaImage?
  
  var autorespondWithError: (error: NSError?, response: NSHTTPURLResponse?)?
  
  var onSuccess: ((MoaImage)->())?
  var onError: ((NSError, NSHTTPURLResponse?)->())?

  init(url: String) {
    self.url = url
  }
  
  func startDownload(url: String, onSuccess: (MoaImage)->(),
    onError: (NSError?, NSHTTPURLResponse?)->()) {
      
    self.onSuccess = onSuccess
    self.onError = onError
      
    if let autorespondWithImage = autorespondWithImage {
      respondWithImage(autorespondWithImage)
    }
      
    if let autorespondWithError = autorespondWithError {
      respondWithError(autorespondWithError.error, response: autorespondWithError.response)
    }
  }
  
  func cancel() {
    cancelled = true
  }
  
  /**
  
  Simulate a successful server response with the supplied image.
  
  - parameter image: Image that is be passed to success handler of all ongoing requests.
  
  */
  public func respondWithImage(image: MoaImage) {
    onSuccess?(image)
  }
  
  /**
  
  Simulate an error response from server.
  
  - parameter error: Optional error that is passed to the error handler ongoing request.
  
  - parameter response: Optional response that is passed to the error handler ongoing request.
  
  */
  public func respondWithError(error: NSError? = nil, response: NSHTTPURLResponse? = nil) {
    onError?(error ?? MoaHttpImageErrors.SimulatedError.new, response)
  }
}


// ----------------------------
//
// MoaSimulator.swift
//
// ----------------------------

import Foundation

/**

Simulates image download in unit tests instead of sending real network requests.

Example:

    override func tearDown() {
      super.tearDown()

      MoaSimulator.clear()
    }

    func testDownload() {
      // Create simulator to catch downloads of the given image
      let simulator = MoaSimulator.simulate("35px.jpg")

      // Download the image
      let imageView = UIImageView()
      imageView.moa.url = "http://site.com/35px.jpg"

      // Check the image download has been requested
      XCTAssertEqual(1, simulator.downloaders.count)
      XCTAssertEqual("http://site.com/35px.jpg", simulator.downloaders[0].url)

      // Simulate server response with the given image
      let bundle = NSBundle(forClass: self.dynamicType)
      let image =  UIImage(named: "35px.jpg", inBundle: bundle, compatibleWithTraitCollection: nil)!
      simulator.respondWithImage(image)

      // Check the image has arrived
      XCTAssertEqual(35, imageView.image!.size.width)
    }

*/
public final class MoaSimulator {

  /// Array of currently registered simulators.
  static var simulators = [MoaSimulator]()
  
  /**
  
  Returns a simulator that will be used to catch image requests that have matching URLs. This method is usually called at the beginning of the unit test.
  
  - parameter urlPart: Image download request that include the supplied urlPart will be simulated. All other requests will continue to real network.
  
  - returns: Simulator object. It is usually used in unit test to verify which request have been sent and simulating server response by calling its respondWithImage and respondWithError methods.
  
  */
  public static func simulate(urlPart: String) -> MoaSimulator {
    let simulator = MoaSimulator(urlPart: urlPart)
    simulators.append(simulator)
    return simulator
  }
  
  /**
  
  Respond to all future download requests that have matching URLs. Call `clear` method to stop auto responding.
  
  - parameter urlPart: Image download request that include the supplied urlPart will automatically and immediately succeed with the supplied image. All other requests will continue to real network.
  
  - parameter image: Image that is be passed to success handler of future requests.
  
  - returns: Simulator object. It is usually used in unit test to verify which request have been sent.  One does not need to call its `respondWithImage` method because it will be called automatically for all matching requests.
  
  */
  public static func autorespondWithImage(urlPart: String, image: MoaImage) -> MoaSimulator {
    let simulator = simulate(urlPart)
    simulator.autorespondWithImage = image
    return simulator
  }
  
  /**
  
  Fail all future download requests that have matching URLs. Call `clear` method to stop auto responding.
  
  - parameter urlPart: Image download request that include the supplied urlPart will automatically and immediately fail. All other requests will continue to real network.
  
  - parameter error: Optional error that is passed to the error handler of failed requests.
  
  - parameter response: Optional response that is passed to the error handler of failed requests.
  
  - returns: Simulator object. It is usually used in unit test to verify which request have been sent.  One does not need to call its `respondWithError` method because it will be called automatically for all matching requests.
  
  */
  public static func autorespondWithError(urlPart: String, error: NSError? = nil,
    response: NSHTTPURLResponse? = nil) -> MoaSimulator {
      
    let simulator = simulate(urlPart)
    simulator.autorespondWithError = (error, response)
    return simulator
  }
  
  /// Stop using simulators and use real network instead.
  public static func clear() {
    simulators = []
  }
  
  static func simulatorsMatchingUrl(url: String) -> [MoaSimulator] {
    return simulators.filter { simulator in
      MoaString.contains(url, substring: simulator.urlPart)
    }
  }
  
  static func createDownloader(url: String) -> MoaSimulatedImageDownloader? {
    let matchingSimulators = simulatorsMatchingUrl(url)
    
    if !matchingSimulators.isEmpty {
      let downloader = MoaSimulatedImageDownloader(url: url)

      for simulator in matchingSimulators {
        simulator.downloaders.append(downloader)
        
        if let autorespondWithImage = simulator.autorespondWithImage {
          downloader.autorespondWithImage = autorespondWithImage
        }
        
        if let autorespondWithError = simulator.autorespondWithError {
          downloader.autorespondWithError = autorespondWithError
        }
      }
      
      return downloader
    }
    
    return nil
  }
  
  // MARK: - Instance
  
  var urlPart: String
  
  /// The image that will be used to respond to all future download requests
  var autorespondWithImage: MoaImage?
  
  var autorespondWithError: (error: NSError?, response: NSHTTPURLResponse?)?
  
  /// Array of registered image downloaders.
  public var downloaders = [MoaSimulatedImageDownloader]()
  
  init(urlPart: String) {
    self.urlPart = urlPart
  }
  
  /**
  
  Simulate a successful server response with the supplied image.
  
  - parameter image: Image that is be passed to success handler of all ongoing requests.
  
  */
  public func respondWithImage(image: MoaImage) {
    for downloader in downloaders {
      downloader.respondWithImage(image)
    }
  }
  
  /**
  
  Simulate an error response from server.
  
  - parameter error: Optional error that is passed to the error handler of all ongoing requests.
  
  - parameter response: Optional response that is passed to the error handler of all ongoing requests.
  
  */
  public func respondWithError(error: NSError? = nil, response: NSHTTPURLResponse? = nil) {
    for downloader in downloaders {
      downloader.respondWithError(error, response: response)
    }
  }
}


// ----------------------------
//
// MoaString.swift
//
// ----------------------------

import Foundation

//
// Helpers for working with strings
//

struct MoaString {
  static func contains(text: String, substring: String,
    ignoreCase: Bool = false,
    ignoreDiacritic: Bool = false) -> Bool {
            
    var options = NSStringCompareOptions()
    
    if ignoreCase { options.insert(NSStringCompareOptions.CaseInsensitiveSearch) }
    if ignoreDiacritic { options.insert(NSStringCompareOptions.DiacriticInsensitiveSearch) }
    
    return text.rangeOfString(substring, options: options) != nil
  }
}


