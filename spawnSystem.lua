local spawnSystem = {}

require("custom.spawnSystem.spawnConfig")

local spawnTable = {
    cell = {},
    refId = {},
    uniqueIndex = {},
    npcTemplates = {},
    creatureTemplates = {},
    inventoryTemplates = {}
}

local pendingCells = {}

function spawnSystem.buildInventory(templateName)
    local templateData = spawnTable.inventoryTemplates[templateName]
end

function spawnSystem.buildNpc(templateName)
    local templateData = spawnTable.npcTemplates[templateName]
    local recordData = {autoCalc = 1}
    local recordStore = RecordStores["npc"]
    local tempGender
    local id = recordStore:GenerateRecordId()
    local pid = tableHelper.getAnyValue(Players).pid

    tes3mp.LogMessage(enumerations.log.INFO,"SpawnSystem: Building custom NPC record "..id.." for "..templateName)

    for key,value in pairs(templateData) do
        if type(value) == "table" then
            local rand = math.random(1,table.getn(value))
            recordData[key] = value[rand]
            tes3mp.LogMessage(enumerations.log.INFO,"SpawnSystem: table "..key.." = "..value[rand])
        else
            if key == "gender" then
                if value == "male" then
                    tempGender = 1
                elseif value == "female" then
                    tempGender = 0
                end
                recordData[key] = tempGender
            else
                recordData[key] = value
            end
            tes3mp.LogMessage(enumerations.log.INFO,"SpawnSystem: string "..key.." = "..value)
        end
    end

    for _,setting in pairs(spawnConfig.npcRequired) do
        if recordData[setting] == nil then
            if setting == "name" then
                recordData[setting] = templateName
            elseif setting == "level" then
                recordData[setting] = math.random(spawnConfig.level[1],spawnConfig.level[2])
            elseif setting == "race" or setting == "class" then
                recordData[setting] = spawnConfig[setting][math.random(1,table.getn(spawnConfig[setting]))]
            elseif setting == "gender" then
                recordData[setting] = math.random(0,1)
                tempGender = spawnConfig[setting][recordData[setting]+1]
            elseif setting == "hair" or setting == "head" then
                local appearanceTable = spawnConfig.npcInfo[recordData.race][tempGender][setting]
                recordData[setting] = appearanceTable[math.random(1,table.getn(appearanceTable))]
            end
        end
        tes3mp.LogMessage(enumerations.log.INFO,"SpawnSystem: "..setting.." = "..recordData[setting])
    end

    recordStore.data.generatedRecords[id] = recordData
    for _, player in pairs(Players) do
        if not tableHelper.containsValue(Players[pid].generatedRecordsReceived, id) then
            table.insert(player.generatedRecordsReceived, id)
        end
    end
    recordStore:Save()
    tes3mp.ClearRecords()
    tes3mp.SetRecordType(enumerations.recordType[string.upper("npc")])
    packetBuilder.AddNpcRecord(id, recordData)
    tes3mp.SendRecordDynamic(pid, true, false)
    tes3mp.LogMessage(enumerations.log.INFO,"SpawnSystem: Finished Building custom NPC record "..id.." for "..templateName)

    return id
end

function spawnSystem.buildCreature(templateName)
    local templateData = spawnTable.creatureTemplates[templateName]
end

function spawnSystem.spawnAtActors(spawnList,cellDescription)
    local objects = {}
    for _,spawn in pairs(spawnList) do
        local numSpawns = spawn.spawnData.count
        local objectData = spawnSystem.getSpawnData(spawn.spawnData)
        objectData.location = spawn.location

        if spawn.spawnData.useMult then
            numSpawns = math.floor(numSpawns*spawnConfig.spawnMult)
        end
        if numSpawns >=1 then
            for i=1,numSpawns do
                table.insert(objects,objectData)
            end
        end
    end
    if not tableHelper.isEmpty(objects) then
        logicHandler.CreateObjects(cellDescription,objects,"spawn")
    end
end

