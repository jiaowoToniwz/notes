# 系统级轻量信息存储方案（对标 Chrome Notes）

> 目标：在系统任意程序里都能快速存一些信息（随手记、收藏文字），
> 常驻内存尽量小（控制在 5~15MB），数据为本地纯文本文件，可搜索、可同步。

## 一、技术选型

**AutoHotkey v2（AHK v2）** —— Windows 原生脚本工具，免费开源。

| 方案 | 常驻内存 | 结论 |
|---|---|---|
| AHK v2 脚本 | 5~15MB | **采用** |
| Windows 自带便笺 | ~40MB | 备选（零代码、可云同步） |
| Python/PowerShell 常驻 | 40~50MB | 不采用（内存偏大） |
| Chrome Notes 扩展 | 空闲 0MB | 仅浏览器内可用，可并存 |

## 二、功能设计（3 个热键 + 托盘菜单）

| 热键 | 功能 | 说明 |
|---|---|---|
| `Ctrl+Alt+N` | 快速笔记 | 黄色便签风格窗口，输入后 Ctrl+Enter 或点「保存」追加到 notes.md，自动带时间戳；Esc 取消 |
| `Ctrl+Alt+M` | 笔记列表 | 主页面：搜索（实时过滤时间+内容）/ 查看 / 新增 / 编辑 / 删除 / 刷新 |
| `Ctrl+Alt+C` | 收藏选中文字 | 取当前程序选中文本 → 追加到 notes.md，记录来源程序 |
| 托盘图标 | 打开列表 / 打开笔记 / 打开目录 / 设置 / 退出 | 右键菜单；双击托盘图标打开列表 |
| 托盘 → 设置 | 修改三个全局热键 + 笔记存放路径 | 热键录入组合键（须含 Ctrl/Alt/Shift，F 键除外）→ 立即生效并写入 notes.ini；笔记路径可输入或浏览选择（绝对路径），保存后笔记改存新位置，可选复制旧笔记，重启后仍生效 |

只做"存"和"看"两件事，不做复习、不建单词本等学习类功能。

## 三、数据存储（目录 = 脚本/exe 所在位置，可移植）

```
<脚本目录>\           ← 例：D:\Notes（拷到任何位置/机器都能用）
├── agents.md      ← 本方案文档
├── notes.ahk      ← AHK v2 主脚本
├── notes.exe      ← 编译版（免装 AHK 环境，日常运行优先用这个）
├── notes.md       ← 主笔记：按时间追加的 Markdown（默认在本目录，可在设置窗口改到任意路径）
├── notes.ini      ← 配置文件（固定随程序）：[Hotkeys] quick/main/copy + [Settings] dir=笔记目录；可删，删后恢复默认
└── README.md      ← 用户使用/安装/编译说明
```

- 纯文本格式，记事本/VS Code/WPS 均可打开
- 可被 Everything / grep 全文搜索
- 目录放入坚果云/OneDrive 即可多端同步
- 无数据库、无依赖，拷走整个目录即完成迁移
- **可移植**：配置文件固定随程序（`CFG_FILE := A_ScriptDir "\notes.ini"`）；笔记目录默认 = 脚本/exe 所在目录（`NOTES_DIR := A_ScriptDir`），设置窗口可改，改后写入 `[Settings] dir=`，重启仍生效

## 四、当前实现要点（notes.ahk）

