import CoreImage

#if !COCOAPODS
import BrightroomEngine
#endif

struct FilterHSLPlus: Filtering, Equatable, Hashable {
    var adjustments: [HSLChannel: HSLAdjustment]

    init(adjustments: [HSLChannel: HSLAdjustment]) {
        self.adjustments = adjustments
    }

    var isZero: Bool {
        adjustments.values.allSatisfy(\.isZero)
    }

    func apply(to image: CIImage, sourceImage: CIImage) -> CIImage {
        guard !isZero else {
            return image
        }

        let maxSide = max(image.extent.width, image.extent.height)
        let cubeDimension = maxSide > 1200 ? 64 : 32

        return HSLPlusFilter.shared.apply(
            to: image,
            adjustments: adjustments,
            cubeDimension: cubeDimension
        ) ?? image
    }
}

extension Dictionary where Key == HSLChannel, Value == HSLAdjustment {
    static var zeroHSLAdjustments: [HSLChannel: HSLAdjustment] {
        Dictionary(uniqueKeysWithValues: HSLChannel.allCases.map { ($0, .zero) })
    }
}

extension EditingStack.Edit.Filters {
    var hslPlusFilter: FilterHSLPlus? {
        additionalFilters.compactMap { $0.base as? FilterHSLPlus }.first
    }

    mutating func setHSLPlusFilter(_ filter: FilterHSLPlus?) {
        additionalFilters.removeAll { $0.base as? FilterHSLPlus != nil }

        guard let filter, !filter.isZero else {
            return
        }

        additionalFilters.append(filter.asAny())
    }
}
