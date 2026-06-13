-- don't load if class is wrong
local _, class = UnitClass("player")
if class ~= "PALADIN" then return end

local _, xmod = ...

xmod.retmodule = {}
xmod = xmod.retmodule

local qTaint = true -- will force queue check

-- thanks cremor
local GetTime, GetSpellCooldown, UnitBuff, UnitAura, UnitPower, UnitSpellHaste, UnitHealth, UnitHealthMax, GetTalentInfoByID, GetGlyphSocketInfo, IsUsableSpell, GetShapeshiftForm, max, min, SPELL_POWER_HOLY_POWER =
GetTime, GetSpellCooldown, UnitBuff, UnitAura, UnitPower, UnitSpellHaste, UnitHealth, UnitHealthMax, GetTalentInfoByID, GetGlyphSocketInfo, IsUsableSpell, GetShapeshiftForm, max, min, SPELL_POWER_HOLY_POWER
local db

-- debug if clcInfo detected
local debug
if clcInfo then debug = clcInfo.debug end

xmod.version = 5000001
xmod.defaults = {
	version = xmod.version,
	prio = "inq es tv hpr exo how cs j",
	rangePerSkill = false,
	howclash = 0, -- priority time for hammer of wrath
	csclash = 0, -- priority time for cs
	exoclash = 0, -- priority time for exorcism
	ssduration = 0, -- minimum duration on ss buff before suggesting refresh
}

-- @defines
--------------------------------------------------------------------------------
local idGCD = 85256

-- spells
local idCrusaderStrike = 35395
local idJudgement = 20271
local idHammerOfWrath = 24275
local idExorcism = 879 --27138
local idMassExorcism = 122032
local idHammerOfTheRighteous = 53595
local idDivineStorm = 53385
local idTemplarsVerdict = 85256
local idHolyPrism = 114165
local idExecutionSentence = 114157


-- buffs
-- /dump C_UnitAuras.GetBuffDataByIndex("Player", 1)
-- /dump C_UnitAuras.GetDebuffDataByIndex("Target", 1)
-- /etrace for combat log search/pause

local idDivinePurpose = 90174
local idArtOfWar = 87138
local idInquisition = 84963

-- debuffs

-- status vars
local s1, s2
local s_ctime, s_otime, s_gcd, s_hp, s_dp, s_aw, s_ss, s_dc, s_fv, s_bc, s_haste, s_in_execute_range

-- the queue
local qn = {} -- normal queue
local q -- working queue

local function GetCooldown(id)
	local start, duration = GetSpellCooldown(id)
	if start == nil then return 100 end
	local cd = start + duration - s_ctime - s_gcd
	if cd < 0 then return 0 end
	return cd
end