function spawnSystem.getSpawnData(spawn)
    local object = {}
    if spawn.template ~= nil then
        tes3mp.LogMessage(enumerations.log.WARN,"SpawnSystem: DEBUG template found "..spawn.template)
        if spawnTable.npcTemplates[spawn.template] ~= nil then
            object.refId = spawnSystem.buildNpc(spawn.template)
            tes3mp.LogMessage(enumerations.log.WARN,"SpawnSystem: DEBUG template built "..spawn.template.." refId "..object.refId)
        elseif spawnTable.creatureTemplates[spawn.template] ~= nil then
            object.refId = spawnSystem.buildCreature(spawn.template)
        end
    else
        object.refId = spawn.refId
        tes3mp.LogMessage(enumerations.log.WARN,"SpawnSystem: DEBUG refId found "..spawn.refId)
    end
    if spawn.scale ~= nil then
        object.scale = spawn.scale
    else
        object.scale = 1
    end
    return object
end

function spawnSystem.processActors(cellDescription)
    local cellData = LoadedCells[cellDescription].data

    tes3mp.LogMessage(enumerations.log.INFO,"SpawnSystem: Processing Actor based spawns for "..cellDescription)

    local spawnList = {}
    --Identify actors in cell we want to do anything with
    for _,uniqueIndex in pairs(cellData.packets.actorList) do
        --Skip actors placed via cell spawns
        if pendingCells[cellDescription] ~= nil and tableHelper.containsValue(pendingCells[cellDescription],uniqueIndex) and spawnConfig.actorSpawnOnCellSpawn == false then
            tes3mp.LogMessage(enumerations.log.INFO,"SpawnSystem: Skipped Actor with uniqueIndex " ..uniqueIndex.." because they were spawned by the cell spawn list for "..cellDescription)
        else
            local actor = cellData.objectData[uniqueIndex]
            if actor.location ~= nil then
                if spawnTable.uniqueIndex[uniqueIndex] ~= nil then
                    for _,spawn in pairs(spawnTable.uniqueIndex[uniqueIndex]) do
                        table.insert(spawnList,{spawnData = spawn, location = actor.location })
                    end
                    tes3mp.LogMessage(enumerations.log.INFO,"SpawnSystem: Actor matched by Unique Index: "..uniqueIndex.."|"..actor.refId.."|"..actor.location.posX.."|"..actor.location.posY.."|"..actor.location.posZ)
                end
                if spawnTable.refId[actor.refId] ~= nil then
                    for _,spawn in pairs(spawnTable.refId[actor.refId]) do
                        table.insert(spawnList,{spawnData = spawn, location = actor.location})
                    end
                    tes3mp.LogMessage(enumerations.log.INFO,"SpawnSystem: Actor matched by RefId: "..uniqueIndex.."|"..actor.refId.."|"..actor.location.posX.."|"..actor.location.posY.."|"..actor.location.posZ)
                end
            else
                tes3mp.LogMessage(enumerations.log.WARN,"SpawnSystem: Actor Location not found for "..uniqueIndex.."|"..actor.refId)
            end
        end
    end
    spawnSystem.spawnAtActors(spawnList,cellDescription)
    tableHelper.removeValue(pendingCells,cellDescription)
    tes3mp.LogMessage(enumerations.log.INFO,"SpawnSystem: Removed cell " .. cellDescription .." from cells pending spawns")
end

function spawnSystem.processCell(cellDescription)
    tes3mp.LogMessage(enumerations.log.INFO,"SpawnSystem: Processing Cell based spawns for "..cellDescription)
    if pendingCells[cellDescription] == nil then
        local placeObjects = {}
        local spawnObjects = {}
        local uniqueIndexes = {}
        local totalPlace = 0
        local totalSpawn = 0
        for _,spawn in pairs(spawnTable.cell[cellDescription]) do
            local object = {}
            if spawn.packetType == "spawn" then
                tes3mp.LogMessage(enumerations.log.WARN,"SpawnSystem: DEBUG spawn packet type")
                object = spawnSystem.getSpawnData(spawn)
                object.location = spawn.location
                for i=1,spawn.count do
                    table.insert(spawnObjects,object)
                    totalSpawn = totalSpawn + 1
                end
            elseif spawn.packetType == "place" then
                object.refId = spawn.refId
                object.location = spawn.location
                object.count = spawn.count
                object.charge = -1
                object.enchantmentCharge = -1
                object.soul = -1
                if spawn.scale ~= nil then
                    object.scale = spawn.scale
                else
                    object.scale = 1
                end
                table.insert(placeObjects,object)
                totalPlace = totalPlace + 1
            end
        end
        uniqueIndexes = logicHandler.CreateObjects(cellDescription,placeObjects,"place")
        tableHelper.merge(uniqueIndexes,logicHandler.CreateObjects(cellDescription,spawnObjects,"spawn"),true)
        tes3mp.LogMessage(enumerations.log.INFO,"SpawnSystem: Placed "..totalPlace.." objects and spawned "..totalSpawn.." actors for "..cellDescription)
        pendingCells[cellDescription] = uniqueIndexes
    else
        tes3mp.LogMessage(enumerations.log.WARN,"SpawnSystem: Skipped spawns for cell "..cellDescription.." because spawns have already been processed")
    end
