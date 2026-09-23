# AstraPlusCar HarmonyOS 完整上手教程

本文面向第一次使用 ArkTS/ArkUI 的学生。阅读前不需要了解 Android、React 或车辆控制。

完成后，你应该能够：

1. 构建、安装和运行 HarmonyOS HAP；
2. 理解 App 如何连接车端 API；
3. 看懂页面、组件、服务和数据模型的分工；
4. 理解移动续期、指令序号和安全停车；
5. 在不破坏车端协议的前提下新增功能。

## 1. App 在整个项目中的位置

```text
用户触摸 ArkUI 按键
       │
       ▼
Index.ets 管理连接和安全状态
       │
       ▼
CarApi.ets 生成 HTTP JSON
       │  Wi-Fi 局域网
       ▼
Orange Pi car_api_server.py
       │  串口
       ▼
当前 Hiwonder/RRC 底盘和电机/舵机
```

HarmonyOS 端不应该知道 PWM、串口名、控制板引脚或四个电机的正反号。App 只使用 HTTP 协议表达“前进、35 速度”这类高层意图。原 E2E/ESP32 样例仍保留在车端仓库，但这台车的 manual 使用 Hiwonder/RRC 后端。

## 2. 运行前的必要条件

### 2.1 车端

车端 API 版本应为 `1.3.0`。先用手机浏览器打开：

```text
http://192.168.149.1:8080/api/health
```

最小正常响应：

```json
{
  "ok": true,
  "apiVersion": "1.3.0",
  "cameraReady": false,
  "cameraError": "camera_disabled"
}
```

浏览器都打不开时，不要先改 App；应检查车端 systemd、IP 和 Wi-Fi。

### 2.2 HarmonyOS 环境

- DevEco Studio；
- HarmonyOS SDK API 23+；
- 可用的调试签名；
- API 23+ 真机；
- 手机已启用开发者选项和调试连接。

项目当前的构建配置：

```text
target SDK: 6.1.0(23)
compatible SDK: 6.1.0(23)
bundleName: top.rayawa.astra_plus_car
```

## 3. 构建、安装和启动

### 3.1 DevEco Studio 方式

1. 打开 `AstraPlusCar-HarmonyOS`，不要打开上一层双仓库工作区。
2. 等待 Sync 结束。
3. 打开项目签名设置，选择或生成本机调试证书。
4. 选择 `entry` / `default`。
5. 连接手机后点击 Run，或先 Build HAP。

### 3.2 命令行方式

```bash
/Users/raychen/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw \
  assembleHap --mode module \
  -p product=default \
  -p module=entry@default \
  -p buildMode=debug \
  --no-daemon
```

输出：

```text
entry/build/default/outputs/default/entry-default-signed.hap
```

安装：

```bash
hdc list targets
hdc install -r entry/build/default/outputs/default/entry-default-signed.hap
```

### 3.3 签名问题

`build-profile.json5` 中的签名材料是本机路径。换电脑后不能直接假设路径仍然有效，应在 DevEco Studio 中重新生成或选择调试签名。

## 4. 项目目录和文件职责

```text
AstraPlusCar-HarmonyOS/
├── AppScope/
│   ├── app.json5                  # bundleName、版本、图标和标签
│   └── resources/                 # App 级资源
├── entry/
│   ├── build-profile.json5        # entry 构建选项
│   └── src/main/
│       ├── module.json5           # Ability、权限和设备类型
│       ├── resources/base/profile/network_config.json
│       │                           # 明文 HTTP 网络安全配置
│       └── ets/
│           ├── entryability/       # App Ability 入口
│           ├── pages/Index.ets     # 主页和所有业务状态
│           ├── components/         # 可复用 ArkUI 界面块
│           ├── services/           # HTTP 和网络路由
│           ├── models/             # 类型和结果工厂
│           └── constants/          # 端点、限制和 UI 常量
├── docs/HARMONYOS_GUIDE.md
├── build-profile.json5               # 产品、SDK 和签名
└── oh-package.json5                  # ohpm 依赖
```

### 4.1 `Index.ets`

`Index` 是页面的状态中心，负责：

- 连接、断开和页面生命周期；
- 移动续期定时器；
- 松手停车定时器；
- 摄像头画面刷新定时器；
- 序号、会话和过期请求判定；
- 将状态和回调传给 UI 组件。

### 4.2 `components/`

