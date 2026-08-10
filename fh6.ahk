; =================================================================
; Forza Horizon 6 (FH6) 自動化輔助腳本
; 版本: 1.5.6
; 說明: 提供買車、賺技能點、點技能、抽轉盤與油門自動化等五大功能行程，
;       採用橫向懸浮按鈕 UI，並完美支援 Xbox 手把與鍵盤的雙向控制及狀態回饋。
; =================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
SetKeyDelay(-1, -1)

; === 強制要求系統管理員權限運行，避免FH6阻擋按鍵 ===
if !A_IsAdmin {
    try {
        Run '*RunAs "' A_ScriptFullPath '"'
    }
    ExitApp()
}

; === 禁用 Win11 邊緣滑動手勢、視窗貼齊與觸發快捷鍵 ===
DisableWin11EdgeActions() {
    try RegWrite(0, "REG_DWORD", "HKCU\Software\Policies\Microsoft\Windows\EdgeUI", "AllowEdgeSwipe")
    try RegWrite(0, "REG_DWORD", "HKLM\SOFTWARE\Policies\Microsoft\Windows\EdgeUI", "AllowEdgeSwipe")
    try RegWrite("0", "REG_SZ", "HKCU\Control Panel\Desktop", "DockMoving")
    try RegWrite(0, "REG_DWORD", "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced", "EnableSnapAssist")
    try RegWrite(0, "REG_DWORD", "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced", "SnapFill")
}
DisableWin11EdgeActions()

#w::return   ; 停用 Win+W (Win11 小工具 / Widgets)
#n::return   ; 停用 Win+N (Win11 通知中心)
#a::return   ; 停用 Win+A (Win11 快速設定)
#z::return   ; 停用 Win+Z (Win11 視窗貼齊佈局 / Snap Layouts)

;OnExit( (*) => (
;    ForceReleaseW_Hardware(),
;     Send("{w up}{a up}{s up}{d up}{x up}{Space up}{Down up}{Shift up}{Ctrl up}{Alt up}{Enter up}{Esc up}")
;))

; =================================================================
; [全域自動化參數設定區]
; =================================================================
global LoadVehicleDelay := 11   ; 等待車輛載入時間（秒）
global LongPressDelay := 3.0     ; 手把長按偵測時間（秒）
global EnableGamepad := 0        ; 【手把控制設定】1 表示預設啟用手把，0 表示預設停用
global IsSimplifyDividers := true ; 簡化進度條格數（簡化後每十次畫一格避免太密集）

; [行程循環次數設定]
global AutoLoopEnabled := false    ; 自動雙循環開關
global LoopCountLimit := 47       ; 技能行程循環次數
global SkillPath := "808" ; 設定車型以決定預設路徑，可填入 "808", "22B", "Revuelto"
global SkillPoints := 987         ; 技能行程技能點數限制
global SkillBuyCarEnabled := true ; 點技能前先自動購買車輛
global NewSequenceLoopLimit := 110 ; 賺技能點行程循環次數
global labcode := "167982162"      ; 賺技能點賽事分享代碼
global BuyCarLoopLimit := 0      ; 買車行程循環次數
global RivalLoopLimit := 0       ; 勁敵刷錢行程循環次數
global RivalThrottleSec := 300    ; 勁敵刷錢按住油門時間（秒）

; [路由器與重啟設定]
global Enable5AMWait := true       ; 啟用路由器重啟等待與自動確認
global RebootHour := 5             ; 路由器重啟時間（24H整點）
global RebootWaitMin := 5          ; 路由器重啟網路斷線等待分鐘

; [偵測與顯示調試設定]
global ShowDashedBox := true        ; 設定是否顯示偵測顏色的虛線框 (true: 顯示, false: 隱藏)

; 【買車行程設定】
global BuyCarMfgUp := 10            ; 車廠 往上格數 (0-20)
global BuyCarMfgDown := 0          ; 車廠 往下格數 (0-20)
global BuyCarMfgLeft := 0          ; 車廠 往左格數 (0-3)
global BuyCarMfgRight := 1         ; 車廠 往右格數 (0-3)
global BuyCarSelUp := 0            ; 選車 往上格數 (0-20)
global BuyCarSelDown := 1          ; 選車 往下格數 (0-20)
global BuyCarSelLeft := 2          ; 選車 往左格數 (0-4)
global BuyCarSelRight := 0         ; 選車 往右格數 (0-4)

; [圖示顯示設定]
global ShowIcon_Esc := true          ; 顯示按 Esc 圖示
global ShowIcon_NewSeq := true       ; 顯示賺技能點圖示
global ShowIcon_Seq := true          ; 顯示點技能圖示
global ShowIcon_Rival := true        ; 顯示勁敵刷錢圖示
global ShowIcon_BuyCar := true       ; 顯示買車圖示
global ShowIcon_Gas := false          ; 顯示油門圖示
global ShowIcon_EnterSpam := true    ; 顯示連點 Enter 圖示
global ShowIcon_EditBox := true      ; 顯示編輯偵測框圖示
global ShowIcon_Exit := true         ; 顯示安全門圖示


; =================================================================
; [全域非設定/執行狀態變數區]
; =================================================================
GroupAdd("GameGroup","ahk_exe ForzaHorizon6.exe") ; 遊戲視窗標題名稱
GroupAdd("GameGroup","ahk_exe notepad.exe") ; 測試用
global GameTitle := "ahk_group GameGroup" ; 將視窗目標指向群組

global DetectBoxDefs := Map(
    1,  { name: "1. ⚔ 賺技能點：黃色賽事卡片", desc: "畫面中央黃色賽事卡片區域", ref: "Window",   x1: 0.260, y1: 0.252, x2: 0.403, y2: 0.501 },
    2,  { name: "2. ⚔ 賺技能點：黑色背景區域", desc: "畫面正中央黑色背景輸入區域", ref: "Window",   x1: 0.417, y1: 0.290, x2: 0.532, y2: 0.399 },
    3,  { name: "3. ⚔ 賺技能點：進度條右下非黑", desc: "賽道載入頁面右下角進度條非黑色區域", ref: "Window",   x1: 0.722, y1: 0.008, x2: 0.814, y2: 0.026 },
    4,  { name: "4. ⚔ 賺技能點：HUD 資訊框", desc: "畫面左上角「剩餘時間 / 目標 / 目前」HUD 資訊框區域", ref: "Window",   x1: 0.025, y1: 0.051, x2: 0.126, y2: 0.102 },
    5,  { name: "5. ⚔ 賺技能點：綠色評分標頭", desc: "畫面中央「是否要為挑戰評分？」亮綠色標頭區域", ref: "Window",   x1: 0.328, y1: 0.345, x2: 0.548, y2: 0.383 },
    6,  { name: "6. ⚔ 賺技能點：儀表板桃紅線條", desc: "畫面右下角儀表板桃紅色線條", ref: "Viewport",   x1: 0.936, y1: 0.766, x2: 0.977, y2: 0.869 },
    7,  { name: "7. 🎖 勁敵刷錢：收藏日誌桃卡", desc: "畫面左側「收藏日誌」桃色卡片區域", ref: "Viewport",   x1: 0.129, y1: 0.347, x2: 0.223, y2: 0.596 },
    8,  { name: "8. 🎖 勁敵刷錢：線上勁敵桃卡", desc: "「線上」分頁「勁敵」桃色卡片區域", ref: "Viewport",   x1: 0.283, y1: 0.568, x2: 0.372, y2: 0.649 },
    9,  { name: "9. 🎖 勁敵刷錢：變更勁敵列表", desc: "畫面中央「變更勁敵」列表區域", ref: "Window",   x1: 0.443, y1: 0.305, x2: 0.477, y2: 0.604 },
    10,  { name: "10. 🎖 勁敵刷錢：詳細資訊區域", desc: "畫面右側「詳細資訊」下方區域", ref: "Window",   x1: 0.754, y1: 0.553, x2: 0.798, y2: 0.586 },
    11,  { name: "11. 🎖 勁敵刷錢：左上角 R 標籤", desc: "畫面左上角標題欄「R 標籤色塊」", ref: "Window",   x1: 0.016, y1: 0.035, x2: 0.051, y2: 0.053 },
    12,  { name: "12. 🎖 勁敵刷錢：篩選綠色標頭", desc: "篩選視窗頂部螢光綠 / 亮綠色區域", ref: "Viewport",   x1: 0.169, y1: 0.208, x2: 0.533, y2: 0.229 },
    13,  { name: "13. 🎖 勁敵刷錢：高速公路等級桃卡", desc: "高速公路環道下方桃紅色等級卡片區域", ref: "Viewport",   x1: 0.205, y1: 0.722, x2: 0.281, y2: 0.794 }
)
global DefaultDetectBoxDefs := Map(
    1,  { x1: 0.260, y1: 0.252, x2: 0.403, y2: 0.501 },
    2,  { x1: 0.417, y1: 0.290, x2: 0.532, y2: 0.399 },
    3,  { x1: 0.722, y1: 0.008, x2: 0.814, y2: 0.026 },
    4,  { x1: 0.025, y1: 0.051, x2: 0.126, y2: 0.102 },
    5,  { x1: 0.328, y1: 0.345, x2: 0.548, y2: 0.383 },
    6,  { x1: 0.936, y1: 0.766, x2: 0.977, y2: 0.869 },
    7,  { x1: 0.129, y1: 0.347, x2: 0.223, y2: 0.596 },
    8,  { x1: 0.283, y1: 0.568, x2: 0.372, y2: 0.649 },
    9,  { x1: 0.443, y1: 0.305, x2: 0.477, y2: 0.604 },
    10,  { x1: 0.754, y1: 0.553, x2: 0.798, y2: 0.586 },
    11,  { x1: 0.016, y1: 0.035, x2: 0.051, y2: 0.053 },
    12,  { x1: 0.169, y1: 0.208, x2: 0.533, y2: 0.229 },
    13,  { x1: 0.205, y1: 0.722, x2: 0.281, y2: 0.794 }
)

global isEditBoxMode := false
global EditBoxMenuGui := ""
global EditBoxWindowGui := ""
global EditBoxHeaderCtrl := ""
global EditBoxInfoCtrl := ""
global EditBoxStatusCtrl := ""
global lastEditBoxPos := { x: -9999, y: -9999, w: -9999, h: -9999 }
global currentSelectedEditMode := 1
global TipGui := ""
global TipTextCtrl := ""
global isDraggingEditBox := false
global dragMouseStartX := 0, dragMouseStartY := 0
global dragWinStartX := 0, dragWinStartY := 0
global dragWinW := 0, dragWinH := 0

LoadAllFromIni()
global ConfirmState := { result: false, isWaiting: false }
global AutoLoopCount := 0          ; 自動雙循環當前次數
global StopAfterCurrentLoop := false ; 於當前循環結束後停止開關
global IsWaitingReboot := false     ; 標記是否處於重啟等待倒數中
global isPauseFocusCheck := false   ; 標記是否暫停遊戲視窗焦點偵測
global isPauseProgressBar := false  ; 標記是否暫停進度條更新（保持顯示並暫停）
global totalRatingPauseMs := 0      ; 綠色評分與過場偵測期間的累積暫停時間（不列入總行程計時）
global pauseStart := 0              ; 記錄當前過場/顏色偵測開始時間（毫秒）
global RivalLoadSec := 10          ; 勁敵刷錢等待載入時間（秒）
global RivalEndHour := 0          ; 勁敵刷錢預計結束時間（時）

; [觸控按鈕位置與進度條設定]
global GuiX := 0
global GuiY := 0
global GuiH := 30
global GuiOpacity := 180
global ProgressBarWidth := 610

; [行程運行狀態標記]
global isGasOn := false
global isSequenceRunning := false
global isEnterSpamRunning := false
global isNewSequenceRunning := false
global isBuyCarRunning := false
global isRivalRunning := false
global isConfirming := false

; [當前行程循環與步驟資訊]
global currentLoopItem := 0
global currentNewLoopItem := 0
global currentBuyCarLoopItem := 0
global currentRivalLoopItem := 0
global currentStepText := ""
global currentLoopTotalMs := 0
global currentLoopStartTime := 0
global currentLoopDuration := 1

; [進度條與計時動態變數]
global sequenceStartTime := 0
global sequenceTotalSec := 0
global globalSegmentEnds := []
global globalTotalMs := 1
global HasPreparationPhase := false
global DividerCtrls := []
global CurrentConfirmUpdateFn := ""

; [手把按壓狀態]
global xTriggeredThisPress := false
global yTriggeredThisPress := false
global lTriggeredThisPress := false
; === 車型路徑資料源與全域參數 ===
global VehiclePaths := Map(
    "808", [
        {r: 4, c: 1},
        {r: 4, c: 2},
        {r: 4, c: 3},
        {r: 3, c: 3},
        {r: 2, c: 3},
        {r: 1, c: 3}
    ],
    "22B", [
        {r: 4, c: 1},
        {r: 4, c: 2},
        {r: 3, c: 2},
        {r: 2, c: 2},
        {r: 1, c: 2},
        {r: 1, c: 1}
    ],
    "Revuelto", [
        {r: 4, c: 1},
        {r: 3, c: 1},
        {r: 2, c: 1},
        {r: 1, c: 1},
        {r: 1, c: 2},
        {r: 1, c: 3}
    ]
)

GetSkillStaticActions(loopIdx) {
    local actions := [
        { key: "Down", press: 80, wait: 450, tip: "20. 拍賣場 按 ⬇" },
        { key: "Enter", press: 80, wait: 600, tip: "21. 按 ⏎" },
        { key: "Down", press: 80, wait: 450, tip: "22. 開始拍賣會 按 ⬇" },
        { key: "Enter", press: 80, wait: 600, tip: "23. 按 ⏎" },
        { sleep: 2000, countdown: true, tip: "等待 2 秒" },
        { key: "x", press: 80, wait: 450, tip: "24 .排序 按 X" },
        { key: "Down", press: 80, wait: 100, repeat: 12, tip: "25. 最近新增 按 ⬇( {1}/6)" }, ;6格
        { key: "Enter", press: 80, wait: 1000, tip: "26. 按 ⏎" },
        { key: "Backspace", press: 80, wait: 1000, tip: "27. 篩選 按 ⌫" },
        { key: "Enter", press: 80, wait: 600, tip: "28. 到最新車輛 按 ⏎ " }
    ]
 
    if (loopIdx == 1) {
        ; 循環前：選取並駕駛第一輛車
        actions.Push({ key: "Enter", press: 80, wait: 600, tip: "29. 按 ⏎" })
        actions.Push({ key: "Down", press: 80, wait:600, tip: "30. 駕駛 按 ⬇" })
        actions.Push({ key: "Enter", press: 80, wait: 600, tip: "31. 按 ⏎" })
        actions.Push({ sleep: 5000, countdown: true, tip: "等待載入 5 秒" })
    } else {
        ; 循環中：選取第二輛車駕駛，並刪除第一輛車
        actions.Push({ key: "Down", press: 80, wait: 450, tip: "29. 第二輛車 按 ⬇" })
        actions.Push({ key: "Enter", press: 80, wait: 600, tip: "30. 按 ⏎" })
        actions.Push({ key: "Down", press: 80, wait: 600, tip: "32. 駕駛 按 ⬇" })
        actions.Push({ key: "Enter", press: 80, wait: 600, tip: "33. 按 ⏎" })
        actions.Push({ sleep: 5000, countdown: true, tip: "等待載入 5 秒" })
        actions.Push({ key: "Up", press: 80, wait: 450, tip: "34. 到第一輛車 按 ⬆" })
        actions.Push({ key: "Enter", press: 80, wait: 600, tip: "35. 開啟選單按 ⏎" })
        actions.Push({ key: "Down", press: 80, wait: 100, repeat: 10, tip: "36. 從車庫移除 按 ⬇( {1}/5)" }) ;5格
        actions.Push({ key: "Enter", press: 80, wait: 600, tip: "37. 按 ⏎" })
        actions.Push({ key: "Down", press: 80, wait: 600, tip: "38. 確定移除 按 ⬇" })
        actions.Push({ key: "Enter", press: 80, wait: 600, tip: "39. 按 ⏎" })
        actions.Push({ sleep: 2000, countdown: true, tip: "等待 2 秒" })
    }
 
    ; 剩餘通用步驟
    actions.Push({ key: "Esc", press: 80, wait: 1200, tip: "40. 按 Esc (1/2)" })
    actions.Push({ key: "Esc", press: 80, wait: 1200, tip: "41. 按 Esc (2/2)" })
    actions.Push({ key: "Right", press: 80, wait: 600, tip: "42. 按 ⮕" })
    actions.Push({ key: "Enter", press: 80, wait: 600, tip: "43. 按 ⏎" })
    actions.Push({ key: "Down", press: 80, wait: 100, repeat: 14, tip: "44. 點技能 ⬇( {1}/7)" }) ;7格
    actions.Push({ sleep: 400, tip: "45. 等待中 (400ms)" })
    actions.Push({ key: "Enter", press: 80, wait: 1500, tip: "46. 按 ⏎ (1500ms)" })
 
    return actions
}

ClonePath(path) {
    cloned := []
    for pt in path {
        cloned.Push({r: pt.r, c: pt.c})
    }
    return cloned
}

global globalSkillPath := ClonePath(VehiclePaths.Has(SkillPath) ? VehiclePaths[SkillPath] : VehiclePaths["808"])
global globalSkillCost := 0 ; 將於下方 CalculatePathCost 定義後正式初始化

global ActiveConfirmDialog := {
    sliderCtrl: "",
    extraSliderCtrls: [],
    limitName: "",
    UpdateTimeDisplay: "",
    sliderMap: Map()
}

OnHScroll(wParam, lParam, msg, hwnd) {
    global ActiveConfirmDialog
    ctrlHwnd := lParam & 0xFFFFFFFF
 
    if (ActiveConfirmDialog.sliderMap && ActiveConfirmDialog.sliderMap.Has(ctrlHwnd)) {
        info := ActiveConfirmDialog.sliderMap[ctrlHwnd]
        if (info.type == "main" || info.type == "extra") {
            ActiveConfirmDialog.UpdateTimeDisplay.Call(info.ctrl)
        }
    }
}
OnMessage(0x0114, OnHScroll)

; --- 【UI 介面設定區】 ---
global MyGui := Gui("+AlwaysOnTop -Caption -Border +ToolWindow +Owner")
MyGui.BackColor := "010101"

global GuiBtns := []
global btnConfigs := [
    { name: "esc",       symbol: "Esc", showVar: "ShowIcon_Esc",       fn: (*) => (WinActive(GameTitle) ? Send("{Esc}") : "") },
    { name: "newSeq",    symbol: "⚔", showVar: "ShowIcon_NewSeq",    fn: (*) => (isNewSequenceRunning ? StopGasAndClean() : (WinActive(GameTitle) ? ToggleNewSequence() : "")) },
    { name: "seq",       symbol: "⚡", showVar: "ShowIcon_Seq",       fn: (*) => (isSequenceRunning ? StopGasAndClean() : (WinActive(GameTitle) ? ToggleLButtonSequence() : "")) },
    { name: "buyCar",    symbol: "🚗", showVar: "ShowIcon_BuyCar",    fn: (*) => (isBuyCarRunning ? StopGasAndClean() : (WinActive(GameTitle) ? ToggleBuyCarSequence() : "")) },
    { name: "rival",     symbol: "🎖", showVar: "ShowIcon_Rival",     fn: (*) => (isRivalRunning ? StopGasAndClean() : (WinActive(GameTitle) ? ToggleRivalSequence() : "")) },
    { name: "gas",       symbol: "🏆", showVar: "ShowIcon_Gas",       fn: (*) => (isGasOn ? StopGasAndClean() : (WinActive(GameTitle) ? ToggleGas() : "")) },
    { name: "enterSpam", symbol: "🎰", showVar: "ShowIcon_EnterSpam", fn: (*) => (isEnterSpamRunning ? StopGasAndClean() : (WinActive(GameTitle) ? ToggleEnterSpam() : "")) },
    { name: "editBox",   symbol: "⿴", showVar: "ShowIcon_EditBox",   fn: (*) => ToggleEditBoxMode() },
    { name: "exit",      symbol: "⏏", showVar: "ShowIcon_Exit",      fn: (*) => (StopGasAndClean(), MyGui.Destroy(), ExitApp()) }
]

SortConfigsBySettings() {
    global btnConfigs
    try {
        scriptText := FileRead(A_ScriptFullPath, "UTF-8")
    } catch {
        return ; 讀取失敗時使用預設順序
    }
    
    order := []
    Loop Parse, scriptText, "`n", "`r" {
        if RegExMatch(A_LoopField, "i)^\s*global\s+(ShowIcon_\w+)\s*:=", &match) {
            order.Push(match[1])
        }
    }
    
    if (order.Length == 0)
        return
        
    newConfigs := []
    for varName in order {
        for cfg in btnConfigs {
            if (cfg.showVar = varName) {
                newConfigs.Push(cfg)
                break
            }
        }
    }
    
    ; 補上可能在設定中漏掉但 btnConfigs 中存在的項目
    for cfg in btnConfigs {
        found := false
        for varName in order {
            if (cfg.showVar = varName) {
                found := true
                break
            }
        }
        if (!found) {
            newConfigs.Push(cfg)
        }
    }
    
    btnConfigs := newConfigs
}

SortConfigsBySettings()

GetBtnIndex(name) {
    global btnConfigs
    for idx, cfg in btnConfigs {
        if (cfg.HasOwnProp("name") && cfg.name == name) {
            return idx
        }
    }
    return 0
}

MyGui.SetFont("s16", "Segoe UI Emoji")
for idx, cfg in btnConfigs {
    btn := MyGui.Add("Text", "cWhite x-100 y-100 w40 h34 Center Background010101 -Wrap -Border -E0x0200 -E0x00020000 +Hidden", cfg.symbol)
    btn.OnEvent("Click", cfg.fn)
    try DllCall("uxtheme\SetWindowTheme", "Ptr", btn.Hwnd, "Str", "", "Str", "")
    GuiBtns.Push(btn)
}

global SkipBtn := MyGui.Add("Text", "cWhite x-100 y-100 w40 h34 Center Background010101 -Wrap -Border -E0x0200 -E0x00020000 +Hidden", "⏭")
try DllCall("uxtheme\SetWindowTheme", "Ptr", SkipBtn.Hwnd, "Str", "", "Str", "")

OnSkipClick(*) {
    global StopAfterCurrentLoop, SkipBtn
    if (StopAfterCurrentLoop) {
        StopAfterCurrentLoop := false
        SkipBtn.Opt("cWhite")
        SkipBtn.Redraw()
        ToolTip("⏭ 已取消，將繼續循環行程")
        SetTimer(() => ToolTip(), -2000)
    } else {
        StopAfterCurrentLoop := true
        SkipBtn.Opt("cRed")
        SkipBtn.Redraw()
        ToolTip("⏭ 將於本輪結束後自動停止...")
        SetTimer(() => ToolTip(), -2000)
    }
}
SkipBtn.OnEvent("Click", OnSkipClick)
 
global hCurrentProgressBmp := 0
global totalActionSteps := 0, currentActIdx := 0, currentStepStartTime := 0, currentStepTotalMs := 0

RenderProgressBarBitmap(loopPercent, totalPercent, text, w := 570, h := 28) {
    global hCurrentProgressBmp, ProgressPic
    if (!ProgressPic)
        return
        
    hdcScreen := DllCall("GetDC", "Ptr", 0, "Ptr")
    hdcMem := DllCall("gdi32\CreateCompatibleDC", "Ptr", hdcScreen, "Ptr")
    hbm := DllCall("gdi32\CreateCompatibleBitmap", "Ptr", hdcScreen, "Int", w, "Int", h, "Ptr")
    hbmOld := DllCall("gdi32\SelectObject", "Ptr", hdcMem, "Ptr", hbm, "Ptr")
    
    ; 1. 填滿面板主底色 0x010101
    hBrushBg := DllCall("gdi32\CreateSolidBrush", "UInt", 0x010101, "Ptr")
    rectBg := Buffer(16, 0)
    NumPut("int", 0, rectBg, 0)
    NumPut("int", 0, rectBg, 4)
    NumPut("int", w, rectBg, 8)
    NumPut("int", h, rectBg, 12)
    DllCall("user32\FillRect", "Ptr", hdcMem, "Ptr", rectBg, "Ptr", hBrushBg)
    DllCall("gdi32\DeleteObject", "Ptr", hBrushBg)
    
    ; 2. 判斷是否有總進度黃條 (totalPercent > 0)
    hasTotalBar := (totalPercent > 0)
    totalBarH := hasTotalBar ? 5 : 0
    loopBarY := totalBarH

    ; 繪製總進度黃條 (亮黃色: 0x00FFFF)
    if (hasTotalBar) {
        totalW := Integer(w * Min(1.0, Max(0.0, totalPercent / 100)))
        if (totalW > 0) {
            hBrushTotal := DllCall("gdi32\CreateSolidBrush", "UInt", 0x00FFFF, "Ptr")
            rectTotal := Buffer(16, 0)
            NumPut("int", 0, rectTotal, 0)
            NumPut("int", 0, rectTotal, 4)
            NumPut("int", totalW, rectTotal, 8)
            NumPut("int", totalBarH, rectTotal, 12)
            DllCall("user32\FillRect", "Ptr", hdcMem, "Ptr", rectTotal, "Ptr", hBrushTotal)
            DllCall("gdi32\DeleteObject", "Ptr", hBrushTotal)
        }
    }
    
    ; 3. 繪製單圈進度水藍條 (亮水藍: 0xFFC080)
    if (loopPercent > 0) {
        loopW := Integer(w * Min(1.0, Max(0.0, loopPercent / 100)))
        if (loopW > 0) {
            hBrushLoop := DllCall("gdi32\CreateSolidBrush", "UInt", 0xFFC080, "Ptr")
            rectLoop := Buffer(16, 0)
            NumPut("int", 0, rectLoop, 0)
            NumPut("int", loopBarY, rectLoop, 4)
            NumPut("int", loopW, rectLoop, 8)
            NumPut("int", h, rectLoop, 12)
            DllCall("user32\FillRect", "Ptr", hdcMem, "Ptr", rectLoop, "Ptr", hBrushLoop)
            DllCall("gdi32\DeleteObject", "Ptr", hBrushLoop)
        }
    }
    
    ; 3. 繪製帶黑色立體陰影的亮白色粗體文字 (確保文字圖層 100% 絕對壓在進度條最上方)
    if (text != "") {
        DllCall("gdi32\SetBkMode", "Ptr", hdcMem, "Int", 1)
        
        hFont := DllCall("gdi32\CreateFontW"
            , "Int", -28
            , "Int", 0, "Int", 0, "Int", 0
            , "Int", 700
            , "UInt", 0, "UInt", 0, "UInt", 0
            , "UInt", 1
            , "UInt", 0, "UInt", 0, "UInt", 0, "UInt", 0
            , "Str", "Microsoft JhengHei", "Ptr")
        hFontOld := DllCall("gdi32\SelectObject", "Ptr", hdcMem, "Ptr", hFont, "Ptr")
        
        ; A. 先繪製黑色外框/陰影 (Offset +1px, +1px)，提供高對比度邊界
        DllCall("gdi32\SetTextColor", "Ptr", hdcMem, "UInt", 0x000000)
        rectShadow := Buffer(24, 0)
        NumPut("int", 7, rectShadow, 0)
        NumPut("int", 1, rectShadow, 4)
        NumPut("int", w + 1, rectShadow, 8)
        NumPut("int", h + 1, rectShadow, 12)
        DllCall("user32\DrawTextW", "Ptr", hdcMem, "Str", text, "Int", -1, "Ptr", rectShadow, "UInt", 0x24)

        ; B. 再繪製純白正面文字 (頂層呈現)
        DllCall("gdi32\SetTextColor", "Ptr", hdcMem, "UInt", 0xFFFFFF)
        rectText := Buffer(24, 0)
        NumPut("int", 6, rectText, 0)
        NumPut("int", 0, rectText, 4)
        NumPut("int", w, rectText, 8)
        NumPut("int", h, rectText, 12)
        DllCall("user32\DrawTextW", "Ptr", hdcMem, "Str", text, "Int", -1, "Ptr", rectText, "UInt", 0x24)
        
        DllCall("gdi32\SelectObject", "Ptr", hdcMem, "Ptr", hFontOld)
        DllCall("gdi32\DeleteObject", "Ptr", hFont)
    }
    
    DllCall("gdi32\SelectObject", "Ptr", hdcMem, "Ptr", hbmOld)
    DllCall("gdi32\DeleteDC", "Ptr", hdcMem)
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdcScreen)
    
    if (hCurrentProgressBmp) {
        DllCall("gdi32\DeleteObject", "Ptr", hCurrentProgressBmp)
    }
    hCurrentProgressBmp := hbm
    ProgressPic.Value := "HBITMAP:" . hbm
}

; 💡 全新單點陣圖進度條 (零白框、零閃爍、文字極致貼合)
global ProgressPic := MyGui.Add("Picture", "x85 y3 w" . ProgressBarWidth . " h28 -Border -E0x0200 -E0x00020000 +Hidden", "")
try DllCall("uxtheme\SetWindowTheme", "Ptr", ProgressPic.Hwnd, "Str", "", "Str", "")

global PreProgressBar := MyGui.Add("Progress", "x-100 y-100 w30 h12 +Hidden", 0)
global ProgressBar := MyGui.Add("Progress", "x-100 y-100 w30 h12 +Hidden", 0)
global LoopProgressBar := MyGui.Add("Progress", "x-100 y-100 w30 h12 +Hidden", 0)
global ProgressText := MyGui.Add("Text", "x-100 y-100 w30 h12 +Hidden", "")

