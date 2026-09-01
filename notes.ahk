#Requires AutoHotkey v2.0

NOTES_DIR := A_ScriptDir  ; 数据目录（默认 = 脚本/exe 所在目录，可在设置窗口修改）
CFG_FILE := A_ScriptDir "\notes.ini"  ; 配置文件固定随程序：记录数据目录与热键
try {
    d := IniRead(CFG_FILE, "Settings", "dir", "")
    if d != "" {
        NOTES_DIR := NormPath(d)
    }
}
catch {
}
NOTES_FILE := NOTES_DIR "\notes.md"
A_FileEncoding := "UTF-8"

; 启动时确保目录和文件存在
DirCreate(NOTES_DIR)
EnsureNotesFile()

; 托盘菜单
A_TrayMenu.Delete()
A_TrayMenu.Add("笔记列表", (*) => MainList())
A_TrayMenu.Add("打开笔记", (*) => Run(NOTES_FILE))
A_TrayMenu.Add("打开目录", (*) => Run(NOTES_DIR))
A_TrayMenu.Add("设置", (*) => SettingsWindow())
A_TrayMenu.Add()
A_TrayMenu.Add("退出", (*) => ExitApp())
A_TrayMenu.Default := "笔记列表"  ; 双击托盘图标打开笔记列表

; ================= 全局热键配置（启动时注册，可在设置窗口修改） =================
DEF_KEYS := ["^!n", "^!m", "^!c"]  ; 默认键：快速笔记 / 笔记列表 / 收藏文字
cfgQuick := ""  ; 快速笔记
cfgMain := ""   ; 笔记列表
cfgCopy := ""   ; 收藏文字

ReadIniKey(key, def) {
    global CFG_FILE
    try {
        return IniRead(CFG_FILE, "Hotkeys", key, def)
    }
    catch {
        return def
    }
}

TryRegHotkey(cfg, def, cb) {
    try {
        Hotkey(cfg, cb)
        return cfg
    }
    catch {
    }
    try {
        Hotkey(def, cb)  ; 配置键被占用时退回默认键
        return def
    }
    catch {
        return ""
    }
}

InitHotkeys() {
    global cfgQuick, cfgMain, cfgCopy, DEF_KEYS
    cfgQuick := ReadIniKey("quick", DEF_KEYS[1])
    cfgMain := ReadIniKey("main", DEF_KEYS[2])
    cfgCopy := ReadIniKey("copy", DEF_KEYS[3])
    cfgQuick := TryRegHotkey(cfgQuick, DEF_KEYS[1], (*) => QuickNote())
    cfgMain := TryRegHotkey(cfgMain, DEF_KEYS[2], (*) => MainList())
    cfgCopy := TryRegHotkey(cfgCopy, DEF_KEYS[3], (*) => CopySelection())
}
InitHotkeys()

; ================= 设置窗口（热键 + 笔记路径） =================
SettingsWin := ""
SettingsEdits := []
SettingsPathEdit := ""
SettingsOrig := []
SettingsCbs := [(*) => QuickNote(), (*) => MainList(), (*) => CopySelection()]
OnMessage(0x100, SettingsKeyMsg)  ; 拦截按键用于录入快捷键

