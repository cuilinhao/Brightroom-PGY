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

protocol ClassicImageEditControlChildViewType {
}

extension ClassicImageEditControlChildViewType where Self : UIView {

  private func find() -> ClassicImageEditControlStackView {
    // 大白话：从当前视图开始，逐级向上找它的 superview（父视图），
    // 一直找到包含我们的 ClassicImageEditControlStackView 为止。
    // 这是一种「视图层级遍历」技巧，避免每个子视图都要手动持有 stackView 的强引用。
    // 如果没找到就崩溃（fatalError），说明用法有问题。
    var _super: UIView?
    _super = superview
    while _super != nil {
      if let target = _super as? ClassicImageEditControlStackView {
        return target
      }
      _super = _super?.superview
    }

    fatalError("ClassicImageEditControlStackView not found in superview hierarchy")

  }

  func push(_ view: UIView & ClassicImageEditControlChildViewType, animated: Bool) {
    // 大白话解释：这个方法让你从任意一个「控制子视图」（比如滤镜面板、调整参数面板）里，
    // 方便地调用 push 去显示另一个新的控制面板。
    // 它会自动向上找父视图里的 ClassicImageEditControlStackView，然后委托它来真正执行 push 操作。
    // 这样每个子视图都不用自己持有 stackView 的引用，代码更干净。
    let controlStackView = find()
    controlStackView.push(view, animated: animated)
  }

  func pop(animated: Bool) {
    // 大白话：从当前子视图调用，找到 StackView 后，让它把最上层的控制面板「弹出」移除。
    // 通常在「完成」「取消」按钮里调用，回到上一个编辑面板。
    find().pop(animated: animated)
  }

}


final class ClassicImageEditControlStackView : UIView {

  private var latestNotifiedEdit: EditingStack.Edit?
  
  func push(_ view: UIView & ClassicImageEditControlChildViewType, animated: Bool) {
    // 【大白话核心解释】
    // 这个方法就像「导航控制器 pushViewController」一样，
    // 把一个新的「编辑控制面板」（比如亮度滑块、滤镜列表、裁剪工具等）叠加到当前显示的最上层。
    // 所有这些面板都是 UIView 的子视图，层层叠加在 StackView 里。
    // 它负责：
    // 1. 把新面板加进来铺满整个区域
    // 2. 如果要动画，就让新面板优雅地从下方淡入滑入，老面板稍微「让位」一下
    
    // 1. 记住当前最上层的控制面板（用于动画时做背景处理）
    let currentTop = subviews.last
    
    // 2. 把新视图添加为子视图，让它显示在最上面
    addSubview(view)
    // 设置新视图大小和当前 StackView 一样大，并支持自动调整尺寸（适配旋转、布局变化）
    view.frame = bounds
    view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
    // 3. 如果需要动画效果，就执行带弹簧的过渡动画（iOS 常见的优雅动效）
    if animated {
      // 前景动画：新面板从透明+轻微下移的位置，平滑地淡入并归位
      // （制造「从底部冒出来」的感觉）
      foreground: do {
        view.alpha = 0
          // 新面板的淡入动画
        view.transform = CGAffineTransform(translationX: 0, y: 8)
        UIView.animate(
          withDuration: 0.3,
          delay: 0,
          usingSpringWithDamping: 1,
          initialSpringVelocity: 0,
          options: [.beginFromCurrentState, .curveEaseOut, .allowUserInteraction],
          animations: {
            view.alpha = 1
            view.transform = .identity
        }, completion: nil)
      }
      
      // 背景动画：让之前最上层的面板稍微向上偏移一点，制造层次感和「被挤下去」的感觉
      // 动画结束后恢复原位（只是视觉反馈，不真正移除）
      background: do {
        
        // 旧面板的让位动画
        if let view = currentTop {
          UIView.animate(
            withDuration: 0.3,
            delay: 0,
            usingSpringWithDamping: 1,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .curveEaseOut, .allowUserInteraction],
            animations: {
              view.transform = CGAffineTransform(translationX: 0, y: 8)
          }, completion: { _ in
            view.transform = .identity
          })
        }
        
      }
    }
    // 非动画模式就直接显示（代码里省略了，因为 addSubview 已经让它显示了）
  }
  
  func pop(animated: Bool) {
    // 【大白话核心解释】
    // pop 就是把当前最上层的控制面板「弹出去」并移除。
    // 类似于导航的 popViewController。
    // 它会：
    // 1. 找到当前最顶层的视图（要移除的）
    // 2. 找到它下面的那个视图（背景层，要恢复动画）
    // 3. 执行淡出+下滑动画，然后真正 removeFromSuperview
    
    // 安全检查：如果没有子视图就直接返回
    guard let currentTop = subviews.last else {
      return
    }
    
    // 找到当前 top 下面的那个视图（用于做「恢复」动画）
    let background = subviews.dropLast().last
    
    // 把移除操作封装成闭包，动画完成后再执行（避免动画中视图还在）
    let remove = {
      currentTop.removeFromSuperview()
    }
    
    if animated {
      // 当前 top 视图：淡出 + 向下偏移 8 点，然后移除
      UIView.animate(
        withDuration: 0.3,
        delay: 0,
        usingSpringWithDamping: 1,
        initialSpringVelocity: 0,
        options: [.beginFromCurrentState, .curveEaseOut, .allowUserInteraction],
        animations: {
          currentTop.alpha = 0
          currentTop.transform = CGAffineTransform(translationX: 0, y: 8)
      }, completion: { _ in
        remove()
      })
      
      // 背景层（之前被盖住的面板）：先偏移一点，然后平滑恢复到正常位置
      // 制造「新面板离开后，旧面板弹回」的视觉效果
      if let view = background {
        view.transform = CGAffineTransform(translationX: 0, y: 8)
        UIView.animate(
          withDuration: 0.3,
          delay: 0,
          usingSpringWithDamping: 1,
          initialSpringVelocity: 0,
          options: [.beginFromCurrentState, .curveEaseOut, .allowUserInteraction],
          animations: {
            view.transform = .identity
        }, completion: { _ in
        })
      }
    }
    else {
      // 非动画模式：直接移除
      remove()
    }
  }
  
}

