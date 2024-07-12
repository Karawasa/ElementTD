-- wavedata.lua
-- manages the spawning of creep waves

wavesKV = LoadKeyValues("scripts/kv/waves.kv")
creepsKV = LoadKeyValues("scripts/npc/npc_units_custom.txt")

if not WAVE_CREEPS then
    WAVE_CREEPS = {}  -- array that stores the order that creeps spawn in. see /scripts/kv/waves.kv
    WAVE_HEALTH = {}  -- array that stores creep health values per wave.  see /scripts/kv/waves.kv
    CREEP_SCRIPT_OBJECTS = {}
    CREEPS_PER_WAVE = 30 -- the number of creeps to spawn in each wave
    CURRENT_WAVE = 1
    CURRENT_BOSS_WAVE = 0
    WAVE_COUNT = wavesKV["WaveCount"]
end

-- loads the creep and health data for each wave. Randomizes the creep order if 'chaos' is set to true
function loadWaveData(chaos)
    local settings = GameSettingsKV.GameLength["Normal"]
    if EXPRESS_MODE then
        WAVE_COUNT = wavesKV["WaveCountExpress"]
        settings = GameSettingsKV.GameLength["Express"]
    end

    if COOP_MAP then
        WAVE_COUNT = wavesKV["WaveCountCoop"]
        settings = GameSettingsKV.GameLength["Coop"]
    end

    local baseHP = tonumber(settings["BaseHP"])
    local multiplier = tonumber(settings["Multiplier"])

    -- coop scaling
    local multiplier_2_wave = settings["Wave_2"] and tonumber(settings["Wave_2"])
    local multiplier_2 = settings["Multiplier_2"] and tonumber(settings["Multiplier_2"])
    local multiplier_3_wave = settings["Wave_3"] and tonumber(settings["Wave_3"])
    local multiplier_3 = settings["Multiplier_3"] and tonumber(settings["Multiplier_3"])

    for i=1,WAVE_COUNT do
        if EXPRESS_MODE then
           WAVE_CREEPS[i] = wavesKV[tostring(i)].CreepExpress
        else
    	   WAVE_CREEPS[i] = chaos and wavesKV[tostring(i)].CreepChaos or wavesKV[tostring(i)].Creep
        end

        if COOP_MAP and wavesKV[tostring(i)].CreepCoop then
            WAVE_CREEPS[i] = wavesKV[tostring(i)].CreepChaos or wavesKV[tostring(i)].CreepCoop
        end

        -- Standard health formula: Last Wave HP * Multiplier
        -- Coop health formula: 
            -- Last Wave HP * Multiplier if its below Multiplier_2
            -- Last Wave HP * Multiplier_2 if its below Multiplier_3
            -- Last Wave HP * Multiplier_3 otherwise
        if i==1 then
            WAVE_HEALTH[i] = baseHP
        else
            if COOP_MAP then
                if multiplier_3 and i >= multiplier_3_wave then
                    WAVE_HEALTH[i] = WAVE_HEALTH[i-1] * multiplier_3
                elseif multiplier_2 and i >= multiplier_2_wave then
                    WAVE_HEALTH[i] = WAVE_HEALTH[i-1] * multiplier_2
                else
                    WAVE_HEALTH[i] = WAVE_HEALTH[i-1] * multiplier
                end
            else
                WAVE_HEALTH[i] = WAVE_HEALTH[i-1] * multiplier
            end
        end
    end
    if chaos then
        local lastWaves = {}
        local k = WAVE_COUNT
        if not EXPRESS_MODE then
            for i = k - 1, k, 1 do
                lastWaves[i] =  WAVE_CREEPS[i]
                WAVE_CREEPS[i] = nil
            end
        elseif EXPRESS_MODE then
            lastWaves[k] = WAVE_CREEPS[k]
            WAVE_CREEPS[k] = nil
        end
        WAVE_CREEPS = shuffle(WAVE_CREEPS)
        if not EXPRESS_MODE then
            for i = k - 1, k, 1 do
                table.insert(WAVE_CREEPS, lastWaves[i])
            end
        elseif EXPRESS_MODE then
            table.insert(WAVE_CREEPS, lastWaves[k])
        end
    end

    -- Print and round the values
    for k,v in pairs(WAVE_CREEPS) do
        WAVE_HEALTH[k] = round(WAVE_HEALTH[k])
        if IsInToolsMode() and not GameSettings.abilitiesMode == "Challenge" then
            local armor = creepsKV[WAVE_CREEPS[k]].Ability1 and (creepsKV[WAVE_CREEPS[k]].Ability1):gsub("_armor", "")
            local ability = (creepsKV[WAVE_CREEPS[k]].Ability2 and (creepsKV[WAVE_CREEPS[k]].Ability2):gsub("creep_ability_", "")) or ""
            print(string.format("%2d | %-16s | %6.0f | %9s | %10s ",k,v,WAVE_HEALTH[k],armor,ability))
        end
    end
