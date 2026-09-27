# AstraPlusCar HarmonyOS 手机手动控制

本应用最低兼容版本与目标版本均为 HarmonyOS API 23。手机与小车连接同一 WLAN 后，在连接半模态页中输入车端 URL；默认地址为 `http://192.168.149.1:8080`。车端协议与部署方式见 [Phone API](../AstraPlusCar-device/docs/PHONE_API.md)。

## 界面与操作

首页使用 HdsNavigation MINI 标题栏，适配顶部和底部安全区，明暗颜色分别由 `entry/src/main/resources/base/element/color.json` 和 `entry/src/main/resources/dark/element/color.json` 管理。顶部以“小车连接”为主状态，右侧 2×2 展示视频、雷达、语音、模型的从属状态；语音和模型目前固定显示离线。点击任一状态可打开连接半模态页。该页先显示固定 16:9 的摄像头预览，再持续显示格式化的雷达 JSON，下面提供车端地址输入和连接测试。

主页面依次展示状态、固定 16:9 的监看画面、操控卡片和连接提示，手机竖屏内无需滚动。操控卡片中央是前进、右转、后退、左转四个带圆角的扇形判定区及停车键；四角分别是左旋转、右旋转、左平移、右平移，按钮沿圆盘外弧排布，速度滑块位于同一张卡片内。手指滑过方向分隔线时，应用先释放原方向，稳定进入新区域后再切换；松手即停车。操控区与速度滑块使用轻触振动，其他交互使用较强振动，按压时提供阴影和点光反馈。未连接时仍可触摸控件，应用显示两秒提示，不发送运动命令。

点击监看画面可在车端截图，并下载到应用私有图库。图库入口位于标题栏；截图跨重启保留并显示 `YYYY-MM-DD HH:mm:ss` 时间戳。点按缩略图可放大，长按缩略图或放大图片可选择删除或下载到系统相册。只有主动选择下载并通过系统确认后，图片才会写入系统相册。车端没有日志流接口，因此应用不提供控制台页面。

控制中手机持续续期；断联、退后台或车端 600 ms 没收到续期都会停止运动。速度滑块发送绝对速度，界面采用设备确认值。UI 改版未更改 HTTP 协议和车端代码。

## 启动与验证

在小车 SSH 终端运行 `systemctl start astra-phone`，随后可退出 SSH。设备服务不会开机自启；相机与雷达就绪时 phone 模式才会启动。如有缺件，查看 `journalctl -u astra-phone`。首次运动测试必须架空车轮。

构建命令：

```bash
/Users/raychen/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw \
  assembleHap --mode module -p product=default -p module=entry@default \
  -p buildMode=debug --no-daemon
```

本轮通过 HAP 构建及鸿蒙手机模拟服务验证了深色页面、安全区、状态更新、视频与雷达布局、前进与左旋转指令及松手停车、截图持久化、放大预览、长按菜单、显式下载到系统相册和删除。模拟服务不代表实车验证；手机与车端真实 Wi-Fi、摄像头、雷达、车轮方向和断联停车仍须在实车上验证。