SettingsWindow() {
    global SettingsWin, SettingsEdits, SettingsPathEdit, SettingsOrig, cfgQuick, cfgMain, cfgCopy, NOTES_DIR
    vals := [cfgQuick, cfgMain, cfgCopy]
    SettingsOrig := vals
    for k in SettingsOrig
        try Hotkey(k, , "Off")  ; 打开/重开期间禁用热键，防止录入时误触发
    if SettingsWin {
        for i, ed in SettingsEdits
            ed.Value := ToFriendly(vals[i])
        SettingsPathEdit.Value := NOTES_DIR
        SettingsWin.Show()
        return
    }
    SettingsWin := Gui("+AlwaysOnTop", "设置")
    SettingsWin.MarginX := 14
    SettingsWin.MarginY := 14
    SettingsWin.SetFont("s10", "Segoe UI")
    names := ["快速笔记", "笔记列表", "收藏文字"]
    ys := [14, 52, 90]
    for i, name in names {
        SettingsWin.Add("Text", "x14 y" (ys[i] + 3) " w80", name "：")
        ed := SettingsWin.Add("Edit", "x102 y" ys[i] " w180 h24 ReadOnly", ToFriendly(vals[i]))
        SettingsEdits.Push(ed)
    }
    SettingsWin.Add("Text", "x14 y128 w400 c666666", "点击输入框后直接按组合键（须含 Ctrl/Alt/Shift）")
    SettingsWin.Add("Text", "x14 y179 w80", "笔记路径：")
    SettingsPathEdit := SettingsWin.Add("Edit", "x102 y176 w180 h24", NOTES_DIR)
    SettingsWin.Add("Button", "x290 y176 w64 h24", "浏览…").OnEvent("Click", SettingsBrowseDir)
    SettingsWin.Add("Text", "x14 y214 w320 c666666", "笔记（notes.md）存放目录，保存后立即生效")
    SettingsWin.Add("Button", "x14 y262 w80 h24", "恢复默认").OnEvent("Click", SettingsReset)
    SettingsWin.Add("Button", "x102 y262 w80 h24", "保存").OnEvent("Click", SettingsSave)
    SettingsWin.Add("Button", "x190 y262 w80 h24", "取消").OnEvent("Click", SettingsCancel)
    SettingsWin.OnEvent("Close", SettingsCancel)
    SettingsWin.OnEvent("Escape", SettingsCancel)
    SettingsWin.Show()
}

SettingsBrowseDir(*) {
    global SettingsWin, SettingsPathEdit
    ; 弹窗前临时取消置顶，否则系统对话框会被置顶的设置窗口盖住（AlwaysOnTop 遮挡铁律）
    WinSetAlwaysOnTop(0, "ahk_id " SettingsWin.Hwnd)
    sel := ""
    try {
        ; IFileDialog：完整目录树 + 默认定位到当前笔记路径（DirSelect/SHBrowseForFolder 的起始目录会被当树根，无法两者兼得）
        fd := ComObject("{DC1C5A9C-E88A-4dde-A5A1-60F82A20AEF7}", "{42f85136-db7e-439c-85f1-e4075d135fc8}")
        ComCall(9, fd, "UInt", 0x20 | 0x40)          ; SetOptions: FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM
        ComCall(17, fd, "Str", "选择笔记存放目录")     ; SetTitle
        if SettingsPathEdit.Value != "" {
            item := 0
            ; alpha 版 DllCall 无 "GUID" 类型，手工构造 IShellItem 的 IID（43826d1e-e718-42ee-bc55-a1e261c37bfe）
            iid := Buffer(16)
            NumPut("UInt", 0x43826d1e, iid, 0)
            NumPut("UShort", 0xe718, iid, 4)
            NumPut("UShort", 0x42ee, iid, 6)
            NumPut("UChar", 0xbc, iid, 8)
            NumPut("UChar", 0x55, iid, 9)
            NumPut("UChar", 0xa1, iid, 10)
            NumPut("UChar", 0xe2, iid, 11)
            NumPut("UChar", 0x61, iid, 12)
            NumPut("UChar", 0xc3, iid, 13)
            NumPut("UChar", 0x7b, iid, 14)
            NumPut("UChar", 0xfe, iid, 15)
            hr := DllCall("shell32\SHCreateItemFromParsingName", "Str", SettingsPathEdit.Value, "Ptr", 0, "Ptr", iid, "Ptr*", &item)
            if hr = 0 && item {
                ComCall(12, fd, "Ptr", item)         ; SetFolder 定位到当前路径（不锁死导航）
                ObjRelease(item)
            }
        }
        if ComCall(3, fd, "Ptr", SettingsWin.Hwnd) = 0 {   ; Show
            result := 0
            if ComCall(20, fd, "Ptr*", &result) = 0 && result {  ; GetResult
                psz := 0
                if ComCall(5, result, "Int", 0x80058000, "Ptr*", &psz) = 0 && psz {  ; GetDisplayName(SIGDN_FILESYSPATH)
                    sel := StrGet(psz, "UTF-16")
                    DllCall("ole32\CoTaskMemFree", "Ptr", psz)
                }
                ObjRelease(result)
            }
        }
    } catch {
        sel := DirSelect("", 3, "选择笔记存放目录")  ; 兼容回退：完整目录树（不定位）
    }
    WinSetAlwaysOnTop(1, "ahk_id " SettingsWin.Hwnd)
    if sel != "" {
        SettingsPathEdit.Value := sel
    }
}

