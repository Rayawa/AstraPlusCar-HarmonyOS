# AstraPlusCar HarmonyOS

这是 AstraPlusCar 的 HarmonyOS 手机控制端。它通过 Wi-Fi 局域网连接小车上的 HTTP API，用于控制移动、停车、速度、云台和摄像头。

> 如果你完全没有 HarmonyOS 开发经验，先按照下面的“从零开始”安装和连接。想了解 ArkTS 结构、API 协议和扩展方法，再阅读 [HarmonyOS 完整上手教程](docs/HARMONYOS_GUIDE.md)。

## 你能用它做什么

- 连接局域网内的 Orange Pi 小车；
- 使用左下角摇杆前进、后退、转向和横向移动；
- 左右平移和原地顺/逆时针旋转；
- 调整 25–60 的行驶速度；
- 调整两路舅机角度；
- 使用 `STOP` 立即发送停车指令；
- 摄像头就绪后全屏预览画面、保存截图并浏览车端相册。

摄像头不可用时，App 仍然可以连接并控制小车。

## 安全第一

首次操作请将车轮架空，先使用低速度短按测试，保持可随时断电。

- 方向键是“按住移动，松手停车”。
- App 进入后台、离开页面或断开连接时会尝试停车。
- 连续移动请求失败时，App 会进入安全离线状态。
- 车端还有 0.9 秒失联看门狗，但它不能替代物理断电和现场看护。

## 系统结构

```text
HarmonyOS App
      │  HTTP / Wi-Fi 局域网
      ▼
Orange Pi 车端 API
      ├── ESP32 串口 → 电机和舅机
      └── 摄像头 → JPEG 画面
```

App 只发送“前进”“停车”“舅机到某个角度”这类高层指令。电机方向、PWM、串口和引脚定义都由设备端负责。

## 从零开始：安装并连接

### 1. 确认车端已就绪

车端项目位于同级的 `AstraPlusCar-device` 仓库。先按该仓库 README 完成 `astra-plus-car-api` 开机自启部署。

在手机浏览器输入：

```text
http://192.168.8.204:8080/api/health
```

看到包含 `"ok": true` 和 `"apiVersion": "1.3.0"` 的 JSON，说明手机到小车的网络已经打通。

如果同时看到：

```json
{
  "cameraReady": false,
  "cameraError": "camera_disabled"
}
```

这是当前纯控制模式的正常结果，不影响底盘和云台。

### 2. 直接安装已构建的 HAP

已签名安装包位于：

```text
entry/build/default/outputs/default/entry-default-signed.hap
```

可以在 DevEco Studio 中连接手机后运行，也可在 `hdc` 可用时执行：

```bash
hdc list targets
hdc install -r entry/build/default/outputs/default/entry-default-signed.hap
```

`hdc list targets` 没有输出时，说明手机还没有连接到开发环境。

### 3. 在 App 中连接

1. 让手机和小车连接同一 Wi-Fi/局域网。
2. 打开 App。
3. 输入基础地址 `http://192.168.8.204:8080`。
4. 也可直接粘贴完整地址 `http://192.168.8.204:8080/api/health`，App 会自动转换。
5. 点击“连接并进入操控”。连接页会逐条打印直连、Wi-Fi 备用路由和错误日志。
6. 连接成功后 App 自动进入竖屏操控界面；看到“已连接 · 控制就绪”或“摄像头未就绪”即可操作。

### 4. 第一次移动测试

1. 车轮架空。
2. 把速度设为 25。
3. 点击一次 `STOP`。
4. 将左下角摇杆短暂向上拖动后立即松手，确认车轮转动并停止。
5. 依次测试后退、左右转、平移和旋转。

## 从源码构建

### 环境

- DevEco Studio；
- HarmonyOS SDK API 23 或更高；
- 已配置 HarmonyOS 调试签名；
- HarmonyOS API 23+ 手机或平板。

### DevEco Studio