; 定義 UI 切換輔助函數
UpdateUiRunningState(btnName) {
    global GuiBtns, SkipBtn, MyGui, GuiX, GuiY, GuiH, GuiOpacity, PreProgressBar, ProgressBar, LoopProgressBar, ProgressText, HasPreparationPhase, StopAfterCurrentLoop, RivalLoopLimit
    runningIdx := GetBtnIndex(btnName)
    for idx, btn in GuiBtns {
        if (idx == runningIdx) {
            btn.Move(0, -2)
            btn.Visible := true
        } else {
            btn.Visible := false
            btn.Move(-100, -100)
        }
    }
 
    if (btnName == "enterSpam" || btnName == "gas") {
        ProgressPic.Visible := false
        if (SkipBtn) {
            SkipBtn.Visible := false
            SkipBtn.Move(-100, -100)
        }
        MyGui.Show("X" GuiX " Y" GuiY " W40 h" GuiH " NoActivate")
    } else if (btnName == "newSeq" || btnName == "seq" || btnName == "rival" || btnName == "buyCar") {
        if (StopAfterCurrentLoop) {
            SkipBtn.Opt("cRed")
        } else {
            SkipBtn.Opt("cWhite")
        }
        SkipBtn.Visible := true
        SkipBtn.Move(40, -2)
        ProgressPic.Move(85, 3, 570, 28)
        ProgressPic.Visible := true
        MyGui.Show("X" GuiX " Y" GuiY " W660 h" GuiH " NoActivate")
    } else {
        if (SkipBtn) {
            SkipBtn.Visible := false
            SkipBtn.Move(-100, -100)
        }
        ProgressPic.Move(45, 3, 610, 28)
        ProgressPic.Visible := true
        MyGui.Show("X" GuiX " Y" GuiY " W660 h" GuiH " NoActivate")
    }
    WinSetTransparent(GuiOpacity, MyGui.Hwnd)
}

ResetUiToNormal() {
    global GuiBtns, SkipBtn, MyGui, GuiX, GuiY, GuiH, GuiOpacity, PreProgressBar, ProgressBar, LoopProgressBar, ProgressText, ProgressPic, GameTitle, btnConfigs
    if (ProgressPic) {
        ProgressPic.Visible := false
    }
    PreProgressBar.Visible := false
    ProgressBar.Visible := false
    LoopProgressBar.Visible := false
    ProgressText.Visible := false
    SkipBtn.Visible := false
    SkipBtn.Move(-100, -100)
    StopAfterCurrentLoop := false
 
    currentX := 0
    for idx, btn in GuiBtns {
        cfg := btnConfigs[idx]
        if (%(cfg.showVar)%) {
            btn.Move(currentX, -2)
            btn.Visible := true
            currentX += 40
        } else {
            btn.Visible := false
            btn.Move(-100, -100)
        }
    }
 
    currentActive := WinActive(GameTitle) || WinActive("ahk_id " MyGui.Hwnd)
    if (currentActive) {
        MyGui.Show("X" GuiX " Y" GuiY " W" . currentX . " h" . GuiH . " NoActivate")
        WinSetTransparent(GuiOpacity, MyGui.Hwnd)
    }
}

ResetUiToNormal()
WinSetTransparent(GuiOpacity, MyGui.Hwnd)
WinSetExStyle("+0x08000000", MyGui.Hwnd)

WM_WINDOWPOSCHANGING(wParam, lParam, msg, hwnd) {
    global EditBoxWindowGui
    if (EditBoxWindowGui != "" && hwnd == EditBoxWindowGui.Hwnd) {
        flags := NumGet(lParam, 32, "UInt")
        if !(flags & 0x0002) {
            curX := NumGet(lParam, 16, "Int")
            curY := NumGet(lParam, 20, "Int")
            curW := NumGet(lParam, 24, "Int")
            curH := NumGet(lParam, 28, "Int")

            minX := 5
            minY := 10
            maxX := A_ScreenWidth - curW - 5
            maxY := A_ScreenHeight - curH - 5

            clampedX := Max(minX, Min(maxX, curX))
            clampedY := Max(minY, Min(maxY, curY))

            NumPut("Int", clampedX, lParam, 16)
            NumPut("Int", clampedY, lParam, 20)
        }
    }
}

OnMessage(0x0201, WM_LBUTTONDOWN)
OnMessage(0x0046, WM_WINDOWPOSCHANGING)

; --- 【定時器啟動區】 ---
SetTimer(WatchGameWindow, 500)
SetTimer(CheckEveryHourly, 1000, 1)
SetTimer(WatchJoystick, 60)

; =================================================================
; --- 【進度條動態分格管理】 ---
; =================================================================
DrawDividers() {
    global DividerCtrls, IsSimplifyDividers, globalSegmentEnds, globalTotalMs, MyGui, isNewSequenceRunning, isSequenceRunning
    ClearDividers()
    
    if (globalSegmentEnds.Length == 0 || globalTotalMs <= 0) {
        return
    }

    xPositions := []
    isSeqWithSkipBtn := isNewSequenceRunning || isSequenceRunning || isRivalRunning || isBuyCarRunning
    startPos := isSeqWithSkipBtn ? 85 : 45
    progressBarWidthVal := isSeqWithSkipBtn ? 570 : 610
    
    if (globalSegmentEnds.Length > 1) {
        preEndX := startPos + (globalSegmentEnds[1] / globalTotalMs) * progressBarWidthVal
        xPositions.Push(preEndX)
    }

    loopCount := globalSegmentEnds.Length - 1
    if (IsSimplifyDividers && loopCount >= 20) {
        for idx, endTime in globalSegmentEnds {
            if (idx == 1 || idx == globalSegmentEnds.Length) {
                continue
            }
            loopIdx := idx - 1
            if (Mod(loopIdx, 10) == 0) {
                xPos := startPos + (endTime / globalTotalMs) * progressBarWidthVal
                xPositions.Push(xPos)
            }
        }
    } else {
        for idx, endTime in globalSegmentEnds {
            if (idx == globalSegmentEnds.Length) {
                continue
            }
            if (idx == 1) {
                continue
            }
            xPos := startPos + (endTime / globalTotalMs) * progressBarWidthVal
            xPositions.Push(xPos)
        }
    }

    while (xPositions.Length > DividerCtrls.Length) {
        ctrl := MyGui.Add("Text", "y3 w2 h12 +BackgroundAAAAFF +Hidden", "")
        DividerCtrls.Push(ctrl)
    }

    for idx, xPos in xPositions {
        ctrl := DividerCtrls[idx]
        ctrl.Move(xPos, 3, 2, 12)
        ctrl.Visible := true
    }
}

ClearDividers() {
    global DividerCtrls
    for ctrl in DividerCtrls {
        ctrl.Visible := false
        ctrl.Move(-100, -100)
    }
}

CalculatePathCost(path) {
    total := 0
    for pt in path {
        r := pt.r
        c := pt.c
        if (r == 4) {
            total += (c == 4) ? 20 : 1
        } else if (r == 3) {
            total += 3
        } else if (r == 2) {
            total += 5
        } else if (r == 1) {
            total += 10
        }
    }
    return total
}
globalSkillCost := CalculatePathCost(globalSkillPath)


; =================================================================
; --- 【無邊框沉浸式確認對話框】 ---
; =================================================================
ShowConfirmDialog(funcName, timeStr, limitVarRef := unset, recalcFn := "", extraParams := "", limitName := "", getSingleLoopMsFn := "") {
    global GuiX, GuiY, GuiOpacity, GameTitle, ConfirmState, IsSimplifyDividers, CurrentConfirmUpdateFn, globalSkillPath, globalSkillCost, SkillBuyCarEnabled, AutoLoopEnabled, Enable5AMWait, RebootHour, RebootWaitMin
    CurrentConfirmUpdateFn := UpdateTimeDisplay

    ConfirmGui := Gui("+AlwaysOnTop -Caption -Border +ToolWindow +Owner")
    ConfirmGui.BackColor := "010101"

    hasLimitSlider := IsSet(limitVarRef) && Type(limitVarRef) == "VarRef"
    hasExtraParams := IsObject(extraParams) && extraParams.Length > 0
    isSkillSeq := (limitName == "LoopCountLimit")

    originalLimit := hasLimitSlider ? %limitVarRef% : 0
    originalExtraVals := []
    if (hasExtraParams) {
        for idx, item in extraParams {
            originalExtraVals.Push(%(item.varRef)%)
        }
    }
    originalEnable5AMWait := Enable5AMWait
    originalRebootHour := RebootHour
    originalRebootWaitMin := RebootWaitMin

    local sliderCtrl := "", chkSimplify := "", timeTextCtrl := "", chkBuyCar := "", chkAutoLoop := ""
    local labelTextPart1 := "", labelTextPart2 := "", labelTextPart3 := ""
    local extraLabelCtrls := []
    local extraSliderCtrls := []
    local gridTitleCtrl := ""
    local chk5AMWait := "", sldRebootHour := "", sldRebootWaitMin := ""
    local lblRebootHourTitle := "", lblRebootHourVal := "", lblRebootHourUnit := ""
    local lblRebootWaitTitle := "", lblRebootWaitVal := "", lblRebootWaitUnit := ""

    ; 初始化全域活動對話框狀態物件，以供全域 OnHScroll 訊息監聽使用
    ActiveConfirmDialog.sliderCtrl := ""
    ActiveConfirmDialog.extraSliderCtrls := extraSliderCtrls
    ActiveConfirmDialog.limitName := limitName
    ActiveConfirmDialog.UpdateTimeDisplay := UpdateTimeDisplay
    ActiveConfirmDialog.sliderMap := Map()






    ; 4x4 矩陣選擇相關控制變數
    local buttons := Map()
    selectedPath := []
 
    UpdateButtonsState() {
        if (!isSkillSeq)
            return
        globalSkillCost := CalculatePathCost(selectedPath)
        if (gridTitleCtrl) {
            gridTitleCtrl.Text := "點技能路徑設定 (起點左下角 🟢)：" globalSkillCost "點"
        }
        if (sliderCtrl && extraSliderCtrls.Length > 0) {
            maxLoops := (globalSkillCost > 0) ? Floor(999 / globalSkillCost) : 999
            sliderCtrl.Opt("Range1-" maxLoops)
            if (sliderCtrl.Value > maxLoops) {
                sliderCtrl.Value := maxLoops
            }
            sliderMinPoint := Max(1, globalSkillCost)
            extraSliderCtrls[1].Opt("Range" sliderMinPoint "-999")
            extraSliderCtrls[1].Value := Min(999, Max(sliderMinPoint, sliderCtrl.Value * globalSkillCost))
        }
        Loop 4 {
            r := A_Index
            Loop 4 {
                c := A_Index
                btnKey := r "_" c
                btnCtrl := buttons[btnKey]
 
                foundIdx := 0
                for idx, pt in selectedPath {
                    if (pt.r == r && pt.c == c) {
                        foundIdx := idx
                        break
                    }
                }
 
                if (foundIdx > 0) {
                    if (foundIdx == 1) {
                        btnCtrl.Text := "🟢"
                    } else {
                        btnCtrl.Text := String(foundIdx)
                    }
                    btnCtrl.Opt("+Background22FF22 +cBlack")
                } else {
                    cost := (r == 4) ? ((c == 4) ? 20 : 1) : ((r == 3) ? 3 : ((r == 2) ? 5 : 10))
                    btnCtrl.Text := String(cost)
                    btnCtrl.Opt("+Background020202 +cWhite")
                }
            }
        }
    }

    OnGridClick(btnKey, *) {
        parts := StrSplit(btnKey, "_")
        r := Integer(parts[1])
        c := Integer(parts[2])

        for idx, pt in selectedPath {
            if (pt.r == r && pt.c == c) {
                if (idx == selectedPath.Length) {
                    selectedPath.Pop()
                    UpdateButtonsState()
                    if (recalcFn) {
                        UpdateTimeDisplay()
                    }
                }
                return
            }
        }

        if (selectedPath.Length == 0) {
            if (r == 4 && c == 1) {
                selectedPath.Push({r: r, c: c})
            }
        } else {
            last := selectedPath[selectedPath.Length]
            diffR := Abs(last.r - r)
            diffC := Abs(last.c - c)
            if ((diffR == 1 && diffC == 0) || (diffR == 0 && diffC == 1)) {
                selectedPath.Push({r: r, c: c})
            }
        }
        UpdateButtonsState()
        if (recalcFn) {
            UpdateTimeDisplay()
        }
    }

    UpdateTimeDisplay(triggerCtrl := "", *) {
        if (hasLimitSlider) {
            %limitVarRef% := sliderCtrl.Value
        }
        if (hasExtraParams) {
            for idx, item in extraParams {
                %(item.varRef)% := extraSliderCtrls[idx].Value
            }
            if (chkBuyCar) {
                SkillBuyCarEnabled := chkBuyCar.Value
            }
        }
        if (chkAutoLoop) {
            AutoLoopEnabled := chkAutoLoop.Value
            earnedPoints := Min(999, sliderCtrl.Value * 10)
            loopCount := globalSkillCost > 0 ? Floor(earnedPoints / globalSkillCost) : 0
            chkAutoLoop.Text := " 自動雙循環（自動連續行程 " loopCount " 次）"
        }

        if (chk5AMWait) {
            Enable5AMWait := chk5AMWait.Value
        }
        if (sldRebootHour && lblRebootHourVal) {
            RebootHour := sldRebootHour.Value
            oldValStr := lblRebootHourVal.Text
            valStr := String(RebootHour)
            if (oldValStr != valStr) {
                lblRebootHourVal.Text := valStr
                if (StrLen(oldValStr) != StrLen(valStr)) {
                    lblRebootHourVal.Move(,, StrLen(valStr) * 16 + 4)
                    lblRebootHourTitle.GetPos(&p1X, &p1Y, &p1W)
                    lblRebootHourVal.Move(p1X + p1W)

                    lblRebootHourVal.GetPos(&pvX, &pvY, &pvW)
                    lblRebootHourUnit.Move(pvX + pvW)
                }
                lblRebootHourTitle.Redraw()
                lblRebootHourVal.Redraw()
                lblRebootHourUnit.Redraw()
            }
        }
        if (sldRebootWaitMin && lblRebootWaitVal) {
            RebootWaitMin := sldRebootWaitMin.Value
            oldValStr := lblRebootWaitVal.Text
            valStr := String(RebootWaitMin)
            if (oldValStr != valStr) {
                lblRebootWaitVal.Text := valStr
                if (StrLen(oldValStr) != StrLen(valStr)) {
                    lblRebootWaitVal.Move(,, StrLen(valStr) * 16 + 4)
                    lblRebootWaitTitle.GetPos(&p2X, &p2Y, &p2W)
                    lblRebootWaitVal.Move(p2X + p2W)

                    lblRebootWaitVal.GetPos(&pvX2, &pvY2, &pvW2)
                    lblRebootWaitUnit.Move(pvX2 + pvW2)
                }
                lblRebootWaitTitle.Redraw()
                lblRebootWaitVal.Redraw()
                lblRebootWaitUnit.Redraw()
            }
        }

        if (isSkillSeq && triggerCtrl) {
            if (triggerCtrl.Hwnd == sliderCtrl.Hwnd) {
                sliderMinPoint := Max(1, globalSkillCost)
                extraSliderCtrls[1].Value := Min(999, Max(sliderMinPoint, sliderCtrl.Value * globalSkillCost))
            } else if (triggerCtrl.Hwnd == extraSliderCtrls[1].Hwnd) {
                maxLoops := (globalSkillCost > 0) ? Floor(999 / globalSkillCost) : 999
                divisor := Max(1, globalSkillCost)
                sliderCtrl.Value := Min(maxLoops, Max(1, Floor(extraSliderCtrls[1].Value / divisor)))
            }
            if (hasLimitSlider) {
                %limitVarRef% := sliderCtrl.Value
            }
            for idx, item in extraParams {
                %(item.varRef)% := extraSliderCtrls[idx].Value
            }
        }

        if (limitName == "RivalLoopLimit" && triggerCtrl) {
            singleLoopSec := getSingleLoopMsFn ? Ceil(getSingleLoopMsFn() / 1000) : 300

            idxHour := extraSliderCtrls.Length - 1
            idxMin := extraSliderCtrls.Length

            if (idxHour >= 1 && idxMin >= 1 && (triggerCtrl.Hwnd == extraSliderCtrls[idxHour].Hwnd || triggerCtrl.Hwnd == extraSliderCtrls[idxMin].Hwnd)) {
                targetHour := extraSliderCtrls[idxHour].Value
                targetMin := extraSliderCtrls[idxMin].Value
 
                currentTotalMin := A_Hour * 60 + A_Min
                targetTotalMin := targetHour * 60 + targetMin
 
                diffMin := targetTotalMin - currentTotalMin
                if (diffMin <= 0) {
                    diffMin += 1440
                }
 
                limitVal := Floor((diffMin * 60) / singleLoopSec)
                if (limitVal < 1) {
                    limitVal := 1
                } else if (limitVal > 100) {
                    limitVal := 100
                }
                sliderCtrl.Value := limitVal
                if (hasLimitSlider) {
                    %limitVarRef% := sliderCtrl.Value
                }
            } else if (idxHour >= 1 && idxMin >= 1) {
                totalSec := sliderCtrl.Value * singleLoopSec
                totalMin := Ceil(totalSec / 60)
                currentTotalMin := A_Hour * 60 + A_Min
                endTotalMin := Mod(currentTotalMin + totalMin, 1440)
                extraSliderCtrls[idxHour].Value := Floor(endTotalMin / 60)
                extraSliderCtrls[idxMin].Value := Mod(endTotalMin, 60)
                %(extraParams[idxHour].varRef)% := extraSliderCtrls[idxHour].Value
                %(extraParams[idxMin].varRef)% := extraSliderCtrls[idxMin].Value
            }
        }

        val := hasLimitSlider ? sliderCtrl.Value : 0
        isSimp := chkSimplify ? chkSimplify.Value : IsSimplifyDividers

        vals := []
        if (hasLimitSlider) {
            vals.Push(val)
        }

        if (hasExtraParams) {
            for idx, item in extraParams {
                ctrlVal := extraSliderCtrls[idx].Value
                vals.Push(ctrlVal)
 
                oldValStr := extraLabelCtrls[idx].valPart.Text
                valStr := String(ctrlVal)
                if (InStr(item.name, "分:秒") || InStr(item.name, "分：秒")) {
                    mins := Floor(ctrlVal / 60)
                    secs := Mod(ctrlVal, 60)
                    valStr := mins "分" Format("{:02d}", secs) "秒"
                } else if (InStr(item.name, "結束時間")) {
                    valStr := Format("{:02d}", ctrlVal)
                }
                if (oldValStr != valStr) {
                    extraLabelCtrls[idx].valPart.Text := valStr
                    if (StrLen(oldValStr) != StrLen(valStr)) {
                        extraLabelCtrls[idx].valPart.Move(,, StrLen(valStr) * 16 + 4)
                        extraLabelCtrls[idx].part1.GetPos(&p1X, &p1Y, &p1W)
                        extraLabelCtrls[idx].valPart.Move(p1X + p1W)

                        extraLabelCtrls[idx].valPart.GetPos(&pvX, &pvY, &pvW)
                        extraLabelCtrls[idx].part2.Move(pvX + pvW)
                    }
                    extraLabelCtrls[idx].part1.Redraw()
                    extraLabelCtrls[idx].valPart.Redraw()
                    extraLabelCtrls[idx].part2.Redraw()
                }
            }
        }

        if (recalcFn) {
            newTimeStr := ""
            if (isSkillSeq) {
                newTimeStr := recalcFn(val, SkillPoints, selectedPath)
            } else {
                newTimeStr := recalcFn(vals*)
            }
            if (newTimeStr != "" && timeTextCtrl && timeTextCtrl.Text != newTimeStr) {
                timeTextCtrl.Text := newTimeStr
                timeTextCtrl.Redraw()
            }
        }

        if (hasLimitSlider && labelTextPart2) {
            oldValStr := labelTextPart2.Text
            displayVal := (limitName == "RivalLoopLimit" && val == 0) ? "∞" : String(val)
            if (oldValStr != displayVal) {
                labelTextPart2.Text := displayVal
                needReposition := (StrLen(oldValStr) != StrLen(displayVal))
                newPart3Text := ""
                if (isSimp && val >= 20) {
                    groupCount := Ceil(val / 10)
                    newPart3Text := "次 / 簡化為" groupCount "格："
                } else {
                    newPart3Text := "次："
                }
                if (labelTextPart3.Text != newPart3Text) {
                    labelTextPart3.Text := newPart3Text
                    needReposition := true
                }
                if (needReposition) {
                    valW := (displayVal == "∞") ? 75 : (StrLen(displayVal) * 16 + 10)
                    labelTextPart2.Move(,, valW)
                    labelTextPart1.GetPos(&l1X, &l1Y, &l1W)
                    labelTextPart2.Move(l1X + l1W)

                    labelTextPart2.GetPos(&l2X, &l2Y, &l2W)
                    labelTextPart3.Move(l2X + l2W)
                }
                labelTextPart1.Redraw()
                labelTextPart2.Redraw()
                labelTextPart3.Redraw()
            }
        }
    }

    ; 計算佈局位置與高度
    totalSliders := (hasLimitSlider ? 1 : 0) + (hasExtraParams ? extraParams.Length : 0)
    rowSpacing := (totalSliders > 5) ? 70 : 80

    ; 視窗高度動態計算 (若為技能行程，因為要放 4x4 矩陣，高度需要大幅增加)
    guiH := 180
    if (totalSliders > 0) {
        guiH := 100 + totalSliders * rowSpacing
    }
    if (isSkillSeq) {
        guiH += 300  ; 額外為 4x4 矩陣與購買車輛開關保留 300 像素高度
    }
    if (limitName == "NewSequenceLoopLimit") {
        guiH += 40   ; 為自動雙循環開關保留高度
    }

    if (totalSliders > 0) {
        ConfirmGui.SetFont("s16 Bold cWhite", "Microsoft JhengHei")
        ConfirmGui.Add("Text", "x20 y15 w180 +BackgroundTrans", "【 " funcName " 】")

        ConfirmGui.SetFont("s13 Bold cYellow", "Microsoft JhengHei")
        ConfirmGui.Add("Text", "x200 y18 w120 Right +BackgroundTrans", "預估總時間：")

        ConfirmGui.SetFont("s20 Bold cYellow")
        timeTextCtrl := ConfirmGui.Add("Text", "x320 y12 w120 Right +BackgroundTrans", timeStr)

        currY := 52

        if (hasLimitSlider) {
            initialLimit := %limitVarRef%

            sliderRange := "1-100"
            if (limitName == "LoopCountLimit") {
                maxLoops := (globalSkillCost > 0) ? Floor(999 / globalSkillCost) : 33
                sliderRange := "1-" . maxLoops
            } else if (limitName == "NewSequenceLoopLimit") {
                sliderRange := "1-120"
            } else if (limitName == "BuyCarLoopLimit") {
                sliderRange := "0-100"
            } else if (limitName == "RivalLoopLimit") {
                sliderRange := "0-100"
            }

            ConfirmGui.SetFont("s14 Bold cGray", "Microsoft JhengHei")
            labelTextPart1 := ConfirmGui.Add("Text", "x20 y" currY " +BackgroundTrans", "循環 ")

            ConfirmGui.SetFont("s20 Bold cYellow", "Microsoft JhengHei")
            labelTextPart2Text := (limitName == "RivalLoopLimit" && initialLimit == 0) ? "∞" : initialLimit
            labelTextPart2 := ConfirmGui.Add("Text", "x+0 y" (currY - 5) " +BackgroundTrans", labelTextPart2Text)

            ConfirmGui.SetFont("s14 Bold cGray", "Microsoft JhengHei")
            labelTextPart3Text := (IsSimplifyDividers && initialLimit >= 20) ? "次 / 簡化為" Ceil(initialLimit / 10) "格：" : "次："
            labelTextPart3 := ConfirmGui.Add("Text", "x+0 y" currY " w220 +BackgroundTrans", labelTextPart3Text)

            ConfirmGui.SetFont("s10 cWhite")
            sliderCtrl := ConfirmGui.Add("Slider", "x20 y" (currY + 30) " w420 h40 Range" sliderRange " Thick30 Tooltip AltSubmit", initialLimit)
            sliderCtrl.OnEvent("Change", UpdateTimeDisplay)
            ActiveConfirmDialog.sliderCtrl := sliderCtrl
            ActiveConfirmDialog.sliderMap[sliderCtrl.Hwnd & 0xFFFFFFFF] := { type: "main", ctrl: sliderCtrl }
            currY += 80
        }

        if (hasExtraParams) {
            for idx, item in extraParams {
                initialVal := %(item.varRef)%

                unitStr :=  "次" 
                if (InStr(item.name, "分:秒") || InStr(item.name, "分：秒")) {
                    unitStr := ""
                } else if (InStr(item.name, "秒")) {
                    unitStr := "秒"
                } else if (InStr(item.name, "點數")) {
                    unitStr := "點"
                } else if (InStr(item.name, "(時)")) {
                    unitStr := "時"
                } else if (InStr(item.name, "(分)")) {
                    unitStr := "分"
                } else if (InStr(item.name, "(格數)") || InStr(item.name, "(格)")) {
                    unitStr := "格"
                }
 
                cleanName := RegExReplace(item.name, "\s*\([^)]+\)")
 
                valStr := String(initialVal)
                if (InStr(item.name, "分:秒") || InStr(item.name, "分：秒")) {
                    mins := Floor(initialVal / 60)
                    secs := Mod(initialVal, 60)
                    valStr := mins "分" Format("{:02d}", secs) "秒"
                } else if (InStr(item.name, "結束時間")) {
                    valStr := Format("{:02d}", initialVal)
                }
                ConfirmGui.SetFont("s14 Bold cGray", "Microsoft JhengHei")
                lblCtrlPart1 := ConfirmGui.Add("Text", "x20 y" currY " +BackgroundTrans",cleanName " ")
 
                ConfirmGui.SetFont("s20 Bold cYellow", "Microsoft JhengHei")
                lblCtrlVal := ConfirmGui.Add("Text", "x+0 y" (currY - 5) " +BackgroundTrans",valStr)
 
                ConfirmGui.SetFont("s14 Bold cGray", "Microsoft JhengHei")
                lblCtrlPart2 := ConfirmGui.Add("Text", "x+0 y" currY " w220 +BackgroundTrans",unitStr "：")

                extraLabelCtrls.Push({ part1: lblCtrlPart1, valPart: lblCtrlVal, part2: lblCtrlPart2 })

                ConfirmGui.SetFont("s10 cWhite")
                sldCtrl := ConfirmGui.Add("Slider", "x20 y" (currY + 25) " w420 h30 Range" item.range " Thick30 Tooltip AltSubmit",initialVal)
                sldCtrl.OnEvent("Change", UpdateTimeDisplay)
                extraSliderCtrls.Push(sldCtrl)
                ActiveConfirmDialog.sliderMap[sldCtrl.Hwnd & 0xFFFFFFFF] := { type: "extra", ctrl: sldCtrl }

                currY += rowSpacing
            }
        }

        if (limitName == "NewSequenceLoopLimit") {
            ConfirmGui.SetFont("s12 cWhite", "Microsoft JhengHei")
            chkAutoLoop := ConfirmGui.Add("Checkbox", "x20 y" currY " w420 Checked" (AutoLoopEnabled ? "1" : "0"), " 自動雙循環（賺點數行程後自動接點技能行程 33 次）")
            chkAutoLoop.OnEvent("Click", UpdateTimeDisplay)
            currY += 40
        }

        ; --- 若為技能行程，在對話框最下方加入 4x4 網格 ---
        if (isSkillSeq) {
            ConfirmGui.SetFont("s12 cWhite", "Microsoft JhengHei")
            chkBuyCar := ConfirmGui.Add("Checkbox", "x20 y" currY " w420 Checked" (SkillBuyCarEnabled ? "1" : "0"), " 點技能前先自動購買車輛")
            chkBuyCar.OnEvent("Click", UpdateTimeDisplay)
            currY += 30

            ConfirmGui.SetFont("s12 Bold cWhite", "Microsoft JhengHei")
            gridTitleCtrl := ConfirmGui.Add("Text", "x20 y" currY " w420 +BackgroundTrans", "點技能路徑設定 (起點左下角 🟢)：" globalSkillCost "點")
            currY += 25

            gridY := currY
            Loop 4 {
                r := A_Index
                Loop 4 {
                    c := A_Index
                    btnKey := r "_" c
                    bX := 20 + (c - 1) * 75
                    bY := gridY + (r - 1) * 55

                    cost := (r == 4) ? ((c == 4) ? 20 : 1) : ((r == 3) ? 3 : ((r == 2) ? 5 : 10))
                    btn := ConfirmGui.Add("Text", "x" bX " y" bY " w65 h48 Center +0x200 +Border +Background020202 cWhite", String(cost))
                    buttons[btnKey] := btn
                    btn.OnEvent("Click", OnGridClick.Bind(btnKey))
                }
            }

            ; 歸零路徑與預設路徑按鈕擺在網格右側
            btnReset := ConfirmGui.Add("Text", "x330 y" gridY " w110 h45 Center +0x200 +Border +Background020202 cWhite", "↩ 歸零路徑")
            btnReset.OnEvent("Click", (*) => (
                selectedPath := [{r: 4, c: 1}],
                UpdateButtonsState(),
                (recalcFn ? UpdateTimeDisplay() : "")
            ))

            btn808 := ConfirmGui.Add("Text", "x330 y" (gridY + 55) " w110 h45 Center +0x200 +Border +Background020202 cWhite", "🚗 808 預設")
            btn808.OnEvent("Click", (*) => (
                selectedPath := ClonePath(VehiclePaths["808"]),
                UpdateButtonsState(),
                (recalcFn ? UpdateTimeDisplay() : "")
            ))

            btn22B := ConfirmGui.Add("Text", "x330 y" (gridY + 110) " w110 h45 Center +0x200 +Border +Background020202 cWhite", "🚗 22B")
            btn22B.OnEvent("Click", (*) => (
                selectedPath := ClonePath(VehiclePaths["22B"]),
                UpdateButtonsState(),
                (recalcFn ? UpdateTimeDisplay() : "")
            ))

            btnRevuelto := ConfirmGui.Add("Text", "x330 y" (gridY + 165) " w110 h45 Center +0x200 +Border +Background020202 cWhite", "🚗 Revuelto")
            btnRevuelto.OnEvent("Click", (*) => (
                selectedPath := ClonePath(VehiclePaths["Revuelto"]),
                UpdateButtonsState(),
                (recalcFn ? UpdateTimeDisplay() : "")
            ))

            ; 預設載入全域路徑設定
            selectedPath := ClonePath(globalSkillPath)
            UpdateButtonsState()

            currY += 225
        }

        ; 右側的確定與取消按鈕
        btnH := Integer((guiH - 50) / 2)
        ConfirmGui.SetFont("s32", "Segoe UI Emoji")
        btnConfirm := ConfirmGui.Add("Text", "x460 y20 w100 h" btnH " Center +0x200 +Border +Background020202", "⭕")
        btnCancel := ConfirmGui.Add("Text", "x460 y" (20 + btnH + 10) " w100 h" btnH " Center +0x200 +Border +Background020202", "❌")
    } else {
        ConfirmGui.SetFont("s20 Bold cWhite", "Microsoft JhengHei")
        ConfirmGui.Add("Text", "x20 y20 w240 +BackgroundTrans", "【 " funcName " 】")

        ConfirmGui.SetFont("s16 Bold cYellow", "Microsoft JhengHei")
        ConfirmGui.Add("Text", "x240 y25 w160 Right +BackgroundTrans", "預估總時間：")

        ConfirmGui.SetFont("s24 Bold cYellow")
        ConfirmGui.Add("Text", "x330 y18 w110 Right +BackgroundTrans", timeStr)

        ConfirmGui.SetFont("s32", "Segoe UI Emoji")
        btnConfirm := ConfirmGui.Add("Text", "x460 y25 w100 h60 Center +0x200 +Border +Background020202", "⭕")
        btnCancel := ConfirmGui.Add("Text", "x460 y95 w100 h60 Center +0x200 +Border +Background020202", "❌")
    }
    UpdateTimeDisplay()

    ConfirmGui.Show("X" GuiX " Y" GuiY " W580 H" guiH " NoActivate")
    WinSetTransparent(GuiOpacity, ConfirmGui.Hwnd)
    WinSetExStyle("+0x08000000", ConfirmGui.Hwnd)

    ConfirmState.result := false
    ConfirmState.isWaiting := true

    OnConfirmClick(*) {
        if (isSkillSeq && selectedPath.Length <= 1) {
            MsgBox("請設定至少一步的點技能路徑！", "提示", "Iconi Owner" ConfirmGui.Hwnd)
            return
        }
        ConfirmState.result := true
        ConfirmState.isWaiting := false
    }

    btnConfirm.OnEvent("Click", OnConfirmClick)
    btnCancel.OnEvent("Click", (*) => (ConfirmState.result := false, ConfirmState.isWaiting := false))

    Sleep(300)
    while (ConfirmState.isWaiting) {
        if (GetAnyJoyState(1)) {
            if (isSkillSeq && selectedPath.Length <= 1) {
                ; 忽略手把按鍵確認，或者此處直接按確定但需要路徑已選定
                continue
            }
            ConfirmState.result := true
            break
        }
        if (GetAnyJoyState(2)) {
            ConfirmState.result := false
            break
        }
        Sleep(50)
    }
 
    if (ConfirmState.result) {
        if (hasLimitSlider) {
            %limitVarRef% := sliderCtrl.Value
        }
        if (hasExtraParams) {
            for idx, item in extraParams {
                %(item.varRef)% := extraSliderCtrls[idx].Value
            }
        }
        if (isSkillSeq) {
            globalSkillPath := selectedPath
        }
        SaveAllToIni()
    } else {
        if (hasLimitSlider) {
            %limitVarRef% := originalLimit
        }
        if (hasExtraParams) {
            for idx, item in extraParams {
                %(item.varRef)% := originalExtraVals[idx]
            }
        }
    }
 
    ConfirmGui.Destroy()
    ; 清空全域活動對話框狀態物件，釋放控制項參考以供後續使用
    ActiveConfirmDialog.sliderCtrl := ""
    ActiveConfirmDialog.extraSliderCtrls := []
    ActiveConfirmDialog.limitName := ""
    ActiveConfirmDialog.UpdateTimeDisplay := ""
    ActiveConfirmDialog.sliderMap := Map()
    Sleep(200)

    if (ConfirmState.result && WinExist(GameTitle)) {
        WinActivate(GameTitle)
        WinWaitActive(GameTitle, , 3)
    }

    CurrentConfirmUpdateFn := ""
    ConfirmState.isWaiting := false
    return ConfirmState.result
}

