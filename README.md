# AstraPlusCar HarmonyOS App

App 向车端 HTTP API 发送移动、停车和云台指令。当前小车的电脑 SSH 地址是 `192.168.8.204`；手机连接小车自带热点 `WSZN-2BFE2915` 时，应使用 `http://192.168.149.1:8080`。

首次试车保持四轮架空。先按[车端 README](../AstraPlusCar-device/README.md)恢复并实机验证 SSH manual，之后再验证 App。看到 `/api/health` 只能证明 HTTP 服务可达，还须检查控制回执、车轮动作和松手停车。

## 一、第一次连接：需要电脑

1. 电脑通过 `ssh root@192.168.8.204` 登录小车，并按车端 README 完成 manual 测试。
2. 在电脑上用 DevEco Studio 打开本仓库，连接 HarmonyOS 手机，配置调试签名并运行 App。已有可用签名时，可用 `hdc install -r entry/build/default/outputs/default/entry-default-signed.hap` 安装构建产物。
3. 小车 API 启动后，手机加入热点 `WSZN-2BFE2915`，先在手机浏览器打开 `http://192.168.149.1:8080/api/health`。
4. App 输入 `http://192.168.149.1:8080`，连接后先点 `STOP`、速度设为 25，再短暂拖动摇杆并松手，确认车轮停止。

电脑上离线构建 HAP：

```bash
cd /Users/raychen/Develop/AstraPlusCar/AstraPlusCar-HarmonyOS
/Users/raychen/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw \
  assembleHap --mode module -p product=default -p module=entry@default \
  -p buildMode=debug --no-daemon
```

## 二、后续连接：手机直连或电脑 SSH

| 方式 | 准备 | 地址或命令 |
| --- | --- | --- |
| 手机直连 | 小车开机，手机加入 `WSZN-2BFE2915`，API 服务健康 | 浏览器检查 `http://192.168.149.1:8080/api/health`；App 连接 `http://192.168.149.1:8080` |
| 电脑 SSH manual | 电脑能访问小车，先停止 API | 在车端仓库运行 `./deploy/start_manual_ssh.sh` |
| 电脑 SSH 维护 | 电脑能访问小车 | `ssh root@192.168.8.204`，检查 `systemctl status astra-plus-car-api --no-pager` |

App 摇杆按住移动、松手停车；旋转键按住旋转、松手停车；`STOP` 立即发停车请求。切到云台页可调角度；只有 `/api/health` 报告 `cameraReady: true` 时，画面和新截图才可用。手机退后台、网络连续失败或车端 0.9 秒未收到新的移动指令时应停车。

## 三、部署与扩展

- `entry/src/main/ets/services/CarApi.ets` 定义 HTTP 请求和错误处理；`entry/src/main/ets/models/CarModels.ets` 定义请求模型；`entry/src/main/ets/pages/Index.ets` 管理连接、定时续期和停车。修改接口时同步检查车端 `python/car_api_server.py`。
- 默认地址在 `entry/src/main/ets/constants/AppConstants.ets`。App 连接页允许输入其他 IP，手机热点直连请使用 `192.168.149.1`。
- 原 manual 与 App API 会争用底盘控制口；使用 manual 前停止 `astra-plus-car-api.service`，退出后再启动 API 并检查 `/api/health`。
- HAP 构建通过属于离线验证，不能代替真机安装、手机到热点的 HTTP 测试或车轮架空的停车测试。

详细 ArkTS 结构与排错见 [HarmonyOS 指南](docs/HARMONYOS_GUIDE.md)。
