----------------------------------
-- Work in progress program for monitoring and controlling Minecraft mod Nuclear-craft Fusion reactor
-- Takes Fusion reactor(s) current efficiency, fuel tank(s) levels and energy storage(s) devices to dynamically control the reactor(s)
-- Incorporated GUI for easy setup of program initially
-- Displays information on graphs to show how variables have changed over time and current status
-- Co-routines used to multi-thread the program to make it quicker
-- Created in LUA for use with Minecraft mod Open-computers
---------------------------------

local component = require("component")
local term = require("term")
local sides = require("sides")
local event = require("event")
local gpu = component.gpu
local w, h = gpu.getResolution()

local DELAY = 1
local MASTERLISTLENGTH = math.floor(w/3 - w/12)

term.clear()

--------------------------- FORMATTING RELATED FUNCTIONS ---------------------------
function formatNumber(number)
    local list = {number = number, units = ""}
    if((number >= 1000000000000) or (number <= -1000000000000)) then
        list.number = tonumber(string.format("%.3f", number/1000000000000))
        list.units = "T"
    elseif((number >= 1000000000) or (number <= -1000000000)) then
        list.number = tonumber(string.format("%.3f", number/1000000000))
        list.units = "G"
    elseif((number >= 1000000) or (number <= -1000000)) then
        list.number = tonumber(string.format("%.3f", number/1000000))
        list.units = "M"
    elseif((number >= 1000) or (number <= -1000)) then
        list.number = tonumber(string.format("%.3f", number/1000))
        list.units = "K"
    else
        list.number = tonumber(string.format("%.3f", number))
        list.units = ""
    end
    return list
end

function formatTime(number)
    local list = {week = 0, day = 0, hour = 0, minute = 0, second = 0}
    repeat
        if((number > 604800) or (number < -604800)) then
            list.week = math.floor(number/604800)
            number = number%604800
        elseif((number > 86400) or (number < -86400)) then
            list.day = math.floor(number/86400)
            number = number%86400
        elseif((number > 3600) or (number < -3600)) then
            list.hour = math.floor(number/3600)
            number = number%3600
        elseif((number > 60) or (number < -60)) then
            list.minute = math.floor(number/60)
            number = number%60
        else
            list.second = math.floor(number)
            number = 0
        end
    until number == 0
    
    return list
end

--------------------------- REACTOR RELATED FUNCTIONS ---------------------------
function getReactors()
    local list = {}
    local i = 0
    for address,name in pairs(component.list("redstone")) do
        i = i + 1
        table.insert(list, i)
        list[i] = {reactorProxy = component.proxy(component.get(address)), fuelConfig = {" ", " "}, fuelOK = {}, energyOK = false, effOK = false, 
                   storedList = {}, gainList = {}, pos = 1, reachedMaxEff = false}
    end
    print("FOUND: "..i.." REACTORS.")
    return list
end

function getReactorEfficiency(proxy)
    return (90*(proxy.getComparatorInput(sides.south)))/15
end
   
function reactorMode(reactor)
    if reactor.fuelOK[1] and reactor.fuelOK[2] then
        if reactor.energyOK then
            if reactor.effOK then
                reactor.reactorProxy.setOutput(sides.south, 0)
                return true
            end
        end
    end    
    reactor.reactorProxy.setOutput(sides.south, 15)
    return false
end

function checkFuelLevels(reactor)
    local i = 1
    local returnList = {}
    for x, tank in pairs(tanks) do
        if (tank.name == reactor.fuelConfig[1] or tank.name == reactor.fuelConfig[2]) then
            if tank.fuelOK then
                returnList[i] = true
            else
                returnList[i] = false
            end
            i = i + 1
        end
    end
    return returnList
end

function checkEnergyLevels()
    for i, storage in pairs(energyDevices) do
        if storage.full == false then
            return false
        end
    end
    return true
end

function checkEfficiency(reactor)
    if reactor.storedList[reactor.pos] >= 90 then
        reactor.reachedMaxEff = true
    end
    if reactor.reachedMaxEff then
        if reactor.storedList[reactor.pos] < reactor.storedList[reactor.pos - 1] then
            return false
        end
    end
    return true
end