| 文件 | 职责 |
| --- | --- |
| `ConnectionScreen.ets` | 连接地址、连接按钮、实时步骤日志和错误信息 |
| `GameControlScreen.ets` | 竖屏状态与摄像头区域、悬浮 HdsTabs、驾驶和云台控制 |
| `GameJoystick.ets` | 左下拖拽摇杆及方向到动作的映射 |
| `GalleryScreen.ets` | 单独的车端照片网格、刷新和拍照入口 |
| `AppHeader.ets` 等旧组件 | 保留的早期分栏界面组件，目前不由 `Index` 使用 |

组件不直接访问 HTTP。它们只接收 `@Prop` 和回调，业务编排统一放在 `Index.ets`。

### 4.3 `CarApi.ets`

`CarApi` 封装 `@kit.NetworkKit` 的 `http.createHttp()`，负责：

- 地址标准化；
- GET/POST 请求；
- JSON 序列化与解析；
- HTTP 状态码判定；
- HarmonyOS 网络错误码转换成中文提示；
- 每次请求后销毁 `HttpRequest`。

### 4.4 `LocalNetworkRoute.ets`

App 首先使用系统默认路由，这与手机浏览器的可用路径一致。直连失败后，`LocalNetworkRoute` 再尝试将 App 绑定到 Wi-Fi/有线网络，用于处理“Wi-Fi 只有局域网、没有互联网”的情况。

## 5. 连接状态机

### 5.1 连接流程

```text
用户点击连接
  → 标准化 endpoint
  → 创建 connectionAttempt
  → 默认路由 GET /api/health
  → 失败时绑定 Wi-Fi 再试一次
  → 健康检查成功
  → 发送默认舅机角度
  → connected = true 并切换到竖屏操控屏
  → cameraReady 为 true 时开始画面刷新
```

摄像头或舅机初始化失败不会把已成功的 HTTP 连接误判为断网。

### 5.2 `connectionAttempt`

每次连接、断开、页面消失或连接丢失都会更新尝试号。异步请求返回时会检查自己是否还属于当前尝试。

这可以防止：

- 用户已经断开，旧的健康检查才返回并错误地显示“已连接”；
- 新连接已建立，旧清理任务却释放了新的网络绑定。

### 5.3 页面生命周期

- `aboutToAppear()`：复位页面状态和 API 地址；
- `onPageHide()`：如果正在连接或已连接，进入安全断开；
- `aboutToDisappear()`：取消定时器、停止控制、尝试停车并释放网络。

## 6. 移动控制为什么需要续期

### 6.1 按下

`GameJoystick` 识别到摇杆动作，或旋转功能键收到 `TouchType.Down` 后调用 `beginMove()`：

1. 立即发送一次 `move`；
2. 启动约 300 ms 的定时器；
3. 持续发送同一动作的新序号。

### 6.2 松开或取消

`TouchType.Up` 和 `TouchType.Cancel` 都会进入 `endMove()`：

1. 立即停止续期定时器；
2. 使旧的移动会话失效；
3. 经过 40 ms 方向切换缓冲后发送 `stop`。

40 ms 缓冲用于减少用户从一个方向快速滑到另一个方向时的多余停车，但 `STOP`、断开和页面生命周期不依赖这个缓冲。

### 6.3 失败处理

连续移动请求失败达到阈值后，App 会：

- 停止续期；
- 清除活动动作；
- 停止摄像头刷新；
- 显示安全离线；
- 依赖车端 0.9 秒看门狗停车。

## 7. HTTP 协议

路由在 `constants/AppConstants.ets` 的 `ApiRoutes` 中统一定义。

| 方法 | 路由 | 用途 |
| --- | --- | --- |
| GET | `/api/health` | API 版本和摄像头状态 |
| GET | `/api/camera/frame` | JPEG 画面 |
| GET | `/api/camera/captures` | 按时间倒序列出最多 200 张照片 |
| GET | `/api/camera/captures/{filename}` | 读取一张已保存的 JPEG |
| POST | `/api/control/move` | 移动 |
| POST | `/api/control/stop` | 停车 |
| POST | `/api/control/servo` | 舅机 |
| POST | `/api/camera/capture` | 车端截图 |

### 7.1 移动 JSON

```json
{
  "action": "forward",
  "speed": 35,
  "degree": 1.1,
  "sequence": 1727000000001
}
```

`CarAction` 枚举：

| App 按键 | 值 |
| --- | --- |
| 前进 | `forward` |
| 后退 | `backward` |
| 左转 | `left` |
| 右转 | `right` |
| 左平移 | `shift_left` |
| 右平移 | `shift_right` |
| 逆时针旋转 | `spin_left` |
| 顺时针旋转 | `spin_right` |

### 7.2 停车 JSON

```json
{
  "sequence": 1727000000002
}
```

### 7.3 舅机 JSON

```json
{
  "vertical": 90,
  "horizontal": 65,
  "sequence": 1727000000003
}
```

