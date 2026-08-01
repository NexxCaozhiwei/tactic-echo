from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "!TacticEcho"


def read(rel: str) -> str:
    return (ADDON / rel).read_text(encoding="utf-8")


def test_tactical_board_defers_container_alpha_and_scale_in_combat() -> None:
    board = read("UI/TacticalBoard.lua")
    assert "local function applyContainerPresentation(frame, alpha, scale)" in board
    assert "if inCombatLockdown() then" in board
    assert "frame.tacticEchoCombatPresentationPending = { alpha = alpha, scale = scale }" in board
    assert "applyContainerPresentation(panel, alpha, scale)" in board
    assert "applyContainerPresentation(defenseFrame, defenseAlpha, defenseScale)" in board
    assert "applyContainerPresentation(defenseFrame, 1, 1)" in board
    assert "panel:SetScale(clamp(scale" not in board
    assert "defenseFrame:SetScale(clamp(defenseScale" not in board


def test_tactical_board_defers_container_visibility_in_combat() -> None:
    board = read("UI/TacticalBoard.lua")
    assert "local function applyFrameShown(frame, shown)" in board
    assert "frame.tacticEchoCombatShownPending = shown" in board
    assert "applyFrameShown(defenseFrame, false)" in board
    assert "applyFrameShown(panel, true)" in board
    assert "applyFrameShown(panel, false); applyFrameShown(defenseFrame, false); return" in board
    assert "defenseFrame:SetShown(hasDefense)" not in board
    assert "panel:Show()" not in board
    assert "panel:Hide()" not in board


def test_tactical_layout_defers_layout_mutations_in_combat() -> None:
    layout = read("UI/TacticalHudLayout.lua")
    assert "local function inCombatLockdown()" in layout
    assert "if inCombatLockdown() then" in layout
    assert "board.tacticEchoLayoutDirty = true" in layout
    assert "board.tacticEchoPendingLayoutFingerprint = fingerprint" in layout
    assert "including SetScale/SetPoint/SetSize/SetShown" in layout
    assert "board.tacticEchoLayoutDirty = nil" in layout


def test_tactical_board_blocks_container_drag_mutations_in_combat() -> None:
    board = read("UI/TacticalBoard.lua")
    assert "local function beginContainerMove(frame)" in board
    assert "frame.tacticEchoCombatDragBlocked = true" in board
    assert "if not db().locked then self.tacticEchoDragging = beginContainerMove(board) end" in board
    assert "if self.tacticEchoDragging == true then finishContainerMove(board) end" in board
    assert "if not db().locked then beginContainerMove(board) end" in board
    assert "function() finishContainerMove(board) end" in board
    assert "if not db().locked then board:StartMoving() end" not in board
    assert "function() board:StopMovingOrSizing(); savePoint(board) end" not in board


def test_tactical_board_only_creates_in_scope_hud_cards() -> None:
    board = read("UI/TacticalBoard.lua")
    assert 'nodes.primary = TacticalIconButton:Create(board, nil, 68, "main_toggle")' in board
    assert 'nodes.tactical.burst[index] = TacticalIconButton:Create(board, nil, 46, "manual_action")' in board
    assert 'nodes.candidates[index] = TacticalIconButton:Create' not in board
    assert 'interrupt = TacticalIconButton:Create' not in board
    assert 'control = TacticalIconButton:Create' not in board
    assert 'mobility = TacticalIconButton:Create' not in board
    assert 'nodes.defense[index] = TacticalIconButton:Create' not in board
