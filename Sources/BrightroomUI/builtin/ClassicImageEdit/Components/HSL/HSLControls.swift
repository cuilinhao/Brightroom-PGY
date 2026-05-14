import UIKit

/// 底部那一排里单个颜色通道按钮：外面一圈是通道代表色，选中会加粗白边、稍微放大，底下小圆点提示当前选中的是谁。
final class HSLChannelButton: UIControl {
    let channel: HSLChannel
    private let ringView = UIView()
    private let innerView = UIView()
    private let dotView = UIView()

    /// 圆点选中态切换时，自动刷新白边/缩放（外层 `EditViewController` 只改这个 bool）。
    override var isSelected: Bool {
        didSet { updateSelection() }
    }

    /// 按传入的通道配色，搭好圆环、内圈、底下小点三层视图。
    init(channel: HSLChannel) {
        self.channel = channel
        super.init(frame: .zero)
        setupUI()
    }

    /// XIB/Storyboard 不用，走到这算接错。
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 把圆环、内圆、小点的约束一次性钉死，顺便按当前选中态刷新外观。
    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        //外圆
        ringView.translatesAutoresizingMaskIntoConstraints = false
        ringView.backgroundColor = channel.uiColor
        ringView.layer.cornerRadius = 10
        ringView.layer.borderWidth = 0
        ringView.layer.borderColor = UIColor.white.cgColor
        ringView.isUserInteractionEnabled = false
        addSubview(ringView)

        // 内圆
        innerView.translatesAutoresizingMaskIntoConstraints = false
        innerView.backgroundColor = UIColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 1)
        innerView.layer.cornerRadius = 15 / 2
        innerView.isUserInteractionEnabled = false
        ringView.addSubview(innerView)

        dotView.translatesAutoresizingMaskIntoConstraints = false
        dotView.backgroundColor = UIColor.white.withAlphaComponent(0.85)
        dotView.layer.cornerRadius = 3
        dotView.isUserInteractionEnabled = false
        addSubview(dotView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 52 - 15),
            heightAnchor.constraint(equalToConstant: 62 - 15),

            ringView.topAnchor.constraint(equalTo: topAnchor),
            ringView.centerXAnchor.constraint(equalTo: centerXAnchor),
            ringView.widthAnchor.constraint(equalToConstant: 20),
            ringView.heightAnchor.constraint(equalToConstant: 20),

            innerView.centerXAnchor.constraint(equalTo: ringView.centerXAnchor),
            innerView.centerYAnchor.constraint(equalTo: ringView.centerYAnchor),
            innerView.widthAnchor.constraint(equalToConstant: 10 + 5),
            innerView.heightAnchor.constraint(equalToConstant: 10 + 5),

            dotView.topAnchor.constraint(equalTo: ringView.bottomAnchor, constant: 14),
            dotView.centerXAnchor.constraint(equalTo: centerXAnchor),
            dotView.widthAnchor.constraint(equalToConstant: 6),
            dotView.heightAnchor.constraint(equalToConstant: 6)
        ])

        updateSelection()
    }

    /// 选中：白边加粗、内圈染色、略微放大；没选中：暗底、缩回去。
    private func updateSelection() {
        ringView.layer.borderWidth = isSelected ? 4 : 0
        innerView.backgroundColor = isSelected ? channel.uiColor : UIColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 1)
        dotView.alpha = isSelected ? 1 : 0.85
        transform = isSelected ? CGAffineTransform(scaleX: 1.08, y: 1.08) : .identity
    }
}

/// 自定义滑杆：轨道是一条渐变条，中间有个刻度表示 0，拖圆疙瘩改数值，手势结束后会往上层发 `.valueChanged`。
///
 //MARK: -  滑竿
final class HSLGradientSlider: UIControl {
    /// 滑杆拖到最左边时的取值（和 `maximumValue` 一起决定刻度的映射范围）。
    var minimumValue: Float = -100 {
        didSet { updateThumbPosition() }
    }

    /// 滑杆拖到最右边时的取值。
    var maximumValue: Float = 100 {
        didSet { updateThumbPosition() }
    }

    /// 当前数值；会自动夹在 min/max 之间，一变就挪拇指。
    var value: Float = 0 {
        didSet {
            value = min(max(value, minimumValue), maximumValue)
            updateThumbPosition()
        }
    }