end

-- starts the break timer for the specified player.
-- the next wave spawns once the break time is over
function StartBreakTime(playerID, breakTime, rush_wave)
    local ply = PlayerResource:GetPlayer(playerID)
    local hero = PlayerResource:GetSelectedHeroEntity(playerID)
    local playerData = GetPlayerData(playerID)
    if hero then 
        hero:RemoveModifierByName("modifier_silence")
    end

    -- let's figure out how long the break is
    local wave = playerData.nextWave
    if GameSettings:GetGamemode() == "Competitive" and GameSettings:GetEndless() == "Normal" then
        wave = CURRENT_WAVE
    elseif rush_wave then
        wave = rush_wave
    end

    ElementTD:PrecacheWave(wave)

    local msgTime = 5 -- how long to show the message for
    if (wave - 1) % 5 == 0 and not EXPRESS_MODE and wave ~= GameSettings.length.Wave then
        breakTime = 30
    end

    -- First boss breaktime 60 seconds
    if not EXPRESS_MODE and wave == WAVE_COUNT and CURRENT_BOSS_WAVE == 0 then
        breakTime = 60
    end

    if msgTime >= breakTime then
        msgTime = breakTime - 0.5
    end

    Log:debug("Starting break time for " .. GetPlayerName(playerID).. " for wave "..wave)
    if ply then
        local bShowButton = GameSettings:GetGamemode() ~= "Competitive" or (PlayerResource:GetPlayerCount() == 1 and wave == GameSettings.length.Wave)
        CustomGameEventManager:Send_ServerToPlayer( ply, "etd_update_wave_timer", { time = breakTime, button = bShowButton } )
    end

    ShowWaveBreakTimeMessage(playerID, wave, breakTime, msgTime)

    if PlayerIsAlive(playerID) then
        -- Update portal
        local sector = playerData.sector + 1
        ShowPortalForSector(sector, wave, playerID)
    
        -- Grant Lumber and Essence to all players the moment the next wave is set
        if WaveGrantsLumber(wave - 1) and wave ~= GameSettings.length.Wave then
            ModifyLumber(playerID, 1)
            if IsPlayerUsingRandomMode( playerID ) then
                Notifications:ClearBottom(playerID)
                local element = GetRandomElementForPlayerWave(playerID, wave-1)

                Log:info("Randoming element for player "..playerID..": "..element)

                if element == "pure" then
                    SendEssenceMessage(playerID, "#etd_random_essence")
                    ModifyLumber(playerID,-1)
                    ModifyPureEssence(playerID, 1)
                    playerData.pureEssenceTotal = playerData.pureEssenceTotal + 1
                    playerData.pureEssencePurchase = playerData.pureEssencePurchase + 1

                    -- Track pure essence purchasing as part of the element order
                    playerData.elementOrder[#playerData.elementOrder+1] = "Pure"

                    -- Gold bonus for Pure Essence randoming (removed in 1.5)
                    -- GivePureEssenceGoldBonus(playerID)
                else
                    SendEssenceMessage(playerID, "#etd_random_elemental")
                    SummonElemental({caster = playerData.summoner, Elemental = element .. "_elemental"})
                end
            else
                Log:info("Giving 1 lumber to " .. playerData.name)
            end
        end

        if WaveGrantsEssence(wave-1) then
            ModifyPureEssence(playerID, 1) 
            Log:info("Giving 1 pure essence to " .. playerData.name)
            playerData.pureEssenceTotal = playerData.pureEssenceTotal + 1
        end
    end

    -- create the actual timer
    Timers:CreateTimer("SpawnWaveDelay"..playerID, {
        endTime = breakTime,
        callback = function()

            if wave == WAVE_COUNT and not EXPRESS_MODE then
                CURRENT_BOSS_WAVE = 1
                if PlayerIsAlive(playerID) then
                    Log:info("Spawning the first boss wave for ["..playerID.."]")            
                    playerData.iceFrogKills = 0
                    playerData.bossWaves = CURRENT_BOSS_WAVE
                end
                ShowBossWaveMessage(playerID, CURRENT_BOSS_WAVE)
            else
                if PlayerIsAlive(playerID) then
                    Log:info("Spawning wave " .. wave .. " for ["..playerID.."]")
                end
                ShowWaveSpawnMessage(playerID, wave)
            end

            if wave == 1 then
                EmitAnnouncerSoundForPlayer("announcer_announcer_battle_begin_01", playerID)
            end

            -- update wave info
            UpdateWaveInfo(playerID, wave)

            -- spawn dat wave
            if PlayerIsAlive(playerID) then
                SpawnWaveForPlayer(playerID, wave) 
            end
        end
    })
end

-- Calls StartBreakTime on the dead players, only once per wave, used for Rush mode
function StartBreakTime_DeadPlayers(playerID, breakTime, wave)
    for _,v in pairs(playerIDs) do
        local hero = PlayerResource:GetSelectedHeroEntity(v)
        if not PlayerIsAlive(playerID) and hero.rush_wave ~= wave then
            hero.rush_wave = wave --Keep track to don't update a wave info twice
            StartBreakTime(v, breakTime, wave)
        end
    end
end

function SpawnEntity(entityClass, playerID, position, waveNumber)
    local entity = CreateUnitByName(entityClass, position, true, nil, nil, DOTA_TEAM_NEUTRALS)
    if entity then
        entity:AddNewModifier(nil, nil, "modifier_phased", {})

        entity:SetDeathXP(0)
        entity.class = entityClass
        entity.playerID = playerID

        -- give this creep its elemental armor ability
        local armorType = creepsKV[entityClass]["CreepAbility1"]
        if armorType and armorType ~= "" then
            AddAbility(entity, armorType)
            entity.armorType = armorType
        else
            Log:warn("Could not find armor ability for " .. creepClass)
        end

        -- create a script object for this entity
        local scriptObject
        local scriptClassName = GetUnitKeyValue(entityClass, "ScriptClass") or "CreepBasic"
        if CHALLENGE_MODE and waveNumber < WAVE_COUNT - 1 then
            scriptObject = ClassWrapper:new()
            local abilities = AbilitiesMode:GetChallengeAbilitiesForWave(waveNumber)

            for _, ability in pairs(abilities) do
                AddAbility(entity, ability)
                scriptClassName = AbilitiesMode:GetClassNameFromAbility(ability)
                scriptObject:Wrap(scriptClassName, CREEP_CLASSES[scriptClassName](entity, entityClass))
             end
        else
            scriptObject = CREEP_CLASSES[scriptClassName](entity, entityClass)  

            local ability = creepsKV[entityClass]["CreepAbility2"]
            if ability and ability ~= "" then
                AddAbility(entity, ability)
            end
        end

        entity.scriptObject = scriptObject
        CREEP_SCRIPT_OBJECTS[entity:entindex()] = scriptObject
        
        -- tint this creep if keyvalue ModelColor is set
        local modelColor = GetUnitKeyValue(entityClass, "ModelColor")
        if modelColor then
            modelColor = split(modelColor, " ")
            entity:SetRenderColor(tonumber(modelColor[1]), tonumber(modelColor[2]), tonumber(modelColor[3]))
        end

        if GetUnitKeyValue(entityClass, "ParticleEffect") then
            local particle = ParticleManager:CreateParticle(GetUnitKeyValue(entityClass, "ParticleEffect"), 2, entity) 
            ParticleManager:SetParticleControlEnt(particle, 0, entity, 5, "attach_origin", entity:GetOrigin(), true)
        end

        -- Adjust slows multiplicatively
        entity:AddNewModifier(entity, nil, "modifier_slow_adjustment", {})

        -- Add to scoreboard remaining count
        if not COOP_MAP then
            local playerData = GetPlayerData(playerID)
            playerData.remaining = playerData.remaining + 1
            UpdateScoreboard(playerID)
        end

        return entity
    else
        Log:error("Attemped to create unknown creep type: " .. entityClass)
        return nil
    end
end

-- spawn the wave for the specified player
function SpawnWaveForPlayer(playerID, wave)
    local waveObj = Wave(playerID, wave)
    local playerData = GetPlayerData(playerID)
    local sector = playerData.sector + 1
    local startPos = EntityStartLocations[sector]
    local ply = PlayerResource:GetPlayer(playerID)

    -- First wave marks the start of the game
    if START_GAME_TIME == 0 then
        START_GAME_TIME = GameRules:GetGameTime()
    end

    playerData.waveObject = waveObj
    if wave == WAVE_COUNT then
        playerData.waveObjects[WAVE_COUNT+playerData.bossWaves] = waveObj
        if playerData.bossWaves + 1 > CURRENT_BOSS_WAVE then
            CURRENT_BOSS_WAVE = playerData.bossWaves + 1
        end
    end
    playerData.waveObjects[wave] = waveObj

    CustomGameEventManager:Send_ServerToAllClients("SetTopBarWaveValue", {playerId=playerID, wave=wave} )

    if not InterestManager:IsStarted() then
        InterestManager:StartInterest()
    end
    if GameSettings:GetEndless() ~= "Endless" then
        InterestManager:CheckForIncorrectPausing(playerID)
    end

    waveObj:SetOnCompletedCallback(function()
        if playerData.health == 0 then
            return
        end

        playerData.completedWaves = playerData.completedWaves + 1
        print("Player [" .. playerID .. "] has completed wave "..playerData.completedWaves)
        InterestManager:PlayerCompletedWave(playerID, wave)
        
        if GameSettings:GetEndless() == "Normal" then
            playerData.nextWave = playerData.nextWave + 1
        end
        if ply then
            EmitSoundOnClient("ui.npe_objective_complete", ply)
        end

        -- Boss Wave completed starts the new one with no breaktime
        if playerData.completedWaves >= WAVE_COUNT and not EXPRESS_MODE then
            local bossWaveNumber = playerData.completedWaves - WAVE_COUNT + 1
            print("Player [" .. playerID .. "] has completed boss wave "..bossWaveNumber)

            -- Boss wave score
            playerData.scoreObject:UpdateScore(SCORING_BOSS_WAVE_CLEAR, wave)

            playerData.bossWaves = playerData.bossWaves + 1
            Log:info("Spawning boss wave " .. playerData.bossWaves .. " for ["..playerID.."] ".. playerData.name)
        
            UpdateWaveInfo(playerID, wave) -- update wave info
            ShowBossWaveMessage(playerID, playerData.bossWaves)
            SpawnWaveForPlayer(playerID, WAVE_COUNT) -- spawn the next boss wave
            
            return
        end

        -- Cleared/completed game
        local finishedExpress = EXPRESS_MODE and playerData.completedWaves == WAVE_COUNT
        local clearedNormal = not EXPRESS_MODE and playerData.completedWaves == WAVE_COUNT - 1
        if finishedExpress or clearedNormal then
            playerData.clearTime = GameRules:GetGameTime() - START_GAME_TIME -- Used to determine the End Speed Bonus
            playerData.scoreObject:UpdateScore( SCORING_WAVE_CLEAR, wave )
            Timers:CreateTimer(2, function()
                playerData.scoreObject:UpdateScore( SCORING_GAME_CLEAR )
            end)

            if finishedExpress then
                Log:info("Player ["..playerID.."] has completed the game.")
                GameRules:SendCustomMessage("<font color='" .. playerColors[playerID] .."'>" .. playerData.name .. "</font> has completed the game!", 0, 0)
                playerData.duration = GameRules:GetGameTime() - START_GAME_TIME
                playerData.victory = 1
                UpdateScoreboard(playerID, true)
                ElementTD:CheckGameEnd()
                return
            end
        else
            playerData.scoreObject:UpdateScore( SCORING_WAVE_CLEAR, wave )
        end

        -- First player to finish the wave sets the next wave
        if playerData.completedWaves == CURRENT_WAVE then
            print("Player: " .. playerData.name .. " [" .. playerID .. "] is the first to complete wave " .. CURRENT_WAVE)

            if PlayerResource:GetPlayerCount() > 1 then
                local color = playerColors[sector-1]
                GameRules:SendCustomMessage("<font color='"..color.."'>"..playerData.name.."</font> is the first to complete Wave " .. CURRENT_WAVE, 0, 0)
            end

            -- Next wave
            CURRENT_WAVE = playerData.nextWave
            if GameSettings:GetGamemode() == "Competitive" and GameSettings:GetEndless() ~= "Endless" then
                CompetitiveNextRound(CURRENT_WAVE)
            end
        end

        if GameSettings:GetGamemode() ~= "Competitive" and GameSettings:GetEndless() ~= "Endless" then
            StartBreakTime(playerID, GetPlayerDifficulty(playerID):GetWaveBreakTime(playerData.nextWave))
        end

        playerData.waveObjects[waveObj.waveNumber] = nil
    end)

    waveObj:SpawnWave()
end

-- give 1 lumber every 5 waves or every 3 if express mode ignoring the last wave (55/50/30)
function WaveGrantsLumber( wave )
    if wave == 0 then return end
    if COOP_MAP then
        return wave % 5 == 0 and wave < 50
    elseif EXPRESS_MODE then
        return wave % 3 == 0 and wave < 30
    else
        return wave % 5 == 0 and wave < 55
    end
end

-- pure essence at waves 50/55, 24/27 in express, 45/50 on coop
function WaveGrantsEssence( wave )
    if wave == 0 then return end
    if COOP_MAP then
        return wave == 45 or wave == 50
    elseif EXPRESS_MODE then
        return wave == 24 or wave == 27
    else
        return wave == 50 or wave == 55
    end
end

function ShowPortalForSector(sector, wave, playerID)
    local element = string.gsub(creepsKV[WAVE_CREEPS[wave]].CreepAbility1, "_armor", "")
    local portal = SectorPortals[sector]
    if not portal then return end

    local origin = portal:GetAbsOrigin()
    origin.z = origin.z - 200
    origin.y = origin.y - 70

    ClosePortalForSector(playerID, sector, true)

    local particleName = "particles/custom/portals/spiral.vpcf"
    portal.particle = ParticleManager:CreateParticle(particleName, PATTACH_CUSTOMORIGIN, nil)
    ParticleManager:SetParticleControl(portal.particle, 0, origin)
    ParticleManager:SetParticleControl(portal.particle, 15, GetElementColor(element))
    
    -- Portal World Notification
    if COOP_MAP then
        Timers:CreateTimer(0.1, function()
            if COOP_WAVE_LANE_LEAKS[sector] and COOP_WAVE_LANE_LEAKS[sector] > 0 then
                CustomGameEventManager:Send_ServerToAllClients("world_notification", {entityIndex = portal:GetEntityIndex(), text = "#etd_wave_"..element, leaked = COOP_WAVE_LANE_LEAKS[sector]})
                portal.leaked = true
            else
                CustomGameEventManager:Send_ServerToAllClients("world_notification", {entityIndex = portal:GetEntityIndex(), text = "#etd_wave_"..element})
                portal.leaked = false
            end
        end)
    else
        local player = PlayerResource:GetPlayer(playerID)
        if player then 
            CustomGameEventManager:Send_ServerToPlayer(player, "world_notification", {entityIndex = portal:GetEntityIndex(), text = "#etd_wave_"..element})
        end
    end
  
end

function ClosePortalForSector(playerID, sector, removeInstantly)
    local portal = SectorPortals[sector]
    if not IsValidEntity(portal) then return end
    if portal.particle then
        ParticleManager:DestroyParticle(portal.particle, removeInstantly or false)
    end

    if COOP_MAP then
        if not portal.leaked then
            CustomGameEventManager:Send_ServerToAllClients("world_remove_notification", {entityIndex = portal:GetEntityIndex()})
            portal.leaked = false
        end
    else
        local player = PlayerResource:GetPlayer(playerID)
        if player then 
            CustomGameEventManager:Send_ServerToPlayer(player, "world_remove_notification", {entityIndex = portal:GetEntityIndex()})
        end
    end
end

function CreateMoveTimerForCreep(creep, sector)
    local destination = EntityEndLocations[sector]
    Timers:CreateTimer(0.1, function()
        if IsValidEntity(creep) and creep:IsAlive() then
            creep:MoveToPosition(destination)
            if (creep:GetAbsOrigin() - destination):Length2D() <= 100 then
                local playerID = creep.playerID
                local playerData = GetPlayerData(playerID)
                
                if GameSettings:GetEndless() ~= "Endless" then
                    InterestManager:PlayerLeakedWave(playerID, creep.waveObject.waveNumber)
                end

                -- Boss Wave leaks = 3 lives
                local lives = 1
                if playerData.completedWaves + 1 >= WAVE_COUNT and not EXPRESS_MODE then
                    lives = 3
                end

                -- Bulky creeps count as 2
                if creep:HasAbility("creep_ability_bulky") then
                    lives = lives * 2
                end
                
                ReduceLivesForPlayer(playerID, lives)

                creep.recently_leaked = true
                Timers:CreateTimer(10, function()
                    if IsValidEntity(creep) then creep.recently_leaked = nil end
                end)

                FindClearSpaceForUnit(creep, EntityStartLocations[playerData.sector + 1], true)
                creep:SetForwardVector(Vector(0, -1, 0))
            end
            return 0.1
        else
            return
        end
    end)
end

-- If the game mode is competitive spawn the next wave for all players after breaktime
function CompetitiveNextRound(wave)
    for _,v in pairs(playerIDs) do
        StartBreakTime(v, GetPlayerDifficulty(v):GetWaveBreakTime(wave))
    end
end

function ReduceLivesForPlayer(playerID, lives)
    local playerData = GetPlayerData(playerID)
    local hero = PlayerResource:GetSelectedHeroEntity(playerID)
    local ply = PlayerResource:GetPlayer(playerID)

    -- Cheats can melt steel beams
    if playerData.zenMode or playerData.godMode then
        lives = 0
        return
    end

    playerData.health = playerData.health - lives
    if COOP_MAP then
        COOP_HEALTH = playerData.health
    end

    local maxLives = GameSettings:GetMapSetting("Lives")
    if playerData.health <= 0 then
        playerData.health = 0

        if hero then
            hero:ForceKill(false)
        end

        if playerData.completedWaves + 1 >= WAVE_COUNT and not EXPRESS_MODE then
            playerData.scoreObject:UpdateScore( SCORING_GAME_FINISHED )
        else
            playerData.scoreObject:UpdateScore( SCORING_WAVE_LOST )
        end
        ElementTD:EndGameForPlayer(playerID) -- End the game for the dead player
    elseif PlayerIsAlive(playerID) then
        
        if COOP_MAP then
            playerData.waveObject.leaks = CURRENT_WAVE_OBJECT.leaks
        else
            playerData.waveObject.leaks = playerData.waveObject.leaks + lives
        end
        
        if hero and playerData.health < maxLives then --When over max health, HP loss is covered by losing modifier_bonus_life
            hero:SetHealth(playerData.health)
        end
    end

    Sounds:EmitSoundOnClient(playerID, "ETD.Leak")

    if hero then
        hero:CalculateStatBonus(true)
        UpdatePlayerHealth(playerID)
        CustomGameEventManager:Send_ServerToAllClients("SetTopBarPlayerHealth", {playerId=playerID, health=playerData.health/hero:GetMaxHealth() * 100} )
    end

    UpdateScoreboard(playerID)
end