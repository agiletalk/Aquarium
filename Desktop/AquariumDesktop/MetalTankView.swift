import AppKit
import AquariumCore
import CoreText
import Metal
import QuartzCore

/// GPU 렌더러 — 글리프는 처음 볼 때 한 번만 아틀라스에 래스터화하고, 매 tick CPU는
/// 빈칸이 아닌 셀 목록(셀당 8바이트)만 만들어 넘긴다. 픽셀은 GPU가 칠한다.
///
/// CPU 렌더러(TankView)는 41MB 버퍼 곳곳의 페이지에 처음 닿는 비용이 바닥이었다.
/// 여기서는 CPU가 화면 버퍼를 만지지 않는다.
///
/// 색: 드로어블은 bgra8Unorm(sRGB 태그)이고 블렌딩도 인코딩된 값 그대로 한다 — CPU 경로의
/// CG가 sRGB 비트맵에서 하는 것과 같은 수식이라 결과가 같다(±1 반올림).
final class MetalTankView: NSView, TankRenderer {
    let cells: CellFrame
    weak var world: World?
    var panel: PanelContent?

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let metalLayer = CAMetalLayer()
    private let palette: MTLBuffer
    private var atlas: GlyphAtlas?
    private var scale: CGFloat = 0

    /// 셀 목록 링 버퍼 — GPU가 아직 읽는 버퍼를 덮어쓰지 않게 세 장을 돌린다.
    private var instanceBuffers: [MTLBuffer] = []
    private var ring = 0
    private let inFlight = DispatchSemaphore(value: 3)
    /// 마지막으로 그린 셀 — 바뀐 게 없으면 GPU를 깨우지 않는다.
    private var lastDrawn: [DrawnCell] = []

    private struct Instance {
        var col: UInt16
        var row: UInt16
        var slot: UInt16
        var color: UInt8
        var flags: UInt8          // bit0 2칸 폭, bit1 컬러 글리프(이모지)
    }

    private struct Uniforms {
        var viewport: SIMD2<Float>
        var cellSize: SIMD2<Float>
        var slotSize: SIMD2<Float>
        var slotsPerRow: UInt32
        var pad: UInt32 = 0
    }

    /// Metal을 쓸 수 없으면 nil — 부르는 쪽이 CPU 렌더러로 떨어진다.
    init?(visibleRect: CGRect, metrics: CellMetrics) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let pipeline = Self.makePipeline(device),
              let palette = device.makeBuffer(length: 256 * MemoryLayout<SIMD4<Float>>.stride,
                                              options: .storageModeShared) else { return nil }
        let grid = Self.gridFrame(in: visibleRect, metrics: metrics)
        cells = CellFrame(cols: grid.cols, rows: grid.rows, metrics: metrics)
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
        self.palette = palette
        super.init(frame: grid.frame)

        let colors = palette.contents().assumingMemoryBound(to: SIMD4<Float>.self)
        for i in 0..<256 { colors[i] = Self.components(Palette.colors[i]) }

        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        metalLayer.isOpaque = true
        metalLayer.maximumDrawableCount = 2      // 전체 화면 드로어블 한 장이 41MB — 두 장만
        metalLayer.framebufferOnly = !Probe.enabled // Probe 검증은 드로어블을 읽어야 한다
        metalLayer.backgroundColor = Palette.background
        metalLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer = metalLayer   // wantsLayer보다 먼저 — layer-hosting
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isOpaque: Bool { true }