; =================================================================
; --- 【熱鍵區：完全限定在遊戲視窗內且未在確認狀態才有效】 ---
; =================================================================
#HotIf WinActive(GameTitle) && !isConfirming
;買車
F5:: {
    global isBuyCarRunning
    if (isBuyCarRunning) {
        StopGasAndClean()
    } else {
        ToggleBuyCarSequence()
    }
}
;賺技能點
F6:: {
    global isNewSequenceRunning
    if (isNewSequenceRunning) {
        StopGasAndClean()
    } else {
        ToggleNewSequence()
    }
}
;連點enter抽轉盤
F7:: {
    global isEnterSpamRunning
    if (isEnterSpamRunning) {
        StopGasAndClean()
    } else {
        ToggleEnterSpam()
    }
}
;刪除車再換車點技能
F8:: {
    global isSequenceRunning
    if (isSequenceRunning) {
        StopGasAndClean()
    } else {
        ToggleLButtonSequence()
    }
}
;刷錢
F9:: {
    global isGasOn
    if (isGasOn) {
        StopGasAndClean()
    } else {
        ToggleGas()
    }
}
;勁敵刷錢
F4:: {
    global isRivalRunning
    if (isRivalRunning) {
        StopGasAndClean()
    } else {
        ToggleRivalSequence()
    }
}

#HotIf WinActive(GameTitle)
F10:: {
    StopGasAndClean()
    MyGui.Destroy()
    ExitApp()
}
#HotIf

#HotIf ConfirmState.isWaiting
*Enter:: {
    global ConfirmState
    ConfirmState.result := true
    ConfirmState.isWaiting := false
}
*Esc:: {
    global ConfirmState
    ConfirmState.result := false
    ConfirmState.isWaiting := false
}
#HotIf

; =================================================================
; --- 【核心手把非同步監聽器】 ---
; =================================================================
WatchJoystick() {
    global isGasOn, isSequenceRunning, isEnterSpamRunning, isNewSequenceRunning, isBuyCarRunning, isConfirming, LongPressDelay, GameTitle, MyGui

    static wasXDown := false, xPressedTime := 0, xClickCount := 0, xLastClickTime := 0
    static wasYDown := false, yPressedTime := 0
    static wasLDown := false, lPressedTime := 0, lClickCount := 0, lLastClickTime := 0

    if (isConfirming) {
        wasXDown := wasYDown := wasLDown := false
        xPressedTime := yPressedTime := lPressedTime := 0
        xClickCount := lClickCount := 0
        return
    }

    if (!WinActive(GameTitle) && !WinActive("ahk_id " MyGui.Hwnd)) {
        wasXDown := wasYDown := wasLDown := false
        xPressedTime := yPressedTime := lPressedTime := 0
        xClickCount := lClickCount := 0
        return
    }

    ; =================================================================
    ; 【手把 X 鍵：Joy3】
    ; =================================================================
    isXDown := GetAnyJoyState(3)
    if (isXDown) {
        if (!wasXDown) {
            wasXDown := true
            xPressedTime := A_TickCount

            ; 觸發中按一下同鍵中斷 (F5 買車, F7 連點enter)
            if (isBuyCarRunning || isEnterSpamRunning) {
                StopGasAndClean()
                xPressedTime := 0 ; 避免重複觸發
            }
        } else {
            if (xPressedTime != 0) {
                elapsed := A_TickCount - xPressedTime
                ; 長按 X➟啟動 F7 (連點enter)
                if (elapsed >= LongPressDelay * 1000) {
                    xPressedTime := 0
                    xClickCount := 0 ; 清除雙擊
                    if (!isGasOn && !isSequenceRunning && !isEnterSpamRunning && !isNewSequenceRunning && !isBuyCarRunning && !isConfirming) {
                        SetTimer(ToggleEnterSpam, -10)
                    }
                }
            }
        }
    } else {
        if (wasXDown) {
            wasXDown := false
            if (xPressedTime != 0) {
                ; 短按放開，記錄點擊
                xClickCount++
                xLastClickTime := A_TickCount
            }
            xPressedTime := 0
        }
    }

    ; 雙擊 X 偵測 (間隔 300 毫秒內)
    if (xClickCount == 1 && A_TickCount - xLastClickTime > 300) {
        xClickCount := 0
    } else if (xClickCount == 2) {
        xClickCount := 0
        ; 啟動 F5 (買車)
        if (!isGasOn && !isSequenceRunning && !isEnterSpamRunning && !isNewSequenceRunning && !isBuyCarRunning && !isConfirming) {
            SetTimer(ToggleBuyCarSequence, -10)
        }
    }

    ; =================================================================
    ; 【手把 Y 鍵：Joy4】
    ; =================================================================
    isYDown := GetAnyJoyState(4)
    if (isYDown) {
        if (!wasYDown) {
            wasYDown := true
            yPressedTime := A_TickCount

            ; 觸發中按一下同鍵中斷 (F8 技能行程)
            if (isSequenceRunning) {
                StopGasAndClean()
                yPressedTime := 0
            }
        } else {
            if (yPressedTime != 0) {
                elapsed := A_TickCount - yPressedTime
                ; 長按 Y➟啟動 F8 (技能行程)
                if (elapsed >= LongPressDelay * 1000) {
                    yPressedTime := 0
                    if (!isGasOn && !isSequenceRunning && !isEnterSpamRunning && !isNewSequenceRunning && !isBuyCarRunning && !isConfirming) {
                        SetTimer(ToggleLButtonSequence, -10)
                    }
                }
            }
        }
    } else {
        wasYDown := false
        yPressedTime := 0
    }

    ; =================================================================
    ; 【手把 LB 鍵：Joy5】
    ; =================================================================
    isLDown := GetAnyJoyState(5)
    if (isLDown) {
        if (!wasLDown) {
            wasLDown := true
            lPressedTime := A_TickCount

            ; 觸發中按一下同鍵中斷 (F6 賺技能點)
            if (isNewSequenceRunning) {
                StopGasAndClean()
                lPressedTime := 0
            }
        } else {
            if (lPressedTime != 0) {
                elapsed := A_TickCount - lPressedTime
 
                ; 油門行程 (F9) 運行中➟長按 LB 中斷
                if (isGasOn) {
                    if (elapsed >= LongPressDelay * 1000) {
                        StopGasAndClean()
                        lPressedTime := 0
                    }
                } else {
                    ; 非運行中長按 LB➟啟動 F9 (油門行程)
                    if (elapsed >= LongPressDelay * 1000) {
                        lPressedTime := 0
                        lClickCount := 0 ; 清除雙擊
                        if (!isGasOn && !isSequenceRunning && !isEnterSpamRunning && !isNewSequenceRunning && !isBuyCarRunning && !isConfirming) {
                            SetTimer(ToggleGas, -10)
                        }
                    }
                }
            }
        }
    } else {
        if (wasLDown) {
            wasLDown := false
            if (lPressedTime != 0) {
                ; 短按放開，記錄點擊
                lClickCount++
                lLastClickTime := A_TickCount
            }
            lPressedTime := 0
        }
    }

    ; 雙擊 LB 偵測 (間隔 300 毫秒內)
    if (lClickCount == 1 && A_TickCount - lLastClickTime > 300) {
        lClickCount := 0
    } else if (lClickCount == 2) {
        lClickCount := 0
        ; 啟動 F6 (賺技能點)
        if (!isGasOn && !isSequenceRunning && !isEnterSpamRunning && !isNewSequenceRunning && !isBuyCarRunning && !isConfirming) {
            SetTimer(ToggleNewSequence, -10)
        }
    }

    ; =================================================================
    ; 【強制釋放：Joy9 (L3) + Joy10 (R3)】
    ; =================================================================
    isL3Down := GetAnyJoyState(9)
    isR3Down := GetAnyJoyState(10)
    if (isL3Down && isR3Down) {
        StopGasAndClean()
        Send("{w up}{a up}{s up}{d up}{x up}{Space up}{Down up}{Shift up}{Ctrl up}{Alt up}{Enter up}{Esc up}")
        ToolTip("⚠️ 已強制釋放所有按鍵！")
        SetTimer(() => ToolTip(), -1500)
    }
}

; =================================================================
; --- 【核心行程執行區】 ---
; =================================================================
RunEnterSpamSequence() {
    global isEnterSpamRunning, GameTitle, MyGui, isConfirming
    if (isEnterSpamRunning) {
        return
    }

    isConfirming := true
    confirmed := ShowConfirmDialog("連點 Enter 🎰", "∞", "∞")
    isConfirming := false

    if (!confirmed) {
        StopGasAndClean()
        return
    }

    isEnterSpamRunning := true
    UpdateUiRunningState("enterSpam")

    if WinExist(GameTitle) {
        WinActivate(GameTitle)
        WinWaitActive(GameTitle, , 2)
    }

    while (isEnterSpamRunning) {
        if (!WinActive(GameTitle) && !WinActive("ahk_id " MyGui.Hwnd)) {
            StopGasAndClean()
            break
        }
        Send("{Enter Down}")
        Sleep(100)
        Send("{Enter Up}")
        Sleep(1000)
    }
}

RunLButtonSequence(bypassConfirm := false) {
    global MyGui, ProgressText, isSequenceRunning, LoopCountLimit, currentLoopItem, GuiX, GuiY, GuiH, loopStartTime, TotalMs, isConfirming, SkillPoints, globalSkillPath, currentLoopTotalMs, AutoLoopEnabled, AutoLoopCount, SkillBuyCarEnabled
    global sequenceStartTime, sequenceTotalSec, NewSequenceLoopLimit, globalSkillCost, globalSegmentEnds, globalTotalMs
    global BuyCarMfgUp, BuyCarMfgDown, BuyCarMfgLeft, BuyCarMfgRight, BuyCarSelUp, BuyCarSelDown, BuyCarSelLeft, BuyCarSelRight
    if (isSequenceRunning) {
        return
    }
    isSequenceRunning := true

    buyCarEndActions := [
        ; --- 買車完畢後的收尾步驟 ---
        { key: "Esc", press: 80, wait: 1200, repeat: 3, tip: "買車完畢: 按 Esc ({1}/3)" },
        { key: "Right", press: 80, wait: 600, tip: "買車完畢: 按 ⮕" },
        { key: "Up", press: 80, wait: 600, tip: "買車完畢: 按 ⬆" }
    ]

    skillTransitActions := [
        ; --- 技能循環對接步驟 ---
        { key: "Up", press: 80, wait: 500, repeat: 2, tip: "技能循環對接: 按 ⬆ ({1}/2)" }
    ]

    skillEndActions := [
        ; --- 技能行程結尾步驟 ---
        { key: "Esc", press: 80, wait: 1200, tip: "技能結尾: 按 Esc (1/2)" },
        { key: "Esc", press: 80, wait: 1200, tip: "技能結尾: 按 Esc (2/2)" },
        { key: "Left", press: 80, wait: 450, tip: "技能結尾: 按 ⬅" }
    ]

    finalEndActions := [
        ; --- 技能行程最後一次結束的步驟 ---
        { key: "Enter", press: 80, wait: 1000, tip: "按 ⏎" },
        { key: "Down", press: 80, wait: 600, tip: "按 ⬇" },
        { key: "Enter", press: 80, wait: 1000, tip: "按 ⏎" },
        { key: "y", press: 80, wait: 1000, tip: "篩選 按 Y" },
        { key: "Enter", press: 80, wait: 1000, tip: "按 ⏎" },
        { key: "esc", press: 80, wait: 1000, tip: "按 Esc" },
        { key: "Enter", press: 80, wait: 1000, tip: "選車 按 ⏎" },
        { key: "Down", press: 80, wait: 500, tip: "乘駕車輛 按 ⬇" },
        { key: "Enter", press: 80, wait: 5000, tip: "按 ⏎" },
        { key: "y", press: 80, wait: 1000, tip: "篩選 按 Y" },
        { key: "x", press: 80, wait: 1000, tip: "重置 按 X" },
        { key: "esc", press: 80, wait: 1000, tip: "按 Esc" },
        { key: "x", press: 80, wait: 450, tip: "排序 按 X" },
        { key: "Down", press: 80, wait: 100, repeat: 12, tip: "最近新增 按 ⬇( {1}/6)" },
        { key: "Enter", press: 80, wait: 1000, tip: "按 ⏎" },
        { key: "Backspace", press: 80, wait: 1000, tip: "篩選 按 ⌫" },
        { key: "Enter", press: 80, wait: 600, tip: "到最新車輛 按 ⏎ " },
        { key: "Enter", press: 80, wait: 600, tip: "開啟選單按 ⏎" },
        { key: "Down", press: 80, wait: 100, repeat: 10, tip: "從車庫移除 按 ⬇( {1}/5)" },
        { key: "Enter", press: 80, wait: 600, tip: "按 ⏎" },
        { key: "Down", press: 80, wait: 600, tip: "確定移除 按 ⬇" },
        { key: "Enter", press: 80, wait: 600, tip: "按 ⏎" },
        { key: "Esc", press: 80, wait: 1200, repeat: 3, tip: "全部行程結束: 按 Esc ({1}/3)" }
    ]

    navPress := 100
    navWait := 1200
    enterPress := 100
    enterWait := 1200

    preActions := [
        ; --- 行程開始前按 ---
        { key: "esc", press: 80, wait: 1000, tip: "1. 按 Esc" },
        { key: "PgDn", press: 80, wait: 500, tip: "2. 按 PgDn" },
        { key: "Left", press: 80, wait: 500, tip: "3. 買賣車輛 按 ⬅" },
        { key: "Enter", press: 80, wait: 500, tip: "4. 按 ⏎ (1/2)" },
        { key: "Enter", press: 80, wait: 500, tip: "5. 去嘉年華 按 ⏎ (2/2)" },
        { sleep: 6000, countdown: true, tip: "4. 等待 4 秒" },
        { key: "Left", press: 80, wait: 500, tip: "7. 按 ⬅" },
        { key: "Down", press: 80, wait: 500, tip: "8. 收藏日誌 按 ⬇" },
        { key: "Enter", press: 80, wait: 500, tip: "9. 按 ⏎" },
        { sleep: 1000, countdown: true, tip: "等待 1 秒" },
        { key: "Right", press: 80, wait: 500, tip: "10. 探索大師 按 ⮕" },
        { key: "Enter", press: 80, wait: 500, tip: "11. 按 ⏎" },
        { key: "Down", press: 80, wait: 500, tip: "12. 車輛收藏 按 ⬇" },
        { key: "Enter", press: 80, wait: 500, tip: "13. 按 ⏎" },
        { key: "Right", press: 80, wait: 100, tip: "防漂移 按 ⮕" },
        { key: "Backspace", press: 80, wait: 500, tip: "14. 車廠 按 ⌫" },
        { key: "Left", press: 80, wait: 100, tip: "防漂移按 ⬅" }
    ]

    ; 15. 車廠垂直移動
    if (BuyCarMfgUp > 0) {
        preActions.Push({ key: "Up", press: 80, wait: 500, repeat: BuyCarMfgUp, tip: "15-Up. 選車廠 按 ⬆ (第 {1} 次/共 " . BuyCarMfgUp . " 次)" })
    }
    if (BuyCarMfgDown > 0) {
        preActions.Push({ key: "Down", press: 80, wait: 500, repeat: BuyCarMfgDown, tip: "15-Down. 選車廠 按 ⬇ (第 {1} 次/共 " . BuyCarMfgDown . " 次)" })
    }

    ; 16. 車廠水平移動
    if (BuyCarMfgLeft > 0) {
        preActions.Push({ key: "Left", press: 80, wait: 500, repeat: BuyCarMfgLeft, tip: "16-Left. 選車廠 按 ⬅ (第 {1} 次/共 " . BuyCarMfgLeft . " 次)" })
    }
    if (BuyCarMfgRight > 0) {
        preActions.Push({ key: "Right", press: 80, wait: 500, repeat: BuyCarMfgRight, tip: "16-Right. 選車廠 按 ⮕ (第 {1} 次/共 " . BuyCarMfgRight . " 次)" })
    }

    ; 17. 進入車廠
    preActions.Push({ key: "Enter", press: 80, wait: 500, tip: "17. 選車廠 按 Enter" })

    ; 18. 選車垂直與水平移動
    if (BuyCarSelUp > 0) {
        preActions.Push({ key: "Up", press: 80, wait: 500, repeat: BuyCarSelUp, tip: "18-Up. 選車 按 ⬆ (第 {1} 次/共 " . BuyCarSelUp . " 次)" })
    }
    if (BuyCarSelDown > 0) {
        preActions.Push({ key: "Down", press: 80, wait: 500, repeat: BuyCarSelDown, tip: "18-Down. 選車 按 ⬇ (第 {1} 次/共 " . BuyCarSelDown . " 次)" })
    }
    if (BuyCarSelLeft > 0) {
        preActions.Push({ key: "Left", press: 80, wait: 500, repeat: BuyCarSelLeft, tip: "18-Left. 選車 按 ⬅ (第 {1} 次/共 " . BuyCarSelLeft . " 次)" })
    }
    if (BuyCarSelRight > 0) {
        preActions.Push({ key: "Right", press: 80, wait: 500, repeat: BuyCarSelRight, tip: "18-Right. 選車 按 ⮕ (第 {1} 次/共 " . BuyCarSelRight . " 次)" })
    }

    buyCarActions := [
        ; --- 買車行程步驟 ---
        { key: "Space", press: 80, wait: 500, tip: "買車: 按 Space" },
        { key: "Down", press: 80, wait: 500, tip: "買車: 按 ⬇" },
        { key: "Enter", press: 80, wait: 500, tip: "買車: 按 ⏎ (1/3)" },
        { key: "Enter", press: 80, wait: 500, tip: "買車: 按 ⏎ (2/3)" },
        { key: "Enter", press: 80, wait: 1000, tip: "買車: 按 ⏎ (3/3)" }
    ]


    ; 由路徑產生導航按鍵序列的函數
    GenerateKeySequence(path := "") {
        if (path == "") {
            path := globalSkillPath
        }
        keys := []
        if (path.Length <= 1) {
            return keys
        }
        Loop path.Length - 1 {
            curr := path[A_Index]
            next := path[A_Index + 1]

            ; 判斷前進方向
            if (next.r < curr.r) {
                keys.Push("Up")
            } else if (next.r > curr.r) {
                keys.Push("Down")
            } else if (next.c < curr.c) {
                keys.Push("Left")
            } else if (next.c > curr.c) {
                keys.Push("Right")
            }
        }
        return keys
    }

    CalculateActionMs(action) {
        if (action.HasOwnProp("sleep")) {
            return action.sleep
        } else if (action.HasOwnProp("text")) {
            return action.HasOwnProp("wait") ? action.wait : 1000
        } else {
            repeat := action.HasOwnProp("repeat") ? action.repeat : 1
            return (action.press + action.wait) * repeat
        }
    }

    ; Calculate single loop times first
    local oneBuyLoopMs := 0
    for action in buyCarActions {
        oneBuyLoopMs += CalculateActionMs(action)
    }

    local navKeys := GenerateKeySequence(globalSkillPath)
    local navMs := 0
    for k in navKeys {
        navMs += (100 + 1200) * 2
    }
    local endMs := (100 + 1200) * 2 + (100 + 450)
 
    local firstLoopMs := 0
    for action in GetSkillStaticActions(1) {
        firstLoopMs += CalculateActionMs(action)
    }
    firstLoopMs += navMs + endMs

    local restLoopMs := 0
    for action in GetSkillStaticActions(2) {
        restLoopMs += CalculateActionMs(action)
    }
    restLoopMs += navMs + endMs

    CalculateTotalMs(path := "") {
        global SkillBuyCarEnabled
        if (path == "") {
            path := globalSkillPath
        }

        local totalMs := 0
        for idx, action in preActions {
            if (!SkillBuyCarEnabled && idx > 6) {
                break
            }
            totalMs += CalculateActionMs(action)
        }
        if (SkillBuyCarEnabled) {
            totalMs += oneBuyLoopMs * LoopCountLimit
            for action in buyCarEndActions {
                totalMs += CalculateActionMs(action)
            }
        }

        local navKeysPath := GenerateKeySequence(path)
        local singleNavMs := (navPress + navWait + enterPress + enterWait) * navKeysPath.Length

        local localEndMs := 0
        for action in skillEndActions {
            localEndMs += CalculateActionMs(action)
        }

        local tmpFirstMs := 0
        for action in GetSkillStaticActions(1) {
            tmpFirstMs += CalculateActionMs(action)
        }
        tmpFirstMs += singleNavMs + localEndMs + (navPress + 100) * 3 + (enterPress + enterWait)

        local tmpRestMs := 0
        for action in GetSkillStaticActions(2) {
            tmpRestMs += CalculateActionMs(action)
        }
        tmpRestMs += singleNavMs + localEndMs + (navPress + 100) * 3 + (enterPress + enterWait)

        totalMs += tmpFirstMs + (tmpRestMs * (LoopCountLimit - 1))

        if (LoopCountLimit > 1) {
            local transitMs := 0
            for action in skillTransitActions {
                transitMs += CalculateActionMs(action)
            }
            totalMs += (LoopCountLimit - 1) * transitMs
        }

        for action in finalEndActions {
            totalMs += CalculateActionMs(action)
        }

        return totalMs
    }

    SleepAndCheck(ms) {
        global isSequenceRunning, GameTitle, MyGui
        loop Ceil(ms / 100) {
            if (!isSequenceRunning || (!WinActive(GameTitle) && !WinActive("ahk_id " MyGui.Hwnd))) {
                return false
            }
            Sleep(100)
        }
        return true
    }

    CountdownSleep(totalMs, prefix) {
        global isSequenceRunning, GameTitle, MyGui
        startTime := A_TickCount
        while (isSequenceRunning && (A_TickCount - startTime < totalMs)) {
            if (!WinActive(GameTitle) && !WinActive("ahk_id " MyGui.Hwnd)) {
                return false
            }
            elapsedMs := A_TickCount - startTime
            remainingMs := totalMs - elapsedMs
            remainingSec := Ceil(remainingMs / 1000)
            if (remainingSec < 0) {
                remainingSec := 0
            }
            timeDisplay := FormatTimeDuration(remainingSec)
            ShowTip(prefix " (倒數" timeDisplay ")")
            Sleep(100)
        }
        return isSequenceRunning
    }
 
    recalcFn := (limit, skillPts, path := "") => (
        FormatTimeDuration(Ceil(CalculateTotalMs(path) / 1000))
    )
 
    confirmed := false
    if (bypassConfirm) {
        SkillPoints := Min(999, NewSequenceLoopLimit * 10)
        SkillBuyCarEnabled := true
        confirmed := true
    } else {
        AutoLoopEnabled := false  ; 手動啟動技能行程時，關閉自動雙循環
        SkillPoints := LoopCountLimit * globalSkillCost
        timeStr := recalcFn(LoopCountLimit, SkillPoints)
        extraParams := [
            { varRef: &SkillPoints, name: "技能點數", range: "30-999" }
        ]

        isConfirming := true
        confirmed := ShowConfirmDialog("技能行程 ⚡", timeStr, &LoopCountLimit, recalcFn, extraParams, "LoopCountLimit")
        isConfirming := false
    }
 
    if (!confirmed) {
        StopGasAndClean()
        return
    }

    LoopCountLimit := Floor(SkillPoints / globalSkillCost)
    if (LoopCountLimit < 1) {
        StopGasAndClean()
        return
    }

    ; 重新計算單次循環時間以反映確認後的最終路徑
    navKeys := GenerateKeySequence(globalSkillPath)
    navMs := 0
    for k in navKeys {
        navMs += (100 + 1200) * 2
    }
 
    firstLoopMs := 0
    for action in GetSkillStaticActions(1) {
        firstLoopMs += CalculateActionMs(action)
    }
    firstLoopMs += navMs + endMs + (navPress + 100) * 3 + (enterPress + enterWait)

    restLoopMs := 0
    for action in GetSkillStaticActions(2) {
        restLoopMs += CalculateActionMs(action)
    }
    restLoopMs += navMs + endMs + (navPress + 100) * 3 + (enterPress + enterWait)

    TotalMs := CalculateTotalMs()
    sequenceTotalSec := Ceil(TotalMs / 1000)

    if WinExist(GameTitle) {
        WinActivate(GameTitle)
        if !WinWaitActive(GameTitle, , 3) {
            StopGasAndClean()
            return
        }
    }

    ; 計算前置時間
    preparationMs := 0
    for idx, action in preActions {
        if (!SkillBuyCarEnabled && idx > 6) {
            break
        }
        preparationMs += CalculateActionMs(action)
    }
    if (SkillBuyCarEnabled) {
        preparationMs += oneBuyLoopMs * LoopCountLimit
        for action in buyCarEndActions {
            preparationMs += CalculateActionMs(action)
        }
    }

    ; 設定全域進度條變數
    global HasPreparationPhase
    HasPreparationPhase := true
    globalTotalMs := TotalMs
    globalSegmentEnds := [ preparationMs ]
    if (LoopCountLimit >= 1) {
        globalSegmentEnds.Push(preparationMs + firstLoopMs)
    }
    if (LoopCountLimit > 1) {
        local transitMs := 0
        for action in skillTransitActions {
            transitMs += CalculateActionMs(action)
        }
        Loop LoopCountLimit - 1 {
            globalSegmentEnds.Push(globalSegmentEnds[globalSegmentEnds.Length] + restLoopMs + transitMs)
        }
        local finalEndMs := 0
        for action in finalEndActions {
            finalEndMs += CalculateActionMs(action)
        }
        globalSegmentEnds.Push(globalTotalMs)
    }

    preActionsMs := 0
    for idx, action in preActions {
        if (!SkillBuyCarEnabled && idx > 6) {
            break
        }
        preActionsMs += CalculateActionMs(action)
    }
    buyCarEndMs := 0
    for action in buyCarEndActions {
        buyCarEndMs += CalculateActionMs(action)
    }

    global currentLoopStartTime, currentLoopDuration
    currentLoopStartTime := A_TickCount
    currentLoopDuration := preActionsMs
 
    DrawDividers()
    sequenceStartTime := A_TickCount
    loopStartTime := A_TickCount
    UpdateUiRunningState("seq")
    SetTimer(UpdateLoopProgress, 100)

    loopBreak := false

    ; --- 1. 執行前置步驟 (僅一次) ---
    for idx, action in preActions {
        if (!isSequenceRunning || (!WinActive(GameTitle) && !WinActive("ahk_id " MyGui.Hwnd))) {
            loopBreak := true
            break
        }

        ; 當不買車時，只執行前 6 步，第 7 步起直接跳過
        if (!SkillBuyCarEnabled && idx > 6) {
            break
        }

        if (action.HasOwnProp("sleep")) {
            if (action.HasOwnProp("countdown")) {
                if (!CountdownSleep(action.sleep, action.tip)) {
                    loopBreak := true
                    break
                }
            } else {
                ShowTip(action.tip)
                if (!SleepAndCheck(action.sleep)) {
                    loopBreak := true
                    break
                }
            }
        } else {
            repeat := action.HasOwnProp("repeat") ? action.repeat : 1
            if (repeat > 1) {
                repeatSuccess := true
                Loop repeat {
                    tipText := Format(action.tip, A_Index)
                    ShowTip(tipText)
                    if (!SendKey(action.key, action.press, action.wait, &isSequenceRunning)) {
                        repeatSuccess := false
                        break
                    }
                }
                if (!repeatSuccess) {
                    loopBreak := true
                    break
                }
            } else {
                ShowTip(action.tip)
                if (!SendKey(action.key, action.press, action.wait, &isSequenceRunning)) {
                    loopBreak := true
                    break
                }
            }
        }
    }

    ; --- 2. 執行買車次數循環 ---
    if (!loopBreak && SkillBuyCarEnabled && LoopCountLimit > 0) {
        Loop LoopCountLimit {
            currentLoopStartTime := A_TickCount
            currentLoopDuration := oneBuyLoopMs
            currentLoopItem := A_Index
            currentLoopTotalMs := oneBuyLoopMs
            if (!isSequenceRunning || (!WinActive(GameTitle) && !WinActive("ahk_id " MyGui.Hwnd))) {
                loopBreak := true
                break
            }
            buyCarLoopBreak := false
            for action in buyCarActions {
                ShowTip("[" A_Index "/5]" action.tip)
                if (!SendKey(action.key, action.press, action.wait, &isSequenceRunning)) {
                    buyCarLoopBreak := true
                    break
                }
            }
            if (buyCarLoopBreak) {
                loopBreak := true
                break
            }
        }
    }

    ; --- 3. 買車完畢後按 esc*3 與 Right 還有 Up ---
    if (!loopBreak && SkillBuyCarEnabled && LoopCountLimit > 0) {
        currentLoopStartTime := A_TickCount
        currentLoopDuration := buyCarEndMs
        for action in buyCarEndActions {
            repeat := action.HasOwnProp("repeat") ? action.repeat : 1
            if (repeat > 1) {
                repeatSuccess := true
                Loop repeat {
                    tipText := Format(action.tip, A_Index)
                    ShowTip(tipText)
                    if (!SendKey(action.key, action.press, action.wait, &isSequenceRunning)) {
                        repeatSuccess := false
                        break
                    }
                }
                if (!repeatSuccess) {
                    loopBreak := true
                    break
                }
            } else {
                ShowTip(action.tip)
                if (!SendKey(action.key, action.press, action.wait, &isSequenceRunning)) {
                    loopBreak := true
                    break
                }
            }
        }
    }

    ; --- 4. 執行點技能次數循環 ---
    if (!loopBreak) {
        currentLoopItem := 0
        Loop LoopCountLimit {
            if (!isSequenceRunning)
                break

            currentLoopItem := A_Index
            currentLoopTotalMs := (A_Index == 1) ? firstLoopMs : restLoopMs
            loopStartTime := A_TickCount
            currentLoopStartTime := A_TickCount
            currentLoopDuration := currentLoopTotalMs
 
            ; 執行點技能的前半靜態步驟
            skillBreak := false

            ; 僅在第二次以後的點技能循環中，開頭才按兩次 Up 對接畫面
            if (A_Index > 1) {
                for action in skillTransitActions {
                    repeat := action.HasOwnProp("repeat") ? action.repeat : 1
                    repeatSuccess := true
                    Loop repeat {
                        tipText := Format(action.tip, A_Index)
                        ShowTip(tipText)
                        if (!SendKey(action.key, action.press, action.wait, &isSequenceRunning)) {
                            repeatSuccess := false
                            break
                        }
                    }
                    if (!repeatSuccess) {
                        loopBreak := true
                        break
                    }
                }
                if (loopBreak)
                    break
            }

            for action in GetSkillStaticActions(A_Index) {
                if (action.HasOwnProp("sleep")) {
                    if (action.HasOwnProp("countdown")) {
                        if (!CountdownSleep(action.sleep, action.tip)) {
                            skillBreak := true
                            break
                        }
                    } else {
                        ShowTip(action.tip)
                        if (!SleepAndCheck(action.sleep)) {
                            skillBreak := true
                            break
                        }
                    }
                } else {
                    repeat := action.HasOwnProp("repeat") ? action.repeat : 1
                    if (repeat > 1) {
                        repeatSuccess := true
                        Loop repeat {
                            tipText := Format(action.tip, A_Index)
                            ShowTip(tipText)
                            if (!SendKey(action.key, action.press, action.wait, &isSequenceRunning)) {
                                repeatSuccess := false
                                break
                            }
                        }
                        if (!repeatSuccess) {
                            skillBreak := true
                            break
                        }
                    } else {
                        ShowTip(action.tip)
                        if (!SendKey(action.key, action.press, action.wait, &isSequenceRunning)) {
                            skillBreak := true
                            break
                        }
                    }
                }
            }
            if (skillBreak) {
                loopBreak := true
                break
            }

            ; 執行路徑導航前先按三次左確認游標對接
            ShowTip("技能導航前置: 按 ⬅ (1/3)")
            if (!SendKey("Left", navPress, 100, &isSequenceRunning)) {
                loopBreak := true
                break
            }
            ShowTip("技能導航前置: 按 ⬅ (2/3)")
            if (!SendKey("Left", navPress, 100, &isSequenceRunning)) {
                loopBreak := true
                break
            }
            ShowTip("技能導航前置: 按 ⬅ (3/3)")
            if (!SendKey("Left", navPress, 100, &isSequenceRunning)) {
                loopBreak := true
                break
            }

            ; 點選起點的技能
            ShowTip("技能導航前置: 按 Enter (點選起點)")
            if (!SendKey("Enter", enterPress, enterWait, &isSequenceRunning)) {
                loopBreak := true
                break
            }

            ; 執行路徑導航
            navKeys := GenerateKeySequence()
            pathBreak := false
            for key in navKeys {
                ShowTip("技能導航: 按 " key)
                if (!SendKey(key, navPress, navWait, &isSequenceRunning)) {
                    pathBreak := true
                    break
                }
 
                ShowTip("技能導航: 按 Enter")
                if (!SendKey("Enter", enterPress, enterWait, &isSequenceRunning)) {
                    pathBreak := true
                    break
                }
            }
            if (pathBreak) {
                loopBreak := true
                break
            }

            ; 結尾兩次 Esc 退出與 Left 移動
            for action in skillEndActions {
                ShowTip(action.tip)
                if (!SendKey(action.key, action.press, action.wait, &isSequenceRunning)) {
                    loopBreak := true
                    break
                }
            }
            if (loopBreak)
                break

            if (isSequenceRunning && A_Index < LoopCountLimit) {
                if (!SleepAndCheck(1500)) {
                    loopBreak := true
                    break
                }
            }
        }
    }

    ; --- 5. 最後一次結尾按三次 esc ---
    if (isSequenceRunning) {
        for action in finalEndActions {
            repeat := action.HasOwnProp("repeat") ? action.repeat : 1
            Loop repeat {
                tipText := Format(action.tip, A_Index)
                ShowTip(tipText)
                if (!SendKey(action.key, action.press, action.wait, &isSequenceRunning)) {
                    break
                }
            }
        }
    }
    if (!loopBreak) {
        if (AutoLoopEnabled && !StopAfterCurrentLoop) {
            ; 行程全部結束後等待一分鐘 (60 秒)
            sequenceStartTime := A_TickCount
            sequenceTotalSec := 60
            loopStartTime := A_TickCount
            currentLoopTotalMs := 60000
            currentLoopItem := 1
            LoopCountLimit := 1

            if (CountdownSleep(30000, "雙循環過場：等待 30 秒")) {
                AutoLoopCount++
                isSequenceRunning := false
                SetTimer(UpdateLoopProgress, 0)
;                Send("{w up}{a up}{s up}{d up}{x up}{Space up}{Down up}{Shift up}{Ctrl up}{Alt up}{Enter up}{Esc up}")
                SetTimer(RunNewSequence.Bind(true), -100)
                return
            }
        }
    }

    StopGasAndClean()
}

