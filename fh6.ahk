; =================================================================
; Forza Horizon 6 (FH6) 自動化輔助腳本
; 版本: 1.0.0
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

OnExit( (*) => (
    ForceReleaseW_Hardware(),
    Send("{a up}{s up}{d up}{x up}{Space up}{Down up}{Shift up}{Ctrl up}{Alt up}{Enter up}{Esc up}")
))

; =================================================================
; [全域自動化參數設定區]
; =================================================================
global LoadVehicleDelay := 11   ; 等待車輛載入時間（秒）
global LongPressDelay := 3.0     ; 手把長按偵測時間（秒）
global WHoldDuration := 60       ; 賺技能點時按住油門前進的時間（秒）
global GameTitle := "ahk_exe ForzaHorizon6.exe" ; 遊戲視窗標題名稱
global ConfirmState := { result: false, isWaiting: false }

; [行程循環次數設定]
global LoopCountLimit := 10       ; 技能行程循環次數
global NewSequenceLoopLimit := 50 ; 賺技能點行程循環次數
global BuyCarLoopLimit := 23      ; 買車行程循環次數

; [點技能選廠牌位置]
global BrandDownCount := 9
global BrandRightCount := 1

; [觸控按鈕位置與進度條設定]
global GuiX := 0
global GuiY := 0
global GuiH := 30
global GuiOpacity := 180
global ProgressBarWidth := 610
global IsSimplifyDividers := true ; 是否簡化進度條格數，當超過等於20次後會每10次畫一格

; [動態分格 UI 陣列]
global DividerCtrls := []
; =================================================================

global isGasOn := false
global isSequenceRunning := false
global isEnterSpamRunning := false
global isNewSequenceRunning := false
global isBuyCarRunning := false
global currentLoopItem := 0
global currentNewLoopItem := 0
global currentBuyCarLoopItem := 0
global isConfirming := false
global currentStepText := ""

global xTriggeredThisPress := false
global yTriggeredThisPress := false
global lTriggeredThisPress := false

; --- 【倒數計時器全域變數】 ---
global sequenceStartTime := 0
global sequenceTotalSec := 0

; --- 【UI 介面設定區】 ---
global MyGui := Gui("+AlwaysOnTop -Caption -Border +ToolWindow +Owner")
MyGui.BackColor := "010101"

global GuiBtns := []
global btnConfigs := [
    { symbol: "🚗", x: 0,   fn: (*) => (isBuyCarRunning ? StopGasAndClean() : (WinActive(GameTitle) ? ToggleBuyCarSequence() : "")) },
    { symbol: "⚔", x: 40,  fn: (*) => (isNewSequenceRunning ? StopGasAndClean() : (WinActive(GameTitle) ? ToggleNewSequence() : "")) },
    { symbol: "🎰", x: 80,  fn: (*) => (isEnterSpamRunning ? StopGasAndClean() : (WinActive(GameTitle) ? ToggleEnterSpam() : "")) },
    { symbol: "⚡", x: 120, fn: (*) => (isSequenceRunning ? StopGasAndClean() : (WinActive(GameTitle) ? ToggleLButtonSequence() : "")) },
    { symbol: "🏆", x: 160, fn: (*) => (isGasOn ? StopGasAndClean() : (WinActive(GameTitle) ? ToggleGas() : "")) },
    { symbol: "⏏", x: 200, fn: (*) => (StopGasAndClean(), MyGui.Destroy(), ExitApp()) }
]

MyGui.SetFont("s16", "Segoe UI Emoji")
for idx, cfg in btnConfigs {
    btn := MyGui.Add("Text", "cWhite x" cfg.x " y-2 w40 h34 Center +0x200 -Wrap", cfg.symbol)
    btn.OnEvent("Click", cfg.fn)
    GuiBtns.Push(btn)
}

; 💡 進度條位置
global ProgressBar := MyGui.Add("Progress", "x45 y3 w" . ProgressBarWidth . " h24 Backgroundffffff cYellow", 0)

