; =================================================================
; Forza Horizon 6 (FH6) 自動化輔助腳本
; 版本: 1.3.0
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

;OnExit( (*) => (
;    ForceReleaseW_Hardware(),
;    Send("{a up}{s up}{d up}{x up}{Space up}{Down up}{Shift up}{Ctrl up}{Alt up}{Enter up}{Esc up}")
;))

; =================================================================
; [全域自動化參數設定區]
; =================================================================
global LoadVehicleDelay := 11   ; 等待車輛載入時間（秒）
global LongPressDelay := 3.0     ; 手把長按偵測時間（秒）
global WHoldDuration := 36       ; 賺技能點時按住油門前進的時間（秒）
GroupAdd("GameGroup","ahk_exe ForzaHorizon6.exe") ; 遊戲視窗標題名稱
GroupAdd("GameGroup","ahk_exe notepad.exe") ; 測試用
global GameTitle := "ahk_group GameGroup" ; 將視窗目標指向群組
global ConfirmState := { result: false, isWaiting: false }

; [行程循環次數設定]
global LoopCountLimit := 25       ; 技能行程循環次數
global SkillPoints := 975         ; 技能行程技能點數限制 (975 / 39 = 25 次)
global NewSequenceLoopLimit := 99 ; 賺技能點行程循環次數
global BuyCarLoopLimit := 26      ; 買車行程循環次數
global RivalLoopLimit := 10       ; 勁敵刷錢行程循環次數
global RivalThrottleSec := 420    ; 勁敵刷錢按住油門時間（秒）
global RivalLoadSec := 10          ; 勁敵刷錢等待載入時間（秒）
global RivalTransitionSec := 30   ; 勁敵刷錢等待過場時間（秒）

; [點技能選廠牌位置]
global BrandDownCount := 10
global BrandRightCount := 0

; [觸控按鈕位置與進度條設定]
global GuiX := 0
global GuiY := 0
global GuiH := 30
global GuiOpacity := 180
global ProgressBarWidth := 610
global IsSimplifyDividers := false ; 簡化進度條格數（簡化後每十次畫一格避免太密集）

; [動態分格 UI 陣列]
global DividerCtrls := []
; =================================================================

global isGasOn := false
global isSequenceRunning := false
global isEnterSpamRunning := false
global isNewSequenceRunning := false
global isBuyCarRunning := false
global isRivalRunning := false
global currentLoopItem := 0
global currentNewLoopItem := 0
global currentBuyCarLoopItem := 0
global currentRivalLoopItem := 0
global isConfirming := false
global currentStepText := ""

global xTriggeredThisPress := false
global yTriggeredThisPress := false
global lTriggeredThisPress := false

; --- 【倒數計時器全域變數】 ---
global sequenceStartTime := 0
global sequenceTotalSec := 0
global CurrentConfirmUpdateFn := ""

; --- 【UI 介面設定區】 ---
global MyGui := Gui("+AlwaysOnTop -Caption -Border +ToolWindow +Owner")
MyGui.BackColor := "010101"