function updateReactors()
    local i = 1
    for x, reactor in pairs(reactors) do
        local efficiency = getReactorEfficiency(reactor.reactorProxy)
        reactor.pos = insertToList(reactor.storedList, efficiency, MASTERLISTLENGTH*10)
        reactor.energyOK = checkEnergyLevels()
        reactor.fuelOK[1], reactor.fuelOK[2] = checkFuelLevels(reactor)
        reactor.effOK = checkEfficiency(reactor)
        if reactor.pos > 1 then
            insertToList(reactor.gainList, math.floor((reactor.storedList[reactor.pos] - reactor.storedList[reactor.pos - 1])/(21*DELAY)), MASTERLISTLENGTH*10)
            local average = getAverageGain(reactor.gainList)
            esTime = estimateTime(92, average.number, reactor.storedList[reactor.pos])
            reactorGUI(x, efficiency, average, esTime, reactor.storedList, i, reactor.fuelConfig, (reactor.fuelOK[1] and reactor.fuelOK[2]), reactor.effOK, reactor.energyOK)
        end
        i = i + 13
    end
end

function getFuelConfigs()
    local fuelTable = {"Hydrogen","Deuterium","Tritium","Molten Lithium-6","Molten Lithium-7","Molten Boron-11"}
    for x, reactor in pairs(reactors) do
        writeToScreen({1, 2}, tostring("Reactor "..x..": Select fuel types"), false)
        local fuel = {}
        for i = 1, 2 do
            local list = getDrawButtons(#fuelTable, {x = w/20 , y = h/10}, 0x00FF00)
            placeTextOnButtons(list, fuelTable)
            fuel[i] = getMouseClick(list)
        end
        reactor.fuelConfig = fuel
        writeToScreen({1,h/2 - h/4 + x}, tostring("Reactor :"..x..": Fuel config: "..table.concat(reactor.fuelConfig, ", ")))
    end
end

--------------------------- TANKS RELATED FUNCTIONS ---------------------------
getTanks = coroutine.create(function()
    local list = {}
    local i = 0
    for address,name in pairs(component.list("tank_controller")) do
        for a,b in pairs(component.proxy(address).getFluidInTank(sides.up)) do
            if type(a) == "number" then    
                i = i + 1
                table.insert(list, i)
                list[i] = {tankController = component.proxy(address), fuelOK = false, name = b.label, 
                           threshold = nil, pos = 1, storedList = {}, gainList = {}, capacity = component.proxy(address).getTankCapacity(sides.up)}
                if list[i].capacity >= 10000000 then
                    list[i].threshold = 100000
                else
                    list[i].threshold = list[i].capacity*0.1
                end
            end
        end
    end
    return list
end)

function checkTankLevel(threshold, level)
    if threshold > level then
        return false
    else
        return true
    end
end

function updateTanks()
    local i = 1
    for x, tank in pairs(tanks) do
        local level = tank.tankController.getTankLevel(sides.up)
        tank.fuelOK = checkTankLevel(tank.threshold, level)
        tank.pos = insertToList(tank.storedList, level, MASTERLISTLENGTH)
        if tank.pos > 1 then
            insertToList(tank.gainList, math.floor((tank.storedList[tank.pos] - tank.storedList[tank.pos - 1])/(21*DELAY)), MASTERLISTLENGTH)
            local average = getAverageGain(tank.gainList)
            local levelFormatted = formatNumber(level)
            local esTime = estimateTime(tank.capacity, average.number, tank.storedList[tank.pos])
            fuelGUI(tank.name, average, levelFormatted, esTime, tank.gainList, i, x)
        end
        i = i + 13
    end    
end

--------------------------- LIST RELATED FUNCTIONS ---------------------------
function insertToList(list, value, listSize)    
    local listLength = #list
    if (listLength < listSize) then
        table.insert(list, value)
    else
        for i = 1, (listLength - 1) do
            list[i] = list[i + 1]
        end
        list[listLength] = value
    end
    return listLength
end

--------------------------- AVERAGE RELATED FUNCTIONS ---------------------------
function estimateTime(maxValue, averageGain, currentValue)
    if(averageGain > 0) then
        return formatTime((maxValue-currentValue)/(averageGain*20))
    else
        return formatTime((0 - currentValue)/(averageGain*20))
    end
end

function getAverageGain(list)
    local total = 0
    for i, value in pairs(list) do
        total = total + value    
    end
    return formatNumber(total/#list)
end

--------------------------- ENERGY RELATED FUNCTIONS ---------------------------
getEnergyStorages = coroutine.create(function()
    local list = {}
    local i = 0
    for address,name in pairs(component.list("draconic_rf_storage")) do
      i = i + 1
      table.insert(list, i)
      list[i] = {device = "Core", storageProxy = component.proxy(address), pos = 1, storedList = {}, gainList = {}, capacity = component.proxy(address).getMaxEnergyStored(), full = false}
    end
    for address,name in pairs(component.list("energy_device")) do
      i = i + 1
      table.insert(list, i)
      list[i] = {device = "Storage", storageProxy = component.proxy(address), pos = 1, storedList = {}, gainList = {}, capacity = component.proxy(address).getMaxEnergyStored(), full = false}
    end
    return list
end)

function updateStorage()
    local i = 1
    for x,storage in pairs(energyDevices) do 
        local energy = storage.storageProxy.getEnergyStored()
        storage.pos = insertToList(storage.storedList, energy, MASTERLISTLENGTH)
        storage.full = isFull(storage.capacity, energy)
        if storage.pos > 1 then
            insertToList(storage.gainList, math.floor((storage.storedList[storage.pos] - storage.storedList[storage.pos - 1])/(21*DELAY)), MASTERLISTLENGTH)
            local average = getAverageGain(storage.gainList)
            local energyFormatted = formatNumber(energy)
            local esTime = estimateTime(storage.capacity, average.number, storage.storedList[storage.pos])
            storageGUI(storage.device, average, energyFormatted, esTime, storage.gainList, i, x)
        else
        end
        i = i + 13
    end    
end

function isFull(capacity, energy)
    if((capacity - energy) < 10000) then
        return true
    else
        return false
    end 
end

--------------------------- BUTTON RELATED FUNCTIONS ---------------------------
function getDrawButtons(amount, posScreen, bColor, rowWidth)
    if rowWidth == nil then
        rowWidth = w
    end
    local temp = posScreen.x
    local list = {}
    gpu.setBackground(bColor)
    for i = 1, amount do
        if((posScreen.x + w/8) >= rowWidth) then
            posScreen.x = temp
            posScreen.y = posScreen.y + h/10 + 2
        end
        gpu.fill(posScreen.x, posScreen.y, w/8, h/10, " ")
        table.insert(list, i)
        list[i] =  {posScreen.x, posScreen.y, w/8, h/10, 1, nil}
        posScreen.x = posScreen.x + w/8 + 5
    end
    
    return list
end    

function placeTextOnButtons(buttonList, textList)
    for i, v in pairs(buttonList) do
        writeToScreen({v[1] + v[3]/2, v[2] + v[4]/2}, textList[i], true)
        v[6] = textList[i]
    end
    
    return buttonList
end
    
function getMouseClick(buttonList)
    local i = 0
    local x = nil
    repeat
        x = click(buttonList)
        if type(x) == "string" then
            i = i + 1
        end            
    until i == 2
    return x
end

function click(buttonList)
    local state,_,x,y = event.pull(1, touch)
    if(x ~= nil and y ~= nil) then
        x = checkForButtonClick(x, y, buttonList)
    end
    return x
end

function buttonClicked(text, pos, status)
    if status then
        gpu.setBackground(0xFF0000)
    else
        gpu.setBackground(0x00FF00)
    end
    gpu.fill(pos[1], pos[2], pos[3], pos[4], " ")
    writeToScreen({pos[1] + pos[3]/2, pos[2] + pos[4]/2}, text, true)
    gpu.setBackground(0x000000)
end

function checkForButtonClick(x, y, buttonList)
    for i, v in pairs(buttonList) do 
        local xDif = v[1] + v[3]
        local yDif = v[2] + v[4]
        if((x >= v[1] and x <= xDif) and (y >= v[2] and y <= yDif)) then
            if( v[5] < 4) then
                status = true
                v[5] = v[5] + 1
            else
                status = false
                v[5] = 1
            end
            buttonClicked(v[6], {v[1], v[2], v[3], v[4]}, status)
            return v[6]
        end
    end
    return false
end

--------------------------- GUI TEXT RELATED FUNCTIONS ---------------------------
function clearScreen()
    gpu.setBackground(0x000000)
    gpu.fill(1, 1, w, h, " ")
    return true
end
    
function centerText(str, pos)
    return {pos[1] - (string.len(str)/2), pos[2]}
end

function emptyColText()
    local empty = {}
    for i = 1, ((w/3)/2) do
        empty[i] = " "
    end
    
    return table.concat(empty, " ")
end

function writeToScreen(pos, text, centre, lineWipe, colStart)
    if(lineWipe) then
        term.setCursor(colStart, pos[2])
        term.write(emptyColLine)
    end
    if(centre) then
        pos = centerText(text, pos)
    end
    term.setCursor(pos[1], pos[2])
    term.write(text)
    return true
end

function writeEstimateToScreen(pos, esTime, mode, colStart)
    if(colStart == nil) then
        colStart = pos[1]
    end
    local text = tostring(esTime.week.." weeks, "..esTime.day.." days, "..esTime.hour.." hours, "
                        ..esTime.minute.." minutes, "..esTime.second.." seconds.")                
    term.setCursor(colStart, pos[2])
    term.write(emptyColLine)
    if(mode) then
        pos = centerText(text, pos)
    end
    term.setCursor(pos[1], pos[2])
    term.write(text)
    return true
end

function getCol(col, colMax)
    return (w/colMax * col) + 1
end

--------------------------- DRAW BOX RELATED FUNCTIONS ---------------------------
function centerBox(length, pos)
    return {pos[1] - length/2, pos[2]}
end

function drawBox(pos, charDim, color, center, text)
    if center then
        pos = centerBox(charDim.x, pos)
    end
    gpu.setBackground(color)
    gpu.fill(pos[1], pos[2], charDim.x, charDim.y, " ")
    if not (text == nil) then
        writeToScreen({pos[1] + 1, pos[2] + 1}, text, false, false)
    end
    gpu.setBackground(0x000000)
end

--------------------------- GRAPH RELATED FUNCTIONS ---------------------------
function drawGraph(pos, dim, data, colStart, axisUnits)
    clearGraph(pos, dim)
    local minMax = getMinMax(data)
    pos = writeAxis(pos, dim, minMax, colStart, axisUnits)
    for i, value in pairs(data) do
        local baseLevel = getBaseLevel(minMax[1], minMax[2], value, pos, dim)
        local strip = getStrip(pos, dim, baseLevel, minMax, value, amount)
        drawBox({pos[1] + i - 1, strip.y},{x = strip.w, y = strip.h}, getStripColor(value, minMax[1], minMax[2]))
    end
    gpu.setBackground(0x000000)
    return {pos, dim}
end

function writeAxis(pos, dim, minMax, colStart, axisUnits)
    local minValue = formatNumber(minMax[1])
    local maxValue = formatNumber(minMax[2])
    if (minMax[1] == 0) and (minMax[2] >= 0) then
        writeToScreen({pos[1], pos[2] - dim.y}, (tostring(maxValue.number)..maxValue.units..axisUnits), false, true, colStart)
        writeToScreen({pos[1], pos[2] - 1}, tostring("0"..axisUnits), false, true, colStart)
    elseif (minMax[1] < 0) and (minMax[2] == 0) then
        writeToScreen({pos[1], pos[2] - 1}, (tostring(minValue.number)..minValue.units..axisUnits), false, true, colStart)
        writeToScreen({pos[1], pos[2] - dim.y}, tostring("0"..axisUnits), false, true, colStart)
    else
        writeToScreen({pos[1], pos[2] - dim.y}, (tostring(maxValue.number)..maxValue.units..axisUnits), false, true, colStart)
        writeToScreen({pos[1], pos[2] - 1}, (tostring(minValue.number)..minValue.units..axisUnits), false, true, colStart)
    end
    writeToScreen({pos[1] + 6, pos[2]}, tostring("-"..math.floor((MASTERLISTLENGTH)*21*DELAY).." ticks"), false, true, colStart)
    writeToScreen({pos[1] + dim.x + 7, pos[2]}, "|", false, false, colStart)
    return {pos[1] + 7, pos[2]}
end   

function drawBorder(pos, dim)
    local w = 1
    drawBox(pos,{ x = 1, y = dim.y}, 0x646464)
    drawBox(pos[1], pos[2], {x = 1, y = dim.y}, 0x646464)
end


function clearGraph(pos, dim)
    gpu.setBackground(0x000000)
    gpu.fill(pos[1] ,pos[2] - dim.y, dim.x + 8, dim.y, " ")
    return true
end
 
function getStrip(pos, dim, baseLevel, minMax, value)
    local y, h = 0, 0
    local percen = 0
    if value >= 0 then
        if minMax[2] ~= 0 then
            percen = 1 - (minMax[2] - value)/minMax[2]
        end
        h = tonumber(string.format("%.0f",(dim.y - (pos[2] - baseLevel)) * percen))
        y = baseLevel - h
    else
        percen = 1 - (minMax[1] + value)/minMax[1]
        h = tonumber(string.format("%.0f",(pos[2] - baseLevel)  * (-1)*percen))
        y = baseLevel
    end
    return {y = y, w = 1, h = h}
end
 
function getBaseLevel(minValue, maxValue, value, pos, dim)
    if minValue >= 0 then
        return pos[2]
    elseif (minValue < 0 and maxValue <= 0) then
        return pos[2] - dim.y
    else
        return tonumber(string.format("%.0f", pos[2] - (((-1)*minValue)/(maxValue - minValue)) * dim.y))
    end
end
 
function getMinMax(data)
    local minV = data[1]
    local maxV = data[1]
    for i, value in pairs(data) do
        if value >= maxV then
            maxV = value
        elseif value <= minV then
            minV = value
        end
    end
    return {minV, maxV}
end
 
function getStripColor(value, minValue, maxValue)
    if value < 0 then    
        maxValue = (-1)*minValue  
    end
    local temp = (-1)*value
    local g = "f"
    local r = "f"
    local percen = 1
    if value >= 0 then
        if maxValue ~= 0 then
            percen = (maxValue - value)/maxValue
        end
        r = string.format("%x", percen*15)
    elseif value < 0 then
        percen = (maxValue - temp)/maxValue
        g = string.format("%x", percen*15)
    end
    return tonumber("0x"..r.."f"..g.."f00")
end

--------------------------- INTRODUCTION GUI RELATED FUNCTIONS ---------------------------
introDisplayFuelConfigs = coroutine.create(function()
    local i = 1
    local col = getCol(2.5, 3)
    for i2,v in pairs(reactors) do
        writeToScreen({col, i}, tostring("Reactor "..i2.." has fuel config:"), true)
        writeToScreen({col, i+1}, table.concat(v.fuelConfig, ", "), true)
        writeToScreen({col, i + 2}, " ", true)
        i = i + 3
    end
end)

introDisplayTanks = coroutine.create(function(tanks)
    local i = 1
    local col = getCol(1.5, 3)
    for i2, v in pairs(tanks) do
        writeToScreen({col, i}, tostring("Found tank "..v.name..": "..v.tankController.getTankLevel(sides.up).."mB."), true)
        writeToScreen({col, i + 1}, tostring("Low fuel threshold: "..v.threshold.."mB."), true)
        writeToScreen({col, i + 2}, " ", true)
        i = i + 3
    end
end)

introDisplayStorage = coroutine.create(function(storages)
    local i = 1
    local col = getCol(0.5, 3)
    for i2, v in pairs(storages) do
        local capacity = formatNumber(v.capacity)
        writeToScreen({col, i}, tostring(v.device.." "..i2..": "..capacity.number.."RF".."."), true)
        local storage = formatNumber(v.storageProxy.getEnergyStored())
        writeToScreen({col, i + 1}, tostring("Energy stored: "..storage.number..storage.units.."RF".."."), true)
        writeToScreen({col, i + 2}, " ", true)
        i = i + 3
    end
end)

--------------------------- MAIN GUI RELATED FUNCTIONS ---------------------------
function fuelGUI(name, average, levelFormatted, esTime, gainList, i, x)
    local col = getCol(1.5, 3)
    local colStart = getCol(1, 3)
    writeToScreen({col, i}, tostring("Tank "..name..": "..levelFormatted.number..levelFormatted.units.."mB"), true, true, colStart)
    writeToScreen({col, i + 1}, tostring("Average net fluid: "..average.number..average.units.."mB/t."), true, true, colStart)
    if(average.number > 0) then
        writeToScreen({col, i + 2}, tostring("Time until full:"), true, true, colStart)
        writeEstimateToScreen({col, i + 3}, esTime, true,  colStart)
    elseif(average.number < 0) then
        writeToScreen({col, i + 2}, "Time until empty:", true, true, colStart)
        writeEstimateToScreen({col, i + 3}, esTime, true, colStart)
    else
        writeToScreen({col, i + 2}, "NO NET FLUID", true, true, colStart)
        writeToScreen({col, i + 3}, " ", true, true, colStart)    
    end
    drawGraph({colStart + 1, i + 10}, {y = 6, x = MASTERLISTLENGTH}, gainList, colStart, "mB/t")
end

function storageGUI(device, average, energyFormatted, esTime, gainList, i, x)
    local col = getCol(2.5, 3)
    local colStart = getCol(2, 3)
    writeToScreen({col, i}, tostring(device.." "..x..": "..energyFormatted.number..energyFormatted.units.."RF."), true, true, colStart)
    writeToScreen({col, i + 1}, tostring("Average net energy: "..average.number..average.units.."RF/t."), true, true, colStart)
    
    if(average.number > 0) then
        writeToScreen({col, i + 2}, tostring("Time until full:"), true, true, colStart)
        writeEstimateToScreen({col, i + 3}, esTime, true, colStart)
    elseif(average.number < 0) then
        writeToScreen({col, i + 2}, "Time until empty:", true, true, colStart)
        writeEstimateToScreen({col, i + 3}, esTime, true, colStart)
    else
        writeToScreen({col, i + 2}, "NO NET ENERGY", true, true, colStart)
        writeToScreen({col, i + 3}, "NA", true, true, colStart)    
    end
    drawGraph({colStart + 1, i + 10}, {y = 6, x = MASTERLISTLENGTH}, gainList, colStart, "RF/t")
end

function reactorGUI(x, efficiency, average, esTime, storedList, i, fuelConfig, fuelOK, effOK, energyOK)
    local col = getCol(0.5, 3)
    local colStart = getCol(0, 3)
    if efficiency == 90 then
        writeToScreen({col, i}, tostring("Reactor "..x..": efficiency at 90-100%."), true, true, colStart)
    else
        writeToScreen({col, i}, tostring("Reactor "..x..": efficiency at "..efficiency.."-"..(efficiency+6).."%."), true, true, colStart)
    end
    writeToScreen({col, i + 1}, "Fuel config: "..table.concat(fuelConfig, ",")..".", true, true, colStart)
    if(average.number > 0) then
        writeToScreen({col, i + 2}, tostring("Time until max efficiency:"), true, true, colStart)
        writeEstimateToScreen({col, i + 3}, esTime, true, colStart)
    elseif(average.number < 0) then
        writeToScreen({col, i + 2}, "Time until zero efficiency:", true, true, colStart)
        writeEstimateToScreen({col, i + 3}, esTime, true, colStart)
    else
        writeToScreen({col, i + 2}, "NO NET EFFICIENCY", true, true, colStart)
        writeToScreen({col, i + 3}, "NA", true, true, colStart) 
    end
    local boxColour = nil
    if fuelOK then 
        boxColour = 0x00FF00
    else
        boxColour = 0xFF0000
    end
    drawBox({colStart + 2 * (w/27) - 1, i + 5}, {x = 13, y = 3}, boxColour, true, "Fuel Status")
    if effOK then 
        boxColour = 0x00FF00
    else
        boxColour = 0xFF0000
    end 
    drawBox({colStart + (4.5* (w/27) - 1), i + 5}, {x = 12, y = 3}, boxColour, true, "Eff Status")
    if energyOK then 
        boxColour = 0x00FF00
    else
        boxColour = 0xFF0000
    end 
    drawBox({colStart + (7 * (w/27)), i + 5}, {x = 15, y = 3}, boxColour, true, "Energy Status")
end

--------------------------- ININTAL CREATION OF DEVICES ---------------------------

emptyColLine = emptyColText()

reactors = getReactors()
getFuelConfigs()

clearScreen()

status, tanks = coroutine.resume(getTanks)
status, energyDevices = coroutine.resume(getEnergyStorages)

coroutine.resume(introDisplayFuelConfigs)
coroutine.resume(introDisplayTanks, tanks)
coroutine.resume(introDisplayStorage, energyDevices)

os.sleep(2)
clearScreen()
--------------------------- FOREVER UPDATE LOOP ---------------------------
while true do
    updateTanksCo = coroutine.create(updateTanks)
    coroutine.resume(updateTanksCo)
    updateReactorsCo = coroutine.create(updateReactors)
    coroutine.resume(updateReactorsCo)
    updateStorageCo = coroutine.create(updateStorage)
    coroutine.resume(updateStorageCo)
  
    os.sleep(DELAY)
end