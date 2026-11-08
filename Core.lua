-- Artifact Power User: minimap button that uses "Artifact Power" consumables
-- from your bags. Hover for a count/total, click (or Alt+MouseWheel) to use
-- one. Legion 7.3.5.

local DEFAULT_ANGLE = 215
local MINIMAP_RADIUS = 80

APUserDB = APUserDB or {}
APUserDB.minimapAngle = APUserDB.minimapAngle or DEFAULT_ANGLE

-- ============================================================================
-- Artifact Power item detection (tooltip scan, cached per itemID so we only
-- ever scan a given item once per session)
-- ============================================================================

local scanTooltip = CreateFrame("GameTooltip", "APUserScanTooltip", nil, "GameTooltipTemplate")
scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")

local apCache = {} -- itemID -> AP amount per use (number), or false if not an AP item

-- The use-effect line is genitive ("силы артефакта"), not the nominative
-- category line ("Сила артефакта") shown elsewhere in the same tooltip.
local AP_KEYWORDS = { "силы артефакта", "сила артефакта", "Сила артефакта", "Artifact Power" }

-- Large values are written as "<number>[,<decimal>] <magnitude>" (млн =
-- million, млрд = billion, тыс = thousand); the comma is a decimal point
-- ("2,5 млрд" = 2.5 billion), not a thousands separator.
local MAGNITUDE_WORDS = { "млрд", "млн", "тыс" }
local MAGNITUDE_MULTIPLIER = { ["млрд"] = 1e9, ["млн"] = 1e6, ["тыс"] = 1e3 }

-- Tooltip lines can carry hidden formatting codes (e.g. the number colored
-- differently from the surrounding text) that render invisibly but still
-- sit in the raw string and break a naive number match right after the
-- digits - strip them before parsing.
local function StripEscapeCodes(text)
	if not text then return text end
	text = text:gsub("|c%x%x%x%x%x%x%x%x", "") -- |cAARRGGBB color start
	text = text:gsub("|r", "")                  -- color reset
	text = text:gsub("|T.-|t", "")               -- inline texture
	text = text:gsub("|A.-|a", "")               -- inline atlas texture
	text = text:gsub("|H.-|h(.-)|h", "%1")        -- hyperlink, keep the visible text
	return text
end