- `#Requires AutoHotkey v2.0`，无第三方库，约 530 行
- 启动时自动创建 notes.md；三个 GUI 窗口（快速笔记、笔记列表、笔记详情）均 `+AlwaysOnTop`，关闭只隐藏不销毁，热键再按恢复
- 快速笔记/笔记详情窗口 `+Resize +MinSize420x300 / +MinSize460x340`：可拖拽调整大小、可最大化，Edit 控件通过 Size 回调跟随缩放（注意：`+MaxSize` 无参会把窗口锁死为当前尺寸，不可用）
- 写入用 `FileAppend`（UTF-8，追加模式）
- 收藏选中文本走剪贴板：备份 → 置空 → 发 Ctrl+C → ClipWait 取回 → 恢复原剪贴板
- **所有 MsgBox 必须带 `0x40000`（MB_TOPMOST）**：列表/详情窗口是 AlwaysOnTop，不带置顶的确认弹窗会被主窗口盖住，表现为"点了没反应"（本次已修复 6 处）
- 列表解析 `ParseNotes()`：按 `## yyyy-MM-dd HH:mm` 切分，删除/编辑后整体重写 notes.md
- **热键动态注册（设置窗口）**：启动时 `InitHotkeys()` 从 notes.ini 读键名（`[Hotkeys] quick/main/copy`）并 `Hotkey(键, (*) => 函数)` 注册；`Hotkey()` 无 Delete 选项——改键时旧键用 `Hotkey(旧键, , "Off")` 禁用，新键用 `Hotkey(新键, 回调, "On")` 注册（"On" 必须放第三参数，否则已禁用键不会重新启用）；回调必须能接受 1 个参数，统一用 `(*) =>` 包装
- 设置窗口录入：**OnMessage(0x100)** 拦截 WM_KEYDOWN（v2 的 OnEvent 不支持 KeyDown 事件），配合 `Gui.FocusedCtrl` 判断聚焦输入框、`GetKeyState` 检测 Ctrl/Alt/Shift、`KeyNameForVK` 把虚拟键码转键名；Esc 清空输入框；设置窗口打开期间禁用三个热键防误触；保存时校验非空、不重复，失败回滚旧键
- **GUI 布局铁律：每个控件必须显式指定 x 和 y**（AHK v2 省略 x 会跟随上一个控件左缘形成阶梯，省略 y 会垂直堆叠错位）；设置窗口用固定网格：标签 x14、输入框 x102 w180、浏览按钮 x290、按钮行 y262 齐平
- **笔记路径设置**：设置窗口第 4 行「笔记路径」Edit + 浏览按钮；**浏览用 IFileDialog 而非 DirSelect**（SHBrowseForFolder 把起始目录当树根——传当前路径树里只有该目录、传空又不定位，无法两者兼得）；IFileDialog 方案：`ComObject(CLSID_FileOpenDialog, IID_IFileDialog)` + `ComCall`，`SetOptions(FOS_PICKFOLDERS|FOS_FORCEFILESYSTEM)`、`SetTitle`、`SHCreateItemFromParsingName` 构造 IShellItem 后 `SetFolder` 定位到当前路径（不锁死导航）、`Show(owner)`、`GetResult` + `GetDisplayName(SIGDN_FILESYSPATH)` 取路径；**弹窗遮挡坑**：任何系统对话框都不是置顶窗口，弹窗前必须 `WinSetAlwaysOnTop(0, "ahk_id " 设置窗口)`，返回后再恢复置顶；**alpha 版坑**：DllCall 无 `"GUID"` 参数类型（用手工 `Buffer(16)`+NumPut 构造 IID）、无 `BufferAlloc`/`VarSetCapacity`（用 `Buffer(n)`）、无 `SendRaw`（用 `SendText`）；整段 try/catch 失败回退 `DirSelect("", 3, ...)`（完整树但不定位）；保存时校验绝对路径（`^[A-Za-z]:` 或 UNC `^\\\\`）、`DirCreate` 试建失败即中止；路径变化时询问是否 `FileCopy` 旧 notes.md 到新位置（YesNo 弹窗），应用后更新全局 `NOTES_DIR/NOTES_FILE` 并 `RefreshList()`；最后写 `[Settings] dir=`——**可移植性铁律：dir 只有指向自定义路径（≠程序目录）时才写入，等于程序目录或目录失效（被删/换机）时启动自动 `IniDelete` 清理并回退 `A_ScriptDir`**（曾因残留 `dir=D:\Notes` 导致整目录拷走后 notes.md 仍写到旧位置；已修复并三场景验证）

