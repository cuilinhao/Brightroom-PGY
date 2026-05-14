import UIKit
import Photos

/// 调色主界面：上面大图预览，下面选通道、拖滑杆。预览用缩略图 + 小立方体 LUT 跑得动；点「确定」再用原图 + 大立方体导出高清。
final class EditViewController: UIViewController {
    /// 导出「确定」时用的全尺寸已转正原图， LUT 用 64 维算最终成品。
    private let originalImage: UIImage
    /// 滑杆实时预览用的缩小图，配合 32 维立方体，降低延迟。
    private let previewSourceImage: UIImage

    /// 八个颜色通道各自当前拧了多少（色相 / 饱和 / 亮度），内存里真正的编辑状态。
    private var adjustments: [HSLChannel: HSLAdjustment] = Dictionary(
        uniqueKeysWithValues: HSLChannel.allCases.map { ($0, .zero) }
    )

    /// 底部圆点里正对用户的那一个通道，滑杆改的就是它的参数。
    private var selectedChannel: HSLChannel = .yellow
    /// 预览渲染排队：数字越大越「新」，旧 `DispatchWorkItem` 算完要核对版本，防止盖错图。
    private var renderVersion = 0
    /// 还在排队/延迟执行里的那一次预览任务，新滑动来时先 cancel 掉。
    private var pendingRenderWorkItem: DispatchWorkItem?
    /// 单开一条后台队列算 LUT + 渲染，别卡主线程。
    private let renderQueue = DispatchQueue(label: "hsl.plus.render.queue", qos: .userInitiated)

    /// 上面一整块专放预览图的容器（背景色跟整体黑底一致）。
    private let imageContainerView = UIView()
    /// 真正显示照片（预览或导出前效果）的视图。
    private let imageView = UIImageView()
    /// 屏幕下方深色操作区：标题、色点、滑杆、取消/确定都搁在这上面。
    private let bottomPanel = UIView()

    /// 预览图右下角「新建预设」，把当前 HSL 参数 JSON 存本地。
    private let newPresetButton = UIButton(type: .system)
    /// 预览图左下波形占位钮，目前只弹出说明文案。
    private let waveformButton = UIButton(type: .system)

    /// 底部面板左上角「HSL+」标题字。
    private let hslTitleLabel = UILabel()
    /// 中间准星：只重置当前选中通道的三项滑杆。
    private let targetButton = UIButton(type: .system)
    /// 右边禁止符：八个通道一次全部清零。
    private let prohibitButton = UIButton(type: .system)
    /// 横排容纳八个颜色通道圆点的栈视图。
    private let colorStackView = UIStackView()
    /// 与 `HSLChannel.allCases` 一一对应的八个可点圆钮。
    private var channelButtons: [HSLChannelButton] = []

    /// 「色相」二字左边标签。
    private let hueTitleLabel = UILabel()
    /// 色相滑杆右边当前整数值。
    private let hueValueLabel = UILabel()
    /// 色相条：范围 ±180，颜色是一条彩虹渐变提示。
    private let hueSlider = HSLGradientSlider()

    /// 「饱和度」左边标签。
    private let saturationTitleLabel = UILabel()
    /// 饱和度滑杆右边当前整数值。
    private let saturationValueLabel = UILabel()
    /// 饱和度条：±100，轨道会跟当前通道色挂钩。
    private let saturationSlider = HSLGradientSlider()

    /// 「亮度」左边标签。
    private let lightnessTitleLabel = UILabel()
    /// 亮度滑杆右边当前整数值。
    private let lightnessValueLabel = UILabel()
    /// 亮度条：±100，暗→亮渐变跟当前通道色走。
    private let lightnessSlider = HSLGradientSlider()

    /// 左下角叉：放弃编辑返回上一页。
    private let cancelButton = UIButton(type: .system)
    /// 右下角黄底「确定」：用原图算高清再弹是否存相册。
    private let confirmButton = UIButton(type: .system)