local function ExtractAPAmount(text)
	if not text then return nil end
	text = StripEscapeCodes(text)

	local hasKeyword = false
	for _, keyword in ipairs(AP_KEYWORDS) do
		if text:find(keyword, 1, true) then
			hasKeyword = true
			break
		end
	end
	if not hasKeyword then return nil end

	for _, magWord in ipairs(MAGNITUDE_WORDS) do
		local whole, frac = text:match("(%d+)[,%.]?(%d*)%s*" .. magWord)
		if whole then
			local value = tonumber(whole)
			if frac and frac ~= "" then
				value = value + tonumber("0." .. frac)
			end
			local amount = value * MAGNITUDE_MULTIPLIER[magWord]
			if amount > 0 then return amount end
		end
	end

	-- No magnitude word - a plain number, possibly thousands-separated by
	-- whatever byte the locale uses (e.g. a non-breaking space Lua's %s
	-- doesn't match); glue every digit run in the line together.
	local digits = {}
	for group in text:gmatch("%d+") do
		digits[#digits + 1] = group
	end
	if #digits > 0 then
		local amount = tonumber(table.concat(digits))
		if amount and amount > 0 then return amount end
	end
	return nil
end

-- Returns the AP amount a single use of this item grants, or false if it's
-- not an Artifact Power item (or we don't know yet - see NumLines() check).
local function ScanItemForAP(itemID, bypassCache)
	if not itemID then return false end
	if not bypassCache then
		local cached = apCache[itemID]
		if cached ~= nil then
			return cached
		end
	end

	scanTooltip:ClearLines()
	scanTooltip:SetItemByID(itemID)

	if scanTooltip:NumLines() == 0 then
		-- Item info not cached client-side yet; don't remember a result, try again later.
		return false
	end

	local amount = nil
	for i = 2, scanTooltip:NumLines() do
		local line = _G["APUserScanTooltipTextLeft" .. i]
		amount = ExtractAPAmount(line and line:GetText())
		if amount then break end
	end

	apCache[itemID] = amount or false
	return apCache[itemID]
end

-- Totals can land in the billions (same AP items the game itself
-- abbreviates as "2,5 млрд"), so mirror that formatting instead of
-- printing a wall of digits.
local function FormatBigNumber(n)
	if n >= 1e9 then
		return string.format("%.2f млрд", n / 1e9)
	elseif n >= 1e6 then
		return string.format("%.2f млн", n / 1e6)
	elseif n >= 1e3 then
		return string.format("%.1f тыс", n / 1e3)
	end
	return tostring(math.floor(n))
end

-- ============================================================================
-- Bag scanning
-- ============================================================================

local function GetAPSummary()
	local totalCount, totalPower = 0, 0
	for bag = 0, NUM_BAG_SLOTS do
		for slot = 1, (GetContainerNumSlots(bag) or 0) do
			local itemID = GetContainerItemID(bag, slot)
			if itemID then
				local amount = ScanItemForAP(itemID)
				if amount then
					local _, itemCount = GetContainerItemInfo(bag, slot)
					itemCount = itemCount or 1
					totalCount = totalCount + itemCount
					totalPower = totalPower + (amount * itemCount)
				end
			end
		end
	end
	return totalCount, totalPower
end

-- Finds the first Artifact Power item currently in bags.
-- Returns bag, slot, itemLink or nil if none found.
local function FindFirstAPItem()
	for bag = 0, NUM_BAG_SLOTS do
		for slot = 1, (GetContainerNumSlots(bag) or 0) do
			local itemID = GetContainerItemID(bag, slot)
			if itemID and ScanItemForAP(itemID) then
				return bag, slot, GetContainerItemLink(bag, slot)
			end
		end
	end
	return nil
end

-- ============================================================================
-- Minimap button
--
-- UseContainerItem() is a protected function - it can only be invoked by a
-- secure template reacting to a direct hardware click, never by addon Lua
-- calling it from a script handler (OnClick included, but *especially*
-- OnMouseWheel, which isn't on Blizzard's hardware-action-allowed list at
-- all). So instead of calling it ourselves, this button is a
-- SecureActionButtonTemplate with type=item/item=<link> attributes that we
-- keep pointed at the first AP item found; clicking it (or triggering a
-- bound key click on it) lets Blizzard's own secure code use the item.
-- ============================================================================

local button = CreateFrame("Button", "APUserMinimapButton", Minimap, "SecureActionButtonTemplate")
button:SetSize(31, 31)
button:SetFrameStrata("MEDIUM")
button:SetFrameLevel(8)
-- AnyUp only: registering AnyDown too makes the secure click (and our
-- OnClick hook that reassigns the item attribute) fire twice per click,
-- once on press and once on release - if the item has a cast time, the
-- second firing lands mid-cast and clips it, like changing targets mid-cast.
button:RegisterForClicks("AnyUp")
button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local icon = button:CreateTexture(nil, "BACKGROUND")
icon:SetSize(20, 20)
icon:SetPoint("CENTER", 0, 0)
icon:SetTexture("Interface\\Icons\\inv_scroll_10")
icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- trim the default icon border padding
button.icon = icon

local border = button:CreateTexture(nil, "OVERLAY")
border:SetSize(54, 54)
border:SetPoint("TOPLEFT", 0, 0)
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

local function UpdateButtonPosition()
	local angle = math.rad(APUserDB.minimapAngle or DEFAULT_ANGLE)
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * MINIMAP_RADIUS, math.sin(angle) * MINIMAP_RADIUS)
end

button:SetMovable(true)
button:RegisterForDrag("LeftButton")
button:SetScript("OnDragStart", function(self)
	self:SetScript("OnUpdate", function()
		local mx, my = Minimap:GetCenter()
		local px, py = GetCursorPosition()
		local scale = Minimap:GetEffectiveScale()
		px, py = px / scale, py / scale
		APUserDB.minimapAngle = math.deg(math.atan2(py - my, px - mx))
		UpdateButtonPosition()
	end)
end)
button:SetScript("OnDragStop", function(self)
	self:SetScript("OnUpdate", nil)
end)

-- ============================================================================
-- Keep the secure button's item/target attributes pointed at the first AP
-- item. SetAttribute on a secure frame from insecure code is fine outside
-- combat; while in combat we just defer the refresh until it ends.
-- ============================================================================

local pendingRefresh = false

-- True while the player is mid-cast or mid-channel. Using an item in that
-- window isn't wanted (can clip/interrupt the cast), so we point the
-- secure button at nothing until the cast resolves.
local function IsPlayerCasting()
	return UnitCastingInfo("player") ~= nil or UnitChannelInfo("player") ~= nil
end

local function RefreshUseAttribute()
	if InCombatLockdown() then
		pendingRefresh = true
		return
	end
	pendingRefresh = false

	local itemLink
	if not IsPlayerCasting() then
		local _, _, link = FindFirstAPItem()
		itemLink = link
	end

	if itemLink then
		button:SetAttribute("type", "item")
		button:SetAttribute("item", itemLink)
	else
		button:SetAttribute("type", nil)
		button:SetAttribute("item", nil)
	end
end

local function RefreshTooltipIfShown()
	if GameTooltip:GetOwner() == button then
		button:GetScript("OnEnter")(button)
	end
end

button:SetScript("OnEnter", function(self)
	local count, power = GetAPSummary()
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:SetText("Сила артефакта", 1, 1, 1)
	GameTooltip:AddLine(string.format("Предметов в сумках: %d", count), 0.9, 0.9, 0.9)
	GameTooltip:AddLine(string.format("Суммарная сила артефакта: %s", FormatBigNumber(power)), 0.1, 1, 0.1)
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Клик: использовать предмет", 0.6, 0.8, 1)
	GameTooltip:AddLine("Alt + колесо: использовать предмет", 0.6, 0.8, 1)
	if IsPlayerCasting() then
		GameTooltip:AddLine("Недоступно: идёт каст/ченнелинг", 1, 0.3, 0.3)
	end
	GameTooltip:Show()
end)
button:SetScript("OnLeave", function()
	GameTooltip:Hide()
end)

-- The secure click already performs the item use via the type/item
-- attributes; this just handles our own non-protected bookkeeping
-- (refreshing the tooltip and picking the next item to point at).
--
-- UNIT_SPELLCAST_START lags a bit behind the click itself (server round
-- trip), so IsPlayerCasting() can still say "not casting" for a brief
-- window right after a click that just started one. Re-pointing the
-- attribute immediately would let a near-simultaneous second click/wheel
-- tick clip that not-yet-registered cast - so clear the attribute right
-- away (nothing to click on for a moment) and only recompute the real
-- target after a short delay.
local CLICK_SETTLE_DELAY = 0.3 -- seconds
local settleTimer

button:HookScript("OnClick", function()
	if not InCombatLockdown() then
		button:SetAttribute("type", nil)
		button:SetAttribute("item", nil)
	end
	RefreshTooltipIfShown()

	if settleTimer then
		settleTimer:Cancel()
	end
	settleTimer = C_Timer.NewTimer(CLICK_SETTLE_DELAY, function()
		settleTimer = nil
		RefreshUseAttribute()
		RefreshTooltipIfShown()
	end)
end)

-- ============================================================================
-- Alt+MouseWheel: bind the key combo to click this same secure button
-- instead of handling OnMouseWheel ourselves (OnMouseWheel can't initiate
-- protected actions at all, bound keys can).
-- ============================================================================

ClearOverrideBindings(button)
SetOverrideBindingClick(button, true, "ALT-MOUSEWHEELUP", "APUserMinimapButton")
SetOverrideBindingClick(button, true, "ALT-MOUSEWHEELDOWN", "APUserMinimapButton")

-- ============================================================================
-- Events
-- ============================================================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("BAG_UPDATE")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "player")
eventFrame:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_ENABLED" then
		if pendingRefresh then
			RefreshUseAttribute()
		end
	else
		RefreshUseAttribute()
		RefreshTooltipIfShown()
	end
end)

