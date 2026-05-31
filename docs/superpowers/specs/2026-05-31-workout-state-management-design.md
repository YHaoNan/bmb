# 运动状态管理与后台通知设计

## 状态机

```
idle ──startSet──▶ exercising ──completeSet──▶ resting
  ▲                    ▲                            │
  │                    └──interruptRest──────────────┘
  └────restComplete───▶ idle
```

- `idle`: 无活跃动作，可开始任意 set
- `exercising`: 全局唯一一个 set 在进行中，其他 set 锁定
- `resting`: 组间休息倒计时，可被 startSet 打断

## 架构

```
Flutter: WorkoutStateManager (单例)
  │ MethodChannel "com.bmb.app/workout"
  ▼
Android: MainActivity.kt → WorkoutService.kt
  ├─ 前台服务通知 (常驻通知栏)
  ├─ WindowManager 悬浮窗 (仅休息+后台)
  └─ VibrationEffect (休息结束)
```

## Flutter 组件

### WorkoutStateManager
- 单例，全局状态
- 方法: startSet, completeSet, interruptRest, setRestTimer
- 回调: onStateChanged, onRestTick, onRestComplete
- 集成到 WorkoutPage，替换当前 per-set 计时逻辑

### MethodChannel 协议
| 方法 | 参数 | 说明 |
|------|------|------|
| startWorkoutService | — | 启动前台服务 |
| updateNotification | state, title, text, remainingSecs, totalSecs | 更新通知 |
| stopWorkoutService | — | 停止服务 |
| showFloatingTimer | remainingSecs, totalSecs | 显示悬浮窗 |
| hideFloatingTimer | — | 隐藏悬浮窗 |
| triggerVibration | — | 震动 |
| checkOverlayPermission | — → bool | 检查权限 |
| requestOverlayPermission | — | 请求权限 |

## Android 组件

### WorkoutService.kt
- 前台服务，`startForeground` 常驻通知
- 通知栏三种状态: idle/exercising/resting (Custom RemoteViews)
- 休息态展开通知: 圆形进度条 (layer-list drawable) + 中心秒数

### 悬浮窗
- WindowManager TYPE_APPLICATION_OVERLAY
- 60dp 半透明圆形，neon 绿进度环 + 中心秒数
- 点击 Intent 返回 MainActivity

### 权限
- FOREGROUND_SERVICE + FOREGROUND_SERVICE_DATA_SYNC
- POST_NOTIFICATIONS (Android 13+)
- SYSTEM_ALERT_WINDOW (悬浮窗)
- VIBRATE
