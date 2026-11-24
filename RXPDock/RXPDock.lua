-- Quests | RestedXP tabs above the Questie tracker (Questie_BaseFrame).
-- RestedXP is never hidden: hiding RXPFrame pauses the guide (its OnHide sets isHidden).
-- On the Quests tab it is only made invisible and click-through, so it keeps tracking steps.
local tabs, buttons, hidQuestie, tick, dragging
local active, hidPS, psHooked = "quests", false, false -- active: the tab really shown this tick

-- muted[f] = the mouse state RXP wants back for f (click, motion, wheel)
local muted, hooked, quiet = {}, {}, false
local setters = {
	EnableMouse = function(s, on) s.c, s.m = on, on end,
	SetMouseClickEnabled = function(s, on) s.c = on end,
	SetMouseMotionEnabled = function(s, on) s.m = on end,
	EnableMouseWheel = function(s, on) s.w = on end,
}

local function db()
	RXPDockDB = RXPDockDB or { tab = "quests" }
	return RXPDockDB
end

local function top(f) return f and f:IsShown() and f:GetTop() and f:GetTop() * f:GetEffectiveScale() end

-- RXP's window and its parts that stick up above it. V2 UI (beta setting) uses a separate window.
local function rxpParts(r)
	local a, ok, w = _G.RXP, false, nil
	if a and a.v2 and a.v2.GetGuideWindowAnchorFrame then ok, w = pcall(a.v2.GetGuideWindowAnchorFrame, a.v2) end
	if ok and w then
		local st = a.v2.state and a.v2.state.player and a.player and a.v2.state.player[a.player.name]
		-- in V2 RXPFrame stays at its old spot and doesn't follow the window; counting it would make us chase it
		local sf = st and st.activeStepFrame and st.activeStepFrame.frame
		if sf and select(2, sf:GetPoint(1)) ~= w then sf = nil end -- not attached to the window yet
		return w, { sf }
	end
	return r, { r.GuideName, r.CurrentStepFrame, r.BarContainer }
end

-- Put RXP's highest visible part right under the tab bar.
local function placeRXP(win, parts)
	local wTop = top(win)
	if not (wTop and tabs:GetBottom()) or IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") then return end
	local highest = wTop
	for i = 1, 3 do highest = math.max(highest, top(parts[i]) or wTop) end
	local ts, ws = tabs:GetEffectiveScale(), win:GetEffectiveScale()
	local x = tabs:GetLeft() * ts / ws
	local y = ((tabs:GetBottom() - 6) * ts - (highest - wTop)) / ws -- 6: room for RXP's step number badge
	local p, rel, rp, ox, oy = win:GetPoint(1)
	if p == "TOPLEFT" and rel == UIParent and rp == "BOTTOMLEFT" and ox
		and math.abs(ox - x) < 0.5 and math.abs(oy - y) < 0.5 then return end
	win:ClearAllPoints()
	win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
end

local function off(f)
	quiet = true
	pcall(function() f:SetMouseClickEnabled(false); f:SetMouseMotionEnabled(false); f:EnableMouseWheel(false) end)
	quiet = false
end

-- RXP turns mouse on/off on its step frames itself: remember what it asked for, keep it off while muted.
local function hook(f)
	if hooked[f] then return end
	hooked[f] = true
	for name, set in pairs(setters) do
		if f[name] then
			hooksecurefunc(f, name, function(self, on)
				if quiet or not muted[self] then return end
				set(muted[self], not not on)
				off(self)
			end)
		end
	end
end

local function mute(f)
	if not f:IsShown() or (f:IsProtected() and InCombatLockdown()) then return end -- hidden frames can't take clicks
	local s = muted[f]
	if s then
		-- setting a mouse script (OnEnter...) can turn the mouse back on without the hooked setters
		if f:IsMouseClickEnabled() then s.c = true; off(f) end
		if f:IsMouseMotionEnabled() then s.m = true; off(f) end
	else
		hook(f)
		local click = f.IsMouseClickEnabled and f:IsMouseClickEnabled()
		local motion = f.IsMouseMotionEnabled and f:IsMouseMotionEnabled()
		if click == nil then click = f:IsMouseEnabled() end
		if motion == nil then motion = f:IsMouseEnabled() end
		muted[f] = { c = click, m = motion, w = f.IsMouseWheelEnabled and f:IsMouseWheelEnabled() or false }
		off(f)
	end
	for _, c in ipairs({ f:GetChildren() }) do mute(c) end
