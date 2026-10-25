"""Execute the shipped Lua modules against a fake Lua 5.1 engine."""

from __future__ import annotations

from pathlib import Path
import sys
import unittest

try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    raise SystemExit("lupa.lua51 is required: python -m pip install lupa")

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from check_all import engine_calls
from summarize_log import summarize


FAKE_ENGINE = r'''
World = {turn=10, mode=true, managerReads=0, nameReads={}, met={[1]=true}, logs={},
    claims={[0]=0,[1]=1,[2]=-1,[3]=1,[4]=2}, unitLists={}, enumerateError={}};
print = function(...) local parts={}; for i=1,select('#',...) do parts[i]=tostring(select(i,...)); end
    World.logs[#World.logs+1]=table.concat(parts,' '); end;
function FakeUnit(id, kind, remaining)
    local u={id=id,kind=kind,remaining=remaining};
    function u:GetID() return self.id; end
    function u:GetType() return self.kind; end
    function u:GetProperty(key) assert(key=='lifespan'); return self.remaining; end
    function u:GetLifespan() if self.noDirect then error('not exposed in UI'); end return self.remaining; end
    return u;
end
World.unitLists[0]={FakeUnit(11,100,9)};
World.unitLists[1]={FakeUnit(12,101,3)};
World.unitLists[2]={FakeUnit(13,104,20)};
local definitions={};
GameInfo={Units={},Yields={YIELD_FAITH={Index=5}}};
for i=0,4 do local kind='UNIT_HERO_'..i; local def={Index=i,HeroClassType='HEROCLASS_'..i,Name='Hero '..i,UnitType=kind};
    definitions[#definitions+1]=def; local unit={Index=100+i,UnitType=kind,Hash=1000+i};
    GameInfo.Units[kind]=unit; GameInfo.Units[100+i]=unit; end
GameInfo.HeroClasses=function() local i=0; return function() i=i+1; return definitions[i]; end; end;
Players={}; PlayerConfigurations={};
for id=0,2 do local owner=id; local player={};
    function player:GetUnits()
        if World.enumerateError[owner] then error('units unavailable'); end
        return {Members=function() return ipairs(World.unitLists[owner]); end};
    end
    function player:GetDiplomacy() return {HasMet=function(_,other) return World.met[other]==true; end}; end
    function player:GetCities() return {FindID=function() return nil; end}; end
    Players[id]=player;
    PlayerConfigurations[id]={GetPlayerName=function() World.nameReads[owner]=(World.nameReads[owner] or 0)+1; return 'Player '..owner; end};
end
HeroManager={
    GetHeroClaimPlayer=function(_,index) return World.claims[index]; end,
    IsHeroDiscovered=function() return true; end,
    GetHeroOriginCityID=function() return {id=-1}; end
};
Game={GetCurrentGameTurn=function() return World.turn; end,GetLocalPlayer=function() return 0; end,
    GetHeroesManager=function() World.managerReads=World.managerReads+1; return HeroManager; end};
GameConfiguration={GetValue=function(key) assert(key=='GAMEMODE_HEROES'); return World.mode; end};
UnitPropertyKeys={LifespanRemaining='lifespan'};
UnitManager={GetUnitTypeBaseLifespan=function() return 40; end};
Locale={Lookup=function(text) return text; end};
CityCommandTypes={PARAM_UNIT_TYPE=1,PARAM_YIELD_TYPE=2,PURCHASE=3};
CityManager={CanStartCommand=function() return false; end};
'''


class ProbeTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(FAKE_ENGINE)
        self.probe = self.lua.execute((ROOT / "HLS_Dev/UI/HLS_Probe.lua").read_text(encoding="utf-8-sig"))
        self.world = self.lua.globals().World

    def heroes(self):
        return list(self.probe.Snapshot().heroes.values())

    def logs(self):
        return "\n".join(self.world.logs.values())

    def test_reads_actual_timer_for_every_owner_without_base_estimate(self):
        heroes = self.heroes()
        self.assertEqual([h.state for h in heroes], ["active", "active", "unclaimed", "fallen", "active"])
        self.assertEqual([heroes[i].remaining for i in (0, 1, 4)], [9, 3, 20])
        self.assertEqual(heroes[0].baseLifespan, 40)
        self.assertEqual(self.probe.RunAllSpikes().fail, 0)

    def test_unmet_owner_never_looks_up_identity(self):
        hero = self.heroes()[4]
        self.assertFalse(hero.ownerMet)
        self.assertEqual(hero.ownerName, "Unknown civ")
        self.assertIsNone(self.world.nameReads[2])

    def test_mode_off_never_reads_heroes_manager(self):
        self.world.mode = False
        snapshot = self.probe.Snapshot()
        self.assertFalse(snapshot.modeEnabled)
        self.assertEqual(len(snapshot.heroes), 0)
        self.assertEqual(self.world.managerReads, 0)

    def test_no_active_heroes_is_unverified_coverage(self):
        self.lua.execute("for i=0,4 do World.claims[i]=-1; end")
        report = self.probe.RunAllSpikes()
        self.assertEqual(report.fail, 0)
        self.assertIn("coverage own=0 other=0 unmet=0", self.logs())
        self.assertIn("UNVERIFIED", self.logs())

    def test_missing_exact_property_fails_closed(self):
        self.world.unitLists[0][1].remaining = None
        self.assertGreater(self.probe.RunAllSpikes().fail, 0)
        self.assertIn("exactProperty=nil", self.logs())
        self.assertIsNone(self.heroes()[0].remaining)

    def test_optional_tuner_getter_absence_is_unverified(self):
        self.world.unitLists[0][1].noDirect = True
        self.assertEqual(self.probe.RunAllSpikes().fail, 0)
        self.assertIn("independent UI GetLifespan unavailable", self.logs())

    def test_failed_enumeration_is_not_a_fallen_hero(self):
        self.world.enumerateError[1] = True
        self.assertEqual(self.heroes()[1].state, "unavailable")
        self.assertEqual(self.heroes()[3].state, "unavailable")
        self.assertGreater(self.probe.RunAllSpikes().fail, 0)

    def test_multiple_matching_units_are_not_selected_arbitrarily(self):
        self.lua.execute("table.insert(World.unitLists[0],FakeUnit(99,100,8))")
        hero = self.heroes()[0]
        self.assertEqual(hero.state, "unavailable")
        self.assertIsNone(hero.remaining)

    def test_missing_manager_reports_a_failure_without_crashing(self):
        self.lua.globals().HeroManager = None
        self.assertGreater(self.probe.RunAllSpikes().fail, 0)

    def test_countdown_uses_actual_turn_delta(self):
        self.probe.StartChecker()
        self.lua.execute("World.turn=12; for _,list in pairs(World.unitLists) do for _,unit in ipairs(list) do unit.remaining=unit.remaining-2; end end")
        report = self.probe.CheckTurn()
        self.assertEqual(report["pass"], 3)
        self.assertEqual(report.fail, 0)
        self.assertEqual(report.unverified, 0)

    def test_external_extension_is_not_falsely_reported_as_countdown_pass(self):
        self.probe.StartChecker()
        self.lua.execute("World.turn=11; World.unitLists[0][1].remaining=14")
        report = self.probe.CheckTurn()
        self.assertGreater(report.unverified, 0)
        self.assertIn("expectedWithoutExternalChanges=8", self.logs())

    def test_unit_id_change_invalidates_comparison(self):
        self.probe.StartChecker()
        self.lua.execute("World.turn=11; World.unitLists[0][1].id=999")
        report = self.probe.CheckTurn()
        self.assertGreater(report.unverified, 0)
        self.assertIn("identity changed", self.logs())

    def test_unexposed_historical_fields_are_never_invented(self):
        for hero in self.heroes():
            for field in ("deathTurn", "startingLifespan", "bonusTurns", "recallsUsed"):
                self.assertIsNone(hero[field])


