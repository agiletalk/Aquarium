import CoreGraphics
import CoreImage
import Foundation

/// 라운지 전시용 QR 코드 생성. CoreImage의 CIQRCodeGenerator로 모듈 격자를 뽑는다 —
/// 시스템 프레임워크라 Package.swift 의존성은 그대로 0이다.
enum QRCode {
    /// 어두운 모듈이 true인 정사각 격자. 사방에 밝은 여백(quiet zone)이 붙어 나온다.
    ///
    /// 필터가 붙여주는 여백 폭은 보장된 값이 아니라서, 흰 테두리를 전부 깎아낸 뒤
    /// 우리가 다시 채운다. 규격은 4모듈을 요구하지만 화면에 그리는 코드라 2로 줄였다 —
    /// 전체 크기의 22%가 순수 여백이었다. 스캔이 불안정하면 여기부터 4로 되돌릴 것.
    static let quietZoneDefault = 2

    static func modules(for text: String, quietZone: Int = quietZoneDefault) -> [[Bool]]? {
        guard let data = text.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        // L(7% 복원). 오염·훼손을 견뎌야 하는 인쇄물이라면 M 이상이 맞지만 화면 렌더는
        // 손상될 일이 없다. 같은 주소가 더 낮은 버전에 담겨 코드가 작아진다.
        filter.setValue("L", forKey: "inputCorrectionLevel")
        guard let image = filter.outputImage else { return nil }

        let w = Int(image.extent.width.rounded())
        let h = Int(image.extent.height.rounded())
        // 1픽셀 = 1모듈. 400을 넘으면 페이로드가 터미널에 그릴 수 없을 만큼 길다는 뜻.
        guard w > 0, h > 0, w <= 400, h <= 400 else { return nil }

        // GPU가 없는 환경(SSH·헤드리스)에서도 돌도록 소프트웨어 렌더러로 고정한다.
        guard let cg = CIContext(options: [.useSoftwareRenderer: true])
            .createCGImage(image, from: image.extent) else { return nil }

        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: w * h)
        defer { buf.deallocate() }
        buf.initialize(repeating: 255, count: w * h)
        guard let ctx = CGContext(data: buf, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))

        // CoreGraphics는 원점이 좌하단이라 행을 뒤집어 읽는다 (QR은 방향이 있다).
        var dark = [[Bool]](repeating: [Bool](repeating: false, count: w), count: h)
        for r in 0..<h {
            let base = (h - 1 - r) * w
            for c in 0..<w where buf[base + c] < 128 { dark[r][c] = true }
        }

        return pad(trim(dark), by: quietZone)
    }

    /// 흰 테두리를 깎아 코드 본체만 남긴다.
    private static func trim(_ dark: [[Bool]]) -> [[Bool]] {
        var top = 0, bottom = dark.count - 1
        while top <= bottom, !dark[top].contains(true) { top += 1 }
        while bottom > top, !dark[bottom].contains(true) { bottom -= 1 }
        guard top <= bottom else { return dark }

        let width = dark[0].count
        var left = 0, right = width - 1
        while left <= right, !(top...bottom).contains(where: { dark[$0][left] }) { left += 1 }
        while right > left, !(top...bottom).contains(where: { dark[$0][right] }) { right -= 1 }

        return (top...bottom).map { Array(dark[$0][left...right]) }
    }

    /// 사방에 밝은 여백을 두른다. 세로 모듈 수는 짝수로 맞춘다 —
    /// 하프블록(▀) 한 줄이 모듈 두 행을 담당하므로 홀수면 마지막 줄이 반쪽이 된다.
    private static func pad(_ dark: [[Bool]], by quiet: Int) -> [[Bool]] {
        guard let width = dark.first?.count else { return dark }
        let padded = width + quiet * 2
        let blank = [Bool](repeating: false, count: padded)
        var out = [[Bool]](repeating: blank, count: quiet)
        for row in dark {
            out.append([Bool](repeating: false, count: quiet) + row + [Bool](repeating: false, count: quiet))
        }
        out.append(contentsOf: [[Bool]](repeating: blank, count: quiet))
        if out.count % 2 != 0 { out.append(blank) }
        return out
    }
}
