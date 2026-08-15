import AVFoundation
import Flutter
import UIKit

private let thumbnailChannelName = "cheriflix/native_thumbnail_extractor"

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let thumbnailQueue = DispatchQueue(
    label: "cheriflix.thumbnail.extractor",
    qos: .userInitiated,
    attributes: .concurrent
  )

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    guard let controller = window?.rootViewController as? FlutterViewController else {
      return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    let channel = FlutterMethodChannel(
      name: thumbnailChannelName,
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "extractFrame" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.handleExtractFrame(call: call, result: result)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func handleExtractFrame(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(code: "invalid_args", message: "Missing arguments", details: nil))
      return
    }

    guard
      let videoPath = args["videoPath"] as? String,
      let width = args["width"] as? Int,
      let height = args["height"] as? Int
    else {
      result(FlutterError(code: "invalid_args", message: "Invalid required args", details: nil))
      return
    }

    let timeMs = (args["timeMs"] as? Int) ?? 0
    let exact = (args["exact"] as? Bool) ?? false
    let jpegQuality = max(40, min(100, (args["jpegQuality"] as? Int) ?? (exact ? 90 : 80)))

    if videoPath.hasPrefix("http://") || videoPath.hasPrefix("https://") {
      // Local-file-focused pipeline.
      result(nil)
      return
    }

    let fileUrl: URL
    if videoPath.hasPrefix("file://"), let parsed = URL(string: videoPath) {
      fileUrl = parsed
    } else {
      fileUrl = URL(fileURLWithPath: videoPath)
    }

    if !FileManager.default.fileExists(atPath: fileUrl.path) {
      result(nil)
      return
    }

    thumbnailQueue.async {
      do {
        let extraction = try self.extractFrame(
          from: fileUrl,
          timeMs: max(0, timeMs),
          width: max(1, width),
          height: max(1, height),
          exact: exact,
          jpegQuality: jpegQuality
        )
        DispatchQueue.main.async {
          if let extraction = extraction {
            result([
              "bytes": FlutterStandardTypedData(bytes: extraction.bytes),
              "actualTimeMs": extraction.actualTimeMs,
            ])
          } else {
            result(nil)
          }
        }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "extract_failed", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  private func extractFrame(
    from url: URL,
    timeMs: Int,
    width: Int,
    height: Int,
    exact: Bool,
    jpegQuality: Int
  ) throws -> IOSFrameExtractionResult? {
    let asset = AVURLAsset(url: url)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: width, height: height)

    if exact {
      // As close to requested timestamp as practical for settled thumbnail.
      generator.requestedTimeToleranceBefore = .zero
      generator.requestedTimeToleranceAfter = .zero
    } else {
      // Relaxed tolerance for faster preview response under active drag.
      let tolerance = CMTime(value: 180, timescale: 1000) // 180ms
      generator.requestedTimeToleranceBefore = tolerance
      generator.requestedTimeToleranceAfter = tolerance
    }

    let requestTime = CMTime(value: CMTimeValue(timeMs), timescale: 1000)
    var actualTime = CMTime.zero

    do {
      let imageRef = try generator.copyCGImage(at: requestTime, actualTime: &actualTime)
      let image = UIImage(cgImage: imageRef)
      guard
        let data = image.jpegData(compressionQuality: CGFloat(jpegQuality) / 100.0)
      else {
        return nil
      }

      return IOSFrameExtractionResult(
        bytes: data,
        actualTimeMs: Int((CMTimeGetSeconds(actualTime) * 1000.0).rounded())
      )
    } catch {
      if !exact {
        return nil
      }
      // Fallback to relaxed tolerance for edge codecs where strict zero fails.
      generator.requestedTimeToleranceBefore = CMTime(value: 250, timescale: 1000)
      generator.requestedTimeToleranceAfter = CMTime(value: 250, timescale: 1000)
      let fallbackImage = try generator.copyCGImage(at: requestTime, actualTime: &actualTime)
      let image = UIImage(cgImage: fallbackImage)
      guard let data = image.jpegData(compressionQuality: CGFloat(jpegQuality) / 100.0) else {
        return nil
      }
      return IOSFrameExtractionResult(
        bytes: data,
        actualTimeMs: Int((CMTimeGetSeconds(actualTime) * 1000.0).rounded())
      )
    }
  }
}

private struct IOSFrameExtractionResult {
  let bytes: Data
  let actualTimeMs: Int
}
