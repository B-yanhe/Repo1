# DeepSeek Harness 桌面启动器

双击桌面上的 **DeepSeek Harness** 快捷方式即可：

1. 后台（无任何黑框闪现）启动 `dsh web` 服务；
2. 单独弹出一个浏览器窗口（Edge/Chrome 的“应用模式”，没有标签栏和地址栏，像桌面软件一样）；
3. 命令提示符 / 控制台窗口始终在后台隐藏运行，不打扰你。

## 文件说明

| 文件 | 作用 |
| --- | --- |
| `dsh-web.vbs` | 快捷方式真正指向的文件。用 `wscript` + 隐藏窗口运行 PowerShell，所以连一瞬间的黑框都不会出现。 |
| `dsh-web.ps1` | 主体逻辑：复用或启动服务、等待就绪、打开窗口、出错时弹提示框。 |
| `install-shortcut.ps1` | 创建/删除桌面快捷方式（移动过本文件夹后重新运行一次即可）。 |
| `dsh-niang.ico` | 快捷方式图标：鲸鱼娘（素材取自 `dsh-whale-widget-bowl` 的 `DSniang1.png`），圆角方形。 |
| `make-icon.js` | 重新生成图标；`node make-icon.js <sharp目录> <源图.(svg\|png)> <输出.ico>`，SVG 走蓝底白鲸、位图走圆角裁切。 |
| `brand-title-plugin/` | 窗口标题插件的源码（已安装到 `$DSH_HOME\profiles\node_modules\dsh-brand-title`）。 |

## 窗口标题

应用窗口标题栏原本是 `<会话标题> — DeepSeek Harness`。`brand-title-plugin` 把浏览器标题
固定成 **DeepSeek Harness**，所以标题栏从今往后只显示产品名。

- 插件的挂载行写在 `$DSH_HOME\profiles\web\cordis.patch.yml`（Web profile 配了
  `patchReload: live`，改完**刷新页面**即生效，不需要重启服务）；
- 源码在 `brand-title-plugin/`，安装位置 `$DSH_HOME\profiles\node_modules\dsh-brand-title`
  （profile 共享解析根，不受 pnpm 管理，`dsh plugin add` 不会清掉它）；
- 卸载：删掉 `cordis.patch.yml` 末尾那三行 `- insert:` / `- id: brand-title` /
  `name: dsh-brand-title`，刷新页面即可。

## 快捷方式的指向

- 目标：`C:\Windows\System32\wscript.exe "G:\DSH\1\dsh-launcher\dsh-web.vbs"`
- 起始位置：`G:\DSH\1\dsh-launcher`
- 图标：`dsh-niang.ico`

移动文件夹后运行一次：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-shortcut.ps1
```

删除快捷方式：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-shortcut.ps1 -Remove
```

## 行为细节

- **端口 `3080`**：浏览器登录 cookie 绑定「主机 + 端口」，所以端口保持固定，30 天内再打开都不用重新登录。
- **已经很在运行的服务会被复用**：如果 `3080` 上已有服务在监听，快捷方式只把窗口打开，不会另起一个服务（第二个服务也无法绑定同一端口）。
- **首次启动**：脚本从服务输出的日志里取出官方打印的带 token 的地址（`http://127.0.0.1:3080/?token=...`），浏览器访问后会自动换取 cookie 并跳转到干净的 `/`。
- **日志**：`%LOCALAPPDATA%\DeepSeekHarness\dsh-web.log`（服务的全部输出）。
- **工作目录**：新会话的默认工作区，当前设为 `G:\DSH\1`（见 `dsh-web.ps1` 顶部的 `$Workspace`）。

## 手动使用 / 排查

```powershell
# 正常启动（会弹窗口）
powershell -NoProfile -ExecutionPolicy Bypass -File dsh-web.ps1

# 诊断模式：不打开浏览器，只打印解析到的地址（失败时打印原因而不是弹框）
powershell -NoProfile -ExecutionPolicy Bypass -File dsh-web.ps1 -NoOpen

# 以普通浏览器标签页打开，而不是独立窗口
powershell -NoProfile -ExecutionPolicy Bypass -File dsh-web.ps1 -BrowserTab

# 停止后台服务
powershell -NoProfile -ExecutionPolicy Bypass -File dsh-web.ps1 -Stop

# 换端口 / 换工作目录
powershell -NoProfile -ExecutionPolicy Bypass -File dsh-web.ps1 -Port 3099 -Workspace G:\proj
```

### 常见问题

- **弹框说找不到 CLI**：`dsh` 目前只存在于 npx 缓存里（`@deepseek-ai/dsh`）。先执行一次
  `npx -y @deepseek-ai/dsh@latest web` 让缓存重新生成；脚本会在
  `%LOCALAPPDATA%\npm-cache\_npx`、`%APPDATA%\npm-cache\_npx`、`%APPDATA%\npm\node_modules`
  下自动搜索 `@deepseek-ai\dsh\lib\bin.js`。也可以用环境变量 `DSH_LAUNCH_BIN`
  直接指定该文件的完整路径。
- **窗口里显示 401 Unauthorized**：浏览器没有该端口的登录 cookie。用 `-NoOpen` 查看日志里的
  带 token 地址，手动访问一次即可换取 cookie。
- **端口 3080 被别的程序占用**：快捷方式会把该地址当成本机 GUI 直接打开。若确实冲突，用
  `-Port <其它端口>` 启动，或改掉 `dsh-web.ps1` 顶部的 `$Port`。
