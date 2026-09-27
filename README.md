# AstraPlusCar HarmonyOS 手机手动控制

本应用最低兼容版本与目标版本均为 HarmonyOS API 23。手机与小车连接同一 WLAN 后，在连接弹层中输入车端 URL；默认地址为 `http://192.168.149.1:8080`。车端协议与部署方式见 [Phone API](../AstraPlusCar-device/docs/PHONE_API.md)。

## 界面

首页采用 HdsNavigation MINI 标题栏与安全区适配，顶部三个状态入口分别显示小车、视频和雷达连接状态。点任一入口打开连接半模态页，左侧实时预览摄像头，右侧持续显示格式化的雷达 JSON；下方可输入 URL、测试连接或断开。控制台和图库均为 HdsNavDestination 页面，可由标题栏菜单进入。

主页面从上到下是状态、监看画面和长方形控制卡片，手机竖屏内无需滚动。卡片中央的圆环分为前进、左转、后退、右转四个圆角扇形触控区，手指滑过分隔线会先释放原方向、稳定进入新扇区后再切换；左右两侧的左旋转、左平移、右旋转、右平移按钮按住运动、松手停车，中心“停车”可立即停车，速度滑块位于同一卡片底部。点击监看画面会在车端截图，并下载到应用私有图库。图库截图跨重启保留，显示 `YYYY-MM-DD HH:mm:ss` 时间戳，长按图片删除本机副本。控制台保留最近 200 条客户端日志，展示车端 `/api/v1/status` 返回的状态摘要和连接、控制、截图结果；当前车端 API 未提供 stdout 或日志流接口，因此控制台不能显示车端任意 `print()` 输出。

控制中手机持续续期；断联、退后台或车端 600 ms 没收到续期都会停止运动。速度滑块发送绝对速度，界面采用设备确认值。UI 改版未更改 HTTP 协议和车端代码。

## 启动与验证

在小车 SSH 终端运行 `systemctl start astra-phone`，随后可退出 SSH。设备服务不会开机自启；相机与雷达就绪时 phone 模式才会启动。如有缺件，查看 `journalctl -u astra-phone`。首次运动测试必须架空车轮。

构建命令：

```bash
/Users/raychen/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw \
  assembleHap --mode module -p product=default -p module=entry@default \
  -p buildMode=debug --no-daemon
```

本轮已用 HAP 构建和鸿蒙手机进行离线及本机模拟服务验证：导航、安全区、状态更新、视频与雷达展示、截图持久化、长按删除。模拟服务不代表实车验证；手机 WLAN、车端真实摄像头/雷达、车轮方向和断联停车仍须在实车上验证。
