-- Author      : generalwrex (Natop on Myzrael TBC)
-- Create Date : 1/28/2022 9:30:08 AM

WowSimsExporter = LibStub("AceAddon-3.0"):NewAddon("WowSimsExporter", "AceConsole-3.0", "AceEvent-3.0")


WowSimsExporter.Character = ""
WowSimsExporter.Link = "https://feralpaw69.github.io/wotlksim/"

local AceGUI = LibStub("AceGUI-3.0")
local LibParse = LibStub("LibParse")

local version = "2.3.1"

local defaults = {
	profile = {
		--updateGearChange = true,
	},
}

local options = { 
	name = "WowSimsExporter",
	handler = WowSimsExporter,
	type = "group",
	args = {
		--updateGearChange = {
			--type = "toggle",
			--name = "Update on Gear Change",
			--desc = "Update your data when you change gear pieces.",
			--get = "isGearChangeSet",
			--set = "setGearChange"
		--},
		openExporterButton = {
			type = "execute",
			name = "Open Exporter Window",
			desc = "Opens the exporter window",
			func = function() WowSimsExporter:CreateWindow() end
		},
	},
}


function WowSimsExporter:CreateCharacterStructure(unit)
    local name, realm = UnitName(unit)
    local locClass, engClass, locRace, engRace, gender, name, server = GetPlayerInfoByGUID(UnitGUID(unit))
    local level = UnitLevel(unit)

    self.Character = {
        name = name,
        realm = realm,
        race = engRace:gsub( "Scourge", "Undead"), -- hack? lol
        class = engClass:lower(),
		level = tonumber(level),
        talents = "",
		glyphs = { major = { }, minor = { } }, --wotlk
        professions = { }, --{ name = "", level = "" }, --wotlk
		spec  =  self:CheckCharacterSpec(engClass:lower()),
        gear = { items = { } } 
	}

    return self.Character
end

function WowSimsExporter:CreateGlyphEntry()
	local minor = {}
	local major = {}

	for t = 1, 6 do
		local enabled, glyphType = GetGlyphSocketInfo(t)
		if enabled then
			local link = GetGlyphLink(t)
			local name = link and link:match("%[(.-)%]")
			if name then
				if glyphType == 1 then -- major
					table.insert(major, name)
				elseif glyphType == 2 then -- minor
					table.insert(minor, name)
				end
			end
		end
	end

	self.Character.glyphs.major = major
	self.Character.glyphs.minor = minor
end



function WowSimsExporter:CreateProfessionEntry()
	local wanted = {}
	for _, profName in pairs(WowSimsExporter.professionNames) do
		wanted[profName] = true
	end
	local professions = {}

	-- GetSkillLineInfo skips skills under collapsed headers, so expand
	-- everything temporarily and restore the collapsed state afterwards.
	local collapsed = {}
	local anyCollapsed = false
	for i = 1, GetNumSkillLines() do
		local skillName, isHeader, isExpanded = GetSkillLineInfo(i)
		if isHeader and not isExpanded then
			collapsed[skillName] = true
			anyCollapsed = true
		end
	end
	if anyCollapsed then ExpandSkillHeader(0) end

	for i = 1, GetNumSkillLines() do
		local name, isHeader, _, skillLevel = GetSkillLineInfo(i)
		if not isHeader and wanted[name] then
			table.insert(professions, { name = name, level = skillLevel })
		end
	end

	if anyCollapsed then
		for i = GetNumSkillLines(), 1, -1 do
			local name, isHeader = GetSkillLineInfo(i)
			if isHeader and collapsed[name] then CollapseSkillHeader(i) end
		end
	end

	self.Character.professions = professions
end

function WowSimsExporter:CreateTalentEntry()
    local talents = {}

    local numTabs = GetNumTalentTabs()
    for t = 1, numTabs do
        local numTalents = GetNumTalents(t)
        for i = 1, numTalents do
	    local nameTalent, icon, tier, column, currRank, maxRank = GetTalentInfo(t, i)
            table.insert(talents, tostring(currRank))
        end
        if (t < 3) then
            table.insert(talents, "-")
        end
    end

    return table.concat(talents)
end

function WowSimsExporter:CheckCharacterSpec(class)
	local specs = self.specializations
	local points = {}
	for tab = 1, 3 do
		-- 3rd return value is points spent in the tree
		local _, _, spent = GetTalentTabInfo(tab)
		points[tab] = spent or 0
	end

	if points[1] + points[2] + points[3] == 0 then return "" end

	for _, character in ipairs(specs) do
		if character.class == class and character.comparator(points[1], points[2], points[3]) then
			return character.spec
		end
	end
	return ""
end

