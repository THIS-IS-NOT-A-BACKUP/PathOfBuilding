-- Path of Building
--
-- Module: Build
-- Loads and manages the current build.
--
local pairs = pairs
local ipairs = ipairs
local next = next
local t_insert = table.insert
local m_min = math.min
local m_max = math.max
local m_floor = math.floor
local m_abs = math.abs
local s_format = string.format

local buildMode = new("ControlHost")

local function InsertIfNew(t, val)
	if (not t) then return end
	for i,v in ipairs(t) do
		if v == val then return end
	end
	table.insert(t, val)
end

---matchFlags
---  Compares the skill flags table against the line flag settings
---  Required enabling flags check takes precedence over disabling flags check
---@param reqFlags table containing the required flags
---@param notFlags table containing the disabling flags
---@param flags table containing the flags to match against
local function matchFlags(reqFlags, notFlags, flags)
	if type(reqFlags) == "string" then
		reqFlags = { reqFlags }
	end
	if reqFlags then
		for _, flag in ipairs(reqFlags) do
			if not flags[flag] then
				return
			end
		end
	end

	if type(notFlags) == "string" then
		notFlags = { notFlags }
	end
	if notFlags then
		for _, flag in ipairs(notFlags) do
			if flags[flag] then
				return
			end
		end
	end
	-- Both flag checks passed, default true
	return true
end