1. 用 DevEco Studio 打开 `AstraPlusCar-HarmonyOS` 目录。
2. 等待项目同步完成。
3. 在 Signing Configs 中选择或生成本机调试证书。
4. 选择 `entry` 模块和 `default` 产品。
5. 执行 **Build > Build Hap(s)/APP(s) > Build Hap(s)**。

### 命令行

```bash
/Users/raychen/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw \
  assembleHap --mode module \
  -p product=default \
  -p module=entry@default \
  -p buildMode=debug \
  --no-daemon
```

换了电脑或 DevEco Studio 安装位置后，需要修改上面的 `hvigorw` 路径，并重新配置签名。

## 界面操作

| 区域 | 用法 |
| --- | --- |
| 连接页 | 输入小车 IP 和 8080 端口，并查看每一步连接日志或报错 |
| 连接/断开 | 执行健康检查、建立或释放网络会话 |
| 驾驶模式摇杆 | 拖动移动，松手停车；左右大幅拖动为横移，斜上为转向 |
| `STOP` | 立即发送停车命令 |
| 驾驶模式速度条 | 调整 25–60 的速度，并提供原地旋转与紧急停车 |
| 云台模式 | 截图、查看俯仰/水平角度、微调方向、复位或打开相册 |
| 底部悬浮标签栏 | 使用 HdsTabs 在驾驶模式和云台模式间切换 |
| 镜头复位 | 恢复默认角度 90° / 65° |
| 中央画面 | 持续显示车端 JPEG 摄像头画面 |
| 相册页 | 单独浏览车端 `capture` 目录中的照片，也可继续拍照 |

## 目录导航

```text
AstraPlusCar-HarmonyOS/
├── AppScope/                         # App 名称、图标和应用级资源
├── entry/
│   ├── src/main/module.json5        # 设备类型、Ability 和网络权限
│   ├── src/main/resources/          # 图标、文字和 HTTP 明文配置
│   └── src/main/ets/
│       ├── pages/Index.ets          # 页面状态和业务编排
│       ├── components/              # 连接屏、游戏操控屏、摇杆和相册 UI
│       ├── services/CarApi.ets      # HTTP 请求和错误映射
│       ├── services/LocalNetworkRoute.ets
│       │                           # 局域网路由备用方案
│       ├── models/CarModels.ets     # 请求/响应类型
│       └── constants/AppConstants.ets
│                                   # 默认 IP、速度、角度、超时和路由
├── docs/HARMONYOS_GUIDE.md            # 详细上手教程
└── build-profile.json5               # SDK、产品和签名
```

## 常见问题

| App 提示 | 含义与处理 |
| --- | --- |
| 车端地址格式无效 | 只填 `http://IP:端口`，或完整 `/api/health` 地址 |
| 连接被拒绝 | 车端 8080 没有监听，检查 systemd 服务 |
| 连接超时 | 检查 IP、Wi-Fi 和手机浏览器的 `/api/health` |
| 系统阻止明文 HTTP | 确认安装的是最新 HAP，并检查 `network_config.json` |
| 健康检查响应格式无效 | 车端版本太旧，应返回 API `1.3.0` 和 `ok: true` |
| 已连接，摄像头未就绪 | 底盘控制可用；当前可能是 `--no-camera` 模式 |
| 车端控制器不可用 | ESP32 串口未连接、权限不足或被其他进程占用 |
| 连续移动指令失败 | App 已进入安全离线，先检查车端再重连 |

## 开发者验证

HarmonyOS 侧的主要离线验收是 HAP 成功构建。本地测试位于 `entry/src/test/LocalUnit.test.ets`，包含地址标准化和基本协议常量检查。

离线构建不代表已经在真实手机、Wi-Fi、车端、串口或电机上完成联调。

## 相关文档

- [HarmonyOS 完整上手教程](docs/HARMONYOS_GUIDE.md)
- 车端仓库：`AstraPlusCar-device`
- 车端部署文档：`AstraPlusCar-device/deploy/README.md`