SettingsKeyMsg(wParam, lParam, msg, hwnd) {
    global SettingsWin, SettingsEdits
    if !SettingsWin || !WinActive("ahk_id " SettingsWin.Hwnd)
        return
    if wParam = 0x1B {  ; Esc 清空当前输入框
        fc := SettingsWin.FocusedCtrl
        if fc && HasVal(SettingsEdits, fc) {
            fc.Value := ""
            return 1
        }
        return
    }
    fc := SettingsWin.FocusedCtrl
    if !fc || !HasVal(SettingsEdits, fc)
        return
    keyName := KeyNameForVK(wParam)
    if keyName = ""
        return
    if GetKeyState("LWin") || GetKeyState("RWin") {
        TrayTip("不支持 Win 键", "设置", 2)
        return 1
    }
    mods := ""
    if GetKeyState("Ctrl") {
        mods .= "^"
    }
    if GetKeyState("Alt") {
        mods .= "!"
    }
    if GetKeyState("Shift") {
        mods .= "+"
    }
    if mods = "" && !RegExMatch(keyName, "^F\d+$") {
        TrayTip("快捷键需含 Ctrl/Alt/Shift 之一", "设置", 2)
        return 1
    }
    fc.Value := ToFriendly(mods keyName)
    return 1
}

KeyNameForVK(wParam) {
    if wParam >= 0x30 && wParam <= 0x39 || wParam >= 0x41 && wParam <= 0x5A {
        return Chr(wParam)
    }
    if wParam >= 0x60 && wParam <= 0x69 {
        n := wParam - 0x60
        return "Numpad" n
    }
    if wParam >= 0x70 && wParam <= 0x87 {
        n := wParam - 0x70 + 1
        return "F" n
    }
    if wParam = 0x6A {
        return "NumpadMult"
    }
    if wParam = 0x6B {
        return "NumpadAdd"
    }
    if wParam = 0x6D {
        return "NumpadSub"
    }
    if wParam = 0x6E {
        return "NumpadDot"  ; 小数点（NumpadDec 不是有效键名）
    }
    if wParam = 0x6F {
        return "NumpadDiv"
    }
    return ""
}

SettingsReset(*) {
    global SettingsEdits, SettingsPathEdit, DEF_KEYS
    for i, ed in SettingsEdits
        ed.Value := ToFriendly(DEF_KEYS[i])
    SettingsPathEdit.Value := A_ScriptDir
}