WatchGameWindow() {
    global GameTitle, MyGui, GuiX, GuiY, GuiH, isConfirming, isPauseFocusCheck
    global isSequenceRunning, isNewSequenceRunning, isBuyCarRunning, isEnterSpamRunning, isGasOn, isRivalRunning
    static isShowing := false
    static lastX := -9999, lastY := -9999

    if (isConfirming || isPauseFocusCheck || isEditBoxMode) {
        return
    }

    currentActive := WinActive(GameTitle) || WinActive("ahk_id " MyGui.Hwnd) || (isEditBoxMode && EditBoxMenuGui && WinActive("ahk_id " EditBoxMenuGui.Hwnd)) || (isEditBoxMode && EditBoxWindowGui && WinActive("ahk_id " EditBoxWindowGui.Hwnd))
    if (currentActive) {
        try {
            ; ⬛ 拋棄所有狀態偵測：純粹、無條件抓取遊戲視窗的 X 與 Y
            WinGetPos(&wX, &wY, &wW, &wH, GameTitle)

            GuiX := wX + 4
            GuiY := wY + 0
        } catch {
            GuiX := 0
            GuiY := 0
        }

        if (!isShowing) {
            isRunning := (isSequenceRunning || isNewSequenceRunning || isBuyCarRunning || isEnterSpamRunning || isGasOn || isRivalRunning)
            if (isRunning) {
                runName := isBuyCarRunning ? "buyCar" : (isNewSequenceRunning ? "newSeq" : (isEnterSpamRunning ? "enterSpam" : (isSequenceRunning ? "seq" : (isGasOn ? "gas" : "rival"))))
                UpdateUiRunningState(runName)
            } else {
                ResetUiToNormal()
            }
            isShowing := true
            lastX := GuiX
            lastY := GuiY
        } else {
            isRunning := (isSequenceRunning || isNewSequenceRunning || isBuyCarRunning || isEnterSpamRunning || isGasOn || isRivalRunning)
            if (isRunning) {
                ; 行程運行中，強制確認進度條為顯示狀態，防誤隱藏
                if (isRivalRunning && RivalLoopLimit == 0) {
                    if (ProgressBar.Visible) {
                        ProgressBar.Visible := false
                        ProgressBar.Move(-100, -100)
                    }
                } else if (isNewSequenceRunning || isSequenceRunning || isBuyCarRunning || (isRivalRunning && RivalLoopLimit > 0)) {
                    if (!ProgressBar.Visible)
                        ProgressBar.Visible := true
                }
                if (isNewSequenceRunning || isSequenceRunning || isBuyCarRunning || isRivalRunning) {
                    if (!LoopProgressBar.Visible)
                        LoopProgressBar.Visible := true
                    if (!ProgressText.Visible)
                        ProgressText.Visible := true
                }
            }
            ; 只要遊戲視窗位置有變動（被拖曳移動），UI 就即時無縫跟隨
            if (GuiX != lastX || GuiY != lastY) {
                try {
                    WinMove(GuiX, GuiY, , , "ahk_id " MyGui.Hwnd)
                    MyGui.Redraw()
                }
                lastX := GuiX
                lastY := GuiY
            }
        }
    } else {
        if (isShowing) {
            MyGui.Hide()
            StopGasAndClean()
            isShowing := false
        }
    }
}

; =================================================================
; --- 【行程安全互斥連動控制區】 ---
; =================================================================
ToggleEnterSpam() {
    global isGasOn, isSequenceRunning, isEnterSpamRunning, isNewSequenceRunning, isBuyCarRunning, isConfirming
    if (isGasOn || isSequenceRunning || isEnterSpamRunning || isNewSequenceRunning || isBuyCarRunning || isConfirming) {
        return
    }
    SetTimer(RunEnterSpamSequence, -10)
}

ToggleLButtonSequence() {
    global isGasOn, isSequenceRunning, isEnterSpamRunning, isNewSequenceRunning, isBuyCarRunning, isConfirming
    if (isGasOn || isSequenceRunning || isEnterSpamRunning || isNewSequenceRunning || isBuyCarRunning || isConfirming) {
        return
    }
    SetTimer(RunLButtonSequence, -10)
}

ToggleGas() {
    global isGasOn, isSequenceRunning, isEnterSpamRunning, isNewSequenceRunning, isBuyCarRunning, isConfirming
    if (isGasOn || isSequenceRunning || isEnterSpamRunning || isNewSequenceRunning || isBuyCarRunning || isConfirming) {
        return
    }

    isConfirming := true
    confirmed := ShowConfirmDialog("油門行程 🏆", "∞", "∞")
    isConfirming := false

    if (!confirmed) {
        StopGasAndClean()
        return
    }

    isGasOn := true
    UpdateUiRunningState("gas")
    SetTimer(InfiniteGasLoop, -10)
}

ToggleNewSequence() {
    global isGasOn, isSequenceRunning, isEnterSpamRunning, isNewSequenceRunning, isBuyCarRunning, isConfirming
    if (isGasOn || isSequenceRunning || isEnterSpamRunning || isNewSequenceRunning || isBuyCarRunning || isConfirming) {
        return
    }
    SetTimer(RunNewSequence, -10)
}

ToggleBuyCarSequence() {
    global isGasOn, isSequenceRunning, isEnterSpamRunning, isNewSequenceRunning, isBuyCarRunning, isConfirming
    if (isGasOn || isSequenceRunning || isEnterSpamRunning || isNewSequenceRunning || isBuyCarRunning || isConfirming) {
        return
    }
    SetTimer(RunBuyCarSequence, -10)
}

RunNewSequence(bypassConfirm := false) {
    global isNewSequenceRunning, GameTitle, MyGui, NewSequenceLoopLimit, currentNewLoopItem, newLoopStartTime, NewSequenceTotalMs, GuiX, GuiY, GuiH, isConfirming, AutoLoopEnabled, AutoLoopCount, labcode, isPauseFocusCheck
    global sequenceStartTime, sequenceTotalSec, globalSkillCost, globalSegmentEnds, globalTotalMs
    if (isNewSequenceRunning) {
        return
    }
    isNewSequenceRunning := true

    preActions := [
        ; --- 行程開始前按 ---
        { key: "esc", press: 80, wait: 1000, tip: "1. 按 Esc" },
        { key: "PgUp", press: 80, wait: 1000, tip: "2. 商店 按 PgUp (1/2)" },
        { key: "PgUp", press: 80, wait: 1000, tip: "3. 創意中心 按 PgUp (2/2)" },
        { key: "Enter", press: 80, wait: 1000, tip: "4. 按 ⏎" },
        { key: "Down", press: 80, wait: 1000, tip: "5. 遊玩挑戰 按 ⬇" },
        { key: "Enter", press: 80, wait: 1000, tip: "6. 按 ⏎" },
        { key: "Backspace", press: 80, wait: 500, tip: "7. 搜尋 按 ⌫" },
        { key: "Up", press: 80, wait: 1000, tip: "8. 分享代碼 按 Up" },
        { key: "Enter", press: 80, wait: 1000, pauseFocus: true, tip: "9. 按 ⏎" },
        { waitForBlack: true, timeout: 10000, estimatedWait: 1500, tip: "9.5. 偵測黑色背景" },
        { text: labcode, wait: 2000, tip: "10. 貼上分享代碼" },
        { key: "Enter", press: 80, wait: 1500, tip: "10. 按 ⏎ 搜尋代碼" },
        { clickCenter: true, wait: 500, tip: "10.5. 點擊頂部空白處脫離輸入框" },
        { key: "Down", press: 80, wait: 1000, tip: "11. 確認 按 ⬇" },
        { key: "Enter", press: 80, wait: 1000, tip: "12. 按 ⏎" },
        { waitForYellow: true, estimatedWait: 2000, resumeFocus: true, tip: "12.5. 偵測黃色卡片載入" },
        { key: "Enter", press: 80, wait: 1000, tip: "13. 按 ⏎" },
        { waitForProgressBarEndNotBlack: true, timeout: 45000, estimatedWait: 20000, tip: "14. 進場完成" }
    ]

    ; --- 循環步驟主體 ---
    loopActions := [
        { key: "w", estimatedWait: 24000, wait: 1000, tip: "15-1. 按住 W 前進" }
    ]

    ; --- 賺技能點最後一次循環步驟 ---
    lastLoopActions := [
        { key: "w", estimatedWait: 24000, wait: 1000, tip: "15-1. 按住 W 前進" }
    ]

    CalculateActionMs(action) {
        if (action.HasOwnProp("sleep")) {
            return action.sleep
        } else if (action.HasOwnProp("dynamicWaitVar")) {
            return (%action.dynamicWaitVar% * 1000) + action.wait
        } else if (action.HasOwnProp("estimatedWait")) {
            return action.estimatedWait + (action.HasOwnProp("wait") ? action.wait : 0)
        } else if (action.HasOwnProp("text")) {
            return action.HasOwnProp("wait") ? action.wait : 1000
        } else if (action.HasOwnProp("clickCenter")) {
            return action.HasOwnProp("wait") ? action.wait : 500
        } else if (action.HasOwnProp("waitForYellow")) {
            return action.HasOwnProp("estimatedWait") ? action.estimatedWait : 2000
        } else if (action.HasOwnProp("waitForBlack")) {
            return action.HasOwnProp("estimatedWait") ? action.estimatedWait : 1500
        } else if (action.HasOwnProp("waitForProgressBarEndNotBlack")) {
            return action.HasOwnProp("estimatedWait") ? action.estimatedWait : 20000
        } else {
            repeat := action.HasOwnProp("repeat") ? action.repeat : 1
            return (action.press + action.wait) * repeat
        }
    }

    CalculateActionListMs(actionList) {
        local total := 0
        for action in actionList {
            total += CalculateActionMs(action)
        }
        return total
    }

    CalculateTotalMs(limit, includeAutoLoop := false) {
        local total := CalculateActionListMs(preActions)

        if (limit > 1) {
            total += CalculateActionListMs(loopActions) * (limit - 1)
            total += CalculateActionListMs(lastLoopActions)
        } else if (limit == 1) {
            total += CalculateActionListMs(lastLoopActions)
        }

        ; 若啟用自動雙循環，加上點技能（與買車）的預估時間，以及 30 秒過場等待時間
        if (includeAutoLoop) {
            local earnedPoints := Min(999, limit * 10)
            local neededPoints := globalSkillCost
            local skillLimit := Floor(earnedPoints / neededPoints)
            if (skillLimit >= 1) {
                total += 30000 ; 雙循環過場等待 30 秒
 
                ; 點技能行程中的常數設定
                local navPress := 100
                local navWait := 1200
                local enterPress := 100
                local enterWait := 1200

                ; 宣告並動態取得點技能行程所需的陣列與函數
                local skillPreActions := [
                    { key: "esc", press: 80, wait: 1000, tip: "1. 按 Esc" },
                    { key: "PgDn", press: 80, wait: 500, tip: "2. 按 PgDn" },
                    { key: "Left", press: 80, wait: 500, tip: "3. 買賣車輛 按 ⬅" },
                    { key: "Enter", press: 80, wait: 500, tip: "4. 去嘉年華 按 ⏎ (1/2)" },
                    { key: "Enter", press: 80, wait: 500, tip: "5. 按 ⏎ (2/2)" },
                    { sleep: 6000, countdown: true, tip: "4. 等待 4 秒" },
                    { key: "Left", press: 80, wait: 500, tip: "7. 按 ⬅" },
                    { key: "Down", press: 80, wait: 500, tip: "8. 收藏日誌 按 ⬇" },
                    { key: "Enter", press: 80, wait: 500, tip: "9. 按 ⏎" },
                    { sleep: 1000, countdown: true, tip: "等待 1 秒" },
                    { key: "Right", press: 80, wait: 500, tip: "10. 探索大師 按 ⮕" },
                    { key: "Enter", press: 80, wait: 500, tip: "11. 按 ⏎" },
                    { key: "Down", press: 80, wait: 500, tip: "12. 車輛收藏 按 ⬇" },
                    { key: "Enter", press: 80, wait: 500, tip: "13. 按 ⏎" },
                    { key: "Right", press: 80, wait: 100, tip: "防漂移 按 ⮕" },
                    { key: "Backspace", press: 80, wait: 500, tip: "14. 車廠 按 ⌫" },
                    { key: "Left", press: 80, wait: 100, tip: "防漂移按 ⬅" }
                ]

                if (BuyCarMfgUp > 0) {
                    skillPreActions.Push({ key: "Up", press: 80, wait: 500, repeat: BuyCarMfgUp })
                }
                if (BuyCarMfgDown > 0) {
                    skillPreActions.Push({ key: "Down", press: 80, wait: 500, repeat: BuyCarMfgDown })
                }
                if (BuyCarMfgLeft > 0) {
                    skillPreActions.Push({ key: "Left", press: 80, wait: 500, repeat: BuyCarMfgLeft })
                }
                if (BuyCarMfgRight > 0) {
                    skillPreActions.Push({ key: "Right", press: 80, wait: 500, repeat: BuyCarMfgRight })
                }
                skillPreActions.Push({ key: "Enter", press: 80, wait: 500 })
                if (BuyCarSelUp > 0) {
                    skillPreActions.Push({ key: "Up", press: 80, wait: 500, repeat: BuyCarSelUp })
                }
                if (BuyCarSelDown > 0) {
                    skillPreActions.Push({ key: "Down", press: 80, wait: 500, repeat: BuyCarSelDown })
                }
                if (BuyCarSelLeft > 0) {
                    skillPreActions.Push({ key: "Left", press: 80, wait: 500, repeat: BuyCarSelLeft })
                }
                if (BuyCarSelRight > 0) {
                    skillPreActions.Push({ key: "Right", press: 80, wait: 500, repeat: BuyCarSelRight })
                }

                local skillBuyCarActions := [
                    { key: "Space", press: 80, wait: 500 },
                    { key: "Down", press: 80, wait: 500 },
                    { key: "Enter", press: 80, wait: 500 },
                    { key: "Enter", press: 80, wait: 500 },
                    { key: "Enter", press: 80, wait: 1000 }
                ]

                local skillBuyCarEndActions := [
                    { key: "Esc", press: 80, wait: 1200, repeat: 3 },
                    { key: "Right", press: 80, wait: 600 },
                    { key: "Up", press: 80, wait: 600 }
                ]

                local skillTransitActions := [
                    { key: "Up", press: 80, wait: 500, repeat: 2 }
                ]

                local skillEndActions := [
                    { key: "Esc", press: 80, wait: 1200 },
                    { key: "Esc", press: 80, wait: 1200 },
                    { key: "Left", press: 80, wait: 450 }
                ]

                local skillFinalEndActions := [
                    { key: "Esc", press: 80, wait: 1200, repeat: 3 }
                ]

                local skillPreMs := 0
                for idx, action in skillPreActions {
                    if (!SkillBuyCarEnabled && idx > 6) {
                        break
                    }
                    skillPreMs += CalculateActionMs(action)
                }
                if (SkillBuyCarEnabled) {
                    local oneBuyLoopMs := 0
                    for action in skillBuyCarActions {
                        oneBuyLoopMs += CalculateActionMs(action)
                    }
                    skillPreMs += oneBuyLoopMs * skillLimit
                    for action in skillBuyCarEndActions {
                        skillPreMs += CalculateActionMs(action)
                    }
                }
 
                local navKeysCount := 0
                if (globalSkillPath.Length > 1) {
                    navKeysCount := globalSkillPath.Length - 1
                }
                local singleNavMs := (navPress + navWait + enterPress + enterWait) * navKeysCount
 
                local localEndMs := 0
                for action in skillEndActions {
                    localEndMs += CalculateActionMs(action)
                }
 
                local tmpFirstMs := 0
                for action in GetSkillStaticActions(1) {
                    tmpFirstMs += CalculateActionMs(action)
                }
                tmpFirstMs += (navPress + 100) * 3 + (enterPress + enterWait)
                tmpFirstMs += singleNavMs + localEndMs
 
                local tmpRestMs := 0
                for action in GetSkillStaticActions(2) {
                    tmpRestMs += CalculateActionMs(action)
                }
                tmpRestMs += (navPress + 100) * 3 + (enterPress + enterWait)
                tmpRestMs += singleNavMs + localEndMs
 
                total += skillPreMs + tmpFirstMs + (tmpRestMs * (skillLimit - 1))
 
                if (skillLimit > 1) {
                    local transitMs := 0
                    for action in skillTransitActions {
                        transitMs += CalculateActionMs(action)
                    }
                    total += (skillLimit - 1) * transitMs
                }
 
                for action in skillFinalEndActions {
                    total += CalculateActionMs(action)
                }
            }
        }

        return total
    }

    SleepAndCheck(ms) {
        global isNewSequenceRunning, GameTitle, MyGui, isPauseFocusCheck
        loop Ceil(ms / 100) {
            if (!isNewSequenceRunning) {
                return false
            }
            if (!isPauseFocusCheck && (!WinActive(GameTitle) && !WinActive("ahk_id " MyGui.Hwnd))) {
                return false
            }
            Sleep(100)
        }
        return true
    }

    CountdownSleep(totalMs, prefix) {
        global isNewSequenceRunning, GameTitle, MyGui, isPauseFocusCheck
        startTime := A_TickCount
        while (isNewSequenceRunning && (A_TickCount - startTime < totalMs)) {
            if (!isPauseFocusCheck && (!WinActive(GameTitle) && !WinActive("ahk_id " MyGui.Hwnd))) {
                return false
            }
            elapsedMs := A_TickCount - startTime
            remainingMs := totalMs - elapsedMs
            remainingSec := Ceil(remainingMs / 1000)
            if (remainingSec < 0) {
                remainingSec := 0
            }
            timeDisplay := FormatTimeDuration(remainingSec)
            ShowTip(prefix " (倒數" timeDisplay ")")
            Sleep(100)
        }
        return isNewSequenceRunning
    }

    recalcFn := (limit) => (
        FormatTimeDuration(Ceil(CalculateTotalMs(limit, AutoLoopEnabled) / 1000))
    )
    timeStr := recalcFn(NewSequenceLoopLimit)

    confirmed := false
    if (bypassConfirm) {
        confirmed := true
    } else {
        isConfirming := true
        confirmed := ShowConfirmDialog("賺技能點 ⚔", timeStr, &NewSequenceLoopLimit, recalcFn, "", "NewSequenceLoopLimit")
        isConfirming := false

        if (confirmed) {
            if (AutoLoopEnabled) {
                AutoLoopCount := 1
            } else {
                AutoLoopCount := 0
            }
        }
    }

    if (!confirmed) {
        StopGasAndClean()
        return
    }

    local oneLoopTotalMs := 0
    for action in loopActions {
        oneLoopTotalMs += CalculateActionMs(action)
    }
    NewSequenceTotalMs := oneLoopTotalMs
    sequenceTotalSec := Ceil(CalculateTotalMs(NewSequenceLoopLimit, false) / 1000)

    if WinExist(GameTitle) {
        WinActivate(GameTitle)
        if !WinWaitActive(GameTitle, , 3) {
            StopGasAndClean()
            return
        }
    }

    global isPauseProgressBar, totalRatingPauseMs
    isPauseProgressBar := false
    totalRatingPauseMs := 0

    preMs := CalculateActionListMs(preActions)
    oneLoopMs := CalculateActionListMs(loopActions)
    finalLoopMs := CalculateActionListMs(lastLoopActions)
 
    global HasPreparationPhase
    HasPreparationPhase := true
    globalTotalMs := CalculateTotalMs(NewSequenceLoopLimit, false)
    globalSegmentEnds := [ preMs ]
    Loop NewSequenceLoopLimit - 1 {
        globalSegmentEnds.Push(globalSegmentEnds[globalSegmentEnds.Length] + oneLoopMs)
    }
    globalSegmentEnds.Push(globalSegmentEnds[globalSegmentEnds.Length] + finalLoopMs)
 
    global currentLoopStartTime, currentLoopDuration
    currentLoopStartTime := A_TickCount
    currentLoopDuration := preMs

    DrawDividers()
    sequenceStartTime := A_TickCount
    newLoopStartTime := A_TickCount
    UpdateUiRunningState("newSeq")
    SetTimer(UpdateNewLoopProgress, 100)

    firstTripMeasured := false
    loopBreak := false
    while (isNewSequenceRunning && !loopBreak) {
        restartFromStep1 := false
        completedLoops := 0

        UpdateUiRunningState("newSeq")
        ; 若從綠色評分恢復，在此處精確恢復進度條推進
        if (isPauseProgressBar) {
            currentLoopStartTime := A_TickCount
            isPauseProgressBar := false
        }

        preIdx := 1
        while (preIdx <= preActions.Length) {
            action := preActions[preIdx]

            if (action.HasOwnProp("pauseFocus") && action.pauseFocus) {
                isPauseFocusCheck := true
            }

            if (!isNewSequenceRunning) {
                loopBreak := true
                break
            }
            if (!isPauseFocusCheck && (!WinActive(GameTitle) && !WinActive("ahk_id " MyGui.Hwnd))) {
                loopBreak := true
                break
            }
            
            if (action.HasOwnProp("sleep")) {
                if (action.HasOwnProp("countdown")) {
                    if (!CountdownSleep(action.sleep, action.tip)) {
                        loopBreak := true
                        break
                    }
                } else {
                    ShowTip(action.tip)
                    if (!SleepAndCheck(action.sleep)) {
                        loopBreak := true
                        break
                    }
                }
            } else if (action.HasOwnProp("text")) {
                ShowTip(action.tip)
                if (!SendTextAction(action.text, action.HasOwnProp("wait") ? action.wait : 1000, &isNewSequenceRunning)) {
                    loopBreak := true
                    break
                }
            } else if (action.HasOwnProp("clickCenter")) {
                ShowTip(action.tip)
                try {
                    WinActivate(GameTitle)
                    WinGetPos(&wX, &wY, &wW, &wH, GameTitle)
                    ; 點擊輸入框上方的遊戲空白區塊 (50% 寬度, 15% 高度) 以關閉螢幕觸控鍵盤並脫離焦點
                    cX := wX + Floor(wW * 0.50)
                    cY := wY + Floor(wH * 0.15)
                    CoordMode("Mouse", "Screen")
                    MouseMove(cX, cY)
                    Sleep(100)
                    Click("Down")
                    Sleep(120)
                    Click("Up")
                    Sleep(200)
                }
                if (!SleepAndCheck(action.HasOwnProp("wait") ? action.wait : 500)) {
                    loopBreak := true
                    break
                }
            } else if (action.HasOwnProp("waitForYellow")) {
                isPauseProgressBar := true
                pauseStart := A_TickCount
                success := DetectYellowCard()
                detectCost := A_TickCount - pauseStart
                sequenceStartTime += detectCost
                currentLoopStartTime += detectCost
                newLoopStartTime += detectCost
                totalRatingPauseMs += detectCost
                isPauseProgressBar := false
                if (!success) {
                    if (!isNewSequenceRunning) {
                        loopBreak := true
                        break
                    }
                    isPauseFocusCheck := false
                    ShowTip("12.5. 超時未偵測到黃卡：已按 Esc 退出，重試返回第 6 步...")
                    preIdx := 6
                    continue
                }
                ShowTip(action.tip)
            } else if (action.HasOwnProp("waitForBlack")) {
                isPauseProgressBar := true
                pauseStart := A_TickCount
                success := DetectBlackBelowProgress()
                detectCost := A_TickCount - pauseStart
                sequenceStartTime += detectCost
                currentLoopStartTime += detectCost
                newLoopStartTime += detectCost
                totalRatingPauseMs += detectCost
                isPauseProgressBar := false
                if (!success) {
                    loopBreak := true
                    break
                }
                ShowTip(action.tip)
            } else if (action.HasOwnProp("waitForProgressBarEndNotBlack")) {
                timeoutVal := action.HasOwnProp("timeout") ? action.timeout : 35000
                isPauseProgressBar := true
                pauseStart := A_TickCount
                success := DetectProgressBarEndNotBlack(timeoutVal)
                detectCost := A_TickCount - pauseStart
                sequenceStartTime += detectCost
                currentLoopStartTime += detectCost
                newLoopStartTime += detectCost
                totalRatingPauseMs += detectCost
                isPauseProgressBar := false
                if (!success) {
                    loopBreak := true
                    break
                }
                ShowTip(action.tip)
            } else {
                repeat := action.HasOwnProp("repeat") ? action.repeat : 1
                if (repeat > 1) {
                    repeatSuccess := true
                    Loop repeat {
                        tipText := Format(action.tip, A_Index)
                        ShowTip(tipText)
                        if (!SendKey(action.key, action.press, action.wait, &isNewSequenceRunning)) {
                            repeatSuccess := false
                            break
                        }
                    }
                    if (!repeatSuccess) {
                        loopBreak := true
                        break
                    }
                } else {
                    ShowTip(action.tip)
                    if (!SendKey(action.key, action.press, action.wait, &isNewSequenceRunning)) {
                        loopBreak := true
                        break
                    }
                }
            }

            if (action.HasOwnProp("resumeFocus") && action.resumeFocus) {
                isPauseFocusCheck := false
            }

            preIdx++
        }

        if (loopBreak || !isNewSequenceRunning) {
            break
        }

        ; --- 執行循環步驟主體 ---
        while (completedLoops < NewSequenceLoopLimit && !loopBreak && isNewSequenceRunning) {
            if (StopAfterCurrentLoop) {
                loopBreak := true
                break
            }

            completedLoops++
            currentNewLoopItem := completedLoops

            if (completedLoops < NewSequenceLoopLimit) {
                if (!CheckAndWait5AMReboot(Ceil(oneLoopMs / 1000), &isNewSequenceRunning)) {
                    loopBreak := true
                    break
                }
            }
            newLoopStartTime := A_TickCount
            currentLoopStartTime := A_TickCount
            currentLoopDuration := (completedLoops == NewSequenceLoopLimit) ? finalLoopMs : oneLoopMs

            if (!WinActive(GameTitle) && !WinActive("ahk_id " MyGui.Hwnd)) {
                loopBreak := true
                break
            }

            isLastLoop := (completedLoops == NewSequenceLoopLimit)
            currentActions := isLastLoop ? lastLoopActions : loopActions
            restartFromStep1 := false

            for action in currentActions {
                if (action.HasOwnProp("sleep")) {
                    sleepMs := action.sleep
                    tipText := action.tip

                    if (action.HasOwnProp("countdown")) {
                        if (!CountdownSleep(sleepMs, tipText)) {
                            loopBreak := true
                            break
                        }
                    } else {
                        ShowTip(tipText)
                        if (!SleepAndCheck(sleepMs)) {
                            loopBreak := true
                            break
                        }
                    }
                } else if (action.HasOwnProp("dynamicWaitVar") || (action.HasOwnProp("key") && action.key == "w")) {
                    wSuccess := false
                    if (action.key == "w") {
                        ; 繪製左上角「剩餘時間/目標/目前」三條黑色標頭持久青色虛線偵測外框
                        try {
                            WinGetPos(&wX, &wY, &wW, &wH, GameTitle)
                            bx1 := wX + Floor(wW * 0.012), by1 := wY + Floor(wH * 0.025)
                            bw := Floor(wW * 0.143), bh := Floor(wH * 0.135)
                            wBoxGui := CreateDashedBoxGui(bx1, by1, bw, bh, "0x00FFFF", 2, 12, 6)
                        } catch {
                            wBoxGui := ""
                        }

                        ; 1. 先等待 5 秒緩衝讓遊戲賽事介面載入 (此時不按 W)
                        CountdownSleep(5000, "15-1. 等待 5 秒緩衝")

                        ; 2. 等待賽事介面出現
                        hasSeenBlack := false
                        blackWaitStart := A_TickCount
                        while (isNewSequenceRunning) {
                            if (!isPauseFocusCheck && (!WinActive(GameTitle) && !WinActive("ahk_id " MyGui.Hwnd))) {
                                break
                            }
                            if (DetectTopLeftThreeBlackBarsExist(false)) {
                                hasSeenBlack := true
                                break
                            }
                            ShowTip("15-1. 等待賽事介面出現...")
                            Sleep(100)
                        }
                        blackWaitMs := A_TickCount - blackWaitStart

                        ; 3. 介面出現後，正式按住 W 前進
                        interfaceDisappearMs := 0
                        if (hasSeenBlack && isNewSequenceRunning) {
                            SendInput("{w Down}")
                            wHoldStart := A_TickCount
                            lastWSubKeyTime := wHoldStart
                            nextWSubKey := "Up"

                            while (isNewSequenceRunning) {
                                if (!isPauseFocusCheck && (!WinActive(GameTitle) && !WinActive("ahk_id " MyGui.Hwnd))) {
                                    wSuccess := false
                                    break
                                }
                                
                                hasBlackCurrent := DetectTopLeftThreeBlackBarsExist(false)

                                ; 當三條黑色底條完全消失時，觸發緩衝並鬆開 W
                                if (!hasBlackCurrent) {
                                    wSuccess := true
                                    interfaceDisappearMs := A_TickCount - wHoldStart
                                    ShowTip("15-1. 偵測到介面消失：緩衝等待 1 秒後鬆開 W...")
                                    CountdownSleep(1000, "15-1. 介面消失：緩衝等待 1 秒準備鬆開 W")
                                    break
                                }

                                if (A_TickCount - lastWSubKeyTime >= 5000) {
                                    SendWPeriodicKey(&nextWSubKey)
                                    lastWSubKeyTime := A_TickCount
                                }

                                estMs := action.HasOwnProp("estimatedWait") ? action.estimatedWait : 24000
                                estSec := Floor(estMs / 1000)
                                elapsedSec := Floor((A_TickCount - wHoldStart) / 1000)
                                remSec := Max(0, estSec - elapsedSec)
                                wPrefix := "按住 W " . FormatSecToMinSec(estSec)
                                ShowTip(wPrefix . " (倒數" . FormatSecToMinSec(remSec) . ")")
                                Sleep(100)
                            }
                        }

                        ; 第一趟完成時，紀錄「等黑色」與「介面消失」時間相加，更新後續循環預估剩餘時間
                        if (!firstTripMeasured && wSuccess) {
                            actualStep15_1_Ms := blackWaitMs + interfaceDisappearMs
                            estimatedStep15_1_Ms := CalculateActionMs(action)
                            diffMs := actualStep15_1_Ms - estimatedStep15_1_Ms

                            globalTotalMs += diffMs * NewSequenceLoopLimit
                            sequenceTotalSec := Max(1, Ceil(globalTotalMs / 1000))
                            oneLoopMs += diffMs
                            finalLoopMs += diffMs

                            globalSegmentEnds := [ preMs ]
                            Loop NewSequenceLoopLimit - 1 {
                                globalSegmentEnds.Push(globalSegmentEnds[globalSegmentEnds.Length] + oneLoopMs)
                            }
                            globalSegmentEnds.Push(globalSegmentEnds[globalSegmentEnds.Length] + finalLoopMs)

                            DrawDividers()
                            firstTripMeasured := true
                        }

                        if (wBoxGui != "") {
                            try {
                                wBoxGui.Destroy()
                            }
                        }
                    } else {
                        if (action.HasOwnProp("dynamicWaitVar")) {
                            holdMs := %action.dynamicWaitVar% * 1000
                        } else if (action.HasOwnProp("estimatedWait")) {
                            holdMs := action.estimatedWait
                        } else {
                            holdMs := 24000
                        }
                        SendInput("{" action.key " Down}")

                        if (action.key == "w") {
                            wSuccess := HoldWWithPeriodicKeys(holdMs, action.tip, &isNewSequenceRunning)
                        } else if (action.HasOwnProp("countdown")) {
                            wSuccess := CountdownSleep(holdMs, action.tip)
                        } else {
                            ShowTip(action.tip)
                            wSuccess := SleepAndCheck(holdMs)
                        }
                    }

                    ShowTip("釋放 " action.key " 鍵")
                    if (action.key == "w") {
                        ForceReleaseW_Hardware()
                    } else {
                        SendInput("{" action.key " Up}")
                    }

                    if (!wSuccess) {
                        loopBreak := true
                        break
                    }

                    ; ----------------------------------------------------
                    ; 放開 W 鍵後的按鍵與顏色偵測流程
                    ; ----------------------------------------------------
                    if (!isLastLoop) {
                        ShowTip("15-2. 重新開始：按 Enter")
                        if (!SendKey("Enter", 250, 500, &isNewSequenceRunning)) {
                            loopBreak := true
                            break
                        }

                        ; 循環 1.2 秒持續檢查是否彈出綠色評分介面 (防止選單動畫彈出延遲)
                        hasGreenRating := false
                        loop 12 {
                            if (DetectGreenRatingCard()) {
                                hasGreenRating := true
                                break
                            }
                            Sleep(100)
                        }

                        if (hasGreenRating) {
                            ShowTip("15-2. 偵測到評分介面(綠色)：按 ⏎ 評分中...")
                            
                            ; 凍結進度條（保持顯示暫停）並記錄開始時間
                            isPauseProgressBar := true
                            pauseStart := A_TickCount

                            SendKey("Enter", 250, 1000, &isNewSequenceRunning)
                            
                            ; 評分完成後等待 20 秒過場
                            CountdownSleep(20000, "15-2. 評分完成：等待 20 秒過場")

                            ; 將額外過場與評分耗時加入總累積暫停時間（不列入計時與進度）
                            totalRatingPauseMs += (A_TickCount - pauseStart)
                            isPauseProgressBar := false

                            restartFromStep1 := true
                            UpdateUiRunningState("newSeq")
                            break
                        }

                        ; 無綠色評分介面：等待 3 秒後準備偵測非黑色載入
                        CountdownSleep(3000, "15-2. 等待賽道就緒")
                        ; 偵測進度條右下非黑色
                        ShowTip("15-2. 等待畫面載入...")
                        
                        ; 凍結進度條（保持顯示暫停）
                        isPauseProgressBar := true
                        pauseStart := A_TickCount

                        notBlackSuccess := DetectProgressBarEndNotBlack(35000)

                        ; 恢復進度條更新，將偵測等待耗時納入累積暫停時間（不列入計時與進度）
                        totalRatingPauseMs += (A_TickCount - pauseStart)
                        isPauseProgressBar := false

                        if (!notBlackSuccess) {
                            loopBreak := true
                            break
                        }
                    } else {
                        ShowTip("15-2. 最後一次循環：按 Esc 結束")
                        if (!SendKey("Esc", 250, 1000, &isNewSequenceRunning)) {
                            loopBreak := true
                            break
                        }

                        ShowTip("15-3. 評價：按 ⏎")
                        if (!SendKey("Enter", 250, 1000, &isNewSequenceRunning)) {
                            loopBreak := true
                            break
                        }

                        ShowTip("15-4. 確認評價：按 ⏎")
                        if (!SendKey("Enter", 250, 1000, &isNewSequenceRunning)) {
                            loopBreak := true
                            break
                        }

                        CountdownSleep(20000, "15-5. 行程結束：等待 20 秒過場")
                    }
                }
            }

            if (restartFromStep1) {
                break ; 跳出內層 while 循環，回到外層 while 重新執行 preActions (從第一步開始)！
            }
            if (loopBreak) {
                break
            }
        }

        if (!restartFromStep1) {
            break ; 若正常完成所有循環且未觸發 restartFromStep1，結束外層 while 迴圈！
        }
    }

    ; --- 自動雙循環接續判斷 ---
    if (!loopBreak) {
        if (AutoLoopEnabled && !StopAfterCurrentLoop) {
            earnedPoints := Min(999, NewSequenceLoopLimit * 10)
            neededPoints := globalSkillCost
            loopCount := Floor(earnedPoints / neededPoints)
            if (loopCount >= 1) {
                ShowTip("雙循環：準備接續點技能行程...")
                Sleep(1000)
                isNewSequenceRunning := false
                SetTimer(UpdateNewLoopProgress, 0)
;                Send("{w up}{a up}{s up}{d up}{x up}{Space up}{Down up}{Shift up}{Ctrl up}{Alt up}{Enter up}{Esc up}")
                SetTimer(RunLButtonSequence.Bind(true), -100)
                return
            }
        }
    }

    ShowTip("")
    StopGasAndClean()
}

