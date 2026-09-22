# AstraPlusCar

AstraPlusCar 是一套面向 HarmonyOS 手机、平板和 2in1/PC 的智能小车控制项目。HarmonyOS App 使用 ArkTS 开发，通过局域网 HTTP API 控制 Orange Pi AI Pro 小车，并提供实时画面、车端截图、速度调节、全向移动和双舵机云台控制。

App 最低兼容 HarmonyOS API 20，默认连接地址为 `http://192.168.8.204:8080`。

## 主要功能

- 手机、平板和 2in1/PC 自适应界面
- 小车地址配置和在线状态检测
- 按住前进、后退、左转、右转，松手自动停车
- 左右平移、顺时针/逆时针旋转和紧急停车
- 25–60 速度调节
- 智能摄像头画面预览、暂停和截图
- 云台俯仰、水平角度调节和镜头复位
- 指令序号校验，防止弱网下旧指令覆盖新指令
- App 续期控制和车端 0.9 秒失联停车看门狗
- 摄像头异常自动重连，控制器异常独立提示

## 系统组成

项目由两部分组成：

1. HarmonyOS App：安装在手机、平板或 2in1/PC 上，负责界面和控制指令。
2. 车端 API：运行在 Orange Pi AI Pro 上，将 HTTP 请求转换为原小车项目的电机、舵机和摄像头操作。

```text
HarmonyOS App
    │  局域网 HTTP（默认端口 8080）
    ▼
car_api_server.py
    ├── Controller ── ESP32 串口 ── 电机和舵机
    └── OpenCV ────── /dev/video* ── 智能摄像头
```

## 项目结构

```text
AstraPlusCar/
├── AppScope/                         # 应用级配置与资源
├── entry/                            # HarmonyOS 主模块
│   └── src/main/
│       ├── ets/
│       │   ├── components/           # 连接、摄像头、驾驶、云台等 UI 组件
│       │   ├── constants/            # 地址、范围、超时、路由、颜色等常量
│       │   ├── entryability/         # 应用入口 Ability
│       │   ├── models/               # API 数据模型和控制命令
│       │   ├── pages/                # 主页面与生命周期编排
│       │   └── services/             # HTTP API 和局域网路由服务
│       ├── module.json5              # 模块、设备类型和权限配置
│       └── resources/                # 字符串、颜色、图标和网络配置
├── car_server/
│   ├── car_api_server.py             # Orange Pi 车端 HTTP 服务
│   ├── tests/test_api_contract.py    # API、看门狗和摄像头离线测试
│   └── README.md                     # 车端接口与排障细节
├── build-profile.json5               # SDK、产品和签名配置
└── README.md
```

## 环境要求

### HarmonyOS 开发端

- DevEco Studio 和 HarmonyOS SDK
- HarmonyOS API 20 或更高版本的真机
- 已配置调试签名；换电脑后需要在 DevEco Studio 中重新配置本机签名
- 手机和小车连接同一个 Wi-Fi/局域网

### Orange Pi 车端

- Orange Pi AI Pro
- 已部署原始 `E2E-Sample/Car` 工程
- 默认 Python 目录：`/home/HwHiAiUser/E2E-Samples-ziyan/src/E2E-Sample/Car/python`
- Ascend Toolkit、`pyorbbecsdk`、OpenCV、串口及原项目依赖可正常使用
- 可通过 SSH 登录小车，例如 `ssh root@192.168.8.204`

## 一、构建 HarmonyOS App

### 使用 DevEco Studio

1. 使用 DevEco Studio 打开本项目根目录。
2. 等待工程同步完成。
3. 在签名设置中选择或生成本机调试证书。
4. 选择 `entry` 模块和 `default` 产品。
5. 执行 **Build > Build Hap(s)/APP(s) > Build Hap(s)**。

构建产物位于：

```text
entry/build/default/outputs/default/entry-default-signed.hap
```

### 使用命令行

以下为当前 macOS 开发环境的命令；若 DevEco Studio 安装位置不同，请替换 `hvigorw` 路径：

```bash
/Users/raychen/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw \
  assembleHap --mode module \
  -p product=default \
  -p module=entry@default \
  -p buildMode=debug \
  --no-daemon
```

连接 HarmonyOS 设备后，可直接通过 DevEco Studio 运行，也可以在 `hdc` 已加入 `PATH` 时安装 HAP：

```bash
hdc install -r entry/build/default/outputs/default/entry-default-signed.hap
```

## 二、部署车端 API

不要同时运行原来的 `python3 main.py --mode manual` 和 `car_api_server.py`。两个程序会争用 ESP32 串口和摄像头，造成 `camera_open_failed`、`controller_unavailable` 或 `I/O operation on closed file`。

在电脑的项目根目录执行：

```bash
scp car_server/car_api_server.py \
  root@192.168.8.204:/home/HwHiAiUser/E2E-Samples-ziyan/src/E2E-Sample/Car/python/
```

登录小车：

```bash
ssh root@192.168.8.204
```

检查是否仍有旧程序占用设备：

```bash
ps -ef | grep -E '[m]ain.py|[c]ar_api_server.py'
fuser -v /dev/video* 2>/dev/null
```

