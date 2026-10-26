# Dive Harder Patch

[English](README.md) | **中文**

Helldivers 1（Steam，2015）的非官方 Lua 模组：已攻破种族重新开放、隐藏目标直接显示、
可选的敌人血量档位，并把 QoL 的选项（作者：SomeDoggo）和自己的开关统一收进暂停菜单里的 **MOD SETTINGS** 页。

模组以独立启动包（`resource_packages/boot_dh`）的形式生效：不修改游戏文件，也不修改
QoL 的文件。安装只是把 `settings.ini` 里的 `boot_package` 指向新的启动包，卸载再指回原版。

当前版本：**0.1.0**

## 功能

| 功能 | 说明 | 默认 |
| --- | --- | --- |
| 已攻破种族解锁 | 已被全服攻破的种族重新出现在战役地图上，可以选星球、下任务；前线放在第 10 星区 | ON |
| 隐藏目标显示 | 黄色问号任务从开局就按真实图标显示，不用侦察无人机 | OFF |
| 敌人血量档位 | `ENEMY HEALTH`：`OFF` / `HARD`（总血量 ×1.5）/ `HELLDIVE`（×2） | OFF |
| HUD ping | 在玩家 ID 卡片下方外沿、左对齐画 `PING: xx.xxms` | OFF |
| ping 窗口 | 取最近 3 / 5 / 10 个样本的均值（越小越灵敏，越大越平滑） | 5 |
| 好友列表刷新 | 进多人菜单筛选时自动刷新一次房间列表，不用再手动按刷新才看到 Host 信息 | 自动 |
| 结算页聊天字体 | 修复 QoL 的 `display_player_text` 在结算 / 星球奖励页不生效的问题 | 跟随 QoL |
| 版本号 | 主菜单 QoL 版本在上，`Dive Harder: v.0.1.0` 在下 | — |
| 文案 | 选项名统一大写、去掉下划线，QoL未翻译的 `LOC:xxx` 显示成可读键名 | — |

### MOD SETTINGS

暂停菜单（主菜单 / 船上 / 任务中）在 `SETTINGS` 下面多出一行，点进去整页替换成：

- **QoL** 组（只有装了 QoL 才显示）；
- **DIVE HARDER** 组（5 项）；
- `APPLY CHANGES`。

## 需要什么

- Steam 正版 Helldivers 1（Windows x64）。
- QoL 0.29.2 是**可选**的——安装脚本会自动识别并选对应的载荷。
- 从源码构建需要 Python 3.8+、LuaJIT 2.0.3，以及一份本机游戏安装。

## 安装

1. 解压发布包；
2. 双击 `install.bat`：脚本自动找游戏目录，按 `9cf71054ea26dddf` 的 SHA256 判断纯净原版 /
   QoL，复制对应载荷，备份 `settings.ini`，并把 `boot_package` 指向
   `resource_packages/boot_dh`；
3. 完全退出游戏进程再启动。

游戏里：按 `ESC`，打开 `SETTINGS` 下面那一行（`MOD SETTINGS`），改完在 `APPLY CHANGES`
上确认。

卸载：双击 `revert.bat`，`settings.ini` 从备份恢复，QoL 原样回来。游戏的 `9e13…` / `9cf…`
从没被改过。

## 从源码构建

### 准备基座

`vendor/base_csm.lua` 是 `lua/character_states/character_state_machine` 的反编译结果，
属于游戏代码。

```powershell
python tools/extract_base.py                 # -> build\cs_orig.bc
luajit-decompiler-v2.exe build\cs_orig.bc    # 反编译结果写到它自己的 output\ 目录
# 把那份 .lua 另存为 vendor/base_csm.lua
```

`build.py` 会把它重新编译，必须和游戏启动包里的字节码逐字节一致才肯构建。

### 构建依赖

- Python 3.8+
- **LuaJIT 2.0.3**（本作 Lua 运行时；其它版本的字节码不兼容）
- 一份 Helldivers 安装，`contents` 里有 `9e13b2414b41b842.orig`（纯净原版启动包备份）
- QoL 版还需要 QoL 的启动包备份 `9e13b2414b41b842.qol_boot_backup_*`（旧名
  `.enemy_stats_backup_*` 也认；QoL 安装器或本模组旧安装包会留下）

### 构建

```powershell
python tools/build.py
# 或者显式指定路径
python tools/build.py --contents "E:\Steam\steamapps\common\Helldivers\contents" --luajit "C:\luajit\luajit.exe"
```

输出 `dist/dive_harder_vanilla.bin` 和 `dist/dive_harder_qol.bin`，并打印 SHA256 供安装脚本校验。

### 打包发布

```powershell
pwsh -File tools/package.ps1                            # 构建 + 组装 + 装到本机 + 打 zip
pwsh -File tools/package.ps1 -NoInstall                 # 只构建和打包
```

## 测试

离线自测，用假组件跑钩子，不需要开游戏：

```powershell
luajit tests\test_health.lua
luajit tests\test_menu.lua
luajit tests\test_ping.lua
```

每个脚本都会打印每条断言，最后输出 `all … tests passed`；失败返回非零退出码。

## 目录结构

```
lua/
  dive_harder.lua        全部钩子代码
  ping_hud.lua           HUD ping / ping 窗口 / friends 刷新
installer/
  install.ps1, install.bat
  revert.ps1,  revert.bat
  INSTALL.txt            随发布包分发的玩家说明
tools/
  bundle.py              启动包读写 + murmur64a
  build.py               拼装 Lua、编译、生成两个载荷
  extract_base.py        从启动包里取出原版字节码
  package.ps1            构建 + 组装 + 安装 + 打包
tests/                   离线自测
```

## 已知限制

- 已攻破种族只是「客户端重新开放 + 前线在第 10 星区」，不会真的推进服务器战役；母星
  （boss planet）仍走本地流程。
- 隐藏目标、敌人血量以主机为准。
- 敌人血量在出生时放大，改档位只影响之后刷出来的敌人。
- QoL 更新后需要用新的 QoL 启动包重新生成 QoL 载荷；安装脚本按 `9cf` 哈希认版本，
  未知版本会中止。

## 许可

MIT，见 [LICENSE](LICENSE)。HELLDIVERS 及其素材版权归 Sony Interactive Entertainment /
Arrowhead Game Studios 所有，本项目非官方、与他们无关。QoL 是SomeDoggo的作品。
`vendor/base_csm.lua` 由玩家自己的游戏安装反编译得到，不在本仓库中，本仓库也不分发任何
游戏素材。