RunBuyCarSequence() {
    global isBuyCarRunning, GameTitle, MyGui, BuyCarLoopLimit, currentBuyCarLoopItem, buyCarStartTime, BuyCarTotalMs, GuiX, GuiY, GuiH, isConfirming
    global sequenceStartTime, sequenceTotalSec, globalSegmentEnds, globalTotalMs
    global BuyCarMfgUp, BuyCarMfgDown, BuyCarMfgLeft, BuyCarMfgRight, BuyCarSelUp, BuyCarSelDown, BuyCarSelLeft, BuyCarSelRight
    if (isBuyCarRunning) {
        return
    }
    isBuyCarRunning := true

    staticActions := [
        { key: "Space", press: 80, wait: 500, tip: "1. 買車 按 Space (250ms)" },
        { key: "Down", press: 80, wait: 500, tip: "2. 確定 按 ⬇ (250ms)" },
        { key: "Enter", press: 80, wait: 500, tip: "3. 按 ⏎ (1/3)" },
        { key: "Enter", press: 80, wait: 500, tip: "4. 按 ⏎ (2/3)" },
        { key: "Enter", press: 80, wait: 1000, tip: "5. 按 ⏎ (3/3)" }
    ]

    CalculateTotalMs(mfgUp := BuyCarMfgUp, mfgDown := BuyCarMfgDown, mfgLeft := BuyCarMfgLeft, mfgRight := BuyCarMfgRight, selUp := BuyCarSelUp, selDown := BuyCarSelDown, selLeft := BuyCarSelLeft, selRight := BuyCarSelRight) {
        local totalMs := 0
        for action in staticActions {
            if (action.HasOwnProp("sleep")) {
                totalMs += action.sleep
            } else {
                repeat := action.HasOwnProp("repeat") ? action.repeat : 1
                totalMs += (action.press + action.wait) * repeat
            }
        }
        return totalMs
    }

    SleepAndCheck(ms) {
        global isBuyCarRunning, GameTitle, MyGui
        loop Ceil(ms / 100) {
            if (!isBuyCarRunning || (!WinActive(GameTitle) && !WinActive("ahk_id " MyGui.Hwnd))) {
                return false
            }
            Sleep(100)
        }
        return true
    }

    recalcFn := (limit, mfgUp := 0, mfgDown := 0, mfgLeft := 0, mfgRight := 0, selUp := 0, selDown := 0, selLeft := 0, selRight := 0) => (
        dynamicTotalMs := CalculateTotalMs(mfgUp, mfgDown, mfgLeft, mfgRight, selUp, selDown, selLeft, selRight),
        FormatTimeDuration(Ceil((limit * dynamicTotalMs) / 1000))
    )
    extraParams := [
        { name: "車廠 往上(格數)", varRef: &BuyCarMfgUp, range: "0-20" },
        { name: "車廠 往下(格數)", varRef: &BuyCarMfgDown, range: "0-20" },
        { name: "車廠 往左(格數)", varRef: &BuyCarMfgLeft, range: "0-3" },
        { name: "車廠 往右(格數)", varRef: &BuyCarMfgRight, range: "0-3" },
        { name: "選車 往上(格數)", varRef: &BuyCarSelUp, range: "0-20" },
        { name: "選車 往下(格數)", varRef: &BuyCarSelDown, range: "0-20" },
        { name: "選車 往左(格數)", varRef: &BuyCarSelLeft, range: "0-4" },
        { name: "選車 往右(格數)", varRef: &BuyCarSelRight, range: "0-4" }
    ]
    timeStr := recalcFn(BuyCarLoopLimit, BuyCarMfgUp, BuyCarMfgDown, BuyCarMfgLeft, BuyCarMfgRight, BuyCarSelUp, BuyCarSelDown, BuyCarSelLeft, BuyCarSelRight)
 
    isConfirming := true
    confirmed := ShowConfirmDialog("買車行程 🚗", timeStr, &BuyCarLoopLimit, recalcFn, extraParams, "BuyCarLoopLimit")
    isConfirming := false

    if (!confirmed) {
        StopGasAndClean()
        return
    }

    if (BuyCarLoopLimit <= 0) {
        StopGasAndClean()
        return
    }

    BuyCarTotalMs := CalculateTotalMs()
    sequenceTotalSec := Ceil((BuyCarLoopLimit * BuyCarTotalMs) / 1000)

    if WinExist(GameTitle) {
        WinActivate(GameTitle)
        if !WinWaitActive(GameTitle, , 3) {
            StopGasAndClean()
            return
        }
    }

    global HasPreparationPhase
    HasPreparationPhase := false
    globalTotalMs := BuyCarLoopLimit * BuyCarTotalMs
    globalSegmentEnds := []
    Loop BuyCarLoopLimit {
        globalSegmentEnds.Push(A_Index * BuyCarTotalMs)
    }

    global currentLoopStartTime, currentLoopDuration
    DrawDividers()
    sequenceStartTime := A_TickCount
    UpdateUiRunningState("buyCar")
    SetTimer(UpdateBuyCarLoopProgress, 100)

    currentBuyCarLoopItem := 0
    Loop BuyCarLoopLimit {
        if (!isBuyCarRunning)
            break
        currentBuyCarLoopItem := A_Index
        buyCarStartTime := A_TickCount
        currentLoopStartTime := A_TickCount
        currentLoopDuration := BuyCarTotalMs

        if (!WinActive(GameTitle) && !WinActive("ahk_id " MyGui.Hwnd)) {
            StopGasAndClean()
            break
        }

        loopBreak := false
        for action in staticActions {
            if (action.HasOwnProp("sleep")) {
                ShowTip(action.tip)
                if (!SleepAndCheck(action.sleep)) {
                    loopBreak := true
                    break
                }
            } else {
                repeat := action.HasOwnProp("repeat") ? action.repeat : 1
                if (repeat > 1) {
                    repeatSuccess := true
                    Loop repeat {
                        tipText := Format(action.tip, A_Index)
                        ShowTip(tipText)
                        if (!SendKey(action.key, action.press, action.wait, &isBuyCarRunning)) {
                            repeatSuccess := false
                            break
                        }
                    }
                    if (!repeatSuccess) {
                        loopBreak := true
                        break
                    }
                } else {
                    ShowTip(action.tip)
                    if (!SendKey(action.key, action.press, action.wait, &isBuyCarRunning)) {
                        loopBreak := true
                        break
                    }
                }
            }
        }
        if (loopBreak)
            break
    }
    ShowTip("")
    StopGasAndClean()
}

UpdateLoopProgress() {
    global isSequenceRunning, sequenceStartTime, globalTotalMs, ProgressBar, LoopProgressBar, ProgressText, currentStepText, MyGui
    global currentLoopStartTime, currentLoopDuration
    static lastLoopVal := -1
    static lastSubLoopVal := -1
    
    if (!isSequenceRunning) {
        SetTimer(UpdateLoopProgress, 0)
        return
    }

    elapsedTotal := A_TickCount - sequenceStartTime
    if (elapsedTotal < 200) {
        lastLoopVal := -1
        lastSubLoopVal := -1
    }
    
    percent := Integer(Min(10000, Max(0, (elapsedTotal / globalTotalMs) * 10000)))
    newLoopVal := Integer(percent * 570 / 10000)
    
    elapsedLoop := A_TickCount - currentLoopStartTime
    loopPercent := (currentLoopDuration > 0) ? Integer(Min(10000, Max(0, (elapsedLoop / currentLoopDuration) * 10000))) : 0
    newSubLoopVal := Integer(loopPercent * 570 / 10000)

    if (newLoopVal != lastLoopVal || newSubLoopVal != lastSubLoopVal) {
        ProgressBar.Value := percent
        LoopProgressBar.Value := loopPercent
        lastLoopVal := newLoopVal
        lastSubLoopVal := newSubLoopVal
    }
    ShowTip(currentStepText)
}

UpdateNewLoopProgress() {
    global isNewSequenceRunning, sequenceStartTime, globalTotalMs, ProgressBar, LoopProgressBar, ProgressText, currentStepText, MyGui, IsWaitingReboot, isPauseProgressBar, totalRatingPauseMs, pauseStart
    global currentLoopStartTime, currentLoopDuration
    static lastLoopVal := -1
    static lastSubLoopVal := -1

    if (!isNewSequenceRunning) {
        SetTimer(UpdateNewLoopProgress, 0)
        return
    }

    if (IsWaitingReboot) {
        return
    }

    ; 1. 黃色進度條：計算扣除顏色/過場偵測等待後的總進度（偵測期間時間不計入）
    currentPauseMs := isPauseProgressBar ? (A_TickCount - pauseStart) : 0
    elapsedTotal := A_TickCount - sequenceStartTime - totalRatingPauseMs - currentPauseMs
    if (elapsedTotal < 200) {
        lastLoopVal := -1
        lastSubLoopVal := -1
    }
    percent := Integer(Min(10000, Max(0, (elapsedTotal / globalTotalMs) * 10000)))
    newLoopVal := Integer(percent * 570 / 10000)

    ; 2. 藍色進度條：單圈進度（顏色/過場偵測期間保持暫停不前進）
    elapsedLoop := isPauseProgressBar ? (pauseStart - currentLoopStartTime) : (A_TickCount - currentLoopStartTime)
    loopPercent := (currentLoopDuration > 0) ? Integer(Min(10000, Max(0, (elapsedLoop / currentLoopDuration) * 10000))) : 0
    newSubLoopVal := Integer(loopPercent * 570 / 10000)

    ; 僅在像素位置有變動時更新，防止頻繁重繪造成閃爍
    if (newLoopVal != lastLoopVal || newSubLoopVal != lastSubLoopVal) {
        ProgressBar.Value := percent
        LoopProgressBar.Value := loopPercent
        lastLoopVal := newLoopVal
        lastSubLoopVal := newSubLoopVal
    }

    ShowTip(currentStepText)
}

UpdateBuyCarLoopProgress() {
    global isBuyCarRunning, sequenceStartTime, globalTotalMs, ProgressBar, LoopProgressBar, ProgressText, currentStepText, MyGui
    global currentLoopStartTime, currentLoopDuration
    static lastLoopVal := -1
    static lastSubLoopVal := -1

    if (!isBuyCarRunning) {
        SetTimer(UpdateBuyCarLoopProgress, 0)
        return
    }

    elapsedTotal := A_TickCount - sequenceStartTime
    if (elapsedTotal < 200) {
        lastLoopVal := -1
        lastSubLoopVal := -1
    }
    percent := Integer(Min(10000, Max(0, (elapsedTotal / globalTotalMs) * 10000)))
    newLoopVal := Integer(percent * 570 / 10000)
    
    elapsedLoop := A_TickCount - currentLoopStartTime
    loopPercent := (currentLoopDuration > 0) ? Integer(Min(10000, Max(0, (elapsedLoop / currentLoopDuration) * 10000))) : 0
    newSubLoopVal := Integer(loopPercent * 570 / 10000)

    if (newLoopVal != lastLoopVal || newSubLoopVal != lastSubLoopVal) {
        ProgressBar.Value := percent
        LoopProgressBar.Value := loopPercent
        lastLoopVal := newLoopVal
        lastSubLoopVal := newSubLoopVal
        if (ProgressText && ProgressText.Visible) {
            ProgressText.Redraw()
        }
    }
    ShowTip(currentStepText)
}

UpdateRivalLoopProgress() {
    global isRivalRunning, sequenceStartTime, globalTotalMs, ProgressBar, LoopProgressBar, ProgressText, currentStepText, MyGui, IsWaitingReboot, RivalLoopLimit
    global currentLoopStartTime, currentLoopDuration
    static lastLoopVal := -1
    static lastSubLoopVal := -1

    if (!isRivalRunning) {
        SetTimer(UpdateRivalLoopProgress, 0)
        return
    }

    if (IsWaitingReboot) {
        return
    }

    elapsedTotal := A_TickCount - sequenceStartTime
    if (elapsedTotal < 200) {
        lastLoopVal := -1
        lastSubLoopVal := -1
    }
    percent := 0
    if (RivalLoopLimit > 0) {
        percent := Integer(Min(10000, Max(0, (elapsedTotal / globalTotalMs) * 10000)))
    }
    newLoopVal := Integer(percent * 570 / 10000)
    
    elapsedLoop := A_TickCount - currentLoopStartTime
    loopPercent := (currentLoopDuration > 0) ? Integer(Min(10000, Max(0, (elapsedLoop / currentLoopDuration) * 10000))) : 0
    newSubLoopVal := Integer(loopPercent * 570 / 10000)

    if (newLoopVal != lastLoopVal || newSubLoopVal != lastSubLoopVal) {
        if (RivalLoopLimit > 0) {
            ProgressBar.Value := percent
        }
        LoopProgressBar.Value := loopPercent
        lastLoopVal := newLoopVal
        lastSubLoopVal := newSubLoopVal
        if (ProgressText && ProgressText.Visible) {
            ProgressText.Redraw()
        }
    }
    ShowTip(currentStepText)
}

InfiniteGasLoop() {
    global isGasOn, GameTitle, MyGui
 
    if WinExist(GameTitle) {
        WinActivate(GameTitle)
        WinWaitActive(GameTitle, , 2)
    }

    while (isGasOn) {
        startTime := A_TickCount
        randomHoldTime := Random(55000, 65000)
        if (isGasOn) {
            Send("{w Down}")
        }

        lastWSubKeyTime := A_TickCount
        nextWSubKey := "Up"

        while (isGasOn && (A_TickCount - startTime < randomHoldTime)) {
            if (!WinActive(GameTitle) && !WinActive("ahk_id " MyGui.Hwnd)) {
                StopGasAndClean()
                return
            }

            if (A_TickCount - lastWSubKeyTime >= 5000) {
                SendWPeriodicKey(&nextWSubKey)
                lastWSubKeyTime := A_TickCount
            }

            Sleep(100)
        }
        if (!isGasOn)
            break

        Send("{w Up}")
        randomReleaseTime := Random(500, 800)
        sleepTime := A_TickCount
        while (isGasOn && (A_TickCount - sleepTime < randomReleaseTime)) {
            if (!WinActive(GameTitle) && !WinActive("ahk_id " MyGui.Hwnd)) {
                StopGasAndClean()
                return
            }
            Sleep(50)
        }
    }
    ForceReleaseW_Hardware()
}

CheckEveryHourly() {
    static lastTriggeredHour := -1
    global isGasOn, GameTitle, StatusBtn
    if (A_Min == 0 && lastTriggeredHour != A_Hour) {
        lastTriggeredHour := A_Hour
        if (isGasOn == true) {
            isGasOn := false
            ForceReleaseW_Hardware()
            if WinExist(GameTitle) {
                WinActivate(GameTitle)
                Sleep(1200)
            }
            Send("{Enter Down}")
            Sleep(250)
            Send("{Enter Up}")
            Sleep(5000)
            Send("{Enter Down}")
            Sleep(250)
            Send("{Enter Up}")
            Sleep(2000)
            Send("{c Down}")
            Sleep(250)
            Send("{c Up}")
            Sleep(1000)
            Send("{2 Down}")
            Sleep(250)
            Send("{2 Up}")
            Sleep(10000)

            if (WinActive(GameTitle)) {
                isGasOn := true
                UpdateUiRunningState("gas")
                SetTimer(InfiniteGasLoop, -10)
            } else {
                ResetUiToNormal()
            }
        }
    }
}

StopGasAndClean() {
    global MyGui, isGasOn, isSequenceRunning, isEnterSpamRunning, isNewSequenceRunning, isBuyCarRunning, ProgressText, PreProgressBar, ProgressBar, LoopProgressBar, GuiX, GuiY, GuiH, currentStepText, isRivalRunning, AutoLoopCount, HasPreparationPhase, StopAfterCurrentLoop, SkipBtn, isPauseFocusCheck
    global isEditBoxMode, EditBoxMenuGui, EditBoxWindowGui

    if (isEditBoxMode) {
        isEditBoxMode := false
        SetTimer(UpdateEditBoxCoords, 0)
        if (EditBoxWindowGui != "") {
            try EditBoxWindowGui.Destroy()
            EditBoxWindowGui := ""
        }
        if (EditBoxMenuGui != "") {
            try EditBoxMenuGui.Destroy()
            EditBoxMenuGui := ""
        }
    }

    isPauseFocusCheck := false
    isGasOn := false
    isSequenceRunning := false
    isEnterSpamRunning := false
    isNewSequenceRunning := false
    isBuyCarRunning := false
    isRivalRunning := false
    AutoLoopCount := 0
    HasPreparationPhase := false
    SetTimer(UpdateLoopProgress, 0)
    SetTimer(UpdateNewLoopProgress, 0)
    SetTimer(UpdateBuyCarLoopProgress, 0)
    SetTimer(UpdateRivalLoopProgress, 0)

    if (ProgressText) {
        ProgressText.Value := ""
    }
    PreProgressBar.Value := 0
    ProgressBar.Value := 0
    LoopProgressBar.Value := 0
    ShowTip("")
    ClearDividers()

    StopAfterCurrentLoop := false
    if (SkipBtn) {
        SkipBtn.Opt("cWhite")
        SkipBtn.Visible := false
        SkipBtn.Move(-100, -100)
    }
    if WinExist("ahk_id " MyGui.Hwnd) {
        ResetUiToNormal()
    }
    ForceReleaseW_Hardware()
}