    /// 화면 배율에 맞춰 드로어블·아틀라스를 만든다. 창에 붙은 뒤에야 배율을 안다.
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        guard scale != self.scale else { return }
        self.scale = scale
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        atlas = GlyphAtlas(device: device, cells: cells, scale: scale)
        lastDrawn = []
        render()
    }

    func refresh() {
        guard let world else { return }
        let tf = Probe.now()
        cells.update(from: world, panel: panel)
        Probe.add("compose+flatten", since: tf)
        render()
    }

    private func render() {
        guard let atlas, cells.cells != lastDrawn else { return }
        let tb = Probe.now()
        var instances: [Instance] = []
        instances.reserveCapacity(4096)
        let cols = cells.cols
        for (i, cell) in cells.cells.enumerated() where !cell.isBlank {
            guard let slot = atlas.slot(for: cell) else { continue }
            instances.append(Instance(col: UInt16(i % cols), row: UInt16(i / cols), slot: slot.index,
                                      color: cell.color,
                                      flags: (cell.wide ? 1 : 0) | (slot.isColor ? 2 : 0)))
        }
        Probe.add("instances", since: tb, count: instances.count)

        let te = Probe.now()
        inFlight.wait()
        // 드로어블·커맨드 버퍼를 먼저 확보한다. 못 받으면 아무 상태도 바꾸지 않는다 — 안 그린 프레임을
        // "그렸다"고 기록하면 정적인 화면이 낡은 채로 남고, 링 버퍼만 돌면 GPU가 읽는 버퍼를 덮을 수 있다.
        guard let drawable = metalLayer.nextDrawable(),
              let commands = queue.makeCommandBuffer() else { inFlight.signal(); return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        let bg = Self.components(Palette.background)
        pass.colorAttachments[0].clearColor = MTLClearColor(red: Double(bg.x), green: Double(bg.y),
                                                            blue: Double(bg.z), alpha: 1)
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { inFlight.signal(); return }
        let buffer = instanceBuffer(capacity: instances.count)
        if !instances.isEmpty {
            instances.withUnsafeBytes { buffer.contents().copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
        }
        lastDrawn = cells.cells
        var uniforms = Uniforms(
            viewport: SIMD2(Float(drawable.texture.width), Float(drawable.texture.height)),
            cellSize: SIMD2(Float(cells.metrics.width * scale), Float(cells.metrics.height * scale)),
            slotSize: SIMD2(Float(atlas.slotWidth), Float(atlas.slotHeight)),
            slotsPerRow: UInt32(atlas.slotsPerRow))
        if !instances.isEmpty {
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.setFragmentTexture(atlas.texture, index: 0)
            encoder.setFragmentBuffer(palette, offset: 0, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4,
                                   instanceCount: instances.count)
        }
        encoder.endEncoding()
        commands.present(drawable)
        let semaphore = inFlight
        commands.addCompletedHandler { _ in semaphore.signal() }
        commands.commit()
        Probe.add("encode+commit", since: te)

        if Probe.enabled {
            Probe.verifyTick { self.verify(commands, drawable.texture) }
        }
    }

    private func instanceBuffer(capacity: Int) -> MTLBuffer {
        let needed = max(1, capacity) * MemoryLayout<Instance>.stride
        if instanceBuffers.isEmpty {
            instanceBuffers = (0..<3).compactMap { _ in device.makeBuffer(length: 64 * 1024, options: .storageModeShared) }
        }
        if instanceBuffers[ring].length < needed,
           let bigger = device.makeBuffer(length: needed * 2, options: .storageModeShared) {
            instanceBuffers[ring] = bigger
        }
        let buffer = instanceBuffers[ring]
        ring = (ring + 1) % instanceBuffers.count
        return buffer
    }

    /// Probe 전용: GPU 결과를 CPU 경로로 처음부터 그린 그림과 비교한다.
    /// 래스터 경로가 달라 안티앨리어싱 가장자리에서 ±1 정도는 날 수 있다 — 최대 차이를 함께 본다.
    private func verify(_ commands: MTLCommandBuffer, _ texture: MTLTexture) -> (mismatched: Int, total: Int) {
        commands.waitUntilCompleted()
        guard let reference = cells.referenceImage(of: lastDrawn, scale: scale) else { return (0, 0) }
        let width = texture.width, height = texture.height
        var pixels = [UInt32](repeating: 0, count: width * height)
        pixels.withUnsafeMutableBytes {
            texture.getBytes($0.baseAddress!, bytesPerRow: width * 4,
                             from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        Probe.cellPixelWidth = Double(cells.metrics.width * scale)
        Probe.cellPixelHeight = Int((cells.metrics.height * scale).rounded())
        Probe.bigCells = []
        let result = reference.compare(bgra: pixels, width: width, height: height)
        let where_ = Probe.bigCells.prefix(8).map { key -> String in
            let cell = lastDrawn[key.row * cells.cols + key.col]
            return "(\(key.row),\(key.col)) '\(cells.character(of: cell.code))' wide=\(cell.wide)"
        }
        Probe.log("  GPU vs CPU 최대 채널 차이 \(result.maxDiff), 2 이상 차이 \(result.bigDiffs)px · 셀 \(where_)")
        return (result.mismatched, width * height)
    }

    private static func components(_ color: CGColor) -> SIMD4<Float> {
        let c = color.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)?
            .components ?? [0, 0, 0, 1]
        return SIMD4(Float(c[0]), Float(c[1]), Float(c[2]), 1)
    }

    /// 렌더러를 바꾸거나 테마·모니터를 바꿀 때마다 뷰를 새로 만드는데, 셰이더 컴파일은 수십 ms라 한 번만 한다.
    private static var cachedPipeline: (device: ObjectIdentifier, state: MTLRenderPipelineState)?

    private static func makePipeline(_ device: MTLDevice) -> MTLRenderPipelineState? {
        if let cached = cachedPipeline, cached.device == ObjectIdentifier(device) { return cached.state }
        guard let state = compilePipeline(device) else { return nil }
        cachedPipeline = (ObjectIdentifier(device), state)
        return state
    }

    private static func compilePipeline(_ device: MTLDevice) -> MTLRenderPipelineState? {
        guard let library = try? device.makeLibrary(source: shaderSource, options: nil) else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "tankVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "tankFragment")
        let color = descriptor.colorAttachments[0]!
        color.pixelFormat = .bgra8Unorm
        // 미리 곱한 알파: out = src + dst × (1 − srcA)
        color.isBlendingEnabled = true
        color.sourceRGBBlendFactor = .one
        color.destinationRGBBlendFactor = .oneMinusSourceAlpha
        color.sourceAlphaBlendFactor = .one
        color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    /// 실행 중에 컴파일한다 — 서드파티도 별도 빌드 단계도 없다.
    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Instance { ushort col; ushort row; ushort slot; uchar color; uchar flags; };
    struct Uniforms { float2 viewport; float2 cellSize; float2 slotSize; uint slotsPerRow; uint pad; };
    struct VOut {
        float4 position [[position]];
        float2 quadOrigin [[flat]];
        float2 slotOrigin [[flat]];
        uint color [[flat]];
        uint flags [[flat]];
    };

    vertex VOut tankVertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                           const device Instance* instances [[buffer(0)]],
                           constant Uniforms& u [[buffer(1)]]) {
        Instance i = instances[iid];
        float span = (i.flags & 1) ? 2.0 : 1.0;
        float2 corner = float2(vid & 1, vid >> 1);
        float2 origin = float2(i.col, i.row) * u.cellSize;            // 픽셀, 좌상단 원점
        float2 p = origin + corner * float2(u.cellSize.x * span, u.cellSize.y);
        VOut o;
        o.position = float4(p.x / u.viewport.x * 2.0 - 1.0, 1.0 - p.y / u.viewport.y * 2.0, 0.0, 1.0);
        o.quadOrigin = origin;
        o.slotOrigin = float2(i.slot % u.slotsPerRow, i.slot / u.slotsPerRow) * u.slotSize;
        o.color = i.color;
        o.flags = i.flags;
        return o;
    }

    fragment float4 tankFragment(VOut in [[stage_in]],
                                 texture2d<float, access::read> atlas [[texture(0)]],
                                 constant float4* palette [[buffer(0)]]) {
        uint2 local = uint2(floor(in.position.xy - in.quadOrigin));
        float4 t = atlas.read(uint2(in.slotOrigin) + local);
        if (in.flags & 2) { return t; }                                // 컬러 이모지 (미리 곱한 알파)
        float4 c = palette[in.color];
        return float4(c.rgb * t.a, t.a);
    }
    """
}

/// 글리프 아틀라스 — 셀 크기 슬롯에 글자를 처음 볼 때 한 번 래스터화한다(2칸 글자는 슬롯 2개).
/// 일반 글자는 흰색 커버리지로 넣고 셰이더가 팔레트 색을 곱한다. 컬러 이모지는 제 색 그대로.
final class GlyphAtlas {
    let texture: MTLTexture
    let slotWidth: Int
    let slotHeight: Int
    let slotsPerRow: Int
    private let slotRows: Int
    private let cells: CellFrame
    private let scale: CGFloat
    private var next = 0
    private var slots: [Key: Slot] = [:]

    struct Slot {
        let index: UInt16
        let isColor: Bool
    }

    private struct Key: Hashable {
        let code: UInt32
        let wide: Bool
    }

    init?(device: MTLDevice, cells: CellFrame, scale: CGFloat, size: Int = 1024) {
        slotWidth = Int((cells.metrics.width * scale).rounded())
        slotHeight = Int((cells.metrics.height * scale).rounded())
        slotsPerRow = size / slotWidth
        slotRows = size / slotHeight
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
                                                                  width: size, height: size, mipmapped: false)
        descriptor.usage = .shaderRead
        descriptor.storageMode = device.hasUnifiedMemory ? .shared : .managed
        guard slotsPerRow > 1, slotRows > 0, let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        self.texture = texture
        self.cells = cells
        self.scale = scale
    }

    /// 아틀라스가 꽉 차면 nil — 그 글자는 그리지 않는다(어항에 쓰는 글자는 수십 개뿐이다).
    func slot(for cell: DrawnCell) -> Slot? {
        let key = Key(code: cell.code, wide: cell.wide)
        if let hit = slots[key] { return hit }
        let span = cell.wide ? 2 : 1
        // 2칸 슬롯은 한 줄 안에 붙어 있어야 한다.
        if next % slotsPerRow + span > slotsPerRow { next += slotsPerRow - next % slotsPerRow }
        guard next + span <= slotsPerRow * slotRows else { return nil }
        let index = next
        next += span
        let isColor = rasterize(cell, at: index, span: span)
        let slot = Slot(index: UInt16(index), isColor: isColor)
        slots[key] = slot
        return slot
    }

    /// CPU 경로와 같은 글리프 원점·폰트로 그린다. 슬롯이 곧 클립(셀 행 띠)이다.
    private func rasterize(_ cell: DrawnCell, at index: Int, span: Int) -> Bool {
        let glyph = cells.glyph(for: cell)
        let isColor = CTFontGetSymbolicTraits(glyph.font).contains(.traitColorGlyphs)
        let width = slotWidth * span, height = slotHeight
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return }
            context.scaleBy(x: scale, y: scale)
            context.setShouldSmoothFonts(false)
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            var g = glyph.glyph
            var position = cells.glyphOffset(for: cell, glyph)
            CTFontDrawGlyphs(glyph.font, &g, &position, 1, context)
        }
        let x = (index % slotsPerRow) * slotWidth, y = (index / slotsPerRow) * slotHeight
        texture.replace(region: MTLRegionMake2D(x, y, width, height), mipmapLevel: 0,
                        withBytes: bytes, bytesPerRow: width * 4)
        return isColor
    }
}
