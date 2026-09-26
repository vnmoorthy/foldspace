import UIKit
import ImageIO

/// Optional pre-rendered effects. Views retain procedural fallbacks when a file is absent.
enum VisualAssets {
    private static let images = NSCache<NSString, UIImage>()
    private static let atlases = NSCache<NSString, NSArray>()

    /// Downsample large galaxy planes for phone-sized presentation before decoding them.
    static func image(named name: String) -> UIImage? {
        if let cached = images.object(forKey: name as NSString) { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cgImage)
        images.setObject(image, forKey: name as NSString, cost: cgImage.bytesPerRow * cgImage.height)
        return image
    }

    /// PNG atlas coordinates start at the top-left and advance across each row.
    static func frames(named name: String, columns: Int, rows: Int) -> [UIImage] {
        guard columns > 0, rows > 0 else { return [] }
        let key = "\(name)#\(columns)x\(rows)" as NSString
        if let cached = atlases.object(forKey: key) as? [UIImage] { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width % columns == 0, image.height % rows == 0 else { return [] }
        let width = image.width / columns
        let height = image.height / rows
        let frames = (0..<(columns * rows)).compactMap { index -> UIImage? in
            let rect = CGRect(x: (index % columns) * width, y: (index / columns) * height,
                              width: width, height: height)
            guard let tile = image.cropping(to: rect) else { return nil }
            return UIImage(cgImage: tile)
        }
        guard frames.count == columns * rows else { return [] }
        atlases.setObject(frames as NSArray, forKey: key, cost: image.bytesPerRow * image.height)
        return frames
    }
}