ShowTip(stepText) {
    global GuiX, GuiY, currentStepText, ProgressText, sequenceStartTime, sequenceTotalSec, MyGui, globalTotalMs
    global isSequenceRunning, loopStartTime, TotalMs, currentLoopItem, LoopCountLimit
    global isNewSequenceRunning, newLoopStartTime, NewSequenceTotalMs, currentNewLoopItem, NewSequenceLoopLimit
    global isBuyCarRunning, buyCarStartTime, BuyCarTotalMs, currentBuyCarLoopItem, BuyCarLoopLimit
    global isRivalRunning, currentRivalLoopItem, RivalLoopLimit
    global totalActionSteps, currentActIdx, currentStepStartTime, currentStepTotalMs

    static lastInfoText := ""

    if (stepText == "") {
        currentStepText := ""
        if (ProgressText) {
            ProgressText.Value := ""
        }
        lastInfoText := ""
        ToolTip()
        return
    }

    displayTip := stepText
    displayTip := StrReplace(displayTip, "Enter", "⏎")
    displayTip := StrReplace(displayTip, "Backspace", "⌫")
    displayTip := StrReplace(displayTip, "Space", "⎵")
    displayTip := StrReplace(displayTip, "Down", "⬇")
    displayTip := StrReplace(displayTip, "Up", "⬆")
    displayTip := StrReplace(displayTip, "Left", "⬅")
    displayTip := StrReplace(displayTip, "Right", "⮕")
    displayTip := StrReplace(displayTip, "↵", "⏎")

    currentStepText := stepText

    cur := 0, limit := 0
    if (isSequenceRunning) {
        cur := currentLoopItem, limit := LoopCountLimit
    } else if (isNewSequenceRunning) {
        cur := currentNewLoopItem, limit := NewSequenceLoopLimit
    } else if (isBuyCarRunning) {
        cur := currentBuyCarLoopItem, limit := BuyCarLoopLimit
    } else if (isRivalRunning) {
        cur := currentRivalLoopItem, limit := RivalLoopLimit
    } else {
        tipX := GuiX
        tipY := GuiY + GuiH + 5
        CoordMode("ToolTip", "Screen")
        ToolTip(displayTip, tipX, tipY)
        SetTimer(() => ToolTip(), -3000)
        return
    }
 
    ; 💡 1. 計算單圈進度水藍條 (loopPercent) - 採用時間加權演算法，讓進度條速度與真實時間 100% 絕對勻速一致！
    if (IsSet(staticActionStartMs) && staticActionStartMs.Length >= currentActIdx && currentActIdx > 0 && currentLoopDuration > 0) {
        stepStartMs := staticActionStartMs[currentActIdx]
        stepDurMs := staticActionDurMs[currentActIdx]
        stepElapsed := (currentStepStartTime > 0) ? (A_TickCount - currentStepStartTime) : 0
        stepInternalMs := Min(stepDurMs, Max(0, stepElapsed))
        
        currentAccumulatedMs := stepStartMs + stepInternalMs
        loopPercent := Min(100.0, Max(0.0, (currentAccumulatedMs / currentLoopDuration) * 100.0))
    } else {
        elapsedLoop := A_TickCount - currentLoopStartTime
        loopPercent := (currentLoopDuration > 0) ? Min(100.0, Max(0.0, (elapsedLoop / currentLoopDuration) * 100)) : 0
    }

    ; 💡 2. 組合提示文字 (infoText) 與總進度黃條 (totalPercentVal)
    if (isRivalRunning && RivalLoopLimit == 0) {
        infoText := "↻" cur "➤" displayTip
        totalPercentVal := 0
    } else {
        if (limit > 0) {
            curIndex := (cur > 0) ? cur : 1
            totalPercentVal := Min(100.0, Max(0.0, ((curIndex - 1) + (loopPercent / 100.0)) / limit * 100.0))
            percent := Integer(totalPercentVal)
        } else {
            totalPercentVal := 0
            percent := 0
        }

        singleLoopSec := (currentLoopDuration > 0) ? (currentLoopDuration / 1000.0) : 30.0
        remainingLoops := Max(0, limit - cur)
        remSec := Max(0, Ceil(remainingLoops * singleLoopSec + (1.0 - loopPercent / 100.0) * singleLoopSec))
        countdownStr := FormatTimeDuration(remSec)

        prefix := (AutoLoopEnabled && AutoLoopCount > 0) ? "↻" AutoLoopCount "" : ""
        infoText := prefix "[" cur "/" limit "]" percent "％" countdownStr "➤" displayTip
    }

    if (ProgressPic && ProgressPic.Visible) {
        w := (SkipBtn && SkipBtn.Visible) ? 570 : 610
        RenderProgressBarBitmap(loopPercent, totalPercentVal, infoText, w, 28)
    }
}

ToggleRivalSequence() {
    global isGasOn, isSequenceRunning, isEnterSpamRunning, isNewSequenceRunning, isBuyCarRunning, isRivalRunning, isConfirming
    if (isGasOn || isSequenceRunning || isEnterSpamRunning || isNewSequenceRunning || isBuyCarRunning || isRivalRunning || isConfirming) {
        return
    }
    SetTimer(RunRivalSequence, -10)
}

RunRivalSequence() {
    global isRivalRunning, GameTitle, MyGui, RivalThrottleSec, RivalLoopLimit, currentRivalLoopItem, rivalLoopStartTime, RivalTotalMs, GuiX, GuiY, GuiH, isConfirming, RivalLoadSec, RivalTransitionSec, RivalEndHour, RivalEndMin
    global sequenceStartTime, sequenceTotalSec, globalSegmentEnds, globalTotalMs
    global totalActionSteps, currentActIdx, currentStepStartTime, currentStepTotalMs
    if (isRivalRunning) {
        return
    }
    isRivalRunning := true

    staticActions := [
        { key: "Esc", press: 80, wait: 500, detectColor: 7, timeout: 10000, estimatedWait: 2500, retryStep: true, tip: "1. 按 Esc (等待左側桃色選單)" }, ; 10s逾時：重新按 Esc
        { key: "PgDn", press: 80, wait: 500, tip: "2. 按 PgDn (1/3)" },
        { key: "PgDn", press: 80, wait: 500, tip: "3. 按 PgDn (2/3)" },
        { key: "PgDn", press: 80, wait: 500, tip: "4. 按 PgDn (3/3)" },
        { key: "Down", press: 80, wait: 500, tip: "5. 勁敵 按 ⬇" },
        { detectColor: 8, timeout: 3000, estimatedWait: 1000, retryFromStep1: true, tip: "5.5. 驗證桃色區塊吻合" }, ; 3s逾時：按 Esc 返回第 1 步
        { key: "Enter", press: 80, wait: 1000, tip: "6. 勁敵 按 ⏎ (1/3)" },
        { key: "Enter", press: 80, wait: 2000, tip: "7. 公路競速賽 按 ⏎ (2/3)" },
        { key: "Enter", press: 80, wait: 1000, tip: "8. 高速公路環道 按 ⏎ (3/3)" },
        { key: "Enter", press: 80, wait: 1500, tip: "11. 按 ⏎" },
        { key: "Left", press: 80, wait: 500, tip: "12. 性能R 按 ⬅" },
        { detectColor: 13, timeout: 9000, estimatedWait: 2500, retryStep12: true, tip: "12.5. 偵測性能R" }, ; 9s逾時：按 ⬅ 重試偵測
        { detectRedR: 10, timeout: 9000, estimatedWait: 2500, retryRightLeft: true, actionKey: "y", press: 80, wait: 500, tip: "13. 等待詳細資訊紅底R➟按 Y" }, ; 9s逾時：按 ⮕ 再按 ⬅ 重試偵測
        { detectRedR: 9, timeout: 9000, retryYStep14: true, actionKey: "Enter", press: 80, wait: 500, estimatedWait: 2500, tip: "14. 等待勁敵列表紅底R➟按 ⏎" }, ; 9s逾時：按 Y 重試
        { detectRedR: 10, timeout: 9000, estimatedWait: 2500, retryEscStep15: true, actionKey: "Enter", press: 80, wait: 500, tip: "15. 等待詳細資訊紅底R➟按 ⏎" }, ; 9s逾時：按 Esc 返回第 14 步重試
        { key: "y", press: 80, wait: 500, tip: "16. 我的最愛 按 Y" },
        { detectColor: 12, timeout: 9000, estimatedWait: 2500, retryStep16: true, tip: "16.5. 偵測篩選綠色區域" }, ; 9s逾時：按 Y 重試偵測
        { key: "Enter", press: 80, wait: 500, tip: "17. 按 ⏎" },
        { key: "Esc", press: 80, wait: 500, tip: "18. 按 駕駛車 Esc" },
        { key: "Enter", press: 80, wait: 500, tip: "19. 按 ⏎" },
        { detectRedR: 11, actionKey: "Enter", press: 80, wait: 500, preDelay: 1000, estimatedWait: 4000, tip: "20. 等待賽道載入➟按 ⏎" },
        { key: "w", dynamicWaitVar: "RivalThrottleSec", wait: 500, countdown: true, tip: "21. 按住 W 設定秒數" },
        { key: "Esc", press: 80, wait: 1000, tip: "22. 按 退出賽事 Esc" },
        { key: "Right", press: 80, wait: 500, tip: "23. 按 完成勁敵 ⮕" },
        { key: "Enter", press: 80, wait: 500, tip: "24. 按 ⏎" },
        { key: "Enter", press: 80, wait: 500, tip: "25. 按 ⏎" },
        { key: "Enter", press: 80, wait: 500, tip: "26. 按 ⏎" },
        { sleep: 10000, countdown: true, tip: "等待 10 秒過場" },
        { detectColor: 6, press: 80, wait: 500, estimatedWait: 5000, tip: "27. 等待儀表板出現" }
    ]

    global staticActionStartMs := [], staticActionDurMs := []

    CalculateTotalMs() {
        global staticActionStartMs, staticActionDurMs
        staticActionStartMs := []
        staticActionDurMs := []
        local totalMs := 0
        for action in staticActions {
            staticActionStartMs.Push(totalMs)
            actMs := 0
            if (action.HasOwnProp("sleep")) {
                actMs := action.sleep
            } else if (action.HasOwnProp("sleepVar")) {
                actMs := %action.sleepVar% * 1000
            } else if (action.HasOwnProp("sleepRange")) {
                actMs := ((action.sleepRange[1] + action.sleepRange[2]) / 2) * 1000
            } else if (action.HasOwnProp("dynamicWaitVar")) {
                actMs := (%action.dynamicWaitVar% * 1000) + (action.HasOwnProp("wait") ? action.wait : 0)
            } else if (action.HasOwnProp("detectColor") || action.HasOwnProp("detectRedR")) {
                pressTime := action.HasOwnProp("press") ? action.press : 0
                waitTime := action.HasOwnProp("wait") ? action.wait : 0
                preDelay := action.HasOwnProp("preDelay") ? action.preDelay : 0
                estWait := action.HasOwnProp("estimatedWait") ? action.estimatedWait : 3000
                actMs := pressTime + waitTime + preDelay + estWait
            } else {
                pressTime := action.HasOwnProp("press") ? action.press : 0
                waitTime := action.HasOwnProp("wait") ? action.wait : 0
                repeat := action.HasOwnProp("repeat") ? action.repeat : 1
                actMs := (pressTime + waitTime) * repeat
            }
            staticActionDurMs.Push(actMs)
            totalMs += actMs
        }
        return totalMs
    }

    SleepAndCheck(ms) {
        global isRivalRunning, GameTitle, MyGui
        loop Ceil(ms / 100) {
            if (!isRivalRunning || (!WinActive(GameTitle) && !WinActive("ahk_id " MyGui.Hwnd))) {
                return false
            }
            Sleep(100)
        }
        return true
    }

    CountdownSleep(totalMs, prefix) {
        global isRivalRunning, GameTitle, MyGui
        startTime := A_TickCount
        while (isRivalRunning && (A_TickCount - startTime < totalMs)) {
            if (!WinActive(GameTitle) && !WinActive("ahk_id " MyGui.Hwnd)) {
                return false
            }
            elapsedMs := A_TickCount - startTime
            remainingMs := totalMs - elapsedMs
            remainingSec := Ceil(remainingMs / 1000)
            if (remainingSec < 0) {
                remainingSec := 0
            }
            timeDisplay := FormatTimeDuration(remainingSec)
            ShowTip(prefix "(倒數" timeDisplay ")")
            Sleep(100)
        }
        return isRivalRunning
    }

    ; 初始化預計結束時間
    singleLoopSec := Ceil(CalculateTotalMs() / 1000)
    actualLimit := (RivalLoopLimit == 0) ? 1 : RivalLoopLimit
    totalMin := Ceil((actualLimit * singleLoopSec) / 60)
    currentTotalMin := A_Hour * 60 + A_Min
    endTotalMin := Mod(currentTotalMin + totalMin, 1440)
    RivalEndHour := Floor(endTotalMin / 60)
    RivalEndMin := Mod(endTotalMin, 60)

    recalcFn := (limit, throttleSec, loadSec, endHour := 0, endMin := 0) => (
        dynamicTotalMs := CalculateTotalMs(),
        actualLim := (limit == 0) ? 1 : limit,
        FormatTimeDuration(Ceil((actualLim * dynamicTotalMs) / 1000))
    )
    timeStr := recalcFn(RivalLoopLimit, RivalThrottleSec, RivalLoadSec, RivalEndHour, RivalEndMin)
 
    extraParams := [
        { varRef: &RivalThrottleSec, name: "油門時間(分:秒)", range: "10-1800" },
        { varRef: &RivalLoadSec, name: "等待載入(秒)", range: "1-30" },
        { varRef: &RivalEndHour, name: "結束時間(時)", range: "0-23" },
        { varRef: &RivalEndMin, name: "結束時間(分)", range: "0-59" }
    ]

    isConfirming := true
    confirmed := ShowConfirmDialog("勁敵刷錢 🎖", timeStr, &RivalLoopLimit, recalcFn, extraParams, "RivalLoopLimit", CalculateTotalMs)
    isConfirming := false

    if (!confirmed) {
        StopGasAndClean()
        return
    }

    RivalTotalMs := CalculateTotalMs()
    actualLimitVal := (RivalLoopLimit == 0) ? 1 : RivalLoopLimit
    sequenceTotalSec := Ceil((actualLimitVal * RivalTotalMs) / 1000)

    if WinExist(GameTitle) {
        WinActivate(GameTitle)
        if !WinWaitActive(GameTitle, , 3) {
            StopGasAndClean()
            return
        }
    }

    global HasPreparationPhase
    HasPreparationPhase := false
    globalTotalMs := RivalLoopLimit * RivalTotalMs
    globalSegmentEnds := []
    Loop RivalLoopLimit {
        globalSegmentEnds.Push(A_Index * RivalTotalMs)
    }

    global currentLoopStartTime, currentLoopDuration
    DrawDividers()
    sequenceStartTime := A_TickCount
    UpdateUiRunningState("rival")
    SetTimer(UpdateRivalLoopProgress, 100)

    currentRivalLoopItem := 0
    Loop {
        if (!isRivalRunning || (RivalLoopLimit > 0 && A_Index > RivalLoopLimit) || StopAfterCurrentLoop) {
            break
        }
        currentRivalLoopItem := A_Index
        if (RivalLoopLimit == 0 || A_Index < RivalLoopLimit) {
            if (!CheckAndWait5AMReboot(Ceil(RivalTotalMs / 1000), &isRivalRunning)) {
                break
            }
        }
        rivalLoopStartTime := A_TickCount
        currentLoopStartTime := A_TickCount
        currentLoopDuration := RivalTotalMs

        if (!WinActive(GameTitle) && !WinActive("ahk_id " MyGui.Hwnd)) {
            StopGasAndClean()
            break
        }

        totalActionSteps := staticActions.Length
        loopBreak := false
        actIdx := 1
        while (actIdx <= staticActions.Length && !loopBreak && isRivalRunning) {
            action := staticActions[actIdx]
            currentActIdx := actIdx
            currentStepStartTime := A_TickCount
            currentStepTotalMs := 0
            if (action.HasOwnProp("sleep")) {
                currentStepTotalMs := action.sleep
            } else if (action.HasOwnProp("sleepVar")) {
                currentStepTotalMs := %action.sleepVar% * 1000
            } else if (action.HasOwnProp("dynamicWaitVar")) {
                currentStepTotalMs := %action.dynamicWaitVar% * 1000
            } else if (action.HasOwnProp("estimatedWait")) {
                currentStepTotalMs := action.estimatedWait
            }
            if (action.HasOwnProp("sleep")) {
                if (action.HasOwnProp("countdown")) {
                    if (!CountdownSleep(action.sleep, action.tip)) {
                        loopBreak := true
                        break
                    }
                } else {
                    ShowTip(action.tip)
                    if (!SleepAndCheck(action.sleep)) {
                        loopBreak := true
                        break
                    }
                }
            } else if (action.HasOwnProp("sleepVar")) {
                sleepMs := %action.sleepVar% * 1000
                if (action.HasOwnProp("countdown")) {
                    if (!CountdownSleep(sleepMs, action.tip)) {
                        loopBreak := true
                        break
                    }
                } else {
                    ShowTip(action.tip)
                    if (!SleepAndCheck(sleepMs)) {
                        loopBreak := true
                        break
                    }
                }
            } else if (action.HasOwnProp("sleepRange")) {
                minVal := action.sleepRange[1]
                maxVal := action.sleepRange[2]
                randomWaitSec := Random(minVal, maxVal)
                tipText := Format(action.tip, randomWaitSec)
                if (!CountdownSleep(randomWaitSec * 1000, tipText)) {
                    loopBreak := true
                    break
                }
            } else if (action.HasOwnProp("detectColor") || action.HasOwnProp("detectRedR")) {
                if (action.HasOwnProp("key")) {
                    ShowTip(action.tip)
                    if (!SendKey(action.key, action.press, action.wait, &isRivalRunning)) {
                        loopBreak := true
                        break
                    }
                }


                mode := action.HasOwnProp("detectColor") ? action.detectColor : action.detectRedR
                startTime := A_TickCount
                foundColor := false
                timeoutMs := action.HasOwnProp("timeout") ? action.timeout : 0

                ; 建立並顯示該 mode 的青色細虛線偵測區域外框
                GetDetectBoxCoords(mode, &bx1, &by1, &bx2, &by2)
                bw := bx2 - bx1, bh := by2 - by1
                detectBoxGui := CreateDashedBoxGui(bx1, by1, bw, bh, "0x00FFFF", 2, 12, 6)

                consecutiveCount := 0
                requiredCount := (mode == 6) ? 4 : 2
                while (isRivalRunning || isNewSequenceRunning) {
                    if (!WinActive(GameTitle) && !WinActive("ahk_id " MyGui.Hwnd)) {
                        break
                    }
                    if (timeoutMs > 0 && (A_TickCount - startTime > timeoutMs)) {
                        break
                    }
                    if DetectColorByMode(mode, false) {
                        consecutiveCount++
                        if (consecutiveCount >= requiredCount) {
                            foundColor := true
                            detectCost := A_TickCount - startTime
                            currentLoopStartTime += detectCost
                            sequenceStartTime += detectCost
                            ShowTip(action.tip)
                            break
                        }
                    } else {
                        consecutiveCount := 0
                    }
                    elapsedSec := Round((A_TickCount - startTime) / 1000, 1)
                    ShowTip(action.tip " (" elapsedSec "s)")
                    Sleep(100)
                }

                try {
                    detectBoxGui.Destroy()
                }

                if (!foundColor || (!isRivalRunning && !isNewSequenceRunning)) {
                    if (action.HasOwnProp("retryStep") && action.retryStep && isRivalRunning) {
                        ShowTip("1. 10秒未偵測到桃色選單：按 Esc 重試偵測...")
                        SendKey("Esc", 80, 500, &isRivalRunning)
                        continue
                    }
                    if (action.HasOwnProp("retryFromStep1") && action.retryFromStep1 && isRivalRunning) {
                        ShowTip("4.5. 未偵測到桃色區塊：按 Esc 返回並從第 1 步重試...")
                        SendKey("Esc", 250, 1000, &isRivalRunning)
                        actIdx := 1
                        continue
                    }
                    if (action.HasOwnProp("retryStep12") && action.retryStep12 && isRivalRunning) {
                        ShowTip("12.5. 9秒未偵測到性能R：按 ⬅ 重試偵測...")
                        SendKey("Left", 80, 500, &isRivalRunning)
                        continue
                    }
                    if (action.HasOwnProp("retryRightLeft") && action.retryRightLeft && isRivalRunning) {
                        ShowTip("13. 9秒未偵測到詳細資訊紅底R：按 ⮕ 再按 ⬅ 重試偵測...")
                        SendKey("Right", 80, 500, &isRivalRunning)
                        SendKey("Left", 80, 500, &isRivalRunning)
                        continue
                    }
                    if (action.HasOwnProp("retryYStep14") && action.retryYStep14 && isRivalRunning) {
                        ShowTip("14. 9秒未偵測到勁敵列表紅底R：按 Y 重試偵測...")
                        SendKey("y", 80, 500, &isRivalRunning)
                        continue
                    }
                    if (action.HasOwnProp("retryEscStep15") && action.retryEscStep15 && isRivalRunning) {
                        ShowTip("15. 9秒未偵測到詳細資訊紅底R：按 Esc 返回第 14 步重試...")
                        SendKey("Esc", 80, 500, &isRivalRunning)
                        actIdx := 14
                        continue
                    }
                    if (action.HasOwnProp("retryStep16") && action.retryStep16 && isRivalRunning) {
                        ShowTip("16.5. 9秒未偵測到篩選綠色區域：按 Y 重試偵測...")
                        SendKey("y", 80, 500, &isRivalRunning)
                        continue
                    }
                    loopBreak := true
                    break
                }
                if (action.HasOwnProp("preDelay") && action.preDelay > 0) {
                    if (!CountdownSleep(action.preDelay, "偵測成功")) {
                        loopBreak := true
                        break
                    }
                }
                if (action.HasOwnProp("actionKey")) {
                    if (!SendKey(action.actionKey, action.press, action.wait, &isRivalRunning)) {
                        loopBreak := true
                        break
                    }
                }
            } else if (action.HasOwnProp("dynamicWaitVar")) {
                holdMs := %action.dynamicWaitVar% * 1000
                SendInput("{" action.key " Down}")
 
                wSuccess := false
                if (action.key == "w") {
                    wTip := "按住 W " . FormatSecToMinSec(%action.dynamicWaitVar%)
                    wSuccess := HoldWWithPeriodicKeys(holdMs, wTip, &isRivalRunning)
                } else if (action.HasOwnProp("countdown")) {
                    wSuccess := CountdownSleep(holdMs, action.tip)
                } else {
                    ShowTip(action.tip)
                    wSuccess := SleepAndCheck(holdMs)
                }
 
                ShowTip("釋放 " action.key " 鍵")
                if (action.key == "w") {
                    ForceReleaseW_Hardware()
                } else {
                    SendInput("{" action.key " Up}")
                }
 
                if (!wSuccess) {
                    loopBreak := true
                    break
                }
                if (!SleepAndCheck(action.wait)) {
                    loopBreak := true
                    break
                }
            } else {
                repeat := action.HasOwnProp("repeat") ? action.repeat : 1
                if (repeat > 1) {
                    repeatSuccess := true
                    Loop repeat {
                        tipText := Format(action.tip, A_Index)
                        ShowTip(tipText)
                        if (!SendKey(action.key, action.press, action.wait, &isRivalRunning)) {
                            repeatSuccess := false
                            break
                        }
                    }
                    if (!repeatSuccess) {
                        loopBreak := true
                        break
                    }
                } else {
                    ShowTip(action.tip)
                    if (!SendKey(action.key, action.press, action.wait, &isRivalRunning)) {
                        loopBreak := true
                        break
                    }
                }
            }
            actIdx++
        }
        if (loopBreak)
            break
    }

    ShowTip("")
    StopGasAndClean()
}



; --- 時間格式化輔助函數（支援 hh:mm:ss、mm:ss 與 ss秒） ---
FormatTimeDuration(seconds) {
    if (seconds >= 3600) {
        hours := Floor(seconds / 3600)
        mins := Floor(Mod(seconds, 3600) / 60)
        secs := Mod(seconds, 60)
        return Format("{:02d}", hours) ":" Format("{:02d}", mins) ":" Format("{:02d}", secs)
    } else if (seconds >= 60) {
        mins := Floor(seconds / 60)
        secs := Mod(seconds, 60)
        return mins ":" Format("{:02d}", secs)
    } else {
        return seconds "秒"
    }
}

ForceReleaseW_Hardware() {
    Send("{w Up}")
    SendInput("{w Up}")
    DllCall("keybd_event", "int", 0x57, "int", 0, "int", 2, "ptr", 0)
    Sleep(20)
}

SendWPeriodicKey(&nextWSubKey) {
    if (nextWSubKey == "Up") {
        Send("{Up down}")
        Sleep(80)
        Send("{Up up}")
        nextWSubKey := "h"
    } else {
        Send("{h down}")
        Sleep(80)
        Send("{h up}")
        nextWSubKey := "Up"
    }
    SendInput("{w Down}")
}

FormatSecToMinSec(totalSec) {
    sec := Integer(totalSec)
    if (sec <= 0)
        return "0秒"
    m := Floor(sec / 60)
    s := Mod(sec, 60)
    if (m > 0 && s > 0)
        return m "分" s "秒"
    else if (m > 0)
        return m "分"
    else
        return s "秒"
}

HoldWWithPeriodicKeys(totalMs, prefix, &isRunning) {
    global GameTitle, MyGui, isPauseFocusCheck
    startTime := A_TickCount
    lastWSubKeyTime := startTime
    nextWSubKey := "Up"

    while (isRunning && (A_TickCount - startTime < totalMs)) {
        if (!isPauseFocusCheck && (!WinActive(GameTitle) && !WinActive("ahk_id " MyGui.Hwnd))) {
            return false
        }
        
        if (A_TickCount - lastWSubKeyTime >= 5000) {
            SendWPeriodicKey(&nextWSubKey)
            lastWSubKeyTime := A_TickCount
        }

        elapsedMs := A_TickCount - startTime
        remainingMs := totalMs - elapsedMs
        remainingSec := Ceil(remainingMs / 1000)
        if (remainingSec < 0) {
            remainingSec := 0
        }
        timeDisplay := FormatSecToMinSec(remainingSec)
        ShowTip(prefix " (倒數" timeDisplay ")")
        Sleep(100)
    }
    return isRunning
}

WM_LBUTTONDOWN(wParam, lParam, msg, hwnd) {
    global MyGui, GuiBtns, isGasOn, isSequenceRunning, isEnterSpamRunning, isNewSequenceRunning, isBuyCarRunning, CurrentConfirmUpdateFn, isRivalRunning
    global isEditBoxMode, EditBoxWindowGui

    if (isEditBoxMode && EditBoxWindowGui != "") {
        guiHwnd := EditBoxWindowGui.Hwnd
        try {
            rootHwnd := DllCall("user32\GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr")
        } catch {
            rootHwnd := hwnd
        }
        if (hwnd == guiHwnd || rootHwnd == guiHwnd) {
            PostMessage(0xA1, 2, 0, guiHwnd)
            return 0
        }
    }
 
    try {
        cls := WinGetClass(hwnd)
    } catch {
        cls := ""
    }
    if (cls == "msctls_trackbar32") {
        ctrlObj := GuiCtrlFromHwnd(hwnd)
        if (ctrlObj) {
            ctrlObj.GetPos(&cX, &cY, &cW, &cH)
            guiHwnd := ctrlObj.Gui.Hwnd
            WinGetPos(&winX, &winY, , , "ahk_id " guiHwnd)
            CoordMode("Mouse", "Screen")
            MouseGetPos(&mX, &mY)
            relativeX := mX - (winX + cX)
            currVal := ctrlObj.Value

            ; 取得控制點的精確像素範圍 (TBM_GETTHUMBRECT = 0x0419)
            thumbRect := Buffer(16, 0)
            SendMessage(0x0419, 0, thumbRect, hwnd)
            tLeft := NumGet(thumbRect, 0, "Int")
            tRight := NumGet(thumbRect, 8, "Int")

            ; 如果點擊在控制點上，交由系統預設處理（允許拖曳）
            if (relativeX >= tLeft && relativeX <= tRight) {
                return
            }

            ; 取得軌道精確像素範圍 (TBM_GETCHANNELRECT = 0x041A)
            chanRect := Buffer(16, 0)
            SendMessage(0x041A, 0, chanRect, hwnd)
            cLeft := NumGet(chanRect, 0, "Int")
            cRight := NumGet(chanRect, 8, "Int")
            channelWidth := cRight - cLeft

            if (channelWidth > 0) {
                minVal := SendMessage(0x0401, 0, 0, hwnd)
                maxVal := SendMessage(0x0402, 0, 0, hwnd)
                if (maxVal > minVal) {
                    if (relativeX < tLeft) {
                        ; 點擊在控制點左側➟減少數值
                        distPx := tLeft - relativeX
                        diffVal := (distPx / channelWidth) * (maxVal - minVal)
                        jump := Max(1, Round(diffVal * 0.3))
                        newVal := Max(minVal, currVal - jump)
                    } else {
                        ; 點擊在控制點右側➟增加數值
                        distPx := relativeX - tRight
                        diffVal := (distPx / channelWidth) * (maxVal - minVal)
                        jump := Max(1, Round(diffVal * 0.3))
                        newVal := Min(maxVal, currVal + jump)
                    }
                    ctrlObj.Value := newVal
                    if (CurrentConfirmUpdateFn) {
                        CurrentConfirmUpdateFn(ctrlObj)
                    }

                    ; 只要滑鼠左鍵沒放開，就能繼續拖移控制點
                    startX := mX
                    isDragging := false
                    while GetKeyState("LButton", "P") {
                        MouseGetPos(&curX, &curY)
                        if (!isDragging && abs(curX - startX) > 5) {
                            isDragging := true
                        }
                        if (isDragging) {
                            WinGetPos(&winX, &winY, , , "ahk_id " guiHwnd)
                            relativeX := curX - (winX + cX)
                            pct := (relativeX - cLeft) / (cRight - cLeft)
                            pct := Min(1.0, Max(0.0, pct))
                            dragVal := Round(minVal + pct * (maxVal - minVal))
                            if (ctrlObj.Value != dragVal) {
                                ctrlObj.Value := dragVal
                                if (CurrentConfirmUpdateFn) {
                                    CurrentConfirmUpdateFn(ctrlObj)
                                }
                            }
                        }
                        Sleep(15)
                    }
                    return 0
                }
            }
        }
    }

    for btn in GuiBtns {
        if (hwnd == btn.Hwnd) {
            return
        }
    }
}

