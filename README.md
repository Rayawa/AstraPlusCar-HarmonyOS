# AstraPlusCar HarmonyOS 手机手动控制

此 App 对接设备端 `main.py --phone` 的 `/api/v1` 接口。手机与小车处于同一 WLAN；当前车载热点的文档地址为 `http://192.168.149.1:8080`，连接页可改成实际 IP。设备端完整协议和部署方式见 [Phone API](../AstraPlusCar-device/docs/PHONE_API.md)。

第一版提供相机实时 JPEG 预览、雷达完整 JSON、`q/w/e/a/s/d/z` 和左右方向控制、上下速度步进、0–100 速度滑块、停车，以及车端截图加手机相册保存。方向键按住运动、松手停车；`z` 是一次计时掉头。控制中手机持续续期；断联、退后台或车端 600 ms 没收到续期都会停止运动。速度滑块会向设备发送绝对速度，界面随后采用设备确认值。

先在小车 SSH 终端运行 `systemctl start astra-phone`，随后可以退出 SSH。设备服务不会开机自启。只有相机和雷达就绪时 phone 模式才会启动；如有缺件请查看 `journalctl -u astra-phone`。手机连接小车 WLAN 后打开 App，输入服务 URL 并连接。STOP 一直显示在驾驶界面；首次运动测试必须架空车轮。

构建命令：

```bash
/Users/raychen/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw \
  assembleHap --mode module -p product=default -p module=entry@default \
  -p buildMode=debug --no-daemon
```

成功构建 HAP 只证明 ArkTS 和打包通过。手机 WLAN、画面、雷达串口、车轮方向和掉电/断联停车仍须在实车上逐项验证。项目的旧云台与相册组件留在仓库中，但第一版 phone 页面不调用这些旧接口。