end

function spawnSystem.OnActorList(eventStatus,pid,cellDescription,actors)
    if eventStatus.validCustomHandlers and eventStatus.validDefaultHandler then
        if tableHelper.containsValue(pendingCells,cellDescription) then
            --process cell immediately because we don't have to wait for position data
            if spawnTable.cell[cellDescription] ~= nil then
                spawnSystem.processCell(cellDescription)
            end

            --process actors
            local actorListTimer = tes3mp.CreateTimerEx("spawnSystemTimerFunc",spawnConfig.actorSpawnTimer,"s",cellDescription)
            tes3mp.StartTimer(actorListTimer)
        end
    end
end

function spawnSystemTimerFunc(cellDescription)
    LoadedCells[cellDescription]:SaveActorPositions()
    spawnSystem.processActors(cellDescription)
end

function spawnSystem.OnCellLoad(eventStatus,pid,cellDescription)
    if eventStatus.validCustomHandlers and eventStatus.validDefaultHandler then
        if LoadedCells[cellDescription].data.loadState.hasFullActorList ~= true then
            table.insert(pendingCells,cellDescription)
            tes3mp.LogMessage(enumerations.log.INFO,"SpawnSystem: Added cell " .. cellDescription .." to cells pending spawns")
        end
    end
end

--Merge spawn jsons together
function spawnSystem.init()
    for _,tableEntry in pairs(spawnConfig.spawnTables) do
        local jsonTable = jsonInterface.load("custom/spawnData/"..tableEntry.name)
        tes3mp.LogMessage(enumerations.log.INFO,"SpawnSystem: Loading "..tableEntry.name.." into spawn table")
        --spawnType will be cell, refId, uniqueIndex, npcTemplates, or creatureTemplates
        for spawnType,subTable in pairs(jsonTable) do
            if tableHelper.isEmpty(spawnTable[spawnType]) then
                spawnTable[spawnType] = subTable
            else 
                --id will be a cell id, refId, uniqueIndex, or templateName
                for id, spawnList in pairs(subTable) do
                    if spawnTable[spawnType][id] == nil then
                        spawnTable[spawnType][id] = spawnList
                    elseif tableEntry.mergeType == 0 then
                        spawnTable[spawnType][id] = spawnList
                        tes3mp.LogMessage(enumerations.log.INFO,"SpawnSystem: Overwriting "..spawnType.." entry for "..id.." with entry from "..tableEntry.name)
                    elseif tableEntry.mergeType == 1 then
                        if spawnType == "cell" or spawnType == "refId" or spawnType == "uniqueIndex" then
                            tes3mp.LogMessage(enumerations.log.INFO,"SpawnSystem: Merging "..spawnType.." entry for "..id.." with entry from "..tableEntry.name)
                            for _,spawn in pairs(spawnList) do
                                table.insert(spawnTable[spawnType][id],spawn)
                            end
                        else
                            tes3mp.LogMessage(enumerations.log.INFO,"SpawnSystem: Skipping "..spawnType.." entry for "..id.." from "..tableEntry.name.." because templates cannot be merged")
                        end
                    elseif tableEntry.mergeType == 2 then
                        tes3mp.LogMessage(enumerations.log.INFO,"SpawnSystem: Skipping "..spawnType.." entry for "..id.." from "..tableEntry.name)
                    end
                end
            end
        end
    end
    math.randomseed(os.time())
    math.random()
    math.random()
    math.random()
    math.random()
end

customEventHooks.registerHandler("OnCellLoad",spawnSystem.OnCellLoad)
customEventHooks.registerHandler("OnActorList",spawnSystem.OnActorList)
customEventHooks.registerHandler("OnServerPostInit",spawnSystem.init)