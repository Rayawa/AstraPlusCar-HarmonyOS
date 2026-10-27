# AstraPlusCar-HarmonyOS

[English](README.md) | 简体中文

支持驾驶控制、相机预览、雷达状态与截图的 HarmonyOS 小车控制端。

## 项目概述

应用通过局域网 HTTP API 连接小车，提供触摸与语音控制、视频预览、近距离提示及应用私有图库。运动指令受连接和画面状态约束，松手、断联或退后台会结束当前运动；设备服务由 AstraPlusCar-device 单独维护。

## 技术栈与依赖

ArkTS、ArkUI/HDS、HarmonyOS API 23、OHPM、Hvigor，使用平台 HTTP、媒体、语音和触觉能力。entry 未声明第三方运行时依赖。车辆功能需要兼容的小车服务和局域网。

## 文件结构

- `entry/src/main/ets/` — ArkTS 应用代码
- `entry/src/main/resources/` — 资源与路由
- `AppScope/` — 应用配置
- `build-profile.example.json5` — 构建配置模板
- `oh-package.json5` — 包依赖
- `docs/` — 接口及开发说明
- `car_server/` — 保留的服务端辅助文件
- `tools/` — 开发工具

## 快速上手

1. 使用 DevEco Studio 打开仓库根目录，并安装 `build-profile.example.json5` 指定的 SDK。
2. 将模板复制为 `build-profile.json5`，恢复 OHPM 依赖；如需真机安装，在本地配置签名。
3. 选择 `entry` 模块和兼容设备或模拟器，在 IDE 中构建运行。证书及机器路径不进入版本控制。

启动兼容的小车服务，将手机与小车接入同一网络，在连接页填写 `http://<vehicle-host>:8080`。先确认实时画面和传感器状态，再测试运动。接口说明参见[设备端仓库](https://github.com/Rayawa/AstraPlusCar-device)。