end

local function unmute()
	quiet = true
	for f, s in pairs(muted) do
		if not (f:IsProtected() and InCombatLockdown()) then
			pcall(function() f:SetMouseClickEnabled(s.c); f:SetMouseMotionEnabled(s.m); f:EnableMouseWheel(s.w) end)
			muted[f] = nil
		end
	end
	quiet = false
end

local function paint()
	for key, b in pairs(buttons) do
		local on = db().tab == key
		if on then b.text:SetTextColor(0.96, 0.94, 0.9) else b.text:SetTextColor(0.56, 0.53, 0.47) end
		b.line:SetShown(on)
		b.sel:SetShown(on)
	end
end

local function makeTab(key, label, x)
	local b = CreateFrame("Button", nil, tabs)
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	b.text:SetText(label)
	b.text:SetPoint("LEFT", 8, 1)
	b:SetSize(b.text:GetStringWidth() + 16, 20)
	b:SetPoint("BOTTOMLEFT", x, 0)
	b.line = b:CreateTexture(nil, "OVERLAY")
	b.line:SetColorTexture(0.2, 0.9, 0.2)
	b.line:SetPoint("BOTTOMLEFT")
	b.line:SetPoint("BOTTOMRIGHT")
	b.line:SetHeight(2)
	b.sel = b:CreateTexture(nil, "BACKGROUND") -- soft wash behind the active tab, like Polestar
	b.sel:SetAllPoints()
	b.sel:SetColorTexture(1, 1, 1, 0.07)
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.07)
	b:SetScript("OnClick", function()
		if db().tab == key or IsControlKeyDown() then return end -- Ctrl = dragging, not switching
		if SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
		db().tab = key; paint(); tick()
	end)
	buttons[key] = b
	return b
end

local function makeTabs(q)
	tabs = CreateFrame("Frame", "RXPDockTabs", UIParent)
	tabs:SetHeight(20)
	tabs:SetPoint("BOTTOMRIGHT", q, "TOPRIGHT", 0, 0) -- follows Questie when you move it; width set by fitTabs
	local div = tabs:CreateTexture(nil, "ARTWORK")
	div:SetColorTexture(1, 1, 1, 0.12)
	div:SetPoint("BOTTOMLEFT")
	div:SetPoint("BOTTOMRIGHT")
	div:SetHeight(1)
	buttons = {}
	local a = makeTab("quests", QUESTS_LABEL or "Quests", 0)
	local b = makeTab("rxp", "RestedXP", a:GetWidth())
	makeTab("polestar", "Polestar", a:GetWidth() + b:GetWidth())
	paint()
	-- Questie re-shows its tracker on every update; hide it again in the same frame (no flicker).
	hooksecurefunc(q, "Show", function(self)
		if active ~= "quests" and not InCombatLockdown() and not dragging then self:Hide() end
	end)
	-- Ctrl + drag the tab bar moves the Questie tracker (and so everything), using Questie's own drag code,
	-- which also saves the new spot. Handy when the tracker itself sits under the minimap.
	local function startDrag(_, button)
		if not IsControlKeyDown() or InCombatLockdown() then return end
		local ok, TBF = pcall(QuestieLoader.ImportModule, QuestieLoader, "TrackerBaseFrame")
		if not ok or not TBF then return end
		dragging = true
		if not q:IsShown() then q:Show(); hidQuestie = true end -- a hidden frame can't be dragged; tick restores it after
		TBF.OnDragStart(q, button)
	end
	local function stopDrag(_, button)
		if not dragging then return end
		dragging = false
		local ok, TBF = pcall(QuestieLoader.ImportModule, QuestieLoader, "TrackerBaseFrame")
		if ok and TBF then TBF.OnDragStop(q, button) end
	end
	tabs:EnableMouse(true)
	tabs:SetScript("OnMouseDown", startDrag)
	tabs:SetScript("OnMouseUp", stopDrag)
	for _, b in pairs(buttons) do
		b:HookScript("OnMouseDown", startDrag)
		b:HookScript("OnMouseUp", stopDrag)
	end