GetAnyJoyState(btnNum) {
    if (!EnableGamepad) {
        return false
    }
    xiState := Buffer(16, 0)
    Loop 4 {
        userIndex := A_Index - 1
        status := -1
        try {
            status := DllCall("XInput1_4\XInputGetState", "UInt", userIndex, "Ptr", xiState)
        } catch {
            try {
                status := DllCall("XInput1_3\XInputGetState", "UInt", userIndex, "Ptr", xiState)
            } catch {
                status := -1
            }
        }
        if (status == 0) { 
            wButtons := NumGet(xiState, 4, "UShort")
            mask := 0
            switch btnNum {
                case 1:  mask := 0x1000 ; A
                case 2:  mask := 0x2000 ; B
                case 3:  mask := 0x4000 ; X
                case 4:  mask := 0x8000 ; Y
                case 5:  mask := 0x0100 ; LB
                case 9:  mask := 0x0040 ; L3
                case 10: mask := 0x0080 ; R3
            }
            if (mask && (wButtons & mask)) {
                return true
            }
        }
    }
    if (GetKeyState("Joy" btnNum)) {
        return true
    }
    Loop 8 {
        if (GetKeyState(A_Index "Joy" btnNum)) {
            return true
        }
    }
    return false
}
CheckAndWait5AMReboot(loopDurationSec, &isRunningVar) {
    global Enable5AMWait, RebootHour, RebootWaitMin, GameTitle, MyGui, IsWaitingReboot, ProgressBar, LoopProgressBar, currentNewLoopItem, NewSequenceLoopLimit, currentRivalLoopItem, RivalLoopLimit, isNewSequenceRunning, isRivalRunning
    if (!Enable5AMWait) {
        return true
    }

    hourStr := Format("{:02d}", RebootHour)
    rebootStartStr := FormatTime(A_Now, "yyyyMMdd") hourStr "0000"
    rebootEndStr := DateAdd(rebootStartStr, RebootWaitMin, "Minutes")

    secondsToRebootEnd := DateDiff(rebootEndStr, A_Now, "Seconds")
    if (secondsToRebootEnd >= 0) {
        secondsToRebootStart := DateDiff(rebootStartStr, A_Now, "Seconds")
        if (secondsToRebootStart <= 0 || loopDurationSec >= secondsToRebootStart) {
            waitSec := secondsToRebootEnd
            if (waitSec > 0) {
                IsWaitingReboot := true
                startTime := A_TickCount
                totalMs := waitSec * 1000
                while (isRunningVar && (A_TickCount - startTime < totalMs)) {
                    if (!WinActive(GameTitle) && !WinActive("ahk_id " MyGui.Hwnd)) {
                        isRunningVar := false
                        IsWaitingReboot := false
                        LoopProgressBar.Value := 0
                        return false
                    }
                    elapsedMs := A_TickCount - startTime
                    remainingMs := totalMs - elapsedMs
                    remainingSec := Ceil(remainingMs / 1000)
                    if (remainingSec < 0) {
                        remainingSec := 0
                    }
                    timeDisplay := FormatTimeDuration(remainingSec)
                    ShowTip("等待網路重啟 (" hourStr ":" Format("{:02d}", RebootWaitMin) ")(倒數" timeDisplay ")")

                    ; 更新藍色 LoopProgressBar 進度
                    percent := Integer(Min(10000, Max(0, (elapsedMs / totalMs) * 10000)))
                    LoopProgressBar.Value := percent

                    ; 根據當前行程更新黃色 ProgressBar 總進度
                    if (isNewSequenceRunning && NewSequenceLoopLimit > 0) {
                        ProgressBar.Value := Integer(((currentNewLoopItem - 1) / NewSequenceLoopLimit) * 10000)
                    } else if (isRivalRunning && RivalLoopLimit > 0) {
                        ProgressBar.Value := Integer(((currentRivalLoopItem - 1) / RivalLoopLimit) * 10000)
                    }

                    Sleep(100)
                }
                IsWaitingReboot := false
                LoopProgressBar.Value := 0
                if (!isRunningVar) {
                    return false
                }
            }
            ; 按兩次 Enter 確認斷線訊息
            if (!SendKey("Enter", 250, 1000, &isRunningVar)) {
                return false
            }
            if (!SendKey("Enter", 250, 1000, &isRunningVar)) {
                return false
            }
        }
    }
    return true
}
SendKey(keyName, pressDuration, waitDuration, &isRunning) {
    ; 如果已經停止執行，就回傳 false 讓迴圈中斷
    if (!isRunning) {
        return false
    }
 
    ; 按下按鍵
    Send("{" keyName " down}")
    Sleep(pressDuration)
 
    ; 鬆開按鍵
    Send("{" keyName " up}")
    if (waitDuration > 0) {
        Sleep(waitDuration)
    }
 
    return isRunning
}
SendTextAction(strText, waitDuration, &isRunning) {
    if (!isRunning) {
        return false
    }

    A_Clipboard := strText
    Sleep(100)
    Send("^v")
    if (waitDuration > 0) {
        Sleep(waitDuration)
    }

    return isRunning
}

CreateDashedBoxGui(x1, y1, w, h, color := "0x00FFFF", thickness := 2, dashLen := 12, gapLen := 6) {
    global ShowDashedBox
    if (!ShowDashedBox) {
        return ""
    }

    boxGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 +E0x08000000")
    try {
        if WinExist(GameTitle)
            boxGui.Opt("+Owner" WinGetID(GameTitle))
    }
    boxGui.BackColor := "0x000001"
    WinSetTransColor("0x000001", boxGui.Hwnd)

    ; 上邊界
    x := 0
    while (x < w) {
        segW := Min(dashLen, w - x)
        boxGui.AddText("X" x " Y0 W" segW " H" thickness " Background" color)
        x += dashLen + gapLen
    }

    ; 下邊界
    x := 0
    while (x < w) {
        segW := Min(dashLen, w - x)
        boxGui.AddText("X" x " Y" (h - thickness) " W" segW " H" thickness " Background" color)
        x += dashLen + gapLen
    }

    ; 左邊界
    y := 0
    while (y < h) {
        segH := Min(dashLen, h - y)
        boxGui.AddText("X0 Y" y " W" thickness " H" segH " Background" color)
        y += dashLen + gapLen
    }

    ; 右邊界
    y := 0
    while (y < h) {
        segH := Min(dashLen, h - y)
        boxGui.AddText("X" (w - thickness) " Y" y " W" thickness " H" segH " Background" color)
        y += dashLen + gapLen
    }

    boxGui.Show("X" x1 " Y" y1 " W" w " H" h " NoActivate")
    return boxGui
}

DetectYellowCard(timeoutMs := 15000) {
    global GameTitle, MyGui, isNewSequenceRunning, isPauseFocusCheck
    startTime := A_TickCount

    GetDetectBoxCoords(1, &x1, &y1, &x2, &y2)
    w := x2 - x1
    h := y2 - y1

    ; 建立細虛線外框 GUI 覆蓋顯示偵測範圍 (亮青色高對比細虛線外框，中央完全透明)
    boxGui := CreateDashedBoxGui(x1, y1, w, h, "0x00FFFF", 2, 12, 6)

    searchX1 := x1
    searchY1 := y1
    searchX2 := x2
    searchY2 := y2

    targetColor1 := 0xFFD700
    targetColor2 := 0xFFDF00
    variation := 40

    found := false
    lastPressTime := A_TickCount

    while (isNewSequenceRunning) {
        if (!isPauseFocusCheck && !WinActive(GameTitle) && !WinActive("ahk_id " MyGui.Hwnd)) {
            break
        }

        CoordMode("Pixel", "Screen")
        if PixelSearch(&fx, &fy, searchX1, searchY1, searchX2, searchY2, targetColor1, variation) || PixelSearch(&fx, &fy, searchX1, searchY1, searchX2, searchY2, targetColor2, variation) {
            found := true
            Sleep(500) ; 偵測到黃色卡片後緩衝等待 500ms，確保 UI 選單動畫結束並獲得按鍵焦點
            try {
                WinActivate(GameTitle)
            }
            break
        }

        ; 若等待超過 10 秒仍未偵測到黃色卡片，按 Esc 退出並返回第 6 步重試
        if (A_TickCount - lastPressTime >= 10000) {
            ShowTip("12.5. 等待超過 10 秒未偵測到黃卡：對焦遊戲視窗並按 Esc 退出...")
            try {
                WinActivate(GameTitle)
            }
            SendKey("Esc", 250, 1000, &isNewSequenceRunning)
            found := false
            break
        }

        elapsedSec := Round((A_TickCount - startTime) / 1000, 1)
        ShowTip("12.5. 等待黃色卡片載入中... (" elapsedSec "s)")
        Sleep(150)
    }

    try {
        boxGui.Destroy()
    }

    return (found && isNewSequenceRunning)
}

DetectProgressBarEndNotBlack(timeoutMs := 30000) {
    global GameTitle, MyGui, isNewSequenceRunning, isPauseFocusCheck, GuiX, GuiY, GuiH, ProgressBarWidth
    startTime := A_TickCount

    GetDetectBoxCoords(3, &x1, &y1, &x2, &y2)
    w := x2 - x1
    h := y2 - y1

    boxGui := CreateDashedBoxGui(x1, y1, w, h, "0x00FFFF", 2, 12, 6)

    searchX1 := x1
    searchY1 := y1
    searchX2 := x2
    searchY2 := y2

    ; 黑色目標顏色 (RGB 0x000000, 容差 50)
    blackColor := 0x000000
    variation := 50

    isLoaded := false
    while (isNewSequenceRunning && (timeoutMs == 0 || A_TickCount - startTime < timeoutMs)) {
        if (!isPauseFocusCheck && !WinActive(GameTitle) && !WinActive("ahk_id " MyGui.Hwnd)) {
            break
        }

        CoordMode("Pixel", "Screen")
        ; 若 PixelSearch 在區域內找不到黑色，代表該區域已非黑色（遊戲畫面/UI載入完成）
        if !PixelSearch(&fx, &fy, searchX1, searchY1, searchX2, searchY2, blackColor, variation) {
            isLoaded := true
            break
        }

        elapsedSec := Round((A_TickCount - startTime) / 1000, 1)
        ShowTip("等待賽道就緒... (" elapsedSec "s)")
        Sleep(100)
    }

    try {
        boxGui.Destroy()
    }

    return (isLoaded && isNewSequenceRunning)
}

DetectBlackBelowProgress(timeoutMs := 0) {
    global GameTitle, MyGui, isNewSequenceRunning, isPauseFocusCheck
    startTime := A_TickCount

    try {
        WinGetPos(&wX, &wY, &wW, &wH, GameTitle)
    } catch {
        wX := 0, wY := 0, wW := A_ScreenWidth, wH := A_ScreenHeight
    }

    ; 畫面正中央區域 (35% ~ 65% 寬度, 35% ~ 65% 高度)
    x1 := wX + Floor(wW * 0.35)
    y1 := wY + Floor(wH * 0.35)
    x2 := wX + Floor(wW * 0.65)
    y2 := wY + Floor(wH * 0.65)

    w := x2 - x1
    h := y2 - y1

    ; 建立細虛線外框 GUI 覆蓋顯示偵測範圍 (亮青色高對比細虛線外框，中央完全透明)
    boxGui := CreateDashedBoxGui(x1, y1, w, h, "0x00FFFF", 2, 12, 6)

    searchX1 := x1
    searchY1 := y1
    searchX2 := x2
    searchY2 := y2

    ; 黑色 / 暗色目標顏色 (RGB 0x000000, 容差 55，符合黑色暗影背景)
    targetColor := 0x000000
    variation := 55

    found := false
    while (isNewSequenceRunning) {
        if (!isPauseFocusCheck && !WinActive(GameTitle) && !WinActive("ahk_id " MyGui.Hwnd)) {
            break
        }

        CoordMode("Pixel", "Screen")
        if PixelSearch(&fx, &fy, searchX1, searchY1, searchX2, searchY2, targetColor, variation) {
            found := true
            break
        }

        elapsedSec := Round((A_TickCount - startTime) / 1000, 1)
        ShowTip("9.5. 等待輸入介面展開... (" elapsedSec "s)")
        Sleep(150)
    }

    try {
        boxGui.Destroy()
    }

    return (found && isNewSequenceRunning)
}



DetectGreenRatingCard(showBox := false) {
    global GameTitle, MyGui, isPauseFocusCheck

    GetDetectBoxCoords(5, &x1, &y1, &x2, &y2)
    w := x2 - x1
    h := y2 - y1

    boxGui := ""
    if (showBox) {
        boxGui := CreateDashedBoxGui(x1, y1, w, h, "0x00FFFF", 2, 12, 6)
    }

    searchX1 := x1
    searchY1 := y1
    searchX2 := x2
    searchY2 := y2

    ; 精確亮綠色 / 黃綠色標頭目標顏色 (RGB 0xCCFF00, 0xD4FF00，容差 45)
    targetColor1 := 0xCCFF00
    targetColor2 := 0xD4FF00
    variation := 45

    CoordMode("Pixel", "Screen")
    found := PixelSearch(&fx, &fy, searchX1, searchY1, searchX2, searchY2, targetColor1, variation) 
          || PixelSearch(&fx, &fy, searchX1, searchY1, searchX2, searchY2, targetColor2, variation)

    if (showBox && boxGui != "") {
        try {
            boxGui.Destroy()
        }
    }

    return found
}

GetTargetGameWindowPos(&wX, &wY, &wW, &wH) {
    try {
        if WinExist("ahk_exe ForzaHorizon6.exe") {
            WinGetPos(&wX, &wY, &wW, &wH, "ahk_exe ForzaHorizon6.exe")
            if (wW > 400 && wH > 300 && wX >= -10000 && wY >= -10000)
                return
        }
        if WinExist("ahk_exe notepad.exe") {
            WinGetPos(&wX, &wY, &wW, &wH, "ahk_exe notepad.exe")
            if (wW > 400 && wH > 300 && wX >= -10000 && wY >= -10000)
                return
        }
    }
    wX := 0, wY := 0, wW := A_ScreenWidth, wH := A_ScreenHeight
}

GetGameViewportClientRect(&vpX, &vpY, &vpW, &vpH) {
    GetTargetGameWindowPos(&wX, &wY, &wW, &wH)

    targetRatio := 16.0 / 9.0
    currentRatio := wW / wH

    if (currentRatio > targetRatio) {
        ; 視窗太寬 (左右有黑邊，例如 21:9 螢幕或遠端控制視窗)
        vpW := Floor(wH * targetRatio)
        vpH := wH
        vpX := wX + Floor((wW - vpW) / 2)
        vpY := wY
    } else if (currentRatio < targetRatio) {
        ; 視窗太高 (上下有黑邊)
        vpW := wW
        vpH := Floor(wW / targetRatio)
        vpX := wX
        vpY := wY + Floor((wH - vpH) / 2)
    } else {
        ; 無黑邊 (正好 16:9)
        vpX := wX, vpY := wY, vpW := wW, vpH := wH
    }
}

DetectColorByMode(mode := 1, showBox := false) {
    global GameTitle, MyGui, isPauseFocusCheck

    GetDetectBoxCoords(mode, &x1, &y1, &x2, &y2)

    w := x2 - x1, h := y2 - y1
    boxGui := ""
    if (showBox) {
        boxGui := CreateDashedBoxGui(x1, y1, w, h, "0x00FFFF", 2, 12, 6)
    }

    searchX1 := x1, searchY1 := y1, searchX2 := x2, searchY2 := y2

    found := false
    CoordMode("Pixel", "Screen")

    if (mode == 1) {
        ; 1. ⚔ 賺技能點：黃色賽事卡片 (0xFFD700, 0xFFDF00)
        found := PixelSearch(&fx, &fy, searchX1, searchY1, searchX2, searchY2, 0xFFD700, 40)
              || PixelSearch(&fx, &fy, searchX1, searchY1, searchX2, searchY2, 0xFFDF00, 40)
    } else if (mode == 2) {
        ; 2. ⚔ 賺技能點：黑色背景區域 (0x000000)
        found := PixelSearch(&fx, &fy, searchX1, searchY1, searchX2, searchY2, 0x000000, 55)
    } else if (mode == 3) {
        ; 3. ⚔ 賺技能點：進度條右下非黑
        found := !PixelSearch(&fx, &fy, searchX1, searchY1, searchX2, searchY2, 0x000000, 50)
    } else if (mode == 4) {
        ; 4. ⚔ 賺技能點：HUD 資訊框 (0x000000, 0xFFD700)
        found := PixelSearch(&fx, &fy, searchX1, searchY1, searchX2, searchY2, 0x000000, 55)
              || PixelSearch(&fx, &fy, searchX1, searchY1, searchX2, searchY2, 0xFFD700, 45)
    } else if (mode == 5) {
        ; 5. ⚔ 賺技能點：綠色評分標頭 (0xCCFF00, 0xD4FF00)
        found := PixelSearch(&fx, &fy, searchX1, searchY1, searchX2, searchY2, 0xCCFF00, 45)
              || PixelSearch(&fx, &fy, searchX1, searchY1, searchX2, searchY2, 0xD4FF00, 45)
    } else if (mode == 6) {
        ; 6. ⚔ 賺技能點：儀表板桃紅線條 (0xD0006F, 0xDF0078, 0xE6007A, 0xFF007F, 0xEE007C)
        found := PixelSearch(&fx, &fy, searchX1, searchY1, searchX2, searchY2, 0xD0006F, 40)
              || PixelSearch(&fx, &fy, searchX1, searchY1, searchX2, searchY2, 0xDF0078, 40)
              || PixelSearch(&fx, &fy, searchX1, searchY1, searchX2, searchY2, 0xE6007A, 40)
              || PixelSearch(&fx, &fy, searchX1, searchY1, searchX2, searchY2, 0xFF007F, 40)
              || PixelSearch(&fx, &fy, searchX1, searchY1, searchX2, searchY2, 0xEE007C, 40)
    } else if (mode == 7) {
        ; 7. 🎖 勁敵刷錢：收藏日誌桃卡 (0xFF007F, 0xE6007A, 0xFF1493, 0xEE007C, 0xD0006F)
        found := PixelSearch(&fx, &fy, searchX1, searchY1, searchX2, searchY2, 0xFF007F, 40)
              || PixelSearch(&fx, &fy, searchX1, searchY1, searchX2, searchY2, 0xE6007A, 40)
              || PixelSearch(&fx, &fy, searchX1, searchY1, searchX2, searchY2, 0xFF1493, 40)
              || PixelSearch(&fx, &fy, searchX1, searchY1, searchX2, searchY2, 0xEE007C, 40)
              || PixelSearch(&fx, &fy, searchX1, searchY1, searchX2, searchY2, 0xD0006F, 40)
    } else if (mode == 8 || mode == 9 || mode == 10 || mode == 11 || mode == 13) {
        ; 8/9/10/11/13. 🎖 勁敵刷錢桃色卡片 / 詳細資訊 / 左上角 R 標籤
        found := PixelSearch(&fx, &fy, searchX1, searchY1, searchX2, searchY2, 0xD0006F, 45)
              || PixelSearch(&fx, &fy, searchX1, searchY1, searchX2, searchY2, 0xDF0078, 45)
              || PixelSearch(&fx, &fy, searchX1, searchY1, searchX2, searchY2, 0xE6007A, 45)
              || PixelSearch(&fx, &fy, searchX1, searchY1, searchX2, searchY2, 0xFF007F, 45)
              || PixelSearch(&fx, &fy, searchX1, searchY1, searchX2, searchY2, 0xEE007C, 45)
              || PixelSearch(&fx, &fy, searchX1, searchY1, searchX2, searchY2, 0xFF1493, 45)
              || PixelSearch(&fx, &fy, searchX1, searchY1, searchX2, searchY2, 0xD80072, 45)
    } else if (mode == 12) {
        ; 12. 🎖 勁敵刷錢：篩選綠色標頭 (RGB 0xCCFF00, 0xBFFF00, 0xADFF2F, 容差 45)
        found := PixelSearch(&fx, &fy, searchX1, searchY1, searchX2, searchY2, 0xCCFF00, 45)
              || PixelSearch(&fx, &fy, searchX1, searchY1, searchX2, searchY2, 0xBFFF00, 45)
              || PixelSearch(&fx, &fy, searchX1, searchY1, searchX2, searchY2, 0xADFF2F, 45)
    }

    if (showBox && boxGui != "") {
        try {
            boxGui.Destroy()
        }
    }

    return found
}

DetectRedRInDetails(mode := 10, showBox := true) {
    return DetectColorByMode(mode, showBox)
}


DetectTopLeftThreeBlackBarsExist(showBox := true) {
    global GameTitle

    GetDetectBoxCoords(4, &x1, &y1, &x2, &y2)
    w := x2 - x1
    h := y2 - y1

    boxGui := ""
    if (showBox) {
        boxGui := CreateDashedBoxGui(x1, y1, w, h, "0x00FFFF", 2, 12, 6)
    }

    searchX1 := x1
    searchY1 := y1
    searchX2 := x2
    searchY2 := y2

    ; 搜尋該區域內是否有「黑色背景」(0x000000~0x353535) 或「亮黃色/亮黃綠色資訊標題」(0xFFD700, 0xCCFF00)
    targetBlack := 0x000000
    targetYellow := 0xFFD700
    variationBlack := 55
    variationYellow := 45

    CoordMode("Pixel", "Screen")
    hasHud := PixelSearch(&fx, &fy, searchX1, searchY1, searchX2, searchY2, targetBlack, variationBlack)
           || PixelSearch(&fx, &fy, searchX1, searchY1, searchX2, searchY2, targetYellow, variationYellow)

    if (showBox && boxGui != "") {
        try {
            boxGui.Destroy()
        }
    }

    return hasHud
}

; =================================================================
; [編輯偵測框與 ini 設定檔管理系統]
; =================================================================

LoadAllFromIni() {
    global LoadVehicleDelay, LongPressDelay, EnableGamepad, IsSimplifyDividers
    global AutoLoopEnabled, LoopCountLimit, SkillPath, SkillPoints, SkillBuyCarEnabled
    global NewSequenceLoopLimit, labcode, BuyCarLoopLimit, RivalLoopLimit, RivalThrottleSec
    global Enable5AMWait, RebootHour, RebootWaitMin, ShowDashedBox
    global BuyCarMfgUp, BuyCarMfgDown, BuyCarMfgLeft, BuyCarMfgRight
    global BuyCarSelUp, BuyCarSelDown, BuyCarSelLeft, BuyCarSelRight
    global ShowIcon_Esc, ShowIcon_NewSeq, ShowIcon_Seq, ShowIcon_Rival, ShowIcon_BuyCar, ShowIcon_Gas, ShowIcon_EnterSpam, ShowIcon_EditBox, ShowIcon_Exit

    iniFile := A_ScriptDir "\fh6.ini"
    if !FileExist(iniFile) {
        SaveAllToIni()
        return
    }

    ; [Settings]
    try LoadVehicleDelay := Integer(IniRead(iniFile, "Settings", "LoadVehicleDelay", String(LoadVehicleDelay)))
    try LongPressDelay := Float(IniRead(iniFile, "Settings", "LongPressDelay", String(LongPressDelay)))
    try EnableGamepad := Integer(IniRead(iniFile, "Settings", "EnableGamepad", String(EnableGamepad)))
    try IsSimplifyDividers := (IniRead(iniFile, "Settings", "IsSimplifyDividers", IsSimplifyDividers ? "true" : "false") = "true")
    try AutoLoopEnabled := (IniRead(iniFile, "Settings", "AutoLoopEnabled", AutoLoopEnabled ? "true" : "false") = "true")
    try LoopCountLimit := Integer(IniRead(iniFile, "Settings", "LoopCountLimit", String(LoopCountLimit)))
    try SkillPath := IniRead(iniFile, "Settings", "SkillPath", SkillPath)
    try SkillPoints := Integer(IniRead(iniFile, "Settings", "SkillPoints", String(SkillPoints)))
    try SkillBuyCarEnabled := (IniRead(iniFile, "Settings", "SkillBuyCarEnabled", SkillBuyCarEnabled ? "true" : "false") = "true")
    try NewSequenceLoopLimit := Integer(IniRead(iniFile, "Settings", "NewSequenceLoopLimit", String(NewSequenceLoopLimit)))
    try labcode := IniRead(iniFile, "Settings", "labcode", labcode)
    try BuyCarLoopLimit := Integer(IniRead(iniFile, "Settings", "BuyCarLoopLimit", String(BuyCarLoopLimit)))
    try RivalLoopLimit := Integer(IniRead(iniFile, "Settings", "RivalLoopLimit", String(RivalLoopLimit)))
    try RivalThrottleSec := Integer(IniRead(iniFile, "Settings", "RivalThrottleSec", String(RivalThrottleSec)))
    try Enable5AMWait := (IniRead(iniFile, "Settings", "Enable5AMWait", Enable5AMWait ? "true" : "false") = "true")
    try RebootHour := Integer(IniRead(iniFile, "Settings", "RebootHour", String(RebootHour)))
    try RebootWaitMin := Integer(IniRead(iniFile, "Settings", "RebootWaitMin", String(RebootWaitMin)))
    try ShowDashedBox := (IniRead(iniFile, "Settings", "ShowDashedBox", ShowDashedBox ? "true" : "false") = "true")

    ; [BuyCar]
    try BuyCarMfgUp := Integer(IniRead(iniFile, "BuyCar", "BuyCarMfgUp", String(BuyCarMfgUp)))
    try BuyCarMfgDown := Integer(IniRead(iniFile, "BuyCar", "BuyCarMfgDown", String(BuyCarMfgDown)))
    try BuyCarMfgLeft := Integer(IniRead(iniFile, "BuyCar", "BuyCarMfgLeft", String(BuyCarMfgLeft)))
    try BuyCarMfgRight := Integer(IniRead(iniFile, "BuyCar", "BuyCarMfgRight", String(BuyCarMfgRight)))
    try BuyCarSelUp := Integer(IniRead(iniFile, "BuyCar", "BuyCarSelUp", String(BuyCarSelUp)))
    try BuyCarSelDown := Integer(IniRead(iniFile, "BuyCar", "BuyCarSelDown", String(BuyCarSelDown)))
    try BuyCarSelLeft := Integer(IniRead(iniFile, "BuyCar", "BuyCarSelLeft", String(BuyCarSelLeft)))
    try BuyCarSelRight := Integer(IniRead(iniFile, "BuyCar", "BuyCarSelRight", String(BuyCarSelRight)))

    ; [Icons]
    try ShowIcon_Esc := (IniRead(iniFile, "Icons", "ShowIcon_Esc", ShowIcon_Esc ? "true" : "false") = "true")
    try ShowIcon_NewSeq := (IniRead(iniFile, "Icons", "ShowIcon_NewSeq", ShowIcon_NewSeq ? "true" : "false") = "true")
    try ShowIcon_Seq := (IniRead(iniFile, "Icons", "ShowIcon_Seq", ShowIcon_Seq ? "true" : "false") = "true")
    try ShowIcon_Rival := (IniRead(iniFile, "Icons", "ShowIcon_Rival", ShowIcon_Rival ? "true" : "false") = "true")
    try ShowIcon_BuyCar := (IniRead(iniFile, "Icons", "ShowIcon_BuyCar", ShowIcon_BuyCar ? "true" : "false") = "true")
    try ShowIcon_Gas := (IniRead(iniFile, "Icons", "ShowIcon_Gas", ShowIcon_Gas ? "true" : "false") = "true")
    try ShowIcon_EnterSpam := (IniRead(iniFile, "Icons", "ShowIcon_EnterSpam", ShowIcon_EnterSpam ? "true" : "false") = "true")
    try ShowIcon_EditBox := (IniRead(iniFile, "Icons", "ShowIcon_EditBox", ShowIcon_EditBox ? "true" : "false") = "true")
    try ShowIcon_Exit := (IniRead(iniFile, "Icons", "ShowIcon_Exit", ShowIcon_Exit ? "true" : "false") = "true")

    ; [DetectBoxes]
    LoadDetectBoxesFromIni()
}

SafeIniWrite(val, section, key) {
    iniFile := A_ScriptDir "\fh6.ini"
    Loop 5 {
        try {
            IniWrite(val, iniFile, section, key)
            return
        } catch {
            Sleep(30)
        }
    }
}