global GuiBtns := []
global btnConfigs := [
    { name: "esc",       symbol: "␛", x: 0,   fn: (*) => (WinActive(GameTitle) ? Send("{Esc}") : "") },
    { name: "buyCar",    symbol: "🚗", x: 40,  fn: (*) => (isBuyCarRunning ? StopGasAndClean() : (WinActive(GameTitle) ? ToggleBuyCarSequence() : "")) },
    { name: "newSeq",    symbol: "⚔", x: 80,  fn: (*) => (isNewSequenceRunning ? StopGasAndClean() : (WinActive(GameTitle) ? ToggleNewSequence() : "")) },
    { name: "seq",       symbol: "⚡", x: 120, fn: (*) => (isSequenceRunning ? StopGasAndClean() : (WinActive(GameTitle) ? ToggleLButtonSequence() : "")) },
    { name: "enterSpam", symbol: "🎰", x: 160, fn: (*) => (isEnterSpamRunning ? StopGasAndClean() : (WinActive(GameTitle) ? ToggleEnterSpam() : "")) },
    { name: "gas",       symbol: "🏆", x: 200, fn: (*) => (isGasOn ? StopGasAndClean() : (WinActive(GameTitle) ? ToggleGas() : "")) },
    { name: "rival",     symbol: "🎖", x: 240, fn: (*) => (isRivalRunning ? StopGasAndClean() : (WinActive(GameTitle) ? ToggleRivalSequence() : "")) },
    { name: "exit",      symbol: "⏏", x: 280, fn: (*) => (StopGasAndClean(), MyGui.Destroy(), ExitApp()) }
]

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
UpdateUiRunningState(btnName) {
    global GuiBtns, MyGui, GuiX, GuiY, GuiH, GuiOpacity, ProgressBar, ProgressText
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
    global GuiBtns, MyGui, GuiX, GuiY, GuiH, GuiOpacity, ProgressBar, ProgressText, GameTitle, btnConfigs
    ProgressBar.Visible := false
    ProgressText.Visible := false
    for idx, btn in GuiBtns {
        btn.Move(btnConfigs[idx].x, -2)
        btn.Visible := true
    }
    
    currentActive := WinActive(GameTitle) || WinActive("ahk_id " MyGui.Hwnd)
    if (currentActive) {
        MyGui.Show("X" GuiX " Y" GuiY " W" . (btnConfigs.Length * 40) . " h" . GuiH . " NoActivate")
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
ShowConfirmDialog(funcName, timeStr, limitVarRef := unset, recalcFn := "", extraParams := "", limitName := "") {
    global GuiX, GuiY, GuiOpacity, GameTitle, ConfirmState, IsSimplifyDividers, CurrentConfirmUpdateFn
    CurrentConfirmUpdateFn := UpdateTimeDisplay

    ConfirmGui := Gui("+AlwaysOnTop -Caption -Border +ToolWindow +Owner")
    ConfirmGui.BackColor := "010101"

    hasLimitSlider := IsSet(limitVarRef) && Type(limitVarRef) == "VarRef"
    hasExtraParams := IsObject(extraParams) && extraParams.Length > 0

    local sliderCtrl := "", chkSimplify := "", timeTextCtrl := ""
    local labelTextPart1 := "", labelTextPart2 := "", labelTextPart3 := ""
    local extraLabelCtrls := []  ; 儲存物件 { part1: ctrl, valPart: ctrl, part2: ctrl }
    local extraSliderCtrls := []
    local isSkillSeq := (limitName == "LoopCountLimit")
    local gridCtrls := []

    UpdateTimeDisplay(triggerCtrl := "", *) {
        if (isSkillSeq && triggerCtrl) {
            if (triggerCtrl.Hwnd == sliderCtrl.Hwnd) {
                extraSliderCtrls[1].Value := Min(999, Max(39, sliderCtrl.Value * 39))
            } else if (triggerCtrl.Hwnd == extraSliderCtrls[1].Hwnd) {
                sliderCtrl.Value := Min(25, Max(1, Floor(extraSliderCtrls[1].Value / 39)))
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
                }
                if (oldValStr != valStr) {
                    ; 僅更新變動的數字本身
                    extraLabelCtrls[idx].valPart.Text := valStr
                    
                    ; 只有當數字的位數（字數長度）改變時，才調整寬度與移動後方的單位標籤
                    if (StrLen(oldValStr) != StrLen(valStr)) {
                        extraLabelCtrls[idx].valPart.Move(,, StrLen(valStr) * 16 + 4)
                        extraLabelCtrls[idx].part1.GetPos(&p1X, &p1Y, &p1W)
                        extraLabelCtrls[idx].valPart.Move(p1X + p1W)
                        
                        extraLabelCtrls[idx].valPart.GetPos(&pvX, &pvY, &pvW)
                        extraLabelCtrls[idx].part2.Move(pvX + pvW)
                    }
                }
            }
        }

        if (recalcFn) {
            newTimeStr := recalcFn(vals*)
            if (newTimeStr != "" && timeTextCtrl && timeTextCtrl.Text != newTimeStr) {
                timeTextCtrl.Text := newTimeStr
            }
        }
        
        if (hasLimitSlider && labelTextPart2) {
            oldValStr := labelTextPart2.Text
            if (oldValStr != String(val)) {
                ; 僅更新變動的數字本身
                labelTextPart2.Text := val
                
                needReposition := (StrLen(oldValStr) != StrLen(String(val)))
                
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
                
                ; 只有在位數改變或說明文字改變時，才重新排列位置
                if (needReposition) {
                    labelTextPart2.Move(,, StrLen(val) * 16 + 4)
                    labelTextPart1.GetPos(&l1X, &l1Y, &l1W)
                    labelTextPart2.Move(l1X + l1W)
                    
                    labelTextPart2.GetPos(&l2X, &l2Y, &l2W)
                    labelTextPart3.Move(l2X + l2W)
                }
            }
        }

        if (isSkillSeq && gridCtrls.Length > 0) {
            ; 找到對應的 BrandDownCount 與 BrandRightCount 滑桿值
            ; 第一個 extraParam 是 SkillPoints，第二個是 BrandDownCount，第三個是 BrandRightCount
            currentDown := extraSliderCtrls[2].Value
            currentRight := extraSliderCtrls[3].Value

            ; 使用 static 變數記錄前一次亮起的格子坐標，避免每次拖動滑桿都重新繪製所有 48 個格子
            static prevDown := -1
            static prevRight := -1

            if (currentDown != prevDown || currentRight != prevRight) {
                Loop 4 {
                    colIdx := A_Index - 1
                    Loop 12 {
                        rowIdx := A_Index - 1
                        ctrl := gridCtrls[colIdx + 1][rowIdx + 1]
                        
                        isTarget := (colIdx == currentRight && rowIdx == currentDown)
                        wasTarget := (colIdx == prevRight && rowIdx == prevDown)
                        
                        ; 只針對「即將變亮」或「即將變暗」的格子進行重繪，其他格子維持原樣不重繪以防閃爍
                        if (isTarget) {
                            ctrl.Opt("+BackgroundYellow cBlack")
                            ctrl.Redraw()
                        } else if (wasTarget) {
                            ctrl.Opt("+Background334455 cWhite")
                            ctrl.Redraw()
                        }
                    }
                }
                prevDown := currentDown
                prevRight := currentRight
            }
        }
    }

    OnGridClick(ctrl, *) {
        ; 搜尋被點選的格子在 gridCtrls 中的座標
        Loop 4 {
            cIdx := A_Index - 1
            Loop 12 {
                rIdx := A_Index - 1
                if (gridCtrls[cIdx + 1][rIdx + 1].Hwnd == ctrl.Hwnd) {
                    ; 更新對應滑桿的值
                    ; extraSliderCtrls 中：第一個(1)是技能點數，第二個(2)是向下次數，第三個(3)是向右次數
                    extraSliderCtrls[2].Value := rIdx ; BrandDownCount
                    extraSliderCtrls[3].Value := cIdx ; BrandRightCount
                    ; 觸發重繪與計算
                    UpdateTimeDisplay()
                    return
                }
            }
        }
    }

    ; 計算佈局位置與高度
    totalSliders := (hasLimitSlider ? 1 : 0) + (hasExtraParams ? extraParams.Length : 0)
    hasCheckbox := hasLimitSlider

    ; 視窗高度動態計算
    guiH := 180
    if (totalSliders > 0) {
        guiH := 100 + totalSliders * 80 + (hasCheckbox ? 40 : 0)
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

            ; 判斷極限值變數的名稱，動態決定 Range
            sliderRange := "1-100"
            if (limitName == "LoopCountLimit") {
                sliderRange := "1-25"
            } else if (limitName == "NewSequenceLoopLimit") {
                sliderRange := "1-120"
            } else if (limitName == "BuyCarLoopLimit") {
                sliderRange := "1-100"
            } else if (limitName == "RivalLoopLimit") {
                sliderRange := "1-100"
            }

            ConfirmGui.SetFont("s14 Bold cGray", "Microsoft JhengHei")
            labelTextPart1 := ConfirmGui.Add("Text", "x20 y" currY " +BackgroundTrans", "循環 ")
            
            ConfirmGui.SetFont("s20 Bold cYellow", "Microsoft JhengHei")
            labelTextPart2 := ConfirmGui.Add("Text", "x+0 y" (currY - 5) " +BackgroundTrans", initialLimit)
            
            ConfirmGui.SetFont("s14 Bold cGray", "Microsoft JhengHei")
            labelTextPart3Text := (IsSimplifyDividers && initialLimit >= 20) ? "次 / 簡化為" Ceil(initialLimit / 10) "格：" : "次："
            labelTextPart3 := ConfirmGui.Add("Text", "x+0 y" currY " w350 +BackgroundTrans", labelTextPart3Text)

            ConfirmGui.SetFont("s10 cWhite")
            sliderCtrl := ConfirmGui.Add("Slider", "x20 y" (currY + 30) " w420 h40 Range" sliderRange " Thick30 Tooltip AltSubmit", initialLimit)
            sliderCtrl.OnEvent("Change", UpdateTimeDisplay)
            
            currY += 80
        }

        if (hasExtraParams) {
            for idx, item in extraParams {
                initialVal := %(item.varRef)%

                ; 判斷原名稱包含的單位並改寫成「名稱 數值單位：」格式
                unitStr :=  "次" ; 預設單位為「次」
                if (InStr(item.name, "分:秒") || InStr(item.name, "分：秒")) {
                    unitStr := ""
                } else if (InStr(item.name, "秒")) {
                    unitStr := "秒"
                } else if (InStr(item.name, "點數")) {
                    unitStr := "點"
                }
                
                ; 清理名稱中的括號文字以求整潔
                cleanName := RegExReplace(item.name, "\s*\([^)]+\)")
                
                ; 特別修飾廠牌次數的名稱使其更自然流暢
                if (InStr(cleanName, "向下次數")) {
                    cleanName := "點技能選廠牌向下"
                } else if (InStr(cleanName, "向右次數")) {
                    cleanName := "點技能選廠牌向右"
                }

                valStr := String(initialVal)
                if (InStr(item.name, "分:秒") || InStr(item.name, "分：秒")) {
                    mins := Floor(initialVal / 60)
                    secs := Mod(initialVal, 60)
                    valStr := mins "分" Format("{:02d}", secs) "秒"
                }
                ConfirmGui.SetFont("s14 Bold cGray", "Microsoft JhengHei")
                lblCtrlPart1 := ConfirmGui.Add("Text", "x20 y" currY " +BackgroundTrans",cleanName " ")
                
                ConfirmGui.SetFont("s20 Bold cYellow", "Microsoft JhengHei")
                lblCtrlVal := ConfirmGui.Add("Text", "x+0 y" (currY - 5) " +BackgroundTrans",valStr)
                
                ConfirmGui.SetFont("s14 Bold cGray", "Microsoft JhengHei")
                lblCtrlPart2 := ConfirmGui.Add("Text", "x+0 y" currY " w350 +BackgroundTrans",unitStr "：")

                extraLabelCtrls.Push({ part1: lblCtrlPart1, valPart: lblCtrlVal, part2: lblCtrlPart2 })

                ConfirmGui.SetFont("s10 cWhite")
                sldCtrl := ConfirmGui.Add("Slider", "x20 y" (currY + 30) " w420 h40 Range" item.range " Thick30 Tooltip AltSubmit",initialVal)
                sldCtrl.OnEvent("Change", UpdateTimeDisplay)
                extraSliderCtrls.Push(sldCtrl)

                currY += 80
            }
        }

        if (isSkillSeq) {
            guiH += 260
        }

        if (hasCheckbox) {
            ConfirmGui.SetFont("s12 cWhite", "Microsoft JhengHei")
            chkSimplify := ConfirmGui.Add("Checkbox", "x20 y" currY " w420 Checked" (IsSimplifyDividers ? "1" : "0"), " 簡化進度條格數（簡化後每十次畫一格避免太密集）")
            chkSimplify.OnEvent("Click", UpdateTimeDisplay)
            currY += 40
        }

        if (isSkillSeq) {
            ConfirmGui.SetFont("s11 Bold cWhite", "Microsoft JhengHei")
            ConfirmGui.Add("Text", "x20 y" currY " w420 +BackgroundTrans", "廠牌位置預覽（可以直接點格子設定）：")
            currY += 25

            ; 建立 4(寬/欄/向右) x 12(高/列/向下) 的格網，標示文字為 1-1 到 4-12
            Loop 4 {
                colIdx := A_Index - 1
                gridCol := []
                Loop 12 {
                    rowIdx := A_Index - 1
                    
                    ; 橫向 4 欄 (0 到 3)，分配在 420 像素寬度
                    gridX := 20 + (colIdx * 105)
                    ; 縱向 12 列 (0 到 11)
                    gridY := currY + (rowIdx * 18)
                    
                    isTarget := (colIdx == BrandRightCount && rowIdx == BrandDownCount)
                    colorOpt := isTarget ? "+BackgroundYellow cBlack" : "+Background334455 cWhite"
                    
                    ; 格式化文字標示，如 1-1、4-12
                    gridText := (colIdx + 1) "-" (rowIdx + 1)
                    
                    ConfirmGui.SetFont("s8 Bold", "Microsoft JhengHei")
                    ctrl := ConfirmGui.Add("Text", "x" gridX " y" gridY " w95 h15 Center +0x200 " colorOpt, gridText)
                    ctrl.OnEvent("Click", OnGridClick)
                    gridCol.Push(ctrl)
                }
                gridCtrls.Push(gridCol)
            }
        }

        ; 按鈕尺寸與擺放
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

    ConfirmGui.Show("X" GuiX " Y" GuiY " W580 H" guiH " NoActivate")
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
    
    if (ConfirmState.result) {
        if (hasLimitSlider) {
            %limitVarRef% := sliderCtrl.Value
        }
        if (hasExtraParams) {
            for idx, item in extraParams {
                %(item.varRef)% := extraSliderCtrls[idx].Value
            }
        }
        if (chkSimplify) {
            IsSimplifyDividers := chkSimplify.Value
        }
    }
    
    ConfirmGui.Destroy()
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
        Sleep(60)
        Send("{Enter Up}")
        Sleep(60)
    }
}