SettingsSave(*) {
    global SettingsEdits, SettingsPathEdit, SettingsWin, SettingsOrig, SettingsCbs, cfgQuick, cfgMain, cfgCopy, NOTES_DIR, NOTES_FILE
    newKeys := [FromFriendly(SettingsEdits[1].Value), FromFriendly(SettingsEdits[2].Value), FromFriendly(SettingsEdits[3].Value)]
    for i, k in newKeys {
        if k = "" {
            MsgBox("请为每项都设置快捷键", "设置", "T3 0x40000")
            return
        }
    }
    if newKeys[1] = newKeys[2] || newKeys[1] = newKeys[3] || newKeys[2] = newKeys[3] {
        MsgBox("三个快捷键不能相同", "设置", "T3 0x40000")
        return
    }
    newDir := NormPath(SettingsPathEdit.Value)
    if newDir = "" {
        MsgBox("请设置笔记存放路径", "设置", "T3 0x40000")
        return
    }
    if !RegExMatch(newDir, "^[A-Za-z]:") && !RegExMatch(newDir, "^\\\\") {
        MsgBox("笔记路径需为绝对路径，如 D:\MyNotes", "设置", "T3 0x40000")
        return
    }
    moved := newDir != NOTES_DIR
    if moved {
        try {
            DirCreate(newDir)
        }
        catch {
            MsgBox("无法创建目录：" newDir, "设置", "T3 0x40000")
            return
        }
        ; 迁移旧笔记放在热键注册之前：此后任何失败都不会留下"笔记消失"的中间状态
        oldFile := NOTES_FILE
        newFile := newDir "\notes.md"
        if FileExist(oldFile) && !FileExist(newFile) {
            if MsgBox("是否将现有笔记复制到新位置？`n" oldFile "`n→ " newFile, "笔记迁移", "YesNo 0x40000") = "Yes" {
                try {
                    FileCopy(oldFile, newFile)
                }
                catch {
                    MsgBox("复制笔记失败，已取消修改：`n" oldFile, "笔记迁移", "T3 0x40000")
                    return
                }
            }
        }
    }
    ; 先禁用全部旧键（交换键位场景必须按此顺序），再逐个注册新键
    for k in SettingsOrig
        try Hotkey(k, , "Off")
    for i, k in newKeys {
        try Hotkey(k, SettingsCbs[i], "On")  ; "On"：旧键被禁用过，注册时需重新启用
        catch {
            ; 回滚：清理已注册的新键，恢复全部旧键（含键位交换时按位置对应回调）
            for j, nk in newKeys
                if j <= i && !HasVal(SettingsOrig, nk)
                    try Hotkey(nk, , "Off")
            for j, ok in SettingsOrig
                try Hotkey(ok, SettingsCbs[j], "On")
            MsgBox("快捷键无效或已被占用：" SettingsEdits[i].Value, "设置", "T3 0x40000")
            return
        }
    }
    if moved {
        NOTES_DIR := newDir
        NOTES_FILE := newFile
        EnsureNotesFile()
        RefreshList()  ; 列表窗口按新路径刷新
    }
    try {
        IniWrite(newKeys[1], CFG_FILE, "Hotkeys", "quick")
        IniWrite(newKeys[2], CFG_FILE, "Hotkeys", "main")
        IniWrite(newKeys[3], CFG_FILE, "Hotkeys", "copy")
        IniWrite(NOTES_DIR, CFG_FILE, "Settings", "dir")
    }
    catch {
        TrayTip("配置写入失败（目录可能只读），本次设置重启后不保留", "设置", 3)
    }
    cfgQuick := newKeys[1]
    cfgMain := newKeys[2]
    cfgCopy := newKeys[3]
    SettingsWin.Hide()
}

SettingsCancel(*) {
    global SettingsWin, SettingsOrig, SettingsCbs
    for i, ok in SettingsOrig
        try Hotkey(ok, SettingsCbs[i], "On")  ; 重新启用旧键
    SettingsWin.Hide()
}

ToFriendly(hk) {
    out := ""
    if InStr(hk, "^") {
        out .= "Ctrl+"
    }
    if InStr(hk, "!") {
        out .= "Alt+"
    }
    if InStr(hk, "+") {
        out .= "Shift+"
    }
    if InStr(hk, "#") {
        out .= "Win+"
    }
    key := StrReplace(hk, "^", "")
    key := StrReplace(key, "!", "")
    key := StrReplace(key, "+", "")
    key := StrReplace(key, "#", "")
    if StrLen(key) = 1 && RegExMatch(key, "i)^[a-z]$")
        key := StrUpper(key)
    return out key
}

FromFriendly(s) {
    out := ""
    if RegExMatch(s, "i)Ctrl") {
        out .= "^"
    }
    if RegExMatch(s, "i)Alt") {
        out .= "!"
    }
    if RegExMatch(s, "i)Shift") {
        out .= "+"
    }
    if RegExMatch(s, "i)Win") {
        out .= "#"
    }
    key := RegExReplace(s, "i)^.*\+(.+)$", "$1")
    return out key
}

HasVal(arr, v) {
    for x in arr
        if x = v
            return true
    return false
}