如果存在旧的手动程序或 API 服务，请回到对应终端按 `Ctrl+C` 停止，确保最终只运行一个 `car_api_server.py`。

加载环境并启动服务：

```bash
source /usr/local/Ascend/ascend-toolkit/set_env.sh
source /home/HwHiAiUser/pyorbbecsdk/env.sh
cd /home/HwHiAiUser/E2E-Samples-ziyan/src/E2E-Sample/Car/python
python3 car_api_server.py --host 0.0.0.0 --port 8080
```

服务启动后会显示：

```text
Astra Drive API listening on http://0.0.0.0:8080
```

保持该终端运行。需要停止服务时按 `Ctrl+C`。

## 三、验证车端服务

先在小车上执行：

```bash
curl http://127.0.0.1:8080/api/health
```

正常响应示例：

```json
{
  "ok": true,
  "apiVersion": "1.1.0",
  "cameraReady": true,
  "cameraDevice": 0,
  "cameraError": ""
}
```

然后在手机浏览器访问：

```text
http://192.168.8.204:8080/api/health
```

浏览器能显示 JSON，说明手机到小车的局域网链路和 8080 端口已经连通。

## 四、使用 App

1. 确认手机与小车位于同一局域网。
2. 启动车端 `car_api_server.py`。
3. 打开 Astra Drive App。
4. 保持默认地址 `http://192.168.8.204:8080`，或填写小车的实际 IP 和端口。
5. 点击“连接”。
6. 连接后可使用方向键、全向移动、速度滑块、云台滑块、镜头复位和截图功能。
7. 方向按钮需要按住；松开、取消触摸、进入后台或断开连接时都会停车。
8. 截图保存在小车 Python 工作目录下的 `capture/` 文件夹中。

摄像头或云台未就绪时，App 会保留已经建立的网络连接并单独显示错误，不会将单项硬件故障误判为手机网络断开。

## 常用启动参数

```bash
python3 car_api_server.py \
  --host 0.0.0.0 \
  --port 8080 \
  --camera 0 \
  --capture-dir ./capture
```

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `--host` | `0.0.0.0` | 监听地址；局域网访问需监听所有网卡 |
| `--port` | `8080` | HTTP 服务端口 |
| `--camera` | `0` | OpenCV 摄像头编号 |
| `--capture-dir` | 当前目录下的 `capture/` | 截图保存目录 |

如果摄像头不是 `/dev/video0`，先执行 `ls -l /dev/video*` 查看设备，再尝试 `--camera 1` 等实际编号。

## API 概览

| 方法 | 路径 | 功能 |
| --- | --- | --- |
| `GET` | `/api/health` | 查询服务版本和摄像头状态 |
| `GET` | `/api/camera/frame` | 获取最新 JPEG 画面 |
| `POST` | `/api/control/move` | 前后、转向、平移和旋转 |
| `POST` | `/api/control/stop` | 停车 |
| `POST` | `/api/control/servo` | 调整双舵机角度 |
| `POST` | `/api/camera/capture` | 将当前画面保存到车端 |

完整参数和维护约定参见 [car_server/README.md](car_server/README.md)。

## 常见问题

### 手机浏览器显示 `ERR_CONNECTION_REFUSED`

表示小车的 8080 端口没有进程监听。检查：

```bash
ss -lntp | grep 8080
ps -ef | grep '[c]ar_api_server.py'
```

如果没有输出，请按“部署车端 API”一节重新启动服务。

### `cameraReady` 为 `false`

网络连接已经成功，但摄像头尚未打开。检查设备和占用进程：

```bash
ls -l /dev/video*
fuser -v /dev/video* 2>/dev/null
```

确认没有 `main.py --mode manual` 占用摄像头，并尝试正确的 `--camera` 编号。

### App 显示“车端控制器不可用”

检查是否同时运行了多个小车程序，并确认 ESP32 串口存在：

```bash
ps -ef | grep -E '[m]ain.py|[c]ar_api_server.py'
ls -l /dev/ttyUSB* /dev/ttyACM* 2>/dev/null
```

停止重复进程后重启 API 服务。

### 健康检查成功但 App 仍异常

确认 `/api/health` 返回的 `apiVersion` 为 `1.1.0`，并重新安装最新构建的 signed HAP。旧车端脚本的健康响应不包含 `apiVersion`。

## 离线验证

以下操作不需要连接小车：

```bash
python3 -m py_compile \
  car_server/car_api_server.py \
  car_server/tests/test_api_contract.py

python3 -m unittest discover -s car_server/tests -v
```

ArkTS 侧以 HAP 全量编译和打包成功作为离线验收依据。

## 安全说明

- API 当前没有身份认证，只应在可信的私有局域网中使用。
- `--host 0.0.0.0` 会让同一网络中的其他设备访问该端口，不要直接暴露到公网。
- 启动、停止或调试服务前，应确保小车周围安全并可随时断电。
- App、网络或手机异常时，车端看门狗会在约 0.9 秒未收到续期后停车，但不能替代物理急停和现场安全措施。
