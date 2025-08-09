-- planGeneSlots(brName, target, maxOver) -> { slots = {...}, total = N } | nil, err
-- Uses Block Reader -> getBlockData() shaped like your example.
local function planGeneSlots(brName, target, maxOver)
    -- wrap block reader
    local br = peripheral.wrap(brName)
    if not br then return nil, "Block Reader not found: " .. tostring(brName) end

    -- pull block data safely
    local ok, data = pcall(function() return br.getBlockData() end)
    if not ok or not data then return nil, "getBlockData() failed" end

    -- dig into Items[]
    local inv = (((data.storageWrapper or {}).contents or {}).inventory or {})
    local items = inv.Items
    if type(items) ~= "table" then return nil, "No inventory Items[] in block data" end

    -- collect candidates: {slot=1-based, purity=number}
    local cand = {}
    for _, it in ipairs(items) do
        if it and it.id == "productivebees:gene" and it.components
            and it.components["productivebees:gene_group"]
            and type(it.components["productivebees:gene_group"].purity) == "number" then
            local purity = it.components["productivebees:gene_group"].purity
            local slot0  = it.Slot or 0
            table.insert(cand, { slot = slot0 + 1, purity = purity })
        end
    end
    if #cand == 0 then return nil, "No gene items with purity found" end

    -- subset DP over purity; track minimal count for tie-break
    -- dp[sum] = { prevSum, idxUsed, count }
    local dp = { [0] = { prev = nil, idx = nil, count = 0 } }
    local sums = { 0 }

    for idx, it in ipairs(cand) do
        local p = it.purity
        local newSums = {}
        for _, s in ipairs(sums) do
            local ns = s + p
            local cur = dp[ns]
            local nxt = { prev = s, idx = idx, count = dp[s].count + 1 }
            if not cur or nxt.count < cur.count then
                dp[ns] = nxt
                table.insert(newSums, ns)
            end
        end
        for _, ns in ipairs(newSums) do table.insert(sums, ns) end
    end

    -- choose best total in [target, target+maxOver]
    local best, bestCount = nil, math.huge
    for s, node in pairs(dp) do
        if s >= target and s <= target + maxOver then
            if (not best or s < best) or (s == best and node.count < bestCount) then
                best, bestCount = s, node.count
            end
        end
    end
    if not best then
        return nil, ("No combination within %d..%d"):format(target, target + maxOver)
    end

    -- reconstruct chosen indices → slots
    local chosenIdx = {}
    local cur = best
    while cur and cur ~= 0 do
        local node = dp[cur]
        table.insert(chosenIdx, node.idx)
        cur = node.prev
    end
    -- dedupe (defensive), then map to slots
    local mark, slots = {}, {}
    for _, i in ipairs(chosenIdx) do
        if not mark[i] then
            mark[i] = true
            table.insert(slots, cand[i].slot)
        end
    end

    return { slots = slots, total = best }, nil
end


local plan, err = planGeneSlots("block_reader_1", 100, 5)
if not plan then
    printError(err)
    return
end
print("Total purity:", plan.total)
print("Slots to pull:", table.concat(plan.slots, ","))

local toCraft = peripheral.wrap("front")
local buffer = peripheral.wrap("bottom")
local slot = turtle.getSelectedSlot()

if toCraft and buffer then
    for _, slot in ipairs(plan.slots) do
        print("Pulling from slot", slot)
        -- pull 1 item from this slot into the turtle
        -- This assumes an input chest in front
        buffer.pullItems(peripheral.getName(toCraft), slot)
        turtle.suckDown(1)
        turtle.select(slot + 1)
        if turtle.getSelectedSlot() > 2 then
            shell.run("craft", "all")
            turtle.select(1)
        end
    end
    turtle.select(1)
    turtle.dropUp()
end