GAMEPLAY_ENGINE = r'''
World.spawnCalls=0; World.killCalls=0;
for id=0,2 do local owner=id; local player=Players[id];
    function player:GetID() return owner; end
    function player:IsMajor() return true; end
    function player:IsHuman() return owner==0; end
    function player:GetCities() return {GetCapitalCity=function() return {
        GetX=function() return owner*10; end,GetY=function() return owner*10+1; end}; end}; end
end
Game.GetPlayers=function() return {Players[2],Players[0],Players[1]}; end;
local OriginalFakeUnit=FakeUnit;
FakeUnit=function(id,kind,remaining)
    local unit=OriginalFakeUnit(id,kind,remaining);
    local originalRead=unit.GetLifespan;
    function unit:GetLifespan() if self.setCalled and World.throwReadAfterSet then error('post-mutation read failed'); end return originalRead(self); end
    function unit:IsHero() return true; end
    function unit:SetLifespan(value) self.setCalled=true; if not World.setterFail then self.remaining=value; end; end
    return unit;
end
for _,list in pairs(World.unitLists) do for i,unit in ipairs(list) do list[i]=FakeUnit(unit.id,unit.kind,unit.remaining); end; end
UnitManager.InitUnit=function(owner,kind,x,y)
    World.spawnCalls=World.spawnCalls+1;
    local definition=GameInfo.Units[kind];
    local unit=FakeUnit(200+World.spawnCalls,definition.Index,40);
    table.insert(World.unitLists[owner],unit);
    if World.spawnCalls~=World.failRegisterAt then World.claims[definition.Index-100]=owner; end
    return unit;
end
UnitManager.Kill=function(unit)
    World.killCalls=World.killCalls+1;
    if World.killFail then return; end
    for owner=0,2 do local list=World.unitLists[owner]; for i=#list,1,-1 do
        if list[i]==unit then table.remove(list,i); end; end; end
end
GameEvents={HLS_Dev_Request={Add=function(handler) World.handler=handler; end}};
'''


class GameplayTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(FAKE_ENGINE + GAMEPLAY_ENGINE)
        self.lua.execute((ROOT / "HLS_Dev/Scripts/HLS_Dev_Gameplay.lua").read_text(encoding="utf-8-sig"))
        self.world = self.lua.globals().World

    def request(self, command, player=0):
        self.world.handler(player, self.lua.table_from({"command": command, "stamp": 1}))

    def logs(self):
        return "\n".join(self.world.logs.values())

    def prepare_setup(self):
        self.lua.execute("for i=0,4 do World.claims[i]=-1; end; for id=0,2 do World.unitLists[id]={}; end")

    def test_synced_extension_checks_actual_plus_five(self):
        self.request("extend")
        self.assertEqual(self.world.unitLists[0][1].remaining, 14)
        self.assertEqual(self.world.unitLists[1][1].remaining, 3)
        self.assertIn("PASS hero=HEROCLASS_0", self.logs())
        self.assertIn("before=9 actual=14 expected=14", self.logs())

    def test_extension_setter_failure_is_not_dispatch_pass(self):
        self.world.setterFail = True
        self.request("extend")
        self.assertEqual(self.world.unitLists[0][1].remaining, 9)
        self.assertIn("FAIL hero=HEROCLASS_0", self.logs())

    def test_exception_after_mutation_is_a_contextual_failure(self):
        self.world.throwReadAfterSet = True
        self.request("extend")
        self.assertEqual(self.world.unitLists[0][1].remaining, 14)
        self.assertIn("[HLS][DEV extend] turn=10 player=0 stamp=1 FAIL", self.logs())
        self.assertIn("partial mutation possible", self.logs())
        self.assertNotIn("PASS hero=", self.logs())

    def test_kill_selects_ai_hero_and_verifies_absence(self):
        self.request("killAI")
        self.assertEqual(len(self.world.unitLists[1]), 0)
        self.assertEqual(len(self.world.unitLists[0]), 1)
        self.assertIn("actual=absent expected=absent", self.logs())
        self.assertEqual(self.world.killCalls, 1)

    def test_failed_kill_reports_actual_surviving_unit(self):
        self.world.killFail = True
        self.request("killAI")
        self.assertEqual(len(self.world.unitLists[1]), 1)
        self.assertIn("FAIL hero=HEROCLASS_1", self.logs())

    def test_setup_requires_registered_own_ai_fallen_and_unclaimed_states(self):
        self.prepare_setup()
        self.request("setup")
        self.assertEqual(self.world.spawnCalls, 3)
        self.assertEqual(self.world.killCalls, 1)
        self.assertEqual(self.world.claims[0], 0)
        self.assertEqual(self.world.claims[1], 1)
        self.assertEqual(self.world.claims[2], 0)
        self.assertEqual(self.world.claims[3], -1)
        self.assertEqual(len(self.world.unitLists[0]), 1)
        self.assertEqual(len(self.world.unitLists[1]), 1)
        self.assertIn("PASS variant=A actual=localAlive:1,aiAlive:1,registeredFallen:1,unclaimed:1", self.logs())

    def test_partial_setup_cleans_units_and_locks_retry_without_invented_unclaim(self):
        self.prepare_setup()
        self.world.failRegisterAt = 2
        self.request("setup")
        self.assertEqual(self.world.spawnCalls, 2)
        self.assertEqual(len(self.world.unitLists[0]), 0)
        self.assertEqual(len(self.world.unitLists[1]), 0)
        self.assertEqual(self.world.claims[0], 0)
        self.assertIn("claim state may remain", self.logs())
        self.request("setup")
        self.assertEqual(self.world.spawnCalls, 2)
        self.assertIn("already attempted", self.logs())

    def test_successful_setup_also_locks_repeat(self):
        self.prepare_setup()
        self.request("setup")
        self.request("setup")
        self.assertEqual(self.world.spawnCalls, 3)

    def test_absent_eligible_hero_stays_unverified(self):
        self.prepare_setup()
        self.request("extend")
        self.request("killAI")
        self.assertEqual(self.world.spawnCalls + self.world.killCalls, 0)
        self.assertIn("UNVERIFIED actual=no eligible live claimed hero", self.logs())

    def test_invalid_and_unknown_requests_never_mutate(self):
        self.request("extend", player=99)
        self.request("invented")
        self.world.handler(0, None)
        self.assertEqual(self.world.unitLists[0][1].remaining, 9)
        self.assertEqual(self.world.spawnCalls + self.world.killCalls, 0)

    def test_gameplay_uses_only_synced_request_registration(self):
        source = (ROOT / "HLS_Dev/Scripts/HLS_Dev_Gameplay.lua").read_text(encoding="utf-8-sig")
        self.assertNotIn("Game.GetLocalPlayer", source)
        self.assertNotIn("math.random", source)
        self.assertNotRegex(source, r"(?<!Game)\bEvents\.[A-Za-z_]+\.Add")
        self.assertIn("GameEvents.HLS_Dev_Request.Add(OnRequest)", source)