UpdateButtonPosition()
RefreshUseAttribute()

-- Safety-net rescan: BAG_UPDATE should catch every bag change, but this
-- periodic rescan covers any item that becomes/stops being usable without
-- one firing (e.g. a cooldown or level-based restriction clearing).
local RESCAN_INTERVAL = 10 -- seconds
C_Timer.NewTicker(RESCAN_INTERVAL, function()
	RefreshUseAttribute()
	RefreshTooltipIfShown()
end)

-- ============================================================================
-- Debug: /apdebug dumps, for every item currently detected as an Artifact
-- Power item, its link, the amount+count computed, and every raw tooltip
-- line - useful if Blizzard ever changes the tooltip phrasing and detection
-- silently breaks again.
-- ============================================================================

local function DebugDumpAPItems()
	wipe(apCache)
	print("|cff33ccffAPUser debug:|r сканирую сумки (кэш сброшен)...")
	local found = false
	for bag = 0, NUM_BAG_SLOTS do
		for slot = 1, (GetContainerNumSlots(bag) or 0) do
			local itemID = GetContainerItemID(bag, slot)
			if itemID then
				local amount = ScanItemForAP(itemID, true) -- bypass cache: always fresh for debug
				if amount then
					found = true
					local link = GetContainerItemLink(bag, slot)
					local _, itemCount = GetContainerItemInfo(bag, slot)
					print(string.format("|cffffff00[AP]|r %s x%d -> %s (%d) за использование (itemID=%d)",
						link or "?", itemCount or 1, FormatBigNumber(amount), amount, itemID))

					scanTooltip:ClearLines()
					scanTooltip:SetItemByID(itemID)
					for i = 1, scanTooltip:NumLines() do
						local lineLeft = _G["APUserScanTooltipTextLeft" .. i]
						local text = lineLeft and lineLeft:GetText()
						if text then
							print(string.format("  line %d: %s", i, text))
						end
					end
				end
			end
		end
	end
	if not found then
		print("|cffff4444APUser debug:|r ни один предмет не определён как Сила артефакта.")
	end
end

SLASH_APUSERDEBUG1 = "/apdebug"
SlashCmdList["APUSERDEBUG"] = DebugDumpAPItems