RunLButtonSequence() {
    global MyGui, ProgressText, isSequenceRunning, BrandDownCount, BrandRightCount, LoopCountLimit, currentLoopItem, GuiX, GuiY, GuiH, loopStartTime, TotalMs, isConfirming, SkillPoints
    global sequenceStartTime, sequenceTotalSec
    if (isSequenceRunning) {
        return
    }
    isSequenceRunning := true

    BuildActionsList(brandDown, brandRight) {
        local actionsList := [
            ["Up", 450], ["Up", 450], ["Up", 450], ["Down", 450], ["Enter", 600], ["Down", 450], ["Enter", 600],
            ["Backspace", 1000]
        ]
        if (brandDown > 0) {
            Loop brandDown {
                actionsList.Push(["Down", 200])
            }
            actionsList.Push(["_Sleep", 200])
        }
        if (brandRight > 0) {
            Loop brandRight {
                actionsList.Push(["Right", 200])
            }
            actionsList.Push(["_Sleep", 200])
        }
        actionsList.Push(
            ["Enter", 600], ;選好廠牌
            ["Enter", 600], ["Down", 200, 5], ["Enter", 600], ;從車庫移除車輛
            ["Down", 500], ["Enter", 600], ;確認移除
            ["_Sleep", 1000], ["Right", 450], ["Enter", 600], ["Down", 450], ["Enter", 600], ;乘駕車輛
            ["_Sleep", 3000], ;等待載入
            ["Esc", 1200], ["Esc", 1200], ["Right", 600], ;退回到車輛選單
            ["Enter", 600], ["Down", 200, 7], ;升級與調教
            ["_Sleep", 400], ["Enter", 1500], ["Enter", 1200], ["Up", 450],
            ["Enter", 1200], ["Up", 450], ["Enter", 1200], ["Up", 450],
            ["Enter", 1200], ["Right", 450], ["Enter", 1200], ["Right", 450],
            ["Enter", 1200], ["Esc", 1200], ["Esc", 1200], ["Left", 450]
        )
        return actionsList
    }

    CalculateTotalMs(brandDown, brandRight) {
        tempActions := BuildActionsList(brandDown, brandRight)
        totalMs := 0
        for item in tempActions {
            if (item[1] == "_Sleep") {
                totalMs += item[2]
            } else {
                repeat := (item.Length >= 3) ? item[3] : 1
                keyTime := (item[1] == "Backspace") ? 200 : 100
                totalMs += (keyTime + item[2]) * repeat
            }
        }
        return totalMs
    }
    
    recalcFn := (limit, skillPts, brandDown, brandRight) => (
        ms := CalculateTotalMs(brandDown, brandRight),
        FormatTimeDuration(Ceil((limit * ms + Max(0, limit - 1) * 1500) / 1000))
    )
    
    timeStr := recalcFn(LoopCountLimit, SkillPoints, BrandDownCount, BrandRightCount)
    
    extraParams := [
        { varRef: &SkillPoints, name: "技能點數", range: "39-999" },
        { varRef: &BrandDownCount, name: "選廠牌向下次數", range: "0-11" },
        { varRef: &BrandRightCount, name: "選廠牌向右次數", range: "0-3" }
    ]
    
    isConfirming := true
    confirmed := ShowConfirmDialog("技能行程 ⚡", timeStr, &LoopCountLimit, recalcFn, extraParams, "LoopCountLimit")
    isConfirming := false
 
    if (!confirmed) {
        StopGasAndClean()
        return
    }

    ; 計算實際的循環次數
    LoopCountLimit := Floor(SkillPoints / 39)
    if (LoopCountLimit < 1) {
        LoopCountLimit := 1
    }

    ; 動態建立 actions 動作清單
    actions := BuildActionsList(BrandDownCount, BrandRightCount)

    TotalMs := CalculateTotalMs(BrandDownCount, BrandRightCount)
    sequenceTotalSec := Ceil((LoopCountLimit * TotalMs + (LoopCountLimit - 1) * 1500) / 1000)


    if WinExist(GameTitle) {
        WinActivate(GameTitle)
        if !WinWaitActive(GameTitle, , 3) {
            StopGasAndClean()
            return
        }
    }

    DrawDividers(LoopCountLimit)
    sequenceStartTime := A_TickCount
    UpdateUiRunningState("seq")
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
            
            isRunning := (isSequenceRunning || isNewSequenceRunning || isBuyCarRunning || isEnterSpamRunning || isGasOn || isRivalRunning)
            if (isRunning) {
                runName := isBuyCarRunning ? "buyCar" : (isNewSequenceRunning ? "newSeq" : (isEnterSpamRunning ? "enterSpam" : (isSequenceRunning ? "seq" : (isGasOn ? "gas" : "rival"))))
                UpdateUiRunningState(runName)
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

RunNewSequence() {
    global isNewSequenceRunning, GameTitle, MyGui, WHoldDuration, NewSequenceLoopLimit, currentNewLoopItem, newLoopStartTime, NewSequenceTotalMs, GuiX, GuiY, GuiH, isConfirming
    global sequenceStartTime, sequenceTotalSec
    if (isNewSequenceRunning) {
        return
    }
    isNewSequenceRunning := true

    recalcFn := (limit, wHold) => (
        dynamicTotalMs := (wHold * 1000) + 13250,
        FormatTimeDuration(Ceil((limit * dynamicTotalMs) / 1000))
    )
    timeStr := recalcFn(NewSequenceLoopLimit, WHoldDuration)
    
    extraParams := [
        { varRef: &WHoldDuration, name: "按住油門前進(秒)", range: "5-60" }
    ]

    isConfirming := true
    confirmed := ShowConfirmDialog("賺技能點 ⚔", timeStr, &NewSequenceLoopLimit, recalcFn, extraParams, "NewSequenceLoopLimit")
    isConfirming := false

    if (!confirmed) {
        StopGasAndClean()
        return
    }

    NewSequenceTotalMs := (WHoldDuration * 1000) + 13250
    sequenceTotalSec := Ceil((NewSequenceLoopLimit * NewSequenceTotalMs) / 1000)

    if WinExist(GameTitle) {
        WinActivate(GameTitle)
        if !WinWaitActive(GameTitle, , 3) {
            StopGasAndClean()
            return
        }
    }

    DrawDividers(NewSequenceLoopLimit)
    sequenceStartTime := A_TickCount
    UpdateUiRunningState("newSeq")
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

        ShowTip("5. 等待8秒")
        if (!SleepAndCheck(8000)) {
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
    recalcFn := (limit) => FormatTimeDuration(Ceil((limit * BuyCarTotalMs) / 1000))
    timeStr := recalcFn(BuyCarLoopLimit)
    
    isConfirming := true
    confirmed := ShowConfirmDialog("買車行程 🚗", timeStr, &BuyCarLoopLimit, recalcFn, , "BuyCarLoopLimit")
    isConfirming := false

    if (!confirmed) {
        StopGasAndClean()
        return
    }

    sequenceTotalSec := Ceil((BuyCarLoopLimit * BuyCarTotalMs) / 1000)

    if WinExist(GameTitle) {
        WinActivate(GameTitle)
        if !WinWaitActive(GameTitle, , 3) {
            StopGasAndClean()
            return
        }
    }

    DrawDividers(BuyCarLoopLimit)
    sequenceStartTime := A_TickCount
    UpdateUiRunningState("buyCar")
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
                UpdateUiRunningState("gas")
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
    isRivalRunning := false
    SetTimer(UpdateLoopProgress, 0)
    SetTimer(UpdateNewLoopProgress, 0)
    SetTimer(UpdateBuyCarLoopProgress, 0)
    SetTimer(UpdateRivalLoopProgress, 0)

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
    } else if (isRivalRunning) {
        cur := currentRivalLoopItem, limit := RivalLoopLimit
        loopIndex := (cur > 0) ? cur : 1
        loopRatio := Min((A_TickCount - rivalLoopStartTime) / RivalTotalMs, 1.0)
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

ToggleRivalSequence() {
    global isGasOn, isSequenceRunning, isEnterSpamRunning, isNewSequenceRunning, isBuyCarRunning, isRivalRunning, isConfirming
    if (isGasOn || isSequenceRunning || isEnterSpamRunning || isNewSequenceRunning || isBuyCarRunning || isRivalRunning || isConfirming) {
        return
    }
    SetTimer(RunRivalSequence, -10)
}

RunRivalSequence() {
    global isRivalRunning, GameTitle, MyGui, RivalThrottleSec, RivalLoopLimit, currentRivalLoopItem, rivalLoopStartTime, RivalTotalMs, GuiX, GuiY, GuiH, isConfirming, RivalLoadSec, RivalTransitionSec
    global sequenceStartTime, sequenceTotalSec
    if (isRivalRunning) {
        return
    }
    isRivalRunning := true

    recalcFn := (limit, throttleSec, loadSec, transitionSec) => (
        dynamicTotalMs := (throttleSec * 1000) + (loadSec * 3 * 1000) + (transitionSec * 2 * 1000) + 39250,
        FormatTimeDuration(Ceil((limit * dynamicTotalMs) / 1000))
    )
    timeStr := recalcFn(RivalLoopLimit, RivalThrottleSec, RivalLoadSec, RivalTransitionSec)
    
    extraParams := [
        { varRef: &RivalThrottleSec, name: "油門時間(分:秒)", range: "10-1800" },
        { varRef: &RivalLoadSec, name: "等待載入(秒)", range: "1-30" },
        { varRef: &RivalTransitionSec, name: "等待過場(秒)", range: "10-120" }
    ]

    isConfirming := true
    confirmed := ShowConfirmDialog("勁敵刷錢 🎖", timeStr, &RivalLoopLimit, recalcFn, extraParams, "RivalLoopLimit")
    isConfirming := false

    if (!confirmed) {
        StopGasAndClean()
        return
    }

    RivalTotalMs := (RivalThrottleSec * 1000) + (RivalLoadSec * 3 * 1000) + (RivalTransitionSec * 2 * 1000) + 39250
    sequenceTotalSec := Ceil((RivalLoopLimit * RivalTotalMs) / 1000)

    if WinExist(GameTitle) {
        WinActivate(GameTitle)
        if !WinWaitActive(GameTitle, , 3) {
            StopGasAndClean()
            return
        }
    }

    DrawDividers(RivalLoopLimit)
    sequenceStartTime := A_TickCount
    UpdateUiRunningState("rival")
    SetTimer(UpdateRivalLoopProgress, 100)

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
            timeDisplay := ""
            if (remainingSec >= 60) {
                mins := Floor(remainingSec / 60)
                secs := Mod(remainingSec, 60)
                timeDisplay := mins "分" Format("{:02d}", secs) "秒"
            } else {
                timeDisplay := remainingSec "秒"
            }
            ShowTip(prefix " (倒數 " timeDisplay ")")
            Sleep(100)
        }
        return isRivalRunning
    }

    SendKey(key, holdMs:=250, sleepMs:=500) {
        global isRivalRunning, GameTitle, MyGui
        if (!isRivalRunning || (!WinActive(GameTitle) && !WinActive("ahk_id " MyGui.Hwnd))) {
            return false
        }
        SendInput("{" key " Down}")
        if (!SleepAndCheck(holdMs)) {
            SendInput("{" key " Up}")
            return false
        }
        SendInput("{" key " Up}")
        return SleepAndCheck(sleepMs)
    }

    currentRivalLoopItem := 0
    Loop RivalLoopLimit {
        if (!isRivalRunning) {
            break
        }
        currentRivalLoopItem := A_Index
        rivalLoopStartTime := A_TickCount

        if (!WinActive(GameTitle) && !WinActive("ahk_id " MyGui.Hwnd)) {
            StopGasAndClean()
            break
        }

        ShowTip("1. 送出 Esc")
        if (!SendKey("Esc")) {
            break
        }

        ShowTip("2. 送出 PgDn (1/3)")
        if (!SendKey("PgDn")) {
            break
        }
        ShowTip("3. 送出 PgDn (2/3)")
        if (!SendKey("PgDn")) {
            break
        }
        ShowTip("4. 送出 PgDn (3/3)")
        if (!SendKey("PgDn")) {
            break
        }

        ShowTip("5. 送出 Down")
        if (!SendKey("Down")) {
            break
        }

        ShowTip("6. 送出 Enter (1/3)")
        if (!SendKey("Enter", 250, 1000)) {
            break
        }
        ShowTip("7. 送出 Enter (2/3)")
        if (!SendKey("Enter", 250, 1000)) {
            break
        }
        ShowTip("8. 送出 Enter (3/3)")
        if (!SendKey("Enter", 250, 1000)) {
            break
        }

        ShowTip("9. 送出 Left (1/2)")
        if (!SendKey("Left")) {
            break
        }
        ShowTip("10. 送出 Left (2/2)")
        if (!SendKey("Left")) {
            break
        }

        ShowTip("11. 送出 Enter")
        if (!SendKey("Enter")) {
            break
        }

        ShowTip("12. 送出 Left")
        if (!SendKey("Left")) {
            break
        }

        if (!CountdownSleep(RivalLoadSec * 1000, "等待 Y 按鍵")) {
            break
        }

        ShowTip("13. 送出 Y")
        if (!SendKey("y")) {
            break
        }

        if (!CountdownSleep(RivalLoadSec * 1000, "14. 等待載入")) {
            break
        }

        ShowTip("15. 送出 Enter")
        if (!SendKey("Enter")) {
            break
        }

        if (!CountdownSleep(RivalLoadSec * 1000, "16. 等待載入")) {
            break
        }

        ShowTip("17. 送出 Enter")
        if (!SendKey("Enter")) {
            break
        }

        ShowTip("18. 送出 Y")
        if (!SendKey("y")) {
            break
        }

        ShowTip("19. 送出 Enter")
        if (!SendKey("Enter")) {
            break
        }

        ShowTip("20. 送出 Esc")
        if (!SendKey("Esc")) {
            break
        }

        ShowTip("21. 送出 Enter")
        if (!SendKey("Enter")) {
            break
        }

        if (!CountdownSleep(RivalTransitionSec * 1000, "22. 等待過場")) {
            break
        }

        ShowTip("23. 送出 Enter")
        if (!SendKey("Enter")) {
            break
        }

        SendInput("{w Down}")
        wSuccess := CountdownSleep(RivalThrottleSec * 1000, "24. 按住 W 設定秒數")
        ShowTip("釋放 W 鍵")
        ForceReleaseW_Hardware()
        SendInput("{w Up}")
        if (!wSuccess) {
            break
        }
        if (!SleepAndCheck(500)) {
            break
        }

        ShowTip("25. 送出 Esc")
        if (!SendKey("Esc")) {
            break
        }

        ShowTip("26. 送出 Right")
        if (!SendKey("Right")) {
            break
        }

        ShowTip("27. 送出 Enter (1/2)")
        if (!SendKey("Enter")) {
            break
        }
        ShowTip("28. 送出 Enter (2/2)")
        if (!SendKey("Enter")) {
            break
        }

        if (!CountdownSleep(RivalTransitionSec * 1000, "29. 等待過場")) {
            break
        }

        ShowTip("30. 送出 Esc")
        if (!SendKey("Esc")) {
            break
        }

        randomWaitSec := Random(10, 30)
        if (!CountdownSleep(randomWaitSec * 1000, "31. 等待 " randomWaitSec " 秒")) {
            break
        }
    }

    ShowTip("")
    StopGasAndClean()
}

UpdateRivalLoopProgress() {
    global isRivalRunning, rivalLoopStartTime, RivalTotalMs, ProgressBar, ProgressText, currentStepText, currentRivalLoopItem, RivalLoopLimit
    static lastPercent := -1

    if (!isRivalRunning) {
        SetTimer(UpdateRivalLoopProgress, 0)
        lastPercent := -1
        return
    }

    loopIndex := (currentRivalLoopItem > 0) ? currentRivalLoopItem : 1
    loopRatio := Min((A_TickCount - rivalLoopStartTime) / RivalTotalMs, 1.0)
    segmentSize := 100 / RivalLoopLimit
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
    global MyGui, GuiBtns, isGasOn, isSequenceRunning, isEnterSpamRunning, isNewSequenceRunning, isBuyCarRunning, CurrentConfirmUpdateFn, isRivalRunning
    
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
                        ; 點擊在控制點左側 -> 減少數值
                        distPx := tLeft - relativeX
                        diffVal := (distPx / channelWidth) * (maxVal - minVal)
                        jump := Max(1, Round(diffVal * 0.3))
                        newVal := Max(minVal, currVal - jump)
                    } else {
                        ; 點擊在控制點右側 -> 增加數值
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
    if (hwnd == MyGui.Hwnd || DllCall("GetParent", "Ptr", hwnd) == MyGui.Hwnd) {
        if (isGasOn || isSequenceRunning || isEnterSpamRunning || isNewSequenceRunning || isBuyCarRunning || isRivalRunning) {
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