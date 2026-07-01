# TEAP v3 自动定位契约（P5.6）

## 不变的协议

TEAP 保持 20 格 v3 帧：第 1～4 格为 `T / E / Version=3 / State`，尾部仍使用 CRC16 与 Commit。`BindingToken`、Session、Sequence、Freshness、Catalog 与 Flags 的派发语义不变。

## 定位

1. TEK 读取 WoW HWND 的客户区原点和尺寸。
2. 只截取客户区左上有界 ROI：`360×96`、`640×160`、最多 `960×240` 物理像素。
3. 搜索 `T=84` 与 `E=69` 的色块，基于同高、同水平带和中心 pitch 推导第三格。
4. 只接受第三格颜色为 Version `3` 的候选。
5. 按候选几何读取完整 20 格，CRC16 与 Commit 必须正确。
6. 第二帧仍必须完整有效、Session 相同且 Freshness 前进，布局才被标记为 Verified。

`T/E/3` 只定位，不能单独放行输入。`State` 非 armed 会被现有门禁拒绝；armed 仍必须通过完整同帧验证。

## 几何与采样

- Anchor：WoW 客户区左上 + 8 物理像素安全边距。
- AddOn 使用 `UIParent:GetEffectiveScale()` 调整 UI 单位，方格至少约 8 物理像素。
- Locator 允许 `gap=0`，以 pitch 和颜色边界识别几何。
- 运行期每格中心使用 3×3（小格）或 5×5（>=8px）中位数 RGB 采样。

## 失败语义

自动模式找不到 Header、完整帧无效、freshness 停滞或候选布局变更时，TEK 进入非派发等待/重定位；不得使用绝对坐标 fallback。独占全屏的黑帧、冻结帧或桌面旧帧应作为捕获后端问题单独诊断。