### 7.4 序号

`nextCommandSequence()` 选择“上次序号 + 1”和 `Date.now()` 中较大的一个，从而保证同一 App 会话内单调增长。

车端会拒绝迟到的旧指令，防止旧 `move` 在新 `stop` 后重新让车辆动起来。

## 8. 参数和限制

`AppConstants.ets` 是 App 侧单一配置入口：

| 项目 | 当前值 |
| --- | --- |
| 默认地址 | `http://192.168.149.1:8080`（手机连接车载热点时） |
| 默认速度 | 35 |
| 速度范围 | 25–60 |
| 默认舅机 | 90° / 65° |
| 垂直角度 | 20–160° |
| 水平角度 | 0–180° |
| 转弯 `degree` | 1.1 |
| 连接超时 | 4000 ms |
| 读取超时 | 5000 ms |
| 移动续期 | 300 ms |
| 画面刷新 | 350 ms |
| 方向切换缓冲 | 40 ms |

如果修改协议限制，必须同时检查车端 `ServerDefaults`。

## 9. 网络权限和 HTTP

`entry/src/main/module.json5` 声明：

```text
ohos.permission.INTERNET
ohos.permission.GET_NETWORK_INFO
```

`entry/src/main/resources/base/profile/network_config.json` 允许 Network Kit 访问局域网明文 HTTP。这是因为小车当前在受信任的私有局域网中使用 HTTP，没有 TLS 证书。

不要将车端 8080 端口映射到公网。当前 API 没有身份认证，只适合受信任的实验室局域网。

## 10. 错误处理与排查

### 10.1 App 已知网络错误

| 错误码 | App 提示 | 排查 |
| --- | --- | --- |
| `2300007` | 连接被拒绝 | 车端 8080 未监听或被防火墙拒绝 |
| `2300028` | 连接超时 | IP 错误、不在同网或路由不可达 |
| `2300997` | 系统阻止明文 HTTP | 检查 HAP 版本和 `network_config.json` |

### 10.2 标准排查流程

1. 确认手机当前 Wi-Fi。
2. 在手机浏览器打开完整 `/api/health`。
3. 确认 JSON 中 `ok` 为 `true`、`apiVersion` 为 `1.3.0`。
4. App 中只使用相同 IP 和端口。
5. 如浏览器成功、App 失败，记录 App 底部的完整错误码。
6. 确认安装的是最新 signed HAP，而不是手机中的旧包。

### 10.3 摄像头问题

`cameraReady: false` 时 App 会显示“控制就绪，摄像头未就绪”。这时：

- 方向、STOP、速度、平移、旋转和舅机仍然可用；
- App 不会自动启动画面定时器；
- 点击截图会显示摄像头未就绪；
- 应在车端排查摄像头，而不是修改 App 的连接判定。

## 11. 如何新增功能

### 11.1 新增纯 UI 功能

只涉及布局或显示时：

1. 在 `components/` 中修改或新建组件；
2. 通过 `@Prop` 接收状态；
3. 通过回调向 `Index` 上报交互；
4. 不要在按钮组件中直接创建 HTTP 请求。

### 11.2 新增 API

1. 先在两个仓库中定义请求和响应结构；
2. 车端在 `ApiRoutes` 和 Handler 中实现；
3. App 在 `ApiRoutes`、`CarModels`和 `CarApi` 中实现；
4. `Index` 管理状态和错误；
5. UI 只传递用户意图；
6. 增加 Python API 合约测试和 ArkTS 本地测试；
7. 构建 HAP，再做真机联调。

### 11.3 新增车辆动作

必须同时更新：

- 车端动作类；
- 车端 `ActionNames` / `CarRuntime.ACTIONS`；
- App `CarAction`；
- `DrivePanel` 的按键；
- API 合约测试；
- 本文档的指令表。

## 12. 构建和验收清单

### 12.1 离线

- [ ] `git diff --check` 无错误；
- [ ] HAP 构建成功；
- [ ] 地址标准化测试通过；
- [ ] App 与车端路由、JSON 字段和限制一致。

### 12.2 真机

- [ ] 手机浏览器能打开 `/api/health`；
- [ ] App 能连接；
- [ ] 摄像头不可用时仍能控制底盘；
- [ ] 按住移动、松手停车；
- [ ] `STOP` 可用；
- [ ] App 进入后台后停车；
- [ ] 断 Wi-Fi 后车端看门狗停车；
- [ ] 舅机角度和复位方向正确；
- [ ] 如启用摄像头，预览和截图正常。

离线构建成功不等于真车联调成功。文档、提交记录和验收报告中应明确区分两者。
