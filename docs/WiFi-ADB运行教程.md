# WiFi ADB 运行教程

通过无线 ADB 在安卓手机上运行此 Flutter 项目。

---

## 1. 前提条件

- Flutter SDK 已安装
- Android SDK 已安装
- 手机和电脑在同一 WiFi 网络

## 2. 手机端设置

1. 打开 **设置 → 关于手机**，连续点击「版本号」7 次开启开发者模式
2. 进入 **设置 → 系统 → 开发者选项**，开启 **USB 调试**

## 3. 配置 Flutter Android SDK 路径

如果 `flutter doctor` 报 Android SDK 相关错误，或 `flutter devices` 不显示设备：

```bash
# 设置 Android SDK 路径（替换为你的实际路径）
flutter config --android-sdk "D:\Software\AndroidSDK"

# 验证
flutter doctor
flutter devices
```

> Flutter 使用其 `bin/cache/artifacts/engine/` 下的 ADB，而非系统 PATH 中的 ADB。
> 配置正确后 Flutter 会使用 SDK 中的 `platform-tools\adb.exe`。

## 4. 连接手机

### 首次连接（需 USB 线）

```bash
# 用 USB 线连接手机，确认设备已识别
adb devices

# 切换到 TCP/IP 模式（端口 5555）
adb tcpip 5555

# 拔掉 USB 线，获取手机 IP（设置 → 关于手机 → 状态信息）
adb connect <手机IP>:5555

# 确认连接成功
adb devices
```

### 后续连接

同一网络下直接：

```bash
adb connect <手机IP>:5555
```

## 5. 运行项目

```bash
# 进入项目目录
cd bmb

# 查看可用设备（应包含 Android 设备）
flutter devices

# 运行
flutter run
```

多设备时指定目标：

```bash
flutter run -d <device-id>
```

## 6. 常见问题

| 问题 | 解决方法 |
|------|---------|
| `flutter devices` 看不到手机 | 运行 `flutter config --android-sdk` 设置 SDK 路径 |
| ADB 连接超时 | 确认手机和电脑在同一 WiFi；尝试 `adb kill-server && adb start-server` |
| 手机重启后连不上 | 重新 `adb tcpip 5555`（需 USB 线）后 `adb connect` |
| 端口冲突 | 更换端口：`adb tcpip <自定义端口>` → `adb connect <IP>:<端口>` |
