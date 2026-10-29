-- Adapted from Babylon GreatPeopleHeroPanel.lua, Copyright 2020, Firaxis Games.
-- Show Hero Lifespans 0.1.0. Vanilla XML, parent tab and actions are retained.

include("InstanceManager");
include("HeroesSupport");
include("CivilizationIcon");
include("HLS_Presentation");
include("HLS_HeroData");

-- ===========================================================================
--	CONSTANTS
-- ===========================================================================

local m_sPortraitPrefix = "ICON_";
local m_sPortraitSuffix = "_PORTRAIT";

-- ===========================================================================
--	MEMBERS
-- ===========================================================================

local m_pHeroPanelIM		= InstanceManager:new("HeroPanelInstance",	"Content",	Controls.HeroStack);
local m_pAbilityIM		= InstanceManager:new("AbilityInstance",	"Top");
local m_pCommandIM		= InstanceManager:new("CommandInstance",	"Top");
local m_pStatIM			= InstanceManager:new("StatInstance",		"Top");

local m_newestHeroType	= "";
local m_HLSActive = false;
local m_HLSRefreshPending = false;

-- ===========================================================================
function RefreshHeroes()
	ClearHeroes();
    m_HLSActive = true;
    local manager = Game.GetHeroesManager();
    if manager == nil then return; end
    local localPlayer = Game.GetLocalPlayer();
    local heroes = {};
    for row in GameInfo.HeroClasses() do
        local hero = HLS_HeroData.Read(row, manager, localPlayer);
        -- All claimed heroes follow visibility Option A. Discovery still
        -- controls unclaimed cards, as in vanilla.
        if hero.owner ~= -1 or manager:IsHeroDiscovered(localPlayer, row.Index) then
            heroes[#heroes + 1] = hero;
        end
    end
    table.sort(heroes, HLS_Presentation.Less);
    for _, hero in ipairs(heroes) do AddHero(hero.definition, hero); end
end

-- RequestRefresh coalesces work for the next UI frame (UnitPanel.lua:2419).
-- Gamecore batches can finish after LocalPlayerTurnBegin's early snapshot.
-- Re-read each published batch while visible, covering extension/death/recall
-- without a timer, update loop, guessed lifespan or gameplay bridge.
function HLS_QueueRefresh()
    if m_HLSActive and ContextPtr:IsVisible() and not m_HLSRefreshPending then
        m_HLSRefreshPending = true;
        ContextPtr:RequestRefresh();
    end
end

function HLS_OnDeferredRefresh()
    ContextPtr:ClearRequestRefresh();
    m_HLSRefreshPending = false;
    if m_HLSActive and ContextPtr:IsVisible() then RefreshHeroes(); end
end

-- ===========================================================================
function AddHero( kHeroDef, hero )
    local kHeroInstance = m_pHeroPanelIM:GetInstance();

	local sHeroName = "";
	if kHeroDef.HeroClassType == m_newestHeroType then
		sHeroName = "[ICON_New] ";
	end
	sHeroName = sHeroName .. Locale.ToUpper(kHeroDef.Name);
    kHeroInstance.IndividualName:SetText(sHeroName);

	local sIconName = m_sPortraitPrefix .. kHeroDef.HeroClassType .. m_sPortraitSuffix;
	kHeroInstance.Portrait:SetIcon(sIconName);

    -- Stats
    local kStats = GetHeroUnitStats(kHeroDef.Index);

    local card = HLS_Presentation.Card(hero, Locale.Lookup);
    if card.statValue ~= nil then
        local pLifespanInst = m_pStatIM:GetInstance(kHeroInstance.EffectStack);
        pLifespanInst.StatIcon:SetIcon("ICON_LIFESPAN");
        local value = card.statValue;
        if card.warning then value = "[COLOR:Red]" .. value .. "[ENDCOLOR]"; end
        pLifespanInst.ValueText:SetText(value);
        pLifespanInst.NameText:SetText(card.statLabel);
    end

	if kStats.BaseMoves ~= nil and kStats.BaseMoves > 0 then
        local pCombatInst = m_pStatIM:GetInstance(kHeroInstance.EffectStack);
        pCombatInst.StatIcon:SetIcon("ICON_MOVES");
        pCombatInst.ValueText:SetText(kStats.BaseMoves);
        pCombatInst.NameText:SetText(Locale.Lookup("LOC_HUD_UNIT_PANEL_MOVEMENT"));
    end

    if kStats.Combat ~= nil and kStats.Combat > 0 then
        local pCombatInst = m_pStatIM:GetInstance(kHeroInstance.EffectStack);
        pCombatInst.StatIcon:SetIcon("ICON_STRENGTH");
        pCombatInst.ValueText:SetText(kStats.Combat);
        pCombatInst.NameText:SetText(Locale.Lookup("LOC_HUD_UNIT_PANEL_STRENGTH"));
    end

    if kStats.RangedCombat ~= nil and kStats.RangedCombat > 0 then
        local pRangedCombatInst = m_pStatIM:GetInstance(kHeroInstance.EffectStack);
        pRangedCombatInst.StatIcon:SetIcon("ICON_RANGED_STRENGTH");
        pRangedCombatInst.ValueText:SetText(kStats.RangedCombat);
        pRangedCombatInst.NameText:SetText(Locale.Lookup("LOC_HUD_UNIT_PANEL_RANGED_STRENGTH"));
    end

	if kStats.Range ~= nil and kStats.Range > 0 then
        local pRangedCombatInst = m_pStatIM:GetInstance(kHeroInstance.EffectStack);
        pRangedCombatInst.StatIcon:SetIcon("ICON_RANGE");
        pRangedCombatInst.ValueText:SetText(kStats.Range);
        pRangedCombatInst.NameText:SetText(Locale.Lookup("LOC_HUD_UNIT_PANEL_ATTACK_RANGE"));
    end

	if kStats.Charges ~= nil and kStats.Charges > 0 then
        local pChargesInst = m_pStatIM:GetInstance(kHeroInstance.EffectStack);
        pChargesInst.StatIcon:SetIcon("ICON_STATS_SPREADCHARGES");
        pChargesInst.ValueText:SetText(kStats.Charges);
        pChargesInst.NameText:SetText(Locale.Lookup("LOC_HUD_UNIT_PANEL_CHARGES"));
    end

    -- Abilities
    local kAbilities = GetHeroClassUnitAbilities(kHeroDef.Index);
    for _, kAbility in pairs(kAbilities) do
        local pAbilityInst = m_pAbilityIM:GetInstance(kHeroInstance.EffectStack);

        pAbilityInst.AbilityName:SetText(Locale.ToUpper(kAbility.Name));
		pAbilityInst.AbilityText:SetText(Locale.Lookup(kAbility.Description));
    end

    -- Commands
    local kCommands = GetHeroClassUnitCommands(kHeroDef.Index);
    for _, kCommand in pairs(kCommands) do
        local pCommandInst = m_pCommandIM:GetInstance(kHeroInstance.EffectStack);

		pCommandInst.CommandName:SetText( Locale.ToUpper(kCommand.Name) );
		pCommandInst.CommandText:SetText( Locale.Lookup(kCommand.Description) );
		pCommandInst.CommandIcon:SetIcon( kCommand.Icon );
    end

	-- Setup Civilopedia button
	if GameCapabilities.HasCapability("CAPABILITY_DISPLAY_TOP_PANEL_CIVPEDIA") then
		kHeroInstance.CivilopediaButton:RegisterCallback( Mouse.eLClick, function() OpenCivilopediaForHero(kHeroDef.UnitType); end );
		kHeroInstance.CivilopediaButton:SetHide(false);
	else
		kHeroInstance.CivilopediaButton:SetHide(true);
	end

    -- Never attach an unmet owner's civ icon or leader tooltip.
    local claimedByPlayer = hero.owner;
    kHeroInstance.ClaimedByCivIcon.CivIconBacking:SetHide(true);
    kHeroInstance.DeceasedText:SetHide(true);
    kHeroInstance.LookAtButton:SetHide(true);
    kHeroInstance.FaithRecallButton:SetHide(true);
    if claimedByPlayer == -1 then
        kHeroInstance.HeroStatus:SetText(Locale.Lookup("LOC_GREAT_PEOPLE_HEROES_DISCOVERED_STATE"));
        return;
    end
    kHeroInstance.HeroStatus:SetText(card.ownerLabel or Locale.Lookup("LOC_HLS_UNAVAILABLE"));
    if hero.hasMet then
        local controller = CivilizationIcon:AttachInstance(kHeroInstance.ClaimedByCivIcon);
        controller:UpdateIconFromPlayerID(claimedByPlayer);
        controller:SetLeaderTooltip(claimedByPlayer);
        kHeroInstance.ClaimedByCivIcon.CivIconBacking:SetHide(false);
    end

    local bHideLookAtButton, bHideRecallButton = true, true;
    if hero.isLocal then
        if hero.unit then
            local pHeroUnit = hero.unit;
            kHeroInstance.LookAtButton:SetToolTipString(Locale.Lookup("LOC_GREAT_PEOPLE_HEROES_LOOK_AT_HERO_TT"));
            kHeroInstance.LookAtButton:RegisterCallback(Mouse.eLClick, function() LookAtUnit(pHeroUnit); end);
            bHideLookAtButton = false;
        elseif hero.state == "fallen" then
            local manager = Game.GetHeroesManager();
            local cityID = manager:GetHeroOriginCityID(kHeroDef.Index);
            local player = Players[claimedByPlayer];
            local city = cityID and player and player:GetCities():FindID(cityID.id);
            if city then
                kHeroInstance.LookAtButton:SetToolTipString(Locale.Lookup("LOC_GREAT_PEOPLE_HEROES_LOOK_AT_CITY_TT"));
                kHeroInstance.LookAtButton:RegisterCallback(Mouse.eLClick, function() LookAtCity(city); end);
                bHideLookAtButton = false;
                local visible, canRecall = UpdateRecallButton(kHeroInstance, kHeroDef.Index, kHeroDef.UnitType, city);
                bHideRecallButton = not visible;
                hero.canRecall = canRecall;
            end
        end
    end
    kHeroInstance.LookAtButton:SetHide(bHideLookAtButton);
    kHeroInstance.FaithRecallButton:SetHide(bHideRecallButton);
    card = HLS_Presentation.Card(hero, Locale.Lookup);
    kHeroInstance.DeceasedText:SetText(card.fallenText or "");
    kHeroInstance.DeceasedText:SetHide(card.fallenText == nil);

end

-- ===========================================================================
function OpenCivilopediaForHero( sHeroUnitType )
	LuaEvents.GreatPeopleHeroPanel_Close();
	LuaEvents.OpenCivilopedia(sHeroUnitType);
end

-- ===========================================================================
function LookAtUnit( pUnit )
	LuaEvents.GreatPeopleHeroPanel_Close();
	UI.LookAtPlotScreenPosition( pUnit:GetX(), pUnit:GetY(), 0.5, 0.5 );
	UI.SelectUnit( pUnit );
end

-- ===========================================================================
function LookAtCity( pCity )
	LuaEvents.GreatPeopleHeroPanel_Close();
	UI.LookAtPlotScreenPosition( pCity:GetX(), pCity:GetY(), 0.5, 0.5 );
	UI.SelectCity( pCity );
end

-- ===========================================================================
function UpdateRecallButton( kHeroInstance, eHeroClass, sUnitType, pCity )
	local kHeroUnitDef = GameInfo.Units[sUnitType];
	local kYieldDef = GameInfo.Yields["YIELD_FAITH"];

	local tParameters = {};
	tParameters[CityCommandTypes.PARAM_UNIT_TYPE] = kHeroUnitDef.Hash;
	tParameters[CityCommandTypes.PARAM_YIELD_TYPE] = kYieldDef.Index;
	if CityManager.CanStartCommand( pCity, CityCommandTypes.PURCHASE, true, tParameters, false ) then
		local isCanStart, results = CityManager.CanStartCommand( pCity, CityCommandTypes.PURCHASE, false, tParameters, true );

		local pCityGold = pCity:GetGold();
		local faithCost = pCityGold:GetPurchaseCost( kYieldDef.Index, kHeroUnitDef.Hash, MilitaryFormationTypes.STANDARD_MILITARY_FORMATION );
		kHeroInstance.FaithRecallButton:SetText(faithCost .. "[ICON_Faith]");

		local sToolTip = Locale.Lookup("LOC_GREAT_PEOPLE_HEROES_FAITH_RECALL_TT", faithCost);

		if isCanStart then
			kHeroInstance.FaithRecallButton:RegisterCallback( Mouse.eLClick, function() RecallHero(eHeroClass); end );
			kHeroInstance.FaithRecallButton:SetDisabled(false);
		else
			-- Add failure reasons to the tooltip
			if results ~= nil and results[CityCommandResults.FAILURE_REASONS] ~= nil then
				local kFailureReasons = results[CityCommandResults.FAILURE_REASONS];
				if kFailureReasons ~= nil and table.count( kFailureReasons ) > 0 then
					for i,v in ipairs(kFailureReasons) do
						sToolTip = sToolTip .. "[NEWLINE][NEWLINE][COLOR:Red]" .. Locale.Lookup(v) .. "[ENDCOLOR]";
					end
				end
			end

			-- Affordability check
			local pPlayerReligion = Players[pCity:GetOwner()]:GetReligion();
			if pPlayerReligion ~= nil and not pPlayerReligion:CanAfford( pCity:GetID(), kHeroUnitDef.Hash ) then
				sToolTip = sToolTip .. "[NEWLINE][NEWLINE]" .. Locale.Lookup("LOC_GREAT_PEOPLE_HEROES_INSUFFICIENT_FAITH_TT");
			end

			kHeroInstance.FaithRecallButton:SetDisabled(true);
		end

		kHeroInstance.FaithRecallButton:SetToolTipString(sToolTip);

		return true, isCanStart;
	end

	return false, false;
end

-- ===========================================================================
function RecallHero( eHeroClass )
	local kHeroDef = GameInfo.HeroClasses[eHeroClass];
	local kHeroUnitDef = GameInfo.Units[kHeroDef.UnitType];

	local pGameHeroes = Game.GetHeroesManager();
    local claimedByPlayer = pGameHeroes:GetHeroClaimPlayer(kHeroDef.Index);
	local pPlayerCities = Players[claimedByPlayer]:GetCities();
	local kCityID = pGameHeroes:GetHeroOriginCityID(kHeroDef.Index);
	local pHeroCity = pPlayerCities:FindID(kCityID.id);

	-- Close the panel and look at the city the hero will be spawned in
	LuaEvents.GreatPeopleHeroPanel_Close();
	UI.LookAtPlotScreenPosition( pHeroCity:GetX(), pHeroCity:GetY(), 0.5, 0.5 );

	-- Purchase the hero
	local tParameters = {};
	tParameters[CityCommandTypes.PARAM_UNIT_TYPE] = kHeroUnitDef.Hash;
	tParameters[CityCommandTypes.PARAM_MILITARY_FORMATION_TYPE] = MilitaryFormationTypes.STANDARD_MILITARY_FORMATION;
	tParameters[CityCommandTypes.PARAM_YIELD_TYPE] = GameInfo.Yields["YIELD_FAITH"].Index;
	UI.PlaySound("Purchase_With_Faith");
	CityManager.RequestCommand(pHeroCity, CityCommandTypes.PURCHASE, tParameters);
end

-- ===========================================================================
function ClearHeroes()
    m_HLSActive = false;
    m_HLSRefreshPending = false;
    ContextPtr:ClearRequestRefresh();
	if m_pStatIM ~= nil then
		m_pStatIM:ResetInstances();
	end
	if m_pAbilityIM ~= nil then
		m_pAbilityIM:ResetInstances();
	end
	if m_pCommandIM ~= nil then
		m_pCommandIM:ResetInstances();
	end
	if m_pHeroPanelIM ~= nil then
		m_pHeroPanelIM:ResetInstances();
	end
end

-- ===========================================================================
function OnHeroStackSizeChanged()
	LuaEvents.GreatPeopleHeroPanel_SizeChanged(Controls.HeroStack:GetSizeX());
end

-- ===========================================================================
function OnHeroesPopup_ShowNewHero( kHeroDef )
	m_newestHeroType = kHeroDef.HeroClassType;
	LuaEvents.GreatPeopleHeroPanel_Show();
end

-- ===========================================================================
function Initialize()
    -- Sources: UnitPanel.lua:4225; ResearchChooser.lua:399,485; parent popup:1213.
    ContextPtr:SetRefreshHandler(HLS_OnDeferredRefresh);
    Events.LocalPlayerTurnBegin.Add(HLS_QueueRefresh);
    Events.GameCoreEventPublishComplete.Add(HLS_QueueRefresh);
	-- Set this context to autosize
	ContextPtr:SetAutoSize(true);

	LuaEvents.GreatPeoplePopup_RefreshHeroes.Add(RefreshHeroes);
	LuaEvents.GreatPeoplePopup_ClearHeroes.Add(ClearHeroes);
	LuaEvents.HeroesPopup_ShowNewHero.Add(OnHeroesPopup_ShowNewHero);

	Controls.HeroStack:RegisterSizeChanged( OnHeroStackSizeChanged );
end
function HLS_OnShutdown()
    Events.LocalPlayerTurnBegin.Remove(HLS_QueueRefresh);
    Events.GameCoreEventPublishComplete.Remove(HLS_QueueRefresh);
    LuaEvents.GreatPeoplePopup_RefreshHeroes.Remove(RefreshHeroes);
    LuaEvents.GreatPeoplePopup_ClearHeroes.Remove(ClearHeroes);
    LuaEvents.HeroesPopup_ShowNewHero.Remove(OnHeroesPopup_ShowNewHero);
    ContextPtr:ClearRequestRefresh();
end
ContextPtr:SetShutdown(HLS_OnShutdown);
Initialize();