end

-- Tab bar = width of the window it sits on, right-aligned to Questie. On the RestedXP tab the bar (and
-- so RXP) is no wider than RXP, so the hidden, wider Questie tracker can't hold RXP away from the screen edge.
local function fitTabs(q, win)
	local f = active ~= "quests" and win or q
	local w = f:GetWidth() * f:GetEffectiveScale() / tabs:GetEffectiveScale()
	if w > 0 and math.abs(tabs:GetWidth() - w) > 0.5 then tabs:SetWidth(w) end
end

-- RXP visible and clickable, or invisible and click-through (but still running).
local function showRXP(on, r, win)
	if on then
		if next(muted) then unmute() end -- RXP has no secure children (item/target buttons live on UIParent)
		r:SetAlpha(1); win:SetAlpha(1)
	else
		r:SetAlpha(0); win:SetAlpha(0)
		mute(r); if win ~= r then mute(win) end
	end
end

-- Polestar's guide window. Hiding it is safe: its own close button does the same and the guide keeps running.
local function hidePS(p)
	if p:IsShown() and not (p:IsProtected() and InCombatLockdown()) then p:Hide(); hidPS = true end
end

function tick()
	local q, r = _G.Questie_BaseFrame, _G.RXPFrame
	if not (q and r) then return end -- no Questie tracker: leave RXP alone
	if not tabs then makeTabs(q) end
	if dragging then return end
	local win, parts = rxpParts(r)
	local p = _G.PolestarGuideFrame
	if p and not psHooked then
		psHooked = true
		-- Polestar re-shows its window by itself: put it away again unless its tab is open.
		p:HookScript("OnShow", function(self) if active ~= "polestar" and not dragging then hidePS(self) end end)
	end
	local safe = not InCombatLockdown() -- Questie's tracker holds secure quest-item buttons
	-- the tab really shown: a closed RXP or Polestar falls back to Quests
	active = db().tab
	if active == "rxp" and not win:IsShown() then active = "quests" end
	if active == "polestar" and not (p and (p:IsShown() or hidPS)) then active = "quests" end
	if p and active ~= "polestar" then hidePS(p) end
	fitTabs(q, active == "polestar" and p or win)
	placeRXP(win, parts)
	if active == "polestar" then
		if hidPS and not (p:IsProtected() and InCombatLockdown()) then hidPS = false; p:Show() end
		placeRXP(p, {})
		if q:IsShown() then
			if not safe then return end
			q:Hide()
		end
		hidQuestie = true
		showRXP(false, r, win) -- invisible but still tracking steps
	elseif active == "rxp" then -- RestedXP tab
		if q:IsShown() then
			if not safe then return end -- can't hide Questie in combat: keep the old view until it ends
			q:Hide()
		end
		hidQuestie = true
		showRXP(true, r, win)
	else
		if hidQuestie and safe then
			hidQuestie = false
			-- let Questie decide: it shows only when quests are tracked and none of its hide rules apply
			local ok = pcall(function() QuestieLoader:ImportModule("QuestieTracker"):Update() end)
			if not ok then q:Show() end
		end
		if hidQuestie then return end -- Questie can't come back until combat ends: keep RXP visible meanwhile
		-- Questie hid itself (no quests, instance, tracker off): show RXP so the slot isn't empty
		showRXP(not q:IsShown(), r, win)
	end
end

C_Timer.NewTicker(0.2, tick)

SLASH_RXPDOCK1 = "/rxpdock"
SlashCmdList.RXPDOCK = function()
	local nextTab = { quests = "rxp", rxp = "polestar", polestar = "quests" }
	db().tab = nextTab[db().tab] or "quests"
	if buttons then paint(); tick() end
end
