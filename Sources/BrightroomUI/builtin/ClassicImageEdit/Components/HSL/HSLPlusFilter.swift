import UIKit
import CoreImage

/// 某一个颜色通道上，用户拧了三根滑杆之后的数值：色相偏多少度、饱和度加减多少、亮度加减多少。
struct HSLAdjustment: Equatable, Hashable, Codable {
    var hue: Float
    var saturation: Float
    var lightness: Float

    static let zero = HSLAdjustment(hue: 0, saturation: 0, lightness: 0)

    /// 三根滑杆是不是几乎都回到中间（没动），滤镜这条路径可以当成「不用算」。
    var isZero: Bool {
        abs(hue) < 0.001 && abs(saturation) < 0.001 && abs(lightness) < 0.001
    }
}

/// App 里那 8 个彩色圆点：红橙黄绿青蓝紫洋红。每个通道在色环上有个「中心角度」，滤镜就靠它判断像素算不算这一类颜色。
enum HSLChannel: Int, CaseIterable, Hashable, Codable {
    case red
    case orange
    case yellow
    case green
    case cyan
    case blue
    case purple
    case magenta

    /// 界面上展示用的中文名字，给用户看的。
    var displayName: String {
        switch self {
        case .red: return "红色"
        case .orange: return "橙色"
        case .yellow: return "黄色"
        case .green: return "绿色"
        case .cyan: return "青色"
        case .blue: return "蓝色"
        case .purple: return "紫色"
        case .magenta: return "洋红"
        }
    }

    /// 这个通道在色环上的「正中心」色相（0~1，对应一圈 360°），离它近的颜色算「归这类通道管」。
    var centerHue: Float {
        switch self {
        case .red: return 0.0 / 360.0
        case .orange: return 30.0 / 360.0
        case .yellow: return 60.0 / 360.0
        case .green: return 120.0 / 360.0
        case .cyan: return 185.0 / 360.0
        case .blue: return 220.0 / 360.0
        case .purple: return 275.0 / 360.0
        case .magenta: return 315.0 / 360.0
        }
    }

    /// 圆点、渐变条上用的代表色，纯 UI 好看用的，和算法里的 centerHue 是配套的。
    var uiColor: UIColor {
        switch self {
        case .red: return UIColor(red: 0.92, green: 0.12, blue: 0.16, alpha: 1)
        case .orange: return UIColor(red: 1.00, green: 0.55, blue: 0.20, alpha: 1)
        case .yellow: return UIColor(red: 1.00, green: 0.82, blue: 0.04, alpha: 1)
        case .green: return UIColor(red: 0.25, green: 0.70, blue: 0.25, alpha: 1)
        case .cyan: return UIColor(red: 0.08, green: 0.72, blue: 0.78, alpha: 1)
        case .blue: return UIColor(red: 0.10, green: 0.48, blue: 0.95, alpha: 1)
        case .purple: return UIColor(red: 0.57, green: 0.26, blue: 0.84, alpha: 1)
        case .magenta: return UIColor(red: 0.88, green: 0.18, blue: 0.80, alpha: 1)
        }
    }
}

/// 真正干活的：根据 HSL 调整拼一张「颜色查找表」（LUT），交给 Core Image 的 CIColorCube 一次性套到整张照片上，比逐像素算快多了。
final class HSLPlusFilter {
    static let shared = HSLPlusFilter()

    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private lazy var context = CIContext(options: [
        .workingColorSpace: colorSpace,
        .outputColorSpace: colorSpace,
        .cacheIntermediates: true
    ])

    /// 单例：外面只用 `HSLPlusFilter.shared`，不让大家到处 `init` 重复建 CIContext。
    private init() {}