    /// 轨道里面渐变的颜色数组，编辑页按当前通道换一套配色。
    var gradientColors: [UIColor] = [.darkGray, .lightGray] {
        didSet { gradientLayer.colors = gradientColors.map { $0.cgColor } }
    }

    private let trackView = UIView()
    private let gradientLayer = CAGradientLayer()
    private let centerTick = UIView()
    
    /// 滑竿的圈圈
    private let thumbView = UIView()
    
   
    private let thumbInnerView = UIView()
    private let trackHeight: CGFloat = 4
    private let thumbSize: CGFloat = 10 + 5

    /// 纯代码创建时用，里面会 `setupUI`。
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    /// 同上，接口摆着用。
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 搭轨道渐变层、中间零点、`thumb` 圆钮，并加 Auto Layout。
    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear

        trackView.translatesAutoresizingMaskIntoConstraints = false
        trackView.backgroundColor = .clear
        trackView.layer.cornerRadius = trackHeight / 2
        trackView.layer.masksToBounds = true
        addSubview(trackView)

        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        gradientLayer.colors = gradientColors.map { $0.cgColor }
        trackView.layer.addSublayer(gradientLayer)

        centerTick.translatesAutoresizingMaskIntoConstraints = false
        centerTick.backgroundColor = UIColor.white.withAlphaComponent(0.18)
        centerTick.layer.cornerRadius = 4
        addSubview(centerTick)
        
        /// 设置滑竿上的圆
        thumbView.translatesAutoresizingMaskIntoConstraints = true
        thumbView.bounds = CGRect(x: 0, y: 0, width: thumbSize, height: thumbSize)
        thumbView.backgroundColor = UIColor(red: 0.28, green: 0.28, blue: 0.28, alpha: 1)
        thumbView.layer.cornerRadius = thumbSize / 2
        thumbView.layer.borderWidth = 3
        thumbView.layer.borderColor = UIColor(red: 0.62, green: 0.62, blue: 0.62, alpha: 1).cgColor
        thumbView.isUserInteractionEnabled = false
        addSubview(thumbView)

        thumbInnerView.translatesAutoresizingMaskIntoConstraints = false
        thumbInnerView.backgroundColor = UIColor(red: 0.33, green: 0.33, blue: 0.33, alpha: 1)
        thumbInnerView.layer.cornerRadius = 5
        thumbView.addSubview(thumbInnerView)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 42-20),

            trackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            trackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            trackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            trackView.heightAnchor.constraint(equalToConstant: trackHeight),

            centerTick.centerXAnchor.constraint(equalTo: centerXAnchor),
            centerTick.centerYAnchor.constraint(equalTo: centerYAnchor),
            centerTick.widthAnchor.constraint(equalToConstant: 8),
            centerTick.heightAnchor.constraint(equalToConstant: 8),
            
            thumbInnerView.centerXAnchor.constraint(equalTo: thumbView.centerXAnchor),
            thumbInnerView.centerYAnchor.constraint(equalTo: thumbView.centerYAnchor),
            thumbInnerView.widthAnchor.constraint(equalToConstant: 10),
            thumbInnerView.heightAnchor.constraint(equalToConstant: 10)
        ])
    }

    /// 布局变了就拉伸渐变层宽度，并让拇指跟着当前 `value` 挪位置。
    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = trackView.bounds
        updateThumbPosition()
    }

    /// 按最小最大值把 `value` 映射成横向比例，更新拇指中心点坐标。
    private func updateThumbPosition() {
        guard bounds.width > 0 else { return }
        let progress = CGFloat((value - minimumValue) / (maximumValue - minimumValue))
        let x = progress * bounds.width
        thumbView.center = CGPoint(x: x, y: bounds.midY)
    }

    /// 手指在控件上的横坐标换算成滑杆数值，夹在 min/max 之间，并广播给上层。
    private func updateValue(with touch: UITouch) {
        let location = touch.location(in: self)
        let progress = min(max(location.x / max(bounds.width, 1), 0), 1)
        value = minimumValue + Float(progress) * (maximumValue - minimumValue)
        sendActions(for: .valueChanged)
    }

    /// 手指刚按下：立刻把拇指吃到触点位置，好实现「点轨道直接跳」。
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        updateValue(with: touch)
        return true
    }

    /// 手指拖着：持续跟随更新数值。
    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        updateValue(with: touch)
        return true
    }
}