-- actions ---------------------------------------------------------------------
local actions = {

	--Templar's Verdict 3hp
	tv = {
		id = idTemplarsVerdict,
		GetCD = function()
		
			if (s1 ~= idTemplarsVerdict) and ((s_hp > 2) or s_buff_DivinePurpose) and (IsSpellKnown(idTemplarsVerdict)) then
					return 0
				end
				
				return 100
		end,
		UpdateStatus = function()
			s_ctime = s_ctime + s_gcd + 1.5 / s_haste
			s_hp = min(3, s_hp - 3)

		end,
		info = "Templar's Verdict (3 Holy Power)",
	},
	
	-- Inquisition 3hp get to 81 to test
	inq = {
		id = idInquisition,
		GetCD = function()
		
			if (s1 ~= idInquisition) and ((s_hp > 2) or s_buff_DivinePurpose) and (IsSpellKnown(idInquisition)) and not s_buff_Inquisition then
					return 0
				end
				
				return 100
		end,
		UpdateStatus = function()
			s_ctime = s_ctime + s_gcd + 1.5 / s_haste
			s_hp = min(3, s_hp - 3)

		end,
		info = "Inquisiton (3 Holy Power)",
	},

	--Holy Prism
	hpr = {
		id = idHolyPrism,
		GetCD = function()
			if (s1 ~= idHolyPrism) and (IsSpellKnown(idHolyPrism)) and IsUsableSpell(idHolyPrism) then
				return GetCooldown(idHolyPrism)
			end
			return 100
		end,
		UpdateStatus = function()
			s_ctime = s_ctime + s_gcd + 1.5 / s_haste

		end,
		info = "Holy Prism",
	},
	
	--Execution Sentence
	es = {
		id = idExecutionSentence,
		GetCD = function()
			if (s1 ~= idExecutionSentence) and (IsSpellKnown(idExecutionSentence)) and IsUsableSpell(idExecutionSentence) then
				return GetCooldown(idExecutionSentence)
			end
			return 100
		end,
		UpdateStatus = function()
			s_ctime = s_ctime + s_gcd + 1.5 / s_haste

		end,
		info = "Execution Sentence",
	},

	--Crusader Strike
	cs = {
		id = idCrusaderStrike,
		GetCD = function()
			if (s1 ~= idCrusaderStrike) and (IsSpellKnown(idCrusaderStrike)) then
				return GetCooldown(idCrusaderStrike)
			end
			return 100
		end,
		UpdateStatus = function()
			s_ctime = s_ctime + s_gcd + 1.5 / s_haste

			s_hp = max(0, s_hp + 1)

		end,
		info = "Crusader Strike",
	},

	--Hammer of the righteous
	-- hor3 = {
		-- id = idHammerOfTheRighteous,
		-- GetCD = function()
		
		-- code for in range
		-- inRange = 0
			-- for i = 1, 40 do
				-- if UnitExists('nameplate'.. i) and IsSpellInRange('Crusader Strike', 'nameplate'.. i) == 1 then 
				-- inRange = inRange + 1
				-- end
			-- end
		-- ----
		
			-- if (s1 ~= idHammerOfTheRighteous) and (IsSpellKnown(idHammerOfTheRighteous)) and (inRange > 2) then
				-- return GetCooldown(idHammerOfTheRighteous)
			-- end
			-- return 100
		-- end,
		-- UpdateStatus = function()
			-- s_ctime = s_ctime + s_gcd + 1.5 / s_haste

			-- s_hp = max(0, s_hp + 1)

		-- end,
		-- info = "Hammer of the Righteous @3 or more targets",
	-- },

	-- Judgement
	j = {
		id = idJudgement,
		GetCD = function()
			if (s1 ~= idJudgement) and (IsSpellKnown(idJudgement)) and IsUsableSpell(idJudgement) then
				return GetCooldown(idJudgement)
			end
			return 100
		end,
		UpdateStatus = function()
			s_ctime = s_ctime + s_gcd + 1.5 / s_haste

		end,
		info = "Judgement",
	},

	--Hammer of Wrath
	how = {
		id = idHammerOfWrath,
		GetCD = function()
			if (s1 ~= idHammerOfWrath) and (IsSpellKnown(idHammerOfWrath)) and IsUsableSpell(idHammerOfWrath) then
				return GetCooldown(idHammerOfWrath)
			end
			return 100
		end,
		UpdateStatus = function()
			s_ctime = s_ctime + s_gcd + 1.5 / s_haste

		end,
		info = "Hammer Of Wrath",
	},

	--Exorcism
	exo = {
		id = idExorcism,
		GetCD = function()
		
			if (s1 ~= idExorcism) and not IsSpellKnownOrOverridesKnown(idMassExorcism) then
				return GetCooldown(idExorcism)
			end
			
			if (s1 ~= idExorcism) and IsSpellKnownOrOverridesKnown(idMassExorcism) then
				return GetCooldown(idMassExorcism)
			end
			
			return 100
		end,
		UpdateStatus = function()
			s_ctime = s_ctime + s_gcd + 1.5 / s_haste

		end,
		info = "Exorcism",
	},

	--Divine Storm -- Use ahead of TV at all times to work
	-- ds3 = {
		-- id = idDivineStorm,
		-- GetCD = function()
		
		-- code for in range
		-- inRange = 0
			-- for i = 1, 40 do
				-- if UnitExists('nameplate'.. i) and IsSpellInRange('Crusader Strike', 'nameplate'.. i) == 1 then 
				-- inRange = inRange + 1
				-- end
			-- end
		-- ----
		
			-- if (s1 ~= idDivineStorm) and (IsSpellKnown(idDivineStorm)) and (inRange > 2) and (s_hp > 2) then
				-- return GetCooldown(idDivineStorm)
			-- end
			-- return 100
		-- end,
		-- UpdateStatus = function()
			-- s_ctime = s_ctime + s_gcd + 1.5 / s_haste
			-- s_hp = min(3, s_hp - 3)
			
		-- end,
		-- info = "Divine Storm w/ 3 or more targets",
	-- },


}

--------------------------------------------------------------------------------

local function UpdateQueue()
	-- normal queue
	qn = {}
	for v in string.gmatch(db.prio, "[^ ]+") do
		if actions[v] then
			table.insert(qn, v)
		else
			print("clcretmodule - invalid action:", v)
		end
	end
	db.prio = table.concat(qn, " ")

	-- force reconstruction for q
	qTaint = true
end

-- reads all the interesting data // List of Buffs
local function GetStatus()
	-- current time
	s_ctime = GetTime()

	-- gcd value
	local start, duration = GetSpellCooldown(idGCD)
	s_gcd = start + duration - s_ctime
	if s_gcd < 0 then s_gcd = 0 end


	-- the buffs

	s_buff_DivinePurpose = C_UnitAuras.GetPlayerAuraBySpellID(idDivinePurpose)
	s_buff_ArtOfWar = C_UnitAuras.GetPlayerAuraBySpellID(idArtOfWar)
	s_buff_Inquisition = C_UnitAuras.GetPlayerAuraBySpellID(idInquisition)

	-- the debuffs


	-- client hp and haste
	s_haste = 1 -- + UnitSpellHaste("player") / 100
	s_mana = UnitPower("player", 0)
	s_manaMax = UnitPowerMax("player", 0)
	s_hp = UnitPower("player", 9)
	
