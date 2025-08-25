-------------------------------------------------------------------------------------------------
-- Copyright 2024-2025 Lyubimov Vladislav (grifon7676@gmail.com)
-- Copyright 2025 Norzia (devilicip2@gmail.com) for sirus-wow
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy of this software
-- and associated documentation files (the “Software”), to deal in the Software without
-- restriction, including without limitation the rights to use, copy, modify, merge, publish,
-- distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the
-- Software is furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all copies or
-- substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
-- BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
-- NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
-- DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
-------------------------------------------------------------------------------------------------

local addonName = "DeathLogger"

local Utils = {}

local isRequestActive = false
Utils.guildCache = {}

Utils.classes = {
    [1] = "Воин",
    [2] = "Паладин",
    [3] = "Охотник",
    [4] = "Разбойник",
    [5] = "Жрец",
    [6] = "Рыцарь смерти",
    [7] = "Шаман",
    [8] = "Маг",
    [9] = "Чернокнижник",
    [11] = "Друид"
}

Utils.alliances = {
    [0] = "Орда",
    [1] = "Альянс",
    [2] = "Нейтрал",
    [3] = "Неопределено",
    ["Horde"] = "Орда",
    ["Alliance"] = "Альянс"
}

Utils.races = {
    [1] = { "Человек", "Альянс" },
    [2] = { "Орк", "Орда" },
    [3] = { "Дворф", "Альянс" },
    [4] = { "Ночной эльф", "Альянс" },
    [5] = { "Нежить", "Орда" },
    [6] = { "Таурен", "Орда" },
    [7] = { "Гном", "Альянс" },
    [8] = { "Тролль", "Орда" },
    [9] = { "Гоблин", "Орда" },
    [10] = { "Эльф крови", "Орда" },
    [11] = { "Дреней", "Альянс" },
    [12] = { "Ворген", "Альянс" },
    [13] = { "Нага", "Орда" },
    [14] = { "Пандарен", "Альянс" },
    [15] = { "Высший Эльф", "Альянс" },
    [16] = { "Пандарен", "Орда" },
    [17] = { "Ночнорожденный", "Орда" },
    [18] = { "Озаренный Дреней", "Альянс" },
    [19] = { "Вульпера", "Альянс" },
    [20] = { "Вульпера", "Орда" },
    [21] = { "Вульпера", "Нейтрал" },
    [22] = { "Пандарен", "Нейтрал" },
    [23] = { "Зандалар", "Орда" },
    [24] = { "Эльф Бездны", "Альянс" },
    [25] = { "Эредар", "Орда" },
    [26] = { "Дворф Черного Железа", "Альянс" },
    [27] = { "Драктир", "Нейтрал" },
    [28] = { "Драктир", "Орда" },
    [29] = { "Драктир", "Альянс" }
}

Utils.colors = {
    ["Орда"] = "FFFF0000",
    ["Альянс"] = "FF0070DD",
    ["Нейтрал"] = "FF777C87",
    ["Неопределено"] = "FF000000",
    ["Воин"] = "FFC69B6D",
    ["Паладин"] = "FFF48CBA",
    ["Охотник"] = "FFAAD372",
    ["Разбойник"] = "FFFFF468",
    ["Жрец"] = "FFF0EBE0",
    ["Рыцарь смерти"] = "FFC41E3B",
    ["Шаман"] = "FF2359FF",
    ["Маг"] = "FF68CCEF",
    ["Чернокнижник"] = "FF9382C9",
    ["Друид"] = "FFFF7C0A",
    ["Золотой"] = "FFFF8000",
    ["Зеленый"] = "FF00FF00",
    ["Синий"] = "FF0070DD",
    ["Фиолетовый"] = "FFA335EE",
    ["Неизвестно"] = "FFFF69B4",
    ["Красный"] = "FFFF0000",
    ["Белый"] = "FFFFFFFF"
}

Utils.causes = {
    [0] = "Усталость",
    [1] = "Утопление",
    [2] = "Падение",
    [3] = "Лава",
    [4] = "Болото",
    [5] = "Огонь",
    [6] = "Падение в бездну",
    [7] = "Убийство",
    [8] = "Дуэль/PVP",
    [9] = "Дружеский огонь",
    [10] = "От собственных действий"
}

function Utils.ColorWord(word, colorRepr)
    if not word or not colorRepr then return nil end
    local colorCode = Utils.colors[colorRepr]
    if not colorCode then return nil end
    return "|c" .. colorCode .. word .. "|r"
end

function Utils.ExtractName(str)
    if not str then
        print("[DEBUG][ExtractName] Входная строка пуста или равна nil.")
        return nil
    end
    local name = str:match("^[^:]+")
    if not name then
        print("[DEBUG][ExtractName] Не удалось извлечь имя из строки:", str)
    end
    return name
end

-- function Utils.StringToMap(str)
    -- local tbl = {}
    -- local keys = { "name", "raceID", "sideID", "classID", "level", "locationStr", "causeID", "enemyName", "enemyLevel" }
    -- local index = 1
    -- for str in string.gmatch(str, "[^:]+") do
        -- tbl[keys[index]] = tonumber(str) or str
        -- index = index + 1
    -- end
    -- tbl.name = Utils.ExtractName(str)
    -- return tbl
-- end

function Utils.StringToMap(str)
    local tbl = {}
    local keys = { "name", "raceID", "sideID", "classID", "level", "locationStr", "causeID", "enemyName", "enemyLevel" }
    local index = 1
    for strPart in string.gmatch(str, "[^:]+") do
        tbl[keys[index]] = tonumber(strPart) or strPart
        index = index + 1
        if index > #keys then break end  -- сейв от переполнения
    end
	tbl.name = Utils.ExtractName(str)
    tbl.causeID = tbl.causeID or 0
    return tbl
end

function Utils.TimeNow()
    return date("%H:%M", GetServerTime())
end

function Utils.GetRaceData(id)
    local raceTuple = Utils.races[id]
    local coloredRace, race, side
    if raceTuple then
        race = raceTuple[1]
        side = raceTuple[2]
        coloredRace = Utils.ColorWord(race, side)
    else
        race = id
        coloredRace = race
        side = "Неизвестно"
    end
    return coloredRace, race, side
end

function Utils.IsPlayerInGuild(targetName)
    if IsInGuild() then
        local numMembers = GetNumGuildMembers()
        for i = 1, numMembers do
            local name = GetGuildRosterInfo(i)
            if name == targetName then
                return true
            end
        end
    end
    return false
end

function Utils.TablesEqual(t1, t2)
    if #t1 ~= #t2 then return false end
    for i = 1, #t1 do
        if t1[i] ~= t2[i] then
            return false
        end
    end
    return true
end

function Utils.CopyTable(src, dst)
    dst = dst or {}
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = Utils.CopyTable(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

_G[addonName.."_Utils"] = Utils