Loop 30 {
    ctrl := MyGui.Add("Text", "y3 w2 h24 +BackgroundAAAAFF +Hidden", "")
    DividerCtrls.Push(ctrl)
}

MyGui.SetFont("s16 Bold", "Microsoft JhengHei")

; 💡 文字置中微調
global ProgressText := MyGui.Add("Text", "cBlack x45 y1 w" . ProgressBarWidth . " h28 +BackgroundTrans +0x200", "")

; 定義 UI 切換輔助函數
UpdateUiRunningState(runningIdx) {
    global GuiBtns, MyGui, GuiX, GuiY, GuiH, GuiOpacity, ProgressBar, ProgressText
    for idx, btn in GuiBtns {
        if (idx == runningIdx) {
            btn.Move(0, -2)
            btn.Visible := true
        } else {
            btn.Visible := false
            btn.Move(-100, -100)
        }
    }
    
    if (runningIdx == 3 || runningIdx == 5) {
        ProgressBar.Visible := false
        ProgressText.Visible := false
        MyGui.Show("X" GuiX " Y" GuiY " W40 h" GuiH " NoActivate")
    } else {
        ProgressBar.Visible := true
        ProgressText.Visible := true
        MyGui.Show("X" GuiX " Y" GuiY " W660 h" GuiH " NoActivate")
    }
    WinSetTransparent(GuiOpacity, MyGui.Hwnd)
}

ResetUiToNormal() {
    global GuiBtns, MyGui, GuiX, GuiY, GuiH, GuiOpacity, ProgressBar, ProgressText, GameTitle
    ProgressBar.Visible := false
    ProgressText.Visible := false
    xCoords := [0, 40, 80, 120, 160, 200]
    for idx, btn in GuiBtns {
        btn.Move(xCoords[idx], -2)
        btn.Visible := true
    }
    
    currentActive := WinActive(GameTitle) || WinActive("ahk_id " MyGui.Hwnd)
    if (currentActive) {
        MyGui.Show("X" GuiX " Y" GuiY " W240 h" GuiH " NoActivate")
        WinSetTransparent(GuiOpacity, MyGui.Hwnd)
    }
}

ResetUiToNormal()
WinSetTransparent(GuiOpacity, MyGui.Hwnd)
WinSetExStyle("+0x08000000", MyGui.Hwnd)

OnMessage(0x0201, WM_LBUTTONDOWN)

; --- 【定時器啟動區】 ---
SetTimer(WatchGameWindow, 500)
SetTimer(CheckEveryHourly, 1000, 1)
SetTimer(WatchJoystick, 60)

