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
    assert "applyFrameShown(defenseFrame, hasDefense)" in board
    assert "applyFrameShown(panel, true)" in board
    assert "applyFrameShown(panel, false); applyFrameShown(defenseFrame, false); return" in board
    assert "defenseFrame:SetShown(hasDefense)" not in board
    assert "panel:Show()" not in board
    assert "panel:Hide()" not in board


def test_tactical_board_blocks_drag_moving_api_in_combat() -> None:
    board = read("UI/TacticalBoard.lua")
    assert "local function beginContainerMove(frame)" in board
    assert "frame.tacticEchoCombatDragBlocked = true" in board
    assert "local function finishContainerMove(frame, prefix)" in board
    assert "if inCombatLockdown() then\n        frame.tacticEchoCombatDragBlocked = nil" in board
    assert "board:StartMoving()" not in board
    assert "defenseFrame:StartMoving()" not in board
    assert "board:StopMovingOrSizing()" not in board
    assert "defenseFrame:StopMovingOrSizing()" not in board


def test_tactical_layout_defers_layout_mutations_in_combat() -> None:
    layout = read("UI/TacticalHudLayout.lua")
    assert "local function inCombatLockdown()" in layout
    assert "if inCombatLockdown() then" in layout
    assert "board.tacticEchoLayoutDirty = true" in layout
    assert "board.tacticEchoPendingLayoutFingerprint = fingerprint" in layout
    assert "including SetScale/SetPoint/SetSize/SetShown" in layout
    assert "board.tacticEchoLayoutDirty = nil" in layout