    /// 把当前这套 HSL 调整套到图上：先转正方向，没调就原图返回；有调就造 LUT + `CIColorCube` 出一张新图。
    func render(
        image: UIImage,
        adjustments: [HSLChannel: HSLAdjustment],
        cubeDimension: Int
    ) -> UIImage? {
        // 先把图转正成 .up，避免 CIImage 和后面色算各说各的朝向。
        let normalizedImage = image.normalizedUpImage()
        guard let inputImage = CIImage(image: normalizedImage) else {
            return nil
        }

        guard let outputImage = apply(
            to: inputImage,
            adjustments: adjustments,
            cubeDimension: cubeDimension
        ) else {
            return nil
        }

        guard outputImage !== inputImage else {
            return normalizedImage
        }

        // CIFilter 出来还是 CIImage，要 raster 成位图才能再包回 UIImage。
        guard let cgImage = context.createCGImage(outputImage, from: inputImage.extent) else {
            return nil
        }

        // scale 跟原图走，orientation 定死朝上（前面已经 normalized 过了）。
        return UIImage(cgImage: cgImage, scale: normalizedImage.scale, orientation: .up)
    }

    func apply(
        to image: CIImage,
        adjustments: [HSLChannel: HSLAdjustment],
        cubeDimension: Int
    ) -> CIImage? {
        // 滑杆全在中间、等于没调的通道踢掉，少算点 LUT。
        let activeAdjustments = adjustments.filter { !$0.value.isZero }
        // 完全没动 HSL：滤镜原样返回，省一次 GPU。
        guard !activeAdjustments.isEmpty else {
            return image
        }

        // CPU 侧先把「任意 RGB 进去、该变什么 RGB 出来」编成 3D 查找表。
        let cubeData = makeCubeData(
            dimension: cubeDimension,
            adjustments: activeAdjustments
        )

        // 系统自带：按立方体查表改整张图的颜色。
        guard let filter = CIFilter(name: "CIColorCube") else {
            return nil
        }

        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(cubeDimension, forKey: "inputCubeDimension")
        filter.setValue(cubeData, forKey: "inputCubeData")

        return filter.outputImage
    }

    /// 按立方体边长 `dimension` 枚举每个 RGB 小格子，转成 HSL 按通道加权改色，再塞回一块给 Core Image 用的 float 立方体数据。
    private func makeCubeData(
        dimension: Int,
        adjustments: [HSLChannel: HSLAdjustment]
    ) -> Data {
        // N×N×N 个格子，每格 RGBA 四个 float。
        let totalCount = dimension * dimension * dimension * 4
        var cube = [Float](repeating: 0, count: totalCount)
        let maxIndex = Float(dimension - 1)
        var offset = 0

        // 三重循环扫整个 RGB 立方体：每个格子的「输入色」算出一个「输出色」。
        for bIndex in 0..<dimension {
            let b = Float(bIndex) / maxIndex
            for gIndex in 0..<dimension {
                let g = Float(gIndex) / maxIndex
                for rIndex in 0..<dimension {
                    let r = Float(rIndex) / maxIndex

                    // 进 HSL 才能在色环上谈「这是红通道还是黄通道」。
                    var hsl = rgbToHsl(r: r, g: g, b: b)

                    // 灰度几乎没色相，别硬拧 H，否则数值会飘。
                    if hsl.s > 0.015 {

                        // rawValue 排序只是让多通道叠加时顺序固定、结果可复现。
                        for (channel, adjustment) in adjustments.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {

                            // 和该通道中心色相差多少（越近越该吃这一刀的参数）。
                            let distance = hueDistance(hsl.h, channel.centerHue)
                            let range: Float = 16.0 / 360.0
                            let feather: Float = 22.0 / 360.0

                            // 中间实、边缘虚的权重，过渡用 smoothstep 抹平硬边。
                            let weight = 1.0 - smoothstep(
                                edge0: range,
                                edge1: range + feather,
                                x: distance
                            )

                            if weight > 0.0001 {

                                // 按权重把用户调的色相旋转、饱和/亮度偏移叠上去。
                                hsl.h = wrap01(hsl.h + adjustment.hue / 360.0 * weight)
                                hsl.s = clamp(hsl.s + adjustment.saturation / 100.0 * weight, 0, 1)
                                hsl.l = clamp(hsl.l + adjustment.lightness / 100.0 * weight, 0, 1)
                            }
                        }
                    }

                    // LUT 里存的还是 RGB，转回去写入连续 float。
                    let rgb = hslToRgb(h: hsl.h, s: hsl.s, l: hsl.l)

                    cube[offset + 0] = rgb.r
                    cube[offset + 1] = rgb.g
                    cube[offset + 2] = rgb.b
                    cube[offset + 3] = 1.0
                    offset += 4
                }
            }
        }

        // 交给 CIColorCube 的就是这一坨裸字节。
        return cube.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }

    /// 标准算法：把 0~1 的 RGB 变成色相(H)、饱和度(S)、亮度(L)，H、S、L 也都是归一化好的，方便后面按色相分区动刀。
    private func rgbToHsl(r: Float, g: Float, b: Float) -> (h: Float, s: Float, l: Float) {
        let maxValue = max(r, max(g, b))
        let minValue = min(r, min(g, b))
        let delta = maxValue - minValue
        // L：最亮最暗的中点，0~1。
        let l = (maxValue + minValue) / 2.0

        // RGB 三个数一模一样：没有色相、没有饱和度，只剩亮度。
        guard delta > 0.000001 else {
            return (0, 0, l)
        }

        let s = delta / (1.0 - abs(2.0 * l - 1.0))
        var h: Float

        // H：看「谁最大」分三支公式，把一圈色相摊在 0~1（不是角度制）。
        if maxValue == r {
            h = ((g - b) / delta).truncatingRemainder(dividingBy: 6.0)
        } else if maxValue == g {
            h = ((b - r) / delta) + 2.0
        } else {
            h = ((r - g) / delta) + 4.0
        }

        h /= 6.0
        if h < 0 { h += 1.0 }

        return (h, s, l)
    }

    /// 把 HSL 再翻译回 RGB，写入 LUT 格子前最后一步；灰度（没饱和度）时三个通道都等于亮度。
    private func hslToRgb(h: Float, s: Float, l: Float) -> (r: Float, g: Float, b: Float) {
        // 没彩度就是灰片，三个通道都抄亮度。
        if s <= 0.000001 {
            return (l, l, l)
        }

        // 经典两段式：先算临时色 q，再配 p，后面 hueToRgb 分段插值。
        let q = l < 0.5 ? l * (1.0 + s) : l + s - l * s
        let p = 2.0 * l - q

        let r = hueToRgb(p: p, q: q, t: h + 1.0 / 3.0)
        let g = hueToRgb(p: p, q: q, t: h)
        let b = hueToRgb(p: p, q: q, t: h - 1.0 / 3.0)

        return (r, g, b)
    }

    /// `hslToRgb` 里拆出来的一小块：根据辅助点 p、q 和插值参数 t 算出某一个 R/G/B 分量。
    private func hueToRgb(p: Float, q: Float, t input: Float) -> Float {
        var t = input
        // t 在 0~1 一段里折返，像色相在色环上转圈。
        if t < 0 { t += 1 }
        if t > 1 { t -= 1 }

        if t < 1.0 / 6.0 { return p + (q - p) * 6.0 * t }
        if t < 1.0 / 2.0 { return q }
        if t < 2.0 / 3.0 { return p + (q - p) * (2.0 / 3.0 - t) * 6.0 }
        return p
    }

    /// 色环是首尾相接的：两个色相的「最短弧长」，用来算这个像素离通道中心有多近。
    private func hueDistance(_ a: Float, _ b: Float) -> Float {
        let d = abs(a - b)
        // 既往前走也往后走，取短的那条弧。
        return min(d, 1.0 - d)
    }

    /// 平滑阶梯：从 0 慢慢爬到 1，过渡比线性柔和，用来做「离中心越远影响越小」的权重曲线。
    private func smoothstep(edge0: Float, edge1: Float, x: Float) -> Float {
        guard edge1 != edge0 else { return x < edge0 ? 0 : 1 }
        // 先归一化到 0~1，再用 3t²-2t³ 那种 S 形。
        let t = clamp((x - edge0) / (edge1 - edge0), 0, 1)
        return t * t * (3.0 - 2.0 * t)
    }

    /// 把数卡在最小最大值之间，饱和度亮度不能飞出 0~1。
    private func clamp(_ value: Float, _ minValue: Float, _ maxValue: Float) -> Float {
        min(max(value, minValue), maxValue)
    }

    /// 色相加了偏移之后折回 0~1 一圈里，避免跑出色环。
    private func wrap01(_ value: Float) -> Float {
        var v = value.truncatingRemainder(dividingBy: 1.0)
        //  remainder 可能是负的，加一圈拉回来。
        if v < 0 { v += 1.0 }
        return v
    }
}
