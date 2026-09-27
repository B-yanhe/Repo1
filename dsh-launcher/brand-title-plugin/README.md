# dsh-brand-title

把 DeepSeek Harness 浏览器窗口标题固定为产品名 **DeepSeek Harness**。

## 为什么需要它

`dsh-client-ui-layout` 的 `DocumentTitle` 会写：

```js
document.title = `${sessionTitle} — ${productTitle}`
```

所以应用窗口（Edge `--app=` 独立窗口）的标题栏会顶着当前会话标题，
例如「创建Deepseek快捷方式启动脚本 — DeepSeek Harness」。

## 它做什么

- 在 `document` 实例上定义自己的 `title` 访问器，让上层的写入变成空操作；
- 用 `MutationObserver` 盯着 `<head>`，任何直接改 `<title>` 元素的行为都会被改回来；
- 插件卸载时恢复原状。

## 安装位置

本包放在 `$DSH_HOME/profiles/node_modules/dsh-brand-title`（profile 共享解析根），
不归 pnpm 管理，因此 `dsh plugin add` 之类的安装不会把它清掉。

挂载行写在 `$DSH_HOME/profiles/web/cordis.patch.yml`：

```yaml
- insert:
    - id: brand-title
      name: dsh-brand-title
```

Web profile 配了 `patchReload: live`，所以改完 patch **刷新页面**即可生效，不用重启服务。

## 卸载

删掉 `cordis.patch.yml` 里那两行（`- insert:` 与其下的 `- id: brand-title`），刷新页面。