function WowSimsExporter:OpenWindow(input)
    if not input or input:trim() == "" then
		self:CreateWindow()
	elseif (input == "export") then        
        self:CreateWindow(true)
    elseif (input == "open") then
		self:CreateWindow()
    elseif (input=="options") then           
		InterfaceOptionsFrame_OpenToCategory(self.optionsFrame)
		InterfaceOptionsFrame_OpenToCategory(self.optionsFrame)
    end
end

function WowSimsExporter:GetGearEnchantGems(type)
    local gear = {}
    local slotNames = WowSimsExporter.slotNames

    -- 0 / empty means "nothing" in an item link
    local function num(v)
        v = tonumber(v)
        if v and v > 0 then return v end
        return nil
    end

    for slotNum = 1, #slotNames do
        local slotId = GetInventorySlotInfo(slotNames[slotNum])
        local itemLink = GetInventoryItemLink("player", slotId)

        if itemLink then
            local Id, Enchant, Gem1, Gem2, Gem3, Gem4 = self:ParseItemLink(itemLink)
            local item = {}
            item.id = tonumber(Id)
            item.enchant = num(Enchant)
            -- The gem fields in an item link are gem *enchant* IDs; the simulator
            -- needs the gems' item IDs, which GetItemGem returns via the gem link.
            item.gems = {}
            for g = 1, 4 do
                local _, gemLink = GetItemGem(itemLink, g)
                local gemId = gemLink and tonumber(gemLink:match("item:(%d+)"))
                item.gems[g] = gemId or 0
            end
            -- trim trailing empty sockets, keep 0 placeholders in between
            while #item.gems > 0 and item.gems[#item.gems] == 0 do
                item.gems[#item.gems] = nil
            end
            if #item.gems == 0 then item.gems = nil end
            gear[slotNum] = item
        end
    end

    self.Character.spec = self:CheckCharacterSpec(self.Character.class)
    self.Character.talents = self:CreateTalentEntry()
    self:CreateGlyphEntry() -- wotlk
    self:CreateProfessionEntry() -- wotlk
    self.Character.gear.items = gear

    return self.Character
end


function WowSimsExporter:ParseItemLink(itemLink)
    -- item:itemId:enchantId:gem1:gem2:gem3:gem4:suffixId:uniqueId:...
    local itemString = itemLink:match("item:([%-%d:]*)")
    if not itemString then return nil end
    local fields = {}
    for field in (itemString .. ":"):gmatch("(%-?%d*):") do
        fields[#fields + 1] = field
    end
    return fields[1], fields[2], fields[3], fields[4], fields[5], fields[6]
end

function WowSimsExporter:OnInitialize()

	self.db = LibStub("AceDB-3.0"):New("WSEDB", defaults, true)

	LibStub("AceConfig-3.0"):RegisterOptionsTable("WowSimsExporter", options)
	self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("WowSimsExporter", "WowSimsExporter")

	local profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
	LibStub("AceConfig-3.0"):RegisterOptionsTable("WowSimsExporter_Profiles", profiles)
	LibStub("AceConfigDialog-3.0"):AddToBlizOptions("WowSimsExporter_Profiles", "Profiles", "WowSimsExporter")

    self:RegisterChatCommand("wse", "OpenWindow")
    self:RegisterChatCommand("wowsimsexporter", "OpenWindow")
    self:RegisterChatCommand("wsexporter", "OpenWindow")

    self:Print("WowSimsExporter v" .. version .. " Initialized. use /wse For Window.")

end


-- UI
function WowSimsExporter:BuildLinks(frame, character)
	local specs = self.specializations
	local supportedsims =  self.supportedSims 
	local class = character.class
	local spec  = character.spec

	if WowSimsExporter.tContains(supportedsims, class) then

		for i, char in ipairs(specs) do
			if char and char.class == class and char.spec == spec then

				local link = WowSimsExporter.prelink..(char.url)..WowSimsExporter.postlink

				local l = AceGUI:Create("InteractiveLabel")
				l:SetText("Click to copy: "..link.."\r\n")
				l:SetFullWidth(true)
				l:SetCallback("OnClick", function()		
					WowSimsExporter:CreateCopyDialog(link)
				end)
				frame:AddChild(l)
			end
		end
	end
end


function WowSimsExporter:CreateCopyDialog(text)

	local frame = AceGUI:Create("Frame")
	frame:SetTitle("WSE Copy Dialog")
    frame:SetStatusText("Use CTRL+C to copy link")
    frame:SetLayout("Flow")
	frame:SetWidth(400)
	frame:SetHeight(100)
	frame:SetCallback(
        "OnClose",
        function(widget)
            AceGUI:Release(widget)
        end
    )

	local editbox = AceGUI:Create("EditBox")
    editbox:SetText(text)
    editbox:SetFullWidth(true)
    editbox:DisableButton(true)

	editbox:SetFocus()
	editbox:HighlightText()
	
	frame:AddChild(editbox)

end

function WowSimsExporter:CreateWindow(generate)

	local char = self:CreateCharacterStructure("player")
	
    if self.frame then
        AceGUI:Release(self.frame)
        self.frame = nil
    end

    local frame = AceGUI:Create("Frame")
    self.frame = frame
    frame:SetCallback(
        "OnClose",
        function(widget)
            if WowSimsExporter.frame == widget then WowSimsExporter.frame = nil end
            AceGUI:Release(widget)
        end
    )
    frame:SetTitle("WowSimsExporter V" .. version .. "")
    frame:SetStatusText("Click 'Generate Data' to generate exportable data")
    frame:SetLayout("Flow")


    local jsonbox = AceGUI:Create("MultiLineEditBox")
    jsonbox:SetLabel("Copy and paste into the websites importer!")
    jsonbox:SetFullWidth(true)
    jsonbox:SetFullHeight(true)
    jsonbox:DisableButton(true)
   
	local function l_Generate()
		WowSimsExporter.Character = WowSimsExporter:GetGearEnchantGems("player")
		jsonbox:SetText(LibParse:JSONEncode(WowSimsExporter.Character)) 
		jsonbox:HighlightText()
		jsonbox:SetFocus()

		frame:SetStatusText("Data Generated!")
	end

	if generate then l_Generate() end

    local button = AceGUI:Create("Button")
    button:SetText("Generate Data")
    button:SetWidth(200)
	button:SetCallback("OnClick", function()		
		l_Generate()
	end)
	
	
	local icon = AceGUI:Create("Icon")
	icon:SetImage("Interface\\AddOns\\WowSimsExporter\\Skins\\wowsims.tga") 
	icon:SetImageSize(32, 32)
	icon:SetFullWidth(true)


    local label = AceGUI:Create("Label")
	label:SetFullWidth(true)
    label:SetText([[

To upload your character to the simuator, click on the url below that leads to the simuator website.

You will find an Import button on the top right of the simulator named "Import". Click that and select the "Addon" tab, paste the data
into the provided box and click "Import"

]])

	if not WowSimsExporter.tContains(self.supportedSims, char.class) then

		frame:AddChild(icon)

		local l1 = AceGUI:Create("Heading")
		l1:SetText("")
		l1:SetColor(255,0,0)
		l1:SetFullWidth(true)
		frame:AddChild(l1)


		local l = AceGUI:Create("Label")
		l:SetText("Your characters class is currently unsupported. The supported classes are currently;\n"..table.concat(self.supportedSims,"\n"))
		l:SetColor(255,0,0)
		l:SetFullWidth(true)
		frame:AddChild(l)

		-- never added to the frame, so release them ourselves
		AceGUI:Release(jsonbox)
		AceGUI:Release(button)
		AceGUI:Release(label)
	else

		frame:AddChild(icon)
		frame:AddChild(label)
		WowSimsExporter:BuildLinks(frame, char)
		frame:AddChild(button)
		frame:AddChild(jsonbox)

	end

end



-- Small "WSE" button next to the Currency tab of the character window.
function WowSimsExporter:CreateCharacterFrameButton()
	if self.charButton or not CharacterFrame then return end

	local button = CreateFrame("Button", "WowSimsExporterCharacterButton", CharacterFrame, "UIPanelButtonTemplate")
	button:SetWidth(44)
	button:SetHeight(22)
	button:SetText("WSE")
	button:SetFrameLevel(CharacterFrame:GetFrameLevel() + 5)

	-- right of the last visible tab (Currency, or Skills if Currency is hidden)
	local function Reanchor()
		local anchor
		for i = 5, 1, -1 do
			local tab = _G["CharacterFrameTab" .. i]
			if tab and tab:IsShown() then anchor = tab break end
		end
		button:ClearAllPoints()
		if anchor then
			button:SetPoint("LEFT", anchor, "RIGHT", 2, 0)
		else
			button:SetPoint("TOPLEFT", CharacterFrame, "BOTTOMLEFT", 0, 0)
		end
	end
	Reanchor()
	CharacterFrame:HookScript("OnShow", Reanchor)

	button:SetScript("OnClick", function() WowSimsExporter:CreateWindow(true) end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("WowSimsExporter")
		GameTooltip:AddLine("Export this character to the simulator.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)

	self.charButton = button
end

function WowSimsExporter:OnEnable()
	self:CreateCharacterFrameButton()
end

function WowSimsExporter:OnDisable()
end

function WowSimsExporter:isGearChangeSet(info)
	return self.db.profile.updateGearChange
end

function WowSimsExporter:setGearChange(info, value)
	self.db.profile.updateGearChange = value
end