/// 懒得塞图片资源了，就用代码画了一批简单图标（叉、加号、准星、禁止、波形），给按钮当图像用。
final class IconFactory {
    /// 画一个「X」，给取消关闭用。
    static func xmark(size: CGFloat = 34, color: UIColor = .white) -> UIImage {
        draw(size: CGSize(width: size, height: size)) { rect in
            let path = UIBezierPath()
            path.move(to: CGPoint(x: rect.minX + 7, y: rect.minY + 7))
            path.addLine(to: CGPoint(x: rect.maxX - 7, y: rect.maxY - 7))
            path.move(to: CGPoint(x: rect.maxX - 7, y: rect.minY + 7))
            path.addLine(to: CGPoint(x: rect.minX + 7, y: rect.maxY - 7))
            color.setStroke()
            path.lineWidth = 3
            path.lineCapStyle = .round
            path.stroke()
        }
    }

    /// 画一个「+」，给新建预设用。
    static func plus(size: CGFloat = 26, color: UIColor = .white) -> UIImage {
        draw(size: CGSize(width: size, height: size)) { rect in
            let path = UIBezierPath()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY + 2))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - 2))
            path.move(to: CGPoint(x: rect.minX + 2, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX - 2, y: rect.midY))
            color.setStroke()
            path.lineWidth = 3
            path.lineCapStyle = .round
            path.stroke()
        }
    }

    /// 准星/瞄准器样式，表示「只重置当前通道」。
    static func target(size: CGFloat = 38, color: UIColor = UIColor.white.withAlphaComponent(0.92)) -> UIImage {
        draw(size: CGSize(width: size, height: size)) { rect in
            let center = CGPoint(x: rect.midX, y: rect.midY)
            color.setStroke()

            let circle = UIBezierPath(arcCenter: center, radius: 10, startAngle: 0, endAngle: CGFloat.pi * 2, clockwise: true)
            circle.lineWidth = 2
            circle.stroke()

            let path = UIBezierPath()
            path.move(to: CGPoint(x: center.x, y: rect.minY + 4))
            path.addLine(to: CGPoint(x: center.x, y: center.y - 13))
            path.move(to: CGPoint(x: center.x, y: center.y + 13))
            path.addLine(to: CGPoint(x: center.x, y: rect.maxY - 4))
            path.move(to: CGPoint(x: rect.minX + 4, y: center.y))
            path.addLine(to: CGPoint(x: center.x - 13, y: center.y))
            path.move(to: CGPoint(x: center.x + 13, y: center.y))
            path.addLine(to: CGPoint(x: rect.maxX - 4, y: center.y))
            path.lineWidth = 2
            path.lineCapStyle = .round
            path.stroke()
        }
    }

    /// 圆加斜杠，表示「全部通道清零」。
    static func prohibited(size: CGFloat = 34, color: UIColor = .white) -> UIImage {
        draw(size: CGSize(width: size, height: size)) { rect in
            color.setStroke()
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let circle = UIBezierPath(arcCenter: center, radius: size * 0.38, startAngle: 0, endAngle: CGFloat.pi * 2, clockwise: true)
            circle.lineWidth = 3
            circle.stroke()

            let slash = UIBezierPath()
            slash.move(to: CGPoint(x: rect.minX + 8, y: rect.minY + 8))
            slash.addLine(to: CGPoint(x: rect.maxX - 8, y: rect.maxY - 8))
            slash.lineWidth = 3
            slash.lineCapStyle = .round
            slash.stroke()
        }
    }

    /// 几根竖条假装波形，占位直方图入口。
    static func waveform(size: CGFloat = 40, color: UIColor = .white) -> UIImage {
        draw(size: CGSize(width: size, height: size)) { rect in
            let bars: [CGFloat] = [10, 17, 24, 30, 22, 28, 15]
            let spacing: CGFloat = 4
            let width: CGFloat = 3
            let total = CGFloat(bars.count) * width + CGFloat(bars.count - 1) * spacing
            var x = rect.midX - total / 2
            color.setStroke()
            for h in bars {
                let path = UIBezierPath()
                path.move(to: CGPoint(x: x, y: rect.midY - h / 2))
                path.addLine(to: CGPoint(x: x, y: rect.midY + h / 2))
                path.lineWidth = width
                path.lineCapStyle = .round
                path.stroke()
                x += width + spacing
            }
        }
    }

    /// 公用：`UIGraphicsImageRenderer` 开一块画布，闭包里画完返回 `UIImage`。
    private static func draw(size: CGSize, actions: (CGRect) -> Void) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            actions(CGRect(origin: .zero, size: size))
        }
    }
}