## 五、编译为 exe（免安装分发）

### 方式一：Ahk2Exe（官方工具）

```
"C:\Program Files\AutoHotkey\v2\Compiler\Ahk2Exe.exe" /in "D:\Notes\notes.ahk" /out "D:\Notes\notes.exe" /base "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /compress 1
```

- 若 Compiler 目录缺失 UPX.exe，`/compress 1` 会卡死，去掉该参数即可
- 注意：曾遇到 Ahk2Exe 启动后无窗口、CPU 0、挂死（原因未明，重下新版也可能无效），此时用方式二

### 方式二：资源注入手工编译（可靠兜底）

原理（从 AHK v2 源码确认）：编译 exe = AutoHotkey64.exe 副本 + 脚本写入其 **RT_RCDATA 资源（ID=1）**；运行时启动器检测到该资源即加载资源内脚本，不再读取同名 .ahk 文件。

```powershell
Copy-Item 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' 'D:\Notes\notes.exe' -Force
# P/Invoke kernel32：BeginUpdateResource → UpdateResource(h, 类型=10, 名称=1, 语言=0x0409, 脚本UTF-8无BOM字节) → EndUpdateResource
```

- 效果与 Ahk2Exe 等效：单进程、运行内存约 12MB
- 注意：资源注入会破坏 AutoHotkey64.exe 的数字签名，属预期

### 编译铁律（本次事故教训）

1. **先确认 notes.ahk 已保存最新修改**，再编译——曾发生 exe 比 ahk 旧 20 分钟，修复没进 exe，弹窗依然被遮
2. **运行中的 notes.exe 会锁输出文件**，编译前先杀进程：`Stop-Process -Name notes -Force`
3. **编译后验证修复真的进去了**：`grep -a -c "0x40000" notes.exe`（应等于 .ahk 中的处数）
4. 验证 exe 行为：运行 → 触发删除 → 检查确认框窗口 WS_EX_TOPMOST 标志（GetWindowLong -20 与 0x8）

## 六、开机自启

1. `Win+R` → `shell:startup` 打开启动文件夹
2. 建快捷方式，目标指向 `notes.exe`（编译版）或 `"C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" "D:\Notes\notes.ahk"`（脚本版）
3. 目录位置变化**无需任何修改**：`NOTES_DIR := A_ScriptDir`，数据自动跟随脚本/exe 所在目录

## 七、内存优化要点

- 脚本只做事件响应（热键触发），不做任何轮询
- 不加载第三方库；GUI 窗口平时隐藏不销毁
- 托盘图标保留（提供菜单入口），必要时可 `#NoTrayIcon` 再省一点

## 八、维护与备份

- 数据即文件：每日/每周把 D:\Notes 拷到备份盘，或用网盘同步文件夹（若设置了自定义笔记路径，连同该目录一起备份）
- 修改热键：**托盘右键 → 设置**，录入组合键后保存即生效（存 notes.ini，重启仍生效）；修改笔记路径：设置窗口「笔记路径」输入或浏览选择，保存时可选复制旧笔记到新位置；也可手改 notes.ini 的 `[Hotkeys] quick/main/copy` 或 `[Settings] dir`；脚本版改完托盘 Reload，exe 版改完必须**重新编译**（见第五节铁律）
- 排错：托盘右键 → 退出后重新运行；看 Windows 事件查看器中的脚本报错

## 九、风险与注意事项

- 全局热键可能与个别软件快捷键冲突（可在托盘 → 设置中换键）
- 收藏选中文字依赖剪贴板，复制瞬间其它程序若同时在复制会有竞争（概率极低）
- **AlwaysOnTop 窗口的遮挡问题**：任何新弹窗（MsgBox / 自绘窗口）都必须置顶，否则被列表窗口盖住
- 建议与 Chrome Notes 并存：浏览器内用扩展，浏览器外用 AHK，互不干扰