end

-- remove all talents not available and present in rotation
-- adjust for modified skills present in rotation
local function GetWorkingQueue()
	q = {}
	local name, selected, available
	for k, v in pairs(qn) do
		-- see if it has a talent requirement
		if actions[v].reqTalent then
			-- see if the talent is activated
			isKnown = IsPlayerSpell(actions[v].reqTalent)
			if isKnown then
				table.insert(q, v)
			end
		else
			table.insert(q, v)
		end				
	end
end

local function GetNextAction()
	-- check if working queue needs updated due to glyph talent changes
	if qTaint then
		GetWorkingQueue()
		qTaint = false
	end

	local n = #q

	-- parse once, get cooldowns, return first 0
	for i = 1, n do
		local action = actions[q[i]]
		local cd = action.GetCD()
		if debug and debug.enabled then
			debug:AddBoth(q[i], cd)
		end
		if cd == 0 then
			return action.id, q[i]
		end
		action.cd = cd
	end

	-- parse again, return min cooldown
	local minQ = 1
	local minCd = actions[q[1]].cd
	for i = 2, n do
		local action = actions[q[i]]
		if minCd > action.cd then
			minCd = action.cd
			minQ = i
		end
	end
	return actions[q[minQ]].id, q[minQ]
end

-- exposed functions

-- this function should be called from addons
function xmod.Init()
	db = xmod.db
	UpdateQueue()
end

function xmod.GetActions()
	return actions
end

function xmod.Update()
	UpdateQueue()
end

function xmod.Rotation()
	s1 = nil
	GetStatus()
	if debug and debug.enabled then
		debug:Clear()
		debug:AddBoth("ctime", s_ctime)
		debug:AddBoth("gcd", s_gcd)
		debug:AddBoth("haste", s_haste)

	end
	local action
	s1, action = GetNextAction()
	if debug and debug.enabled then
		debug:AddBoth("s1", action)
		debug:AddBoth("s1Id", s1)
	end
	-- 
	s_otime = s_ctime -- save it so we adjust buffs for next
	actions[action].UpdateStatus()

	s_otime = s_ctime - s_otime

	-- -----------
	-- AOE Mode --
	-- -----------
	
	inRange = 0
	for i = 1, 40 do
		if UnitExists('nameplate'.. i) and IsSpellInRange('Crusader Strike', 'nameplate'.. i) == 1 then 
			inRange = inRange + 1
		end
	end
	
	-- templars verdict/divine storm interchange
	if db.aoeMode and (inRange > 2) then -- Smaller number
		idTemplarsVerdict = 53385
	end

	actions['tv'].id = idTemplarsVerdict
	
	if db.aoeMode and (inRange < 3) then -- Bigger number
		idTemplarsVerdict = 85256
	end

	actions['tv'].id = idTemplarsVerdict
	
	-- crusader strike/hammer of the righteous interchange
	if db.aoeMode and (inRange > 2) then -- Smaller number
		idCrusaderStrike = 53595
	end

	actions['cs'].id = idCrusaderStrike
	
	if db.aoeMode and (inRange < 3) then -- Bigger number
		idCrusaderStrike = 35395
	end

	actions['cs'].id = idCrusaderStrike

	-- --------------

	if debug and debug.enabled then
		debug:AddBoth("csc", s_CrusaderStrikeCharges)
	end

	if debug and debug.enabled then
		debug:AddBoth("ctime", s_ctime)
		debug:AddBoth("otime", s_otime)
		debug:AddBoth("gcd", s_gcd)
		debug:AddBoth("haste", s_haste)
		debug:AddBoth("dJudgement", s_debuff_Judgement)
		
	end
	s2, action = GetNextAction()
	if debug and debug.enabled then
		debug:AddBoth("s2", action)
	end

	return s1, s2
end

-- event frame
local ef = CreateFrame("Frame", "clcRetModuleEventFrame") -- event frame
ef:Hide()

local function OnEvent()
	qTaint = true

	-- mexo attempt. failed ver, have to reload to detect change, trukaduk
	-- if IsSpellKnownOrOverridesKnown(122032) then
		-- idExorcism = 122032
	-- end

	-- actions['exo'].id = idExorcism

end
ef:SetScript("OnEvent", OnEvent)
ef:RegisterEvent("PLAYER_ENTERING_WORLD")
ef:RegisterEvent("PLAYER_LEVEL_UP")