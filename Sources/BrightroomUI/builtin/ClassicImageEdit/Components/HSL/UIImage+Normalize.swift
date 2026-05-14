import UIKit

/// 给相册图补的两招：`normalizedUpImage` 把方向摆正，`scaledImage` 缩小给实时预览省算力。
extension UIImage {
    /// 相册里来的图经常是横着、倒着的（带 orientation）。先画成一张「头朝上」的图，后面算颜色才不会乱。
    func normalizedUpImage() -> UIImage {
        if imageOrientation == .up {
            return self
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false

        // 画到一张新 bitmap 里，.exif 里的旋转会被「烤」进像素，orientation 就变成 up。
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// 把最长边压到指定长度以内，像素少一点，预览/调色时 GPU 压力小；不放大，本来就小的图原样返回。
    func scaledImage(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        // 已经够小就不动，避免无谓失真。
        guard longest > maxSide else {
            return self
        }

        let ratio = maxSide / longest
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