NormPath(p) {
    p := Trim(p)
    p := StrReplace(p, "/", "\")
    p := RegExReplace(p, "\\+$", "")
    if p != "" && RegExMatch(p, "^[A-Za-z]:$") {
        p .= "\"  ; 保留盘符根（D:\），避免变成相对路径 D:
    }
    return p
}

EnsureNotesFile() {
    global NOTES_FILE
    if !FileExist(NOTES_FILE) {
        FileAppend("# 快速笔记`n", NOTES_FILE, "UTF-8")
    }
}

; ================= 新增便签窗口（类 Windows 便签样式） =================
NotesWin := ""
NotesEdit := ""

QuickNote() {
    global NotesWin, NotesEdit, NotesBtnSave, NotesBtnCancel
    if NotesWin {
        NotesWin.Show()
        NotesEdit.Focus()
        return
    }
    NotesWin := Gui("+AlwaysOnTop +Resize +MinSize420x300", "快速笔记")
    NotesWin.BackColor := "FFFFE1"
    NotesWin.MarginX := 14
    NotesWin.MarginY := 14
    NotesWin.SetFont("s12", "Segoe UI")
    NotesEdit := NotesWin.Add("Edit", "w420 h220 Multi Wrap -Border BackgroundFFFFE1")
    NotesWin.SetFont("s9", "Segoe UI")
    NotesBtnSave := NotesWin.Add("Button", "Default w90", "保存")
    NotesBtnSave.OnEvent("Click", QuickSave)
    NotesBtnCancel := NotesWin.Add("Button", "w90 x+8", "取消")
    NotesBtnCancel.OnEvent("Click", QuickCancel)
    NotesWin.OnEvent("Close", QuickCancel)
    NotesWin.OnEvent("Escape", QuickCancel)
    NotesWin.OnEvent("Size", QuickNoteSize)
    NotesWin.Show()
    NotesEdit.Focus()
}

QuickNoteSize(GuiObj, MinMax, Width, Height) {
    global NotesEdit, NotesBtnSave, NotesBtnCancel
    if MinMax = -1
        return
    ew := Width - 28
    eh := Height - 14 - 14 - 34 - 14
    if eh < 100
        return
    NotesEdit.Move(14, 14, ew, eh)
    by := 14 + eh + 14
    NotesBtnSave.Move(14, by)
    NotesBtnCancel.Move(14 + 98, by)
}

#HotIf WinActive("快速笔记")
^Enter::QuickSave()
#HotIf

QuickSave(*) {
    global NotesWin, NotesEdit
    text := Trim(NotesEdit.Value)
    if text != "" {
        AppendNote(text)
        NotesEdit.Value := ""
    }
    NotesWin.Hide()
    RefreshList()
}

QuickCancel(*) {
    global NotesWin, NotesEdit
    NotesEdit.Value := ""
    NotesWin.Hide()
}

; ================= 笔记列表主页面 =================
MainWin := ""
MainLV := ""
MainSearch := ""
MainEntries := []
MainMap := []

MainList() {
    global MainWin, MainLV, MainSearch
    if MainWin {
        MainWin.Show()
        RefreshList()
        MainSearch.Focus()
        return
    }
    MainWin := Gui("+AlwaysOnTop", "笔记列表")
    MainWin.MarginX := 12
    MainWin.MarginY := 12
    MainWin.SetFont("s10", "Segoe UI")
    MainWin.Add("Text", "w50", "搜索：")
    MainSearch := MainWin.Add("Edit", "x+8 w480 h24", "")
    MainSearch.OnEvent("Change", (*) => RefreshList())
    MainLV := MainWin.Add("ListView", "w560 h320 +Grid +LV0x10000", ["时间", "内容"])
    MainLV.OnEvent("DoubleClick", (lv, row) => ViewNote(row))
    MainWin.Add("Button", "w80", "新增").OnEvent("Click", (*) => QuickNote())
    MainWin.Add("Button", "w80 x+8", "查看").OnEvent("Click", (*) => ViewSelected())
    MainWin.Add("Button", "w80 x+8", "删除").OnEvent("Click", (*) => DeleteSelected())
    MainWin.Add("Button", "w80 x+8", "刷新").OnEvent("Click", (*) => RefreshList())
    MainWin.Add("Button", "w80 x+8", "关闭").OnEvent("Click", (*) => MainWin.Hide())
    MainWin.OnEvent("Close", (*) => MainWin.Hide())
    MainWin.OnEvent("Escape", (*) => MainWin.Hide())
    MainWin.Show()
    RefreshList()
    MainSearch.Focus()
}

RefreshList() {
    global MainLV, MainSearch, MainEntries, MainMap
    if !MainLV
        return
    MainEntries := ParseNotes()
    query := Trim(MainSearch.Value)
    MainMap := []
    MainLV.Delete()
    for i, e in MainEntries {
        preview := PreviewText(e.body)
        if query != "" && !InStr(e.time, query) && !InStr(e.body, query)
            continue
        MainMap.Push(i)
        MainLV.Add("", e.time, preview)
    }
    MainLV.ModifyCol(1, 120)
    MainLV.ModifyCol(2, 430)
}

ViewSelected() {
    global MainLV
    row := MainLV.GetNext(0)
    if row = 0 {
        MsgBox("请先选择一条笔记", "提示", "T3 0x40000")
        return
    }
    ViewNote(row)
}

ViewNote(row) {
    global MainMap, MainEntries
    if row < 1 || row > MainMap.Length
        return
    idx := MainMap[row]
    if idx < 1 || idx > MainEntries.Length
        return
    ShowDetail(idx, MainEntries[idx])
}

; ================= 笔记详情（查看 / 编辑 / 删除） =================
DetailWin := ""
DetailEdit := ""
DetailIdx := 0

ShowDetail(idx, entry) {
    global DetailWin, DetailEdit, DetailIdx, DetailTimeText, DetailBtnSave, DetailBtnDelete, DetailBtnClose
    DetailIdx := idx
    if DetailWin {
        DetailWin.Show()
        DetailEdit.Value := entry.body
        DetailEdit.Focus()
        return
    }
    DetailWin := Gui("+AlwaysOnTop +Resize +MinSize460x340", "笔记详情")
    DetailWin.BackColor := "FFFFE1"
    DetailWin.MarginX := 14
    DetailWin.MarginY := 14
    DetailWin.SetFont("s11", "Segoe UI")
    DetailTimeText := DetailWin.Add("Text", "w440 c444444", "时间：" entry.time)
    DetailEdit := DetailWin.Add("Edit", "w440 h240 Multi Wrap -Border BackgroundFFFFE1", entry.body)
    DetailWin.SetFont("s9", "Segoe UI")
    DetailBtnSave := DetailWin.Add("Button", "Default w90", "保存修改")
    DetailBtnSave.OnEvent("Click", SaveDetail)
    DetailBtnDelete := DetailWin.Add("Button", "w90 x+8", "删除")
    DetailBtnDelete.OnEvent("Click", DeleteDetail)
    DetailBtnClose := DetailWin.Add("Button", "w90 x+8", "关闭")
    DetailBtnClose.OnEvent("Click", (*) => DetailWin.Hide())
    DetailWin.OnEvent("Close", (*) => DetailWin.Hide())
    DetailWin.OnEvent("Escape", (*) => DetailWin.Hide())
    DetailWin.OnEvent("Size", DetailSize)
    DetailWin.Show()
    DetailEdit.Focus()
}

DetailSize(GuiObj, MinMax, Width, Height) {
    global DetailTimeText, DetailEdit, DetailBtnSave, DetailBtnDelete, DetailBtnClose
    if MinMax = -1
        return
    ew := Width - 28
    eh := Height - 14 - 22 - 14 - 34 - 14
    if eh < 100
        return
    DetailTimeText.Move(14, 14, ew, 22)
    DetailEdit.Move(14, 50, ew, eh)
    by := 50 + eh + 14
    DetailBtnSave.Move(14, by)
    DetailBtnDelete.Move(112, by)
    DetailBtnClose.Move(210, by)
}

SaveDetail(*) {
    global DetailWin, DetailEdit, DetailIdx, MainEntries
    if DetailIdx < 1 || DetailIdx > MainEntries.Length {
        MsgBox("笔记已不存在，请刷新列表", "提示", "T3 0x40000")
        return
    }
    text := RTrim(DetailEdit.Value, "`r`n `t")
    if text = "" {
        MsgBox("笔记内容不能为空", "提示", "T3 0x40000")
        return
    }
    MainEntries[DetailIdx].body := text
    WriteNotes(MainEntries)
    RefreshList()
    DetailWin.Hide()
}

DeleteSelected() {
    global MainLV, MainMap, MainEntries
    row := MainLV.GetNext(0)
    if row = 0 {
        MsgBox("请先选择一条笔记", "提示", "T3 0x40000")
        return
    }
    if row < 1 || row > MainMap.Length
        return
    idx := MainMap[row]
    if idx < 1 || idx > MainEntries.Length
        return
    if MsgBox("确定删除这条笔记？", "删除笔记", "OKCancel 0x40000") = "OK"
        DoDelete(idx)
}

DeleteDetail(*) {
    global DetailWin, DetailIdx
    if MsgBox("确定删除这条笔记？", "删除笔记", "OKCancel 0x40000") = "OK" {
        DoDelete(DetailIdx)
        DetailWin.Hide()
    }
}

DoDelete(idx) {
    global MainEntries
    if idx < 1 || idx > MainEntries.Length
        return
    MainEntries.RemoveAt(idx)
    WriteNotes(MainEntries)
    RefreshList()
}

; ================= 数据读写 =================
ParseNotes() {
    global NOTES_FILE
    entries := []
    if !FileExist(NOTES_FILE)
        return entries
    text := FileRead(NOTES_FILE, "UTF-8")
    lines := StrSplit(text, "`n", "`r")
    time := ""
    bodyLines := []
    for line in lines {
        if RegExMatch(line, "^## (\d{4}-\d{2}-\d{2} \d{2}:\d{2})$", &m) {
            if time != "" {
                entries.Push({time: time, body: JoinLines(bodyLines)})
            }
            time := m[1]
            bodyLines := []
        } else if time != "" {
            bodyLines.Push(line)
        }
    }
    if time != "" {
        entries.Push({time: time, body: JoinLines(bodyLines)})
    }
    return entries
}

JoinLines(lines) {
    while lines.Length > 0 && Trim(lines[lines.Length], " `t") = "" {
        lines.Pop()
    }
    out := ""
    for i, line in lines {
        if i > 1
            out .= "`n"
        out .= line
    }
    return out
}

WriteNotes(entries) {
    global NOTES_FILE
    content := "# 快速笔记`n"
    for e in entries {
        content .= "`n## " e.time "`n" e.body "`n"
    }
    f := FileOpen(NOTES_FILE, "w", "UTF-8")
    f.Write(content)
    f.Close()
}

PreviewText(body) {
    lines := StrSplit(body, "`n")
    for line in lines {
        line := Trim(line)
        if line != "" {
            if StrLen(line) > 50
                return SubStr(line, 1, 50) "…"
            return line
        }
    }
    return "(空)"
}

; ================= 收藏选中文字（经剪贴板） =================
CopySelection(*) {
    clipSaved := ClipboardAll()
    A_Clipboard := ""
    Send("^c")
    if !ClipWait(1) {
        A_Clipboard := clipSaved
        return
    }
    sel := Trim(A_Clipboard)
    A_Clipboard := clipSaved
    if sel = ""
        return
    winTitle := WinGetTitle("A")
    AppendNote("> " sel "`n`n— 来自：" winTitle)
    RefreshList()
}

AppendNote(text) {
    global NOTES_FILE
    stamp := FormatTime(, "yyyy-MM-dd HH:mm")
    FileAppend("`n## " stamp "`n" text "`n", NOTES_FILE, "UTF-8")
    TrayTip(text, "已保存", 2)
}
