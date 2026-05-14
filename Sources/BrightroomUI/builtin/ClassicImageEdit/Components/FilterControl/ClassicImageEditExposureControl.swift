//
// Copyright (c) 2018 Muukii <muukii.app@gmail.com>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import UIKit

#if !COCOAPODS
import BrightroomEngine
#endif
import Verge


 //MARK: - 曝光 | 光亮 控制器

open class ClassicImageEditExposureControlBase : ClassicImageEditFilterControlBase {

  public required init(viewModel: ClassicImageEditViewModel) {
    super.init(viewModel: viewModel)
  }
}

open class ClassicImageEditExposureControl : ClassicImageEditExposureControlBase {
  
  open override var title: String {
    return viewModel.localizedStrings.editBrightness
  }

    private lazy var navigationView = ClassicImageEditNavigationView(saveText: viewModel.localizedStrings.done, cancelText: viewModel.localizedStrings.cancel)

  public let slider = ClassicImageEditStepSlider(frame: .zero)

    
  //MARK: -  init stepup  注册滑块事件和导航按钮回调：
    
  open override func setup() {
    super.setup()
    print("📸 [Exposure] ▶ setup() — 控制器初始化，注册滑块事件")

    backgroundColor = ClassicImageEditStyle.default.control.backgroundColor

    TempCode.layout(navigationView: navigationView, slider: slider, in: self)

    slider.addTarget(self, action: #selector(valueChanged), for: .valueChanged)

    navigationView.didTapCancelButton = { [weak self] in
      
      guard let self = self else { return }
      print("📸 [Exposure] ✕ 点击 Cancel — revertEdit() 撤销到快照")
      self.viewModel.editingStack.revertEdit()
      self.pop(animated: true)
    }
    
    navigationView.didTapDoneButton = { [weak self] in
      
      guard let self = self else { return }
      print("📸 [Exposure] ✓ 点击 Done — takeSnapshot() 提交快照")
      self.viewModel.editingStack.takeSnapshot()
      self.pop(animated: true)
    }
  }

  open override func didReceiveCurrentEdit(state: Changes<ClassicImageEditViewModel.State>) {
    
    state.ifChanged(\.editingState.loadedState?.currentEdit.filters.exposure).do { value in
      let displayValue = value?.value ?? 0
      print("📸 [Exposure] 🔄 didReceiveCurrentEdit — 外部状态变化，同步滑块 → exposure.value = \(displayValue)")
      slider.set(value: displayValue, in: FilterExposure.range)
    }
    
  }

  @objc
  private func valueChanged() {

    let value = slider.transition(in: FilterExposure.range)
    print("📸 [Exposure] 🎚 slider valueChanged — 原始滑块值映射到 EV = \(value)（范围：\(FilterExposure.range.min) ~ \(FilterExposure.range.max)）")
      
    guard value != 0 else {
      print("📸 [Exposure] 🗑 value == 0，清空 filters.exposure = nil（移除滤镜节点）")
      viewModel.editingStack.set(filters: {
        $0.exposure = nil
      })
      return
    }    
    
    print("📸 [Exposure] ✏️ 写入 EditingStack → filters.exposure.value = \(value)")
    viewModel.editingStack.set(filters: {
      var f = FilterExposure()
      f.value = value
      $0.exposure = f
    })
    
  }
}
