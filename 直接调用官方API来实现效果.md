


// 直接调用官方API来实现效果

除了调整图片光亮，是用的Apple 官方的 Core Image 滤镜直接处理像素数据， 还有那些也是直接可以调用官方API来实现的？阴影，暗角都是吗？
- Mask —— 蒙版
- Brightness —— 亮度
- Contrast —— 对比度
- Clarity —— 清晰度

- Temperature —— 色温
- Saturation —— 饱和度
- Fade —— 褪色/淡化
- Highlights —— 高光
- Shadows —— 阴影

- Vignette —— 暗角（渐晕）
- Sharpen —— 锐化
- Blur —— 模糊


//--- 

所有滤镜代码都读完了，答案非常清晰。

---

## 所有滤镜一览：全部都是 Core Image API

**没有一个是自己手写算法的**，全部直接调用 Apple 官方 `Core Image` 滤镜。

| 功能 | 文件 | 调用的 Core Image 滤镜 | 说明 |
|---|---|---|---|
| **光亮 Exposure** | `FilterExposure` | `CIExposureAdjust` | 调整 EV 曝光值，范围 -1.8 ~ 1.8 |
| **亮度 Brightness** | `FilterBrightness` | `CIColorControls` (`inputBrightness`) | 线性偏移像素亮度，范围 -0.2 ~ 0.2 |
| **对比度 Contrast** | `FilterContrast` | `CIColorControls` (`inputContrast`) | 拉伸亮暗差距，基准值是 1.0 |
| **饱和度 Saturation** | `FilterSaturation` | `CIColorControls` (`inputSaturation`) | 调颜色鲜艳程度，基准值是 1.0 |
| **色温 Temperature** | `FilterTemperature` | `CITemperatureAndTint` | 以 6500K 为基准，向冷/暖偏移 |
| **高光 Highlights** | `FilterHighlights` | `CIHighlightShadowAdjust` (`inputHighlightAmount`) | 专门压亮部细节 |
| **阴影 Shadows** | `FilterShadows` | `CIHighlightShadowAdjust` (`inputShadowAmount`) | 专门提暗部细节 |
| **暗角 Vignette** | `FilterVignette` | `CIVignette` | 边缘压暗，radius 根据图片尺寸动态计算 |
| **锐化 Sharpen** | `FilterSharpen` | `CISharpenLuminance` | 锐化亮度通道 |
| **清晰度 Clarity** | `FilterUnsharpMask` | `CIUnsharpMask` | 反锐化蒙版，本质是增强局部对比 |
| **模糊 Blur** | `FilterGaussianBlur` | `CIGaussianBlur` | 高斯模糊，有 clamp+crop 防止边缘变透明 |
| **褪色 Fade** | `FilterFade` | `CIConstantColorGenerator` + `CISourceOverCompositing` | **唯一一个组合滤镜**：先生成一层白色半透明遮罩，再叠加到图片上 |

---

## 几个有意思的细节

**Brightness 和 Exposure 用的是不同 API，效果也不同：**
- `Brightness` → `CIColorControls` + `inputBrightness`：线性加减，直接偏移像素值，调多了容易死白/死黑
- `Exposure` → `CIExposureAdjust`：按 EV 档数做乘法，模拟真实相机曝光，保留高光细节

**高光和阴影用的是同一个 Core Image 滤镜：**
- `CIHighlightShadowAdjust` 同时有 `inputHighlightAmount` 和 `inputShadowAmount` 两个参数
- 项目里拆成了两个独立的 `FilterHighlights` / `FilterShadows`，每次只传一个参数，另一个用默认值

**Fade 褪色是唯一一个「组合实现」的：**
- 没有直接的 Core Image 褪色滤镜，所以自己组合了：先用 `CIConstantColorGenerator` 生成一张白色半透明图，再用 `CISourceOverCompositing` 叠在原图上，模拟照片褪色效果

**Blur 模糊多了两步边缘处理：**

```34:47:Sources/BrightroomEngine/Filter/FilterGaussianBlur.swift
public func apply(to image: CIImage, sourceImage: CIImage) -> CIImage {

  let radius = RadiusCalculator.radius(value: value, max: FilterGaussianBlur.range.max, imageExtent: image.extent)

  return
    image
      .clamped(to: image.extent)   // 先把边缘像素往外延伸，防止模糊后出现透明边
      .applyingFilter(
        "CIGaussianBlur",
        parameters: [
          "inputRadius" : radius
        ])
      .cropped(to: image.extent)   // 再裁回原始尺寸
}
```

**Mask（蒙版）是唯一一个不在这里的：** 它不是像素滤镜，而是用路径绘制模糊遮罩层，逻辑在 `BlurryMaskingView` 里单独实现。