; =================================================================
; --- 【進度條動態分格管理】 ---
; =================================================================
DrawDividers(limit) {
    global DividerCtrls, ProgressBarWidth, IsSimplifyDividers, MyGui
    ClearDividers()

    totalWidth := ProgressBarWidth
    xPositions := []
    segmentWidth := totalWidth / limit

    Loop limit - 1 {
        ; 如果開啟簡化且次數大於等於 20，只有滿 10 格（A_Index 是 10 的倍數）時才畫
        if (IsSimplifyDividers && limit >= 20) {
            if (Mod(A_Index, 10) == 0) {
                xPositions.Push(45 + (A_Index * segmentWidth))
            }
        } else {
            ; 否則每一格都畫
            xPositions.Push(45 + (A_Index * segmentWidth))
        }
    }

    ; 若分割線座標數量超出預建控制項陣列長度，則動態追加控制項
    while (xPositions.Length > DividerCtrls.Length) {
        ctrl := MyGui.Add("Text", "y3 w2 h24 +BackgroundAAAAFF +Hidden", "")
        DividerCtrls.Push(ctrl)
    }

    for idx, xPos in xPositions {
        ctrl := DividerCtrls[idx]
        ctrl.Move(xPos, 3)
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

; =================================================================
; --- 【無邊框沉浸式確認對話框】 ---
; =================================================================
ShowConfirmDialog(funcName, timeStr, totalCount := 0) {
    global GuiX, GuiY, GuiOpacity, GameTitle, ConfirmState, IsSimplifyDividers

    ConfirmGui := Gui("+AlwaysOnTop -Caption -Border +ToolWindow +Owner")
    ConfirmGui.BackColor := "010101"

    ConfirmGui.SetFont("s22 Bold cWhite", "Microsoft JhengHei")
    ConfirmGui.Add("Text", "x20 y20 w520 Center +BackgroundTrans", "【 " funcName " 】")

    ConfirmGui.SetFont("s18 Bold cGray", "Microsoft JhengHei")

    if (totalCount == "∞") {
        displayText := "預估總執行時間 (∞次)："
    } else if (totalCount > 0) {
        if (IsSimplifyDividers && totalCount >= 20) {
            groupCount := Ceil(totalCount / 10)
            displayText := "預估總執行時間 (" totalCount "次 / 簡化為" groupCount "格)："
        } else {
            displayText := "預估總執行時間 (" totalCount "次)："
        }
    } else {
        displayText := "預估總執行時間："
    }
    ConfirmGui.Add("Text", "x20 y70 w520 Center +BackgroundTrans", displayText)

    ConfirmGui.SetFont("s28 Bold cYellow")
    ConfirmGui.Add("Text", "x20 y110 w520 Center +BackgroundTrans", timeStr)

    ConfirmGui.SetFont("s18 Bold cWhite")
    btnConfirm := ConfirmGui.Add("Text", "x20 y180 w250 h50 Center +BackgroundTrans +0x200", "[手把A / Enter] 確認")
    btnCancel := ConfirmGui.Add("Text", "x290 y180 w250 h50 Center +BackgroundTrans +0x200", "[手把B / Esc] 取消")

    ConfirmGui.Show("X" GuiX " Y" GuiY " W560 H240 NoActivate")
    WinSetTransparent(GuiOpacity, ConfirmGui.Hwnd)
    WinSetExStyle("+0x08000000", ConfirmGui.Hwnd)

    ConfirmState.result := false
    ConfirmState.isWaiting := true

    btnConfirm.OnEvent("Click", (*) => (ConfirmState.result := true, ConfirmState.isWaiting := false))
    btnCancel.OnEvent("Click", (*) => (ConfirmState.result := false, ConfirmState.isWaiting := false))

    Sleep(300)
    while (ConfirmState.isWaiting) {
        if (GetAnyJoyState(1)) {
            ConfirmState.result := true
            break
        }
        if (GetAnyJoyState(2)) {
            ConfirmState.result := false
            break
        }
        Sleep(50)
    }
    ConfirmGui.Destroy()
    Sleep(200)

    if (ConfirmState.result && WinExist(GameTitle)) {
        WinActivate(GameTitle)
        WinWaitActive(GameTitle, , 3)
    }

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
                ; 長按 X -> 啟動 F7 (連點enter)
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
                ; 長按 Y -> 啟動 F8 (技能行程)
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
                
                ; 油門行程 (F9) 運行中 -> 長按 LB 中斷
                if (isGasOn) {
                    if (elapsed >= LongPressDelay * 1000) {
                        StopGasAndClean()
                        lPressedTime := 0
                    }
                } else {
                    ; 非運行中長按 LB -> 啟動 F9 (油門行程)
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
    UpdateUiRunningState(3)

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
        Sleep(60)
        Send("{Enter Up}")
        Sleep(60)
    }
}

RunLButtonSequence() {
    global MyGui, ProgressText, isSequenceRunning, LoadVehicleDelay, BrandDownCount, BrandRightCount, LoopCountLimit, currentLoopItem, GuiX, GuiY, GuiH, loopStartTime, TotalMs, isConfirming
    global sequenceStartTime, sequenceTotalSec
    if (isSequenceRunning) {
        return
    }
    isSequenceRunning := true

    actions := [
        ["Enter", 800], ["Backspace", 1000]
    ]
    if (BrandDownCount > 0) {
        Loop BrandDownCount {
            actions.Push(["Down", 200])
        }
        actions.Push(["_Sleep", 200])
    }
    if (BrandRightCount > 0) {
        Loop BrandRightCount {
            actions.Push(["Right", 200])
        }
        actions.Push(["_Sleep", 200])
    }
    actions.Push(
        ["Enter", 600], ["Down", 450], ["Enter", 600], ["Down", 200, 4],
        ["Enter", 600], ["Down", 450], ["Enter", 600], ["Down", 450],
        ["Enter", 600], ["Enter", 800], ["_LoadVehicle", LoadVehicleDelay * 1000],
        ["Esc", 2000], ["Down", 450], ["Enter", 1200], ["Down", 200, 7],
        ["_Sleep", 400], ["Enter", 1500], ["Enter", 1200], ["Up", 450],
        ["Enter", 1200], ["Up", 450], ["Enter", 1200], ["Up", 450],
        ["Enter", 1200], ["Right", 450], ["Enter", 1200], ["Right", 450],
        ["Enter", 1200], ["Esc", 1200], ["Esc", 1200], ["Up", 450]
    )

    TotalMs := 0
    for item in actions {
        if (item[1] == "_Sleep" || item[1] == "_LoadVehicle") {
            TotalMs += item[2]
        } else {
            repeat := (item.Length >= 3) ? item[3] : 1
            keyTime := (item[1] == "Backspace") ? 200 : 100
            TotalMs += (keyTime + item[2]) * repeat
        }
    }
    
    sequenceTotalSec := Ceil((LoopCountLimit * TotalMs + (LoopCountLimit - 1) * 1500) / 1000)
    timeStr := FormatTimeDuration(sequenceTotalSec)
    
    isConfirming := true
    confirmed := ShowConfirmDialog("技能行程 ⚡", timeStr, LoopCountLimit)
    isConfirming := false

    if (!confirmed) {
        StopGasAndClean()
        return
    }

    if WinExist(GameTitle) {
        WinActivate(GameTitle)
        if !WinWaitActive(GameTitle, , 3) {
            StopGasAndClean()
            return
        }
    }

    DrawDividers(LoopCountLimit)
    sequenceStartTime := A_TickCount
    UpdateUiRunningState(4)
    SetTimer(UpdateLoopProgress, 100)

    SendKey(key, delay) {
        global isSequenceRunning, GameTitle, MyGui
        if (!isSequenceRunning || (!WinActive(GameTitle) && !WinActive("ahk_id " MyGui.Hwnd))) {
            StopGasAndClean()
            Exit
        }
        if (key == "Backspace") {
            Send("{Backspace Up}")
            Sleep(50)
            Send("{Backspace Down}")
            Sleep(150)
            Send("{Backspace Up}")
        } else {
            Send("{" key " Down}")
            Sleep(100)
            Send("{" key " Up}")
        }
        loop Ceil(delay / 50) {
            if (!isSequenceRunning) {
                Exit
            }
            Sleep(50)
        }
    }

    currentLoopItem := 0
    Loop LoopCountLimit {
        if (!isSequenceRunning) {
            break
        }

        currentLoopItem := A_Index
        loopStartTime := A_TickCount

        try {
            for item in actions {
                if (!isSequenceRunning) {
                    break
                }
                actType := item[1]
                actDelay := item[2]

                if (actType == "_Sleep") {
                    ShowTip("等待中 (" actDelay "ms)")
                    Sleep(actDelay)
                } else if (actType == "_LoadVehicle") {
                    ShowTip("載入車輛中 (" Ceil(actDelay / 1000) "秒)")
                    loop Ceil(actDelay / 100) {
                        if (!isSequenceRunning) {
                            Exit
                        }
                        Sleep(100)
                    }
                } else {
                    repeat := (item.Length >= 3) ? item[3] : 1
                    ShowTip("送出按鍵: " actType (repeat > 1 ? " x" repeat : "") " (延遲 " actDelay "ms)")
                    Loop repeat {
                        SendKey(actType, actDelay)
                    }
                }
            }
        } catch Error {
            break
        }
        if (isSequenceRunning && A_Index < LoopCountLimit) {
            loop 30 {
                if (!isSequenceRunning) {
                    break
                }
                Sleep(50)
            }
        }
    }
    StopGasAndClean()
}

WatchGameWindow() {
    global GameTitle, MyGui, GuiX, GuiY, GuiH, isConfirming
    global isSequenceRunning, isNewSequenceRunning, isBuyCarRunning, isEnterSpamRunning, isGasOn
    static isShowing := false

    if (isConfirming) {
        return
    }

    currentActive := WinActive(GameTitle) || WinActive("ahk_id " MyGui.Hwnd)
    if (currentActive) {
        if (!isShowing) {
            MyGui.Hide()
            Sleep(100)
            
            isRunning := (isSequenceRunning || isNewSequenceRunning || isBuyCarRunning || isEnterSpamRunning || isGasOn)
            if (isRunning) {
                runIdx := isBuyCarRunning ? 1 : (isNewSequenceRunning ? 2 : (isEnterSpamRunning ? 3 : (isSequenceRunning ? 4 : 5)))
                UpdateUiRunningState(runIdx)
            } else {
                ResetUiToNormal()
            }
            isShowing := true
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
    UpdateUiRunningState(5)
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

RunNewSequence() {
    global isNewSequenceRunning, GameTitle, MyGui, WHoldDuration, NewSequenceLoopLimit, currentNewLoopItem, newLoopStartTime, NewSequenceTotalMs, GuiX, GuiY, GuiH, isConfirming
    global sequenceStartTime, sequenceTotalSec
    if (isNewSequenceRunning) {
        return
    }
    isNewSequenceRunning := true

    NewSequenceTotalMs := (WHoldDuration * 1000) + 13250
    sequenceTotalSec := Ceil((NewSequenceLoopLimit * NewSequenceTotalMs) / 1000)
    timeStr := FormatTimeDuration(sequenceTotalSec)
    
    isConfirming := true
    confirmed := ShowConfirmDialog("賺技能點 ⚔", timeStr, NewSequenceLoopLimit)
    isConfirming := false

    if (!confirmed) {
        StopGasAndClean()
        return
    }

    if WinExist(GameTitle) {
        WinActivate(GameTitle)
        if !WinWaitActive(GameTitle, , 3) {
            StopGasAndClean()
            return
        }
    }

    DrawDividers(NewSequenceLoopLimit)
    sequenceStartTime := A_TickCount
    UpdateUiRunningState(2)
    SetTimer(UpdateNewLoopProgress, 100)

    SleepAndCheck(ms) {
        global isNewSequenceRunning, GameTitle, MyGui
        loop Ceil(ms / 100) {
            if (!isNewSequenceRunning || (!WinActive(GameTitle) && !WinActive("ahk_id " MyGui.Hwnd))) {
                return false
            }
            Sleep(100)
        }
        return true
    }

    currentNewLoopItem := 0
    Loop NewSequenceLoopLimit {
        if (!isNewSequenceRunning) {
            break
        }
        currentNewLoopItem := A_Index
        newLoopStartTime := A_TickCount

        if (!WinActive(GameTitle) && !WinActive("ahk_id " MyGui.Hwnd)) {
            StopGasAndClean()
            break
        }

        ShowTip("1. 送出 Enter (250ms)")
        SendInput("{Enter Down}")
        Sleep(250)
        SendInput("{Enter Up}")
        if (!SleepAndCheck(500)) {
            break
        }

        ShowTip("2. 按住 W 前進 (" WHoldDuration "秒)")
        SendInput("{w Down}")
        wStartTime := A_TickCount
        wDurationMs := WHoldDuration * 1000
        while (isNewSequenceRunning && (A_TickCount - wStartTime < wDurationMs)) {
            if (!WinActive(GameTitle) && !WinActive("ahk_id " MyGui.Hwnd)) {
                break
            }
            Sleep(100)
        }
        ShowTip("釋放 W 鍵")
        ForceReleaseW_Hardware()
        SendInput("{w Up}")
        if (!isNewSequenceRunning) {
            break
        }
        if (!SleepAndCheck(1000)) {
            break
        }

        ShowTip("3. 按一下 X 鍵 (250ms)")
        SendInput("{x Down}")
        Sleep(250)
        SendInput("{x Up}")
        if (!SleepAndCheck(500)) {
            break
        }

        ShowTip("4. 送出 Enter (250ms)")
        SendInput("{Enter Down}")
        Sleep(250)
        SendInput("{Enter Up}")
        if (!SleepAndCheck(500)) {
            break
        }

        ShowTip("5. 等待十秒")
        if (!SleepAndCheck(10000)) {
            break
        }
    }

    ShowTip("")
    StopGasAndClean()
}

RunBuyCarSequence() {
    global isBuyCarRunning, GameTitle, MyGui, BuyCarLoopLimit, currentBuyCarLoopItem, buyCarStartTime, BuyCarTotalMs, GuiX, GuiY, GuiH, isConfirming
    global sequenceStartTime, sequenceTotalSec
    if (isBuyCarRunning) {
        return
    }
    isBuyCarRunning := true

    BuyCarTotalMs := 4250
    sequenceTotalSec := Ceil((BuyCarLoopLimit * BuyCarTotalMs) / 1000)
    timeStr := FormatTimeDuration(sequenceTotalSec)
    
    isConfirming := true
    confirmed := ShowConfirmDialog("買車行程 🚗", timeStr, BuyCarLoopLimit)
    isConfirming := false

    if (!confirmed) {
        StopGasAndClean()
        return
    }

    if WinExist(GameTitle) {
        WinActivate(GameTitle)
        if !WinWaitActive(GameTitle, , 3) {
            StopGasAndClean()
            return
        }
    }

    DrawDividers(BuyCarLoopLimit)
    sequenceStartTime := A_TickCount
    UpdateUiRunningState(1)
    SetTimer(UpdateBuyCarLoopProgress, 100)

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

    currentBuyCarLoopItem := 0
    Loop BuyCarLoopLimit {
        if (!isBuyCarRunning) {
            break
        }
        currentBuyCarLoopItem := A_Index
        buyCarStartTime := A_TickCount

        if (!WinActive(GameTitle) && !WinActive("ahk_id " MyGui.Hwnd)) {
            StopGasAndClean()
            break
        }

        ShowTip("1. 送出 Space (250ms)")
        SendInput("{Space Down}")
        Sleep(250)
        SendInput("{Space Up}")
        if (!SleepAndCheck(500)) {
            break
        }

        ShowTip("2. 送出 Down (250ms)")
        SendInput("{Down Down}")
        Sleep(250)
        SendInput("{Down Up}")
        if (!SleepAndCheck(500)) {
            break
        }

        ShowTip("3. 送出 Enter (1/3)")
        SendInput("{Enter Down}")
        Sleep(250)
        SendInput("{Enter Up}")
        if (!SleepAndCheck(500)) {
            break
        }

        ShowTip("4. 送出 Enter (2/3)")
        SendInput("{Enter Down}")
        Sleep(250)
        SendInput("{Enter Up}")
        if (!SleepAndCheck(500)) {
            break
        }

        ShowTip("5. 送出 Enter (3/3)")
        SendInput("{Enter Down}")
        Sleep(250)
        SendInput("{Enter Up}")
        if (!SleepAndCheck(1000)) {
            break
        }
    }
    ShowTip("")
    StopGasAndClean()
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

        while (isGasOn && (A_TickCount - startTime < randomHoldTime)) {
            if (!WinActive(GameTitle) && !WinActive("ahk_id " MyGui.Hwnd)) {
                StopGasAndClean()
                return
            }
            Sleep(100)
        }
        if (!isGasOn) {
            break
        }

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
                UpdateUiRunningState(5)
                SetTimer(InfiniteGasLoop, -10)
            } else {
                ResetUiToNormal()
            }
        }
    }
}

StopGasAndClean() {
    global MyGui, isGasOn, isSequenceRunning, isEnterSpamRunning, isNewSequenceRunning, isBuyCarRunning, ProgressText, ProgressBar, GuiX, GuiY, GuiH, currentStepText

    isGasOn := false
    isSequenceRunning := false
    isEnterSpamRunning := false
    isNewSequenceRunning := false
    isBuyCarRunning := false
    SetTimer(UpdateLoopProgress, 0)
    SetTimer(UpdateNewLoopProgress, 0)
    SetTimer(UpdateBuyCarLoopProgress, 0)

    if (ProgressText) {
        ProgressText.Value := ""
    }
    ProgressBar.Value := 0
    ShowTip("")
    ClearDividers()

    if WinExist("ahk_id " MyGui.Hwnd) {
        ResetUiToNormal()
    }
    ForceReleaseW_Hardware()
    Send("{x Up}{Space Up}{Down Up}{Enter Up}")
    SendInput("{x Up}{Space Up}{Down Up}{Enter Up}")
}

UpdateLoopProgress() {
    global isSequenceRunning, loopStartTime, TotalMs, ProgressBar, ProgressText, currentStepText, currentLoopItem, LoopCountLimit
    static lastPercent := -1
    
    if (!isSequenceRunning) {
        SetTimer(UpdateLoopProgress, 0)
        lastPercent := -1
        return
    }

    loopIndex := (currentLoopItem > 0) ? currentLoopItem : 1
    currentLoopTotalMs := TotalMs + ((loopIndex < LoopCountLimit) ? 1500 : 0)
    loopRatio := Min((A_TickCount - loopStartTime) / currentLoopTotalMs, 1.0)
    segmentSize := 100 / LoopCountLimit
    basePercent := (loopIndex - 1) * segmentSize
    percent := Integer(basePercent + (loopRatio * segmentSize))

    if (percent != lastPercent) {
        ProgressBar.Value := percent
        lastPercent := percent
        if (ProgressText)
            ProgressText.Redraw()
    }
    ShowTip(currentStepText)
}

UpdateNewLoopProgress() {
    global isNewSequenceRunning, newLoopStartTime, NewSequenceTotalMs, ProgressBar, ProgressText, currentStepText, currentNewLoopItem, NewSequenceLoopLimit
    static lastPercent := -1

    if (!isNewSequenceRunning) {
        SetTimer(UpdateNewLoopProgress, 0)
        lastPercent := -1
        return
    }

    loopIndex := (currentNewLoopItem > 0) ? currentNewLoopItem : 1
    loopRatio := Min((A_TickCount - newLoopStartTime) / NewSequenceTotalMs, 1.0)
    segmentSize := 100 / NewSequenceLoopLimit
    basePercent := (loopIndex - 1) * segmentSize
    percent := Integer(basePercent + (loopRatio * segmentSize))

    if (percent != lastPercent) {
        ProgressBar.Value := percent
        lastPercent := percent
        if (ProgressText)
            ProgressText.Redraw()
    }
    ShowTip(currentStepText)
}

UpdateBuyCarLoopProgress() {
    global isBuyCarRunning, buyCarStartTime, BuyCarTotalMs, ProgressBar, ProgressText, currentStepText, currentBuyCarLoopItem, BuyCarLoopLimit
    static lastPercent := -1

    if (!isBuyCarRunning) {
        SetTimer(UpdateBuyCarLoopProgress, 0)
        lastPercent := -1
        return
    }

    loopIndex := (currentBuyCarLoopItem > 0) ? currentBuyCarLoopItem : 1
    loopRatio := Min((A_TickCount - buyCarStartTime) / BuyCarTotalMs, 1.0)
    segmentSize := 100 / BuyCarLoopLimit
    basePercent := (loopIndex - 1) * segmentSize
    percent := Integer(basePercent + (loopRatio * segmentSize))

    if (percent != lastPercent) {
        ProgressBar.Value := percent
        lastPercent := percent
        if (ProgressText)
            ProgressText.Redraw()
    }
    ShowTip(currentStepText)
}

ShowTip(stepText) {
    global GuiX, GuiY, currentStepText, ProgressText, sequenceStartTime, sequenceTotalSec
    global isSequenceRunning, loopStartTime, TotalMs, currentLoopItem, LoopCountLimit
    global isNewSequenceRunning, newLoopStartTime, NewSequenceTotalMs, currentNewLoopItem, NewSequenceLoopLimit
    global isBuyCarRunning, buyCarStartTime, BuyCarTotalMs, currentBuyCarLoopItem, BuyCarLoopLimit

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

    currentStepText := stepText

    cur := 0, limit := 0, percent := 0
    if (isSequenceRunning) {
        cur := currentLoopItem, limit := LoopCountLimit
        loopIndex := (cur > 0) ? cur : 1
        currentLoopTotalMs := TotalMs + ((loopIndex < limit) ? 1500 : 0)
        loopRatio := Min((A_TickCount - loopStartTime) / currentLoopTotalMs, 1.0)
        percent := ((loopIndex - 1) / limit * 100) + (loopRatio * (100 / limit))
    } else if (isNewSequenceRunning) {
        cur := currentNewLoopItem, limit := NewSequenceLoopLimit
        loopIndex := (cur > 0) ? cur : 1
        loopRatio := Min((A_TickCount - newLoopStartTime) / NewSequenceTotalMs, 1.0)
        percent := ((loopIndex - 1) / limit * 100) + (loopRatio * (100 / limit))
    } else if (isBuyCarRunning) {
        cur := currentBuyCarLoopItem, limit := BuyCarLoopLimit
        loopIndex := (cur > 0) ? cur : 1
        loopRatio := Min((A_TickCount - buyCarStartTime) / BuyCarTotalMs, 1.0)
        percent := ((loopIndex - 1) / limit * 100) + (loopRatio * (100 / limit))
    } else {
        CoordMode("ToolTip", "Screen")
        ToolTip(stepText, GuiX + 155, GuiY + 5)
        return
    }

    percent := Integer(percent)

    elapsedSec := (A_TickCount - sequenceStartTime) / 1000
    remSec := Max(0, Ceil(sequenceTotalSec - elapsedSec))
    countdownStr := FormatTimeDuration(remSec)

    infoText := "[" cur "/" limit "]" countdownStr "⏱" percent "％" stepText
    
    if (ProgressText && infoText != lastInfoText) {
        ProgressText.Value := infoText
        lastInfoText := infoText
        ProgressText.Redraw()
    }
    ToolTip()
}

FormatTimeDuration(seconds) {
    hours := Format("{:02d}", Integer(seconds / 3600))
    mins := Format("{:02d}", Integer(Mod(seconds, 3600) / 60))
    secs := Format("{:02d}", Mod(seconds, 60))
    return hours ":" mins ":" secs
}

ForceReleaseW_Hardware() {
    Send("{w Up}")
    SendInput("{w Up}")
    DllCall("keybd_event", "int", 0x57, "int", 0, "int", 2, "ptr", 0)
    Sleep(20)
}

WM_LBUTTONDOWN(wParam, lParam, msg, hwnd) {
    global MyGui, GuiBtns, isGasOn, isSequenceRunning, isEnterSpamRunning, isNewSequenceRunning, isBuyCarRunning
    for btn in GuiBtns {
        if (hwnd == btn.Hwnd) {
            return
        }
    }
    if (hwnd == MyGui.Hwnd || DllCall("GetParent", "Ptr", hwnd) == MyGui.Hwnd) {
        if (isGasOn || isSequenceRunning || isEnterSpamRunning || isNewSequenceRunning || isBuyCarRunning) {
            StopGasAndClean()
        }
    }
}

GetAnyJoyState(btnNum) {
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