    /// 进来时把原图转正，另外再生成一张最长边 1200 的预览用图，省得一上来就算全尺寸卡顿。
    init(originalImage: UIImage) {
        self.originalImage = originalImage.normalizedUpImage()
        self.previewSourceImage = originalImage.normalizedUpImage().scaledImage(maxSide: 1200)
        super.init(nibName: nil, bundle: nil)
    }

    /// Storyboard 不用，留着只是为了满足 `UIViewController` 协议；真走到这行就说明接错入口了。
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 不隐藏状态栏，跟系统默认一致。
    override var prefersStatusBarHidden: Bool { false }
    /// 状态栏文字用浅色，衬深色界面。
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    //MARK: - Life Cycle
    /// 页面第一次加载：铺好 UI、默认选中黄通道、滑杆数字和渐变一起刷新好。
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.08, green: 0.08, blue: 0.085, alpha: 1)
        imageView.image = previewSourceImage
        setupUI()
        updateChannelSelectionUI()
        updateSlidersFromSelectedChannel()
        updateSliderGradients()
    }

    /// 编辑页全屏沉浸：把导航栏藏掉，多给图片一点地方。
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    /// 离开编辑页（取消或保存后退）：把导航栏再露出来，首页还能正常显示标题栏。
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    /// 一口气把下面几块 UI 拼完：大图区、浮层按钮、标题行、八个色点、三根滑杆、底角取消/确定。
    private func setupUI() {
        setupImageArea()
        setupBottomPanel()
        setupOverlayButtons()
        setupTopToolRow()
        setupChannelButtons()
        setupSliders()
        setupBottomActions()
    }

    /// 上面大块放图片，下面深色条是控制面板，用 Auto Layout 把高度钉死。
    private func setupImageArea() {
        imageContainerView.translatesAutoresizingMaskIntoConstraints = false
        imageContainerView.backgroundColor = UIColor(red: 0.08, green: 0.08, blue: 0.085, alpha: 1)
        view.addSubview(imageContainerView)

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageContainerView.addSubview(imageView)

        bottomPanel.translatesAutoresizingMaskIntoConstraints = false
        bottomPanel.backgroundColor = UIColor(red: 0.105, green: 0.105, blue: 0.11, alpha: 1)
        view.addSubview(bottomPanel)

        let panelHeight: CGFloat = 386
        NSLayoutConstraint.activate([
            imageContainerView.topAnchor.constraint(equalTo: view.topAnchor),
            imageContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageContainerView.bottomAnchor.constraint(equalTo: bottomPanel.topAnchor),

            imageView.topAnchor.constraint(equalTo: imageContainerView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: imageContainerView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: imageContainerView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: imageContainerView.bottomAnchor),

            bottomPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomPanel.heightAnchor.constraint(equalToConstant: panelHeight)
        ])
    }

    /// 图片上的两个圆钮：波形提示、新建预设，叠在预览区左下/右下。
    private func setupOverlayButtons() {
        // 与「新建预设一起」的按钮
        waveformButton.translatesAutoresizingMaskIntoConstraints = false
        waveformButton.backgroundColor = UIColor.black.withAlphaComponent(0.42)
        waveformButton.layer.cornerRadius = 15
        waveformButton.layer.masksToBounds = true
        waveformButton.setImage(IconFactory.waveform(size: 14), for: .normal)
        waveformButton.tintColor = .white
        waveformButton.addTarget(self, action: #selector(showHistogramHint), for: .touchUpInside)
        imageContainerView.addSubview(waveformButton)

        newPresetButton.translatesAutoresizingMaskIntoConstraints = false
        newPresetButton.backgroundColor = UIColor.black.withAlphaComponent(0.42)
        newPresetButton.layer.cornerRadius = 15
        newPresetButton.layer.masksToBounds = true
        newPresetButton.setTitle("  新建预设", for: .normal)
        newPresetButton.setTitleColor(.white, for: .normal)
        newPresetButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        newPresetButton.setImage(IconFactory.plus(size: 12), for: .normal)
        newPresetButton.tintColor = .white
        newPresetButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 22-10, bottom: 0, right: 24-10)
        newPresetButton.addTarget(self, action: #selector(savePreset), for: .touchUpInside)
        imageContainerView.addSubview(newPresetButton)

        NSLayoutConstraint.activate([
            waveformButton.leadingAnchor.constraint(equalTo: imageContainerView.leadingAnchor, constant: 48),
            waveformButton.bottomAnchor.constraint(equalTo: imageContainerView.bottomAnchor, constant: -28),
            waveformButton.widthAnchor.constraint(equalToConstant: 60),
            waveformButton.heightAnchor.constraint(equalToConstant: 30),

            newPresetButton.trailingAnchor.constraint(equalTo: imageContainerView.trailingAnchor, constant: -72),
            newPresetButton.bottomAnchor.constraint(equalTo: imageContainerView.bottomAnchor, constant: -28),
            newPresetButton.heightAnchor.constraint(equalToConstant: 30)
        ])
    }

    /// 占位的：真正布局都在别的方法里，这里原本对应「截图里一整块黑面板」的语义。
    private func setupBottomPanel() {
        // The screenshot has a plain, nearly black editing panel. All controls are added in the following methods.
    }

    /// 面板顶上一行：左边 HSL+ 文案，中间重置当前通道（准星），右边全盘清空（禁止符）。
    private func setupTopToolRow() {
        hslTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        hslTitleLabel.text = "HSL+"
        hslTitleLabel.textColor = .white
        hslTitleLabel.font = .systemFont(ofSize: 14, weight: .regular)
        bottomPanel.addSubview(hslTitleLabel)

        targetButton.translatesAutoresizingMaskIntoConstraints = false
        targetButton.backgroundColor = UIColor(red: 0.15, green: 0.15, blue: 0.16, alpha: 1)
        targetButton.layer.cornerRadius = 15
        targetButton.layer.borderWidth = 1
        targetButton.layer.borderColor = UIColor.white.withAlphaComponent(0.22).cgColor
        targetButton.setImage(IconFactory.target(size: 12), for: .normal)
        targetButton.tintColor = .white
        targetButton.addTarget(self, action: #selector(resetCurrentChannel), for: .touchUpInside)
        bottomPanel.addSubview(targetButton)

        prohibitButton.translatesAutoresizingMaskIntoConstraints = false
        prohibitButton.setImage(IconFactory.prohibited(size: 25), for: .normal)
        prohibitButton.tintColor = .white
        prohibitButton.addTarget(self, action: #selector(resetAllChannels), for: .touchUpInside)
        bottomPanel.addSubview(prohibitButton)

        NSLayoutConstraint.activate([
            hslTitleLabel.leadingAnchor.constraint(equalTo: bottomPanel.leadingAnchor, constant: 18),
            hslTitleLabel.topAnchor.constraint(equalTo: bottomPanel.topAnchor, constant: 15),

            targetButton.centerXAnchor.constraint(equalTo: bottomPanel.centerXAnchor),
            targetButton.topAnchor.constraint(equalTo: bottomPanel.topAnchor, constant: 12),
            targetButton.widthAnchor.constraint(equalToConstant: 30),
            targetButton.heightAnchor.constraint(equalToConstant: 30),

            prohibitButton.trailingAnchor.constraint(equalTo: bottomPanel.trailingAnchor, constant: -58),
            prohibitButton.centerYAnchor.constraint(equalTo: targetButton.centerYAnchor),
            prohibitButton.widthAnchor.constraint(equalToConstant: 30),
            prohibitButton.heightAnchor.constraint(equalToConstant: 30)
        ])
    }

    /// 八个 `HSLChannelButton` 横排塞进栈视图，点哪个就改当前编辑通道。
    private func setupChannelButtons() {
        colorStackView.translatesAutoresizingMaskIntoConstraints = false
        colorStackView.axis = .horizontal
        colorStackView.alignment = .center
        colorStackView.distribution = .equalSpacing
        
        //---
        //colorStackView.distribution = .fillProportionally
        //colorStackView.distribution =  .fill
        
        bottomPanel.addSubview(colorStackView)
        
        for channel in HSLChannel.allCases {
            let button = HSLChannelButton(channel: channel)
            button.addTarget(self, action: #selector(channelButtonTapped(_:)), for: .touchUpInside)
            channelButtons.append(button)
            colorStackView.addArrangedSubview(button)
        }

        NSLayoutConstraint.activate([
            colorStackView.leadingAnchor.constraint(equalTo: bottomPanel.leadingAnchor, constant: 10),
            colorStackView.trailingAnchor.constraint(equalTo: bottomPanel.trailingAnchor, constant: -10),
            //colorStackView.topAnchor.constraint(equalTo: bottomPanel.topAnchor, constant: 93),
            colorStackView.topAnchor.constraint(equalTo: targetButton.bottomAnchor, constant: 15),
            colorStackView.heightAnchor.constraint(equalToConstant: 62)
        ])
    }

    /// 三根自定义渐变滑杆：范围分别是色相 ±180、饱和/亮度 ±100，改动会通知 `sliderChanged`。
    private func setupSliders() {
        // TODO: - TODO 色相
        configureLabel(hueTitleLabel, text: "色相")
        configureValueLabel(hueValueLabel)
        configureLabel(saturationTitleLabel, text: "饱和度")
        configureValueLabel(saturationValueLabel)
        configureLabel(lightnessTitleLabel, text: "亮度")
        configureValueLabel(lightnessValueLabel)

        hueSlider.minimumValue = -180
        hueSlider.maximumValue = 180
        saturationSlider.minimumValue = -100
        saturationSlider.maximumValue = 100
        lightnessSlider.minimumValue = -100
        lightnessSlider.maximumValue = 100

        hueSlider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        saturationSlider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        lightnessSlider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)

        bottomPanel.addSubview(hueTitleLabel)
        bottomPanel.addSubview(hueValueLabel)
        bottomPanel.addSubview(hueSlider)
        bottomPanel.addSubview(saturationTitleLabel)
        bottomPanel.addSubview(saturationValueLabel)
        bottomPanel.addSubview(saturationSlider)
        bottomPanel.addSubview(lightnessTitleLabel)
        bottomPanel.addSubview(lightnessValueLabel)
        bottomPanel.addSubview(lightnessSlider)

        let left: CGFloat = 20
        let right: CGFloat = -20

        NSLayoutConstraint.activate([
            hueTitleLabel.leadingAnchor.constraint(equalTo: bottomPanel.leadingAnchor, constant: left),
            hueTitleLabel.topAnchor.constraint(equalTo: colorStackView.bottomAnchor, constant: 23),
            hueValueLabel.trailingAnchor.constraint(equalTo: bottomPanel.trailingAnchor, constant: right),
            hueValueLabel.centerYAnchor.constraint(equalTo: hueTitleLabel.centerYAnchor),
            
            hueSlider.leadingAnchor.constraint(equalTo: bottomPanel.leadingAnchor, constant: left),
            hueSlider.trailingAnchor.constraint(equalTo: bottomPanel.trailingAnchor, constant: right),
            hueSlider.topAnchor.constraint(equalTo: hueTitleLabel.bottomAnchor, constant: 4),

            saturationTitleLabel.leadingAnchor.constraint(equalTo: bottomPanel.leadingAnchor, constant: left),
            saturationTitleLabel.topAnchor.constraint(equalTo: hueSlider.bottomAnchor, constant: 12),
            saturationValueLabel.trailingAnchor.constraint(equalTo: bottomPanel.trailingAnchor, constant: right),
            saturationValueLabel.centerYAnchor.constraint(equalTo: saturationTitleLabel.centerYAnchor),
            saturationSlider.leadingAnchor.constraint(equalTo: bottomPanel.leadingAnchor, constant: left),
            saturationSlider.trailingAnchor.constraint(equalTo: bottomPanel.trailingAnchor, constant: right),
            saturationSlider.topAnchor.constraint(equalTo: saturationTitleLabel.bottomAnchor, constant: 4),

            lightnessTitleLabel.leadingAnchor.constraint(equalTo: bottomPanel.leadingAnchor, constant: left),
            lightnessTitleLabel.topAnchor.constraint(equalTo: saturationSlider.bottomAnchor, constant: 12),
            lightnessValueLabel.trailingAnchor.constraint(equalTo: bottomPanel.trailingAnchor, constant: right),
            lightnessValueLabel.centerYAnchor.constraint(equalTo: lightnessTitleLabel.centerYAnchor),
            lightnessSlider.leadingAnchor.constraint(equalTo: bottomPanel.leadingAnchor, constant: left),
            lightnessSlider.trailingAnchor.constraint(equalTo: bottomPanel.trailingAnchor, constant: right),
            lightnessSlider.topAnchor.constraint(equalTo: lightnessTitleLabel.bottomAnchor, constant: 4)
        ])
    }

    /// 滑杆左边灰色小标题「色相/饱和度/亮度」的统一样式。
    private func configureLabel(_ label: UILabel, text: String) {
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.textColor = UIColor.white.withAlphaComponent(0.48)
        label.font = .systemFont(ofSize: 10, weight: .medium)
    }

    /// 滑杆右边显示当前数值的标签，固定宽度方便对齐。
    private func configureValueLabel(_ label: UILabel) {
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = UIColor.white.withAlphaComponent(0.18)
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textAlignment = .right
        label.widthAnchor.constraint(equalToConstant: 80).isActive = true
    }

    /// 左下角叉号退出，右下角黄色「确定」走导出保存流程。
    private func setupBottomActions() {
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.setImage(IconFactory.xmark(size: 40), for: .normal)
        cancelButton.tintColor = .white
        cancelButton.addTarget(self, action: #selector(cancelEditing), for: .touchUpInside)
        bottomPanel.addSubview(cancelButton)

        confirmButton.translatesAutoresizingMaskIntoConstraints = false
        confirmButton.setTitle("确定", for: .normal)
        confirmButton.setTitleColor(.black, for: .normal)
        confirmButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)
        confirmButton.backgroundColor = UIColor(red: 1.0, green: 0.82, blue: 0.04, alpha: 1)
        confirmButton.addTarget(self, action: #selector(confirmEditing), for: .touchUpInside)
        confirmButton.layer.cornerRadius = 15
        confirmButton.layer.masksToBounds  = true
        bottomPanel.addSubview(confirmButton)
        
        NSLayoutConstraint.activate([
            // TODO: - TODO cancelButton
            cancelButton.leadingAnchor.constraint(equalTo: bottomPanel.leadingAnchor, constant: 20),
            cancelButton.bottomAnchor.constraint(equalTo: bottomPanel.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            cancelButton.widthAnchor.constraint(equalToConstant: 24),
            cancelButton.heightAnchor.constraint(equalToConstant: 24),

            confirmButton.trailingAnchor.constraint(equalTo: bottomPanel.trailingAnchor, constant: -20),
            confirmButton.bottomAnchor.constraint(equalTo: cancelButton.bottomAnchor),
            confirmButton.widthAnchor.constraint(equalToConstant: 60),
            confirmButton.heightAnchor.constraint(equalToConstant: 30)
        ])
    }

    /// 用户点了某个颜色圆点：切换当前通道，滑杆读出该通道已保存的 HSL，轨道颜色跟着换。
    @objc private func channelButtonTapped(_ sender: HSLChannelButton) {
        selectedChannel = sender.channel
        updateChannelSelectionUI()
        updateSlidersFromSelectedChannel()
        updateSliderGradients()
    }

    /// 任意一根滑杆在动：把数值写回 `adjustments` 字典里当前通道，刷新文字并排队算预览图。
    @objc private func sliderChanged() {
        adjustments[selectedChannel] = HSLAdjustment(
            hue: hueSlider.value,
            saturation: saturationSlider.value,
            lightness: lightnessSlider.value
        )
        updateValueLabels()
        schedulePreviewRender()
    }

    /// 八个圆点谁该高亮：跟 `selectedChannel` 对上的那个 `isSelected = true`。
    private func updateChannelSelectionUI() {
        for button in channelButtons {
            button.isSelected = button.channel == selectedChannel
        }
    }

    /// 刚换了通道或者重置过：三根滑杆从内存里的 `adjustments` 读回来，数字标签一起更新。
    private func updateSlidersFromSelectedChannel() {
        let adjustment = adjustments[selectedChannel] ?? .zero
        hueSlider.value = adjustment.hue
        saturationSlider.value = adjustment.saturation
        lightnessSlider.value = adjustment.lightness
        updateValueLabels()
    }

    /// 把滑杆当前值四舍五入成整数显示在右边（省得小数晃眼睛）。
    private func updateValueLabels() {
        hueValueLabel.text = "\(Int(round(hueSlider.value)))"
        saturationValueLabel.text = "\(Int(round(saturationSlider.value)))"
        lightnessValueLabel.text = "\(Int(round(lightnessSlider.value)))"
    }

    /// 换通道时给三根滑杆换渐变配色：色相条彩虹感，饱和/明暗跟着当前通道色走，纯视觉提示。
    private func updateSliderGradients() {
        let c = selectedChannel.uiColor
        hueSlider.gradientColors = [
            UIColor(red: 0.9, green: 0.22, blue: 0.14, alpha: 1),
            UIColor(red: 0.94, green: 0.68, blue: 0.05, alpha: 1),
            UIColor(red: 0.16, green: 0.68, blue: 0.18, alpha: 1),
            UIColor(red: 0.1, green: 0.63, blue: 0.85, alpha: 1),
            UIColor(red: 0.16, green: 0.37, blue: 0.95, alpha: 1),
            UIColor(red: 0.78, green: 0.16, blue: 0.72, alpha: 1)
        ]
        saturationSlider.gradientColors = [
            UIColor(red: 0.42, green: 0.42, blue: 0.42, alpha: 1),
            c.withAlphaComponent(0.85),
            c
        ]
        lightnessSlider.gradientColors = [
            .black,
            c.withAlphaComponent(0.65),
            UIColor(red: 0.58, green: 0.58, blue: 0.58, alpha: 1)
        ]
    }

    /// 滑杆停手后别每张图都算：取消上一单、版本号 +1，过几十毫秒再在后台用 32 维立方体画预览，旧结果丢弃。
    private func schedulePreviewRender() {
        pendingRenderWorkItem?.cancel()
        // 版本号只增不减：旧任务跑完如果发现号对不上，直接丢弃结果。
        renderVersion += 1
        let currentVersion = renderVersion
        let image = previewSourceImage
        let currentAdjustments = adjustments

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // 预览走小图 + 32 维立方体，省时间。
            let result = HSLPlusFilter.shared.render(
                image: image,
                adjustments: currentAdjustments,
                cubeDimension: 32
            )
            DispatchQueue.main.async {
                // 用户在这期间又拖了滑杆：这帧结果已经过期，别盖上去。
                guard currentVersion == self.renderVersion else { return }
                self.imageView.image = result ?? image
            }
        }

        pendingRenderWorkItem = workItem
        // 稍微憋一会儿再算，滑杆连续拖动时少烧几次 CPU/GPU。
        renderQueue.asyncAfter(deadline: .now() + 0.035, execute: workItem)
    }

    /// 准星按钮：只把当前选中的那一个通道的三项归零，其它通道不动。
    @objc private func resetCurrentChannel() {
        adjustments[selectedChannel] = .zero
        updateSlidersFromSelectedChannel()
        schedulePreviewRender()
    }

    /// 禁止按钮：八个通道全部重置，相当于整张图回到刚进编辑页的状态。
    @objc private func resetAllChannels() {
        for channel in HSLChannel.allCases {
            adjustments[channel] = .zero
        }
        updateSlidersFromSelectedChannel()
        schedulePreviewRender()
    }

    /// 新建预设：把八个通道的 `HSLAdjustment` 编成 JSON 丢进 `UserDefaults`，弹个框告诉用户存好了。
    @objc private func savePreset() {
        let encoder = JSONEncoder()
        let preset = Dictionary(uniqueKeysWithValues: HSLChannel.allCases.map { channel in
            (String(channel.rawValue), adjustments[channel] ?? .zero)
        })
        
        preset.forEach { (key , item) in
             print("++++ 打印修改的值 \(key), item:\(item)")
        }
        
        if let data = try? encoder.encode(preset) {
            UserDefaults.standard.set(data, forKey: "HSLPlusLastPreset")
        }

        let alert = UIAlertController(
            title: "预设已创建",
            message: "当前 8 个颜色通道的 HSL 参数已保存到本地。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "知道了", style: .default))
        present(alert, animated: true)
    }

    /// 波形占位钮：目前只弹说明，预留以后做直方图之类的能力。
    @objc private func showHistogramHint() {
        let alert = UIAlertController(
            title: "直方图入口",
            message: "截图左下角的圆形按钮已保留。这里可以继续扩展 RGB / 亮度直方图。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "知道了", style: .default))
        present(alert, animated: true)
    }

    /// 左下角叉：不搞保存，直接 pop 回相册选图页。
    @objc private func cancelEditing() {
        navigationController?.popViewController(animated: true)
    }

    /// 确定：先灰掉按钮防连点，后台用**原图** + 64 维立方体渲染高清，回到主线程再弹「要不要存相册」。
    
    //MARK: - 保存到相册
    @objc private func confirmEditing() {
        // 导出算得慢，先把按钮摁死，防用户狂点。
        confirmButton.isEnabled = false
        confirmButton.alpha = 0.65

        let source = originalImage
        let currentAdjustments = adjustments

        renderQueue.async { [weak self] in
            guard let self else { return }
            // 导出必须用原图 + 64 维立方体，比预览精细。
            let result = HSLPlusFilter.shared.render(
                image: source,
                adjustments: currentAdjustments,
                cubeDimension: 64
            ) ?? source

            DispatchQueue.main.async {
                self.confirmButton.isEnabled = true
                self.confirmButton.alpha = 1
                self.showSaveAlert(image: result)
            }
        }
    }

    /// 导出结果出来了：问用户要不要写入相册，点保存才进 `saveImageToPhotoLibrary`。
    private func showSaveAlert(image: UIImage) {
        let alert = UIAlertController(
            title: "是否保存图片？",
            message: "是否将调整后的图片保存到手机相册？",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self] _ in
            self?.saveImageToPhotoLibrary(image)
        })
        present(alert, animated: true)
    }

    /// 向系统申请「只写相册」权限，过了就调系统 API 保存；没过就提示去设置里开。
    private func saveImageToPhotoLibrary(_ image: UIImage) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard let self else { return }
            switch status {
            case .authorized, .limited:
                DispatchQueue.main.async {
                    UIImageWriteToSavedPhotosAlbum(
                        image,
                        self,
                        #selector(self.image(_:didFinishSavingWithError:contextInfo:)),
                        nil
                    )
                }
            default:
                DispatchQueue.main.async {
                    self.showPhotoPermissionAlert()
                }
            }
        }
    }

    /// 系统保存相册后的回调：有错误弹失败原因，成功弹一句恭喜（`image` 参数名和属性重了，是系统签名规定的）。
    @objc private func image(
        _ image: UIImage,
        didFinishSavingWithError error: Error?,
        contextInfo: UnsafeRawPointer
    ) {
        DispatchQueue.main.async {
            if let error {
                let alert = UIAlertController(
                    title: "保存失败",
                    message: error.localizedDescription,
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "知道了", style: .default))
                self.present(alert, animated: true)
            } else {
                let alert = UIAlertController(
                    title: "保存成功",
                    message: "图片已经保存到手机相册。",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "完成", style: .default))
                self.present(alert, animated: true)
            }
        }
    }

    /// 用户没给写相册权限：解释一声，并提供跳系统设置 App 的按钮。
    private func showPhotoPermissionAlert() {
        let alert = UIAlertController(
            title: "没有相册保存权限",
            message: "请在系统设置中允许 App 添加照片。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "去设置", style: .default) { _ in
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        })
        present(alert, animated: true)
    }
}
