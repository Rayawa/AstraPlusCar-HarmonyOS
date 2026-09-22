# 车端 API 桥接服务

现有 `main.py --mode manual` 只接收本机键盘输入，ArkTS 应用无法直接调用。因此本目录提供一个零新增依赖的 HTTP 桥接入口，复用原项目的 `Controller`、动作类和 OpenCV 摄像头。

## 部署到小车

不要同时运行 `main.py --mode manual` 和本服务，两者会争用串口与摄像头。

```bash
# 在电脑的 AstraPlusCar 工程根目录执行（需要时再部署）
scp car_server/car_api_server.py root@192.168.8.204:/home/HwHiAiUser/E2E-Samples-ziyan/src/E2E-Sample/Car/python/

# 登录小车后执行
source /usr/local/Ascend/ascend-toolkit/set_env.sh
source /home/HwHiAiUser/pyorbbecsdk/env.sh
cd /home/HwHiAiUser/E2E-Samples-ziyan/src/E2E-Sample/Car/python
python3 car_api_server.py --host 0.0.0.0 --port 8080
```

应用默认连接 `http://192.168.8.204:8080`，也可在首页修改地址。

部署新版后可用以下命令确认进程与版本；健康响应中的 `apiVersion` 应为
`1.1.0`：

```bash
curl http://127.0.0.1:8080/api/health
```

## 接口

- `GET /api/health`：连接与摄像头状态
- `GET /api/camera/frame`：当前 JPEG 画面
- `POST /api/control/move`：运动，JSON 参数为 `action`、`speed`、`degree`
- `POST /api/control/stop`：停车
- `POST /api/control/servo`：云台，JSON 参数为 `vertical`、`horizontal`
- `POST /api/camera/capture`：保存截图到小车当前工作目录的 `capture/`

App 会在移动、停车和云台请求中附带 `sequence`。移动/停车与云台分别按序处理，迟到的旧请求会被安全忽略；不带该字段的旧客户端仍可兼容运行。

移动接口必须由客户端每 300 ms 左右续期。服务端设有 0.9 秒看门狗，App 崩溃、断网或离开页面后会自动停车。摄像头打开或连续读取失败时，工作线程会自动释放并重连，不需要重启整个服务。

## 连接成功但硬件未就绪

`/api/health` 返回 JSON 说明手机到小车的网络链路已经正常。若其中
`cameraReady` 为 `false`，或控制接口返回 `controller_unavailable`，先确认旧的
手动程序没有占用摄像头和串口：

```bash
ps -ef | grep -E '[m]ain.py|[c]ar_api_server.py'
ls -l /dev/video*
fuser -v /dev/video* 2>/dev/null
ls -l /dev/ttyUSB* /dev/ttyACM* 2>/dev/null
```

只保留一个 `car_api_server.py`。如果仍有 `main.py --mode manual`，请回到启动它的
终端按 `Ctrl+C`，然后重启 API 服务。原手动程序与 API 服务不能并行运行，否则会
同时争用 `/dev/video0` 和 ESP32 串口。若摄像头实际枚举为其他编号，可使用
`--camera 1`（按实际编号替换）启动。

## 维护约定

- 设备、画质、重试、看门狗、请求大小和控制范围统一在 `ServerDefaults` 修改。
- API 路由统一在 `ApiRoutes` 修改，并同步 ArkTS 的 `AppConstants.ets`。
- 新增动作时，在 `ActionNames` 和 `CarRuntime.ACTIONS` 中注册，并补充离线测试。
