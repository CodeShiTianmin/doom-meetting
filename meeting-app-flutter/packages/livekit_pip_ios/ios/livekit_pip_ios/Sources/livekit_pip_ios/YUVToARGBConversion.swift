import Accelerate
import Foundation

final class YUVToARGBConversion {

    enum Coefficient {
        case bt601
        case bt709

        var matrix: UnsafePointer<vImage_YpCbCrToARGBMatrix> {
            switch self {
            case .bt601: return kvImage_YpCbCrToARGBMatrix_ITU_R_601_4
            case .bt709: return kvImage_YpCbCrToARGBMatrix_ITU_R_709_2
            }
        }
    }

    var output: vImage_YpCbCrToARGB

    init(
        coefficient: Coefficient = .bt601,
        inYpCbCrType: vImageYpCbCrType = kvImage420Yp8_Cb8_Cr8,
        outARGBType: vImageARGBType = kvImageARGB8888,
        flags: UInt32 = UInt32(kvImageNoFlags)
    ) {
        var pixelRange = vImage_YpCbCrPixelRange.default
        output = vImage_YpCbCrToARGB()
        vImageConvert_YpCbCrToARGB_GenerateConversion(
            coefficient.matrix,
            &pixelRange,
            &output,
            inYpCbCrType,
            outARGBType,
            flags
        )
    }
}
