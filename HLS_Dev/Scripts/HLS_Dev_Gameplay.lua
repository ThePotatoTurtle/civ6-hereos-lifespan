-- Disposable hotseat test. Synced EXECUTE_SCRIPT mutations only.
-- Sources: EFV_Dev_Gameplay.lua:452,457-458,464,496-499,658-677.
local VERSION = "0.1.1.1"
local function Log(cmd,pid,stamp,msg)
  print("[HLS][DEV "..cmd.."] turn="..tostring(Game.GetCurrentGameTurn()).." player="..tostring(pid).." stamp="..tostring(stamp).." "..msg)
end
local function Roles()
  local humans,ais={},{}
  for id=0,63 do
    local p=Players[id]
    if p and p:IsAlive() and p:IsMajor() then
      local list=p:IsHuman() and humans or ais
      list[#list+1]=id
    end
  end
  if #humans~=3 or #ais~=1 then return nil,"requires exactly 3 alive major humans and 1 alive major AI" end
  return {human1=humans[1],human2=humans[2],human3=humans[3],ai=ais[1]}
end
local function Execute(pid,p)
  if type(p)~="table" then return end
  local cmd,stamp=p.command,p.stamp
  if cmd~="meet12" and cmd~="relationships" then Log("REQUEST",pid,stamp,"UNVERIFIED reason=unknown or removed command; +5 unsupported: gameplay GetLifespan is nil"); return end
  local r,reason=Roles()
  if not r then Log(cmd,pid,stamp,"UNVERIFIED reason="..reason.."; no mutation"); return end
  if pid~=r.human1 and pid~=r.human2 and pid~=r.human3 then Log(cmd,pid,stamp,"UNVERIFIED reason=requester is not a configured human; no mutation"); return end
  if p.human1~=r.human1 or p.human2~=r.human2 or p.human3~=r.human3 or p.ai~=r.ai or p.turn~=Game.GetCurrentGameTurn() then Log(cmd,pid,stamp,"UNVERIFIED reason=stale turn or mismatched sorted roles; no mutation"); return end
  local counts={PASS=0,FAIL=0,UNVERIFIED=0}
  local function Result(status,msg) counts[status]=counts[status]+1; Log(cmd,pid,stamp,status.." "..msg) end
  local function Read(a,method,b)
    local ok,v=pcall(function() local d=Players[a]:GetDiplomacy(); return d[method](d,b) end)
    if ok and type(v)=="boolean" then return v end
  end
  local function Check(phase,a,method,b,expected)
    local actual=Read(a,method,b)
    Result(actual==nil and "UNVERIFIED" or actual==expected and "PASS" or (phase=="before" or phase=="before-friend" or phase=="before-war") and "UNVERIFIED" or "FAIL","phase="..phase.." a="..a.." b="..b.." read="..method.." actual="..tostring(actual).." expected="..tostring(expected))
    return actual
  end
  local function Call(a,method,b,value)
    local ok,err=pcall(function()
      local d=Players[a]:GetDiplomacy()
      if method=="SetHasMet" then d:SetHasMet(b)
      elseif method=="SetHasDeclaredFriendship" then d:SetHasDeclaredFriendship(b,value)
      else d:DeclareWarOn(b,WarTypes.FORMAL_WAR,true) end
    end)
    if not ok then Result("UNVERIFIED","operation="..method.." a="..a.." b="..b.." error="..tostring(err)) end
  end
  local function Meet(a,b)
    Call(a,"SetHasMet",b); Call(b,"SetHasMet",a)
    Check("after",a,"HasMet",b,true); Check("after",b,"HasMet",a,true)
  end
  local a,b,c=r.human1,r.human2,r.human3
  Log(cmd,pid,stamp,"roles human1="..a.." human2="..b.." human3="..c.." ai="..r.ai.." source=validated_sorted_alive_major_ids")
  for _,pair in ipairs({{a,b},{b,a},{a,c},{c,a},{b,c},{c,b}}) do
    local x,y=pair[1],pair[2]
    Log(cmd,pid,stamp,"phase=before a="..x.." b="..y.." met="..tostring(Read(x,"HasMet",y)).." friend="..tostring(Read(x,"HasDeclaredFriendship",y)).." war="..tostring(Read(x,"IsAtWarWith",y)).." allied="..tostring(Read(x,"HasAllied",y)))
  end
  if cmd=="meet12" then
    -- Preserve actual non-target meeting state; natural contact cannot be undone.
    local untouched={{a,c},{c,a},{b,c},{c,b}}
    for _,pair in ipairs(untouched) do pair.before=Read(pair[1],"HasMet",pair[2]) end
    for _,pair in ipairs({{a,b},{b,a},{a,c},{c,a},{b,c},{c,b}}) do Check("before",pair[1],"HasMet",pair[2],false) end
    Meet(a,b)
    for _,pair in ipairs(untouched) do
      if pair.before==nil then Result("UNVERIFIED","non-target meeting baseline unavailable a="..pair[1].." b="..pair[2])
      else Check("after-unchanged",pair[1],"HasMet",pair[2],pair.before) end
    end
  else
    -- Record whether the staged meeting case was preserved before advancing.
    for _,pair in ipairs({{a,b},{b,a}}) do Check("before",pair[1],"HasMet",pair[2],true) end
    for _,pair in ipairs({{a,c},{c,a},{b,c},{c,b}}) do Check("before",pair[1],"HasMet",pair[2],false) end
    Meet(a,b); Meet(a,c); Meet(b,c)
    -- No unsupported scripted peace/alliance removal to manufacture neutral.
    local eligible=true
    for _,pair in ipairs({{a,b},{b,a}}) do if Check("before-friend",pair[1],"IsAtWarWith",pair[2],false)~=false then eligible=false end end
    for _,pair in ipairs({{a,c},{c,a}}) do
      if Check("before-war",pair[1],"HasDeclaredFriendship",pair[2],false)~=false then eligible=false end
      if Check("before-war",pair[1],"HasAllied",pair[2],false)~=false then eligible=false end
    end
    if eligible then
      Call(a,"SetHasDeclaredFriendship",b,true); Call(b,"SetHasDeclaredFriendship",a,true)
      if Read(a,"IsAtWarWith",c)~=true then
        Call(a,"DeclareWarOn",c)
        if Read(a,"IsAtWarWith",c)==false then Call(c,"DeclareWarOn",a) end
      end
    else Result("UNVERIFIED","relationship prerequisites failed; meet changes may have completed; friendship/war not changed") end
    for _,pair in ipairs({{a,b},{b,a}}) do Check("after",pair[1],"HasDeclaredFriendship",pair[2],true) end
    for _,pair in ipairs({{a,c},{c,a}}) do Check("after",pair[1],"IsAtWarWith",pair[2],true) end
    for _,pair in ipairs({{b,c},{c,b}}) do
      Check("after-neutral",pair[1],"IsAtWarWith",pair[2],false)
      Check("after-neutral",pair[1],"HasDeclaredFriendship",pair[2],false)
      Check("after-neutral",pair[1],"HasAllied",pair[2],false)
    end
  end
  Log(cmd,pid,stamp,"SUMMARY "..counts.PASS.." PASS, "..counts.FAIL.." FAIL, "..counts.UNVERIFIED.." UNVERIFIED; run Visibility Check on each human turn; diplomacy does not prove map visibility")
end
local function OnRequest(pid,p)
  local ok,err=pcall(function() Execute(pid,p) end)
  if not ok then Log(type(p)=="table" and tostring(p.command) or "REQUEST",pid,type(p)=="table" and p.stamp or "?","UNVERIFIED error="..tostring(err).."; partial mutation possible") end
end
GameEvents.HLS_Dev_Request.Add(OnRequest)
print("[HLS][DEV GAMEPLAY] ready version="..VERSION.." mutations=only synchronized meet12/relationships requests")