SaveAllToIni() {
    global LoadVehicleDelay, LongPressDelay, EnableGamepad, IsSimplifyDividers
    global AutoLoopEnabled, LoopCountLimit, SkillPath, SkillPoints, SkillBuyCarEnabled
    global NewSequenceLoopLimit, labcode, BuyCarLoopLimit, RivalLoopLimit, RivalThrottleSec
    global Enable5AMWait, RebootHour, RebootWaitMin, ShowDashedBox
    global BuyCarMfgUp, BuyCarMfgDown, BuyCarMfgLeft, BuyCarMfgRight
    global BuyCarSelUp, BuyCarSelDown, BuyCarSelLeft, BuyCarSelRight
    global ShowIcon_Esc, ShowIcon_NewSeq, ShowIcon_Seq, ShowIcon_Rival, ShowIcon_BuyCar, ShowIcon_Gas, ShowIcon_EnterSpam, ShowIcon_EditBox, ShowIcon_Exit

    iniFile := A_ScriptDir "\fh6.ini"

    ; [Settings]
    SafeIniWrite(String(LoadVehicleDelay), "Settings", "LoadVehicleDelay")
    SafeIniWrite(String(LongPressDelay), "Settings", "LongPressDelay")
    SafeIniWrite(String(EnableGamepad), "Settings", "EnableGamepad")
    SafeIniWrite(IsSimplifyDividers ? "true" : "false", "Settings", "IsSimplifyDividers")
    SafeIniWrite(AutoLoopEnabled ? "true" : "false", "Settings", "AutoLoopEnabled")
    SafeIniWrite(String(LoopCountLimit), "Settings", "LoopCountLimit")
    SafeIniWrite(SkillPath, "Settings", "SkillPath")
    SafeIniWrite(String(SkillPoints), "Settings", "SkillPoints")
    SafeIniWrite(SkillBuyCarEnabled ? "true" : "false", "Settings", "SkillBuyCarEnabled")
    SafeIniWrite(String(NewSequenceLoopLimit), "Settings", "NewSequenceLoopLimit")
    SafeIniWrite(labcode, "Settings", "labcode")
    SafeIniWrite(String(BuyCarLoopLimit), "Settings", "BuyCarLoopLimit")
    SafeIniWrite(String(RivalLoopLimit), "Settings", "RivalLoopLimit")
    SafeIniWrite(String(RivalThrottleSec), "Settings", "RivalThrottleSec")
    SafeIniWrite(Enable5AMWait ? "true" : "false", "Settings", "Enable5AMWait")
    SafeIniWrite(String(RebootHour), "Settings", "RebootHour")
    SafeIniWrite(String(RebootWaitMin), "Settings", "RebootWaitMin")
    SafeIniWrite(ShowDashedBox ? "true" : "false", "Settings", "ShowDashedBox")

    ; [BuyCar]
    SafeIniWrite(String(BuyCarMfgUp), "BuyCar", "BuyCarMfgUp")
    SafeIniWrite(String(BuyCarMfgDown), "BuyCar", "BuyCarMfgDown")
    SafeIniWrite(String(BuyCarMfgLeft), "BuyCar", "BuyCarMfgLeft")
    SafeIniWrite(String(BuyCarMfgRight), "BuyCar", "BuyCarMfgRight")
    SafeIniWrite(String(BuyCarSelUp), "BuyCar", "BuyCarSelUp")
    SafeIniWrite(String(BuyCarSelDown), "BuyCar", "BuyCarSelDown")
    SafeIniWrite(String(BuyCarSelLeft), "BuyCar", "BuyCarSelLeft")
    SafeIniWrite(String(BuyCarSelRight), "BuyCar", "BuyCarSelRight")

    ; [Icons]
    SafeIniWrite(ShowIcon_Esc ? "true" : "false", "Icons", "ShowIcon_Esc")
    SafeIniWrite(ShowIcon_NewSeq ? "true" : "false", "Icons", "ShowIcon_NewSeq")
    SafeIniWrite(ShowIcon_Seq ? "true" : "false", "Icons", "ShowIcon_Seq")
    SafeIniWrite(ShowIcon_Rival ? "true" : "false", "Icons", "ShowIcon_Rival")
    SafeIniWrite(ShowIcon_BuyCar ? "true" : "false", "Icons", "ShowIcon_BuyCar")
    SafeIniWrite(ShowIcon_Gas ? "true" : "false", "Icons", "ShowIcon_Gas")
    SafeIniWrite(ShowIcon_EnterSpam ? "true" : "false", "Icons", "ShowIcon_EnterSpam")
    SafeIniWrite(ShowIcon_EditBox ? "true" : "false", "Icons", "ShowIcon_EditBox")
    SafeIniWrite(ShowIcon_Exit ? "true" : "false", "Icons", "ShowIcon_Exit")

    ; [DetectBoxes]
    SaveDetectBoxesToIni()
}

LoadDetectBoxesFromIni() {
    global DetectBoxDefs
    iniFile := A_ScriptDir "\fh6.ini"
    if !FileExist(iniFile)
        return

    Loop 13 {
        mode := A_Index
        try {
            valStr := IniRead(iniFile, "DetectBoxes", "Mode" mode, "")
            if (valStr != "") {
                if RegExMatch(valStr, "x1\s*:=\s*(?:wX|vpX)\s*\+\s*Floor\((?:wW|vpW)\s*\*\s*([\d\.]+)\)", &m1)
                && RegExMatch(valStr, "y1\s*:=\s*(?:wY|vpY|vpH?)\s*\+\s*Floor\((?:wH|vpH)\s*\*\s*([\d\.]+)\)", &m2)
                && RegExMatch(valStr, "x2\s*:=\s*(?:wX|vpX)\s*\+\s*Floor\((?:wW|vpW)\s*\*\s*([\d\.]+)\)", &m3)
                && RegExMatch(valStr, "y2\s*:=\s*(?:wY|vpY|vpH?)\s*\+\s*Floor\((?:wH|vpH)\s*\*\s*([\d\.]+)\)", &m4) {
                    vx1 := Float(m1[1]), vy1 := Float(m2[1]), vx2 := Float(m3[1]), vy2 := Float(m4[1])
                    ; 防呆過濾：避免 0 座標或尺寸太小的損壞數值覆蓋設定
                    if (vx2 > vx1 && vy2 > vy1 && (vx2 - vx1) >= 0.003 && (vy2 - vy1) >= 0.003) {
                        DetectBoxDefs[mode].x1 := vx1
                        DetectBoxDefs[mode].y1 := vy1
                        DetectBoxDefs[mode].x2 := vx2
                        DetectBoxDefs[mode].y2 := vy2
                    }
                }
            }
        }
    }
}

SaveDetectBoxesToIni() {
    global DetectBoxDefs
    iniFile := A_ScriptDir "\fh6.ini"
    Loop 13 {
        mode := A_Index
        box := DetectBoxDefs[mode]
        refVarX := (box.ref == "Viewport") ? "vpX" : "wX"
        refVarW := (box.ref == "Viewport") ? "vpW" : "wW"
        refVarY := (box.ref == "Viewport") ? "vpY" : "wY"
        refVarH := (box.ref == "Viewport") ? "vpH" : "wH"
        
        valStr := Format("x1 := {} + Floor({} * {:.3f}), y1 := {} + Floor({} * {:.3f}), x2 := {} + Floor({} * {:.3f}), y2 := {} + Floor({} * {:.3f})",
            refVarX, refVarW, box.x1,
            refVarY, refVarH, box.y1,
            refVarX, refVarW, box.x2,
            refVarY, refVarH, box.y2)
        
        SafeIniWrite(valStr, "DetectBoxes", "Mode" mode)
    }
}

GetDetectBoxCoords(mode, &x1, &y1, &x2, &y2) {
    global DetectBoxDefs, DefaultDetectBoxDefs
    GetTargetGameWindowPos(&wX, &wY, &wW, &wH)
    GetGameViewportClientRect(&vpX, &vpY, &vpW, &vpH)

    box := DetectBoxDefs.Has(mode) ? DetectBoxDefs[mode] : DetectBoxDefs[1]

    ; 🛡️ 自動防呆：若讀取到 0 或損壞座標 (x2<=x1 或 y2<=y1)，自動自硬體預設值自我修復
    if (box.x2 <= box.x1 || box.y2 <= box.y1 || (box.x2 - box.x1) < 0.003 || (box.y2 - box.y1) < 0.003) {
        def := DefaultDetectBoxDefs.Has(mode) ? DefaultDetectBoxDefs[mode] : DefaultDetectBoxDefs[1]
        box.x1 := def.x1
        box.y1 := def.y1
        box.x2 := def.x2
        box.y2 := def.y2
    }

    if (box.ref == "Viewport") {
        x1 := vpX + Floor(vpW * box.x1)
        y1 := vpY + Floor(vpH * box.y1)
        x2 := vpX + Floor(vpW * box.x2)
        y2 := vpY + Floor(vpH * box.y2)
    } else {
        x1 := wX + Floor(wW * box.x1)
        y1 := wY + Floor(wH * box.y1)
        x2 := wX + Floor(wW * box.x2)
        y2 := wY + Floor(wH * box.y2)
    }
}

ToggleEditBoxMode() {
    global isEditBoxMode, EditBoxMenuGui, EditBoxWindowGui, isGasOn, isSequenceRunning, isEnterSpamRunning, isNewSequenceRunning, isBuyCarRunning, isRivalRunning, currentSelectedEditMode

    if (!isEditBoxMode) {
        if (isGasOn || isSequenceRunning || isEnterSpamRunning || isNewSequenceRunning || isBuyCarRunning || isRivalRunning) {
            ShowTip("⚠️ 請先停止目前運行的行程後再啟用編輯偵測框！")
            return
        }

        isEditBoxMode := true
        CreateEditBoxMenuGui()
        SelectEditBoxMode(currentSelectedEditMode)
        SetTimer(UpdateEditBoxCoords, 50)
        ShowTip("已進入編輯偵測框模式 (可拖移/縮放視窗，再點擊 ⿴ 儲存並離開)")
    } else {
        isEditBoxMode := false
        SetTimer(UpdateEditBoxCoords, 0)
        
        SaveAllToIni()

        if (EditBoxWindowGui != "") {
            try EditBoxWindowGui.Destroy()
            EditBoxWindowGui := ""
            EditBoxHeaderCtrl := ""
            EditBoxInfoCtrl := ""
            EditBoxStatusCtrl := ""
        }
        if (EditBoxMenuGui != "") {
            try EditBoxMenuGui.Destroy()
            EditBoxMenuGui := ""
        }

        ShowTip("已離開編輯模式並成功儲存設定至 fh6.ini")
    }
}

CreateEditBoxMenuGui() {
    global EditBoxMenuGui, DetectBoxDefs, currentSelectedEditMode, MyGui, GuiX, GuiY
    global ShowDashedBox, EnableGamepad, Enable5AMWait, RebootHour, RebootWaitMin

    if (EditBoxMenuGui != "") {
        try EditBoxMenuGui.Destroy()
    }

    EditBoxMenuGui := Gui("+AlwaysOnTop -MaximizeBox -MinimizeBox +ToolWindow", "⿴ 偵測與系統功能選單")
    EditBoxMenuGui.BackColor := "0x1E1E2E"
    EditBoxMenuGui.SetFont("s10 bold c0x00FFFF", "Segoe UI")

    EditBoxMenuGui.AddText("x15 y12", "請選擇要編輯的偵測功能：")

    EditBoxMenuGui.SetFont("norm s10 cWhite", "Segoe UI")
    items := []
    Loop 13 {
        items.Push(DetectBoxDefs[A_Index].name)
    }

    lb := EditBoxMenuGui.Add("ListBox", "x15 y35 w290 r13 cWhite Background0x181825 Choose" currentSelectedEditMode, items)
    lb.OnEvent("Change", (ctrl, info) => SelectEditBoxMode(ctrl.Value))

    resetOneBtn := EditBoxMenuGui.Add("Button", "x15 y295 w140 h30", "🔄 重置此項預設")
    resetOneBtn.OnEvent("Click", (*) => ResetDetectBoxToDefault(currentSelectedEditMode))

    resetAllBtn := EditBoxMenuGui.Add("Button", "x165 y295 w140 h30", "⚠️ 重置全部預設")
    resetAllBtn.OnEvent("Click", (*) => ResetDetectBoxToDefault(0))

    ; ⚙ 系統、手把與路由器重啟設定
    EditBoxMenuGui.SetFont("s9 bold c0x00FFFF", "Segoe UI")
    EditBoxMenuGui.Add("GroupBox", "x15 y332 w290 h185 c0x00FFFF", "⚙ 系統與斷線重啟設定")

    SetSimplifyDividers(val) {
        global IsSimplifyDividers
        IsSimplifyDividers := val ? true : false
        SaveAllToIni()
    }
    SetShowDashedBox(val) {
        global ShowDashedBox
        ShowDashedBox := val ? true : false
        SaveAllToIni()
    }
    SetEnableGamepad(val) {
        global EnableGamepad
        EnableGamepad := val ? 1 : 0
        SaveAllToIni()
    }
    SetEnable5AMWait(val) {
        global Enable5AMWait
        Enable5AMWait := val ? true : false
        SaveAllToIni()
    }
    SetRebootHour(val) {
        global RebootHour
        RebootHour := Max(0, Min(23, Integer(val || 5)))
        SaveAllToIni()
    }
    SetRebootWaitMin(val) {
        global RebootWaitMin
        RebootWaitMin := Max(1, Min(60, Integer(val || 5)))
        SaveAllToIni()
    }

    cbSimplify := EditBoxMenuGui.AddCheckBox("x25 y354 " (IsSimplifyDividers ? "Checked" : ""), "📊 簡化進度條格數 (每十次畫一格)")
    cbSimplify.OnEvent("Click", (ctrl, *) => SetSimplifyDividers(ctrl.Value))

    cbDashed := EditBoxMenuGui.AddCheckBox("x25 y377 " (ShowDashedBox ? "Checked" : ""), "🔳 顯示偵測顏色的虛線框")
    cbDashed.OnEvent("Click", (ctrl, *) => SetShowDashedBox(ctrl.Value))

    cbPad := EditBoxMenuGui.AddCheckBox("x25 y400 " (EnableGamepad ? "Checked" : ""), "🎮 啟用 Xbox 手把控制")
    cbPad.OnEvent("Click", (ctrl, *) => SetEnableGamepad(ctrl.Value))

    cbWait5 := EditBoxMenuGui.AddCheckBox("x25 y423 " (Enable5AMWait ? "Checked" : ""), "⏰ 啟用每日網路斷線自動等待")
    cbWait5.OnEvent("Click", (ctrl, *) => SetEnable5AMWait(ctrl.Value))

    ; 斷線小時拉桿 (0 ~ 23 點)
    EditBoxMenuGui.SetFont("s9 cWhite", "Segoe UI")
    EditBoxMenuGui.AddText("x25 y450", "斷線時間：")
    EditBoxMenuGui.SetFont("s9 bold c0x00FFFF", "Segoe UI")
    lblHourVal := EditBoxMenuGui.AddText("x85 y450 w45", RebootHour " 點")
    sldHour := EditBoxMenuGui.AddSlider("x135 y447 w160 h24 Range0-23 Thick20 Tooltip AltSubmit", RebootHour)
    sldHour.OnEvent("Change", (ctrl, *) => (
        SetRebootHour(ctrl.Value),
        lblHourVal.Value := ctrl.Value " 點"
    ))

    ; 等待分鐘拉桿 (1 ~ 60 分鐘)
    EditBoxMenuGui.SetFont("s9 cWhite", "Segoe UI")
    EditBoxMenuGui.AddText("x25 y482", "等待時間：")
    EditBoxMenuGui.SetFont("s9 bold c0x00FFFF", "Segoe UI")
    lblWaitVal := EditBoxMenuGui.AddText("x85 y482 w45", RebootWaitMin " 分")
    sldWait := EditBoxMenuGui.AddSlider("x135 y479 w160 h24 Range1-60 Thick20 Tooltip AltSubmit", RebootWaitMin)
    sldWait.OnEvent("Change", (ctrl, *) => (
        SetRebootWaitMin(ctrl.Value),
        lblWaitVal.Value := ctrl.Value " 分"
    ))

    writeAhkBtn := EditBoxMenuGui.Add("Button", "x15 y527 w290 h34", "📋 將 INI / 目前設定固化寫回 AHK 預設值")
    writeAhkBtn.OnEvent("Click", (*) => SaveIniAsAHKDefaults())

    saveBtn := EditBoxMenuGui.Add("Button", "x15 y569 w290 h36 +Default", "💾 儲存設定並離開 (⿴)")
    saveBtn.OnEvent("Click", (*) => ToggleEditBoxMode())

    EditBoxMenuGui.OnEvent("Close", (*) => ToggleEditBoxMode())

    menuX := GuiX + 40
    menuY := GuiY + 45
    EditBoxMenuGui.Show("X" menuX " Y" menuY " W320 H615 NoActivate")
}

ResetDetectBoxToDefault(mode := 0) {
    global DetectBoxDefs, DefaultDetectBoxDefs, currentSelectedEditMode
    if (mode == 0) {
        Loop 13 {
            m := A_Index
            def := DefaultDetectBoxDefs[m]
            DetectBoxDefs[m].x1 := def.x1
            DetectBoxDefs[m].y1 := def.y1
            DetectBoxDefs[m].x2 := def.x2
            DetectBoxDefs[m].y2 := def.y2
        }
        ShowTip("已將全數 13 個偵測框重置為原廠預設值！")
    } else {
        def := DefaultDetectBoxDefs[mode]
        DetectBoxDefs[mode].x1 := def.x1
        DetectBoxDefs[mode].y1 := def.y1
        DetectBoxDefs[mode].x2 := def.x2
        DetectBoxDefs[mode].y2 := def.y2
        ShowTip(Format("已將「{}」重置為原廠預設值！", DetectBoxDefs[mode].name))
    }
    SaveAllToIni()
    SelectEditBoxMode(currentSelectedEditMode)
}

SaveIniAsAHKDefaults() {
    global DetectBoxDefs, DefaultDetectBoxDefs
    global EnableGamepad, Enable5AMWait, RebootHour, RebootWaitMin, ShowDashedBox
    global LoadVehicleDelay, LongPressDelay, IsSimplifyDividers, AutoLoopEnabled, LoopCountLimit
    global SkillPath, SkillPoints, SkillBuyCarEnabled, NewSequenceLoopLimit, labcode
    global BuyCarLoopLimit, RivalLoopLimit, RivalThrottleSec
    global BuyCarMfgUp, BuyCarMfgDown, BuyCarMfgLeft, BuyCarMfgRight
    global BuyCarSelUp, BuyCarSelDown, BuyCarSelLeft, BuyCarSelRight
    global ShowIcon_Esc, ShowIcon_NewSeq, ShowIcon_Seq, ShowIcon_Rival, ShowIcon_BuyCar, ShowIcon_Gas, ShowIcon_EnterSpam, ShowIcon_EditBox, ShowIcon_Exit

    ahkFile := A_ScriptFullPath

    try {
        content := FileRead(ahkFile, "UTF-8")

        ; 1. 替換 DetectBoxDefs 與 DefaultDetectBoxDefs 地圖
        bOpen := "{", bClose := "}"
        newDefStr := "global DetectBoxDefs := Map(`n"
        Loop 13 {
            m := A_Index
            box := DetectBoxDefs[m]
            Comma := (m < 13) ? "," : ""
            newDefStr .= Format("    {:d},  " bOpen " name: `"{}`", desc: `"{}`", ref: `"{}`",   x1: {:.3f}, y1: {:.3f}, x2: {:.3f}, y2: {:.3f} " bClose "{}`n",
                m, box.name, box.desc, box.ref, box.x1, box.y1, box.x2, box.y2, Comma)
        }
        newDefStr .= ")"

        newDefaultStr := "global DefaultDetectBoxDefs := Map(`n"
        Loop 13 {
            m := A_Index
            box := DetectBoxDefs[m]
            Comma := (m < 13) ? "," : ""
            newDefaultStr .= Format("    {:d},  " bOpen " x1: {:.3f}, y1: {:.3f}, x2: {:.3f}, y2: {:.3f} " bClose "{}`n",
                m, box.x1, box.y1, box.x2, box.y2, Comma)
        }
        newDefaultStr .= ")"

        if RegExMatch(content, "s)global DetectBoxDefs := Map\(.*?\)", &match1) {
            content := RegExReplace(content, "s)global DetectBoxDefs := Map\(.*?\)", newDefStr, , 1)
        }
        if RegExMatch(content, "s)global DefaultDetectBoxDefs := Map\(.*?\)", &match2) {
            content := RegExReplace(content, "s)global DefaultDetectBoxDefs := Map\(.*?\)", newDefaultStr, , 1)
        }

        ; 2. 替換全域變數預設值 (全行程各種設定)
        ReplaceVar(&src, varName, newVal) {
            valStr := (Type(newVal) == "String") ? '"' newVal '"' : (newVal = true ? "true" : (newVal = false ? "false" : String(newVal)))
            src := RegExReplace(src, "m)^(\s*global\s+" varName "\s*:=\s*)[^;`r`n]+", "${1}" valStr, , 1)
        }

        ReplaceVar(&content, "EnableGamepad", EnableGamepad)
        ReplaceVar(&content, "Enable5AMWait", Enable5AMWait ? true : false)
        ReplaceVar(&content, "RebootHour", RebootHour)
        ReplaceVar(&content, "RebootWaitMin", RebootWaitMin)
        ReplaceVar(&content, "ShowDashedBox", ShowDashedBox ? true : false)

        ReplaceVar(&content, "LoadVehicleDelay", LoadVehicleDelay)
        ReplaceVar(&content, "LongPressDelay", LongPressDelay)
        ReplaceVar(&content, "IsSimplifyDividers", IsSimplifyDividers ? true : false)
        ReplaceVar(&content, "AutoLoopEnabled", AutoLoopEnabled ? true : false)
        ReplaceVar(&content, "LoopCountLimit", LoopCountLimit)
        ReplaceVar(&content, "SkillPath", SkillPath)
        ReplaceVar(&content, "SkillPoints", SkillPoints)
        ReplaceVar(&content, "SkillBuyCarEnabled", SkillBuyCarEnabled ? true : false)
        ReplaceVar(&content, "NewSequenceLoopLimit", NewSequenceLoopLimit)
        ReplaceVar(&content, "labcode", labcode)
        ReplaceVar(&content, "BuyCarLoopLimit", BuyCarLoopLimit)
        ReplaceVar(&content, "RivalLoopLimit", RivalLoopLimit)
        ReplaceVar(&content, "RivalThrottleSec", RivalThrottleSec)

        ReplaceVar(&content, "BuyCarMfgUp", BuyCarMfgUp)
        ReplaceVar(&content, "BuyCarMfgDown", BuyCarMfgDown)
        ReplaceVar(&content, "BuyCarMfgLeft", BuyCarMfgLeft)
        ReplaceVar(&content, "BuyCarMfgRight", BuyCarMfgRight)
        ReplaceVar(&content, "BuyCarSelUp", BuyCarSelUp)
        ReplaceVar(&content, "BuyCarSelDown", BuyCarSelDown)
        ReplaceVar(&content, "BuyCarSelLeft", BuyCarSelLeft)
        ReplaceVar(&content, "BuyCarSelRight", BuyCarSelRight)

        ReplaceVar(&content, "ShowIcon_Esc", ShowIcon_Esc ? true : false)
        ReplaceVar(&content, "ShowIcon_NewSeq", ShowIcon_NewSeq ? true : false)
        ReplaceVar(&content, "ShowIcon_Seq", ShowIcon_Seq ? true : false)
        ReplaceVar(&content, "ShowIcon_Rival", ShowIcon_Rival ? true : false)
        ReplaceVar(&content, "ShowIcon_BuyCar", ShowIcon_BuyCar ? true : false)
        ReplaceVar(&content, "ShowIcon_Gas", ShowIcon_Gas ? true : false)
        ReplaceVar(&content, "ShowIcon_EnterSpam", ShowIcon_EnterSpam ? true : false)
        ReplaceVar(&content, "ShowIcon_EditBox", ShowIcon_EditBox ? true : false)
        ReplaceVar(&content, "ShowIcon_Exit", ShowIcon_Exit ? true : false)

        f := FileOpen(ahkFile, "w", "UTF-8")
        f.Write(content)
        f.Close()

        Loop 13 {
            m := A_Index
            DefaultDetectBoxDefs[m].x1 := DetectBoxDefs[m].x1
            DefaultDetectBoxDefs[m].y1 := DetectBoxDefs[m].y1
            DefaultDetectBoxDefs[m].x2 := DetectBoxDefs[m].x2
            DefaultDetectBoxDefs[m].y2 := DetectBoxDefs[m].y2
        }

        ShowTip("✅ 已成功將目前 INI / 全行程最新設定與座標固化寫回 AHK 原始碼預設值！")
    } catch as err {
        ShowTip("⚠️ 寫回 AHK 預設值失敗：" err.Message)
    }
}

SelectEditBoxMode(mode) {
    global currentSelectedEditMode, EditBoxWindowGui, EditBoxHeaderCtrl, EditBoxInfoCtrl, EditBoxStatusCtrl, DetectBoxDefs, GameTitle, lastEditBoxPos

    ; 切換到新偵測框時，立刻將上一個與全域設定同步儲存至 ini
    SaveAllToIni()

    currentSelectedEditMode := mode
    GetDetectBoxCoords(mode, &x1, &y1, &x2, &y2)
    w := Max(20, x2 - x1)
    h := Max(20, y2 - y1)

    lastEditBoxPos.x := x1
    lastEditBoxPos.y := y1
    lastEditBoxPos.w := w
    lastEditBoxPos.h := h

    if (EditBoxWindowGui != "") {
        try EditBoxWindowGui.Destroy()
        EditBoxWindowGui := ""
        EditBoxHeaderCtrl := ""
        EditBoxInfoCtrl := ""
        EditBoxStatusCtrl := ""
    }

    EditBoxWindowGui := Gui("+AlwaysOnTop +Resize -Caption +ToolWindow")
    EditBoxWindowGui.BackColor := "0x00FFFF"
    WinSetTransparent(180, EditBoxWindowGui.Hwnd)

    ; 左上角偵測狀態標籤
    EditBoxWindowGui.SetFont("s9 bold cWhite", "Segoe UI")
    EditBoxStatusCtrl := EditBoxWindowGui.Add("Text", "x5 y2 w115 h20 Center Background0x000000", "[ ⏳ 檢測中 ]")

    ; 頂部標題說明
    EditBoxWindowGui.SetFont("s10 bold cBlack", "Segoe UI")
    EditBoxHeaderCtrl := EditBoxWindowGui.Add("Text", "x125 y2 w875 h20 Center Background0x00FFFF", DetectBoxDefs[mode].desc)

    ; 下方座標數據
    EditBoxWindowGui.SetFont("norm s9 cBlack", "Segoe UI")
    EditBoxInfoCtrl := EditBoxWindowGui.Add("Text", "x0 y24 w1000 h40 Center Background0x00FFFF", "")

    EditBoxWindowGui.Show("X" x1 " Y" y1 " W" w " H" h " NoActivate")

    try {
        EditBoxWindowGui.GetPos(&gX, &gY, &gW, &gH)
        lastEditBoxPos.x := gX
        lastEditBoxPos.y := gY
        lastEditBoxPos.w := gW
        lastEditBoxPos.h := gH
    } catch {
        lastEditBoxPos.x := x1
        lastEditBoxPos.y := y1
        lastEditBoxPos.w := w
        lastEditBoxPos.h := h
    }

    ; 切換開啟新偵測框時，立刻進行一次單次偵測
    PerformEditBoxDetection()
}



UpdateEditBoxCoords() {
    global isEditBoxMode, EditBoxWindowGui, EditBoxHeaderCtrl, EditBoxInfoCtrl, EditBoxStatusCtrl, currentSelectedEditMode, DetectBoxDefs, GameTitle, lastEditBoxPos

    if (!isEditBoxMode || EditBoxWindowGui == "")
        return

    try {
        EditBoxWindowGui.GetPos(&gX, &gY, &gW, &gH)
    } catch {
        return
    }

    ; 🛡️ 防呆保護：過濾載入失敗/最小化等異常 0 座標尺寸，避免寫入 0 壞損資料
    if (gW <= 30 || gH <= 20)
        return

    ; 只有當使用者實際用滑鼠拖移或縮放變動視窗時，才更新座標
    if (gX == lastEditBoxPos.x && gY == lastEditBoxPos.y && gW == lastEditBoxPos.w && gH == lastEditBoxPos.h)
        return

    lastEditBoxPos.x := gX
    lastEditBoxPos.y := gY
    lastEditBoxPos.w := gW
    lastEditBoxPos.h := gH

    mode := currentSelectedEditMode
    box := DetectBoxDefs[mode]

    if (box.ref == "Viewport") {
        GetGameViewportClientRect(&refX, &refY, &refW, &vpH)
        refH := vpH
    } else {
        GetTargetGameWindowPos(&refX, &refY, &refW, &refH)
    }

    if (refW <= 0 || refH <= 0)
        return

    x1_pct := Max(0.0, Min(1.0, (gX - refX) / refW))
    y1_pct := Max(0.0, Min(1.0, (gY - refY) / refH))
    x2_pct := Max(x1_pct + 0.001, Min(1.0, (gX + gW - refX) / refW))
    y2_pct := Max(y1_pct + 0.001, Min(1.0, (gY + gH - refY) / refH))

    box.x1 := Round(x1_pct, 3)
    box.y1 := Round(y1_pct, 3)
    box.x2 := Round(x2_pct, 3)
    box.y2 := Round(y2_pct, 3)

    try {
        if (EditBoxHeaderCtrl != "") {
            EditBoxHeaderCtrl.Move(125, 2, Max(10, gW - 125), 20)
        }
        if (EditBoxInfoCtrl != "") {
            EditBoxInfoCtrl.Move(0, 24, gW, Max(20, gH - 24))
            infoText := Format("X: {:.1f}% ~ {:.1f}% ({:.3f} ~ {:.3f})`nY: {:.1f}% ~ {:.1f}% ({:.3f} ~ {:.3f})",
                x1_pct * 100, x2_pct * 100, x1_pct, x2_pct,
                y1_pct * 100, y2_pct * 100, y1_pct, y2_pct)
            EditBoxInfoCtrl.Value := infoText
        }
        if (EditBoxStatusCtrl != "") {
            EditBoxStatusCtrl.Value := "[ ⏳ 調整中... ]"
        }
    }

    ; 停止持續偵測，於移動縮放停止 300ms 後執行一次單次偵測與儲存
    SetTimer(PerformEditBoxDetection, -300)
}

PerformEditBoxDetection() {
    global isEditBoxMode, EditBoxStatusCtrl, currentSelectedEditMode

    if (!isEditBoxMode || EditBoxStatusCtrl == "")
        return

    ; 執行單次顏色彩色與 UI 偵測 (非持續偵測)
    found := DetectColorByMode(currentSelectedEditMode, false)

    try {
        if (found) {
            EditBoxStatusCtrl.Value := "[ ✅ 已偵測到 ]"
        } else {
            EditBoxStatusCtrl.Value := "[ ❌ 未偵測到 ]"
        }
    }

    ; 偵測完成後立即寫入儲存 ini
    SaveAllToIni()
}