function buildMode:Init(dbFileName, buildName, buildXML, convertBuild, importLink)
	self.dbFileName = dbFileName
	self.buildName = buildName
	self.importLink = importLink
	if dbFileName then
		self.dbFileSubPath = self.dbFileName:sub(#main.buildPath + 1, -#self.buildName - 5)
	else
		self.dbFileSubPath = main.modes.LIST.subPath or ""
	end
	if not buildName then
		main:SetMode("LIST")
	end

	-- Load build file
	self.xmlSectionList = { }
	self.spectreList = { }
	self.timelessData = { jewelType = { }, conquerorType = { }, devotionVariant1 = 1, devotionVariant2 = 1, jewelSocket = { }, fallbackWeightMode = { }, searchList = "", searchListFallback = "", searchResults = { }, sharedResults = { } }
	self.viewMode = "TREE"
	self.characterLevel = m_min(m_max(main.defaultCharLevel or 1, 1), 100)
	self.targetVersion = liveTargetVersion
	self.bandit = "None"
	self.pantheonMajorGod = "None"
	self.pantheonMinorGod = "None"
	self.characterLevelAutoMode = main.defaultCharLevel == 1 or main.defaultCharLevel == nil
	if buildXML then
		if self:LoadDB(buildXML, "Unnamed build") then
			self:CloseBuild()
			return
		end
		self.modFlag = true
	else
		if self:LoadDBFile() then
			self:CloseBuild()
			return
		end
		self.modFlag = false
	end

	if convertBuild then
		self.targetVersion = liveTargetVersion
	end
	if self.targetVersion ~= liveTargetVersion then
		self.targetVersion = nil
		self:OpenConversionPopup()
		return
	end

	self.abortSave = true

	wipeTable(self.controls)

	local miscTooltip = new("Tooltip")

	-- Controls: top bar, left side
	self.anchorTopBarLeft = new("Control", nil, {4, 4, 0, 20})
	self.controls.back = new("ButtonControl", {"LEFT",self.anchorTopBarLeft,"RIGHT"}, {0, 0, 60, 20}, "<< Back", function()
		if self.unsaved then
			self:OpenSavePopup("LIST")
		else
			self:CloseBuild()
		end
	end)
	self.controls.buildName = new("Control", {"LEFT",self.controls.back,"RIGHT"}, {8, 0, 0, 20})
	self.controls.buildName.width = function(control)
		local limit = self.anchorTopBarRight:GetPos() - 98 - 40 - self.controls.back:GetSize() - self.controls.save:GetSize() - self.controls.saveAs:GetSize()
		local bnw = DrawStringWidth(16, "VAR", self.buildName)
		self.strWidth = m_min(bnw, limit)
		self.strLimited = bnw > limit
		return self.strWidth + 98
	end
	self.controls.buildName.Draw = function(control)
		local x, y = control:GetPos()
		local width, height = control:GetSize()
		SetDrawColor(0.5, 0.5, 0.5)
		DrawImage(nil, x + 91, y, self.strWidth + 6, 20)
		SetDrawColor(0, 0, 0)
		DrawImage(nil, x + 92, y + 1, self.strWidth + 4, 18)
		SetDrawColor(1, 1, 1)
		SetViewport(x, y + 2, self.strWidth + 94, 16)
		DrawString(0, 0, "LEFT", 16, "VAR", "Current build:  "..self.buildName)
		SetViewport()
		if control:IsMouseInBounds() then
			SetDrawLayer(nil, 10)
			miscTooltip:Clear()
			if self.dbFileSubPath and self.dbFileSubPath ~= "" then
				miscTooltip:AddLine(16, self.dbFileSubPath..self.buildName)
			elseif self.strLimited then
				miscTooltip:AddLine(16, self.buildName)
			end
			miscTooltip:Draw(x, y, width, height, main.viewPort)
			SetDrawLayer(nil, 0)
		end
	end
	self.controls.save = new("ButtonControl", {"LEFT",self.controls.buildName,"RIGHT"}, {8, 0, 50, 20}, "Save", function()
		self:SaveDBFile()
	end)
	self.controls.save.enabled = function()
		return not self.dbFileName or self.unsaved
	end
	self.controls.saveAs = new("ButtonControl", {"LEFT",self.controls.save,"RIGHT"}, {8, 0, 70, 20}, "Save As", function()
		self:OpenSaveAsPopup()
	end)
	self.controls.saveAs.enabled = function()
		return self.dbFileName
	end

	-- Controls: top bar, right side
	self.anchorTopBarRight = new("Control", nil, {function() return main.screenW / 2 + 6 end, 4, 0, 20})
	self.controls.pointDisplay = new("Control", {"LEFT",self.anchorTopBarRight,"RIGHT"}, {-12, 0, 0, 20})
	self.controls.pointDisplay.x = function(control)
		local width, height = control:GetSize()
		if self.controls.saveAs:GetPos() + self.controls.saveAs:GetSize() < self.anchorTopBarRight:GetPos() - width - 16 then
			return -12 - width
		else
			return 0
		end
	end
	self.controls.pointDisplay.width = function(control)
		control.str, control.req = self:EstimatePlayerProgress()
		return DrawStringWidth(16, "FIXED", control.str) + 8
	end
	self.controls.pointDisplay.Draw = function(control)
		local x, y = control:GetPos()
		local width, height = control:GetSize()
		SetDrawColor(1, 1, 1)
		DrawImage(nil, x, y, width, height)
		SetDrawColor(0, 0, 0)
		DrawImage(nil, x + 1, y + 1, width - 2, height - 2)
		SetDrawColor(1, 1, 1)
		DrawString(x + 4, y + 2, "LEFT", 16, "FIXED", control.str)
		if control:IsMouseInBounds() then
			SetDrawLayer(nil, 10)
			miscTooltip:Clear()
			miscTooltip:AddLine(16, control.req)
			miscTooltip:Draw(x, y, width, height, main.viewPort)
			SetDrawLayer(nil, 0)
		end
	end
	self.controls.levelScalingButton = new("ButtonControl", {"LEFT",self.controls.pointDisplay,"RIGHT"}, {12, 0, 50, 20}, self.characterLevelAutoMode and "Auto" or "Manual", function()
		self.characterLevelAutoMode = not self.characterLevelAutoMode
		self.controls.levelScalingButton.label = self.characterLevelAutoMode and "Auto" or "Manual"
		self.configTab:BuildModList()
		self.modFlag = true
		self.buildFlag = true
	end)
	self.controls.characterLevel = new("EditControl", {"LEFT",self.controls.levelScalingButton,"RIGHT"}, {8, 0, 106, 20}, "", "Level", "%D", 3, function(buf)
		self.characterLevel = m_min(m_max(tonumber(buf) or 1, 1), 100)
		self.configTab:BuildModList()
		self.modFlag = true
		self.buildFlag = true
		self.characterLevelAutoMode = false
		self.controls.levelScalingButton.label = "Manual"
	end)
	self.controls.characterLevel:SetText(self.characterLevel)
	self.controls.characterLevel.tooltipFunc = function(tooltip)
		if tooltip:CheckForUpdate(self.characterLevel) then
			tooltip:AddLine(16, "Experience multiplier:")
			local playerLevel = self.characterLevel
			local safeZone = 3 + m_floor(playerLevel / 16)
			for level, expLevel in ipairs(self.data.monsterExperienceLevelMap) do
				local diff = m_abs(playerLevel - expLevel) - safeZone
				local mult
				if diff <= 0 then
					mult = 1
				else
					mult = ((playerLevel + 5) / (playerLevel + 5 + diff ^ 2.5)) ^ 1.5
				end
				if playerLevel >= 95 then
					local xpPenalty = ({0.935, 0.885, 0.813, 0.7175, 0.6})[playerLevel - 94] or 0
					mult = mult * (1 / (1 + 0.1 * (playerLevel - 94))) * xpPenalty
				end
				if mult > 0.01 then
					local line = level
					if level >= 68 then 
						line = line .. string.format(" (Tier %d)", level - 67)
					end
					line = line .. string.format(": %.1f%%", mult * 100)
					tooltip:AddLine(14, line)
				end
			end
		end
	end
	self.controls.classDrop = new("DropDownControl", {"LEFT",self.controls.characterLevel,"RIGHT"}, {8, 0, 100, 20}, nil, function(index, value)
		if value.classId ~= self.spec.curClassId then
			if self.spec:CountAllocNodes() == 0 or self.spec:IsClassConnected(value.classId) then
				self.spec:SelectClass(value.classId)
				self.spec:AddUndoState()
				self.spec:SetWindowTitleWithBuildClass()
				self.buildFlag = true
			else
				main:OpenConfirmPopup("Class Change", "Changing class to "..value.label.." will reset your passive tree.\nThis can be avoided by connecting one of the "..value.label.." starting nodes to your tree.", "Continue", function()
					self.spec:SelectClass(value.classId)
					self.spec:AddUndoState()
					self.spec:SetWindowTitleWithBuildClass()
					self.buildFlag = true					
				end)
			end
		end
	end)
	self.controls.ascendDrop = new("DropDownControl", {"LEFT",self.controls.classDrop,"RIGHT"}, {8, 0, 120, 20}, nil, function(index, value)
		self.spec:SelectAscendClass(value.ascendClassId)
		self.spec:AddUndoState()
		self.spec:SetWindowTitleWithBuildClass()
		self.buildFlag = true
	end)
	-- // hiding away until we learn more, this dropdown and the Loadout dropdown conflict for UI space, will need to address if secondaryAscendancies come back
	--self.controls.secondaryAscendDrop = new("DropDownControl", {"LEFT",self.controls.ascendDrop,"RIGHT"}, {8, 0, 120, 20}, nil, function(index, value)
	--	self.spec:SelectSecondaryAscendClass(value.ascendClassId)
	--	self.spec:AddUndoState()
	--	self.spec:SetWindowTitleWithBuildClass()
	--	self.buildFlag = true
	--end)
	self.controls.buildLoadouts = new("DropDownControl", {"LEFT",self.controls.ascendDrop,"RIGHT"}, {8, 0, 190, 20}, {}, function(index, value)
		if value == "^7^7Loadouts:" or value == "^7^7-----" then
			self.controls.buildLoadouts:SetSel(1)
			return
		end
		if value == "^7^7Sync" then
			self:SyncLoadouts()
			self.controls.buildLoadouts:SetSel(1)
			return
		end
		if value == "^7^7Help >>" then
			main:OpenAboutPopup(7)
			self.controls.buildLoadouts:SetSel(1)
			return
		end
		if value == "^7^7New Loadout" then
			local controls = { }
			controls.label = new("LabelControl", nil, {0, 20, 0, 16}, "^7Enter name for this loadout:")
			controls.edit = new("EditControl", nil, {0, 40, 350, 20}, "New Loadout", nil, nil, 100, function(buf)
				controls.save.enabled = buf:match("%S")
			end)
			controls.save = new("ButtonControl", nil, {-45, 70, 80, 20}, "Save", function()
				local loadout = controls.edit.buf

				local newSpec = new("PassiveSpec", self, latestTreeVersion)
				newSpec.title = loadout
				t_insert(self.treeTab.specList, newSpec)

				local itemSet = self.itemsTab:NewItemSet(#self.itemsTab.itemSets + 1)
				t_insert(self.itemsTab.itemSetOrderList, itemSet.id)
				itemSet.title = loadout

				local skillSet = self.skillsTab:NewSkillSet(#self.skillsTab.skillSets + 1)
				t_insert(self.skillsTab.skillSetOrderList, skillSet.id)
				skillSet.title = loadout

				local configSet = self.configTab:NewConfigSet(#self.configTab.configSets + 1)
				t_insert(self.configTab.configSetOrderList, configSet.id)
				configSet.title = loadout

				self:SyncLoadouts()
				self.modFlag = true
				main:ClosePopup()
			end)
			controls.save.enabled = false
			controls.cancel = new("ButtonControl", nil, {45, 70, 80, 20}, "Cancel", function()
				main:ClosePopup()
			end)
			main:OpenPopup(370, 100, "Set Name", controls, "save", "edit", "cancel")

			self.controls.buildLoadouts:SetSel(1)
			return
		end

		-- item, skill, and config sets have identical structure
		-- return id as soon as it's found
		local function findSetId(setOrderList, value, sets, setSpecialLinks)
			for _, setOrder in ipairs(setOrderList) do
				if value == (sets[setOrder].title or "Default") then
					return setOrder
				else
					local linkMatch = string.match(value, "%{(%w+)%}")
					if linkMatch then
						return setSpecialLinks[linkMatch]["setId"]
					end
				end
			end
			return nil
		end

		-- trees have a different structure with id/name pairs
		-- return id as soon as it's found
		local function findNamedSetId(treeList, value, setSpecialLinks)
			for id, spec in ipairs(treeList) do
				if value == spec then
					return id
				else
					local linkMatch = string.match(value, "%{(%w+)%}")
					if linkMatch then
						return setSpecialLinks[linkMatch]["setId"]
					end
				end
			end
			return nil
		end

		local oneSkill = self.skillsTab and #self.skillsTab.skillSetOrderList == 1
		local oneItem = self.itemsTab and #self.itemsTab.itemSetOrderList == 1
		local oneConfig = self.configTab and #self.configTab.configSetOrderList == 1

		local newSpecId = findNamedSetId(self.treeTab:GetSpecList(), value, self.treeListSpecialLinks)
		local newItemId = oneItem and 1 or findSetId(self.itemsTab.itemSetOrderList, value, self.itemsTab.itemSets, self.itemListSpecialLinks)
		local newSkillId = oneSkill and 1 or findSetId(self.skillsTab.skillSetOrderList, value, self.skillsTab.skillSets, self.skillListSpecialLinks)
		local newConfigId = oneConfig and 1 or findSetId(self.configTab.configSetOrderList, value, self.configTab.configSets, self.configListSpecialLinks)

		-- if exact match nor special grouping cannot find setIds, bail
		if newSpecId == nil or newItemId == nil or newSkillId == nil or newConfigId == nil then
			return
		end

		if newSpecId ~= self.treeTab.activeSpec then
			self.treeTab:SetActiveSpec(newSpecId)
		end
		if newItemId ~= self.itemsTab.activeItemSetId then
			self.itemsTab:SetActiveItemSet(newItemId)
		end
		if newSkillId ~= self.skillsTab.activeSkillSetId then
			self.skillsTab:SetActiveSkillSet(newSkillId)
		end
		if newConfigId ~= self.configTab.activeConfigSetId then
			self.configTab:SetActiveConfigSet(newConfigId)
		end

		self.controls.buildLoadouts:SelByValue(value)
	end)

	--self.controls.similarBuilds = new("ButtonControl", {"LEFT",self.controls.buildLoadouts,"RIGHT"}, {8, 0, 100, 20}, "Similar Builds", function()
	--	self:OpenSimilarPopup()
	--end)
	--self.controls.similarBuilds.tooltipFunc = function(tooltip)
	--	tooltip:Clear()
	--	tooltip:AddLine(16, "Search for builds similar to your current character.")
	--	tooltip:AddLine(16, "For best results, make sure to select your main item set, tree, and skills before opening the popup.")
	--end
	
	if buildName == "~~temp~~" then
		-- Remove temporary build file
		os.remove(self.dbFileName)
		self.buildName = "Unnamed build"
		self.dbFileName = false
		self.dbFileSubPath = nil
		self.modFlag = true
	end

	-- List of display stats
	self.displayStats, self.minionDisplayStats, self.extraSaveStats = LoadModule("Modules/BuildDisplayStats")

	-- Controls: Side bar
	self.anchorSideBar = new("Control", nil, {4, 36, 0, 0})
	self.controls.modeImport = new("ButtonControl", {"TOPLEFT",self.anchorSideBar,"TOPLEFT"}, {0, 0, 134, 20}, "Import/Export Build", function()
		self.viewMode = "IMPORT"
	end)
	self.controls.modeImport.locked = function() return self.viewMode == "IMPORT" end
	self.controls.modeNotes = new("ButtonControl", {"LEFT",self.controls.modeImport,"RIGHT"}, {4, 0, 58, 20}, "Notes", function()
		self.viewMode = "NOTES"
	end)
	self.controls.modeNotes.locked = function() return self.viewMode == "NOTES" end
	self.controls.modeConfig = new("ButtonControl", {"TOPRIGHT",self.anchorSideBar,"TOPLEFT"}, {300, 0, 100, 20}, "Configuration", function()
		self.viewMode = "CONFIG"
	end)
	self.controls.modeConfig.locked = function() return self.viewMode == "CONFIG" end
	self.controls.modeTree = new("ButtonControl", {"TOPLEFT",self.anchorSideBar,"TOPLEFT"}, {0, 26, 72, 20}, "Tree", function()
		self.viewMode = "TREE"
	end)
	self.controls.modeTree.locked = function() return self.viewMode == "TREE" end
	self.controls.modeSkills = new("ButtonControl", {"LEFT",self.controls.modeTree,"RIGHT"}, {4, 0, 72, 20}, "Skills", function()
		self.viewMode = "SKILLS"
	end)
	self.controls.modeSkills.locked = function() return self.viewMode == "SKILLS" end
	self.controls.modeItems = new("ButtonControl", {"LEFT",self.controls.modeSkills,"RIGHT"}, {4, 0, 72, 20}, "Items", function()
		self.viewMode = "ITEMS"
	end)
	self.controls.modeItems.locked = function() return self.viewMode == "ITEMS" end
	self.controls.modeCalcs = new("ButtonControl", {"LEFT",self.controls.modeItems,"RIGHT"}, {4, 0, 72, 20}, "Calcs", function()
		self.viewMode = "CALCS"
	end)
	self.controls.modeCalcs.locked = function() return self.viewMode == "CALCS" end
	self.controls.modeParty = new("ButtonControl", {"TOPLEFT",self.anchorSideBar,"TOPLEFT"}, {0, 52, 72, 20}, "Party", function()
		self.viewMode = "PARTY"
	end)
	self.controls.modeParty.locked = function() return self.viewMode == "PARTY" end
	-- Skills
	self.controls.mainSkillLabel = new("LabelControl", {"TOPLEFT",self.anchorSideBar,"TOPLEFT"}, {0, 80, 300, 16}, "^7Main Skill:")
	self.controls.mainSocketGroup = new("DropDownControl", {"TOPLEFT",self.controls.mainSkillLabel,"BOTTOMLEFT"}, {0, 2, 300, 18}, nil, function(index, value)
		self.mainSocketGroup = index
		self.modFlag = true
		self.buildFlag = true
	end)
	self.controls.mainSocketGroup.maxDroppedWidth = 500
	self.controls.mainSocketGroup.tooltipFunc = function(tooltip, mode, index, value)
		local socketGroup = self.skillsTab.socketGroupList[index]
		if socketGroup and tooltip:CheckForUpdate(socketGroup, self.outputRevision) then
			self.skillsTab:AddSocketGroupTooltip(tooltip, socketGroup)
		end
	end
	self.controls.mainSkill = new("DropDownControl", {"TOPLEFT",self.controls.mainSocketGroup,"BOTTOMLEFT"}, {0, 2, 300, 18}, nil, function(index, value)
		local mainSocketGroup = self.skillsTab.socketGroupList[self.mainSocketGroup]
		mainSocketGroup.mainActiveSkill = index
		self.modFlag = true
		self.buildFlag = true
	end)
	self.controls.mainSkillPart = new("DropDownControl", {"TOPLEFT",self.controls.mainSkill,"BOTTOMLEFT",true}, {0, 2, 300, 18}, nil, function(index, value)
		local mainSocketGroup = self.skillsTab.socketGroupList[self.mainSocketGroup]
		local srcInstance = mainSocketGroup.displaySkillList[mainSocketGroup.mainActiveSkill].activeEffect.srcInstance
		srcInstance.skillPart = index
		self.modFlag = true
		self.buildFlag = true
	end)
	self.controls.mainSkillStageCountLabel = new("LabelControl", {"TOPLEFT",self.controls.mainSkillPart,"BOTTOMLEFT",true}, {0, 3, 0, 16}, "^7Stages:") {
		shown = function()
			return self.controls.mainSkillStageCount:IsShown()
		end,
	}
	self.controls.mainSkillStageCount = new("EditControl", {"LEFT",self.controls.mainSkillStageCountLabel,"RIGHT",true}, {2, 0, 60, 18}, nil, nil, "%D", nil, function(buf)
		local mainSocketGroup = self.skillsTab.socketGroupList[self.mainSocketGroup]
		local srcInstance = mainSocketGroup.displaySkillList[mainSocketGroup.mainActiveSkill].activeEffect.srcInstance
		srcInstance.skillStageCount = tonumber(buf)
		self.modFlag = true
		self.buildFlag = true
	end)
	self.controls.mainSkillMineCountLabel = new("LabelControl", {"TOPLEFT",self.controls.mainSkillStageCountLabel,"BOTTOMLEFT",true}, {0, 3, 0, 16}, "^7Active Mines:") {
		shown = function()
			return self.controls.mainSkillMineCount:IsShown()
		end,
	}
	self.controls.mainSkillMineCount = new("EditControl", {"LEFT",self.controls.mainSkillMineCountLabel,"RIGHT",true}, {2, 0, 60, 18}, nil, nil, "%D", nil, function(buf)
		local mainSocketGroup = self.skillsTab.socketGroupList[self.mainSocketGroup]
		local srcInstance = mainSocketGroup.displaySkillList[mainSocketGroup.mainActiveSkill].activeEffect.srcInstance
		srcInstance.skillMineCount = tonumber(buf)
		self.modFlag = true
		self.buildFlag = true
	end)
	self.controls.mainSkillMinion = new("DropDownControl", {"TOPLEFT",self.controls.mainSkillMineCountLabel,"BOTTOMLEFT",true}, {0, 3, 178, 18}, nil, function(index, value)
		local mainSocketGroup = self.skillsTab.socketGroupList[self.mainSocketGroup]
		local srcInstance = mainSocketGroup.displaySkillList[mainSocketGroup.mainActiveSkill].activeEffect.srcInstance
		if value.itemSetId then
			srcInstance.skillMinionItemSet = value.itemSetId
		else
			srcInstance.skillMinion = value.minionId
		end
		self.modFlag = true
		self.buildFlag = true
	end)
	function self.controls.mainSkillMinion.CanReceiveDrag(control, type, value)
		if type == "Item" and control.list[control.selIndex] and control.list[control.selIndex].itemSetId then
			local mainSocketGroup = self.skillsTab.socketGroupList[self.mainSocketGroup]
			local minionUses = mainSocketGroup.displaySkillList[mainSocketGroup.mainActiveSkill].activeEffect.grantedEffect.minionUses
			return minionUses and minionUses[value:GetPrimarySlot()] -- O_O
		end
	end
	function self.controls.mainSkillMinion.ReceiveDrag(control, type, value, source)
		self.itemsTab:EquipItemInSet(value, control.list[control.selIndex].itemSetId)
	end
	function self.controls.mainSkillMinion.tooltipFunc(tooltip, mode, index, value)
		tooltip:Clear()
		if value.itemSetId then
			self.itemsTab:AddItemSetTooltip(tooltip, self.itemsTab.itemSets[value.itemSetId])
			tooltip:AddSeparator(14)
			tooltip:AddLine(14, colorCodes.TIP.."Tip: You can drag items from the Items tab onto this dropdown to equip them onto the minion.")
		end
	end
	self.controls.mainSkillMinionLibrary = new("ButtonControl", {"LEFT",self.controls.mainSkillMinion,"RIGHT"}, {2, 0, 120, 18}, "Manage Spectres...", function()
		self:OpenSpectreLibrary()
	end)
	self.controls.mainSkillMinionSkill = new("DropDownControl", {"TOPLEFT",self.controls.mainSkillMinion,"BOTTOMLEFT",true}, {0, 2, 200, 16}, nil, function(index, value)
		local mainSocketGroup = self.skillsTab.socketGroupList[self.mainSocketGroup]
		local srcInstance = mainSocketGroup.displaySkillList[mainSocketGroup.mainActiveSkill].activeEffect.srcInstance
		srcInstance.skillMinionSkill = index
		self.modFlag = true
		self.buildFlag = true
	end)
	self.controls.statBoxAnchor = new("Control", {"TOPLEFT",self.controls.mainSkillMinionSkill,"BOTTOMLEFT",true}, {0, 2, 0, 0})
	self.controls.statBox = new("TextListControl", {"TOPLEFT",self.controls.statBoxAnchor,"BOTTOMLEFT"}, {0, 2, 300, 0}, {{x=170,align="RIGHT_X"},{x=174,align="LEFT"}})
	self.controls.statBox.height = function(control)
		local x, y = control:GetPos()
		local warnHeight = main.showWarnings and #self.controls.warnings.lines > 0 and 18 or 0
		return main.screenH - main.mainBarHeight - 4 - y - warnHeight
	end
	self.controls.warnings = new("Control",{"TOPLEFT",self.controls.statBox,"BOTTOMLEFT",true}, {0, 0, 0, 18})
	self.controls.warnings.lines = {}
	self.controls.warnings.width = function(control)
		return control.str and DrawStringWidth(16, "FIXED", control.str) + 8 or 0
	end
	self.controls.warnings.Draw = function(control)
		if #self.controls.warnings.lines > 0 then
			local count = 0
			for _ in pairs(self.controls.warnings.lines) do count = count + 1 end
			control.str = string.format(colorCodes.NEGATIVE.."%d Warnings", count)
			local x, y = control:GetPos()
			local width, height = control:GetSize()
			DrawString(x, y + 2, "LEFT", 16, "FIXED", control.str)
			if control:IsMouseInBounds() then
				SetDrawLayer(nil, 10)
				miscTooltip:Clear()
				for k,v in pairs(self.controls.warnings.lines) do miscTooltip:AddLine(16, v) end
				miscTooltip:Draw(x, y, width, height, main.viewPort)
				SetDrawLayer(nil, 0)
			end
		else
			control.str = {}
		end
	end

	-- Initialise build components
	self.latestTree = main.tree[latestTreeVersion]
	data.setJewelRadiiGlobally(latestTreeVersion)
	self.data = data
	self.importTab = new("ImportTab", self)
	self.notesTab = new("NotesTab", self)
	self.partyTab = new("PartyTab", self)
	self.configTab = new("ConfigTab", self)
	self.itemsTab = new("ItemsTab", self)
	self.treeTab = new("TreeTab", self)
	self.skillsTab = new("SkillsTab", self)
	self.calcsTab = new("CalcsTab", self)

	-- Load sections from the build file
	self.savers = {
		["Config"] = self.configTab,
		["Notes"] = self.notesTab,
		["Party"] = self.partyTab,
		["Tree"] = self.treeTab,
		["TreeView"] = self.treeTab.viewer,
		["Items"] = self.itemsTab,
		["Skills"] = self.skillsTab,
		["Calcs"] = self.calcsTab,
		["Import"] = self.importTab,
	}
	self.legacyLoaders = { -- Special loaders for legacy sections
		["Spec"] = self.treeTab,
	}
	
	--special rebuild to properly initialise boss placeholders
	self.configTab:BuildModList()
	self:UpdateClassDropdowns()

	-- Load legacy bandit and pantheon choices from build section
	for _, control in ipairs({ "bandit", "pantheonMajorGod", "pantheonMinorGod" }) do
		self.configTab.input[control] = self[control]
	end

	-- so we ran into problems with converted trees, trying to check passive tree routes and also consider thread jewels
	-- but we can't check jewel info because items have not been loaded yet, and they come after passives in the xml.
	-- the simplest solution seems to be making sure passive trees (which contain jewel sockets) are loaded last.
	local deferredPassiveTrees = { }
	for _, node in ipairs(self.xmlSectionList) do
		-- Check if there is a saver that can load this section
		local saver = self.savers[node.elem] or self.legacyLoaders[node.elem]
		if saver then
			-- if the saver is treeTab, defer it until everything is loaded
			if saver == self.treeTab  then
				t_insert(deferredPassiveTrees, node)
			else
				if saver:Load(node, self.dbFileName) then
					self:CloseBuild()
					return
				end
			end
		end
	end
	for _, node in ipairs(deferredPassiveTrees) do
		-- Check if there is a saver that can load this section
		if self.treeTab:Load(node, self.dbFileName) then
			self:CloseBuild()
			return
		end
	end
	for _, saver in pairs(self.savers) do
		if saver.PostLoad then
			saver:PostLoad()
		end
	end

	if next(self.configTab.input) == nil then
		-- Check for old calcs tab settings
		self.configTab:ImportCalcSettings()
	end

	-- Build calculation output tables
	self.outputRevision = 1
	self.calcsTab:BuildOutput()
	self:RefreshStatList()
	self.buildFlag = false

	self.spec:SetWindowTitleWithBuildClass()

	--[[
	local testTooltip = new("Tooltip")
	for _, item in pairs(main.uniqueDB.list) do
		ConPrintf("%s", item.name)
		self.itemsTab:AddItemTooltip(testTooltip, item)
		testTooltip:Clear()
	end
	for _, item in pairs(main.rareDB.list) do
		ConPrintf("%s", item.name)
		self.itemsTab:AddItemTooltip(testTooltip, item)
		testTooltip:Clear()
	end
	--]]

	--[[
	local start = GetTime()
	SetProfiling(true)
	for i = 1, 10  do
		self.calcsTab:PowerBuilder()
	end
	SetProfiling(false)
	ConPrintf("Power build time: %d ms", GetTime() - start)
	--]]

	self.abortSave = false
	self:SyncLoadouts()
end

local acts = {
	-- https://www.poewiki.net/wiki/Passive_skill
	[1] = { level = 1, questPoints = 0 },
	-- Act 1   : The Dweller of the Deep
	-- Act 1   : The Marooned Mariner
	[2] = { level = 12, questPoints = 2 },
	-- Act 1,2 : The Way Forward (Reward after reaching Act 2)
	-- Act 2   : Through Sacred Ground (Fellshrine Reward 3.25)
	[3] = { level = 22, questPoints = 4 },
	-- Act 3   : Victario's Secrets
	-- Act 3   : Piety's Pets
	[4] = { level = 32, questPoints = 6 },
	-- Act 4   : An Indomitable Spirit
	[5] = { level = 40, questPoints = 7 },
	-- Act 5   : In Service to Science
	-- Act 5   : Kitava's Torments
	[6] = { level = 44, questPoints = 9 },
	-- Act 6   : The Father of War
	-- Act 6   : The Puppet Mistress
	-- Act 6   : The Cloven One
	[7] = { level = 50, questPoints = 12 },
	-- Act 7   : The Master of a Million Faces
	-- Act 7   : Queen of Despair
	-- Act 7   : Kishara's Star
	[8] = { level = 54, questPoints = 15 },
	-- Act 8   : Love is Dead
	-- Act 8   : Reflection of Terror
	-- Act 8   : The Gemling Legion
	[9] = { level = 60, questPoints = 18 },
	-- Act 9   : Queen of the Sands
	-- Act 9   : The Ruler of Highgate
	[10] = { level = 64, questPoints = 20 },
	-- Act 10  : Vilenta's Vengeance
	-- Act 10  : An End to Hunger (+2)
	[11] = { level = 67, questPoints = 23 },
}

local function actExtra(act, extra)
	-- Act 2 : Deal With The Bandits (+1 if the player kills all bandits)
	return act > 2 and extra or 0
end

function buildMode:SyncLoadouts()
	self.controls.buildLoadouts.list = {"No Loadouts"}

	local filteredList = {"^7^7Loadouts:"}
	local treeList = {}
	local itemList = {}
	local skillList = {}
	local configList = {}
	-- used when clicking on the dropdown to set the correct setId for each SetActiveSet()
	self.treeListSpecialLinks, self.itemListSpecialLinks, self.skillListSpecialLinks, self.configListSpecialLinks = {}, {}, {}, {}

	local oneSkill = self.skillsTab and #self.skillsTab.skillSetOrderList == 1
	local oneItem = self.itemsTab and #self.itemsTab.itemSetOrderList == 1
	local oneConfig = self.configTab and #self.configTab.configSetOrderList == 1

	if self.treeTab ~= nil and self.itemsTab ~= nil and self.skillsTab ~= nil and self.configTab ~= nil then
		local transferTable = {}
		local sortedTreeListSpecialLinks = {}
		for id, spec in ipairs(self.treeTab.specList) do
			local specTitle = spec.title or "Default"
			-- only alphanumeric and comma are allowed in the braces { }
			local linkIdentifier = string.match(specTitle, "%{([%w,]+)%}")

			if linkIdentifier then
				local setName = specTitle:gsub("%{" .. linkIdentifier .. "%}", ""):gsub("^%s*", ""):gsub("%s*$", "")
				if not setName or setName == "" then
					setName = "Default"
				end

				-- iterate over each identifier, delimited by comma, and set the index so we can grab it later
				-- setId index is the id of the set in the global list needed for SetActiveSet
				-- setName is only used for Tree currently and we strip the braces to get the plain name of the set, this is used as the name of the loadout
				for linkId in string.gmatch(linkIdentifier, "[^%,]+") do
					transferTable["setId"] = id
					transferTable["setName"] = setName
					transferTable["linkId"] = linkId
					self.treeListSpecialLinks[linkId] = transferTable
					t_insert(sortedTreeListSpecialLinks, transferTable)
					transferTable = {}
				end
			else
				t_insert(treeList, (spec.treeVersion ~= latestTreeVersion and ("["..treeVersions[spec.treeVersion].display.."] ") or "")..(specTitle))
			end
		end

		-- item, skill, and config sets have identical structure
		local function identifyLinks(setOrderList, tabSets, setList, specialLinks, treeLinks)
			for id, set in ipairs(setOrderList) do
				local setTitle = tabSets[set].title or "Default"
				local linkIdentifier = string.match(setTitle, "%{([%w,]+)%}")

				-- this if/else prioritizes group identifier in case the user creates sets with same name AND same identifiers
				-- result is only the group is recognized and one loadout is created rather than a duplicate from each condition met
				if linkIdentifier then
					local setName = setTitle:gsub("%{" .. linkIdentifier .. "%}", ""):gsub("^%s*", ""):gsub("%s*$", "")
					if not setName or setName == "" then
						setName = "Default"
					end

					for linkId in string.gmatch(linkIdentifier, "[^%,]+") do
						transferTable["setId"] = set
						transferTable["setName"] = setName
						specialLinks[linkId] = transferTable
						transferTable = {}
					end
				else
					setList[setTitle] = true
				end
			end
		end
		identifyLinks(self.itemsTab.itemSetOrderList, self.itemsTab.itemSets, itemList, self.itemListSpecialLinks, self.treeListSpecialLinks)
		identifyLinks(self.skillsTab.skillSetOrderList, self.skillsTab.skillSets, skillList, self.skillListSpecialLinks, self.treeListSpecialLinks)
		identifyLinks(self.configTab.configSetOrderList, self.configTab.configSets, configList, self.configListSpecialLinks, self.treeListSpecialLinks)

		-- loop over all for exact match loadouts
		for id, tree in ipairs(treeList) do
			if (oneItem or itemList[tree]) and (oneSkill or skillList[tree]) and (oneConfig or configList[tree]) then
				t_insert(filteredList, tree)
			end
		end
		-- loop over the identifiers found within braces and set the loadout name to the TreeSet
		for _, tree in ipairs(sortedTreeListSpecialLinks) do
			local treeLinkId = tree.linkId
			if ((oneItem or self.itemListSpecialLinks[treeLinkId]) and (oneSkill or self.skillListSpecialLinks[treeLinkId]) and (oneConfig or self.configListSpecialLinks[treeLinkId])) then
				t_insert(filteredList, tree.setName .." {"..treeLinkId.."}")
			end
		end
	end

	-- giving the options unique formatting so it can not match with user-created sets
	t_insert(filteredList, "^7^7-----")
	t_insert(filteredList, "^7^7New Loadout")
	t_insert(filteredList, "^7^7Sync")
	t_insert(filteredList, "^7^7Help >>")

	if #filteredList > 0 then
		self.controls.buildLoadouts.list = filteredList
	end

	-- Try to select loadout in dropdown based on currently selected tree
	if self.treeTab then
		local treeName = self.treeTab.specList[self.treeTab.activeSpec].title or "Default"
		for i, loadout in ipairs(filteredList) do
			if loadout == treeName then
				local linkMatch = string.match(treeName, "%{(%w+)%}") or treeName
				if linkMatch then
					local skillName = self.skillsTab.skillSets[self.skillsTab.activeSkillSetId].title or "Default"
					local skillMatch = oneSkill or skillName:find(linkMatch, 1, true)
					local itemName = self.itemsTab.itemSets[self.itemsTab.activeItemSetId].title or "Default"
					local itemMatch = oneItem or itemName:find(linkMatch, 1, true)
					local configName = self.configTab.configSets[self.configTab.activeConfigSetId].title or "Default"
					local configMatch = oneConfig or configName:find(linkMatch, 1, true)

					if skillMatch and itemMatch and configMatch then
						self.controls.buildLoadouts:SetSel(i)
						return treeList, itemList, skillList, configList
					end
				end
				break
			end
		end
	end

	self.controls.buildLoadouts:SetSel(1)
	return treeList, itemList, skillList, configList
end

function buildMode:EstimatePlayerProgress()
	local PointsUsed, AscUsed, SecondaryAscUsed = self.spec:CountAllocNodes()
	local extra = self.calcsTab.mainOutput and self.calcsTab.mainOutput.ExtraPoints or 0
	local usedMax, ascMax, secondaryAscMax, level, act = 99 + 23 + extra, 8, 8, 1, 0

	-- Find estimated act and level based on points used
	repeat
		act = act + 1
		level = m_min(m_max(PointsUsed + 1 - acts[act].questPoints - actExtra(act, extra), acts[act].level), 100)
	until act == 11 or level <= acts[act + 1].level
	
	if self.characterLevelAutoMode and self.characterLevel ~= level then
		self.characterLevel = level
		self.controls.characterLevel:SetText(self.characterLevel)
		self.configTab:BuildModList()
	end

	-- Ascendancy points for lab
	-- this is a recommendation for beginners who are using Path of Building for the first time and trying to map out progress in PoB
	local labSuggest = level < 33 and ""
		or level < 55 and "\nLabyrinth: Normal Lab"
		or level < 68 and "\nLabyrinth: Cruel Lab"
		or level < 75 and "\nLabyrinth: Merciless Lab"
		or level < 90 and "\nLabyrinth: Uber Lab"
		or ""
	
	if PointsUsed > usedMax then InsertIfNew(self.controls.warnings.lines, "You have too many passive points allocated") end
	if AscUsed > ascMax then InsertIfNew(self.controls.warnings.lines, "You have too many ascendancy points allocated") end
	if SecondaryAscUsed > secondaryAscMax then InsertIfNew(self.controls.warnings.lines, "You have too many secondary ascendancy points allocated") end
	self.Act = level < 90 and act <= 10 and act or "Endgame"
	
	return string.format("%s%3d / %3d   %s%d / %d", PointsUsed > usedMax and colorCodes.NEGATIVE or "^7", PointsUsed, usedMax, AscUsed > ascMax and colorCodes.NEGATIVE or "^7", AscUsed, ascMax),
		"Required Level: "..level.."\nEstimated Progress:\nAct: "..self.Act.."\nQuestpoints: "..acts[act].questPoints.."\nExtra Skillpoints: "..actExtra(act, extra)..labSuggest
end

function buildMode:CanExit(mode)
	if not self.unsaved then
		return true
	end
	self:OpenSavePopup(mode)
	return false
end

function buildMode:Shutdown()
	if launch.devMode and (not main.disableDevAutoSave) and self.targetVersion and not self.abortSave then
		if self.dbFileName then
			self:SaveDBFile()
		elseif self.unsaved then		
			self.dbFileName = main.buildPath.."~~temp~~.xml"
			self.buildName = "~~temp~~"
			self.dbFileSubPath = ""
			self:SaveDBFile()
		end
	end
	self.abortSave = nil

	self.savers = nil
end

function buildMode:GetArgs()
	return self.dbFileName, self.buildName
end

function buildMode:CloseBuild()
	main:SetWindowTitleSubtext()
	main:SetMode("LIST", self.dbFileName and self.buildName, self.dbFileSubPath)
end

function buildMode:Load(xml, fileName)
	self.targetVersion = xml.attrib.targetVersion or legacyTargetVersion
	if xml.attrib.viewMode then
		self.viewMode = xml.attrib.viewMode
	end
	self.characterLevel = tonumber(xml.attrib.level) or 1
	self.characterLevelAutoMode = xml.attrib.characterLevelAutoMode == "true"
	for _, diff in pairs({ "bandit", "pantheonMajorGod", "pantheonMinorGod" }) do
		self[diff] = xml.attrib[diff] or "None"
	end
	self.mainSocketGroup = tonumber(xml.attrib.mainSkillIndex) or tonumber(xml.attrib.mainSocketGroup) or 1
	wipeTable(self.spectreList)
	for _, child in ipairs(xml) do
		if child.elem == "Spectre" then
			if child.attrib.id and data.minions[child.attrib.id] then
				t_insert(self.spectreList, child.attrib.id)
			end
		elseif child.elem == "TimelessData" then
			self.timelessData.jewelType = {
				id = tonumber(child.attrib.jewelTypeId)
			}
			self.timelessData.conquerorType = {
				id = tonumber(child.attrib.conquerorTypeId)
			}
			self.timelessData.devotionVariant1 = tonumber(child.attrib.devotionVariant1) or 1
			self.timelessData.devotionVariant2 = tonumber(child.attrib.devotionVariant2) or 1
			self.timelessData.jewelSocket = {
				id = tonumber(child.attrib.jewelSocketId)
			}
			self.timelessData.fallbackWeightMode = {
				idx = tonumber(child.attrib.fallbackWeightModeIdx)
			}
			self.timelessData.socketFilter = child.attrib.socketFilter == "true"
			self.timelessData.socketFilterDistance = tonumber(child.attrib.socketFilterDistance) or 0
			self.timelessData.searchList = child.attrib.searchList
			self.timelessData.searchListFallback = child.attrib.searchListFallback
		end
	end
end

function buildMode:Save(xml)
	xml.attrib = {
		targetVersion = self.targetVersion,
		viewMode = self.viewMode,
		level = tostring(self.characterLevel),
		className = self.spec.curClassName,
		ascendClassName = self.spec.curAscendClassName,
		bandit = self.configTab.input.bandit,
		pantheonMajorGod = self.configTab.input.pantheonMajorGod,
		pantheonMinorGod = self.configTab.input.pantheonMinorGod,
		mainSocketGroup = tostring(self.mainSocketGroup),
		characterLevelAutoMode = tostring(self.characterLevelAutoMode)
	}
	for _, id in ipairs(self.spectreList) do
		t_insert(xml, { elem = "Spectre", attrib = { id = id } })
	end
	local addedStatNames = { }
	for index, statData in ipairs(self.displayStats) do
		if matchFlags(statData.flag, statData.notFlag, self.calcsTab.mainEnv.player.mainSkill.skillFlags) then
			local statName = statData.stat and statData.stat..(statData.childStat or "")
			if statName and not addedStatNames[statName] then
				if statData.stat == "SkillDPS" then
					local statVal = self.calcsTab.mainOutput[statData.stat]
					for _, skillData in ipairs(statVal) do
						local triggerStr = ""
						if skillData.trigger and skillData.trigger ~= "" then
							triggerStr = skillData.trigger
						end
						local lhsString = skillData.name
						if skillData.count >= 2 then
							lhsString = tostring(skillData.count).."x "..skillData.name
						end
						t_insert(xml, { elem = "FullDPSSkill", attrib = { stat = lhsString, value = tostring(skillData.dps * skillData.count), skillPart = skillData.skillPart or "", source = skillData.source or skillData.trigger or "" } })
					end
					addedStatNames[statName] = true
				else
					local statVal = self.calcsTab.mainOutput[statData.stat]
					if statVal and statData.childStat then
						statVal = statVal[statData.childStat]
					end
					if statVal and (statData.condFunc and statData.condFunc(statVal, self.calcsTab.mainOutput) or true) then
						t_insert(xml, { elem = "PlayerStat", attrib = { stat = statName, value = tostring(statVal) } })
						addedStatNames[statName] = true
					end
				end
			end
		end
	end
	for index, stat in ipairs(self.extraSaveStats) do
		local statVal = self.calcsTab.mainOutput[stat]
		if statVal then
			t_insert(xml, { elem = "PlayerStat", attrib = { stat = stat, value = tostring(statVal) } })
		end
	end
	if self.calcsTab.mainEnv.minion then
		for index, statData in ipairs(self.minionDisplayStats) do
			if statData.stat then
				local statVal = self.calcsTab.mainOutput.Minion[statData.stat]
				if statVal then
					t_insert(xml, { elem = "MinionStat", attrib = { stat = statData.stat, value = tostring(statVal) } })
				end
			end
		end
	end
	local timelessData = {
		elem = "TimelessData",
		attrib = {
			jewelTypeId = next(self.timelessData.jewelType) and tostring(self.timelessData.jewelType.id),
			conquerorTypeId = next(self.timelessData.conquerorType) and tostring(self.timelessData.conquerorType.id),
			devotionVariant1 = tostring(self.timelessData.devotionVariant1),
			devotionVariant2 = tostring(self.timelessData.devotionVariant2),
			jewelSocketId = next(self.timelessData.jewelSocket) and tostring(self.timelessData.jewelSocket.id),
			fallbackWeightModeIdx = next(self.timelessData.fallbackWeightMode) and tostring(self.timelessData.fallbackWeightMode.idx),
			socketFilter = self.timelessData.socketFilter and "true",
			socketFilterDistance = self.timelessData.socketFilterDistance and tostring(self.timelessData.socketFilterDistance),
			searchList = self.timelessData.searchList and tostring(self.timelessData.searchList),
			searchListFallback = self.timelessData.searchListFallback and tostring(self.timelessData.searchListFallback)
		}
	}
	t_insert(xml, timelessData)
end

function buildMode:ResetModFlags()
	self.modFlag = false
	self.notesTab.modFlag = false
	self.partyTab.modFlag = false
	self.configTab.modFlag = false
	self.treeTab.modFlag = false
	self.treeTab.searchFlag = false
	self.spec.modFlag = false
	self.skillsTab.modFlag = false
	self.itemsTab.modFlag = false
	self.calcsTab.modFlag = false
end

function buildMode:OnFrame(inputEvents)
	-- Stop at drawing the background if the loaded build needs to be converted
	if not self.targetVersion then
		main:DrawBackground(main.viewPort)
		return
	end

	if self.abortSave and not launch.devMode then
		self:CloseBuild()
	end

	for id, event in ipairs(inputEvents) do
		if event.type == "KeyDown" then
			if event.key == "MOUSE4" then
				if self.unsaved then
					self:OpenSavePopup("LIST")
				else
					self:CloseBuild()
				end
		elseif IsKeyDown("CTRL") then
				if event.key == "i" then
						self.viewMode = "IMPORT"
					self.importTab:SelectControl(self.importTab.controls.importCodeIn)
				elseif event.key == "s" then
					self:SaveDBFile()
					inputEvents[id] = nil
				elseif event.key == "w" then
					if self.unsaved then
						self:OpenSavePopup("LIST")
					else
						self:CloseBuild()
					end
				elseif event.key == "1" then
					self.viewMode = "TREE"
				elseif event.key == "2" then
					self.viewMode = "SKILLS"
				elseif event.key == "3" then
					self.viewMode = "ITEMS"
				elseif event.key == "4" then
					self.viewMode = "CALCS"
				elseif event.key == "5" then
					self.viewMode = "CONFIG"
				elseif event.key == "6" then
					self.viewMode = "NOTES"
				elseif event.key == "7" then
					self.viewMode = "PARTY"
				end
			end
		end
	end
	self:ProcessControlsInput(inputEvents, main.viewPort)

	self.controls.classDrop:SelByValue(self.spec.curClassId, "classId")
	self.controls.ascendDrop.list = self.controls.classDrop:GetSelValueByKey("ascendancies")
	self.controls.ascendDrop:SelByValue(self.spec.curAscendClassId, "ascendClassId")
	self.controls.ascendDrop:CheckDroppedWidth(true)
	-- // secondaryAscend dropdown hidden away until we learn more
	--self.controls.secondaryAscendDrop.list = {{label = "None", ascendClassId = 0}, {label = "Warden", ascendClassId = 1}, {label = "Warlock", ascendClassId = 2}, {label = "Primalist", ascendClassId = 3}}
	--self.controls.secondaryAscendDrop:SelByValue(self.spec.curSecondaryAscendClassId, "ascendClassId")

	if self.buildFlag then
		-- Wipe Global Cache
		wipeGlobalCache()

		-- Rebuild calculation output tables
		self.outputRevision = self.outputRevision + 1
		self.buildFlag = false
		self.calcsTab:BuildOutput()
		self:RefreshStatList()
	end
	if main.showThousandsSeparators ~= self.lastShowThousandsSeparators then
		self:RefreshStatList()
	end
	if main.thousandsSeparator ~= self.lastShowThousandsSeparator then
		self:RefreshStatList()
	end
	if main.decimalSeparator ~= self.lastShowDecimalSeparator then
		self:RefreshStatList()
	end
	if main.showTitlebarName ~= self.lastShowTitlebarName then
		self.spec:SetWindowTitleWithBuildClass()
	end

	-- Update contents of main skill dropdowns
	self:RefreshSkillSelectControls(self.controls, self.mainSocketGroup, "")

	-- Draw contents of current tab
	local sideBarWidth = 312
	local tabViewPort = {
		x = sideBarWidth,
		y = 32,
		width = main.screenW - sideBarWidth,
		height = main.screenH - 32
	}
	if self.viewMode == "IMPORT" then
		self.importTab:Draw(tabViewPort, inputEvents)  
	elseif self.viewMode == "NOTES" then
		self.notesTab:Draw(tabViewPort, inputEvents)
	elseif self.viewMode == "PARTY" then
		self.partyTab:Draw(tabViewPort, inputEvents)
	elseif self.viewMode == "CONFIG" then
		self.configTab:Draw(tabViewPort, inputEvents)
	elseif self.viewMode == "TREE" then
		self.treeTab:Draw(tabViewPort, inputEvents)
	elseif self.viewMode == "SKILLS" then
		self.skillsTab:Draw(tabViewPort, inputEvents)
	elseif self.viewMode == "ITEMS" then
		self.itemsTab:Draw(tabViewPort, inputEvents)
	elseif self.viewMode == "CALCS" then
		self.calcsTab:Draw(tabViewPort, inputEvents)
	end

	self.unsaved = self.modFlag or self.notesTab.modFlag or self.partyTab.modFlag or self.configTab.modFlag or self.treeTab.modFlag or self.treeTab.searchFlag or self.spec.modFlag or self.skillsTab.modFlag or self.itemsTab.modFlag or self.calcsTab.modFlag

	SetDrawLayer(5)

	-- Draw top bar background
	SetDrawColor(0.2, 0.2, 0.2)
	DrawImage(nil, 0, 0, main.screenW, 28)
	SetDrawColor(0.85, 0.85, 0.85)
	DrawImage(nil, 0, 28, main.screenW, 4)
	DrawImage(nil, main.screenW/2 - 2, 0, 4, 28)

	-- Draw side bar background
	SetDrawColor(0.1, 0.1, 0.1)
	DrawImage(nil, 0, 32, sideBarWidth - 4, main.screenH - 32)
	SetDrawColor(0.85, 0.85, 0.85)
	DrawImage(nil, sideBarWidth - 4, 32, 4, main.screenH - 32)

	self:DrawControls(main.viewPort)
end

-- Opens the game version conversion popup
function buildMode:OpenConversionPopup()
	local controls = { }
	local currentVersion = treeVersions[latestTreeVersion].display
	controls.note = new("LabelControl", nil, {0, 20, 0, 16}, colorCodes.TIP..[[
Info:^7 You are trying to load a build created for a version of Path of Exile that is
not supported by us. You will have to convert it to the current game version to load it.
To use a build newer than the current supported game version, you may have to update.
To use a build older than the current supported game version, we recommend loading it
in an older version of Path of Building Community instead.
]])
	controls.label = new("LabelControl", nil, {0, 110, 0, 16}, colorCodes.WARNING..[[
Warning:^7 Converting a build to a different game version may have side effects.
For example, if the passive tree has changed, then some passives may be deallocated.
You should create a backup copy of the build before proceeding.
]])
	controls.convert = new("ButtonControl", nil, {-40, 170, 120, 20}, "Convert to ".. currentVersion, function()
		main:ClosePopup()
		self:Shutdown()
		self:Init(self.dbFileName, self.buildName, nil, true)
	end)
	controls.cancel = new("ButtonControl", nil, {60, 170, 70, 20}, "Cancel", function()
		main:ClosePopup()
		self:CloseBuild()
	end)
	main:OpenPopup(580, 200, "Game Version", controls, "convert", nil, "cancel")
end

function buildMode:OpenSavePopup(mode)
	local modeDesc = {
		["LIST"] = "now?",
		["EXIT"] = "before exiting?",
		["UPDATE"] = "before updating?",
	}
	local controls = { }
	controls.label = new("LabelControl", nil, {0, 20, 0, 16}, "^7This build has unsaved changes.\nDo you want to save them "..modeDesc[mode])
	controls.save = new("ButtonControl", nil, {-90, 70, 80, 20}, "Save", function()
		main:ClosePopup()
		self.actionOnSave = mode
		self:SaveDBFile()
	end)
	controls.noSave = new("ButtonControl", nil, {0, 70, 80, 20}, "Don't Save", function()
		main:ClosePopup()
		if mode == "LIST" then
			self:CloseBuild()
		elseif mode == "EXIT" then
			Exit()
		elseif mode == "UPDATE" then
			launch:ApplyUpdate(launch.updateAvailable)
		end
	end)
	controls.close = new("ButtonControl", nil, {90, 70, 80, 20}, "Cancel", function()
		main:ClosePopup()
	end)
	main:OpenPopup(300, 100, "Save Changes", controls)
end

function buildMode:OpenSaveAsPopup()
	local newFileName, newBuildName
	local controls = { }
	local function updateBuildName()
		local buf = controls.edit.buf
		newFileName = main.buildPath..controls.folder.subPath..buf..".xml"
		newBuildName = buf
		controls.save.enabled = false
		if buf:match("%S") then
			local out = io.open(newFileName, "r")
			if out then
				out:close()
			else
				controls.save.enabled = true
			end
		end
	end
	controls.label = new("LabelControl", nil, {0, 20, 0, 16}, "^7Enter new build name:")
	controls.edit = new("EditControl", nil, {0, 40, 450, 20},
	not self.dbFileName and main.predefinedBuildName or (self.buildName or self.dbFileName):gsub("[\\/:%*%?\"<>|%c]", "-"), nil, "\\/:%*%?\"<>|%c", 100, function(buf)
		updateBuildName()
	end)
	controls.folderLabel = new("LabelControl", {"TOPLEFT",nil,"TOPLEFT"}, {10, 70, 0, 16}, "^7Folder:")
	controls.newFolder = new("ButtonControl", {"TOPLEFT",nil,"TOPLEFT"}, {100, 67, 94, 20}, "New Folder...", function()
		main:OpenNewFolderPopup(main.buildPath..controls.folder.subPath, function(newFolderName)
			if newFolderName then
				controls.folder:OpenFolder(newFolderName)
			end
		end)
	end)
	controls.folder = new("FolderListControl", nil, {0, 115, 450, 100}, self.dbFileSubPath, function(subPath)
		updateBuildName()
	end)
	controls.save = new("ButtonControl", nil, {-45, 225, 80, 20}, "Save", function()
		main:ClosePopup()
		self.dbFileName = newFileName
		self.buildName = newBuildName
		self.dbFileSubPath = controls.folder.subPath
		self:SaveDBFile()
		self.spec:SetWindowTitleWithBuildClass()
	end)
	controls.close = new("ButtonControl", nil, {45, 225, 80, 20}, "Cancel", function()
		main:ClosePopup()
		self.actionOnSave = nil
	end)

	if self.dbFileName or self.buildName then
		controls.save.enabled = self.dbFileName or self.buildName
		updateBuildName()
	else
		controls.save.enabled = false
	end

	main:OpenPopup(470, 255, self.dbFileName and "Save As" or "Save", controls, "save", "edit", "close")
end

-- Open the spectre library popup
function buildMode:OpenSpectreLibrary()
	local destList = copyTable(self.spectreList)
	local sourceList = { }
	for id in pairs(self.data.spectres) do
		t_insert(sourceList, id)
	end
	table.sort(sourceList, function(a,b) 
		if self.data.minions[a].name == self.data.minions[b].name then
			return a < b
		else
			return self.data.minions[a].name < self.data.minions[b].name
		end
	end)
	local controls = { }
	controls.list = new("MinionListControl", nil, {-100, 40, 190, 250}, self.data, destList)
	controls.source = new("MinionSearchListControl", nil, {100, 60, 190, 230}, self.data, sourceList, controls.list)
	controls.save = new("ButtonControl", nil, {-45, 330, 80, 20}, "Save", function()
		self.spectreList = destList
		self.modFlag = true
		self.buildFlag = true
		main:ClosePopup()
	end)
	controls.cancel = new("ButtonControl", nil, {45, 330, 80, 20}, "Cancel", function()
		main:ClosePopup()
	end)
	controls.noteLine1 = new("LabelControl", {"TOPLEFT",controls.list,"BOTTOMLEFT"}, {24, 2, 0, 16}, "Spectres in your Library must be assigned to an active")
	controls.noteLine2 = new("LabelControl", {"TOPLEFT",controls.list,"BOTTOMLEFT"}, {20, 18, 0, 16}, "Raise Spectre gem for their buffs and curses to activate")
	local spectrePopup = main:OpenPopup(410, 360, "Spectre Library", controls)
	spectrePopup:SelectControl(spectrePopup.controls.source.controls.searchText)
end

function buildMode:UpdateClassDropdowns(treeVersion)
	local classes = main.tree[treeVersion or latestTreeVersion].classes
	wipeTable(self.controls.classDrop.list)
	-- Initialise class dropdown
	for classId, class in pairs(classes) do
		local ascendancies = {}
		-- Initialise ascendancy dropdown
		for i = 0, #class.classes do
			local ascendClass = class.classes[i]
			t_insert(ascendancies, {
				label = ascendClass.name,
				ascendClassId = i,
			})
		end
		t_insert(self.controls.classDrop.list, {
			label = class.name,
			classId = classId,
			ascendancies = ascendancies,
		})
	end
	table.sort(self.controls.classDrop.list, function(a, b) return a.label < b.label end)
end

function buildMode:OpenSimilarPopup()
	local controls = { }
	-- local width, height = self:GetSize()
	local buildProviders = {
		{
			name = "PoB Archives",
			impl = new("PoBArchivesProvider", "similar")
		}
	}
	local width = 600
	local height = function()
		return main.screenH * 0.8
	end
	local padding = 50
	controls.similarBuildList = new("ExtBuildListControl", nil, {0, padding, width, height() - 2 * padding}, buildProviders)
	controls.similarBuildList.shown = true
	controls.similarBuildList.height = function()
		return height() - 2 * padding
	end
	controls.similarBuildList.width = function ()
		return width - padding
	end
	controls.similarBuildList:SetImportCode(common.base64.encode(Deflate(self:SaveDB("code"))):gsub("+","-"):gsub("/","_"))
	controls.similarBuildList:Init("PoB Archives")

	-- controls.similarBuildList.shown = not controls.similarBuildList:IsShown()

	controls.close = new("ButtonControl", nil, {0, height() - (padding + 20) / 2, 80, 20}, "Close", function()
		main:ClosePopup()
	end)
	-- used in PopupDialog to dynamically size the popup
	local function resizeFunc()
		main.popups[1].height = height()
		main.popups[1].y = function()
			return m_floor((main.screenH - height()) / 2)
		end
		controls.close.y = height() - 35
	end
	main:OpenPopup(width, height(), "Similar Builds", controls, nil, nil, nil, nil, resizeFunc)
end

-- Refresh the set of controls used to select main group/skill/minion
function buildMode:RefreshSkillSelectControls(controls, mainGroup, suffix)
	controls.mainSocketGroup.selIndex = mainGroup
	wipeTable(controls.mainSocketGroup.list)
	for i, socketGroup in pairs(self.skillsTab.socketGroupList) do
		controls.mainSocketGroup.list[i] = { val = i, label = socketGroup.displayLabel }
	end
  controls.mainSocketGroup:CheckDroppedWidth(true)
	if controls.warnings then controls.warnings.shown = #controls.warnings.lines > 0 end
	if #controls.mainSocketGroup.list == 0 then
		controls.mainSocketGroup.list[1] = { val = 1, label = "<No skills added yet>" }
		controls.mainSkill.shown = false
		controls.mainSkillPart.shown = false
		controls.mainSkillMineCount.shown = false
		controls.mainSkillStageCount.shown = false
		controls.mainSkillMinion.shown = false
		controls.mainSkillMinionSkill.shown = false
	else
		local mainSocketGroup = self.skillsTab.socketGroupList[mainGroup]
		local displaySkillList = mainSocketGroup["displaySkillList"..suffix]
		local mainActiveSkill = mainSocketGroup["mainActiveSkill"..suffix] or 1
		wipeTable(controls.mainSkill.list)
		for i, activeSkill in ipairs(displaySkillList) do
			local explodeSource = activeSkill.activeEffect.srcInstance.explodeSource
			local explodeSourceName = explodeSource and (explodeSource.name or explodeSource.dn)
			local colourCoded = explodeSourceName and ("From "..colorCodes[explodeSource.rarity or "NORMAL"]..explodeSourceName)
			t_insert(controls.mainSkill.list, { val = i, label = colourCoded or activeSkill.activeEffect.grantedEffect.name })
		end
		controls.mainSkill.enabled = #displaySkillList > 1
		controls.mainSkill.selIndex = mainActiveSkill
		controls.mainSkill.shown = true
		controls.mainSkillPart.shown = false
		controls.mainSkillMineCount.shown = false
		controls.mainSkillStageCount.shown = false
		controls.mainSkillMinion.shown = false
		controls.mainSkillMinionLibrary.shown = false
		controls.mainSkillMinionSkill.shown = false
		if displaySkillList[1] then
			local activeSkill = displaySkillList[mainActiveSkill]
			local activeEffect = activeSkill.activeEffect
			if activeEffect then
				if activeEffect.grantedEffect.parts and #activeEffect.grantedEffect.parts > 1 then
					controls.mainSkillPart.shown = true
					wipeTable(controls.mainSkillPart.list)
					for i, part in ipairs(activeEffect.grantedEffect.parts) do
						t_insert(controls.mainSkillPart.list, { val = i, label = part.name })
					end
					controls.mainSkillPart.selIndex = activeEffect.srcInstance["skillPart"..suffix] or 1
					if activeEffect.grantedEffect.parts[controls.mainSkillPart.selIndex].stages then
						controls.mainSkillStageCount.shown = true
						controls.mainSkillStageCount.buf = tostring(activeEffect.srcInstance["skillStageCount"..suffix] or activeEffect.grantedEffect.parts[controls.mainSkillPart.selIndex].stagesMin or 1)
					end
				end
				if activeSkill.skillFlags.mine then
					controls.mainSkillMineCount.shown = true
					controls.mainSkillMineCount.buf = tostring(activeEffect.srcInstance["skillMineCount"..suffix] or "")
				end
				if activeSkill.skillFlags.multiStage and not (activeEffect.grantedEffect.parts and #activeEffect.grantedEffect.parts > 1) then
					controls.mainSkillStageCount.shown = true
					controls.mainSkillStageCount.buf = tostring(activeEffect.srcInstance["skillStageCount"..suffix] or activeSkill.skillData.stagesMin or 1)
				end
				if not activeSkill.skillFlags.disable and (activeEffect.grantedEffect.minionList or activeSkill.minionList[1]) then
					wipeTable(controls.mainSkillMinion.list)
					if activeEffect.grantedEffect.minionHasItemSet then
						for _, itemSetId in ipairs(self.itemsTab.itemSetOrderList) do
							local itemSet = self.itemsTab.itemSets[itemSetId]
							t_insert(controls.mainSkillMinion.list, {
								label = itemSet.title or "Default Item Set",
								itemSetId = itemSetId,
							})
						end
						controls.mainSkillMinion:SelByValue(activeEffect.srcInstance["skillMinionItemSet"..suffix] or 1, "itemSetId")
					else
						controls.mainSkillMinionLibrary.shown = (activeEffect.grantedEffect.minionList and not activeEffect.grantedEffect.minionList[1])
						for _, minionId in ipairs(activeSkill.minionList) do
							t_insert(controls.mainSkillMinion.list, {
								label = self.data.minions[minionId].name,
								minionId = minionId,
							})
						end
						controls.mainSkillMinion:SelByValue(activeEffect.srcInstance["skillMinion"..suffix] or controls.mainSkillMinion.list[1], "minionId")
					end
					controls.mainSkillMinion.enabled = #controls.mainSkillMinion.list > 1
					controls.mainSkillMinion.shown = true
					wipeTable(controls.mainSkillMinionSkill.list)
					if activeSkill.minion then
						for _, minionSkill in ipairs(activeSkill.minion.activeSkillList) do
							t_insert(controls.mainSkillMinionSkill.list, minionSkill.activeEffect.grantedEffect.name)
						end
						controls.mainSkillMinionSkill.selIndex = activeEffect.srcInstance["skillMinionSkill"..suffix] or 1
						controls.mainSkillMinionSkill.shown = true
						controls.mainSkillMinionSkill.enabled = #controls.mainSkillMinionSkill.list > 1
					else
						t_insert(controls.mainSkillMinion.list, "<No spectres in build>")
					end
				end
			end
		end
	end
end

function buildMode:FormatStat(statData, statVal, overCapStatVal, colorOverride)
	if type(statVal) == "table" then return "" end
	local val = statVal * ((statData.pc or statData.mod) and 100 or 1) - (statData.mod and 100 or 0)
	local color = colorOverride or (statVal >= 0 and "^7" or statData.chaosInoc and "^8" or colorCodes.NEGATIVE)
	if statData.label == "Unreserved Life" and statVal == 0 then
		color = colorCodes.NEGATIVE
	end
	
	local valStr = s_format("%"..statData.fmt, val)
	valStr:gsub("%.", main.decimalSeparator)
	valStr = color .. formatNumSep(valStr)

	if overCapStatVal and overCapStatVal > 0 then
		valStr = valStr .. "^x808080" .. " (+" .. s_format("%d", overCapStatVal) .. "%)"
	end
	self.lastShowThousandsSeparators = main.showThousandsSeparators
	self.lastShowThousandsSeparator = main.thousandsSeparator
	self.lastShowDecimalSeparator = main.decimalSeparator
	self.lastShowTitlebarName = main.showTitlebarName
	return valStr
end

-- Add stat list for given actor
function buildMode:AddDisplayStatList(statList, actor)
	local statBoxList = self.controls.statBox.list
	for index, statData in ipairs(statList) do
		if matchFlags(statData.flag, statData.notFlag, actor.mainSkill.skillFlags) then
			local labelColor = "^7"
			if statData.color then
				labelColor = statData.color
			end
			if statData.stat then
				local statVal = actor.output[statData.stat]
				-- access output values that are one node deeper (statData.stat is a table e.g. output.MainHand.Accuracy vs output.Life)
				if statVal and statData.childStat then
					statVal = statVal[statData.childStat]
				end
				if statVal and ((statData.condFunc and statData.condFunc(statVal,actor.output)) or (not statData.condFunc and statVal ~= 0)) then
					local overCapStatVal = actor.output[statData.overCapStat] or nil
					if statData.stat == "SkillDPS" then
						labelColor = colorCodes.CUSTOM
						table.sort(actor.output.SkillDPS, function(a,b) return (a.dps * a.count) > (b.dps * b.count) end)
						for _, skillData in ipairs(actor.output.SkillDPS) do
							local triggerStr = ""
							if skillData.trigger and skillData.trigger ~= "" then
								triggerStr = colorCodes.WARNING.." ("..skillData.trigger..")"..labelColor
							end
							local lhsString = labelColor..skillData.name..triggerStr..":"
							if skillData.count >= 2 then
								lhsString = labelColor..tostring(skillData.count).."x "..skillData.name..triggerStr..":"
							end
							t_insert(statBoxList, {
								height = 16,
								lhsString,
								self:FormatStat({fmt = "1.f"}, skillData.dps * skillData.count, overCapStatVal),
							})
							if skillData.skillPart then
								t_insert(statBoxList, {
									height = 14,
									align = "CENTER_X", x = 140,
									"^8"..skillData.skillPart,
								})
							end
							if skillData.source then
								t_insert(statBoxList, {
									height = 14,
									align = "CENTER_X", x = 140,
									colorCodes.WARNING.."from " ..skillData.source,
								})
							end
						end
					elseif not (statData.hideStat) then
						-- Change the color of the stat label to red if cost exceeds pool
						local colorOverride = nil
						if actor.output[statData.stat.."Warning"] or (statData.warnFunc and statData.warnFunc(statVal, actor.output) and statData.warnColor) then
							colorOverride = colorCodes.NEGATIVE
						end
						t_insert(statBoxList, {
							height = 16,
							labelColor..statData.label..":",
							self:FormatStat(statData, statVal, overCapStatVal, colorOverride),
						})
					end
				end
				if statData.warnFunc and statVal and ((statData.condFunc and statData.condFunc(statVal, actor.output)) or not statData.condFunc) then
					local v = statData.warnFunc(statVal, actor.output)
					if v then
						InsertIfNew(self.controls.warnings.lines, v)
					end
				end
			elseif statData.label and statData.condFunc and statData.condFunc(actor.output) then
				t_insert(statBoxList, { 
					height = 16, labelColor..statData.label..":", 
					"^7"..actor.output[statData.labelStat].."%^x808080" .. " (" .. statData.val  .. ")",})
			elseif not statBoxList[#statBoxList] or statBoxList[#statBoxList][1] then
				t_insert(statBoxList, { height = 6 })
			end
		end
	end
	for pool, warningFlag in pairs({["Life"] = "LifeCostWarning", ["Mana"] = "ManaCostWarning", ["Rage"] = "RageCostWarning", ["Energy Shield"] = "ESCostWarning"}) do
		if actor.output[warningFlag] then
			local line = "You do not have enough "..(actor.output.EnergyShieldProtectsMana and pool == "Mana" and "Energy Shield and Mana" or pool).." to use: "
			for _, skill in ipairs(actor.output[warningFlag]) do
				line = line..skill..", "
			end
			line = line:sub(1, -3)
			InsertIfNew(self.controls.warnings.lines, line)
		end
	end
	for pool, warningFlag in pairs({["Unreserved life"] = "LifePercentCostPercentCostWarning", ["Unreserved Mana"] = "ManaPercentCostPercentCostWarning"}) do
		if actor.output[warningFlag] then
			local line = "You do not have enough ".. pool .."% to use: "
			for _, skill in ipairs(actor.output[warningFlag]) do
				line = line..skill..", "
			end
			line = line:sub(1, -3)
			InsertIfNew(self.controls.warnings.lines, line)
		end
	end
	if actor.output.VixensTooMuchCastSpeedWarn then
		InsertIfNew(self.controls.warnings.lines, "You may have too much cast speed or too little cooldown reduction to effectively use Vixen's Curse replacement")
	end
	if actor.output.VixenModeNoVixenGlovesWarn then
		InsertIfNew(self.controls.warnings.lines, "Vixen's calculation mode for Doom Blast is selected but you do not have Vixen's Entrapment Embroidered Gloves equipped")
	end

	do
		local aspectCount = 0
		aspectCount = aspectCount + (actor.output.CrabBarriersMax > 0 and actor.output.CrabBarriers > 0 and 1 or 0)
		aspectCount = aspectCount + (aspectCount < 2 and actor.modDB:Flag(nil, "Condition:AspectOfTheSpiderActive") and 1 or 0)
		aspectCount = aspectCount + (aspectCount < 2 and (actor.modDB:Flag(nil, "Condition:CatsAgilityActive") or actor.modDB:Flag(nil, "Condition:CatsStealthActive")) and 1 or 0)
		aspectCount = aspectCount + (aspectCount < 2 and (actor.modDB:Flag(nil, "Condition:AviansFlightActive") or actor.modDB:Flag(nil, "Condition:AviansMightActive")) and 1 or 0)
		if aspectCount > 1 then
			InsertIfNew(self.controls.warnings.lines, "You have more than one Aspect skill active")
		end
	end
end

function buildMode:InsertItemWarnings()
	if self.calcsTab.mainEnv.itemWarnings.jewelLimitWarning then
		for _, warning in ipairs(self.calcsTab.mainEnv.itemWarnings.jewelLimitWarning) do
			InsertIfNew(self.controls.warnings.lines, "You are exceeding jewel limit with the jewel "..warning)
		end
	end
	if self.calcsTab.mainEnv.itemWarnings.socketLimitWarning then
		for _, warning in ipairs(self.calcsTab.mainEnv.itemWarnings.socketLimitWarning) do
			InsertIfNew(self.controls.warnings.lines, "You have too many gems in your "..warning.." slot")
		end
	end
end

-- Build list of side bar stats
function buildMode:RefreshStatList()
	self.controls.warnings.lines = {}
	local statBoxList = wipeTable(self.controls.statBox.list)
	if self.calcsTab.mainEnv.player.mainSkill.infoMessage then
			if #self.calcsTab.mainEnv.player.mainSkill.infoMessage > 40 then
				for line in string.gmatch(self.calcsTab.mainEnv.player.mainSkill.infoMessage, "([^:]+)") do
					t_insert(statBoxList, { height = 14, align = "CENTER_X", x = 140, colorCodes.CUSTOM .. line})
				end
			else
				t_insert(statBoxList, { height = 14, align = "CENTER_X", x = 140, colorCodes.CUSTOM .. self.calcsTab.mainEnv.player.mainSkill.infoMessage})
			end
		if self.calcsTab.mainEnv.player.mainSkill.infoMessage2 then
			t_insert(statBoxList, { height = 14, align = "CENTER_X", x = 140, "^8" .. self.calcsTab.mainEnv.player.mainSkill.infoMessage2})
		end
	end
	if self.calcsTab.mainEnv.minion then
		t_insert(statBoxList, { height = 18, "^7Minion:" })
		if self.calcsTab.mainEnv.minion.mainSkill.infoMessage then
			-- Split the line if too long
			if #self.calcsTab.mainEnv.minion.mainSkill.infoMessage > 40 then
				for line in string.gmatch(self.calcsTab.mainEnv.minion.mainSkill.infoMessage, "([^:]+)") do
					t_insert(statBoxList, { height = 14, align = "CENTER_X", x = 140, colorCodes.CUSTOM .. line})
				end
			else
				t_insert(statBoxList, { height = 14, align = "CENTER_X", x = 140, colorCodes.CUSTOM .. self.calcsTab.mainEnv.minion.mainSkill.infoMessage})
			end
			if self.calcsTab.mainEnv.minion.mainSkill.infoMessage2 then
				t_insert(statBoxList, { height = 14, align = "CENTER_X", x = 140, "^8" .. self.calcsTab.mainEnv.minion.mainSkill.infoMessage2})
			end
		end
		self:AddDisplayStatList(self.minionDisplayStats, self.calcsTab.mainEnv.minion)
		t_insert(statBoxList, { height = 10 })
		t_insert(statBoxList, { height = 18, "^7Player:" })
	end
	if self.calcsTab.mainEnv.player.mainSkill.skillFlags.disable then
		t_insert(statBoxList, { height = 16, "^7Skill disabled:" })
		t_insert(statBoxList, { height = 14, align = "CENTER_X", x = 140, self.calcsTab.mainEnv.player.mainSkill.disableReason })
	end
	self:AddDisplayStatList(self.displayStats, self.calcsTab.mainEnv.player)
	self:InsertItemWarnings()
end

function buildMode:CompareStatList(tooltip, statList, actor, baseOutput, compareOutput, header, nodeCount)
	local count = 0
	for _, statData in ipairs(statList) do
		if statData.stat and matchFlags(statData.flag, statData.notFlag, actor.mainSkill.skillFlags) and not statData.childStat and statData.stat ~= "SkillDPS" then
			local statVal1 = compareOutput[statData.stat] or 0
			local statVal2 = baseOutput[statData.stat] or 0
			local diff = statVal1 - statVal2
			if statData.stat == "FullDPS" and not compareOutput[statData.stat] then
				diff = 0
			end
			if (diff > 0.001 or diff < -0.001) and (not statData.condFunc or statData.condFunc(statVal1,compareOutput) or statData.condFunc(statVal2,baseOutput)) then
				if count == 0 then
					tooltip:AddLine(14, header)
				end
				local color = ((statData.lowerIsBetter and diff < 0) or (not statData.lowerIsBetter and diff > 0)) and colorCodes.POSITIVE or colorCodes.NEGATIVE
				local val = diff * ((statData.pc or statData.mod) and 100 or 1)
				local valStr = s_format("%+"..statData.fmt, val) -- Can't use self:FormatStat, because it doesn't have %+. Adding that would have complicated a simple function

				valStr = formatNumSep(valStr)

				local line = s_format("%s%s %s", color, valStr, statData.label)
				local pcPerPt = ""
				if statData.compPercent and statVal1 ~= 0 and statVal2 ~= 0 then
					local pc = statVal1 / statVal2 * 100 - 100
					line = line .. s_format(" (%+.1f%%)", pc)
					if nodeCount then
						pcPerPt = s_format(" (%+.1f%%)", pc / nodeCount)
					end
				end
				if nodeCount then
					line = line .. s_format(" ^8[%+"..statData.fmt.."%s per point]", diff * ((statData.pc or statData.mod) and 100 or 1) / nodeCount, pcPerPt)
				end
				tooltip:AddLine(14, line)
				count = count + 1
			end
		end
	end
	return count
end

-- Compare values of all display stats between the two output tables, and add any changed stats to the tooltip
-- Adds the provided header line before the first stat line, if any are added
-- Returns the number of stat lines added
function buildMode:AddStatComparesToTooltip(tooltip, baseOutput, compareOutput, header, nodeCount)
	local count = 0
	if self.calcsTab.mainEnv.player.mainSkill.minion and baseOutput.Minion and compareOutput.Minion then
		count = count + self:CompareStatList(tooltip, self.minionDisplayStats, self.calcsTab.mainEnv.minion, baseOutput.Minion, compareOutput.Minion, header.."\n^7Minion:", nodeCount)
		if count > 0 then
			header = "^7Player:"
		else
			header = header.."\n^7Player:"
		end
	end
	count = count + self:CompareStatList(tooltip, self.displayStats, self.calcsTab.mainEnv.player, baseOutput, compareOutput, header, nodeCount)
	return count
end

-- Add requirements to tooltip
do
	local req = { }
	function buildMode:AddRequirementsToTooltip(tooltip, level, str, dex, int, strBase, dexBase, intBase)
		if level and level > 0 then
			t_insert(req, s_format("^x7F7F7FLevel %s%d", main:StatColor(level, nil, self.characterLevel), level))
		end
		-- Convert normal attributes to Omni attributes
		if self.calcsTab.mainEnv.modDB:Flag(nil, "OmniscienceRequirements") then
			local omniSatisfy = self.calcsTab.mainEnv.modDB:Sum("INC", nil, "OmniAttributeRequirements")
			local highestAttribute = 0
			for i, stat in ipairs({str, dex, int}) do
				if((stat or 0) > highestAttribute) then
					highestAttribute = stat
				end
			end
			local omni = math.floor(highestAttribute * (100/omniSatisfy))
			if omni and (omni > 0 or omni > self.calcsTab.mainOutput.Omni) then
				t_insert(req, s_format("%s%d ^x7F7F7FOmni", main:StatColor(omni, 0, self.calcsTab.mainOutput.Omni), omni))
			end
		else 
			if str and (str > 14 or str > self.calcsTab.mainOutput.Str) then
				t_insert(req, s_format("%s%d ^x7F7F7FStr", main:StatColor(str, strBase, self.calcsTab.mainOutput.Str), str))
			end
			if dex and (dex > 14 or dex > self.calcsTab.mainOutput.Dex) then
				t_insert(req, s_format("%s%d ^x7F7F7FDex", main:StatColor(dex, dexBase, self.calcsTab.mainOutput.Dex), dex))
			end
			if int and (int > 14 or int > self.calcsTab.mainOutput.Int) then
				t_insert(req, s_format("%s%d ^x7F7F7FInt", main:StatColor(int, intBase, self.calcsTab.mainOutput.Int), int))
			end
		end	
		if req[1] then
			tooltip:AddLine(16, "^x7F7F7FRequires "..table.concat(req, "^x7F7F7F, "))
			tooltip:AddSeparator(10)
		end	
		wipeTable(req)
	end
end

function buildMode:LoadDB(xmlText, fileName)
	-- Parse the XML
	local dbXML, errMsg = common.xml.ParseXML(xmlText)
	if not dbXML then
		launch:ShowErrMsg("^1Error loading '%s': %s", fileName, errMsg)
		return true
	elseif #dbXML == 0 then
		main:OpenMessagePopup("Error", "Build file is empty, or error parsing xml.\n\n"..fileName)
		return true
	elseif dbXML[1].elem ~= "PathOfBuilding" then
		launch:ShowErrMsg("^1Error parsing '%s': 'PathOfBuilding' root element missing", fileName)
		return true
	end

	-- Load Build section first
	for _, node in ipairs(dbXML[1]) do
		if type(node) == "table" and node.elem == "Build" then
			self:Load(node, self.dbFileName)
			break
		end
	end

	-- Check if xml has an import link
	for _, node in ipairs(dbXML[1]) do
		if type(node) == "table" and node.elem == "Import" then
			if node.attrib.importLink and not self.importLink then
				self.importLink = node.attrib.importLink
			end
			break
		end
	end

	-- Store other sections for later processing
	for _, node in ipairs(dbXML[1]) do
		if type(node) == "table" then
			t_insert(self.xmlSectionList, node)
		end
	end
end

function buildMode:LoadDBFile()
	if not self.dbFileName then
		return
	end
	ConPrintf("Loading '%s'...", self.dbFileName)
	local file = io.open(self.dbFileName, "r")
	if not file then
		self.dbFileName = nil
		return true
	end
	local xmlText = file:read("*a")
	file:close()
	return self:LoadDB(xmlText, self.dbFileName)
end

function buildMode:SaveDB(fileName)
	local dbXML = { elem = "PathOfBuilding" }

	-- Save Build section first
	do
		local node = { elem = "Build" }
		self:Save(node)
		t_insert(dbXML, node)
	end

	-- Call on all savers to save their data in their respective sections
	for elem, saver in pairs(self.savers) do
		local node = { elem = elem }
		saver:Save(node)
		t_insert(dbXML, node)
	end

	-- Compose the XML
	local xmlText, errMsg = common.xml.ComposeXML(dbXML)
	if not xmlText then
		launch:ShowErrMsg("Error saving '%s': %s", fileName, errMsg)
	else
		return xmlText
	end
end


function buildMode:SaveDBFile()
	if not self.dbFileName then
		self:OpenSaveAsPopup()
		return
	end
	local xmlText = self:SaveDB(self.dbFileName)
	if not xmlText then
		return true
	end
	local file = io.open(self.dbFileName, "w+")
	if not file then
		main:OpenMessagePopup("Error", "Couldn't save the build file:\n"..self.dbFileName.."\nMake sure the save folder exists and is writable.")
		return true
	end
	file:write(xmlText)
	file:close()
	local action = self.actionOnSave
	self.actionOnSave = nil

	-- Reset all modFlags
	self:ResetModFlags()

	if action == "LIST" then
		self:CloseBuild()
	elseif action == "EXIT" then
		Exit()
	elseif action == "UPDATE" then
		launch:ApplyUpdate(launch.updateAvailable)
	end
end

return buildMode