PANEL_ENGINE = r'''
World.callbacks={};
function FakeControl(name)
    return {SetText=function(_,text) World.status=text; end,SetHide=function() end,
        SetDisabled=function() end,SetToolTipString=function() end,SetSizeX=function() end,
        GetSizeX=function() return 300; end,CalculateSize=function() end,
        RegisterCallback=function(_,event,callback) World.callbacks[name]=callback; end};
end
Controls=setmetatable({},{__index=function(t,key) local value=FakeControl(key); rawset(t,key,value); return value; end});
ContextPtr={SetHide=function() end,SetInputHandler=function() end,
    LookUpControl=function(_,name) return FakeControl(name); end,
    BuildInstanceForControl=function(_,name,instance) instance.LaunchItemButton=FakeControl(name); end};
UI={RequestPlayerOperation=function(player,operation,parameters) World.request={player=player,operation=operation,parameters=parameters}; end,
    LookAtPlotScreenPosition=function(x,y) World.focus={x=x,y=y}; end,
    SelectUnit=function(unit) World.selected=unit; end};
LuaEvents={LaunchBar_Resize=function() end};
Events={LocalPlayerTurnBegin={Add=function(callback) World.turnHandler=callback; end}};
Mouse={eLClick=1}; Keys={D=68,VK_ESCAPE=27}; KeyEvents={KeyUp=2}; PlayerOperations={EXECUTE_SCRIPT=99};
include=function(name) assert(name=='HLS_Probe'); end;
for owner=0,2 do local id=owner; local player=Players[id]; local original=player.GetUnits;
    function player:GetUnits() local units=original(self); units.FindID=function(_,wanted)
        for _,unit in ipairs(World.unitLists[id]) do if unit.id==wanted then return unit; end; end; return nil; end; return units; end
    for _,unit in ipairs(World.unitLists[id]) do
        unit.GetX=function() return id*10; end; unit.GetY=function() return id*10+1; end;
    end
end
'''


class PanelTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(FAKE_ENGINE)
        self.lua.execute((ROOT / "HLS_Dev/UI/HLS_Probe.lua").read_text(encoding="utf-8-sig"))
        self.lua.execute(PANEL_ENGINE)
        self.lua.execute((ROOT / "HLS_Dev/UI/HLS_Dev_Panel.lua").read_text(encoding="utf-8-sig"))
        self.world = self.lua.globals().World

    def test_run_spikes_focuses_exact_owned_hero(self):
        self.world.callbacks.RunAllButton()
        self.assertEqual(self.world.selected.id, 11)
        self.assertEqual(self.world.focus.x, 0)
        self.assertEqual(self.world.focus.y, 1)

    def test_extension_dispatch_is_flat_and_does_not_mutate_ui_state(self):
        self.world.callbacks.ExtendButton()
        self.assertEqual(self.world.unitLists[0][1].remaining, 9)
        request = self.world.request
        self.assertEqual(request.player, 0)
        self.assertEqual(request.operation, 99)
        self.assertEqual(dict(request.parameters.items()), {"OnStart": "HLS_Dev_Request", "command": "extend", "stamp": 1})
        self.assertNotIn("PASS", self.world.status)


class ToolTests(unittest.TestCase):
    def test_log_summary_preserves_failed_setup_before_spike_run(self):
        lines, counts = summarize("noise\n[HLS][DEV SETUP] turn=0 player=0 stamp=1 FAIL partial setup\n[HLS][RUN] START\n[HLS][SPIKE S1] timer PASS\n[HLS][SUMMARY] 1 PASS, 0 FAIL")
        self.assertEqual(counts, {"PASS": 1, "FAIL": 1, "UNVERIFIED": 0})
        self.assertTrue(any("FAIL partial setup" in line for line in lines))

    def test_dispatch_prose_is_not_a_result_and_summary_is_not_double_counted(self):
        _, counts = summarize("[HLS][DEV UI] Request sent: setup. Gameplay result is in Lua.log; dispatch alone is not PASS.\n[HLS][SPIKE S1] exactProperty=9 PASS\n[HLS][DEV extend] turn=10 player=0 stamp=1 FAIL partial mutation\n[HLS][SUMMARY] 1 PASS, 1 FAIL, 0 UNVERIFIED")
        self.assertEqual(counts, {"PASS": 1, "FAIL": 1, "UNVERIFIED": 0})

    def test_api_scan_ignores_comments_strings_and_local_module_calls(self):
        source = '-- Game.Missing()\nprint("Game.Fake()")\nProbe.Run(); Game.GetHeroesManager(); unit:GetProperty(key)'
        self.assertEqual(engine_calls(source), {"Game.GetHeroesManager", ":GetProperty"})


if __name__ == "__main__":
    unittest.main(verbosity=2)
