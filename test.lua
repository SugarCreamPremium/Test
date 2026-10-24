repeat wait() until game:IsLoaded()

if game.PlaceId ~= 99925503388128 then
    return
end

--[[
    Fishing Master — AUTO PROGRESSION (PoC)
    ==========================================================
    เดินเกมช่วงต้นให้อัตโนมัติตามลำดับเป้าหมาย แล้วฟาร์มไปเรื่อยจนจบแผน

    ลำดับการทำงาน:
      0) GUARD     -> ก่อนทุกอย่าง: กัน AFK/หลุด + ลดโหลดกราฟิก (ดูหัวข้อ 0 ด้านล่าง)
                      ถ้าหลุดหรือค้าง ไม่มีโอกาสได้ทำขั้นถัดไปเลย
     0b) DAILY     -> ต่อจาก GUARD: รับของเข้าเล่นรายวัน (วันที่ 1-7) ถ้าวันนี้รับได้
                      เกมล็อก 24 ชม./ครั้ง รับได้วันละ 1 วัน ข้ามวันไม่ได้ (ดูหัวข้อ 0b ด้านล่าง)
      1) Tutorial  -> ถ้าอยู่ใน tutorial ให้ Skip ทันที (Tutorial/Skip)
      2) Skill 1   -> ถ้ายังไม่มีสกิลในกระเป๋า (Inventory.Books) ให้สุ่มรอบแรก (ฟรี)
                      ใส่เข้าเบ็ดให้เรียบร้อย — ยังไม่สุ่ม Extra ตอนนี้
      3) FISH      -> เริ่ม auto-fishing ที่จุดฟาร์มของเกาะที่ปลดแล้วและ order สูงสุด ณ ตอนนั้น
                      (มีภารกิจค้างอยู่ = ไปที่เกาะของภารกิจนั้น / ไม่มีภารกิจ = เกาะที่ปลดสูงสุด)
                      (CONFIG.FarmSpots[เกาะ] ถ้าประกาศไว้ / จุดเกิดของเกาะถ้าไม่ได้ประกาศ)
                      ขายปลาก็ขายที่คนขายของเกาะเดียวกันนั้น (อ่าน currentIslandId ตอนขาย)
      4) STEP      -> อ่านสถานะจริงแล้ว "คิด" ว่าทำอะไรต่อ — ไม่มีตารางขั้นตอนตายตัว
                      เกาะที่ดีที่สุด = เกาะที่ปลดล็อกแล้วที่ order สูงสุด (อ่านจาก Catalog ไม่ hardcode)
                      มีภารกิจที่ยังไม่เสร็จ (CONFIG.Missions) -> ซื้อเบ็ด / ว่ายไปตกที่เกาะนั้น / ปลดล็อก
                      ถึง CONFIG.StopIsland แล้ว -> จบ ไม่ต้องทำอะไรอีก
                      ยังไม่ได้ยืนบนเกาะเป้าหมาย -> ว่ายไป NPC + ตั้งจุดเกิดที่นั่น แล้วไปจุดฟาร์ม
                      ยังไม่มี "เบ็ดดีที่สุดของเกาะนั้น" (attackDamage สูงสุดในกลุ่มของเกาะ) -> ซื้อ
                      เกาะนี้ไม่ใช่เกาะที่ยกเว้น และยังไม่มีสกิลถึงเป้า -> สุ่ม (มีแล้วข้าม ไม่สุ่มซ้ำ)
                      เกาะนี้ครบ -> ปลดล็อกเกาะถัดไป (เช็ค unlockCost เท่านั้น เลเวลเป็นข้อมูลตายที่เกมไม่เคยเช็ค)
                      ⚠ ถ้าทำแล้วไม่สำเร็จ จะหน่องแล้วลองซ้ำเอง ไม่มีการ "ข้ามขั้นถาวร" (สาเหตุชั่วคราวเกือบทั้งหมด)

    ⚠️ ทุกขั้นอ่านค่าจริงจากเกมตอนนั้น (Coin / Rods / UnlockedIslands / ตำแหน่ง)
       ไม่มีการนับเวลาเพื่อตัดสินใจที่ไหนเลย
    ⚠️ ข้อกำหนด executor: getconnections/firesignal + hookfunction/setreadonly + settings()
    ⚠️ PoC เพื่อการทดสอบเท่านั้น — ใช้บัญชีทดสอบของคุณเอง
]]

local ReplicatedStorage, RunService, Workspace = game:GetService("ReplicatedStorage"),
    game:GetService("RunService"), game:GetService("Workspace")
local LocalPlayer = game:GetService("Players").LocalPlayer
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")

-- ⚠ เสียงเตือนทั้งหมดของสคริปต์ปิดไว้ (ผู้ใช้สั่ง — ไม่ต้องการข้อความรบกวน)
--   ทุกการเรียกเตือนเดิมถูกเปลี่ยนเป็น logWarn() ที่นี่แล้ว
--   เปิดกลับ: แก้ค่าบรรทัดล่างเป็น true
-- ⚙ เปิด true = พิมพ์สถานะจริงลงคอนโซล (ผู้ใช้สั่ง "เปิดเช็คดู")
--   ปิดกลับ: แก้บรรทัดล่างเป็น false เมื่อแก้เสร็จ
PROG_WARN = true

function logWarn(...)
    if PROG_WARN then warn(...) end
end

--- นาฬิกา "เวลาจริง" ที่ไม่เพี้ยนตามแลคของเครื่อง
---   GetServerTimeNow = เวลาจากเซิร์ฟ + เวลาที่ผ่านไปจริง = เดินตามเวลาจริงเสมอ
---   ⚠ os.clock() ใช้ไม่ได้กับงานนี้ — มันนับเวลา CPU ตอนที่สคริปต์ yield มันไม่เดิน
---   (สคริปต์นี้ใช้ os.clock() เป็น deadline ภายในอยู่แล้ว นั่นคนละเรื่องกัน)
function nowReal()
    local ok, t = pcall(function() return Workspace:GetServerTimeNow() end)
    if ok and type(t) == "number" and t > 0 then return t end
    ok, t = pcall(function() return DateTime.now():UnixTimestampMillis() / 1000 end)
    if ok and type(t) == "number" and t > 0 then return t end
    return os.time()
end

-- จุดเริ่มนับเวลารัน: จับตั้งแต่ตอนสคริปต์เริ่มทำงาน (ตัวแปร global เพราะ S ยังไม่ได้ประกาศ)
PROG_STARTED_AT = nowReal()

local function req(path, name)
    local ok, res = pcall(function() return require(path) end)
    if not ok then logWarn(("[Prog] require %s ไม่ได้: %s"):format(name, tostring(res))) return nil end
    return res
end

local Stardust, P, FishingConfig, Catalog, WorldConfig, RodShopConfig, getLevel,
      FishStorageRules, SkillBookAvail, SellController, IslandConfig, QuestConfig, SpawnStatus,
      -- Controllers (require คืน singleton controller ที่เกมสร้างไว้แล้ว)
      PlayerData, TutorialCtl, GachaCtl, RodShopCtl, EquipCtl, QuestCtl,
      UnitGachaCtl, UnitCtl =
      req(ReplicatedStorage.Stardust, "Stardust"),
      req(ReplicatedStorage.Data.Packets.FishingPackets, "FishingPackets"),
      req(ReplicatedStorage.Data.Config.FishingConfig, "FishingConfig"),
      req(ReplicatedStorage.Data.Catalog, "Catalog"),
      req(ReplicatedStorage.WorldConfig, "WorldConfig"),
      req(ReplicatedStorage.Data.Config.RodShopConfig, "RodShopConfig"),
      req(ReplicatedStorage.Shared.Lib.getRequiredExp_Level, "getRequiredExp_Level"),
      req(ReplicatedStorage.Shared.Lib.FishStorageRules, "FishStorageRules"),
      req(ReplicatedStorage.Utils.skillBookAvailability, "skillBookAvailability"),
      req(ReplicatedStorage.Controllers.SellController, "SellController"),
      req(ReplicatedStorage.Data.Config.IslandConfig, "IslandConfig"),
      req(ReplicatedStorage.Data.Config.QuestConfig, "QuestConfig"),
      req(ReplicatedStorage.Data.Enums.SpawnEnums, "SpawnEnums"),
      req(ReplicatedStorage.Controllers.PlayerDataV2Controller, "PlayerDataV2Controller"),
      req(ReplicatedStorage.Controllers.TutorialController, "TutorialController"),
      req(ReplicatedStorage.Controllers.SkillGachaController, "SkillGachaController"),
      req(ReplicatedStorage.Controllers.FishingRodShopController, "FishingRodShopController"),
      req(ReplicatedStorage.Controllers.EquipmentController, "EquipmentController"),
      req(ReplicatedStorage.Controllers.QuestController, "QuestController"),
      req(ReplicatedStorage.Controllers.UnitGachaController, "UnitGachaController"),
      req(ReplicatedStorage.Controllers.UnitController, "UnitController")

local Client = Stardust and Stardust.Client or nil

-- สีตามระดับหายากของเกม (RarityEnums.PrimaryColor)
-- ⚠ เก็บเป็น global ไม่ใช่ local เพราะ main chunk ของไฟล์นี้ local ระดับบนสุดเกือบเต็มลิมิต 200 ตัว
RarityEnums = req(ReplicatedStorage.Data.Enums.RarityEnums, "RarityEnums")

-- ── สาย Forge (Godslayer Rod V2) + Raid ─────────────────────────────
-- ⚠ global ทั้งหมดด้วยเหตุผลเดียวกับ RarityEnums: เพดาน local 200 ตัวของไฟล์นี้เต็มแล้ว
--   ตัวแปรเหล่านี้ถูกอ่านจากฟังก์ชัน forgeStep/raidStep/rodAtk ที่ประกาศทีหลัง
RodForgeCfg   = req(ReplicatedStorage.Data.Config.RodForgeConfig, "RodForgeConfig")
RodForgeRules = req(ReplicatedStorage.Shared.Lib.RodForgeRules, "RodForgeRules")
RodModifiers  = req(ReplicatedStorage.Shared.Lib.RodModifiers, "RodModifiers")
RaidCfg       = req(ReplicatedStorage.Data.Config.RaidConfig, "RaidConfig")
RaidPkts      = req(ReplicatedStorage.Data.Packets.RaidPackets, "RaidPackets")
RaidEnums     = req(ReplicatedStorage.Data.Enums.RaidEnums, "RaidEnums")
RaidWindow    = req(ReplicatedStorage.Shared.Lib.raidWindow, "raidWindow")
WaterBody     = req(ReplicatedStorage.Shared.WaterBody, "WaterBody")

-- โหลดไว้ล่วงหน้า ไม่งั้น applyLowGraphics จะ require ทุก 5 วินาที
local QualityRuntime = req(ReplicatedStorage.Packages.Gerstner.QualityRuntime, "QualityRuntime")

if not P or not FishingConfig then
    error("[Prog] ต้อง require FishingPackets/FishingConfig ได้ก่อน")
end
if not PlayerData then
    error("[Prog] ต้อง require PlayerDataV2Controller ได้ก่อน")
end

-- ══════════════════════════════════════════════════════════════════
-- 0) กัน AFK / กันหลุด + ลดโหลดกราฟิก
--    ⚠ ต้องอยู่ก่อนทุกอย่าง (ก่อน CONFIG, ก่อน progression) เพราะ
--      ถ้าหลุด/ค้าง ไม่มีโอกาสได้ทำขั้นอื่นอีก
-- ══════════════════════════════════════════════════════════════════

local Guard = {
    keepAlive = true,      -- กัน AFK + ปิดหน้าต่าง Reconnect ของ Roblox
    lowGfx    = true,      -- ลดงานกราฟิก (จาก antilag/boostfps/lowgraphics ของ Infinite Yield)
    note = false,           -- ไม่ใช้แล้ว (เคยพิมพ์สรุปตอนเริ่ม ตัดออกตามคำสั่งลด log)
    applied = {},

    -- ── สวิตช์เฉพาะส่วนที่เพิ่มจากต้นฉบับของ Infinite Yield ──
    --   ชุดหลักของ IY (Terrain/Lighting/QualityLevel/Part/Decal/Particle/PostEffect
    --   + DescendantAdded) ทำตามต้นฉบับทุกอย่าง ไม่มีสวิตช์ปิด
    g_ultraLowGfx  = true,  -- SettingsController "ultra_low_graphic" (ของเกมเอง)
    g_oceanFast    = true,  -- QualityRuntime FastMode (ทะเลไม่ animate — ของเกมเอง)

    -- ⚙ หมวด Fishing ในเมนู Settings ของเกม: ปิด "ทั้งหมด" ตามคำสั่งผู้ใช้
    --   รายการทั้งหมดมาจาก SettingsConfig.Fishing (Data/Config/SettingsConfig.lua:5-27)
    --   ⚠ ค่าที่ผู้ใช้แก้เอง = ตั้งใจ เช่นถ้าอยากเห็น loot ตั้ง show_loot_items = true
    g_fishing = {
        auto_fishing_hide_vfx  = false,  -- Hide VFX ตอนออโนตักตก
        show_cutscenes         = false,  -- Show Cutscenes
        show_loot_items        = false,  -- Show Loot Items
        show_damage_indicator  = false,  -- Show Damage Indicator
        show_my_vfx            = false,  -- Show my VFX
        show_others_vfx        = false,  -- Show others' VFX
        camera_shaking         = false,  -- Camera shaking
    },
    -- ⏱ ตั้งค่าใหม่ทุกกี่วินาที (เกมสร้างของใหม่เข้ามาเรื่อย ๆ ต้องจับให้ทัน)
    --   ⚠ ไม่ใช้ event ของเกม เพราะ SettingsController.Changed ไฟล์ไม่ expose
    --     จึงใช้รอบเวลาแทน (ตรงนี้นับเวลาได้ เพราะเป็นจังหวะงานประจำ
    --     ไม่ใช่การตัดสินใจตอนรอเกมตอบ — ดูหลัก "ไม่นับเวลาเอง" ในส่วน progression)
    f_resweep = 60,
    resweepAcc = 0,      -- ตัวนับรอบตั้งค่าเกม + Boost FPS ใหม่ (ดู installGuards)
}

-- ── 1) กันหน้าต่างของ Roblox ตอน idle ──────────────────────────────
--   "Reconnect / Are you still there?" มาจาก CoreGui ของตัวเกม Roblox
--   ไม่ใช่ของเกม (grep ทั้งดัมป์แล้ว ไม่มีที่ไหนอ้างถึง Idled เลย)
--   → ปิดมันทิ้ง = ไม่มีอะไรมาบังหน้าจอตอนสคริปต์กำลังรัน
--   → และเป็นกันหลุดชั้นแรก เพราะถ้าหน้าต่างโผล่ = เกมกำลังจะตัดเรา
local function killCoreGui()
    pcall(function() game:GetService("GuiService").AutoSelectGuiEnabled = false end)
    local pg = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local core = pg and pg:FindFirstChild("CoreGui")
    if core and core:IsA("ScreenGui") then
        pcall(function() core.Enabled = false end)
    end
    return core ~= nil
end

-- ── 2) กัน idle ตัวจริง ─────────────────────────────────────────────
--   ⚠ วิธีนี้ยกมาจาก 99 Nights MainScript.lua:211-216 (ผู้ใชาสั่งให้เหมือนกัน)
--   เดิมของไฟล์นี้ใช้ "ขยับ HRP ไป 0.01" แทน ซึ่งไม่ใช่ตัวรีเซ็ตเวลาจริง
--     แถก้อยกวนตำแหน่งตัวละครที่สคริปต์ใช้คำนวณ (tween / castToNearestWater)
--
--   Roblox รีเซ็ตเวลานับ idle จาก "มี input จริง" เท่านั้น
--   VirtualUser คือตัวเดียวที่ยิง input ปลอมแบบนี้ได้:
--     CaptureController() = จับคีย์บอร์ด/จอยเข้ามา · ClickButton2() = กดปุ่ม 2 ครั้ง
--
--   หมายเหตุ: คอมเมนต์เดิมบอกว่า "เกมไม่ได้ใช้ Idled เลย" — จริงแล้วก็จริง
--   แต่ Idled ของ CoreGui Roblox เอง ไม่ใช่ของเกม และตัวนับ idle ก็อยู่ที่นั่น
local VirtualUser = nil
local idleConn = nil

local function onIdle()
    if not Guard.keepAlive then return end
    -- 2a) ยิง input ปลอม = ตัวที่รีเซ็ตเวลานับ idle ของ Roblox จริง
    --     ห่อ pcall ไว้เพราะถ้าล้มตรงนี้ callback จะตายทันที
    --     และบรรทัด 2c ที่ต่อ signal ใหม่จะไม่ได้รัน = กัน AFK ตายยาวไปทั้ง session
    if VirtualUser then
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end
    -- 2b) ปิดหน้าต่างอีกรอบ (ถ้ามีอะไรเปิดมันขึ้นมาใหม่)
    killCoreGui()
    -- 2c) ต่อ signal ใหม่ — ตัวเชื่อเดิมอาจโดนตัด
    if idleConn then pcall(function() idleConn:Disconnect() end) end
    idleConn = LocalPlayer.Idled:Connect(onIdle)
end

-- ── 3) ลดโหลดกราฟิก ────────────────────────────────────────────────
--   พอร์ตจาก Infinite Yield ตรง ๆ ทั้งชุด ไม่ตัดออกอะไร
--   ต้นทาง: EdgeIY/infiniteyield  branch master  ไฟล์ "source"  บรรทัด 8012
--       addcmd("antilag", {"boostfps", "lowgraphics"}, function(args, speaker)
--   ทั้งสามชื่อคือคำสั่งเดียวกัน = "Lowers game quality to boost FPS"
--
--   เรียกครั้งเดียวตอนสตาร์ต แล้วต่อ DescendantAdded ค้างไว้
--   เพื่อจัดการสิ่งที่หลุดเข้ามาทีหลังให้เหมือนกัน (ตามต้นฉบับ)
local gfxConn = nil

--- ⚙ ตั้งค่าของเกมเองก่อนเสมอ (ผู้ใช้สั่ง) แล้วค่อย Boost FPS
---   ลำดับสำคัญ: ต้อง "ก่อน" applyLowGraphics เพราะเกราฟิกต่ำที่เกมมีอยู่แล้ว
---   (GraphicController ย่อ particle อยู่แล้วตอน ultra_low_graphic = true)
---   ถ้าไล่ workspace ก่อน เราจะเสียเวลาไปกับชิ้นที่เกมกำลังจะจัดการเอง
---
---   กลไกจริงของเกม (SettingsController.lua:148-152, 294-295):
---     SettingsCtl:_SetLocal(id, v)  -> เขียน _values + ยิง Changed ให้ผู้ฟัง
---     Packet("SetSettings"):Fire(id, v)  -> บันทึกลงเซิร์ฟ
---   เราใช้ _SetLocal อย่างเดียว = เหมือนผู้ใช้กดสวิตช์ แต่ไม่เผาแพ็กเก็ตเกินจำเป็น
function applyGameSettings()
    if not (Client and Client.GetController) then return false end
    if not Client.HasController("SettingsController") then
        pcall(function()
            req(ReplicatedStorage.Controllers.SettingsController, "SettingsController")
        end)
    end
    local okGet, Ctl = pcall(function()
        return Client.GetController("SettingsController")
    end)
    if not (okGet and Ctl and type(Ctl._SetLocal) == "function") then return false end

    local n = 0
    if Guard.g_ultraLowGfx then
        pcall(function()
            Ctl:_SetLocal("ultra_low_graphic", true)
            n = n + 1
        end)
    end
    for id, val in pairs(Guard.g_fishing or {}) do
        if val == false then          -- ปิดเท่านั้น (true = เปิด = ไม่แตะค่าที่ผู้ใช้ตั้ง)
            pcall(function()
                if Ctl:GetSettingValue(id) ~= false then
                    Ctl:_SetLocal(id, false)
                    n = n + 1
                end
            end)
        end
    end
    Guard.fishingSet = true
    return n > 0
end

--- fullSweep = true  = ไล่ทั้ง workspace ใหม่ (ทำครั้งเดียวตอนสตาร์ต)
--- fullSweep = false = ทำแค่ส่วนที่ถูก ๆ (Lighting/Quality/PostEffect) เอาไว้เติมเป็นจังหวะ
local function applyLowGraphics(fullSweep)
    fullSweep = (fullSweep ~= false)
    local changed = {}
    local nPart, nDecal, nFx, nPost = 0, 0, 0, 0

    -- 3a) น้ำบน Terrain
    --   เกมนี้ทะเลหลักเป็น MeshPart ใน Workspace/Ocean ไม่ใช่ terrain
    --   แต่เกมมี Terrain อยู่ บางส่วนอาจใช้น้ำ terrain เลยตั้งครบตามต้นฉบับ
    local Terrain = Workspace:FindFirstChildWhichIsA("Terrain")
    if Terrain then
        pcall(function()
            Terrain.WaterWaveSize = 0
            Terrain.WaterWaveSpeed = 0
            Terrain.WaterReflectance = 0
            Terrain.WaterTransparency = 1
            changed.Terrain = true
        end)
    end

    -- 3b) Lighting
    local Lighting = game:GetService("Lighting")
    pcall(function() Lighting.GlobalShadows = false changed.GlobalShadows = false end)
    pcall(function() Lighting.FogEnd = 9e9 changed.FogEnd = 9e9 end)
    pcall(function() Lighting.FogStart = 9e9 changed.FogStart = 9e9 end)

    -- 3c) คุณภาพการเรนเดอร์ของ Roblox
    if type(settings) == "function" then
        pcall(function()
            settings().Rendering.QualityLevel = 1
            changed.QualityLevel = 1
        end)
    end

    -- 3d) ไล่ทั้ง workspace: Part / Decal / ParticleEmitter / Trail
    --   ⚠ ทำครั้งเดียวตอนสตาร์ต ตามต้นฉบับ
    --   ถ้ามาทำซ้ำทุก 5 วินาทีข้างล่าง = game:GetDescendants() ทั้งฉากทุกครั้ง
    --   ซึ่งคือการกินโหลดตัวเองพอดี ต้องกันไว้
    if fullSweep or not Guard.swept then
        for _, v in ipairs(game:GetDescendants()) do
            if v:IsA("BasePart") then
                pcall(function()
                    v.CastShadow = false
                    v.Material = "Plastic"
                    v.Reflectance = 0
                    v.BackSurface = "SmoothNoOutlines"
                    v.BottomSurface = "SmoothNoOutlines"
                    v.FrontSurface = "SmoothNoOutlines"
                    v.LeftSurface = "SmoothNoOutlines"
                    v.RightSurface = "SmoothNoOutlines"
                    v.TopSurface = "SmoothNoOutlines"
                end)
                nPart = nPart + 1
            elseif v:IsA("Decal") then
                pcall(function()
                    v.Transparency = 1
                    v.Texture = ""
                end)
                nDecal = nDecal + 1
            elseif v:IsA("ParticleEmitter") or v:IsA("Trail") then
                -- ⚠ ชนิดของ Lifetime ต่างกัน: ParticleEmitter = NumberRange, Trail = number
                --   เดิมยัด NumberRange ให้ทั้งสองชนิด -> Trail ฟ้อง
                --   "value of type NumberRange cannot be converted to a number"
                --   (ใน pcall ก็จริง แต่ตัวรันบางตัวบนมือถือพิมพ์ error ออกมาอยู่ดี)
                --   แก้โดยอ่านชนิดของค่าปัจจุบันก่อน แล้วเขียนค่าชนิดเดียวกัน
                pcall(function()
                    local cur = v.Lifetime
                    if typeof(cur) == "NumberRange" then
                        v.Lifetime = NumberRange.new(0)
                    elseif v:IsA("Trail") then
                        v.Enabled = false          -- Trail: ปิดทั้งเส้น ไม่แตะ Lifetime ที่เป็นตัวเลข
                    end
                end)
                nFx = nFx + 1
            end
        end
    end

    -- 3e) PostEffect ใต้ Lighting
    for _, v in ipairs(Lighting:GetDescendants()) do
        if v:IsA("PostEffect") then
            pcall(function() v.Enabled = false end)
            nPost = nPost + 1
        end
    end

    -- 3f) ของที่หลุดเข้ามาทีหลัง — ตามต้นฉบับ
    --   รอ 1 เฟรมก่อนลงมือ เพื่อให้ instance เข้า tree ครบก่อนแตะ
    if not gfxConn then
        gfxConn = Workspace.DescendantAdded:Connect(function(child)
            task.spawn(function()
                if child:IsA("ForceField") or child:IsA("Sparkles")
                    or child:IsA("Smoke") or child:IsA("Fire") or child:IsA("Beam") then
                    RunService.Heartbeat:Wait()
                    pcall(function() child:Destroy() end)
                elseif child:IsA("BasePart") then
                    pcall(function() child.CastShadow = false end)
                end
            end)
        end)
    end

    -- 3g) ของที่เกมมีเอง: FastMode ของทะเล + โหมดกราฟิกต่ำของเกม
    --   ไม่ได้อยู่ในต้นฉบับ แต่เป็นของที่เกมเตรียมไว้เอง
    --   (OceanQualityConfig.FastModeOverride / GraphicController "ultra_low_graphic")
    --   ทำหลังชุดหลักเสร็จ เพื่อไม่ให้แย่งกันตอนไล่ descendant
    if QualityRuntime and type(QualityRuntime.Apply) == "function" and Guard.g_oceanFast then
        pcall(function()
            QualityRuntime.Apply(QualityRuntime.ResolveTier(), true)
            changed.OceanFastMode = true
        end)
    end
    -- ⚠ เรียกหลังไล่ descendant เสร็จ เพราะ GraphicController จะย่อ particle ให้เอง
    --   (ตอนนี้เป็นแค่ตัวห่อ ตัวตั้งจริงอยู่ที่ applyGameSettings ด้านบน)
    pcall(applyGameSettings)
    changed.gameSettings = Guard.fishingSet or false

    Guard.applied = changed
    Guard.swept = { parts = nPart, decals = nDecal, fx = nFx, post = nPost }
    return changed
end

-- ── 4) รันจริง ─────────────────────────────────────────────────────
--   ต่อ event เป็นหลัก (ตามกติกา "ไม่นับเวลาเอง") ใช้ Heartbeat แค่เป็นกันดั่ว
--   เผื่อเกมสร้าง CoreGui / เปิด PostEffect กลับมาระหว่างที่ไม่มี event
local heartbeatAcc = 0
-- ⚠ ตัวนับ "ตัวละครถูกแทนที่" — installGuards() อยู่ก่อน S (บรรทัด ~611) จึงแตะ S ไม่ได้
--   ตัวจับการตายในนั้นแค่บวมค่าตรงนี้ แล้วให้ mainLoop เป็นคนไปล้าง S เอง
local DEATH_STAMP = 0
--- ⚠ ตัวนับรอบ "ตั้งค่าเกม + Boost FPS ใหม่" (60 วิ)
---   เก็บใน Guard (global อยู่แล้ว) ไม่ใช่ local ระดับบนสุด เพราะ main chunk
---   ของไฟล์นี้ชนเพดาน 200 slots ของ Lua 5.1 แล้ว (ดู lowApplyScale)
local function installGuards()
    if not Guard.keepAlive then return end

    -- ขอ VirtualUser ครั้งเดียวตอนติดตั้ง ไม่ใช่ทุกครั้งที่ idle
    if not VirtualUser then
        pcall(function() VirtualUser = game:GetService("VirtualUser") end)
    end

    if idleConn then pcall(function() idleConn:Disconnect() end) end
    idleConn = LocalPlayer.Idled:Connect(onIdle)
    killCoreGui()

    -- เกมสร้าง CoreGui ใหม่ทุกครั้งที่เกิดใหม่ → ต่อรอไว้
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if pg then
        pcall(function() pg.ChildAdded:Connect(function(child)
            if child:IsA("ScreenGui") and child.Name == "CoreGui" then
                task.defer(killCoreGui)
            end
        end) end)
    end
    pcall(function() LocalPlayer.CharacterAdded:Connect(function() task.defer(killCoreGui) end) end)

    -- ⚠ ตัวตาย/ถูกลบตัวละคร: เกมเรียก ResetAll() ซึ่งตั้ง state = "Idling" โดย "ไม่ยิง packet"
    --   (FishingController.lua:1329-1339) ถ้าเราไม่รู้ S.state จะค้างเป็น "Reeling"
    --   -> เงื่อนไข while ใน reelingLoop ยังจริง -> ยิง FishReelPull/Moveset ทิ้งใส่ Idling
    --   ไม่มีทางหยุดจนกว่าเซิร์ฟจะส่ง FishReset มาเอง ซึ่งไม่แน่นอน
    --
    -- ⚠ ห้ามอ้าง S ตรงๆ ตรงนี้: installGuards() อยู่บรรทัด ~270 แต่ S ประกาศที่ ~611
    --   การอ้างชื่อ S ในขอบเขตนี้ = global lookup -> ได้ nil แล้ว error
    --   จึงใช้ตัวนับธรรมดาที่ประกาศไว้ด้านบน แล้วให้ mainLoop เป็นคนไปเคลียร์ S
    local function onCharacterGone()
        DEATH_STAMP = DEATH_STAMP + 1
    end
    pcall(function() LocalPlayer.CharacterRemoving:Connect(onCharacterGone) end)
    pcall(function()
        local function watchDied(h)
            if h and h:IsA("Humanoid") then h.Died:Connect(onCharacterGone) end
        end
        local ch = LocalPlayer.Character
        if ch then
            watchDied(ch:FindFirstChildOfClass("Humanoid"))
            ch.ChildAdded:Connect(watchDied)
        end
        LocalPlayer.CharacterAdded:Connect(function(newCh) task.defer(watchDied, newCh) end)
    end)

    -- ⚠ แยกเป็นสองจังหวะเพราะงานคนละอย่าง:
    --   5 วิ  = กัน CoreGui (ถูกทุก 5 วิ ไม่ต้องเปลี่ยน ถือว่าไว้)
    --   60 วิ = ตั้งค่าเกม + Boost FPS ใหม่ (ของใหม่ที่เกมสร้างเข้ามาเรื่อย ๆ)
    --   ถ้ายิงทุก 5 วิ = game:GetDescendants() ทั้งฉากบ่อยเกินไป = กินโหลดตัวเอง
    RunService.Heartbeat:Connect(function(dt)
        heartbeatAcc = heartbeatAcc + dt
        if heartbeatAcc < 5 then return end      -- แค่จังหวะดูแล ไม่ใช่การตัดสินใจ
        heartbeatAcc = 0
        killCoreGui()

        Guard.resweepAcc = Guard.resweepAcc + dt
        if Guard.resweepAcc < Guard.f_resweep then return end
        Guard.resweepAcc = 0
        -- ⚠ ตั้งค่าก่อน แล้วค่อย Boost (ลำดับเดียวกับตอนสตาร์ต)
        pcall(applyGameSettings)
        -- ⚠ fullSweep = true = ไล่ workspace ใหม่ด้วย เพราะเกาะที่โหลดทีหลัง
        --   จะมีชิ้นใหม่ที่ gfxConn (DescendantAdded) อาจพลาด (โหลดเป็นก้อนเดียว)
        if Guard.lowGfx then applyLowGraphics(true) end
    end)
end

if Guard.keepAlive or Guard.lowGfx then
    -- ⚠ ไล่ workspace ครั้งแรกค้างจังหวะได้เล็กน้อย (เหมือนที่ IY ทำตอนพิมพ์คำสั่ง)
    --   ต้องเกิดก่อนขั้นอื่นทุกอย่าง เพราะถ้าหลุดก่อนหน้านี้ ไม่มีโอกาสได้ต่อ
    -- ⚠ ลำดับสำคัญตามคำสั่งผู้ใช้: ตั้งค่าเกมก่อน แล้วค่อย Boost FPS
    pcall(applyGameSettings)
    if Guard.lowGfx then pcall(applyLowGraphics, true) end
    installGuards()
end

-- ⚠ จุดฟาร์มต่อเกาะประกาศใน CONFIG.FarmSpots (เกาะอื่นนอกจาก Starter)
--   Starter ใช้กลาง House1 ซึ่งคำนวณสดตอนรันด้วย house1StandPoint() ไม่ต้อง hardcode
--   เกาะที่ยังไม่ได้ประกาศ -> ใช้จุดเกิดของเกาะนั้น + เตือนครั้งเดียว (ดู farmSpotFor)

-- forward decl — nextStep/mainLoop เรียกชื่อพวกนี้ แต่ตัวฟังก์ชันอยู่ท้ายไฟล์ (ต้องอ่าน DATA ที่โหลดครบแล้ว)
-- ⚠ ถ้าไม่ประกาศไว้ตรงนี้ Lua จะมองชื่อพวกนี้เป็น global -> เรียกแล้วได้ nil
-- ⚠ ตัวที่นิยามทีหลังต้องเขียน "function ชื่อ(...)" (ไม่ใช่ "local function")
--   ไม่งั้นจะกลายเป็น local ตัวใหม่ที่ทับของเดิม -> ผู้เรียกที่ประกาศไว้ข้างบนได้ nil
local rodPrice, ownsRod, buyRod, islandCost, islandUnlocked, unlockIsland
local travelToIsland, goToFarmSpot
local fetchData, rollSkillOnce, rollUnitOnce, nextStep, runStep
local protectQuestFish, activeFarmIsland
-- ⚠ missionCollect / missionCoin ถูก activeFarmIsland (บรรทัด ~3000) เรียก
--   แต่ตัวมันอยู่ที่ ~3130 = ต้องประกาศล่วงหน้าไว้ตรงนี้
--   ไม่งั้น activeFarmIsland จะมองชื่อเป็น global แล้วได้ nil
local missionCollect, missionCoin
-- ⚠ releaseQuestFish ถูก completeQuest (บรรทัด ~1300) เรียก แต่ตัวมันอยู่ที่ ~3340
local releaseQuestFish

--- แผนทั้งหมด: ทำทีละขั้น แต่ละขั้นมี "เงื่อนไขเงิน" ที่อ่านจาก data.Coin จริงตอนนั้น
---   done(data)  -> ขั้นนี้เสร็จแล้วหรือยัง (อ่านสถานะจริง ไม่นับเวลา)
---   need(data)  -> เงินต้องพอกี่เพื่อจะลงมือ (nil = ไม่ต้องใช้เงิน)
---   run(data)   -> ลงมือทำขั้นนี้ คืน true ถ้าทำสำเร็จ
--- ⚠ ลำดับต้องตรงตามที่ผู้ใช้วางไว้ เพราะเงินก้อนเดียวถูกใช้ซ้ำ:
---   เบ็ด -> ปลดเกาะ -> ย้ายจุด -> เบ็ด -> สกิล -> ปลดเกาะ
local CONFIG = {
    GachaTargetRarity = "Legendary",  -- สกิลเป้าหมาย (Mythical ผ่านด้วย)
    SkillSlotPoll   = 5,       -- วินาทีระหว่างเช็ค "ช่องสกิลที่ยังว่าง" (ควบคู่กับตอนตกปลา)
                              -- ใส่ได้เมื่อไหร่ใส่ทันที พอครบทุกช่องที่ปลดล็อกแล้วจะหยุดเช็คเอง
    -- ⚠ ทะเบียน (ผู้ใช้สั่ง 2026-10-16): รอบก่อนล็อกบอกไม่ได้เลยว่า "ตกปลาได้จริงไหม"
    --   เพราะ path หลักไม่มี log เลย = ล็อก 2.5 ชั่วโมงพิสูจน์ได้แค่ "Mastery ค้างที่ 13"
    --   บรรทัดสรุปหนึ่งบรรทัดต่อ SummaryEvery รอบ mainLoop = ตอบได้ทันทีโดยไม่ท่วม
    Log = {
        Summary     = true,   -- พิมพ์บรรทัดสรุปรอบเวลา
        SummaryEvery = 300,   -- ทุกกี่รอบ mainLoop (หนึ่งรอบ ~5-20 วิ = ทุก ~25-100 นาที)
        Catch       = false,  -- พิมพ์ทุกตัวที่จับได้ (ชื่อ + rarity + น้ำหนัก) — เปิดตอนอยากดู
        SkillFail   = true,   -- พิมพ์รายละเอียดตอนใส่สกิลไม่ขึ้น (ปิด = ไม่รู้ว่าทำไมช่องยังว่าง)
    },
    GoalPoll        = 4,       -- วินาทีระหว่างคิดว่า "ทำอะไรต่อ" จากสถานะจริง
    FarmSpotPoll    = 8,       -- วินาทีระหว่างเช็คว่ายืงอยู่ที่จุดฟาร์มของเกาะปัจจุบันหรือเปลี่ยน
    ActionBackoff   = 6,       -- วินาทีก่อนลอง action ที่ server ปฏิเสธซ้ำ (กันยิงรัว)
    ActionMaxWarn   = 3,       -- เตือนซ้ำได้กี่ครั้งต่อ action เดียวก่อนเงียบ
    -- ⚠ ล้มเหลวครบกี่ครั้งต่อ action เดียว แล้วถือว่า "ตอนนี้ทำอะไรไม่ได้" ปล่อยให้ฟาร์ม
    --   ไม่งั้น action ที่ server ปฏิเสธถาวร (เช่น Accept ที่เงื่อนไขยังไม่ครบ)
    --   จะคืน pending=true ทุกรอบ -> mainLoop ข้ามการเหวี่ยงทั้งเซสชัน ไม่มีทางหยุด
    --   ต้องมากกว่า ActionBackoff พอสมเหตุผล เพราะส่วนใหญ่เป็นแค่ช้า
    ActionGiveUpAfter = 10,

    -- ⚠ กติกาซื้อเบ็ด (ตัดสินใจแล้ว ไม่มีสวิตช์ให้เลือก):
    --   "เบ็ดที่เราจะให้ซื้อเลยด้วยเงินได้ในแต่ละเกาะคืออันที่มีดาเมจสูงสุดเท่านั้น
    --    ถ้าไม่พอคือต้องฟาร์มเพิ่มจนกว่าจะซื้อได้"
    --   = เป้าหมายมีหนึ่งเดียวต่อเกาะ = เบ็ดที่ attackDamage สูงสุดในกลุ่มของเกาะนั้น
    --   เงินไม่ถึงราคา = ไม่ซื้ออะไรเลย ไปฟาร์ม (nextStep ข้อ 4 คืน nil -> mainLoop ฟาร์ม)
    --
    -- ⚠ เคยมีโหมด "ขั้นบันได" ที่เลือก "เบ็ดที่แพงที่สุดที่เงินพอจริง ณ ตอนนี้" — ตัดแล้ว
    --   เพราะมันทำให้หยุดครึ่งทาง: พอมีเงิน 1,300,000 มันซื้อ taoist_rod (atk 4,514)
    --   แล้วนั่งอยู่บนเบ็ดนั้นตลอด เพราะ legacy_rod (atk 8,464) ยังแพงเกินเงินที่เหลือ
    --   = ไม่มีทางขึ้นไปต่อ เพราะเงินที่เหลือมีแต่จะเพิ่มจากการฟาร์ม
    --   แต่ก็ไม่ได้แย่ลงเพียงเพราะเป็นเบ็ดที่จ่ายได้แล้ว = เสียเวลาฟาร์มเปล่า ๆ
    --   บั๊กเดียวกันนี้เกิดกับทุกเกาะ ไม่ใช่แค่ Snow (ดูหัวข้อ RODS ด้านล่าง)
    --
    --   ตารางผลที่ได้ตอนนี้: ปลด Jungle -> ฟาร์มจนได้ steel_rod (90,000)
    --     ปลด Desert  -> ฟาร์มจนได้ diamond_steel_rod (520,000)
    --     ปลด Snow    -> ฟาร์มจนได้ legacy_rod (3,000,000)   (ไม่ใช่ taoist_rod)
    --   เบ็ดระดับกลาง ๆ (stone/iron/golden/golden_steel/taoist) ไม่ถูกซื้อเลย
    --   ซึ่งถูกต้อง เพราะทุกชั้นที่ราคา >= 90,000 ปลดช่องสกิล 4 ช่องเท่ากันหมด
    --   และ EquipmentController อ่านช่องสกิลจาก "เบ็ดที่ใส่อยู่" ไม่ใช่จากที่มีในคลัง

    -- ── แผนเดินเกม ──────────────────────────────────────────
    -- หยุดที่เกาะนี้ (ถึงเกาะนี้แล้ว = ไม่มีแผนอะไรให้ทำ -> ฟาร์มเกาะที่ปลดสูงสุดต่อไป)
    -- ⚠ ต้องขยับไปพร้อมกับ CONFIG.Missions ทุกครั้ง:
    --   ถ้า StopIsland <= เกาะที่ภารกิจต้องไปทำ nextStep จะหยุดที่ stop gate
    --   ก่อนได้ทำภารกิจ แล้วทุกขั้นของภารกิจกลายเป็น dead code
    StopIsland      = "island_lotus",

    -- ── เป้าหมายการสุ่มสกิล ──────────────────────────────────
    -- เกาะที่ไม่มีข้อกำหนดเลย (เกาะแรกใช้สกิลเริ่มต้นก็พอ)
    NoLegendaryIslands = { island_starter = true },
    -- เป้าหมายต่อเกาะ: ต้องมีสกิลที่ "แยกกัน" ตามชนิด >= rarity จำนวน count ตัว
    --
    -- ⚠ กติกานับ (islandSkillsReady):
    --   1) นับจาก skillId ที่แยกกัน สำเนาซ้ำของสกิลเดิมไม่นับ — Inventory.Books[X] = 5 = 1 ตัว
    --   2) สกิลที่ดีกว่าเป้าหมายนับแทนได้ แต่นับเป็น 1 เท่านั้น
    --      เช่น เป้าหมาย Rare 2: Legend 1 + Rare 1 = ผ่าน (2) | Mythical 1 ลอย ๆ = ยังไม่ผ่าน (1)
    --   3) เกาะที่ไม่ประกาศ = ใช้ GachaTargetRarity 1 ตัว (พฤติกรรมเดิม)
    SkillTargets = {
        island_jungle = { rarity = "Rare", count = 1 },
        island_desert = { rarity = "Rare", count = 2 },
        island_snow   = { rarity = "Legendary", count = 1 },
        -- ⚠ Fossil = Legendary 2 ตัว (ผู้ใช้สั่ง 2026-10-21) — "จากเดิม 1 รวมเป็น 2 สกิล"
        --   นับสะสมทั้งบัญชี: Legendary จาก Snow 1 ตัวนับเป็น 1 แล้ว -> ที่ Fossil ขาดอีก 1
        --   ⚠ ต้องได้ครบ "ก่อน" ปลดเบ็ด Dread Fish Rod (ดู dreadSkillsReady / lotusDreadReady /
        --     rodMissionStep) ไม่งั้นบอทจะสลับไปเอาเบ็ดทันทีที่ปลา+เงินครบ โดยสกิลยังไม่ครบ
        island_fossil = { rarity = "Legendary", count = 2 },
        -- ⚠ island_volcano = ยังไม่ประกาศ -> ตกไปใช้ GachaTargetRarity 1 ตัว (พฤติกรรมเดิม)
    },

    -- ── เป้าหมายการสุ่ม Unit ───────────────────────────────────
    -- ⚠ เกาะที่ไม่ประกาศในตารางนี้ = ไม่สุ่ม Unit เลย (ต่างจากสกิลที่ fallback ไป GachaTargetRarity)
    --   เหตุผล: คลัง Unit มีแค่ 3 ช่อง (UnitConfig.FreeCapacity 1 / MaxCapacity 3)
    --   และเกมไม่มีทางขาย Unit — มีแต่ Unit/Remove ที่เป็นการลบถาวร ("ไม่ได้กลับมา")
    --   ถ้าทุกเกาะสุ่ม เราจะเติมคลังด้วยของระดับต่ำจนสุ่มต่อไม่ได้ โดยที่ผู้ใช้ไม่ได้สั่ง
    --   -> ประกาศเฉพาะเกาะที่ผู้ใช้กำหนดจริง แล้วไล่ตามนั้น
    --
    -- ⚠ กติกานับ (islandUnitsReady):
    --   1) นับทุก "ตัว" ที่เรามี (นับที่ uid) ไม่ใช่ที่ unitId
    --      ต่างจากสกิลตรงนี้: สกิลที่ซ้ำกันคือสกิลเดิม แต่ Unit แต่ละครั้งที่สุ่มได้ตัวใหม่
    --      ที่ "roll rarity ของตัวเอง" — สุ่ม ba_chang ได้ Common ครั้งแรก
    --      แล้วสุ่มใหม่ได้ Legendary คือคนละตัว คนละระดับ ต้องนับแยก
    --   2) ตัวที่ดีกว่าเป้าหมายนับแทนได้ แต่ยังนับเป็น 1 เท่านั้น
    --      เป้าหมาย Rare 1 -> Legendary 1 ผ่าน | Common 1 ยังไม่ผ่าน
    --   3) อ่าน rarity จาก data.Units.Owned[uid].Rarity ที่ server replicate มาให้จริง
    UnitTargets = {
        island_jungle = { rarity = "Uncommon", count = 1 },
        island_snow   = { rarity = "Rare",     count = 1 },
    },

    -- ── เกาะที่ใช้สะสมเงิน ──────────────────────────────────
    -- ⚠ ไม่ใช่ที่ตั้งค่า "ฟาร์มที่เกาะไหน" แล้วแล้วจริง
    --   กติกาจริงอยู่ที่ activeFarmIsland: ไปเกาะที่ปลดแล้วและ order สูงสุดเสมอ
    --   ค่านี้มีไว้แค่เป็นกันพลัง ตอนที่ยังไม่มีเกาะไหนปลดเลยในข้อมูล
    FarmIsland      = "island_starter",

    -- จุดยืนตกปลาแยกตามเกาะ — ไม่ประกาศ = ใช้จุดเกิดของเกาะนั้นแทน (ดู farmSpotFor)
    -- ⚠ house1StandPoint() ผูกกับ island_starter/Map/.../House1 อย่างเดียว
    --   เกาะอื่นไม่มีโฟลเดอร์ Map ในดัมป์ จึงต้องประกาศพิกัดเอง
    FarmSpots = {
        island_jungle  = Vector3.new(-1259, 19, -170),
        island_desert  = Vector3.new(38, 10, -1091),
        island_snow    = Vector3.new(1269, 11, -340),
        island_volcano = Vector3.new(2095, 11, 1075),  -- ผู้ใช้ให้พิกัดมา
        island_fossil  = Vector3.new(-742, 10, 2282),  -- ผู้ใช้ให้พิกัดมา
        island_lotus   = Vector3.new(1162, 24, 2611),  -- ผู้ใช้ให้พิกัดมา
    },

    -- ⚠ จุดประจำเกาะ 2 จุดต่อเกาะ (ผู้ใช้ให้พิกัดมา 2026-10-17 = ของจริงในเกม)
    --   spawn  = จุด NPC "Set Spawn" ของเกาะนั้น — จุดที่ต้องไป "ก่อน" ทุกอย่าง
    --            เพราะพอถึงแล้วของที่เหลือของเกาะจะ stream เข้ามา (NPC อื่นจึงมีให้หา)
    --   unlock = จุด NPC ปลดล็อกเกาะของเกาะนั้น
    --
    -- ⚠ หลักฐานว่าพิกัดตรงกับของจริง: npc_unlock_island_3 (Desert Guide) อยู่ที่
    --   (-56.77, 9.95, -1021.57) ตามดัมป์ = ห่างจาก unlock ของ Desert แค่ 5.5 studs
    --   และ spawn ของ Desert (-48, 10, -943) ตรงกับ IslandLandings เดิมพอดี
    --   -> ตารางนี้คือ "เกาะที่ต้องยืนอยู่" ไม่ใช่เกาะเป้าหมายที่กำลังจะไป
    --
    -- ⚠ ทำไมต้องไปใกล้ NPC ก่อนยิง packet: server ตรวจระยะเอง
    --   QuestConfig.NpcDistance = 12 (QuestConfig.lua:6) — อ่านสดตอนรัน ไม่ hardcode
    --   ผู้ใช้เจอจริง 2026-10-16: ยิงจากระยะไกวได้ "Move closer to Jungle Island Guide"
    --   (ข้อความข้างบนมาจากเซิร์ฟ: QuestPacket ตอบ (Boolean, String)
    --    ตัวหลังคือข้อความที่เซิร์ฟเขียนมาเอง ดู QuestController:Complete)
    --   island_starter ไม่มีจุดปลดล็อก (เกาะแรก ไม่ต้องปลด) = ไม่ต้องประกาศ


    IslandPoints = {
        island_starter = { spawn = Vector3.new(-44, 11, 307) },
        island_jungle   = { spawn = Vector3.new(-1168, 11, -66),
                            unlock = Vector3.new(-1264, 11, -117) },
        island_desert   = { spawn = Vector3.new(-48, 10, -943),
                            unlock = Vector3.new(-53, 10, -1018) },
        island_snow     = { spawn = Vector3.new(1176, 9, -270),
                            unlock = Vector3.new(1235, 10, -317) },
        island_volcano  = { spawn = Vector3.new(1770, 9, 1065),
                            unlock = Vector3.new(1879, 13, 1068) },
        island_fossil   = { spawn = Vector3.new(-550, 11, 2170),
                            unlock = Vector3.new(-563, 11, 2228) },
        island_lotus    = { spawn = Vector3.new(1170, 12, 2393),
                            unlock = Vector3.new(1132, 12, 2417) },
    },

    -- จุดลงของเกาะ — ใช้ตอน "ยังหา NPC ไม่เจอ" เท่านั้น (ดู travelToIsland)
    -- เกม replicate NPC ตอนเราเข้าใกล้ (model streaming) ตอนยืนที่ Starter
    --   โฟลเดอร์ Interactives ของ Desert จึงว่างเปล่า = ยังไม่เคย stream เข้ามา
    --   วิธีแก้ = ว่ายไปจุดลงของเกาะก่อน แล้ว NPC ค่อยโผล่มาเอง
    -- ไม่ประกาศ = อ่านจาก <island>.SpawnPoint.Spawners ของเกาะนั้นตอนรัน
    IslandLandings = {
        island_desert = Vector3.new(-48.7626152, 11.749589, -937.482239),
    },

    -- ภารกิจที่ต้องไปทำที่เกาะอื่น (นับปลาเฉพาะชนิด ไม่ใช่แค่เก็บเงิน)
    -- ⚠ ข้อมูลปลาไม่ได้เก็บ "เกาะที่จับ" — เกาะที่นับคือตาราง fishes ใน Catalog.Island
    --   (เกมทำแบบเดียวกันที่ QuestFishRules.qualifiesIsland)
    -- ภารกิจแรกที่ยังไม่ปลดเกาะเป้าหมาย = ภารกิจที่ active อยู่ ทำตามลำดับนี้
    --
    -- ⚠ เกมมีเควสต์ 2 แบบ และ needFish รองรับทั้งสองแบบ:
    --   1) needFish.rarity + count -> นับตามชั้นหายากในเกาะที่ฟาร์ม
    --      (unlock_island_4 ใช้ QuestFishRules.Count)
    --   2) needFish.ids            -> นับตาม "ชื่อปลา" ที่ระบุ
    --      (unlock_island_5 ใช้ QuestFishRules.HasNamed กับ Progress.RequiredFishes)
    --   ทั้งสองแบบพึ่ง Progress ที่รับมาจากเควสต์ที่ "กำลังทำอยู่" ได้เลย
    --   = ค่าในไฟล์นี้เป็นแค่ fallback ตอนที่ยังไม่ได้กดรับเควสต์ (ดู missionRequirement)
    --   และทั้งสองแบบ "ปลาที่ล็อกไว้เกมนับไม่ได้" ต้องปลดล็อกก่อนกด Complete
    --
    -- ── kind = "rod" (เควสต์เบ็ด) ใช้กติกาคนละชุดกับการปลดเกาะ ──
    --   need = {mode=...} มี 4 แบบ:
    --     counter = ตัวนับสะสมที่ server นับให้ (Progress.CurrentFished)
    --     item    = นับไอเทมใน Inventory.Items[itemId].count (ไม่ใช่ปลา)
    --     named   = สแกนกระเป๋าตามชื่อปลา (มี minWeight ได้)
    --     rarity  = สแกนกระเป๋าตามชั้นหายากของเกาะที่ระบุ
    --   needRod = ต้องมีเบ็ดตัวนี้ในคลังก่อนจึงจะรับเควสต์ได้ (กฎของ server)
    --   coin    = เงินที่ต้องจ่ายตอนกด Complete
    --   npcId/npcIsland = ใช้เป็นทางสำรอง ถ้ากด Complete จากระยะไม่ผ่าน
    Missions = {
        {
            key          = "unlock_island_4",
            targetIsland = "island_snow",     -- จบภารกิจเมื่อเกาะนี้ถูกปลด
            farmIsland   = "island_desert",   -- ไปตกที่นี่ระหว่างทำภารกิจ
            needFish     = { rarity = "Legendary", count = 3 },
        },
        {
            key          = "unlock_island_5",
            targetIsland = "island_volcano",
            farmIsland   = "island_snow",
            -- เควสต์นี้ระบุชื่อปลา ไม่ใช่ชั้นหายาก:
            --   "Bring 1 Frozen Crown Dragonfish, 1 Frosttusk Seal, and 1 Frostmaw Monster
            --    from Island 4, along with 4,000,000 Coins"  (npc_unlock_island_5.lua:61)
            -- ทั้งสามตัวเป็น Legendary ของ Snow (Data/Catalog/Fish.lua:796-820)
            -- ⚠ เบ็ดของ Snow = legacy_rod (3,000,000) ซึ่งแพงกว่า 4,000,000 ไม่ได้
            --   ต้องเก็บเงินให้ได้อย่างน้อย 3,000,000 ถึงจะซื้อเบ็ดได้
            needFish     = {
                ids = {
                    frozen_crown_dragonfish = 1,
                    frosttusk_seal         = 1,
                    frostmaw_monster       = 1,
                },
            },
        },
        {
            -- ── เบ็ดที่ดีที่สุดหลังปลด Volcanic ──
            -- ⚠ legacy_rod เป็นเบ็ดในร้านของ SNOW ราคา 3,000,000 (RodShopConfig.lua)
            --   ไม่ใช่ของที่ได้ตอนปลด Volcanic — Volcanic/Fossil ไม่มีเบ็ดในร้านเลย
            --   และเควสต์นี้บังคับว่าต้องมี Legacy Rod ถึงจะรับได้
            key          = "crimson_bead_rod",
            kind         = "rod",
            targetRod    = "crimson_bead_rod",
            npcId        = "npc_crimson_bead_rod",
            npcIsland    = "island_volcano",
            needRod      = "legacy_rod",
            need         = { mode = "counter", have = "CurrentFished", need = "RequiredFished", fallback = 100 },
            coin         = 3000000,
            farmIsland   = "island_volcano",
        },
        {
            -- Bamboo Fragment ตกที่ Jungle 10% ต่อครั้ง (Catalog/Material.lua)
            --   = ไม่มีจุดตกเฉพาะ ตกที่ไหนบน Jungle ก็ได้
            -- ⚠ fragment เป็น "Item" ไม่ใช่ปลา -> อยู่ใน Inventory.Items ไม่ใช่ Inventory.Fishes
            --   และ SellAll ขายแค่ปลา = ไม่ต้องล็อคไว้ (ต่างจากภารกิงอื่น)
            key          = "bamboo_rod",
            kind         = "rod",
            targetRod    = "bamboo_rod",
            npcId        = "npc_bamboo_rod",
            npcIsland    = "island_volcano",
            needRod      = "crimson_bead_rod",
            need         = { mode = "item", itemId = "bamboo_fragment", count = 20 },
            coin         = 3600000,
            farmIsland   = "island_jungle",
            -- ⚠ farmIsland != เกาะที่ปลดสูงสุด: ต้องไปตกที่ Jungle ให้ fragment ครบก่อน
            --   พอครบแล้วถ้าเงินยังไม่พอ ให้กลับไปฟาร์ม Volcanic (activeFarmIsland จัดการ)
        },
        {
            key          = "unlock_island_6",
            targetIsland = "island_fossil",
            farmIsland   = "island_volcano",
            -- "Bring 1 Ancient Trihorn Fish (at least 1,200 kg), 1 Stormblade Shark (at least 2,000 kg),
            --  and 1 Lavascale Dragonfish (at least 2,500 kg) from Island 5 + 15,000,000 Coins"
            --   (QuestConfig.lua:185-190)
            -- ⚠ minWeight = ตัวแยกต่างหากจาก QuestFishRules.SelectNamed:92-101
            --   ปลาที่น้ำหนักไม่ถึง "ไม่นับ" แต่ไม่กินโควตาของชนิดนั้น
            --   = จับตัวเบามาเรื่อย ๆ ได้ ไม่ต้องกลัวว่าจะเสียที่
            -- ⚠ minWeightFromConfig = ชื่อ key ใน QuestConfig ที่เก็บน้ำหนักขั้นต่ำ
            --   ของเควสต์นี้ ให้อ่านสดตอนรัน (ค่าในไฟล์นี้เป็นแค่ fallback)
            -- ⚠ ต้องระบุ key เสมอ ห้ามให้ฟังไปหาน้ำหนักของเควสต์อื่นมาใช้ลอย ๆ
            --   เช่น unlock_island_5 ถ้าไปตกน้ำหนักของ island 6
            --   จะไปตัดปลาที่หนัก 1,200kg ทิ้งทั้งที่เควสต์นั้นไม่มีเงื่อนไขน้ำหนักเลย
            minWeightFromConfig = "UnlockIsland6MinWeightKg",
            needFish     = {
                ids = {
                    ancient_trihorn_fish  = 1,
                    stormblade_shark      = 1,
                    lavascale_dragonfish  = 1,
                },
                minWeight = {
                    ancient_trihorn_fish = 1200,
                    stormblade_shark     = 2000,
                    lavascale_dragonfish = 2500,
                },
            },
        },
        {
            -- ── เกาะ 7 (Lotus): เควสต์ 3 สเต็ป ไม่ใช่เควสต์ปลาธรรมดา ──
            --   Step 1 เก็บ Snow Flower 10 ดอกที่ Snow ตอน Rainbow Rain -> Advance
            --   Step 2 ตกปลาที่ Volcanic ให้ได้ Magma Essence 10 ชิ้น     -> Advance
            --   Step 3 จ่าย 10,000,000 + 200 gems                        -> Complete
            --   (QuestConfig.lua:798-814 · npc_unlock_island_7.lua:85-125)
            -- ⚠ missionRequirement คืน nil ให้ภารกิจนี้ (ไม่มี need/needFish)
            --   -> missionStep ต้องแยก kind == "lotus" ออกก่อน guard นั้น (ดู lotusMissionStep)
            -- ⚠ farmIsland = volcano ใช้เฉพาะ Step 2 · Step 1/3 ใช้เกาะที่ปลดสูงสุด (Fossil)
            --   ซึ่งเป็นเกาะของปลา Mythical ที่ dread_fish_rod ต้องใช้ = เก็บไปพร้อมกันได้
            -- ⚠ วางก่อน dread_fish_rod โดยตั้งใจ: ต้องถือเควสต์นี้ค้างไว้เพื่อให้ดอกไม้เกิด
            --   (SnowFlowerController.lua:26-33 เช็ค Quest.Current.Id == "unlock_island_7")
            --   ส่วน dread ไม่ต้องรับค้าง — ปลา Mythical นับจาก Inventory.Fishes
            --   จึงสลับไป Accept+Complete ชั่วคราวเมื่อของครบ (ดู lotusDreadSwap)
            key          = "unlock_island_7",
            kind         = "lotus",
            targetIsland = "island_lotus",
            farmIsland   = "island_volcano",
            coin         = 10000000,          -- fallback; ค่าจริงอ่านจาก IslandConfig ตอนรัน
        },
        {
            -- "Bring 1 Mythical fish caught at Fossil Island (Island 6) + 10,000,000 Coins"
            --   (npc_dread_fish_rod.lua:47)
            -- ⚠ ไม่มีเงื่อนไขน้ำหนัก — Count(data,"island_fossil","Mythical") ส่งอาร์กิวเมนต์ที่ 4 = nil
            --   และ Mythical ของ Fossil มี 3 ตัว รวม weight 100/600 = 16.7% -> เฉลี่ย ~6 ครั้งที่ตก
            key          = "dread_fish_rod",
            kind         = "rod",
            targetRod    = "dread_fish_rod",
            npcId        = "npc_dread_fish_rod",
            npcIsland    = "island_fossil",
            need         = { mode = "rarity", rarity = "Mythical", islandId = "island_fossil", count = 1 },
            coin         = 10000000,
            farmIsland   = "island_fossil",
            -- ⚠ เก็บปลาตัวที่น้ำหนักน้อยที่สุด (ผู้ใช้สั่ง 2026-10-21) — ตัวหนักขายได้เงินมากกว่า
            --   Quest ไม่มีเงื่อนไขน้ำหนัก (fish = {islandId, rarity, count} ใน QuestConfig:713)
            --   = ทุกตัวที่ตกได้ถูกนับ เก็บตัวเบาไว้ 1 ตัว ขายที่เหลือ
            keepLightest = true,
        },
    },

    -- Move (tween)
    TweenSpeed      = 25,      -- (เดิม 35: ลดเพื่อทดสอบว่าเซิร์ฟดึงกลับเพราะเร็วเกิน — ถ้าไม่ช่วยค่อยปรับกลับ) studs/s (คงที่ทุก FPS — tween ขับด้วยเวลาจริง ไม่ใช่จำนวน step)
    TweenTick       = 0.03,    -- ระยะห่างขั้นต่ำระหว่างการเขียน CFrame (เยอะ = นุ่มขึ้น ไม่กระทบความเร็ว)
    TweenMaxTry     = 20,
    -- ⚠ ค้างนิ่งกี่วินาทีถึงถือว่า "ทริพแล้ว" -> เลิก tween รอบนี้ทิ้ง
    --   ให้ tweenTo รอบถัดไปยิงใหม่จากตำแหน่งจริง ณ ตอนนั้น (ผู้ใชาสั่ง 2026-10-16)
    -- ⚠ ห้ามตั้งสั้นกว่า ~2: tween ข้ามเกาะ 3577 studs / 29 = 123 วินาที
    --   ถ้าตัวละครถูกเกมดึงกลับเป็นจังหวะ ๆ ต้องได้เวลาให้กลับไปต่อก่อนตัดสินว่าค้าง
    TweenStuckSec   = 5,
    -- ขยับไปกี่ studs ถึงถือว่า "ไม่ค้าง" (ในหน้าต่างเวลาข้างบน)
    TweenStuckMove  = 1,
    -- ⚠ เซิร์ฟไม่รับตำแหน่งที่เราเขียน (ข้ามเกาะแล้วถูกดึงกลับที่เดิม)
    --   เทียบ "ตำแหน่งที่ควรจะอยู่ ณ เวลานี้" กับ "ตำแหน่งจริง"
    --   ถ้าห่างเกินนี้ = เราเขียนไปครบเส้นทางแต่ตัวละครไม่เคยไปตาม
    --   เหตุจริงมาจาก log 2026-10-16: 1021.7 studs / TweenSpeed 29 = 35 วิ
    --   ตัวจับค้างเดิมไม่จับ เพราะมันอ่านตำแหน่งที่เราเพิ่งเขียนเอง
    TweenRejectedSec = 2,
    ArriveXZ        = 2.5,    -- ถือว่าถึงเป้าเมื่อห่างเฉพาะแนวนอนไม่เกินกี่ studs
ArriveXZ        = 2.5,    -- ถือว่าถึงเป้าเมื่อห่างเฉพาะแนวนอนไม่เกินกี่ studs
    StandHeight     = 4,       -- ตกจากจุดเป้าประมาณกี่ studs ถึงจะยืนนิ่ง (ใช้เป็น tolerance แนวตั้ง)
    -- ⚙ "โซนที่ยังยกแรงไว้ได้" (ผู้ใช้สั่ง 2026-10-17) = หลังโดนดึงกลับนิดหน่อย
    --   โซนนี้กว้างกว่า ArriveXZ/StandHeight มาก โดยตั้งใจ เพราะสองอย่างนี้ทำหน้าที่ต่างกัน:
    --     • ArriveXZ/StandHeight = "เข้ม" = ตัดสินว่า 'ถึงตามที่สั่งไว้ไหม' → ใช้ตอนเริ่มงานที่จุดนั้น
    --     • HoldXZ/HoldHeight    = "หลวม" = ตัดสินว่า 'ยังอยู่ที่เดิมไหม'     → ใช้ตัดสินว่าจะปล่อยแรงไหม
    --   ถ้าใช้เกณฑ์เดียวกัน = เซิร์ฟดันตัวเราหลุด 3 studs ก็ปล่อยแรง = ตัวละครตก = บั๊กเดิมกลับมา
    HoldXZ          = 14,      -- ยังอยู่ในโซนเดิมได้ถ้าห่างแนวนอนไม่เกินกี่ studs
    HoldHeight      = 18,      -- ยอมหลุดแนวตั้งได้กี่ studs (คลื่น/น้ำขึ้นลง/ตัวลอยขึ้นจากแรงต้าน)
    -- ⚠ ค่าสองชุดนี้ "ผู้ใช้ตั้งใจ" ปรับได้ถ้าเห็นว่าหลุดบ่อยหรือแน่นเกิน
    House1Drop      = 10,      -- จุดยืน = กลางบ้าน - N studs (ผู้ใช้ยืนยันว่าได้ผล)
    -- จุดยืนที่สคริปต์สร้างเอง — ใช้ "เฉพาะตอนไปตกบอส" (ผู้ใช้สั่ง 2026-10-16)
    --   ที่อื่นไม่สร้าง: noclip เปิดค้าง + startAntiSink() ฆ่า velocity ทุกเฟรม
    --   = ตัวละครลอยนิ่งที่จุดเดิมเหมือนแต่ก่อนมีแท่นนี้ขึ้นมา
    --   บอสต้องมีพื้นจริง เพราะต้อง "ยืน" ให้เหยือกตกลงเขตและรัศมีคำนวณจากจุดยืน
    StandSpot = {
        Enabled    = true,
        Name       = "AP_StandSpot",
        Width      = 12,      -- แท่นกว้างเท่าไร (studs)
        Height     = 20,      -- หนาแค่ไหน = ก้นแท่นลงลึก ตัวละครตกมาติดขอบบนเสมอ
        Drop       = 2,       -- ผิวบนอยู่ต่ำกว่าเป้ากี่ studs (ขายืนบนขอบบน -> HRP สูงขึ้นมาเท่านี้)
        AboveWater = 2,       -- บังคับให้ผิวบนสูงกว่าผิวน้ำอย่างน้อยกี่ studs (กันไปตกเป็นคนว่ายน้ำ)
    },
-- ⚠ ตรึงตัวตอน "ถึงจุดแล้ว" (ผู้ใช้สั่งแก้ 2026-10-16:
    --   "ใช้ตรึงตัวเฉพาะตอนถึงเท่านั้น ... พอจะขยับไปไหนค่อยปล่อยตรึง")
    --   ปัญหาจริง: noclip + ฆ่า velocity ทุกเฟรม = ไม่ได้กันการตก แค่ชะลอ
    --     ความเร็วตกถูกจำกัดที่ ~g*dt/2 ≈ 3.3 studs/วิ (60 Hz) = ยังไหลลงทุกวินาที
    --     พอถึงระดับน้ำ เกมสลับเป็น "กำลังว่าย" -> FishingController:HookSwimming
    --       -> ShouldCancelOnSwim -> FishCancel -> "Finish what you are doing first"
    --
    -- ⚠ เปลี่ยนวิธีจาก "ตรึง" เป็น "ยกแรงโน้มถ่วง" (ผู้ใช้สั่ง 2026-10-17:
    --   "แก้ระบบตรึง เป็นไม่ต้องตรึง แต่ให้ลดหรือลบแรงโน้มถ่วงออก ยังเดินได้ปกติ
    --    แค่จะไม่ตกลงตามแรงโน้มถ่วง")
    --   Anchored = engine จับ assembly ทั้งก้อน = เดินไม่ได้เลย ปลาไม่งอย
    --   ใช้ VectorForce ชดเชย (น้ำหนัก x gravity) แทน = ยังเดินได้ปกติ แต่ไม่ไหลลง
    --   ดู S.tools.setNoGravity() · S.tools.pin()
    --
    --   Pin = true  = ถึงจุดแล้วยกแรงโน้มถ่วงไว้ · ขยับก่อนปล่อยทุกครั้ง
    --     เงื่อนไข "ถึงแล้ว" = ตำแหน่งจริงของตัวละคร ห่างจุดเป้าไม่เกิน
    --     ArriveXZ (แนวนอน) / StandHeight (แนวตั้ง) = เกณฑ์เดียวกับที่สคริปต์
    --     ใช้ตัดสินว่ามาถึงอยู่แล้ว ไม่ได้เพิ่มเกณฑ์ใหม่ให้ต้องเชื่อ
    --   Pin = false = ปล่อยให้ไหลเหมือนเดิม (ตกช้า ๆ แต่ยังตก)
    Pin            = true,
    Pin            = true,
    -- ⚙ tween ไปเป้าหมายตรง ๆ ไม่มีการดำน้ำ (ผู้ใช้สั่ง 2026-10-17)
    --   เดิม = true เฟส 3 ตัว: มุดใต้ตัวเอง -> ใต้จุดเป้า -> ขึ้นจุดเป้า
    --   = ไปไหนก็มุดน้ำก่อน เสียเวลาและดูเหมือนตัวละครจมทะเลทั้งเซสชัน
    --   false = tweenDiveTo พาไปที่เป้าตรง ๆ 1 เฟส (ดู tweenDiveTo)
    --   ค่านี้เป็นค่าที่ผู้ใช้ตั้งใจ ไม่ต้องแก้กลับเอง
    TweenViaWater   = false,
    -- ลึกกว่าผิวน้ำกี่ studs (เกม clamp ที่ RootSubmergeDepth+MaxDipBelowTarget = 0.75+1.5 = 2.25)
    -- ลึกเกินนั้นเกมจะดันขึ้นมาเอง เลยอย่าลึกเกิน 2
    -- ⚠ ใช้เฉพาะตอน TweenViaWater = true เท่านั้น ตอนนี้ไม่ได้ใช้
    UnderwaterDepth = 2,

    -- noclip: เปิดค้างตลอดการทำงาน ไม่มีจุดที่ปิด (ผู้ใช้ต้องการ)
    -- ถ้าอยากปิดชั่วคราว เรียก setNoclip(false) เองได้จาก console

    -- Fishing (port จาก test_cast_nearest_water.lua + test_cast_under.lua)
    MaxDist         = 80,      -- รัศมีค้นน้ำเปิดสูงสุด (ServerMaxDistance)
    ScanStep        = 4,       -- ระยะห่างระหว่างวงแหวนค้นน้ำ (studs)
    CastPerfect      = true,
    CastLuckTarget   = 0.92,
    CastHoldTime     = 0.20,
    -- MinHoldTime = ของเกม 0.15 = task.delay ระหว่างกดปุ่มกับเข้าสู่ Throwing
    --   ย่อเหลือเฟรมเดียว หลอด luck เต็มทันทีอยู่แล้ว ไม่ต้องรอให้กดนาน
    MinHoldTime      = 0.01,
    -- CastCooldown = backoff ตอน "เหวี่ยงไม่ได้" (หาน้ำไม่เจอ / ยังถือเบ็ดไม่ได้)
    --   ต้องพอให้ไม่วน castToNearestWater (มัน raycast วงแหวนหลายสิบจุด) จนค้างเฟรม
    CastCooldown     = 0.8,
    -- RecastDelay = หลังเหวี่ยงสำเร็จ รอก่อนวนรอบถัดไป (state = Throwing อยู่แล้ว รอตรงนี้แค่ไม่ได้ poll)
    RecastDelay      = 0.05,
    -- ResultPoll = ขัดจังหวะถาม state ระหว่างรอเกมรีเซ็ตกลับ Idling หลังตกปลา
    --   ยิ่งถี่ยิ่งจับ Idling ได้เร็ว แต่เป็น spin loop — 0.03 คือจุดที่ยังไม่กินเฟรม
    ResultPoll       = 0.03,
    -- ⚠ ReelCps = เกมจำกัดการกดเมาส์ไว้ที่ Click.ManualCps = 6
    --   แต่สคริปต์นี้ยิง FishReelPull ตรงๆ เลยข้าม gate ฝั่ง client นั้นไป
    --   (ดู FishingClickTiming.TryManual — ใช้เฉพาะตอนคนกดเมาส์จริง)
    --   server จะรับได้เท่าไหร่ยังไม่รู้ = ค่านี้คือตัวเลขที่ต้องลอง
    --   ถ้าตกปลาไม่เร็วขึ้นเท่าที่ควร = server แคปไว้ต่ำกว่านี้ -> ลดลงทีละ 2
    ReelCps          = 20.0,
    ReelJitter       = 0.004,
    -- QteDelay = ต้องรอให้ "input settle" ของ server ก่อนตอบ QTE
    --   ⚠ เดิมเป็น 0 = ตอบทันทีที่ได้ prompt (ภายใน 0-16ms) ผลคือ ถูก/ผิด
    --     ขึ้นกับว่าเฟรมนั้นยาวแค่ไหน = สุ่ม (ตรงกับที่เห็นว่าบางจังหวะถูก บางจังหวะผิด)
    --   กฎของ server อยู่ในเกมเอง: FishingConfig.Counter.StrictInputSettleTime = 0.08
    --     (ชื่อนี้ไม่มีที่ไหนใน client dump ที่เรียกมัน = อ่านจากฝั่ง server แน่นอน)
    --   -1 = อ่านค่าจากเกมทุกครั้ง (ค่าเริ่มต้น) / 0 = ตอบทันที (ไม่แนะนำ) / >0 = บังคับเอง
    --   หน้าต่าง QTE กว้าง 1.25s จึงยังเหลือเวลาเยอะ ไม่ต้องกลัวรอ
    QteDelay         = -1,
    -- QteLog = พิมพ์ทุก prompt/ผลลัพธ์ QTE + สรุปเป็น % ถูก
    --   ไม่มีอันนี้มาก่อนหน้านี้ = ตอน QTE ผิด ไม่มีทางรู้ว่าผิดเพราะ "ยิงช้าเกิน"
    --   หรือ "ยิงเร็วเกิน" หรือ "key ผิด" — เดากันไปเรื่อย ๆ
    QteLog           = false,
    QteLogEvery      = 10,      -- พิมพ์สรุปทุก N ครั้ง (0 = ปิดสรุป แต่ยังพิมพ์รายครั้ง)

    -- หลังตกปลา เกมนับถอยหลัง Loot.ConfirmReadyDelay (0.75) แล้วค่อย
    -- task.delay(General.CastCancelDelay = 0.5, ResetAll) = 1.25s
    -- ⚠ ทดสอบมาแล้ว 1.25 คือขั้นต่ำจริงของ server — ย่อแล้วโดน 2 แบบ
    --   SessionActive = "Finish what you are doing first"  (โดนที่ 0.65s)
    --   CastCooldown  = "Casting too fast"                (โดนตอนย่อ CastCancelDelay)
    --   -> server บังคับตามเวลาที่นักพัฒนาตั้งไว้ ไม่มีช่องให้ย่อ
    --   ค่าทั้งสองตัวนี้จึงต้องเป็นค่าของเกม แตะไม่ได้ (แตะแล้วไม่มีทางเร็วขึ้น)
    LootConfirmDelay = 0.75,
    -- CastRetryDelay = ถ้าวันหนึ่งโดนปฏิเสธจริง ให้หยุดก่อนลองใหม่
    --   ไม่งั้นจะยิงรัว ๆ ไปเรื่อยจนโดน rate limit ซ้อน = ช้ากว่าเดิมด้วยซ้ำ
    CastRetryDelay   = 0.4,

    -- LOOT WINDOW (หน้าต่าง "ได้ปลา" ที่ต้องไม่ให้ขึ้นเลย)
    LootSuppress     = true,    -- บังคับให้เกมเดินสาย "ไม่มี loot UI" ของตัวเอง (ไม่ render ตั้งแต่ต้น)

    -- ── DAILY REWARD (ของเข้าเล่นรายวัน วันที่ 1-7) ──────────────────
    -- true = รัน "ครั้งเดียว" ต่อการสตาร์ทสคริปต์ ต่อจากขั้น GUARD (กัน AFK / ลดกราฟิก)
    --
    -- ⚠ กติกาของเกมที่ห้ามข้าม: DailyRewardUtil.compute_state เช็ค
    --   now < LastClaim + 86400  -> ยังรับไม่ได้ (คืน WaitingDay)
    --   = ล็อก "วันละครั้ง" ตอนรับแล้วปุ่มของวันที่ 2 จะไม่ขึ้น
    --   และ packet ไม่รับ argument วันด้วย (DailyReward/Claim ไม่มีพารามิเตอร์)
    --   = server เป็นคนเลื่อนวันเอง ข้ามวันไม่ได้ แม้เราจะยิงรัวกี่ครั้งก็โดนวันเดิม
    --   สคริปต์จึงยิง "ครั้งเดียวต่อสตาร์ท" แล้วอ่านผลกลับจากข้อมูลจริง
    --   ถ้ายังไม่ถึงเวลา = พิมพ์บอกว่ารอบหน้าได้วันไหน แล้วข้าม (ไม่ยิงรัว ไม่กินโควตาของวันหน้า)
    DailyReward      = true,

    -- ⚠ ผลจาก skill_rate_test.lua (ยิง 7 ครั้งใน 80 วิ  = หนึ่งครั้งต่อรอบตกปลาพอดี)
    --   ตัวจำกัดอัตรายิงไม่ใช่ฝั่งเรา แต่คือ 2 อย่างที่แก้จากสคริปต์ไม่ได้:
    --     1) Player:GetAttribute("IsUsingSkill")  — server เปิด/ปิด ไม่มีผู้เขียนในดัมป์
    --        (มีแต่ผู้อ่านใน AuraController / RodController) = ยิงทีละอันระหว่างอนิเมชัน
    --     2) cooldown ของแต่ละสกิลในแคตตาล็อก (4.5-5.5s) ที่ server ส่งมาเป็น phase "Cooldown"
    --   ตัวแปรที่เราควบคุมจริงมีอย่างเดียว: จำนวนช่องสกิลที่ปลดล็อก (สูงสุด 4)
    --   -> อยากยิงบ่อยขึ้น = ต้องอัป mastery ของเบ็ด ไม่ใช่ลดเวลาข้างบน
    Skills           = true,
    -- หน่วงขั้นต่ำระหว่างการยิงสองครั้ง (ทุกช่องรวมกัน) — กันยิงรัวในเฟรมเดียว
    --   ไม่ใช่ตัวจำกัดอัตราจริง (ผลทดสอบห่างจริง 6-7s) แต่คงไว้กัน server ปฏิเสธ
    SkillMinGap      = 0.35,
    -- "กันยิงซ้ำก่อน server ตอบ" เท่านั้น — ทันทีที่ server ส่ง Cooldown/Ready มา
    --   ค่านี้จะถูกเขียนทับทิ้ง ไม่ได้บังคับอัตรายิง
    SkillCastWait    = 0.8,

    -- ── AURA (กองสุ่ม Aura: +Luck ตอนตก + ราคาขายตอนขาย) ─────────────────
    -- ⚠ ช่องใส่ Aura ของเกมมี 1 ช่องเท่านั้น
    --   (PlayerData/Template.lua:18 -> AuraEquip = "None" เป็นสตริงเดียว ไม่ใช่ list
    --    และ equipmentItems.lua:131 เทียบ `a2.AuraEquip == i6` กับ key เดียว)
    --   = สลับไปมาได้ ไม่สะสมพร้อมกัน -> จึงต้องเลือก "ตัวที่ดีที่สุด ณ ตอนนั้น" เสมอ
    --
    -- ⚠ เพดานคลัง aura = 100 ตัว (ผู้ใช้ยืนยันค่าจากเกม) แต่ grep AuraCapacity /
    --   MaxAura ในดัมป์ไม่เจอที่ไหนเลย = เป็นกติกาฝั่งเซิร์ฟ อ่านค่าจากดัมป์ไม่ได้
    --   KeepMax จึงใช้ค่านี้แทน ถ้าเกมเปลี่ยนไปต้องแก้ตรงนี้ที่เดียว
    Aura = {
        Enabled    = true,
        KeepMax    = 100,    -- เพดานคลัง (ค่านี้คือขนาดคลังของเกม)
        ReserveGem = 0,      -- กัน gem ไว้ (gem - Reserve >= ราคาถึงจะสุ่ม)
        PullCount  = 1,      -- สุ่มทีละกี่ครั้ง ต้องเป็น 1 หรือ 10 (AuraGachaConfig.Pull.Counts)
        -- ⚠ ทำไมเป็น 1 ไม่ใช่ 10 (BulkDiscount[10] = 1 = ไม่มีส่วนลด ราคาต่อครั้งเท่ากัน):
        --   - จำนวนแพ็กเก็ต Pull เท่ากันทั้งสองแบบ (1 packet ต่อรอบตรวจ) ไม่มีโทษทางดัน
        --   - Pity (Legendary 45 / Mythical 150 / Divine 1000) นับทีละครั้ง ไม่เกี่ยวขนาดก้อน
        --   - ทีละ 1 ไหลช้ากว่า 10 เท่า (3.3 gem/วิ แทน 33 gem/วิ ที่ Poll = 3)
        --   - ใช้ gem ได้ถึงตัวสุดท้าย (เหลือ 9) ไม่ใช่ทิ้งว่างไว้สูงสุด 99
        --   - ทิ้งของเวรทีละชิ้น (EquipmentRemove 1 packet) ไม่ยิงรวด 10 อัน
        Poll       = 3,      -- ตรวจ "มีอันที่ดีกว่าที่ใส่อยู่ไหม" ทุก N วินาที

        -- ⚠ true = หยุดสุ่ม Aura ตั้งแต่ตอนที่ได้เบ็ด Dread Fish Rod แล้ว
        --   ทับได้จากภายนอกด้วย _G.Config.SaveGemAfterDreadFishRod (ดูบล็อกท้าย CONFIG)
        --   (ก่อนหน้านั้นยังสุ่มตามปกติ เพื่อหา Aura มาใช้ตามแผนปกติ)
        --   เหตุผล: หลังจบเควสต์ทั้งหมดแล้ว Aura ไม่ถูกใช้ต่อ -> เก็บ gem ไว้แทน
        --   ยังใส่/ทิ้ง Aura ที่มีอยู่ตามปกติ เปลี่ยนแค่ไม่สุ่มเพิ่มเท่านั้น
        SaveGemAfterDreadFishRod = false,

        -- ── กติกา gems สำหรับปลดล็อกเกาะ 7 (ผู้ใช้สั่ง 2026-10-20) ──────────
        --   สุ่มจนได้ Aura ที่ +Luck ≥ LuckTarget แล้วหยุด เพื่อกัน gems ไว้ 200
        --   "ถ้ามี Gems 210 ขึ้นไป (พอสุ่ม 1 รอบแล้วยังเหลือ 200) ก็ให้สุ่มจนเหลือแค่ 200"
        --   = เงื่อนไขคือ gem - LotusGemReserve >= ราคาสุ่ม (ไม่ใช่ gem >= 210 ตายตัว)
        LuckTarget      = 4,
        LotusGemReserve = 200,
    },

    -- ── BOSS ────────────────────────────────────────────────────────────
    -- ⚠ บอสไม่ได้เกิดที่จุดที่เราเลือกได้:
    --   เกิดตามอากาศอากาศ (Catalog/Boss.lua) และมี active แค่ 1 เขตทั้งเซิร์ฟ
    --   (FishingConfig.Boss.ActiveRegionsMin/Max = 1)
    --   และแม้ขว้างเข้าเขตบอส มีโอกาสแค่ 10% ที่จะเกี่ยว (Boss.BiteChance = 0.1)
    Boss = {
        Enabled  = true,
        HeightUp = 10,       -- ยืนสูงกว่าจุดบอส N studs (ผู้ใช้กำหนด)
        NearDist = 60,       -- เข้าใกล้กว่านี้ถือว่าถึงจุดแล้ว ไม่ต้องเดินซ้ำ
        Poll     = 1,        -- เช็คว่ายังต้องตีอยู่ไหมทุก N วินาที
        -- ⚠ ธง bossHolding = true แล้ว mainLoop จะข้าม runStep (6092) กับ goToFarmSpot (6107)
        --   แต่ยัง "เหวี่ยงปลาต่อ" ที่จุดที่ยืนอยู่ = ถ้าตัวละครถูกลากออกจากเขตบอส
        --   (บูต 7900 / ขายปลาเต็ม 6072 / ไปตกที่เกาะอื่น) มันจะยืนเหวี่ยงที่จุดเดิม
        --   จนกว่าบอสจะหมดอายุ = บอสหายฟรีโดยไม่รู้ตัว
        --   -> วัดระยำจากเขตบอสสด ๆ ถ้าเกิน DriftedDist = หลุด ให้ว่ายกลับ
        --   (ให้เผื่อจาก NearDist เพราะต้องเหวี่ยงได้จริงถึง MaxCastDist = 70)
        DriftedDist = 120,
        -- ⚠ เป็นแค่ "กันยิงซ้ำ" ไม่ใช่เกณฑ์ตัดสินบอส (Poll = 1 วิ ถ้าไม่บันทึกจะว่ายทุกวินาที
        --   ตอนบอสไปไม่ถึงจริง = log รก + tween ซ้อน) การตัดสินว่ายังตีบอสอยู่ไหม
        --   อ่านจากเขต/ธง BossSpawnClaimed ของเกมเท่านั้น
        DriftRecoverSec = 15,

        -- ⚠ ระยะที่ยังตกปลาได้จริง (FishingConfig.Cast.ServerMaxDistance = 80)
        --   เหลือสิบ studs เผื่อจุดที่ยืนคลาดจากกลางเขต ไม่ให้ชนขอบ
        MaxCastDist = 70,
        -- ⚠ ตกบอสไม่ผ่านกี่ครั้งติดกัน = เลิกยืนกลางน้ำ ไปยืนพื้นดินรอบเขตแทน
        --   (ผู้ใชาสั่ง 2026-10-15) นับจาก FishReset ที่เป็นกลุ่ม Cast failed
        FailToBackup = 3,
        -- รัศมีที่ยอมไปหาพื้นดินรอบเขตบอส (studs)
        LandSearchR = 70,
        -- ยืนสูงเหนือผิวพื้นกี่ studs (กันตัวจม/โดนหัว)
        LandStandUp = 3,
        -- เผื่อด้านบนพื้นต้องโล่งกี่ studs ถึงถือว่า "เหยียบพอยืนได้"
        LandHeadRoom = 8,
        -- ⚠ เกาะที่ต้องปลดก่อนถึงจะเริ่มล่าบอส (ผู้ใช้สั่ง 2026-10-24)
        --   "เริ่มล่าบอสหลังจากปลดเกาะ Desert เท่านั้น — ถ้าบอสเกิดแต่ยังปลดแค่
        --    Starter/Jungle ให้ฟาร์มตามปกติเพื่อปลด Desert ก่อน เพราะถึงตอนนั้น
        --    เรามีสกิลอย่างต่ำ Rare แล้ว = ตกบอสได้ง่ายขึ้น"
        --   ⇒ ข้อจำกัดนี้อยู่เหนือ "บอสเกิดที่เกาะที่เข้าได้" (unlocked) อีกชั้น:
        --     บอสบน Starter/Jungle เกิดได้ก็จริง แต่ยังไม่คุ้มที่จะทิ้งฟาร์มไปตี
        --   nil = ปิดข้อจำกัด (ล่าบอสได้ทุกเกาะที่ปลดแล้ว)
        MinIsland = "island_desert",
    },

    -- ── LOW MODE ────────────────────────────────────────────────────────
    --   "ปิด Render3D" = ซ่อนทุกชิ้นที่ถูกวาด (BasePart/Decal/Particle/Beam/Texture)
    --   แล้วครอบหน้าจอด้วยกรอบสีดำ เหลือแต่ UI สถิติที่เราสร้าง
    -- ⚠ โค้ดยังทำงานครบตอน LowMode เพราะ Transparency เป็นเรื่องของภาพอย่างเดียว
    --   workspace:Raycast ยังชนชิ้นที่โปร่งใสเสมอ -> หาน้ำ/เล็ง/ตีบอส ไม่พัง
    -- ⚠ กด N อีกครั้งเพื่อคืนค่าเดิมทุกชิ้น (เก็บต้นฉบับไว้ตอนซ่อน)
    LowMode = {
        Enabled    = false,     -- เปิดเป็นค่าพื้นฐาน = ปิด Render3D ตั้งแต่แรก
        ToggleKey  = Enum.KeyCode.N,
        StartOn    = false,     -- true = เริ่มที่ปิดไว้ (ผู้ใช้กด N เพื่อดูภาพปกติ)
        BlackCover = false,     -- กรอบดำคลุมเต็มจอ (ไม่งั้นพื้นหลังเกมจะออกเป็นสีขาว)
        FogBlack   = false,     -- หมอกดำ กันสิ่งที่หลุดจากการไล่ซ่อนขึ้นมาเป็นสีขาว
        ShowStats  = false,     -- แสดง UI สถิติรวมตอน LowMode เปิด
        LogoAsset  = "rbxassetid://121541221566629",
        AuraMin    = "Legendary",  -- นับ Aura ตั้งแต่ระดับนี้ขึ้นไป
        Poll       = 2,        -- รีเฟรชข้อความสถิติทุก N วินาที
        -- ⚠ false = ไม่พิมพ์อะไรของ LowMode ลงคอนโซลเลย (ผู้ใชาสั่ง 2026-10-15)
        --   ปิดไว้เป็นค่าปกติ เพราะการวัดขนาดจอต้องเรียก lowApplyScale ทุกครั้งที่รีเฟรช
        --   = ถ้าพิมพ์ทุกครั้งจะล้นคอนโซลจนมองไม่เห็นอะไรอื่น
        --   true  = คืนการพิมพ์สถานะ (ใช้ตอนแผงดูผิด) และเรียกเองได้ที่ _G.lowDiag()
        Debug      = false,
    },

    -- ── WATCHDOG ──────────────────────────────────────────────────────────
    --   เช็ค 2 ระดับ: บูตค้าง / เดินค้าง (ยก pattern จาก 99 Nights MainScript.lua:20-38)
    -- ⚠ ต้อง > เวลาที่ยาวที่สุดที่หลักเดินบล็อกอยู่ เช่น เดินทางข้ามเกาะด้วย tween
    -- ⚠ BootTimeout / StallTimeout นับเฉพาะเวลาที่ "ไม่ได้กำลังว่ายข้ามเกาะ"
    --   เพราะข้ามเกาะหนึ่งครั้ง = 3577 studs / TweenSpeed 29 = 123 วินาที
    --   และ retry ได้อีก TweenMaxTry(20) x 3 เฟส รวมแล้วเกิน 180 วินาทีทุกครั้ง
    --   ถ้านับรวม -> watchdog สั่ง Teleport กลางทางทุกครั้งที่ข้ามเกาะ (เคยเกิดจริง)
    Watchdog = {
        Enabled      = true,
        BootTimeout  = 90,    -- วินาทีที่ "ไม่ว่ายข้ามเกาะ" แล้วบูตยังไม่จบ = ค้าง
        StallTimeout = 60,    -- วินาทีที่ "ไม่ว่ายข้ามเกาะ" แล้ว S.beat ไม่ขยับ = ตาย
        MaxBlockTimeout = 600,-- วินาทีที่บล็อกติดกันโดยไม่ปล่อยเลย = ค้างแน่ (เพดานแข็ง)
        OnFail       = "teleport",  -- "teleport" = TP กลับแมพเดิม · "warn" = เตือนอย่างเดียว
        MaxBootRetry = 3,     -- บูตค้าง = ลอง "รันใหม่" กี่ครั้งก่อนค่อย TP
        MaxRetry     = 3,     -- ครั้งที่ยอมเตือนซ้ำก่อนเลิก (กัน log รก)
        -- ⚠ ห้าม Teleport เด็ดขาด (ผู้ใชาสั่ง 2026-10-16)
        --   เดิม stall/blocked -> TeleportService:Teleport ทิ้งทุกอย่างทิ้ง
        --   ทั้งที่สคริปต์แค่ค้างชั่วคราว (กำลังตกบอส / tween ค้าง / รอเงิน)
        --   TP = เสียทั้งรอบตก ปลาในกระเป๋า และเวลาที่ฟาร์มมา
        --   ตอนนี้ทุกกรณีแค่เตือนแล้วตั้งนาฬิกาใหม่ ให้หลักเดินเดินต่อเอง
        NeverTeleport = true,
    },

    -- ── SELL — ขายก่อนทำงานที่ต้องใช้เงิน ─────────────────────────────────
    -- ⚠ เดิมทุกจุดที่เงินไม่พอปล่อยให้ฟาร์มต่อที่จุดฟาร์ม
    --   = ต้องรอกระเป๋าเต็มค่อยขาย ทั้งที่ในกระเป๋ามีเงินพออยู่แล้ว
    --   เปิดไว้ = พอเงินในมือไม่พอ แต่รวมกับมูลค่าในกระเป๋าแล้วพอ
    --   -> สร้างขั้นตอน "ขายก่อน" แล้วขายเสร็จเดินแผนต่อในรอบเดียวกัน
    Sell = {
        OnDemand = true,
        -- พิมพ์ค่าที่คำนวณได้ตอนตัดสินใจขาย (เปิด/ปิดได้ถ้าคอนโซลรก)
        Log = false,
    },

    -- ── FIGHT — แยก "ตกนาน" ออกจาก "หลักเดินค้าง" ──────────────────────────
    -- ⚠ watchdog นับ stall จาก S.beat ที่นิ่ง แต่ reelingLoop ไม่เคยตั้งธง busy
    --   ผลคือบอสที่ใช้เวลานานโดยการออกแบบ (2 เฟส + ฮีล) ถูก TP ทั้งที่ไม่ได้พัง
    -- ⚠ หลักคิด: ตัดสินจาก "เซิร์ฟยังยิง HP มาไหม" ไม่ใช่จากเวลาที่ผ่านไป
    --   HP ยังลด = รอบตกยังได้ผล = ไม่ค้าง (ตกนานเท่าไหร่ก็ไม่ต้องโดน TP)
    --   HP นิ่งเกิน HPSilence = เกมจบรอบแล้ว แต่เรายังวนไม่ออก = อ่านสถานะจริงแล้วออก
    Fight = {
        -- เซิร์ฟเงียบไปกี่วินาทีถึงถือว่า "รอบตกจบแล้ว" ให้ reelingLoop ออก
        -- ⚠ ต้องมากกว่าช่วงเงียบที่ยาวที่สุดของเกม มิฉะนั้นจะออกกลางบอสเฟส 2
        --   บอสเฟส 2 = PhaseIntermissSec 2 + StunWindUpSec 1.2 + HealChannelSec 1.5
        --   = ~4.7 วินาที -> 12 มีเผื่อเหลือเกือบสามเท่า
        HPSilence  = 20,
        -- อ่านสถานะจริงจากเกมทุก N วินาทีระหว่างตก (อ่านตรง ๆ ไม่ต้องรอ packet)
        StatePoll  = 1,
    },

    -- ── HORST ──────────────────────────────────────────────────────────
    --   รายงานสถานะตัวละครไปที่บอร์ด Horst + ชีท Google
    -- ⚠ ค่าเริ่มต้นคือค่าบรรทัดนี้ ถ้าตั้ง _G.Config.Horst จะทับ (อ่านสดทุกครั้งที่ใช้)
    --   ไม่มีการส่ง DONE เด็ดขาด — ไม่มี Horst_AccountChangeDone ในสคริปต์นี้
    Horst = {
        Enabled    = false,
        Source     = "https://raw.githubusercontent.com/HorstSpaceX/last_update/main/on_loaded.lua",
        MinInterval= 30,       -- วินาที/ครั้ง กันโดน rate limit (เหมือน 99 Nights)
        SendSheet  = true,     -- ส่งชีทด้วย (arg ที่ 2 ของ Horst_SetDescription)
        AuraList   = 3,        -- ส่งชื่อ Aura ระดับสูงสุดกี่ตัวใน Description
        RodList    = 3,        -- ส่งชื่อเบ็ดกี่ตัวใน Description (ที่เหลือรวมเป็น +N)
    },

    -- ── DAILY QUEST ─────────────────────────────────────────────────────
    -- ⚠ ข้อสำคัญที่สุด: เควสต์รายวัน "ไม่" ล็อคกับเกาะที่กดรับ
    --   DailyQuestUtil.PickIsland (DailyQuestUtil.lua:207) สุ่มจากทุกเกาะที่ปลดแล้ว
    --   70% = เกาะ order สูงสุด · 30% = เกาะรองสูงสุด แล้วผูก IslandId ไว้กับใบนั้น
    --   = ต้องไปตกที่ IslandId ที่เกมเขียนมา ห้ามเดาเกาะเอง
    --
    -- ⚠ รับได้ 20 ใบ/วัน (Deck Easy 10 / Medium 5 / Hard 5) รีเซ็ตทุก 86400 วิ
    --   และ "ยกเลิก" = กินโควตาทิ้ง + ตก FullClearBonus (25 gem) ด้วย
    --   -> สคริปต์นี้ไม่มี action ยกเลิกเด็ดขาด
    --
    -- ⚠ รับไม่ได้ถ้า Quest.Current.Id ~= "" (เควสต์ปกติค้างอยู่)
    Daily = {
        Enabled = true,
        -- เริ่มเดลี่หลังปลดเกาะนี้แล้ว (ผู้ใช้สั่ง 2026-10-20: เดิมเริ่มหลังได้ dread_fish_rod
        --   ให้ย้ายมาเริ่มหลังปลดเกาะ Lotus แทน)
        AfterIsland = "island_lotus",
        -- ⚠ ต้องคง AfterMissionDone ไว้: activeFarmIsland คืน farmIsland ของภารกิจก่อนเสมอ
        --   ถ้ามีภารกิจค้าง -> ถ้ารับเดลี่ตอน dread ยังไม่จบ บอทจะไม่ไปเกาะของเดลี่เลย
        --   = ใบเดลี่ค้างไม่มีความคืบหน้าและกินโควตา 20 ใบ/วันทิ้ง
        AfterMissionDone = true,
        -- เดินไปใกล้ NPC ก่อนกดรับถ้ามองเห็นตัวอยู่ (DailyQuestConfig.NpcRadius = 25)
        --   false = ยิง packet จากที่ยืนเลย (แบบเดียวกับเควสต์ปกติ)
        WalkToNpc  = true,
        NpcId       = "npc_daily_quest",
        -- อ่านค่าจาก DailyQuestConfig.NpcRadius ตอนรัน ค่านี้แค่ fallback
        NpcRadius   = 25,
    },

    -- ══════════════════════════════════════════════════════════════
    -- FORGE — Godslayer Rod V2 สาย Forge (ผู้ใช้สั่ง 2026-10-23)
    --
    -- ห่วงโซ่ (RodForgeConfig.Order) + ของที่ต้องใช้:
    --   godslayer_rod_v1   ปลา Rarities x5 (C/U/R/E/L อย่างละ 1 ตัวเบาสุด)  20,000,000 coin
    --   golden_beast_rod   Lotus Legendary x3                               200 gem
    --   diamond_dragon_rod Jungle Legendary x3 + Desert Legendary x3        200 gem + Mythical book 1
    --   godslayer_rod_v2   ปลา kind == "Boss" x5                            500 gem
    --   รวม 20,000,000 coin + 900 gem · ของที่ใช้ (เบ็ดก่อนหน้า/ปลา/book) ถูกกินหมด
    --
    -- ⚠ ลำดับที่ผู้ใช้สั่ง: book ก่อน -> ปลา -> gems -> เงิน (เงินฟาร์มหลังสุดเสมอ)
    --   forgeStep จึง "ไม่เคย" คืน action ไปฟาร์มเงิน — มันคืน nil ให้ mainLoop
    --   ไปฟาร์มที่ activeFarmIsland (เกาะสูงสุด = Lotus) ตามปกติ
    -- ⚠ band ดาเมจของเบ็ด 2-4 ในดัมป์คือ 110-120 ซึ่งต่ำกว่า Dread Fish Rod (52,897) มาก
    --   ตรวจที่หน้า Forge ในเกมก่อนจ่าย 20M — สคริปต์แค่ log ค่าที่คาดไว้ ไม่บล็อก
    Forge = {
        Enabled     = true,
        -- เริ่มสาย Forge ได้หลังปลดเกาะนี้ (NPC ตาชั่งอยู่ที่เกาะนี้)
        AfterIsland = "island_lotus",
        NpcId       = "npc_lotus_rod_forge",
        NpcIsland   = "island_lotus",
        -- งบสุ่มสกิลเพื่อหา Mythical book (ใช้เฉพาะกรณี "ไม่มีเล่มเลย")
        --   ⚠ ต้องจำกัด ไม่งั้นจะกินเงิน 20,000,000 ของ v1
        BookGachaBudget = 2000000,
        -- NPC ของ raid (ค่าจริงอ่านจาก RaidConfig.InteractiveIds ตอนรัน)
        TicketNpc   = "npc_raid_ticket",
        StartNpc    = "npc_raid_start",
        -- เพดานรอเข้า raid (กันค้างตอนแท่นไม่ครบคน)
        MaxRaidWait = 900,
    },
}

-- ══════════════════════════════════════════════════════════════════
-- ⚙ ตั้งค่าจากภายนอกได้ — _G.Config (ผู้ใชาสั่ง 2026-10-15)
--
--   วางบล็อกนี้ก่อนสคริปต์ หรือแก้/ตั้งใหม่ทีหลังก็ได้ ผลเหมือนกันทั้งสองแบบ:
--
--       _G.Config = {
--           SaveGemAfterDreadFishRod = false,   -- ไม่สุ่ม Aura เพิ่มหลังได้เบ็ด Dread Fish
--           Horst                = true,      -- เปิด/ปิด Horst API เพื่อดู Logs
--       }
--
--   ⚠ CONFIG เป็น local (บรรทัด 481) ภายนอกแตะตรง ๆ ไม่ได้
--     loadstring("CONFIG.Aura.SaveGemAfterDreadFishRod = true")() = ไม่มีผล
--     (สร้างตัวใหม่ใน global env ไม่ได้แตะตัวที่สคริปต์อ่านอยู่)
--   ⚠ ค่าที่ผู้ใช้แก้เองในไฟล์ยังถูกนับเสมอ
--     _G.Config ทับเฉพาะคีย์ที่ระบุ · ไม่มีคีย์นั้น = ใช้ค่าในไฟล์
--   ⚠ อ่านสดทุกครั้งที่ใช้ค่า ไม่ใช่ตอนบูตครั้งเดียว
--     = ตั้ง/แก้ _G.Config หลังสคริปต์ขึ้นแล้วก็มีผลทันที ไม่ต้องรีสตาร์ท
--     (ตัวอย่างเดียวกับเดิม: Enabled ของ Horst เคยอ่านครั้งเดียวตอนประกาศ
--      ตั้ง _G.Config.Horst ทีหลังไม่มีผลเลย)
--
--   ไม่เติมค่าเริ่มต้นลงในตารางให้ เพราะถ้าเติม ค่าเก่าจะค้างทับค่าที่แก้ในไฟล์รอบหน้า
_G.Config = type(_G.Config) == "table" and _G.Config or {}

--- อ่านค่าจาก _G.Config ถ้ามีคีย์นั้น · ไม่มี = ใช้ค่าในไฟล์ (fallback)
function cfgOn(key, fallback)
    local c = _G.Config
    if type(c) == "table" and c[key] ~= nil then return c[key] end
    return fallback
end

--- CONFIG เปิดให้แก้ค่าอื่น ๆ ได้จากภายนอก (เจาะจงเส้นทางในตาราง)
---   FM_set("Aura.ReserveGem", 50)
---   ⚠ เดินทางต้องไล่ถึง "ตัวก่อนสุดท้าย" เท่านั้น ถ้าไล่ถึงใบปล่ายสุดจะเจอค่าที่ยังไม่ใช่
---     ตาราง (เช่น false) แล้วหยุดกลางทางโดยไม่ได้เขียนค่าเลย
function FM_set(path, value)
    local keys = {}
    for key in tostring(path):gmatch("[^.]+") do keys[#keys + 1] = key end
    if #keys == 0 then return false end
    local node = CONFIG
    for i = 1, #keys - 1 do
        node = node[keys[i]]
        if type(node) ~= "table" then return false end
    end
    node[keys[#keys]] = value
    return true
end
_G.FishingMasterConfig = CONFIG
_G.FM_set = FM_set

-- ══════════════════════════════════════════════════════════════════
-- 0b) DAILY REWARD — รับของเข้าเล่นรายวัน (วันที่ 1-7)
--
-- รันต่อจากขั้น GUARD พอดี (บรรทัด ~340 installGuards/reportGuards ทำงานไปแล้ว)
-- และก่อนทุกอย่างของ CONFIG.Missions = ได้ของก่อนไปทำภารกิจ
-- ══════════════════════════════════════════════════════════════════
-- ⚠ กติกาจริงทั้งหมดอ่านจากของเกม ไม่ได้เดาเอง (DailyRewardUtil.compute_state):
--
--   DailyReward = { CycleStart, Claimed, LastClaim }   -- Template.lua:48 / schema.lua:190
--
--   now < LastClaim + 86400  -> { WaitingDay = Claimed+1 }        = ยังรับไม่ได้ (คูณเวลา)
--   Claimed >= 7 (คูณเวลาผ่าน) -> { ClaimableDay=1, Claimed=0, Expired=true }  = รอบใหม่
--   อื่น ๆ                     -> { ClaimableDay = Claimed+1 }    = รับได้วันนี้
--
--   -> รับได้ "วันละ 1 วัน" ข้ามวันไม่ได้ และ packet ไม่รับ argument วัน
--      (DailyRewardController.lua:27 — Packet("DailyReward/Claim") ไม่มีพารามิเตอร์)
--      = เปิดหน้าต่าง DailyReward เองก็ไม่ช่วยอะไร เพราะปุ่มวันถัดไปถูก disable
--
-- ของจริงทั้ง 7 วัน (Catalog/DailyRewards.lua — เหรียญกับ gem เท่ากันทุกวัน):
--   วัน 1 = 10,000  ·  วัน 2 = 20,000  ·  วัน 3 = 30,000  ·  วัน 4 = 40,000
--   วัน 5 = 50,000  ·  วัน 6 = 70,000  ·  วัน 7 = 100,000
--   (ยอดทั้งรอบ = 320,000 เหรียญ + 320 gem — อ่านสดจากแคตตาล็อก ไม่ hardcode ตัวเลขนี้)
-- ⚠ เรื่องนี้คนละตัวกับ "Daily Quest" (npc_daily_quest / DailyQuestUtil) = คนละระบบ
--   สคริปต์นี้ไม่แตะ เพราะผู้ใช้สั่งเฉพาะของเข้าเล่นวันที่ 1-7

local DailyRewardUtil = req(ReplicatedStorage.Shared.Lib.DailyRewardUtil, "DailyRewardUtil")
local DailyRewards    = req(ReplicatedStorage.Data.Catalog.DailyRewards, "DailyRewards")

--- อ่าน DailyReward จากข้อมูลผู้เล่นจริง — nil ถ้ายังไม่ replicate / schema เปลี่ยน
---   เช็ค type ทั้ง 2 ฟิลด์ที่ compute_state ใช้ เพราะ schema บังคับว่าต้องเป็น number
local function readDaily()
    local ok, d = pcall(function() return PlayerData:Fetch() end)
    if not ok or type(d) ~= "table" then return nil end
    local dr = d.DailyReward
    if type(dr) ~= "table" then return nil end
    if type(dr.Claimed) ~= "number" or type(dr.LastClaim) ~= "number" then return nil end
    return dr
end

--- สถานะปัจจุบัน = เรียกตรรกะของเกมเอง ไม่เขียนครอบทับ
---   ⚠ get_now() = math.floor(now(0)) คือนาฬิกาที่เซิร์ฟส่งมา ไม่ใช่ os.time ของเรา
---     ถ้าใช้ os.time จะเพี้ยนตามเวลาเครื่องผู้ใช้ แล้วคิดว่า "รับได้" ทั้งที่เซิร์ฟไม่ให้
local function dailyState(dr)
    if not (DailyRewardUtil and DailyRewardUtil.get_now and DailyRewardUtil.compute_state) then
        return nil
    end
    local okNow, nowSec = pcall(DailyRewardUtil.get_now)
    if not okNow or type(nowSec) ~= "number" then return nil end
    local ok, st = pcall(DailyRewardUtil.compute_state, dr, nowSec)
    if ok and type(st) == "table" then return st end
    return nil
end

--- ชื่อรางวัลของวันนั้นจากแคตตาล็อก — อ่านสด ไม่พิมพ์ตัวเลขที่เราพิมพ์เอง
local function dailyLabel(day)
    local rw = (DailyRewards and DailyRewards.GetByDay) and DailyRewards.GetByDay(day) or nil
    if type(rw) == "table" and type(rw.DisplayName) == "string" then return rw.DisplayName end
    return ("วันที่ %s"):format(tostring(day))
end

local function claimDailyReward()
    if not CONFIG.DailyReward then return end

    -- ข้อมูลผู้เล่นตอนสตาร์ทอาจยังไม่ replicate มา (เพิ่งเข้าเกม / เพิ่งวางสคริปต์)
    --   รอให้ DailyReward โผล่จริง แต่จำกัดเพดานไว้กันค้าง แล้วข้ามไปทำงานต่อ
    --   ⚠ 30 วินาทีคือ "เพดานกันค้าง" ไม่ใช่คำตอบว่าข้อมูลจะมาตอนนั้น
    --     ถ้ายังไม่มีจริง ๆ เราแค่ข้ามรอบนี้ ไม่ขวางสคริปต์ไว้
    local dr, t0 = nil, os.clock()
    while true do
        dr = readDaily()
        if dr then break end
        if os.clock() - t0 >= 30 then break end
        task.wait(0.5)
    end
    if not dr then
        logWarn("[Daily] อ่าน DailyReward ไม่ได้ — ข้ามรอบนี้ (ยังไม่ replicate หรือเกมเปลี่ยน schema)")
        return
    end

    local st = dailyState(dr)
    if not st then
        logWarn("[Daily] อ่าน DailyRewardUtil ไม่ได้ — ข้ามรอบนี้")
        return
    end

    -- ── ยังไม่ถึงเวลา: บอกว่ารอบหน้าได้วันไหน แล้วจบ ไม่ยิงให้เปลือง ──
    if not st.ClaimableDay then
        -- WaitingDay = nil เมื่อ Claimed >= 7 = จบรอบแล้ว รอบหน้าเริ่มวันที่ 1
        local nextDay = st.WaitingDay
        if not nextDay then
            nextDay = (dr.Claimed >= 7) and 1 or (dr.Claimed + 1)
        end
        return
    end

    local day  = st.ClaimableDay
    local label = dailyLabel(day)

    -- ⚠ controller ลงทะเบียนตอนเกมสตาร์ทแล้ว (Stardust Client.Run ไล่ require ทุก
    --   ModuleScript ในโฟลเดอร์ Controllers — Client.lua:82-94) ไม่ต้องเปิดหน้าต่างก่อน
    --   และเราไม่เปิดหน้าต่างเลย = ยิง packet ตรง ๆ ตามที่ปุ่มใน UI ทำ
    local ctl = (Client and Client.GetController) and Client.GetController("DailyRewardController") or nil
    if not (ctl and ctl.Claim) then
        logWarn("[Daily] ไม่มี DailyRewardController — ข้ามรอบนี้")
        return
    end

    -- ⚠ ไม่ส่ง argument: packet ไม่รับ (DailyRewardController.lua:27)
    --   server เป็นคนเลื่อน Claimed เอง เราบอกวันไม่ได้แม้จะอยากบอก
    local ok, res = pcall(function() return ctl.Claim:Fire() end)
    if not ok then
        logWarn(("[Daily] ยิง Claim error: %s — ข้ามรอบนี้"):format(tostring(res)))
        return
    end
    if not res then
        -- ⚠ ไม่ใช่แค่ false: Packet:Fire() คืน nil ตอน timeout ด้วย
        --   (Packet.lua:318-321 ส่ง ResponseTimeoutValue ซึ่งไม่เคยถูกตั้งให้เป็นอะไรเลย)
        --   เช็คแค่ == false จะพลาดเคสนี้แล้วไปตกไปที่ข้อความ "Claim ตอบว่าสำเร็จ" ทั้งที่ไม่สำเร็จ
        logWarn(("[Daily] เซิร์ฟปฏิเสธ/ไม่ตอบ Claim (res=%s · ตอนนี้รับไปแล้ว %d/7 วัน) — ไม่ยิงซ้ำ เดี๋ยวกินโควตาของวันหน้า")
            :format(tostring(res), dr.Claimed))
        return
    end

    -- ⚠ ยืนยันด้วยข้อมูลของเกม ไม่ใช่ "รอ x วินาทีแล้วคิดว่าสำเร็จ"
    --   หลังรับวันที่ 7 เกมจะรีเซ็ต Claimed เป็น 0 ด้วย = ตัวเลข "ลดลง" ก็ถือว่าสำเร็จ
    local before, after, t1 = dr.Claimed, nil, os.clock()
    while os.clock() - t1 < 5 do
        local d2 = readDaily()
        if d2 and d2.Claimed ~= before then after = d2.Claimed break end
        task.wait(0.25)
    end

    if after == nil then
        logWarn(("[Daily] Claim ตอบว่าสำเร็จ แต่ Claimed ยังเป็น %d — ข้ามไป ไม่ยิงซ้ำ"):format(before))
        return
    end
end

claimDailyReward()

local S = {
    running   = false,
    beat      = 0,          -- หลักเดินวนกี่รอบแล้ว = ดูว่ายังมีชีวิตอยู่ (watchdog อ่านตัวนี้)
    state     = "Idling",
    qteDir    = nil, qteExpireAt = 0,
    -- บันทึกผล QTE — ก่อนหน้านี้ไม่มีตัวนับเลย ทำให้บอกไม่ได้ว่าทำไม "กด WASD แล้วไม่เข้า"
    qtePrompt = 0,     -- ได้ FishQTEPrompt มากี่ครั้ง
    qteSent   = 0,     -- ยิง FishQTEResponse ออกไปจริงกี่ครั้ง
    qteHit    = 0,     -- server ตอบว่าถูก
    qteMiss   = 0,     -- server ตอบว่าผิด
    qteLate   = 0,     -- จะยิงแต่หน้าต่างปิดไปแล้ว = เสียจังหวะนั้นฟรี (เลยไม่ยิง)
    qteNoKey  = 0,     -- direction ที่ DirectionToKey ไม่มี = เกมไม่ให้กดอะไรเลย
    qteGen    = 0,      -- เลขรอบ QTE — กัน callback ที่หน่วงค้างยิงหลังเกมตัด prompt ทิ้งแล้ว
    stunnedUntil = 0,  -- FishBossStun = ช่วงที่เกมห้ามกดตี (เกมเรียกว่า u310)
    castAckDeadline = 0,
    castRetryAt = 0,        -- ถ้า server สั่ง "casting too fast" = หยุดยิงรัวก่อน
    standSpot    = nil,       -- Part จุดยืนที่สร้างเอง (nil = ไม่มีอยู่ตอนนี้)

    -- แผน (คิดขั้นถัดไปจาก state จริงทุกครั้ง ไม่เก็บลำดับขั้นไว้)
    -- ⚠ ไม่มี farmIsland ที่นี่แล้ว — เคยเขียนไว้แต่ไม่มีใครอ่าน
    --   เกาะที่กำลังฟาร์มอ่านจาก currentIslandId() สด ๆ ทุกครั้ง (สะท้อนการว่ายจริงได้)
    --   ถ้าเก็บไว้มันจะโกหก เพราะ goToFarmSpot อาจว่ายข้ามเกาะได้ในขั้นตอนเดียวกัน
    actionKey  = nil,       -- key ของ action ที่กำลังพยายามทำ (เปลี่ยน = เริ่มนับล้มเหลวใหม่)
    attempts   = 0,         -- ล้มเหลวกี่ครั่งติดกันสำหรับ actionKey นี้ (กันเตือนรัว)
    retryAt    = 0,         -- ก่อนเวลานี้ไม่ยิง action ซ้ำ (backoff หลัง server ปฏิเสธ)
    stopReported = false,   -- เตือนว่า "ครบแล้ว" ไปแล้วหรือยัง
    warnedStale  = false,   -- เตือน "มีสกิลค้างหลายเบ็ด" ไปแล้ว (กันท่วมทุก 5 วิตอน poll)
    warnedLevel  = {},       -- เตือน "เลเวลไม่ถึงเกาะนี้" ไปแล้วรายเกาะ (กันท่วมทุก 5 วิตอน poll)
    warnedNoSpot = {},       -- เตือน "เกาะนี้ยังไม่ได้ประกาศจุดฟาร์ม" ไปแล้วรายเกาะ
    warnedLockedSlot = nil,  -- เตือน "ช่องสกิลยังล็อกอยู่กี่ช่อง" ไปแล้ว (กันท่วมทุก 5 วิตอน poll)
    -- ⚠ ทะเบียน: นับจาก packet ที่เกมส่งมา ไม่ใช่นับเอง
    --   รอบก่อนไม่มีตัวนับเลย -> ล็อกบอกไม่ได้ว่าตกปลาได้จริงไหม
    casts       = 0,         -- เซิร์ฟรับการเหวี่ยงแล้วกี่ครั้ง (FishWaitingAck)
    catches     = 0,         -- จับได้กี่ตัว (FishCatchResult true)
    escapes     = 0,         -- ปลาหนีกี่ตัว (FishCatchResult false)
    skillFail   = 0,         -- EquipMoveset ล้มเหลวกี่ครั้ง (รวมทุกเหตุผล)
    skillBlock  = {},        -- [rodId][ลายเซ็นของสถานะตอนที่ล้ม] = true
                            --   ลองใหม่ได้ต่อเมื่อสถานะเกมเปลี่ยนจริง ไม่ใช่รอเวลา
    loadoutSig  = nil,       -- ลายเซ็นชุดอุปกรณ์ตอนที่ยิง packet รอบก่อน
    loadoutSkip = false,     -- รอบก่อนยิงแล้วแต่สถานะไม่ขยับ = รอบนี้ไม่ต้องยิงซ้ำ
    loadoutOk   = false,     -- ผลของ ensureBestLoadout รอบที่ยิงจริงล่าสุด
    -- ⚠ เครื่องมือที่ต้องเรียกข้ามฟังก์ชัน แต่ไฟล์นี้ชนเพดาน local 200 ตัวของ Lua แล้ว
    --   (วัดได้: แทรก local ทดลองแม้ตัวเดียว luac ก็ไม่ผ่าน) = แนบไว้ใน S แทน
    --   ⚠ ห้ามย้ายออกมาเป็น local ระดับบน ทั้งไฟล์จะ compile ไม่ผ่านทันที
    tools = {              -- .loadoutSignature / .whereSkillLives / .catch / .summary
        -- ⚠ เครื่องมือที่ข้ามฟังก์ชันอยู่ใน S ไม่ใช่ local ระดับไฟล์ เพราะไฟล์นี้ชนเพดาน
        --   200 local แล้ว (เพิ่มตัวเดียว luac ก็ไม่ผ่าน) — ดู S.tools.pin()
    },
    catchSeen   = {},        -- uid ของปลาที่พิมพ์ไปแล้ว (กันพิมพ์ซ้ำตัวเดิม)
    catchSeenCount = 0,      -- จำนวนปลาในกระเป๋าตอนพิมพ์ครั้งก่อน (กระเป๋าถูกขาย = เคลียร์ตาราง)
  -- เตือน "ช่องสกิลยังล็อกอยู่กี่ช่อง" ไปแล้ว (กันท่วมทุก 5 วิตอน poll)
    lockedUids = {},         -- uid ที่ "เราสั่งล็อคเอง" รอบนี้ ใช้กันกด ToggleLock ซ้ำตัวเดิม
                            --   ToggleLock เป็นสวิตช์ ไม่ใช่ set — ถ้ารอถัดไปยังไม่เห็น
                            --   ผลจาก replicate แล้วกดซ้ำ มันจะ "ปลด" ปลาตัวเดิมทิ้ง
                            --   แล้วรอบขายก็จะกินปลาเควสต์ไป (ปลดล็อกใน releaseQuestFish)
    -- ⚠ data.SpawnIsland replicate กลับมาจริงหรือเปล่า — เรียนรู้จากการเดินทางจริง
    --   เป็น false จนกว่าจะเห็นค่าเปลี่ยนตามเกาะที่เราเพิ่งตั้งสำเร็จสักครั้ง
    --   ถ้าไม่มี flag นี้ แล้วเซิร์ฟไม่ส่งค่านี้กลับ จะได้ wrongSpawn = จริงตลอด
    --   = สั่งว่ายวนไม่จบและไม่มีวันได้ตกปลา (ดู travelToIsland ที่ตั้ง flag นี้)
    spawnReplicates = false,
    lastSkillMsg = nil,       -- ข้อความสถานะสกิลที่พิมพ์ไปล่าสุด (พิมพ์ตอนเปลี่ยนเท่านั้น)
    lastUnitMsg  = nil,       -- ข้อความสถานะ Unit ที่พิมพ์ไปล่าสุด (พิมพ์ตอนเปลี่ยนเท่านั้น)
    gemHoldSaid  = false,     -- พิมพ์ "เริ่มเก็บ gem" ไปแล้วหรือยัง (กันพิมพ์ซ้ำทุกรอบ)
    lotusGemWarned = false,   -- พิมพ์ "gems ไม่พอปลด Lotus" ไปแล้วหรือยัง
    lotusGemSaid   = false,   -- พิมพ์ "กัน gems 200 เพราะได้ Luck แล้ว" ไปแล้วหรือยัง
    lotusSwapFail  = 0,       -- สลับไปเอา Dread rod ล้มเหลวติดกันกี่ครั้ง (กันวน Cancel/Accept)
    lotusDetour    = nil,     -- "daily" = ยกเลิก Lotus ชั่วคราวไปทำเดลี่หา gems (nil = ปกติ)
    lotusDetourAt  = 0,       -- nowReal() ตอนเริ่ม detour (ใช้ตัดเวลาค้าง)
    lotusDetourEnd = 0,       -- nowReal() ตอนกลับมาแล้ว (กัน detour ซ้ำรัว ๆ)
    unitEquipped = nil,       -- uid ของ Unit ที่เราสั่งใส่ล่าสุด (กันพิมพ์ซ้ำทุกรอบ)
    unitPulled   = 0,         -- สุ่ม Unit ไปแล้วกี่ครั้งในสคริปต์นี้
    traveling = false,      -- กำลังย้ายเกาะ/ย้ายจุด — ห้ามเหวี่ยงระหว่างนั้น
    moving     = false,     -- กำลัง tween ไปจุดขาย/จุดฟาร์ม

    -- skills
    skillWindowUntil = 0,
    slotReadyAt = {},
    -- ช่องไหนที่ค่า slotReadyAt มาจาก server (true) vs จากการเดาของเราเอง (false)
    --   ใช้ตอนขึ้นรอบตกปลาใหม่ เพื่อล้างเฉพาะฝั่งเรา ไม่ไปทับ cooldown ที่ server เพิ่งบอก
    slotServerAt = {},
    lastSkillAt = 0,
    skillCooldownHooked = false,

    noclipConn = nil,
    antiSinkConn = nil,
    -- ยกแรงโน้มถ่วงแทนการตรึง (VectorForce) — ดู S.tools.setNoGravity()
    pinned   = nil,      -- { hrp = <HumanoidRootPart ที่เรายกแรงให้> } · nil = ไม่ได้ยกแรงอยู่
    grav     = nil,      -- <VectorForce> ที่แนบกับ HRP · nil = ไม่ได้ยกแรงโน้มถ่วง
    antiSinkBase = nil,  -- Workspace.Gravity ตอนที่ผูกแรงครั้งแรก (ตาข่าย ถ้าเพี้ยนให้รู้)
    arriveAt = nil,      -- จุดที่ "มาถึงจริง" ครั้งล่าสุด (ตัวเลข = ตำแหน่งจริงที่อ่านได้
                         --   ไม่ใช่ค่าที่เดา) ใช้ตรวจว่าตอนนี้ยังอยู่ที่นั้นหรือยัง

    -- Aura
    auraAt       = 0,      -- รอบตรวจ aura ถัดไป
    auraPulled   = 0,      -- สุ่มไปกี่ครั้งในสคริปต์นี้
    auraPruned   = 0,      -- ทิ้งไปกี่ตัว
    -- Boss
    bossHolding  = false,  -- true = กำลังยืนตีบอสอยู่ (บล็อก runStep / goToFarmSpot)
    bossRegion   = nil,    -- part ของเขตบอสที่กำลังตี
    bossSeenAt   = 0,      -- รอบที่เพิ่งเจอบอส
    bossSkip     = nil,    -- เขตบอสที่ข้าม (ยังไม่ปลด/อ่านเกาะไม่ได้) กันพิมพ์ซ้ำ
    -- ⚠ ตกบอสไม่ผ่านติดกันกี่ครั้ง (นับจาก FishReset กลุ่ม Cast failed)
    bossFail     = 0,
    -- true = ตกจากกลางน้ำไม่ได้แล้ว ให้ย้ายไปยืนพื้นดินรอบเขต
    bossBackup   = false,
    -- กันย้ายซ้ำทุกรอบของ mainLoop (ย้ายครั้งเดียวพอ)
    bossBackedUp = false,
    -- nowReal() ที่ว่ายกลับเข้าเขตบอสครั้งล่าสุด = กันยิงซ้ำทุก Boss.Poll วิ
    bossDriftAt = 0,
    -- ══ FIGHT HEARTBEAT — ตัวชี้ว่า "รอบตกยังได้ผลอยู่ไหม" ══════════════════
    --   อ่านจาก packet ของเซิร์ฟตรง ๆ ไม่ใช่เดา ไม่นับเวลาเอง
    hpNow       = 0,        -- HP ปลาตอนนี้ (ล่าสุดที่เซิร์ฟยิงมา)
    hpMax       = 0,        -- HP เต็มของปลารอบนี้
    hpAt        = 0,        -- nowReal() ที่ HP ขยับล่าสุด = หัวใจของรอบตก
    fighting    = false,    -- true = reelingLoop กำลังวนอยู่
    fightExit   = nil,      -- เหตุผลที่ออกจากรอบตกล่าสุด (ใช้พิมพ์ตอน watchdog ตัดสิน stall)
    -- Daily
    dqGachaPulls = 0,      -- สุ่มสกิลไปแล้วกี่ครั้งในรอบเควสต์ skill_gacha นี้
    dqGachaAt    = nil,    -- ค่า Progress ครั้งก่อนหน้า (ใช้รู้ว่าเซิร์ฟขยับโปรเกรสไหม)
    dqQuestId    = nil,    -- ตัวระบุเควสต์ใบที่กำลังทำ เพื่อรีเซ็ตตัวนับเมื่อเปลี่ยนใบ
    dqWarned     = false,  -- เตือน "อ่าน data.DailyQuest ไม่ได้" ไปแล้วหรือยัง
    dqSaidQuest  = nil,    -- เควสต์ใบที่พิมพ์ "ไปตกที่..." ไปแล้ว (กันพิมพ์ทุกรอบ)
    statsAt      = 0,      -- รอบรีเฟรช UI สถิติถัดไป
    statsSig     = nil,    -- ข้อความสถิติรอบก่อน (เทียบแล้วเหมือนเดิมไม่ต้องวาดใหม่)
    horstAt      = 0,      -- รอบส่ง Horst ถัดไป (0 = ยังไม่เคยส่ง)
    dqSaidDone   = false,  -- พิมพ์ "ทำเควสต์วันนี้ครบแล้ว" ไปแล้วหรือยัง
    bossPollAt   = 0,      -- รอบตรวจบอสถัดไป (ไม่ต้องสแกนทุกเฟรมของ mainLoop)

    -- ══ FORGE / RAID (Godslayer Rod V2 สาย Forge) ══════════════════════
    forgeBook    = nil,    -- skillId ของ Mythical book ที่ "จอง" ไว้ให้ forge
                           --   ⚠ ห้าม tryEquipAllSkills ใส่กลับลงเบ็ด ไม่งั้น GetStatus.bookId = nil ตลอด
    forgeWarned  = {},     -- เตือนครั้งเดียวต่อเรื่อง (["band:<rodId>"] / ["book"])
    forgeGemSaid = false,  -- พิมพ์ "กัน gems ไว้ให้สาย Forge" ไปแล้วหรือยัง
    forgeSpent   = 0,      -- coin ที่ใช้สุ่มสกิลหาสกิล Mythical ไปแล้ว (เทียบกับ BookGachaBudget)
    raidActive   = false,  -- true = อยู่ในวง raid (mainLoop ต้องไม่ขาย/ไม่เดินแผน/ไม่ตีบอส)
    raidSlot     = nil,    -- เลข slot ของ raid ที่ได้ (จาก RaidController._slot)
    raidPollAt   = 0,      -- รอบตรวจ raid ถัดไป
    raidJoinAt   = 0,      -- nowReal() ตอนยิง JoinPad (ใช้เป็นเพดานรอ)
    raidStartAt  = 0,      -- nowReal() ที่ยิง StartIsland ล่าสุด (กันยิงรัว)
    raidClaimAt  = 0,      -- nowReal() ที่ยิง Claim ล่าสุด
    raidReloc    = 0,      -- ขยับที่ยืนใน raid ไปกี่ครั้งแล้ว (RaidSpotTaken/RaidNoSpot)
    raidIslandIdx = 1,     -- เกาะที่กำลังตกใน raid (1..6) — raidCastTarget ใช้หาทิศสำรอง
}

-- ══════════════════════════════════════════════════
-- 3) อ่าน "ลำดับเกาะ" และ "เบ็ดดีที่สุดของเกาะ" จากข้อมูลของเกม
--    ทุกอย่างด้านล่างคำนวณจาก state จริงทุกครั้งที่ถูกเรียก
--    ไม่มีตารางขั้นตอนตายตัวเหลือให้พันธน์กับเงื่อนไขที่เปลี่ยนกลางคัน
-- ══════════════════════════════════════════════════
local ISLAND_CHAIN   -- cache: รายการเกาะเรียงตาม .order

--- รายการเกาะทั้งหมดเรียงจากเลข 1 ไป N — อ่าน order จาก Catalog ของเกมตรงๆ
---   Catalog.Island.GetAll() คืนมาเรียงตาม .order ให้แล้ว (Catalog.lua:90-101)
---   จึงไม่ต้อง hardcode ลำดับเกาะไว้ในสคริปต์เลย
local function islandChain()
    if ISLAND_CHAIN then return ISLAND_CHAIN end
    local list = {}
    if Catalog and Catalog.Island and Catalog.Island.GetAll then
        local ok, all = pcall(function() return Catalog.Island.GetAll() end)
        if ok and type(all) == "table" then
            for _, entry in ipairs(all) do
                if type(entry) == "table" and type(entry.id) == "string" then
                    list[#list + 1] = entry
                end
            end
        end
    end
    if #list == 0 then
        -- อ่าน Catalog ไม่ได้ (ยังโหลดไม่เสร็จ) -> ใช้ IslandConfig เรียงตามราคาปลดล็อก
        -- ซึ่งให้ลำดับเดียวกันทุกประการ (0 < 40k < 180k < 900k < 4M < 15M)
        local ids = {}
        for id in pairs(IslandConfig or {}) do ids[#ids + 1] = id end
        table.sort(ids, function(a, b)
            return (IslandConfig[a].unlockCost or 0) < (IslandConfig[b].unlockCost or 0)
        end)
        for i, id in ipairs(ids) do list[i] = { id = id, order = i } end
    end
    ISLAND_CHAIN = list
    return list
end

--- ค่า attackDamage ของเบ็ด อ่านจริงจาก Catalog.Rod
---   คืน 0 ถ้า Catalog ไม่รู้จักเบ็ดนี้ (ของใหม่จากเกมอัปเดต) — ไม่ throw
---   ⚠ รวมจาก stat ทุกอันที่ชื่อ attackDamage ไม่ใช่แค่ตัวแรก กันกรณีเกมแตก stat เป็นหลายบรรทัด
---
--- ⚠ เบ็ดจากสาย Forge มี stats = {} ในแคตตาล็อก (Data/Catalog/Rod.lua:140-183)
---   ดาเมจจริงอยู่ใน data.Rods[id].ForgedStats ที่เซิร์ฟ roll ให้
---   ถ้าไม่อ่านส่วนนี้ด้วย เบ็ด forge จะได้ atk = 0 เสมอ -> findBestRod ไม่มีทางเลือกมันได้เลย
---   ใช้ RodModifiers.GetForgedStats ของเกมเองเป็นตัวตรวจ (ไม่เดา schema)
---   data เป็น optional: call site เดิม (bestRodForIsland) ยังเรียกแบบเดิมได้
local function rodAtk(rodId, data)
    if not rodId then return 0 end
    local sum = 0
    if Catalog and Catalog.Rod and Catalog.Rod.GetById then
        local meta = nil
        pcall(function() meta = Catalog.Rod.GetById(rodId) end)
        for _, s in ipairs((type(meta) == "table" and meta.stats) or {}) do
            if type(s) == "table" and s.stat == "attackDamage" then
                sum = sum + (tonumber(s.value) or 0)
            end
        end
    end
    -- ดาเมจที่ forge ได้ (เฉพาะเบ็ดที่ผ่านการ forge แล้ว)
    if RodModifiers and type(data) == "table" and type(data.Rods) == "table" then
        local ok, fs = pcall(function() return RodModifiers.GetForgedStats(rodId, data.Rods[rodId]) end)
        if ok and type(fs) == "table" then
            sum = sum + (tonumber(fs.attackDamage) or 0)
        end
    end
    return sum
end

--- เบ็ดที่ "ดีที่สุด" ของเกาะนี้ = attackDamage สูงสุด ในกลุ่มเบ็ดที่ร้านผูกกับเกาะนี้
---   อ่าน stats จริงจาก Catalog.Rod (ไม่เดาราคา ไม่เดาลำดับในร้าน)
--- คืน nil ถ้าเกาะนี้ไม่มีเบ็ดขายด้วย Coin เลย (เช่น volcano / fossil) = ไม่ต้องซื้ออะไร
local function bestRodForIsland(islandId)
    if not islandId then return nil end
    local bestId, bestAtk = nil, -math.huge
    for rodId, cfg in pairs(RodShopConfig or {}) do
        if type(cfg) == "table" and cfg.islandId == islandId and type(cfg.price) == "number" then
            local atk = rodAtk(rodId)
            -- เบ็ดที่ Catalog ไม่รู้จัก (atk = 0) ยังนับเข้ามาแต่ไม่มีทางชนะตัวที่มีสถิติจริง
            if atk > bestAtk then bestAtk, bestId = atk, rodId end
        end
    end
    return bestId
end

--- ══════════════════════════════════════════════════════════════
--- "เกาะปลดแล้วแต่เบ็ดยังไม่มี" = เบ็ดที่ดีที่สุดของเกาะนั้น (ดาเมจสูงสุด) เท่านั้น
---
--- ตารางจริงจากเกม (RodShopConfig.lua:2-10 + Catalog/Rod.lua) เรียงตามราคา
---
---   island_starter : wooden_rod           0  atk    217  slot 2     ฟรี
---                   stone_rod        3,000  atk    289  slot 4     ข้าม
---                   iron_rod        12,000  atk    542  slot 4     <- เป้าของ Starter
---   island_jungle  : golden_rod      35,000  atk    722  slot 4     ข้าม
---                   steel_rod       90,000  atk  1,354  slot 4     <- เป้าของ Jungle
---   island_desert  : golden_steel_rod 220,000  atk 1,806  slot 4     ข้าม
---                   diamond_steel_rod 520,000 atk 3,385  slot 4     <- เป้าของ Desert
---   island_snow    : taoist_rod    1,300,000 atk 4,514  slot 4     ข้าม
---                   legacy_rod    3,000,000 atk 8,464  slot 4     <- เป้าของ Snow
---   island_volcano : — ไม่มีเบ็ดในร้าน (ได้จากเควสต์เท่านั้น)
---   island_fossil  : — ไม่มีเบ็ดในร้าน (ได้จากเควสต์เท่านั้น)
---
--- สังเกต: ทุกชั้นราคา ~10 เท่ของชั้นก่อนหน้า และทุกเบ็ดที่ราคา >= 90,000
---   ปลดช่องสกิล 4 ช่องเท่ากันหมด -> ซื้อเบ็ดที่แพงกว่าเสมอคุ้มกว่าในแง่ atk
---
--- ⚠ ระวังสับสน: heaven_piercer_turtle_rod / zen_staff_rod อยู่ใน Catalog
---   แต่ไม่มีใน RodShopConfig และไม่มีเควสต์ใน QuestConfig = ยังไม่มีทางได้มา
---   สคริปต์นี้จึงไม่มีทางซื้อ/รอสองอันนี้ และไม่ควร hardcode เป็นเป้าหมาย
--- ══════════════════════════════════════════════════════════════

--- เลเวลผู้เล่น — เกาะหลายเกาะมี requiredLevel (jungle 10 / desert 20)
---   data.Level เป็น field จริงบน profile (PlayerData/Template.lua:6)
---   ถ้าอ่านไม่ได้/เป็น nil ค่อย fallback ไปคำนวณจาก Exp ด้วยสูตรของเกม
--- ⚠ ใช้เป็น "เช็คล่วงหน้า" เท่านั้น ถ้าค่าที่ได้เป็น 0/1 (data ยังไม่มา)
---   ให้ถือว่า "ไม่รู้" = ไม่ขวาง เพราะ server เป็นคนตัดสินจริงอยู่แล้ว
local function playerLevel(data)
    local lv = tonumber(data and data.Level)
    if lv and lv >= 1 then return lv end
    if getLevel and getLevel.getLevel then
        local ok, v = pcall(function() return getLevel.getLevel((data and data.Exp) or 0) end)
        if ok and type(v) == "number" and v >= 1 then return v end
    end
    return nil      -- อ่านไม่ได้ = ไม่ใช้เป็นเงื่อนไขบล็อก
end

local ReelSeq, SEQ_MAX, GachaRequestId = 0, 65535, 0

local function root()
    local char = LocalPlayer and LocalPlayer.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
end

local function getFishingController()
    return Client and Client.GetController("FishingController") or nil
end

--- อ่าน state จริงของเกม (FishingController:GetState()) แล้ว sync กับ S.state
--- สำคัญ: เกมอาจ reset ตัวเอง (ไป Idling) ตอนเรา S.state ยังค้างเป็น Caught/Escaped อยู่
--- ถ้าเรากด cast ตอนนั้น เกมจะตอบ "Finish what you are doing first" (StateBusy/SessionActive)
local function syncState()
    local fc = getFishingController()
    if not fc then return end
    local ok, st = pcall(function() return fc:GetState() end)
    if ok and type(st) == "string" and st ~= "" then
        S.state = st
    end
end

-- ══════════════════════════════════════════════════
-- FIGHT HEARTBEAT — แยก "ตกนาน" ออกจาก "หลักเดินค้าง"
-- ──────────────────────────────────────────────────
-- ⚠ ทุกอย่างในส่วนนี้อ่านจาก packet ของเซิร์ฟตรง ๆ ไม่ใช่เดา ไม่นับเวลาเอง
--   FishReelHPUpdate(hp, maxHP, damage, zone) — เซิร์ฟยิงทุกครั้งที่ HP เปลี่ยน
--     (FishingPackets.lua:23 · FishingController.lua:2754-2761)
--   FishReelPhaseHP(hp, maxHP) — บอสเข้าเฟส 2 = ได้ HP เต็มชุดใหม่
--     (FishingPackets.lua:44 · FishingController.lua:3045-3053)
--
--   ⚠ เดิมสคริปต์ไม่ subscribe สองตัวนี้เลย และทิ้ง hp/maxHP ที่ได้จาก
--     FishFirstPullStart / FishReelStartAck ทิ้งทั้งคู่
--     = ทั้งสคริปต์และ watchdog ไม่มีทางรู้ว่าปลาหายไปแค่ไหน
--     ผลคือ "ตกนาน" กับ "ค้าง" มีหน้าตาเหมือนกันเป๊ะ จนแยกไม่ออก
--     (เคยเห็นจริง: [Watchdog] หลักเดินไม่ขยับ 60s -> TP ทั้งที่น่าจะเป็นบอส)

--- จด HP ล่าสุดที่เซิร์ฟยิงมา + ปักเวลาที่ขยับล่าสุด
function noteFightHP(hp, maxHP)
    local h = tonumber(hp)
    if not h then return end
    S.hpNow = h
    S.hpMax = tonumber(maxHP) or S.hpMax or 0
    S.hpAt  = nowReal()          -- ⚠ nowReal ไม่ใช่ os.clock (ดูหัวข้อ WATCHDOG)
end

--- ล้างหัวใจการตก — เรียกตอนรอบตกจบจริง (จับได้ / หลุด / server reset)
function clearFightHP()
    S.hpNow, S.hpMax, S.hpAt = 0, 0, 0
end

--- "รอบตกยังมีชีวิตอยู่ไหม" = เซิร์ฟยังยิง HP มาใน HPSilence วินาทีที่ผ่านมา
---   ใช้เป็นธง busy ของ watchdog **แทนการเดา**
---     ตกนานจริง (ปลาดุ/บอส 2 เฟส) -> HP ลดเรื่อย ๆ -> true  = watchdog ไม่ตัดสิน
---     ค้างจริง (packet หลุด)     -> ไม่มี HP เกิน HPSilence -> false = นับ stall ตามปกติ
function fightAlive()
    if not S.fighting then return false end
    if S.hpAt <= 0 then return false end          -- ยังไม่เคยได้ HP = ยังตัดสินไม่ได้
    -- เผื่อไว้ 2 เท่า เพราะ reelingLoop ใช้ HPSilence ตัดสินก่อนออกอยู่แล้ว
    return (nowReal() - S.hpAt) <= ((CONFIG.Fight.HPSilence or 12) * 2)
end

--- อ่านสถานะจริงจากเกมตรง ๆ (ไม่รอ packet) — คืน string หรือ nil
local function realFishingState()
    local fc = getFishingController()
    if not fc then return nil end
    local ok, st = pcall(function() return fc:GetState() end)
    if ok and type(st) == "string" and st ~= "" then return st end
    return nil
end

--- สถานะของเกมที่แปลว่า "ยังอยู่ในรอบตกปลาจริง"
---   FishingEnums.lua:24-30 GroupOf — มีแค่ FirstPull กับ Reeling ที่เป็น InCombat
---   (Holding / Throwing / Waiting อยู่กลุ่ม InCasting = ยังไม่ได้ต่อสู้)
FIGHT_STATES = { FirstPull = true, Reeling = true }

-- เกาะที่ตัวละครอยู่ตอนนี้ อ่านจาก IslandRegionController (เกม resolve จากตำแหน่งจริง)
-- คืน string เสมอ ("" = ยังไม่เข้าโซนเกาะไหน)
local function currentIslandId()
    local ok, id = pcall(function()
        local c = Client and Client.GetController and Client.GetController("IslandRegionController")
        if not c then
            c = require(ReplicatedStorage.Controllers.IslandRegionController)
        end
        return c:GetCurrentIslandId()
    end)
    if ok and type(id) == "string" then return id end
    return ""
end

-- ระดับน้ำของเกาะปัจจุบัน (fallback WorldConfig.SEA_LEVEL = 3)
local function getWaterY()
    local ok, y = pcall(function()
        return Catalog.Island.GetWaterY(currentIslandId())
    end)
    if ok and type(y) == "number" then return y end
    return WorldConfig and WorldConfig.SEA_LEVEL or 3
end

-- ══════════════════════════════════════════════════
-- หา "น้ำเปิด" ใกล้ตัวที่สุด (พอร์ตจาก test_cast_nearest_water.lua)
-- ══════════════════════════════════════════════════
local function isOpenWater(x, z)
    local world = Workspace:FindFirstChild("World")
    local islands = world and world:FindFirstChild("Islands")
    if not islands then return true end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = { islands }
    local origin = Vector3.new(x, 500, z)
    local dir    = Vector3.new(0, -1000, 0)
    return Workspace:Raycast(origin, dir, params) == nil
end

local function findNearestOpenWater(origin)
    for r = CONFIG.ScanStep, CONFIG.MaxDist, CONFIG.ScanStep do
        local samples = math.max(8, math.floor((2 * math.pi * r) / CONFIG.ScanStep))
        for i = 0, samples - 1 do
            local ang = (i / samples) * 2 * math.pi
            local x = origin.X + math.cos(ang) * r
            local z = origin.Z + math.sin(ang) * r
            if isOpenWater(x, z) then
                return Vector3.new(x, getWaterY(), z)
            end
        end
    end
    return nil
end

local function faceTowards(target)
    local hrp = root()
    if not (hrp and hrp:IsA("BasePart")) then return end
    local flat = Vector3.new(target.X - hrp.Position.X, 0, target.Z - hrp.Position.Z)
    if flat.Magnitude < 0.001 then return end
    local look = CFrame.lookAt(hrp.Position, Vector3.new(target.X, hrp.Position.Y, target.Z))
    S.tools.tweenCF(hrp, look, 0.05)
end

-- ══════════════════════════════════════════════════
-- raycast หา "พื้นจริง" ที่ตำแหน่ง (x,z)
-- ──────────────────────────────────────────────────
-- เหตุผล: การเดา Y (center.Y - N studs) ทำให้เป้าอาจอยู่ใต้พื้น/ใต้โลก
--          -> ตัวละครตกใต้ฉาก -> เกม warp กลับจุด spawn
--          วิธีนี้อ่านพื้นจริงจากฉากตอนนั้นเลย ไม่ต้องนับค่าเอง
--
-- ⚠ ต้องยิง "จากบนลง" เสมอ: ถ้ายิงจากจุดที่ต่ำกว่าพื้นอยู่แล้ว
--   ray จะวิ่งลงไปในอากาศข้างล่าง -> ไม่เจออะไรเลย -> เข้าใจผิดว่า "ไม่มีพื้น"
--   (เคยเจอจริงที่ House1: ยิงจาก center.Y - 9 ซึ่งต่ำกว่าพื้นเกาะ -> คืน nil ทั้งที่มีพื้น)
-- ══════════════════════════════════════════════════

--- ยิง ray ลงแล้วเก็บ "ทุกผิว" ที่โดนตามทาง ไม่ใช่แค่ผิวแรก
--- ──────────────────────────────────────────────────
--- Workspace:Raycast คืนผิวแรกที่ชนเสมอ แต่บ้าน 1 ชั้น ray เดียวจะทะลุผ่าน:
---   หลังคา -> (อากาศในบ้าน) -> พื้นบ้าน -> (อากาศใต้บ้าน) -> พื้นดิน
--- ถ้าเอาแค่ผิวแรก = ได้หลังคา; ถ้าเอาผิวสุดท้าย = ได้พื้นดินใต้บ้าน (ไม่ใช่ที่ต้องการ)
--- วิธีนี้ = ยิงซ้ำโดยเริ่มต่ำกว่าผิวก่อนหน้าทุกครั้ง แล้วค่อยแยกผิวของบ้านออกมา
local function allSurfacesDown(x, z, fromY, skipList, maxHits)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = skipList or {}
    params.IgnoreWater = true
    -- นับ part ที่ CanCollide=false ด้วย (พื้นบ้านหลายชิ้นไม่ได้เปิด collision)
    params.RespectCanCollide = false

    local out, y = {}, fromY or 500
    for _ = 1, (maxHits or 10) do
        local ok, res = pcall(function()
            return Workspace:Raycast(Vector3.new(x, y, z), Vector3.new(0, -1000, 0), params)
        end)
        if not ok or not res then break end
        out[#out + 1] = res
        y = res.Position.Y - 0.05   -- ลงต่ำกว่าผิวนี้เล็กน้อย เพื่อหาผิวถัดไป
    end
    return out
end

-- satchel เต็มหรือยัง (FishStorageRules.GetState(data).isFull)
local function isSatchelFull(data)
    if not FishStorageRules then
        -- fallback: นับ Inventory.Fishes เอง (ไม่มี capacity จริงในที่นี้)
        return false
    end
    local ok, st = pcall(function() return FishStorageRules.GetState(data) end)
    if ok and type(st) == "table" then return st.isFull end
    return false
end

-- ══════════════════════════════════════════════════
-- หา NPC ของเกาะที่ระบุ (คนขายปลา/คนตั้ง spawn ฯลฯ)
-- ⚠ ต้องกรองด้วย IslandId เสมอ ไม่งั้นเมื่อไปเกาะ 2 แล้วจะไปจับคนขายของเกาะ 1
--   (ทุกเกาะมี npc_fish_seller_1 ของตัวเอง และเกมโหลดมาทั้งหมดพร้อมกัน)
-- ══════════════════════════════════════════════════
local function islandRoot(islandId)
    local world = Workspace:FindFirstChild("World")
    local islands = world and world:FindFirstChild("Islands")
    return (islands and islands:FindFirstChild(islandId)) or nil
end

-- หา model ของ NPC ที่มี InteractiveId ตรงกับที่ขอ ในเกาะที่ระบุ
-- คืน Model (มี HumanoidRootPart) หรือ nil
local function findNpcOnIsland(islandId, interactiveId)
    local isl = islandRoot(islandId)
    if not isl then return nil end
    local inter = isl:FindFirstChild("Interactives")
    if not inter then return nil end
    for _, m in ipairs(inter:GetChildren()) do
        if m:IsA("Model") and m:GetAttribute("IslandId") == islandId
           and (m:GetAttribute("InteractiveId") == interactiveId) then
            return m
        end
    end
    -- เผื่อ attribute ยังไม่ถูกตั้งตอนนั้น: เดาจากชื่อ (npc_fish_seller_1, npc_fish_seller_2 ...)
    for _, m in ipairs(inter:GetChildren()) do
        if m:IsA("Model") and (m.Name == interactiveId or m.Name:sub(1, #interactiveId + 1) == interactiveId .. "_") then
            return m
        end
    end
    return nil
end

--- ชื่อ NPC แบบตรงตัวหรือมีหาง "_..." (npc_car_merchant / npc_car_merchant_desert)
local function npcNameMatch(name, interactiveId)
    return name == interactiveId or name:sub(1, #interactiveId + 1) == interactiveId .. "_"
end

--- หา NPC ที่ยัง stream อยู่ของเกาะไหนก็ได้ แล้วเอาตัวที่ "ใกล้เราที่สุด" — คืน Model, ระยะ
--- ใช้เป็นทางสำรองสุดท้ายตอน NPC ของเกาะที่ต้องการยังไม่โหลดเข้ามา
--- (ตอนยืนที่ Desert เราจะได้ NPC ของ Desert ก่อนเสมอ เพราะมันใกล้กว่าของเกาะอื่น)
---
--- ⚠ สแกน Workspace.Raids / Workspace.RaidSlots ด้วย: NPC ของ raid
---   (Ticket Keeper / Raid Guide / ตัวรับรางวัล) ไม่ได้อยู่ใน World.Islands
---   แต่ถูกสร้างเป็นโมเดลในพื้นที่ raid ตอนที่ raid ทำงาน
local function findNearestNpcAnywhere(interactiveId)
    local hrp = root()
    if not hrp then return nil, nil end
    local best, bestD = nil, math.huge
    local function consider(m)
        local h = m:FindFirstChild("HumanoidRootPart")
        if h and h:IsA("BasePart") then
            local d = (h.Position - hrp.Position).Magnitude
            if d < bestD then best, bestD = m, d end
        end
    end
    local world = Workspace:FindFirstChild("World")
    local islands = world and world:FindFirstChild("Islands")
    if islands then
        for _, isl in ipairs(islands:GetChildren()) do
            local inter = isl:FindFirstChild("Interactives")
            if inter then
                for _, m in ipairs(inter:GetChildren()) do
                    if m:IsA("Model") and npcNameMatch(m.Name, interactiveId) then consider(m) end
                end
            end
        end
    end
    for _, folderName in ipairs({ "Raids", "RaidSlots" }) do
        local f = Workspace:FindFirstChild(folderName)
        if f then
            for _, d in ipairs(f:GetDescendants()) do
                if d:IsA("Model") and npcNameMatch(d.Name, interactiveId) then consider(d) end
            end
        end
    end
    return best, bestD
end

--- จุดลงของเกาะ = จุดที่เอาไปว่ายก่อนตอนที่ NPC ยังไม่โหลดเข้ามา
---
--- ⚠ ลำดับชั้นที่ 1 เปลี่ยนเป็น CONFIG.IslandPoints[id].spawn (ผู้ใช้ให้พิกัด 2026-10-17)
---   = จุด NPC "Set Spawn" ของเกาะนั้น พอถึงจุดนี้ของที่เหลือของเกาะจะ stream เข้ามา
---   ชั้นที่ 2/3 คงไว้เป็นทางสำรอง สำหรับเกาะที่ยังไม่ได้ประกาศพิกัด
--- ลำดับ: IslandPoints.spawn -> CONFIG.IslandLandings -> <island>.SpawnPoint.Spawners -> nil
local function islandLandingSpot(islandId)
    local row = (CONFIG.IslandPoints or {})[islandId]
    if type(row) == "table" and row.spawn then return row.spawn end
    local cfg = (CONFIG.IslandLandings or {})[islandId]
    if cfg then return cfg end
    local isl = islandRoot(islandId)
    local sp = isl and isl:FindFirstChild("SpawnPoint")
    local spawners = sp and sp:FindFirstChild("Spawners")
    if spawners then
        for _, p in ipairs(spawners:GetChildren()) do
            if p:IsA("BasePart") then return p.Position end
        end
    end
    return nil
end

--- รอให้ NPC โผล่ (เกม stream เข้ามาเมื่อเราเข้าใกล้) — คืน Model หรือ nil
--- ⚠ maxWait = เพดานกันค้าง ไม่ใช่เงื่อนไขว่า NPC มีหรือไม่
---   ครบเวลาแล้วยังไม่เจอ = บอกตรง ๆ ว่าไม่เจอ ไม่เงียบรอไปเรื่อย ๆ
local function waitForNpcOnIsland(islandId, interactiveId, maxWait)
    local t0 = nowReal()
    local limit = (maxWait or 6)
    local rounds, maxRounds = 0, math.max(1, math.ceil(limit / 0.25)) + 1
    while nowReal() - t0 < limit and rounds < maxRounds do
        rounds = rounds + 1
        local m = findNpcOnIsland(islandId, interactiveId)
        if m then return m end
        task.wait(0.25)
    end
    return findNpcOnIsland(islandId, interactiveId)
end

-- หาคนขายปลา (npc_fish_seller) ของเกาะที่ระบุ คืน HumanoidRootPart
--- รอจนกว่า "เงื่อนไข" จะเป็นจริง โดยอ่านค่าจริงจากเกมทุกครั้ง
---   ⚠ หลัก "ห้ามนับเวลาเอง" = ตัดสินใจจากค่าของเกม ไม่ใช่จากตัวเลขที่เรานับ
---     ตรงนี้เวลามีแค่หน้าที่ "แบ่งจังหวะวนซ้ำ" ส่วน maxWait เป็นเพดานกันค้าง ไม่ใช่คำตอบ
---   ถ้าใช้ task.wait(0.4) แล้วเช็คครั้งเดียว = ถ้า replicate ช้ากว่านั้น
---   เราจะตอบว่า "ยังไม่สำเร็จ" ทั้งที่เซิร์ฟทำเสร็จแล้ว -> เควสต์ติดถาวร
--- รอจนเงื่อนไขเป็นจริง โดยอ่านสถานะจริงซ้ำ ๆ
--- ⚠ os.clock() ใช้ไม่ได้ในลูปนี้ — มันเป็นเวลา CPU ไม่ขยับตอน yield
---   task.wait(step) ข้างใน = os.clock ไม่เดิน = ถ้าเงื่อนไขไม่เป็นจริงก็วนไม่รู้จบ
---   ใช้ nowReal() (เวลาจริงจากเซิร์ฟ) + จำกัดจำนวนรอบไว้เป็นตาขาสุดท้าย
---   (ตาขาสุดท้ายสำคัญที่สุด: ถ้าอ่าน nowReal ไม่ได้จริงก็ยังต้องจบ)
--- ⚠ pcall(fn) เพิ่ม: ถ้าเงื่อนไขใน fn พัง อย่าให้ลากทั้งสคริปต์ตาย
local function pollUntil(fn, maxWait, step)
    if not (type(step) == "number" and step > 0) then step = 0.1 end
    maxWait = (type(maxWait) == "number" and maxWait > 0) and maxWait or 2
    local t0 = nowReal()
    local maxRounds = math.max(1, math.ceil(maxWait / step))
    local rounds = 0
    while true do
        local ok, r = pcall(fn)
        if ok and r then return r end
        rounds = rounds + 1
        if rounds >= maxRounds then return nil end
        if nowReal() - t0 >= maxWait then return nil end
        task.wait(step)
    end
end

local function findSellerHrp(islandId)
    islandId = islandId or currentIslandId()
    local m = findNpcOnIsland(islandId, "npc_fish_seller")
    if m then
        local hrp = m:FindFirstChild("HumanoidRootPart")
        if hrp and hrp:IsA("BasePart") then return hrp end
    end
    -- fallback: เผื่อโครงสร้างต่างจากที่คาด — หา Interactive tag แล้วกรอง IslandId
    for _, mm in ipairs(CollectionService:GetTagged("Interactive")) do
        if mm:IsA("Model") and mm:GetAttribute("InteractiveId") == "npc_fish_seller"
           and (not islandId or mm:GetAttribute("IslandId") == islandId) then
            local hrp = mm:FindFirstChild("HumanoidRootPart")
            if hrp and hrp:IsA("BasePart") then return hrp end
        end
    end
    -- สำรองสุดท้าย: NPC ของเกาะนี้ยังไม่ stream เข้ามา แต่ตัวของเกาะอื่นที่ stream อยู่โผล่แล้ว
    --   เอาตัวที่ใกล้ที่สุดมาใช้ — ระยะจริงให้ผู้เรียกตัดสินอีกที (ต้อง <= 25 ถึงขายได้)
    local m2, d2 = findNearestNpcAnywhere("npc_fish_seller")
    if m2 and d2 and d2 <= 400 then
        local hrp = m2:FindFirstChild("HumanoidRootPart")
        if hrp and hrp:IsA("BasePart") then return hrp end
    end
    return nil
end

-- ระยะห่างจากคนขายปลา (studs) คืน nil ถ้าหา NPC ไม่ได้
local function sellerDistance(islandId)
    local hrp = root()
    local seller = findSellerHrp(islandId)
    if not (hrp and seller) then return nil end
    return (seller.Position - hrp.Position).Magnitude
end

-- ══════════════════════════════════════════════════
-- DATA HELPERS
-- ══════════════════════════════════════════════════
-- ⚠ ประกาศไว้ข้างบนแล้ว (nextStep เรียกก่อนถึงจุดนี้)
--   เขียนเป็น "function" ไม่ใช่ "local function" ไม่งั้นจะกลายเป็นตัวแปรใหม่ทับตัวเดิม
function fetchData()
    local ok, d = pcall(function() return PlayerData:Fetch() end)
    if ok and type(d) == "table" then return d end
    return nil
end

local function waitForData(timeout)
    local t0 = os.clock()
    while os.clock() - t0 < (timeout or 30) do
        local d = fetchData()
        if d and type(d.Coin) == "number" then return d end
        task.wait(0.5)
    end
    logWarn("[Prog] รอข้อมูลผู้เล่นไม่สำเร็จ")
    return nil
end

local function ownedSkills(data)
    local inv = invOf(data)
    local books = inv and inv.Books
    local out = {}
    if type(books) == "table" then
        for id, count in pairs(books) do
            if type(count) == "number" and count > 0 then out[id] = math.floor(count) end
        end
    end
    return out
end

-- ลำดับความหายากของสกิล (อ่านจาก Catalog.Data.Catalog.Skill ตอนรัน)
local RARITY_RANK = {
    Common = 1, Uncommon = 2, Rare = 3, Legendary = 4, Mythical = 5,
}

--- (เดิมมี rarity สูงสุดที่เรามี + hasRarityAtLeast ตรงนี้
---   ถูกแทนด้วย islandSkillsReady แล้ว เพราะกติกาใหม่นับ "จำนวนสกิลที่แยกกัน"
---   ไม่ใช่แค่ "มีสกิลดีสุดสักตัว" — ทั้งสองให้ผลเหมือนกันเฉพาะตอนที่ยังไม่ได้ประกาศ SkillTargets)

--- เป้าหมายสกิลของเกาะ (nil = เกาะนี้ไม่มีข้อกำหนด / ไม่ประกาศ = GachaTargetRarity 1 ตัว)
local function skillTargetFor(islandId)
    local t = (CONFIG.SkillTargets or {})[islandId]
    if t then return t end
    if CONFIG.NoLegendaryIslands[islandId] then return nil end
    return { rarity = CONFIG.GachaTargetRarity, count = 1 }
end

--- สกิลของเกาะนี้ครบเป้าหมายไหม — คืน ok, ข้อความสถานะ
---
--- ⚠ กติกานับ (ตามที่ผู้ใช้กำหนด):
---   1) นับ skillId ที่แยกกัน — สำเนาซ้ำของสกิลเดิมไม่เพิ่ม (Books[X] = 5 นับเป็น 1)
---   2) สกิลที่ดีกว่าเป้าหมายนับแทนได้ แต่ยังนับเป็น 1 เท่านั้น
---      เป้าหมาย Rare 2 -> Legend 1 + Rare 1 ผ่าน (2) / Mythical 1 ลอย ๆ ไม่ผ่าน (1)
---   อ่านจาก Catalog.Skill ตอนรัน ไม่ hardcode รายชื่อสกิล
local function islandSkillsReady(data, islandId)
    local want = skillTargetFor(islandId)
    if not want then return true, nil end
    local needRank = RARITY_RANK[want.rarity] or RARITY_RANK.Legendary

    -- pairs บน ownedSkills = วนตาม skillId ที่แยกกันอยู่แล้ว
    --   จำนวนสำเนาในค่าไม่ถูกนำมาบวก -> ตรงกับกติกา "สกิลซ้ำกันไม่นับ"
    local n, have = 0, {}
    for skillId in pairs(ownedSkills(data)) do
        local meta = Catalog and Catalog.Skill and Catalog.Skill.GetById and Catalog.Skill.GetById(skillId)
        local r = (type(meta) == "table" and type(meta.rarity) == "string") and meta.rarity or "Common"
        have[r] = (have[r] or 0) + 1
        if (RARITY_RANK[r] or 1) >= needRank then n = n + 1 end
    end

    local ok = n >= (want.count or 1)
    local msg = ("สกิล %s ขั้นต่ำ %d ตัว — ตอนนี้ %d ตัว%s")
        :format(tostring(want.rarity), want.count or 1, n,
            (ok and " (พร้อม)" or " — ยังขาด " .. tostring((want.count or 1) - n)))
    return ok, msg
end

-- ══════════════════════════════════════════════════
-- 2a) UNIT — อ่านของที่มี / นับเป้าหมายรายเกาะ / เลือกตัวที่ดาเมจสูงสุด
-- ══════════════════════════════════════════════════
-- ⚠ ทั้ง 7 ตัวนี้ประกาศเป็น global ไม่ใช่ local เพราะ Lua จำกัด local ใน main chunk ไว้ 200 ตัว
--   และไฟล์นี้มี local ระดับบนสุดอยู่แล้วเกือบเต็ม (โค้ดชุดอื่นก็ใช้รูปแบบนี้เหมือนกัน:
--   AURA_RANK / rollSkillOnce / readAuras / pullAuras / equipAura ...)
-- ⚠ ลำดับความหายากของ Unit ต่างจากสกิลตรงที่มี Epic เพิ่มขึ้นมาอีกขั้น
--   (UnitConfig.Rarities = Common/Uncommon/Rare/Epic/Legendary/Mythical)
UNIT_RARITY_RANK = {
    Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythical = 6,
}

--- ตัวเลข buff ของ Unit ตัวนั้น (คิดตามอายุแล้ว) — สูตรเดียวกับ UnitCore.GetStats
---   buff = BaseValue x (1 + (Age - 1) x BuffGrowthPerAge)   (BuffGrowthPerAge = 0.1)
function unitBuffValue(u, key)
    if type(u) ~= "table" or type(u.Stats) ~= "table" then return 0 end
    local age = (type(u.Age) == "number") and u.Age or 1
    for _, st in ipairs(u.Stats) do
        if type(st) == "table" and st.Key == key then
            return (tonumber(st.BaseValue) or 0) * (1 + (age - 1) * 0.1)
        end
    end
    return 0
end

--- Unit ทุกตัวที่เรามี -> {uid, unitId, name, rarity, age, kind, damageCoef, skillPct, mult, equipped}
---
--- ⚠ rarity ไม่ได้อยู่ใน Catalog.Unit เลย (แคตตาล็อกมีแค่ id/name/icon/modelName/weight/skillGroups)
---   rarity คือค่าที่ "roll ได้ตอนสุ่ม" แล้วเซิร์ฟ replicate มาเก็บที่ Owned[uid].Rarity
---   -> สุ่ม ba_chang สองครั้งอาจได้ Common ครั้งแรก แล้ว Legendary ครั้งที่สอง = คนละตัว
---   และสกิลที่ตัว Unit ใช้ยิง = SkillBookId ที่ roll ได้ตอนสุ่ม (ไม่ใช่สกิลของผู้เล่น)
function ownedUnits(data)
    local out, n = {}, 0
    local units = data and data.Units
    if type(units) ~= "table" or type(units.Owned) ~= "table" then return out, 0 end

    local equipped = {}
    if type(units.Equipped) == "table" then
        for _, uid in ipairs(units.Equipped) do equipped[uid] = true end
    end

    for uid, u in pairs(units.Owned) do
        n = n + 1
        if type(u) == "table" and type(u.UnitId) == "string" then
            local meta, sk = nil, nil
            if Catalog and Catalog.Unit and Catalog.Unit.GetById then
                pcall(function() meta = Catalog.Unit.GetById(u.UnitId) end)
            end
            if Catalog and Catalog.Skill and Catalog.Skill.GetById then
                pcall(function() sk = Catalog.Skill.GetById(u.SkillBookId) end)
            end
            out[uid] = {
                uid       = uid,
                unitId    = u.UnitId,
                name      = (type(meta) == "table" and meta.name) or u.UnitId,
                rarity    = (type(u.Rarity) == "string") and u.Rarity or "Common",
                age       = (type(u.Age) == "number") and u.Age or 1,
                -- สกิลของตัวนี้ (จาก Catalog.Skill ตอนรัน ไม่ hardcode)
                kind       = (type(sk) == "table" and sk.kind) or "Hit",
                damageCoef = (type(sk) == "table" and tonumber(sk.damageCoef)) or 0,
                -- ค่าที่ roll ได้ตอนสุ่ม
                skillPct   = unitBuffValue(u, "skillDamagePct"),
                mult       = tonumber(u.SkillDamageMultiplier) or 1,
                equipped   = equipped[uid] == true,
            }
        end
    end
    return out, n
end

--- ดาเมจฐานของสกิล Unit ตัวนี้ = สูตรเดียวกับที่เกมแสดงในหน้าต่าง Unit
---   (UnitEquipment.lua:197 -> SkillBase(stats, unit, damageCoef, hits) x hits)
---
--- ตัดตัวคูณที่เหมือนกันทุกตัวออก เพราะมันไม่กระทบการจัดอันดับ:
---   attackDamage = ดาเมจเบ็ดของผู้เล่น (เหมือนกันทุกตัว) · /hits x hits = หารแล้วคูณกลับ ตกทิ้ง
--- เหลือเฉพาะสิ่งที่ "ต่างกันต่อ Unit":
---   (damageCoef x Age/100) x (1 + skillDamagePct ของตัวนี้) x SkillDamageMultiplier
---
--- ⚠ สกิลที่ไม่ยิงดาเมจ (kind ~= "Hit") = 0 ไม่ใช่ค่าติดลบ
function unitBaseDamage(u)
    if not u or u.kind ~= "Hit" then return 0 end
    local coef = tonumber(u.damageCoef) or 0
    if coef <= 0 then return 0 end
    return (coef * (u.age or 1) / 100) * (1 + (u.skillPct or 0)) * (u.mult or 1)
end

--- เป้าหมาย Unit ของเกาะ (nil = เกาะนี้ไม่สุ่ม Unit เลย)
function unitTargetFor(islandId)
    return (CONFIG.UnitTargets or {})[islandId]
end

--- Unit ของเกาะนี้ครบเป้าหมายไหม — คืน ok, ข้อความสถานะ, ช่องว่างในคลัง
--- ⚠ นับที่ "uid" ไม่ใช่ unitId = แต่ละครั้งที่สุ่มได้ตัวใหม่ที่ rarity ของตัวเอง (ดู ownedUnits)
function islandUnitsReady(data, islandId)
    local want = unitTargetFor(islandId)
    if not want then return true, nil, nil end
    local needRank = UNIT_RARITY_RANK[want.rarity] or UNIT_RARITY_RANK.Common

    local units, count = ownedUnits(data)
    local n = 0
    for _uid, u in pairs(units) do
        if (UNIT_RARITY_RANK[u.rarity] or 1) >= needRank then n = n + 1 end
    end

    -- ช่องว่างในคลัง = Capacity - จำนวนที่มีจริง (เกมนับจาก #Owned เหมือนกัน)
    local cap = tonumber((data and data.Units or {}).Capacity) or 0
    local free = cap - count

    local need = want.count or 1
    local ok = n >= need
    local msg = ("Unit %s ขั้นต่ำ %d ตัว — ตอนนี้ %d ตัว%s")
        :format(tostring(want.rarity), need, n,
            (ok and " (พร้อม)" or " — ยังขาด " .. tostring(need - n)))
    return ok, msg, free
end

--- ใส่ Unit ที่ "ดาเมจสกิลฐาน" มากที่สุด แล้วถอดตัวอื่นออก
---   (กติกาผู้ใช้: ใช้ตัวเดียว — ตัวที่ดาเมจสูงสุด)
---   คืน true ถ้าเพิ่งสลับ
function equipBestUnit(data)
    if not (UnitCtl and UnitCtl.SetEquipped) then return false end
    local units = ownedUnits(data)
    local best, bestV = nil, -1
    for _uid, u in pairs(units) do
        local v = unitBaseDamage(u)
        if v > bestV then best, bestV = u, v end
    end
    if not best then return false end             -- ยังไม่มี Unit เลย

    local did = false
    -- 1) ใส่ตัวที่ดีที่สุด
    if not best.equipped then
        local ok, res = pcall(UnitCtl.SetEquipped, UnitCtl, best.uid, true)
        if ok and res then did = true end
    end
    -- 2) ถอดตัวอื่นที่ยังใส่อยู่
    for _uid, u in pairs(units) do
        if u.equipped and u.uid ~= best.uid then
            local ok, res = pcall(UnitCtl.SetEquipped, UnitCtl, u.uid, false)
            if ok and res then did = true end
        end
    end
    return did
end

-- ══════════════════════════════════════════════════
-- 1) TUTORIAL SKIP
-- ══════════════════════════════════════════════════
local function isInTutorial(data)
    -- server truth: PlayerData.Tutorial.State ; controller mirror: _state
    local t = data and data.Tutorial
    local st = t and t.State
    if st and st ~= "" and st ~= "Completed" then return true end
    if TutorialCtl and type(TutorialCtl._state) == "string"
       and TutorialCtl._state ~= "" and TutorialCtl._state ~= "Completed" then
        return true
    end
    return false
end

local function doTutorialSkip()
    -- ทางหลัก: เรียก method ของ controller จริง (ยิง Tutorial/Skip + apply state)
    if TutorialCtl and type(TutorialCtl.SkipTutorial) == "function" then
        local ok, err = pcall(function() TutorialCtl:SkipTutorial() end)
        if ok then return true end
        logWarn(("[Prog] SkipTutorial ล้มเหลว: %s"):format(tostring(err)))
    end
    -- fallback: ยิง packet Tutorial/Skip ตรง ๆ
    if TutorialCtl and TutorialCtl.Skip then
        local ok = pcall(function() TutorialCtl.Skip:Fire() end)
        if ok then return true end
    end
    logWarn("[Prog] ไม่สามารถ skip tutorial ได้")
    return false
end

-- ══════════════════════════════════════════════════
-- 2) SKILL GACHA
-- ══════════════════════════════════════════════════
--- สุ่ม 1 ครั้ง (เช็คราคาก่อน) คืน true ถ้าได้สกิล / ราคาไม่พอ
function rollSkillOnce(data)
    local quote = nil
    if GachaCtl and GachaCtl.GetQuote then
        local ok, res = pcall(function() return GachaCtl.GetQuote:Fire(1) end)
        if ok and type(res) == "table" and res.ok then quote = res end
    end
    if not quote then
        logWarn("[Prog] GACHA: GetQuote ล้มเหลว — ข้าม")
        return false, nil
    end
    local cost = tonumber(quote.coin_cost) or 0
    local credits = numOr(quote.credits_available, 0)
    local free = (cost <= 0) or (credits > 0)
    local coin = numOr(data and data.Coin, 0)

    if not free and coin < cost then return false, "no-coin" end

    local res = nil
    if GachaCtl and GachaCtl.Pull then
        GachaRequestId = GachaRequestId + 1
        local ok, r = pcall(function() return GachaCtl.Pull:Fire("Coin", 1, GachaRequestId) end)
        if ok and type(r) == "table" then res = r end
    end
    if not res then
        logWarn("[Prog] GACHA: Pull ไม่ตอบกลับ")
        return false, nil
    end
    if not res.ok then return false, tostring(res.reason) end

    return true, nil
end

-- ══════════════════════════════════════════════════
-- 2b) UNIT GACHA
-- ══════════════════════════════════════════════════
--- สุ่ม Unit 1 ครั้ง (เช็คราคา + ช่องว่างในคลังก่อนยิง)
---   คืน true ถ้าได้ / false, "no-coin" เงินไม่พอ / false, "no-slot" คลังเต็ม
---
--- ⚠ ต่างจาก rollSkillOnce สองจุด (อ่านจาก UnitGachaController.lua:73-82):
---   1) Pull:Fire(count, requestId) — ไม่มี "Coin" นำหน้า (สกิลมี)
---   2) GetQuote ตอบ storage_available แทน credits_available และไม่มี credits มาให้ใช้
---   3) ราคาขึ้นทุกครั้งที่สุ่ม (BaseCost + IncrementPerPull) และรีเซ็ตทุก 12 ชม.
---      -> ทุกครั้งที่ยิงต้องถามราคาจากเซิร์ฟก่อน อย่าเดาราคาเอง
function rollUnitOnce(data)
    if not (UnitGachaCtl and UnitGachaCtl.GetQuote and UnitGachaCtl.Pull) then
        logWarn("[Prog] UNIT GACHA: ไม่มี UnitGachaController — สุ่มไม่ได้")
        return false, nil
    end

    local quote = nil
    local okQ, qres = pcall(function() return UnitGachaCtl.GetQuote:Fire(1) end)
    if okQ and type(qres) == "table" and qres.ok then quote = qres end
    if not quote then
        logWarn("[Prog] UNIT GACHA: GetQuote ล้มเหลว — ข้าม")
        return false, nil
    end

    -- ⚠ คลัง Unit มีแค่ 3 ช่อง (UnitConfig.FreeCapacity 1 / MaxCapacity 3)
    --   และเกมไม่มีทางขาย Unit — มีแต่ Unit/Remove ที่เป็นการลบถาวร ("ไม่ได้กลับมา")
    --   ช่องเต็ม = สุ่มไม่ได้ ต้องให้ผู้ใช้ถอดช่องเพิ่ม (gem) หรือลบตัวเอง สคริปต์นี้ไม่ลบให้
    --   ⚠ tonumber ทั้งค่า: ถ้าเซิร์ฟส่งมาผิดชนิด (string/table) การเทียบ < 1 จะพังทันที
    if numOr(quote.storage_available, 0) < 1 then return false, "no-slot" end

    local cost = tonumber(quote.coin_cost) or 0
    if cost > 0 and numOr(data and data.Coin, 0) < cost then return false, "no-coin" end

    GachaRequestId = GachaRequestId + 1
    local ok, res = pcall(function() return UnitGachaCtl.Pull:Fire(1, GachaRequestId) end)
    if not (ok and type(res) == "table") then
        logWarn("[Prog] UNIT GACHA: Pull ไม่ตอบกลับ")
        return false, nil
    end
    if not res.ok then return false, tostring(res.reason) end

    S.unitPulled = (S.unitPulled or 0) + 1
    return true, nil
end

-- ══════════════════════════════════════════════════
-- 3) RODS (ซื้อจากร้าน) + ISLANDS (ปลดล็อกผ่าน QuestController)
-- ⚠ ทุกตัวในกลุ่มนี้ประกาศไว้ข้างบนแล้ว (เพราะ nextStep เรียกใช้ก่อนถึงจุดนี้)
--   ต้องเขียนเป็น "ชื่อ = function" ธรรมดา ถ้าเขียน local function จะกลายเป็นตัวแปรใหม่
--   ทับของเดิม = nextStep จะเรียกได้แค่ nil
-- ══════════════════════════════════════════════════
--- ราคาเบ็ดจาก RodShopConfig (nil = ห้านี้ไม่ขายด้วย Coin)
function rodPrice(rodId)
    local c = RodShopConfig and RodShopConfig[rodId]
    return (type(c) == "table" and type(c.price) == "number") and c.price or nil
end

--- มีเบ็ดนี้ในคลังแล้วหรือยัง (อ่าน data.Rods จริง)
function ownsRod(data, rodId)
    local rods = data and data.Rods
    return type(rods) == "table" and rods[rodId] ~= nil
end

--- ได้เบ็ด Dread Fish Rod แล้วหรือยัง — เช็คจากคลังเบ็ดก่อน แล้วค่อยดูธงว่าเควสต์จบไหม
---   (เบ็ดนี้มาจากเควสต์ บางทีเซิร์ฟอาจเก็บลง Quest.Done แต่ไม่ลง data.Rods)
DREAD_ROD_ID = "dread_fish_rod"
function dreadRodOwned(data)
    if ownsRod(data, DREAD_ROD_ID) then return true end
    local d = data and data.Quest and data.Quest.Done
    return type(d) == "table" and d[DREAD_ROD_ID] == true
end

--- ตอนนี้เก็บ gem ไว้เลยหรือยัง (SaveGemAfterDreadFishRod เปิด + ได้ Dread Rod แล้ว)
function gemHoldActive(data)
    if not cfgOn("SaveGemAfterDreadFishRod", CONFIG.Aura.SaveGemAfterDreadFishRod) then return false end
    return dreadRodOwned(data)
end

--- ซื้อเบ็ด — คืน true ถ้ามีในคลังแล้วหลังยิง
--- เช็คเงื่อนไขจริงก่อน (เกาะต้องปลดล็อก + เงินพอ) แล้วค่อยยิง PurchaseRod
function buyRod(rodId, data)
    if ownsRod(data, rodId) then return true end
    local cfg = RodShopConfig and RodShopConfig[rodId]
    if type(cfg) ~= "table" then
        logWarn(("[Prog] %s ไม่มีในร้าน (RodShopConfig)"):format(tostring(rodId)))
        return false
    end
    if cfg.islandId and not islandUnlocked(data, cfg.islandId) then
        logWarn(("[Prog] ซื้อ %s ไม่ได้ — ยังไม่ปลดล็อก %s"):format(tostring(rodId), islandTag(cfg.islandId)))
        return false
    end
    if numOr(data.Coin, 0) < (cfg.price or 0) then return false end
    if not (RodShopCtl and RodShopCtl.PurchaseRod) then
        logWarn("[Prog] ไม่มี PurchaseRod packet")
        return false
    end
    local ok, res = pcall(function() return RodShopCtl.PurchaseRod:Fire(rodId) end)
    if ok and res then return true end
    logWarn(("[Prog] PurchaseRod %s ตอบ %s"):format(tostring(rodId), tostring(res)))
    return false
end

--- ราคาปลดล็อกเกาะจาก IslandConfig (nil = อ่านไม่ได้)
function islandCost(islandId)
    local c = IslandConfig and IslandConfig[islandId]
    return (type(c) == "table" and type(c.unlockCost) == "number") and c.unlockCost or nil
end

--- ปลดล็อกเกาะแล้วหรือยัง — อ่าน data.UnlockedIslands จริง (defaultUnlocked ก็นับ)
function islandUnlocked(data, islandId)
    local meta = IslandConfig and IslandConfig[islandId]
    if type(meta) == "table" and meta.defaultUnlocked == true then return true end
    local u = data and data.UnlockedIslands
    return type(u) == "table" and u[islandId] == true
end

--- quest id ของการปลดล็อกเกาะ: island_jungle -> "unlock_island_2"
local UNLOCK_QUEST = {
    island_jungle = "unlock_island_2",
    island_desert = "unlock_island_3",
    island_snow   = "unlock_island_4",
    island_volcano = "unlock_island_5",
    island_fossil = "unlock_island_6",
    island_lotus = "unlock_island_7",
}

--- id ของเควสต์ที่ภารกิจนี้ใช้
---   เควสต์เบ็ดใช้ id ของเบ็ดตัวเอง (targetRod) / เควสต์ปลดเกาะใช้คีย์ของเกาะ
--- ⚠ จำเป็นมาก: Progress ที่เราอ่านเป็นของเควสต์ที่ "กำลังทำอยู่" ไม่ใช่ของภารกิจ m
---   ถ้าเอามาใช้ผิดภารกิจ จะไปล็อคปลาผิดชนิด แล้วกด ToggleLock ซ้ำตัวเดิมจนปลดออก
---   (ToggleLock เป็นสวิตช์ ไม่ใช่ set) -> ปลาของเควสต์ถูกขายทิ้ง
local function questIdOf(m)
    if not m then return nil end
    if m.kind == "rod" then return m.targetRod end
    return UNLOCK_QUEST[m.targetIsland]
end

--- ข้อความจาก server ตอนกด Complete ทั้งที่ยังไม่มีเควสต์ที่กำลังทำอยู่จริง ๆ
---   ใช้เป็น "อาการ" ว่าข้อมูลฝั่งเราไม่ตรงกับ server (ดู unlockIsland ข้างล่าง)
local NO_ACTIVE_QUEST = "You do not have an active quest!"

--- id ของเควสต์ที่กำลังทำอยู่ตอนนี้ (nil = ไม่มี)
---   ที่มา: QuestController.lua:737-738 / 1058-1059 อ่าน data.Quest.Current.Id เหมือนกัน
local function currentQuestId(d)
    local cur = d and d.Quest and d.Quest.Current
    local id = cur and cur.Id
    if type(id) == "string" and id ~= "" then return id end
    return nil
end

--- ยกเลิกเควสต์อื่นที่ค้างอยู่ — server ตอบ "You are already on another quest!" ถ้ายังมีค้าง
---   คืน true ถ้าหลังยกเลิกแล้วไม่มีเควสต์ค้าง (หรือไม่ต้องยกเลิกอยู่แล้ว)
local function clearOtherQuest(questId, d)
    local curId = currentQuestId(d)
    if not curId or curId == questId then return true end
    local ok, res = pcall(function() return QuestCtl:Cancel(curId) end)
    if not ok or not res then return false end
    -- รอให้ข้อมูล replicate กลับมา: วนอ่านสถานะจริงจนว่างจริง ไม่ใช่รอเวลาตายตัว
    local cleared = pollUntil(function()
        return currentQuestId(fetchData() or d) == nil
    end, 2, 0.1)
    if cleared then return true end
    logWarn(("[Prog] ยกเลิกเควสต์ %s แล้วแต่ข้อมูลยังไม่ว่างหลัง 2s — ค่อยเช็คใหม่รอบหน้า"):format(tostring(curId)))
    return false
end

--- รับเควสต์ให้เป็นเควสต์ที่กำลังทำอยู่ (idempotent — ถ้ารับอยู่แล้วคืน true ทันที)
---   force = true = ไม่เชื่อข้อมูลฝั่ง client ยิง Accept ทันที
---
--- ⚠ เดิมผลของ Accept ถูก "ทิ้งทิ้ง":
---       local okA, errA = pcall(function() return QuestCtl:Accept(questId) end)
---       if not okA then ... end
---   `okA` คือผลของ pcall (true เสมอ) ไม่ใช่ผลของ Accept
---   -> ตอน Accept ล้มเหลว เรายังเดินไปเรียก Complete ต่อทันที
---   -> แล้วได้ข้อความหลอกๆ ว่า "You do not have an active quest!"
---   ตอนนี้เช็คผลของ Accept จริง ๆ และคืนเหตุผลที่ล้มเหลวกลับไปด้วย
local function ensureQuestAccepted(questId, d, force)
    if not force and currentQuestId(d) == questId then return true end
    if not clearOtherQuest(questId, d) then
        return false, "ยกเลิกเควสต์เดิมไม่ได้ (อาจมีเควสต์อื่นค้างอยู่)"
    end
    local ok, acc, err = pcall(function() return QuestCtl:Accept(questId) end)
    if not ok then return false, "Accept error: " .. tostring(acc) end
    if not acc then return false, tostring(err) end
    -- ยืนยันว่าเควสต์นี้เป็นเควสต์ที่กำลังทำอยู่จริง ๆ (อ่านสด ไม่รอตายตัว)
    --   เดิมคืน true ทันทีหลัง Accept โดยไม่เคยดูว่า server รับจริงไหม
    if not force then
        local accepted = pollUntil(function()
            return currentQuestId(fetchData()) == questId
        end, 2, 0.1)
        if not accepted then
            return false, ("Accept แล้วแต่ %d วินาทีต่อมายังไม่เห็นเป็นเควสต์ปัจจุบัน"):format(2)
        end
    end
    return true
end

--- ปลดล็อกเกาะ — แทนการเดินไปคุย NPC ด้วย QuestController:Accept + :Complete
--- ⚠ server ตรวจทุกเงื่อนไขเอง (เหรียญ / เกาะก่อนหน้า / ปลาที่ต้องการ) รวมถึง "ระยะจาก NPC"
---   เราแค่ยิง packet ตามลำดับเดียวกับที่ dialogue ของเกมใช้
---   (npc_unlock_island_4.lua: QuestController:Accept(id) แล้ว :Complete(id))
---
--- ลำดับที่ใช้คือหน้า "All requirements met!" ของ npc_unlock_island_4.lua:126-186
---   ยังไม่มีเควสต์ -> Accept -> Complete
---   ถ้า Complete ตอบ NO_ACTIVE_QUEST = ข้อมูลฝั่งเราค้าง (เกิดบ่อยหลัง Cancel ที่รอ replicate แค่ 0.4s)
---      -> บังคับ Accept อีกครั้งแล้ว Complete ซ้ำ (dialogue:150-169 ทำแบบเดียวกัน)
function unlockIsland(islandId, data)
    local questId = UNLOCK_QUEST[islandId]
    if not (QuestCtl and questId) then
        logWarn(("[Prog] ปลดล็อก %s ไม่ได้ — ไม่มี QuestController/quest id"):format(islandTag(islandId)))
        return false
    end
    if not QuestCtl.Accept or not QuestCtl.Complete then
        logWarn("[Prog] QuestController ไม่มี Accept/Complete")
        return false
    end

    -- ⚠ ต้องยืนใกล้ NPC ปลดล็อกก่อนยิง packet — server ตรวจระยะเอง
    --   ผู้ใช้เจอจริง 2026-10-16: ยิงจากระยะไกว = "Move closer to Jungle Island Guide"
    --   approachUnlock แค่พาไปใกล้ NPC (อ่านลิมิตจาก QuestConfig.NpcDistance สด ๆ)
    --   และยิง packet ไม่ได้ = ยังตัดสินใจไม่ได้จริง ๆ แค่ยังไม่ถึงที่
    if not S.tools.approachUnlock(islandId) then
        logWarn(("[Prog] ไปใกล้ NPC ปลดล็อก %s ไม่สำเร็จ — ยังไม่ยิง packet")
            :format(islandTag(islandId)))
        return false
    end

    local okA, accOk, accErr = pcall(ensureQuestAccepted, questId, fetchData() or data)
    if not (okA and accOk) then
        logWarn(("[Prog] รับเควสต์ %s ไม่สำเร็จ: %s"):format(questId, tostring(okA and accErr or accOk)))
        return false
    end

    local function doComplete()
        local ok, res, err = pcall(function() return QuestCtl:Complete(questId) end)
        if not ok then return false, "Complete error: " .. tostring(res) end
        return res, err
    end

    local resC, errC = doComplete()
    if resC then S.tools.afterUnlockSpawn(islandId) return true end

    if tostring(errC) == NO_ACTIVE_QUEST then
        logWarn(("[Prog] %s: %s — ข้อมูลฝั่งเราไม่ตรงกับ server ยิง Accept ซ้ำ"):format(
            questId, tostring(errC)))
        local okF = ensureQuestAccepted(questId, fetchData(), true)
        if okF then resC, errC = doComplete() end
    end

    if resC then S.tools.afterUnlockSpawn(islandId) return true end
    logWarn(("[Prog] ปลดล็อก %s ไม่สำเร็จ: %s"):format(islandTag(islandId), tostring(errC)))
    return false
end

--- กด Complete ของเควสต์ทั่วไป (ใช้กับเควสต์เบ็ด — ไม่ใช่การปลดเกาะ)
---
--- ต่างจาก unlockIsland ตรงที่:
---   - ไม่ผูกกับ IslandConfig / UNLOCK_QUEST เลย (questId มาจาก CONFIG.Missions)
---   - เงินมาจาก Progress.RequiredCoin ของเควสต์นั้น ไม่ใช่ unlockCost ของเกาะ
---   - ต้องมีการปลดล็อกปลาที่ล็อคไว้ก่อน (เรียก releaseQuestFish เอง เพื่อไม่ลืม)
---   - รางวัลคือเบ็ดที่ server ให้มาเอง (Rewards.lua) -> ไม่ต้องซื้ออะไรเพิ่ม
---
--- ⚠ ฝั่ง client ไม่มีเช็คระยะ (ทุกเควสต์ใช้ packet เดียวกัน QuestController.lua:91
---   Packet("QuestPacket", String, String) ครอบ accept/cancel/complete) แต่ server เป็นคนเช็ก
---   หลักฐาน: unlockIsland เจอ "Move closer to ..." ด้วยตัวเอง (2026-10-16)
---   เควสต์เบ็ดยังไม่เจออาการนี้ = ยังพิสูจน์ไม่ได้ว่าไม่เช็ก (ดัมป์เป็นฝั่ง client ล้วน)
---   ทางออกมีอยู่แล้ว: rodMissionStep ยิงไม่ผ่านจะเดินไปหา NPC จริงแล้วลองซ้ำ
local function completeQuest(m, data)
    local questId = m and (m.targetRod or m.key)
    if not (QuestCtl and questId) then
        logWarn(("[Prog] กดเควสต์ %s ไม่ได้ — ไม่มี QuestController"):format(tostring(questId)))
        return false
    end
    if not (QuestCtl.Accept and QuestCtl.Complete) then
        logWarn("[Prog] QuestController ไม่มี Accept/Complete")
        return false
    end

    local okA, accOk, accErr = pcall(ensureQuestAccepted, questId, fetchData() or data)
    if not (okA and accOk) then
        logWarn(("[Prog] รับเควสต์ %s ไม่สำเร็จ: %s"):format(tostring(questId), tostring(okA and accErr or accOk)))
        return false
    end

    -- ปลาที่ล็อคไว้เกมนับไม่ได้ ("Locked fish do not count") -> ปลดก่อนเสมอ
    if not releaseQuestFish(m) then return false end

    local function doComplete()
        local ok, res, err = pcall(function() return QuestCtl:Complete(questId) end)
        if not ok then return false, "Complete error: " .. tostring(res) end
        return res, err
    end

    local res, err = doComplete()
    if res then return true end

    if tostring(err) == NO_ACTIVE_QUEST then
        -- ข้อมูลฝั่งเราไม่ตรงกับ server (เกิดบ่อยหลัง Cancel ที่รอ replicate แค่ 0.4s)
        local okF = ensureQuestAccepted(questId, fetchData(), true)
        if okF then res, err = doComplete() end
    end

    if res then return true end
    logWarn(("[Prog] เควสต์ %s ไม่สำเร็จ: %s"):format(tostring(questId), tostring(err)))
    return false
end

-- ══════════════════════════════════════════════════
-- 5) BEST ROD
-- ══════════════════════════════════════════════════
local function findBestRod(data)
    local rods = data and data.Rods
    if type(rods) ~= "table" then return nil end
    local bestId, bestAtk = nil, -math.huge
    for rodId, rodData in pairs(rods) do
        if type(rodData) == "table" then
            -- rodAtk มี pcall ข้างในแล้ว: เบ็ดในคลังที่ Catalog ไม่รู้จัก (ของเกมอัปเดต/สกินใหม่)
            --   ได้ atk = 0 ไม่ throw และไม่มีทางชนะตัวที่มีสถิติจริง
            -- ⚠ ส่ง data ไปด้วย: เบ็ดสาย Forge มีดาเมจอยู่ใน ForgedStats ไม่ใช่ใน Catalog
            local atk = rodAtk(rodId, data)
            if atk > bestAtk then bestAtk, bestId = atk, rodId end
        end
    end
    return bestId
end

local function equipRod(rodId)
    if not (EquipCtl and EquipCtl.EquipmentEquip) then
        logWarn("[Prog] ไม่มี EquipmentEquip packet")
        return false
    end
    local ok, res = pcall(function() return EquipCtl.EquipmentEquip:Fire("rod", rodId) end)
    if ok and res then return true end
    logWarn(("[Prog] equip rod %s ตอบ %s"):format(rodId, tostring(res)))
    return false
end

-- ══════════════════════════════════════════════════
-- 6) BEST SKILL INTO ROD (slot gate + defer)
-- ══════════════════════════════════════════════════
local function skillPriority(meta)
    if not meta then return 0 end
    if meta.kind == "Buff" then
        local effect = meta.effect
        if effect and effect.type == "NextSkillDamagePct" then
            return 1000 + (effect.value or 0)
        end
        return 900
    end
    return (meta.damageCoef or 0)
end

--- จำนวนสำเนาที่ "ยังใส่ได้" ของสกิลนี้ (อ่านจากตัวช่วยของเกมเอง)
--- ──────────────────────────────────────────────────
--- ⚠ ต้องหักสำเนาที่ใส่ไว้ใน "ทุกเบ็ด" ไม่ใช่แค่เบ็ดที่ติดตั้ง
---   เกมมี skillBookAvailability.GetCounts อยู่แล้ว (Utils/skillBookAvailability.lua:24)
---   คืน available = max(0, owned - จำนวนสำเนาที่ใส่อยู่ทั้งหมด)
---   ถ้าไม่หัก -> เราจะสั่ง EquipMoveset ซ้ำ ๆ แล้วโดนเด้งกลับมาเงียบ ๆ
local function availableSkillCopies(data, skillId)
    if SkillBookAvail and type(SkillBookAvail.GetCounts) == "function" then
        local ok, r = pcall(function() return SkillBookAvail.GetCounts(data, skillId) end)
        if ok and type(r) == "table" and type(r.available) == "number" then
            return r.available
        end
    end
    -- fallback: คำนวณเองจากข้อมูล (กรณีโมดูลของเกมหายไป)
    local inv = invOf(data)
    local books = inv and inv.Books
    local owned = (type(books) == "table" and books[skillId]) or 0
    if type(owned) ~= "number" or owned < 0 then owned = 0 end
    local used = 0
    for _, rd in pairs(data.Rods or {}) do
        for _, s in pairs((type(rd) == "table" and rd.BookSlots) or {}) do
            if s == skillId then used = used + 1 end
        end
    end
    return math.max(0, math.floor(owned) - used)
end

--- สถานะช่องสกิลของเบ็ดที่ติดตั้งอยู่ ณ ตอนนี้ (อ่านจากข้อมูลเกมตรง ๆ)
--- คืน { total, level, empty = {i..}, locked = {i..} }
---   empty  = ช่องที่ปลดล็อกแล้วแต่ยังว่าง  -> ต้องใส่ให้ครบ
---   locked = ช่องที่ยังไม่ถึงเลเวล      -> เดี๋ยวคอยเช็คตอนเลเวลถึง
local function rodSlotState(data, rodId)
    local meta = Catalog and Catalog.Rod and Catalog.Rod.GetById and Catalog.Rod.GetById(rodId)
    if not meta then return nil end
    local total = meta.skillSlots or 0
    local unlocks = meta.slotUnlockLevels or {}
    local rodData = data.Rods and data.Rods[rodId]
    local level = 1
    if getLevel and getLevel.getLevel then
        local okLv, lv = pcall(function() return getLevel.getLevel(rodData and rodData.MasteryXp or 0) end)
        if okLv and type(lv) == "number" then level = lv end
    end
    local slots = (type(rodData) == "table" and rodData.BookSlots) or {}
    local empty, locked = {}, {}
    for i = 1, total do
        local need = unlocks[i]
        if need ~= nil and need > level then
            locked[#locked + 1] = i
        else
            local cur = slots[("Slot%d"):format(i)]
            if cur == nil or cur == "" then empty[#empty + 1] = i end
        end
    end
    return { total = total, level = level, empty = empty, locked = locked }
end

--- รายการสกิลที่ "ยังใส่ได้" เรียงตามความสำคัญ (ดีสุดก่อน)
--- ใส่ซ้ำตามจำนวนสำเนาที่เหลือ -> ถ้ามีสกิลดี 2 เล่มในช่องว่าง 3 ช่องก็ใส่ซ้ำได้
local function rankedAvailableSkills(data)
    local books = ownedSkills(data)
    -- ⚠ pairs() ไม่การันตีลำดับ และ table.sort ก็ไม่ stable
    --   ถ้าไม่เรียง skillId ก่อน ลำดับสกิลที่คะแนนเท่ากันจะสุ่มใหม่ทุกครั้งที่รันสคริปต์
    --   -> ชุดสกิลที่ใส่ในช่องจะต่างกันทุกรอบ ทั้งที่ของเหมือนกัน
    local ids = {}
    for skillId in pairs(books) do ids[#ids + 1] = skillId end
    table.sort(ids)

    local list = {}
    for _, skillId in ipairs(ids) do
        -- ⚠ book ที่จองไว้ให้ Forge ห้ามใส่ลงเบ็ด
        --   RodForgeRules.findMythicalBook นับเฉพาะเล่มที่ available > 0
        --   ถ้าใส่กลับลงเบ็ด = available กลายเป็น 0 = forge Diamond Dragon ไม่มีวัน ready
        if skillId ~= S.forgeBook then
            local avail = availableSkillCopies(data, skillId)
            if avail > 0 then
                local meta = Catalog and Catalog.Skill and Catalog.Skill.GetById
                    and Catalog.Skill.GetById(skillId)
                local score = skillPriority(meta)
                for _ = 1, avail do
                    list[#list + 1] = { id = skillId, score = score }
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.id < b.id        -- สำเนาซ้ำของ id เดียวกันเท่ากันทุกตัว เทียบกันได้
    end)
    return list
end

--- สกิลตัวนี้ถูกใส่อยู่ที่ไหนบ้าง ณ ตอนนี้ (อ่านจากทุกเบ็ดในข้อมูลเกม)
--- คืน { rodId = slotIndex } หรือ {} = ไม่มีที่ไหนเลย
function S.tools.whereSkillLives(data, skillId)
    local out = {}
    if type(data) ~= "table" or type(data.Rods) ~= "table" then return out end
    for rid, rd in pairs(data.Rods) do
        local slots = (type(rd) == "table" and rd.BookSlots) or nil
        if type(slots) == "table" then
            for key, v in pairs(slots) do
                if v == skillId then
                    out[rid] = tonumber(tostring(key):match("^Slot(%d+)$")) or tostring(key)
                end
            end
        end
    end
    return out
end

--- ลายเซ็นของ "ชุดอุปกรณ์ทั้งหมด" = เบ็ดที่ใส่ + สกิลทุกช่อง + เลเวล + จำนวนเล่มในคลัง
--- ใช้เป็นเงื่อนไข "มีอะไรเปลี่ยนจริงไหม" — ไม่เกี่ยวกับเวลาเลย
--- ⚠ ใส่ "เลเวล" ไม่ใช่ "MasteryXp" เพราะ XP ขยับทุกตัวที่จับ
---   ถ้าใส่ XP ลายเซ็นจะเปลี่ยนทุกรอบ = ประตูจะไม่มีวันปิด
function S.tools.loadoutSignature(data)
    if type(data) ~= "table" then return "nodata" end
    local rods = (type(data.Rods) == "table") and data.Rods or {}
    local t = { tostring(data.RodEquip or "-") }
    local ids = {}
    for rid in pairs(rods) do ids[#ids + 1] = rid end
    table.sort(ids)
    for _, rid in ipairs(ids) do
        local rd = rods[rid]
        local sl = (type(rd) == "table" and rd.BookSlots) or {}
        local keys = {}
        for k in pairs(sl) do keys[#keys + 1] = k end
        table.sort(keys)
        local parts = {}
        for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. tostring(sl[k]) end
        t[#t + 1] = rid .. "[" .. table.concat(parts, ",") .. "]"
    end
    -- เลเวลของเบ็ดที่ใส่อยู่ = เลเวลที่ขึ้นแล้วช่องสกิลจะเพิ่ม = ต้องลองใส่ใหม่
    local rd0 = rods[data.RodEquip]
    local lv = 1
    if getLevel and getLevel.getLevel then
        local okLv, v = pcall(function()
            return getLevel.getLevel((type(rd0) == "table" and rd0.MasteryXp) or 0)
        end)
        if okLv and type(v) == "number" then lv = v end
    end
    t[#t + 1] = "lv=" .. tostring(lv)
    local books = (type(invOf(data)) == "table" and invOf(data).Books) or {}
    local bk = {}
    for k, v in pairs(books) do bk[#bk + 1] = tostring(k) .. "=" .. tostring(v) end
    table.sort(bk)
    t[#t + 1] = "books[" .. table.concat(bk, ",") .. "]"
    return table.concat(t, "|")
end

local function equipSkill(skillId, slotIndex, rodId)
    -- ค่าในช่องนี้ ณ ตอนนี้ (อ่านจากข้อมูลเกม ไม่เดา) — local ข้างในเพราะมีผู้เรียกคนเดียว
    --   ไม่ต้องกินโควตา local ระดับบน (Lua จำกัด 200 ตัว/ฟังก์ชัน และไฟล์นี้เต็มแล้ว)
    local function slotNow()
        local d = fetchData()
        local rd = (type(d) == "table" and type(d.Rods) == "table") and d.Rods[rodId] or nil
        local sl = (type(rd) == "table" and rd.BookSlots) or nil
        if type(sl) ~= "table" then return nil end
        return sl[("Slot%d"):format(tonumber(slotIndex) or 0)]
    end

    if not (EquipCtl and EquipCtl.EquipMoveset) then
        logWarn("[Prog] ไม่มี EquipMoveset packet")
        return false, "no-packet"
    end
    -- ⚠ ห้ามเชื่อ res == "Success" อย่างเดียว (ผู้ใช้สั่ง 2026-10-16)
    --   หลักฐานจากล็อกรอบ 15:46-18:17: ยิง rod_gate_close ลงช่อง 2 ได้
    --   "already equipped on another slot!" แล้วรอบถัดไป availableSkillCopies
    --   กลายเป็น 0 ตรงหลังยิง = จำนวนช่องที่ถือสกิลนั้นเพิ่มขึ้น 1
    --   แปลว่าเซิร์ฟวางจริง แต่ตอบกลับเป็น error
    --   เดิมเชื่อคำตอบ = คิดว่ายังไม่สำเร็จ -> ยิงซ้ำ ~500 ครั้งใน 48 นาที
    --   ตอนนี้อ่าน BookSlots ที่เกม replicate กลับมาหลัง Fire = คำตอบของเกม ไม่ใช่ของเรา
    local ok, res = pcall(function() return EquipCtl.EquipMoveset:Fire(skillId, slotIndex) end)
    if not ok then
        logWarn(("[Prog] EquipMoveset(%s, %d) -> ยิงไม่ผ่าน (%s)")
            :format(skillId, slotIndex, tostring(res)))
        return false, tostring(res)
    end
    local after = rodId and slotNow() or nil
    if after == skillId then
        if res ~= "Success" and (CONFIG.Log or {}).SkillFail then
            logWarn(("[Prog] EquipMoveset(%s, %d) ตอบ '%s' แต่ช่องเป็น %s แล้ว = สำเร็จ (เชื่อข้อมูลเกม)")
                :format(skillId, slotIndex, tostring(res), tostring(after)))
        end
        return true, nil
    end
    -- ล้มจริง: บอกให้ชัดว่าสกิลนี้อยู่ที่ไหนตอนนี้ (อ่านจากเกม ไม่เดากฎของเซิร์ฟ)
    local where = S.tools.whereSkillLives(fetchData(), skillId)
    local t = {}
    for rid, sl in pairs(where) do t[#t + 1] = ("%s#%s"):format(tostring(rid), tostring(sl)) end
    table.sort(t)
    logWarn(("[Prog] EquipMoveset(%s, %d) -> %s · ช่องยังเป็น '%s' · สกิลนี้อยู่ที่ %s")
        :format(skillId, slotIndex, tostring(res), tostring(after),
            (#t > 0) and table.concat(t, ", ") or "ไม่มีที่ไหนเลย"))
    return false, tostring(res)
end

--- ใส่สกิลให้เต็มทุกช่องที่ปลดล็อกแล้วของเบ็ดที่ติดตั้งอยู่
--- ──────────────────────────────────────────────────
--- เดิมใส่แค่ "สกิลดีที่สุด 1 ตัว ลง slot แรกที่ว่าง" -> เบ็ดที่ใส่ได้ 3 ช่องแต่มีแค่ 1 ก็ค้าง
--- ตอนนี้: ไล่ใส่ทีละช่องจนกว่าทุกช่องที่ปลดล็อกจะมีสกิล
---
--- คืน true = เต็มแล้ว (ไม่เหลือช่องว่างที่ปลดล็อก)
--- ⚠ caller ต้องเรียกทุกรอบ ไม่มีเงื่อนไข gate ที่ caller
---   เพราะการเปลี่ยนเบ็ดคือการเปลี่ยนตัวแปรที่ต้องอ่านค่าก่อนถึงจะรู้ว่าเปลี่ยน
---   การหยุดเกิดจากการอ่านสถานะจริงข้างใน (ช่องว่าง = 0 -> return true ก่อนยิง packet ใด ๆ)
local function tryEquipAllSkills()
    local data = fetchData()
    if not data then return false end

    local rodId = data.RodEquip
    if not rodId or rodId == "" or rodId == "None" then return false end

    local st = rodSlotState(data, rodId)
    if not st then return false end

    -- เตือนครั้งเดียว: ช่องที่ยังไม่ถึง mastery level = ยิงไม่ได้จนกว่าจะอัปเลเวล
    --   ผลจาก skill_rate_test: ยิงได้แค่ Slot1/Slot2 เพราะเบ็ดที่ใส่อยู่ปลดล็อกแค่ 2 ช่อง
    --   ตัวเลขนี้มีผลตรงกับอัตรายิงสกิลพอดี -> ต้องเห็นให้ชัด ไม่ใช่เงียบ ๆ ไปกับเกม
    if #st.locked > 0 then
        local key = ("%s#%s#%d"):format(tostring(rodId), table.concat(st.locked, ","), st.level)
        if S.warnedLockedSlot ~= key then
            S.warnedLockedSlot = key
            local need = {}
            for _, i in ipairs(st.locked) do
                need[#need + 1] = tostring(((Catalog.Rod.GetById(rodId).slotUnlockLevels or {})[i]) or "?")
            end
            logWarn(("[Prog] 🎣 เบ็ด %s มี %d ช่องสกิล แต่ปลดล็อกได้แค่ %d — ช่องที่ยังล็อกคือ %s "
                .. "(ต้องมี Mastery เลเวล %s) ตอนนี้ Mastery เลเวล %d")
                :format(tostring(rodId), st.total, st.total - #st.locked,
                    table.concat(st.locked, ","), table.concat(need, "/"), st.level))
        end
    end

    -- ⚠ ห้ามหยุดที่ "#st.empty == 0" อีกแล้ว (ผู้ใช้สั่ง 2026-10-16)
    --   เดิมคืนทันที = เบ็ดที่เต็มด้วยสกิลธรรมดาจะถูกปล่อยไปตลอด ไม่มีทางอัปเกรด
    --   ทีนี้ทุกช่องที่ปลดล็อกแล้วต้องได้สกิลที่ดีที่สุดที่หาได้
    local sig = S.tools.loadoutSignature(data)
    -- ⚠ ล้มไปแล้วและสถานะยังเหมือนเดิม = ยิงซ้ำไม่มีทางได้ผลต่าง
    --   เงื่อนไขนี้มาจาก state ของเกม ไม่ใช่จากนาฬิกา (ห้ามนับเวลาเอง)
    if S.skillBlock[rodId] and S.skillBlock[rodId][sig] then return false end
    S.skillBlock[rodId] = {}

    local pool = rankedAvailableSkills(data)
    -- ยังมีช่องว่างแต่ไม่มีสกิลที่ยังใส่ได้ (ของที่มีใส่ไปหมดแล้ว) -> คอยเช็คต่อไปเรื่อย ๆ เผื่อสุ่มได้สกิลใหม่
    if #pool == 0 then return false end

    -- ⚠ กติกาจริง (ผู้ใช้ทดสอบในเกมเอง 2026-10-16): ใส่สกิลตัวเดิมซ้ำในเบ็ดใบเดียวกัน
    --   ไม่ได้ — เซิร์ฟตอบ "This skill is already equipped on another slot!"
    --   = ตัดออกตั้งแต่ตอนเลือก ไม่ใช่ค่อยหยิบมาเจอแล้วค่อยข้ามทีหลัง
    --
    -- ⚠ เหตุผลที่ต้องตัด "ตั้งแต่ต้น" ไม่ใช่ค่อยข้ามในลูป:
    --   ถ้ามาข้ามทีหลัง ตัวชี้รายการจะเดินหน้าทีละก้าว "ทั้งที่ใส่ไม่ได้"
    --   ผลคือสกิลที่ใส่ได้จริงซึ่งอยู่ท้ายรายการถูกกลืนหาย
    --   (เคยเจอ: ช่องว่าง 2 ช่อง + A อยู่เบ็ดนี้แล้ว + A ซ้ำ 2 ตัวในรายการ
    --    = ทั้ง 2 ช่องว่าง แม้ B กับ C เอามาใส่ได้)
    --
    -- ⚠ เหลือ id เดียวต่อเบ็ด 1 ครั้ง: สำเนาที่ 2 ของสกิลเดียวกันใส่ซ้ำไม่ได้อยู่แล้ว
    --   = ไม่ต้องเช็คซ้ำในลูป เพราะรายการหลังกรองแล้วไม่มี id ซ้ำกัน
    local used, failReason, skipped, seen = 0, nil, {}, {}
    local keep = {}
    for _, e in ipairs(pool) do
        local where = S.tools.whereSkillLives(data, e.id)[rodId]
        if where ~= nil then
            if not seen[e.id] then
                seen[e.id] = true
                skipped[#skipped + 1] = ("%s(อยู่ช่อง %s ของเบ็ดนี้)")
                    :format(tostring(e.id), tostring(where))
            end
        elseif not seen[e.id] then
            seen[e.id] = true
            keep[#keep + 1] = e
        end
    end
    pool = keep

    -- ⚠ helper ทั้งหมดในสามบรรทัดนี้เป็น local ของฟังก์ชันนี้
    --   เพราะไฟล์ชนเพดาน 200 local ระดับบนแล้ว = ห้ามประกาศเพิ่มที่ระดับไฟล์
    --
    -- ⚠ คะแนนของสกิลที่ "ใส่อยู่แล้ว" ต้องคำนวณเอง ห้ามดึงจากรายการข้างบน
    --   เพราะสกิลที่เรามีเล่มเดียวและใส่ไปแล้ว จะไม่โผล่ในรายการนั้นเลย
    --   (availableSkillCopies หัก "สำเนาที่ใส่อยู่" ออก) -> ได้ nil
    --   แล้วถือว่าของที่ใส่อยู่แย่ที่สุด = ถอดทิ้งทั้งที่มันดีที่สุดอยู่แล้ว
    local function scoreOf(skillId)
        if not skillId then return 0 end
        local meta = nil
        if Catalog and Catalog.Skill and Catalog.Skill.GetById then
            pcall(function() meta = Catalog.Skill.GetById(skillId) end)
        end
        return skillPriority(meta)          -- meta = nil -> 0
    end

    --- อ่านสกิลที่อยู่ในช่อง i ของเบ็ดที่กำลังใส่ (nil = ว่าง) จาก data ที่ผ่านเข้ามา
    local function slotAt(d, i)
        local rd = (type(d) == "table" and type(d.Rods) == "table") and d.Rods[rodId] or nil
        local sl = (type(rd) == "table" and rd.BookSlots) or nil
        if type(sl) ~= "table" then return nil end
        local v = sl[("Slot%d"):format(i)]
        if type(v) == "string" and v ~= "" then return v end
        return nil
    end

    --- ปลดสกิลออกจากชองเดียว — ยิงค่าว่าง แล้วเชื่อ BookSlots ที่เกมส่งกลับ (ไม่เชื่อ "Success")
    ---   ⚠ EquipMoveset แก้ได้แค่เบ็ดที่ติดตั้งอยู่ (อ่าน data.RodEquip ฝั่งเซิร์ฟ)
    ---   ⚠ เป็น :Response packet = ต้องเว้นหนึ่งเฟรมระหว่างยิงสองครั้ง
    local function unequipOne(i)
        if not (EquipCtl and EquipCtl.EquipMoveset) then return false, "no-packet" end
        local before = slotAt(fetchData() or data, i)
        if not before then return true, nil end      -- ว่างอยู่แล้ว = ไม่ต้องยิง
        local ok, res = pcall(function() return EquipCtl.EquipMoveset:Fire("", i) end)
        if not ok then return false, tostring(res) end
        local after = slotAt(fetchData() or data, i)
        if after == nil then return true, nil end
        logWarn(("[Prog] EquipMoveset(\"\", %d) -> %s · ช่องยังเป็น '%s'")
            :format(i, tostring(res), tostring(after)))
        return false, tostring(res)
    end

    -- ── เฟส 1: อ่านอย่างเดียว — ช่องไหนต้องถูกถอด ──────────────────────
    --   เดินช่องเรียงจากน้อยไปมาก = ตรงกับลำดับที่ equipSkill ใช้
    local lockedAt = {}
    for _, i in ipairs(st.locked) do lockedAt[i] = true end

    local placed, drop = {}, {}
    for i = 1, (st.total or 0) do
        if not lockedAt[i] then
            local have = slotAt(data, i)
            -- ตัวที่ดีที่สุดที่ยังไม่ถูกจับไว้ที่ช่องอื่น
            local best, bestScore
            for _, e in ipairs(pool) do
                if not placed[e.id] then best, bestScore = e.id, e.score break end
            end
            if have == nil then
                if best then placed[best] = true end          -- ว่าง = เตรมด้วยของดีสุด
            elseif best ~= nil and have ~= best and bestScore > scoreOf(have) then
                drop[#drop + 1] = i                            -- ของเดิมแย่กว่า = ถอด
                placed[best] = true
            else
                placed[have] = true                            -- คงของเดิมไว้
            end
        end
    end

    -- ── เฟส 2: ถอด (ถ้ามี) ────────────────────────────────────────────
    --   ⚠ ถอดก่อนใส่เสมอ: EquipMoveset เป็น :Response = ยิงสองใบติดกัน
    --   เซิร์ฟอาจตัดใบหลังทิ้ง และชั่งเวลาตอน :Wait ถูกหน่วงที่เซิร์ฟ (6-7 วิ)
    --   = ยิงทีเดียว (ถอด+ใส่รวด) จะโดน IsUsingSkill บล็อกทั้งเฟส
    local used, failReason = 0, nil
    for _, idx in ipairs(drop) do
        local ok, err = unequipOne(idx)
        if not ok then
            S.skillFail = (S.skillFail or 0) + 1
            failReason = ("ปลดช่อง %d: %s"):format(idx, tostring(err))
            break
        end
        task.wait()      -- เว้นหนึ่งเฟรมก่อนยิงใบถัดไป (เหมือนเกมและ unequipRodSkills)
    end

    if failReason then
        S.skillBlock[rodId] = { [sig] = true }
        logWarn("[Prog] SKILL: " .. tostring(failReason)
            .. " (ช่องยังเหมือนเดิม = ไม่ยิงซ้ำจนกว่าเกมเปลี่ยน) · รอบนี้ตกปลาต่อปกติ")
        return false
    end

    -- ⚠ อ่านข้อมูลใหม่หลังถอด: สำเนาของ id ที่ถอด "เพิ่มขึ้น 1" ตอนนี้
    --   ถ้าไม่อ่านใหม่ รายการที่เหลือจะยังไม่เห็นสำเนาที่เพิ่งคืนมา = ช่องว่างท้าย ๆ ค้าง
    if #drop > 0 then
        data = fetchData() or data
        sig = S.tools.loadoutSignature(data)
    end

    -- ── เฟส 3: วางแผนใส่จากข้อมูลที่เพิ่งอ่านใหม่ ────────────────────
    --   ทำให้สำเนาที่เพิ่งถอดคืนมาถูกใช้ในรอบเดียวกัน (ไม่ต้องรอรอบหน้า)
    local rd1 = (type(data) == "table" and type(data.Rods) == "table") and data.Rods[rodId] or nil
    local sl1 = (type(rd1) == "table" and rd1.BookSlots) or {}
    local fill, taken = {}, {}
    for i = 1, (st.total or 0) do
        if not lockedAt[i] then
            local v = sl1[("Slot%d"):format(i)]
            local have = (type(v) == "string" and v ~= "") and v or nil
            if have then
                taken[have] = true
            else
                for _, e in ipairs(pool) do
                    if not taken[e.id] then
                        taken[e.id] = true
                        fill[#fill + 1] = { idx = i, id = e.id }
                        break
                    end
                end
            end
        end
    end

    -- ── เฟส 4: ใส่ ──────────────────────────────────────────────────
    for _, f in ipairs(fill) do
        local ok, err = equipSkill(f.id, f.idx, rodId)
        if not ok then
            -- ใส่ไม่ผ่าน = เบ็ดอาจถูกสลับไปแล้ว หรือช่องนี้เพิ่งถูกล็อก/ถูกจองไป
            -- หยุดรอบนี้ทันที: ช่องที่เหลือคำนวณจาก slot ของ "เบ็ดเก่า" อยู่
            --   ถ้ายิงต่อจะไปโดนช่องผิดของเบ็ดใหม่ (รอบหน้าค่อยอ่านใหม่แล้วแก้)
            S.skillFail = (S.skillFail or 0) + 1
            failReason = err
            break
        end
        used = used + 1
    end

    if failReason then
        -- ⚠ จำ "สถานะตอนที่ล้ม" ไว้ ต้องเปลี่ยนจริงถึงจะลองใหม่
        S.skillBlock[rodId] = { [sig] = true }
        -- ⚠ ข้อความเดิมบอกว่า "หยุดรอบนี้" ซึ่งไม่จริง — คนเรียกตั้งใจให้ค่าคืน
        --   ตกปลายังเดินต่อ และไม่ควรหยุดเพราะใส่สกิลไม่ขึ้น
        logWarn(("[Prog] SKILL: ใส่ %s ไม่สำเร็จ (ช่องยังเหมือนเดิม = ไม่ยิงซ้ำจนกว่าเกมเปลี่ยน) "
                .. "· รอบนี้ตกปลาต่อปกติ"):format(tostring(failReason)))
    elseif (used > 0 or #drop > 0 or #skipped > 0) and (CONFIG.Log or {}).SkillFail then
        local said = {}
        if used > 0 then said[#said + 1] = ("ใส่ %d ช่อง"):format(used) end
        if #drop > 0 then said[#said + 1] = ("ถอด %d ช่องที่แย่กว่า"):format(#drop) end
        if #skipped > 0 then
            said[#said + 1] = "ข้าม " .. table.concat(skipped, ", ")
                .. " (อยู่เบ็ดนี้แล้ว = ใส่ซ้ำในเบ็ดเดียวกันไม่ได้)"
        end
        logWarn("[Prog] SKILL: " .. table.concat(said, " · "))
    end
    return false
end

-- ══════════════════════════════════════════════════
--- ปลดสกิลออกจากเบ็ดที่กำลังใส่อยู่ ทุกช่อง
--- ──────────────────────────────────────────────────────────
--- ⚠ EquipMoveset ไม่มีพารามิเตอร์ rodId — server รู้จักแค่ "เบ็ดที่ติดตั้งอยู่"
---   (EquipmentController:_ResolveBookSlots:1595 อ่าน data.RodEquip เป็นตัวเลือกช่อง)
---   = ปลดได้เฉพาะเบ็ดที่กำลังใส่อยู่เท่านั้น ถ้าจะย้ายไปเบ็ดอื่นต้องปลดก่อนสลับ
---
--- ⚠ ทำไมต้องปลดก่อนสลับ: availableSkillCopies หัก "จำนวนสกิลที่ใส่อยู่ในทุกเบ็ด"
---   ถ้าปล่อยสกิลค้างในเบ็ดเก่า ตัวนับจะเห็นว่าสกิลนั้นถูกใช้ไปแล้ว
---   -> เบ็ดใหม่จะเลยไม่มีสกิลให้ใส่ในช่องที่ว่าง
---
--- ⚠ ข้อจำกัดของเกม: ปลดได้แค่เบ็ดที่ติดตั้งอยู่เท่านั้น
---   ฟังก์ชันนี้จึง "ไม่ตรวจ" ว่าตัวเองถือเบ็ดใบที่ส่งมาหรือเปล่า — เชื่อผู้เรียก
---   (ผู้เรียกต้องเป็นคนสลับมาก่อนด้วย switchToRod เสมอ)
---
--- คืน true ถ้าไม่มีสกิลติดอยู่ หรือปลดครบทุกช่องแล้ว
local function unequipRodSkills(data, rodId)
    if rodId == nil or rodId == "" or rodId == "None" then return true end
    if not (EquipCtl and EquipCtl.EquipMoveset) then
        logWarn("[Prog] ไม่มี EquipMoveset packet — ปลดสกิลไม่ได้")
        return false
    end

    -- ช่องที่ "มี" สกิลอยู่จริง (อ่าน BookSlots ตรง ๆ ไม่ต้องคิด level/slotUnlockLevels
    --   เพราะเราจะปลดทุกอย่างที่ติดอยู่ ไม่ต้องเลือกเฉพาะช่องที่ปลดล็อก)
    local used = {}
    local cur = (type(data.Rods) == "table" and data.Rods[rodId]) or nil
    local slots = (type(cur) == "table" and cur.BookSlots) or nil
    if type(slots) == "table" then
        for key, v in pairs(slots) do
            if type(v) == "string" and v ~= "" then
                local idx = tonumber(tostring(key):match("^Slot(%d+)$"))
                if idx then used[#used + 1] = idx end
            end
        end
    end
    if #used == 0 then return true end
    table.sort(used)

    for _, idx in ipairs(used) do
        -- ค่าว่าง = ปลด (เกมทำแบบนี้ตอนกดสกิลที่ใส่อยู่ซ้ำ — EquipmentController:2030)
        local ok, res = pcall(function() return EquipCtl.EquipMoveset:Fire("", idx) end)
        if not ok or res ~= "Success" then
            logWarn(("[Prog] ปลดสกิลช่อง %d ของ %s ไม่สำเร็จ -> %s")
                :format(idx, tostring(rodId), tostring(res)))
            return false
        end
        -- ⚠ ไม่ต้องหน่วงหลัง Fire: EquipMoveset เป็น :Response(Packet.String)
        --   = Fire คืนค่าก็คือรอคำตอบ server จบแล้ว (EquipmentController:83)
        --   เกมเองก็ยิงทีละอันผ่าน Skills.inFlight (EquipmentController:2044)
        --   เหลือแค่ yield ให้เฟรมไม่ค้าง ถ้าจะยิงซ้ำต่อให้เร็วกว่านี้ต้องระวังด้วย
        task.wait()
    end

    -- ยืนยันกับข้อมูลจริงว่าว่างครบ (ไม่เชื่อแค่คำตอบ "Success")
    --   เช็ครอบแรกก่อนรอเสมอ: replicate มักมาถึงตอน Fire คืนค่าพอดี
    local t0 = os.clock()
    repeat
        local d = fetchData()
        local rd = (d and type(d.Rods) == "table" and d.Rods[rodId]) or nil
        local live = (type(rd) == "table" and rd.BookSlots) or {}
        local left = 0
        for _, v in pairs(live) do
            if type(v) == "string" and v ~= "" then left = left + 1 end
        end
        if left == 0 then return true end
        task.wait(0.05)
    until os.clock() - t0 >= 2
    logWarn(("[Prog] ปลดสกิลใน %s ไม่หมดในเวลาที่กำหนด — ยังสลับเบ็ดต่อ"):format(tostring(rodId)))
    return false
end

-- ══════════════════════════════════════════════════
-- 6b) BEST LOADOUT (เบ็ดดีที่สุดในกระเป๋า + สกิลดีที่สุดในช่องว่าง)
-- ══════════════════════════════════════════════════
--- เบ็ดในคลังที่ยังมีสกิลติดอยู่ — อ่านจากข้อมูลเกมล้วน ไม่ยิง packet ใด ๆ
--- ⚠ excludeRod = เบ็ดเป้าหมายที่เราจะใช้ต่อ (ต้องมีสกิลติดอยู่ = ปกติ ไม่ใช่สิ่งที่ต้องแก้)
---   ถ้าไม่ตัดออก: ทุกรอบ poll จะไปถอดสกิลที่ใส่ไว้ดี ๆ แล้วต้องใส่กลับ = ยิง packet วนไม่จบ
local function rodsHoldingSkills(data, excludeRod)
    local out = {}
    if type(data.Rods) ~= "table" then return out end
    for rodId, rd in pairs(data.Rods) do
        if rodId ~= excludeRod and type(rd) == "table" and type(rd.BookSlots) == "table" then
            for _, v in pairs(rd.BookSlots) do
                if type(v) == "string" and v ~= "" then
                    out[#out + 1] = rodId
                    break
                end
            end
        end
    end
    return out
end

--- สลับไปใส่เบ็ดใบนี้ แล้วรอจน data.RodEquip เปลี่ยนจริง
--- คืน true เมื่อเซิร์ฟเวอร์ยืนยันว่าเป็นเบ็ดใบนี้แล้ว
local function switchToRod(rodId)
    local d = fetchData()
    if not d then return false end
    if d.RodEquip == rodId then return true end
    if not equipRod(rodId) then return false end
    -- ⚠ EquipmentEquip เป็น :Response(Packet.Boolean8) = Fire คืนค่าคือรอ server แล้ว
    --   (EquipmentController:85) ข้อมูลมัก replicate ถึงตอนนี้พอดี
    --   เช็ครอบแรกก่อนรอเสมอ แล้วค่อยไล่หยุดถี่ลง
    local t0 = os.clock()
    repeat
        local x = fetchData()
        if x and x.RodEquip == rodId then return true end
        task.wait(0.03)
    until os.clock() - t0 >= 2
    return false
end

--- ทำให้แน่ใจว่ากำลังใช้เบ็ดที่ดีที่สุดที่มีในกระเป๋า และสกิลอยู่ครบแค่เบ็ดใบเดียว
---
--- @param waitRod string|nil เบ็ดที่เพิ่งซื้อมา — ถ้าระบุ จะรอจนกว่าข้อมูลจะ replicate มาจริง
---   (เพิ่งยิง PurchaseRod เสร็จ data.Rods ยังไม่มีเบ็ดใหม่ ถ้าไม่รอจะเลือกเบ็ดเก่าไปติด)
---
--- ⚠ ไม่ต้อง gate ที่ caller: "เบ็ดที่ดีที่สุด" เปลี่ยนได้ตลอดเวลา
---   (ซื้อเบ็ดใหม่ / ผู้ใช้สลับเบ็ดเอง / เกมอัปเดตคลัง) — อ่าน data.RodEquip สดทุกครั้ง
---
--- คืน true ถ้าเบ็ดที่ติดตั้งหลังเสร็จคือเบ็ดที่ดีที่สุดในกระเป๋าแล้ว
local function ensureBestLoadout(waitRod)
    local data = fetchData()
    if not data then return false end

    -- ⚠ ประตูสถานะ: ชุดอุปกรณ์ไม่เปลี่ยนเลย = ไม่มีอะไรให้ทำ = ไม่ต้องยิง packet
    --   เดิมยิงชุด "สลับเบ็ด -> ถอดสกิล -> สลับเบ็ด -> ใส่สกิล" ทุก SkillSlotPoll วินาที
    --   = ~1,100 ครั้งในรอบ 2.5 ชั่วโมง ทั้งที่ 99% รอบไม่มีอะไรเปลี่ยน
    --   ⚠ ข้ามประตูนี้ถ้าเพิ่งซื้อเบ็ด (waitRod) เพราะข้อมูลยังไม่ replicate
    if not waitRod then
        local sig0 = S.tools.loadoutSignature(data)
        if S.loadoutSkip and S.loadoutSig == sig0 then return S.loadoutOk end
        S.loadoutSig, S.loadoutSkip = sig0, false
    end

    -- เพิ่งซื้อเบ็ด: รอให้เบ็ดใบนั้นโผล่ในคลังจริงก่อนตัดสินใจเลือก
    if waitRod and (type(data.Rods) ~= "table" or data.Rods[waitRod] == nil) then
        local t0 = os.clock()
        while os.clock() - t0 < 3 do
            task.wait(0.2)
            data = fetchData()
            if not data then return false end
            if type(data.Rods) == "table" and data.Rods[waitRod] ~= nil then break end
        end
    end

    -- ⚠ เดิมมี pinnedQuestRod บังคับใส่เบ็ดที่เควสต์กำหนด แต่พิสูจน์แล้วว่าเป็น no-op
    --   crimson_bead_rod นับ "Fish Caught with Legacy Rod" (Requirements/crimson_bead_rod.lua:51)
    --   แต่ตอนทำเควสต์นี้ เรามี legacy_rod เป็นเบ็ดที่แรงสุดในคลังอยู่แล้วเสมอ
    --   (crimson/bamboo/dread เป็นของหลังจากนี้ และถ้ามี = missionDone เป็นจริงอยู่แล้ว)
    --   findBestRod จึงเลือกได้ legacy_rod อยู่ดี ไม่ต้องบังคับ และถ้ามีเบ็ดแรงกว่า
    --   การบังคับจะกลับทำให้เราใช้เบ็ดอ่อนกว่าเดิม = แย่กว่าเดิม
    local best = findBestRod(data)

    -- ── 1) เช็คก่อน (อ่านอย่างเดียว ไม่ยิง packet): มีสกิลค้างอยู่กี่เบ็ด ──
    --   ต้องรู้ตั้งแต่แรกว่าต้อง "ไล่ถอด" กี่เบ็ด จะได้รู้ว่าต้องสลับกี่ครั้ง
    local stale = rodsHoldingSkills(data, best)
    if #stale > 0 then
        -- เตือนรวมทีเดียวตอนเข้าไปจัดการ ไม่เตือนทีละเบ็ด (จะท่วมทุก 5 วิตอน poll รอบหน้า)
        if not S.warnedStale then
            S.warnedStale = true
            logWarn(("[Prog] พบสกิลค้าง %d เบ็ด (%s) — ไล่ถอดให้หมดก่อนใช้เบ็ดที่ดีที่สุด")
                :format(#stale, table.concat(stale, ", ")))
        end
        local stuck = {}

        -- เรียงให้เบ็ดที่ใส่อยู่ตอนนี้มาก่อน = ไม่ต้องสลับไป-กลับมาซ้ำ
        local cur0 = data.RodEquip
        for i, rid in ipairs(stale) do
            if rid == cur0 then
                table.remove(stale, i)
                table.insert(stale, 1, rid)
                break
            end
        end

        -- ⚠ EquipMoveset ไม่มีพารามิเตอร์ rodId = server แก้ได้แค่เบ็ดที่ติดตั้งอยู่
        --   (EquipmentController:_ResolveBookSlots:1595 อ่าน data.RodEquip)
        --   = ถอดเบ็ดไหน ต้องสลับไปที่เบ็ดนั้นก่อน แล้วค่อยยิงค่าว่างทีละช่อง
        for _, rid in ipairs(stale) do
            if not switchToRod(rid) then
                -- สลับไม่ได้ = สกิลยังค้าง รอบถัดไปค่อยลองใหม่ (ยิงซ้ำทันทีไม่ช่วย)
                --   แต่ต้องสลับเบ็ดที่ดีที่สุดต่อเสมอ ไม่งั้นจะค้างอยู่ที่เบ็ดเสีย
                stuck[rid] = true
            else
                unequipRodSkills(fetchData() or data, rid)
            end
            -- อ่านใหม่ทุกใบ: ตัวนับ "สกิลที่ยังใช้อยู่" ต้องลดลงตามจริง
            data = fetchData() or data
        end
        -- จัดการครบทุกเบ็ด = ค่อยเตือนได้อีกรอบถ้ามีของใหม่โผล่มา
        if not next(stuck) then S.warnedStale = false end
    end

    -- ── 2) สลับไปเบ็ดที่ดีที่สุด ──
    if best and best ~= data.RodEquip then
        if switchToRod(best) then
            data = fetchData() or data
        end
    end

    -- ⚠ ใส่สกิล "หลัง" การสลับเบ็ดเสมอ: tryEquipAllSkills อ่าน data.RodEquip สด
    --   แล้วนับช่องว่างจากเบ็ดที่ติดตั้ง — ถ้าเบ็ดยังไม่เปลี่ยนจริง จะได้ช่องของเบ็ดเก่า
    tryEquipAllSkills()

    -- ── 3) Unit: ใส่ตัวที่ดาเมจสกิลฐานสูงสุด แล้วถอดตัวอื่น (กติกาผู้ใช้) ──
    --   เรียกที่นี่เพราะ ensureBestLoadout ถูกเรียกทุกครั้งที่ action สำเร็จ
    --   = สุ่มได้ตัวใหม่แล้วเข้ามาในรอบเดียวกัน ไม่ต้องรอจังหวะอื่น
    equipBestUnit(data)

    local after = fetchData() or data
    S.loadoutOk = (best == nil) or (after.RodEquip == best)
    -- ⚠ ถ้ายิงแล้วสถานะยังเหมือนเดิมเป๊ะ = รอบหน้าไม่ต้องยิงซ้ำ
    S.loadoutSkip = (S.tools.loadoutSignature(after) == S.tools.loadoutSignature(data))
    S.loadoutSig  = S.tools.loadoutSignature(data)
    return S.loadoutOk
end

-- ══════════════════════════════════════════════════
-- 7) MOVE TO HOUSE1 (noclip + tween)
-- ══════════════════════════════════════════════════
--- noclip — เรียกครั้งเดียวตอนเริ่ม script ด้วย setNoclip(true) แล้วค้างไว้ตลอด
--- Heartbeat วนใส่ CanCollide=false ให้ BasePart ทุกชิ้น (อ่าน LocalPlayer.Character ใหม่ทุกครั้ง
--- ตัวละครเกิดใหม่จึงครอบคลุมหลัง respawn ด้วย) ไม่มีจุดที่ปิดอัตโนมัติ
local function setNoclip(enabled)
    if enabled then
        if S.noclipConn then return end
        S.noclipConn = RunService.Heartbeat:Connect(function()
            local char = LocalPlayer and LocalPlayer.Character
            if not char then return end
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    pcall(function() part.CanCollide = false end)
                end
            end
        end)
    else
        -- ไม่ต้องมี conn ของรอบนี้ก็ disconnect ได้ ไม่ต้อง return ออกก่อน
        if S.noclipConn then
            S.noclipConn:Disconnect()
            S.noclipConn = nil
        end
        -- ⚠ กู้ collision เสมอ แม้ไม่มี conn ของรอบนี้
        --   เพราะ CanCollide=false ที่ setNoclip(true) เขียนไว้เป็นสถานะ
        --   ของตัวเอนจิน ไม่ใช่ของสคริปต์ executor เปิด environment ใหม่ทุกครั้ง
        --   แต่ Heartbeat ของรอบก่อนตายไปแล้ว = ไม่มีใครคอยเปิด collision กลับ
        --   อาการคือ "ตัวละครทะลุพื้นไปเรื่อย ๆ / ขยับไม่ได้"
        local char = LocalPlayer and LocalPlayer.Character
        if char then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    -- ⚠ ห้ามเรียก part:GetAncestors() — executor บางตัวไม่มีเมธอดนี้
                    --   ในตารางของ Instance ขึ้นว่า
                    --   "GetAncestors is not a valid member of Part ...HumanoidRootPart"
                    --   แล้วทั้งรอบ progression ตายตามด้วย
                    --   (setNoclip <- standAt <- tweenDiveTo <- goToFarmSpot <- progression)
                    --   เดิน Parent แทน = เป็น property ล้วน ใช้ได้ทุก executor
                    --   แถมไม่ต้องสร้างตารางใหม่ทุกชิ้นทุกครั้งที่ปิด noclip
                    --
                    -- ⚠ pcall ครอบทั้งก้อน "ต่อ 1 ชิ้น" ไม่ใช่ต่อบรรทัด
                    --   เพราะชิ้นที่พังต้องไม่ลากให้ชิ้นที่เหลือค้าง CanCollide=false
                    --   (ค้าง = ตัวละครทะลุพื้น ขยับไม่ได้)
                    pcall(function()
                        -- ⚠ ของแต่ง (Accessory) ค่า CanCollide ปกติคือ false
                        --   ถ้าดันเป็น true ตอนเปิด collision กลับ มันจะชนตัวเอง -> ตัวสั่น
                        --   noclip เขียนทับไปแล้ว การคืนค่าเริ่มต้นจึงถูกกว่า
                        local isAcc = false
                        local up, walk = part.Parent, 0
                        while up do
                            if up:IsA("Accessory") then isAcc = true break end
                            up = up.Parent
                            walk = walk + 1
                            if walk > 64 then break end     -- กันวน (Parent ของ Instance ไม่มีวงจรอยู่แล้ว)
                        end
                        part.CanCollide = not isAcc
                    end)
                end
            end
        end
    end
end

local function findHouse1()
    local world = Workspace:FindFirstChild("World")
    local islands = world and world:FindFirstChild("Islands")
    local starter = islands and islands:FindFirstChild("island_starter")
    local map = starter and starter:FindFirstChild("Map")
    local th = map and map:FindFirstChild("Trees & Houses")
    local house = th and th:FindFirstChild("House1")
    return house
end

local function modelCenter(model)
    if not model then return nil end
    if model:IsA("BasePart") then return model.Position end
    if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
        return model.PrimaryPart.Position
    end
    local ok, cf, size = pcall(function() return model:GetBoundingBox() end)
    if ok and cf then return cf.Position end
    -- fallback: ค่าเฉลี่ยตำแหน่ง descendant parts
    local sum = Vector3.new(); local n = 0
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then sum = sum + d.Position; n = n + 1 end
    end
    if n > 0 then return sum / n end
    return nil
end

--- ฆ่า velocity (gravity + ความเร็วสะสมจาก tween) ก่อนเขียน CFrame ทุก step
--- สำคัญมาก: ถ้าไม่ฆ่า velocity ตัวละครจะเร่งความเร็วลงตลอด tween
---   พอปล่อย CFrame ครั้งสุดท้าย (ตอน task.wait ท้าย tween) -> พุ่งลงด้วยความเร็วสูงมาก
---   -> ทะลุพื้น/ทะลุโลก -> เกม warp กลับจุด spawn (อาการ "เด้งกลับจุดแรกสุด")
local function stopVelocity()
    local hrp = root()
    if not hrp then return end
    pcall(function() hrp.AssemblyLinearVelocity = Vector3.zero end)
    pcall(function() hrp.AssemblyAngularVelocity = Vector3.zero end)
end

-- ══════════════════════════════════════════════════════════════════════
-- PIN — ตรึงตัวละครไว้ที่จุดที่มาถึงแล้ว ไม่ให้ไหลลง
-- ══════════════════════════════════════════════════════════════════════
-- ⚠ ทำไมฆ่า velocity ไม่พอ (ผู้ใช้สั่งหา 2026-10-16: "ตัวละครเราไหลลงเรื่อยๆ เลย")
--   startAntiSink() เขียน AssemblyLinearVelocity = 0 ทุกเฟรม แต่ gravity เพิ่ง
--   ใส่ความเร็วลงให้ *หลัง* step ของ engine เสมอ -> ตกได้สูงสุด ~g*dt/2 ต่อเฟรม
--   ที่ 60 Hz และ g = 196.2 = ~3.3 studs/วิ → ยัง "ไหลลงทุกวินาที" ไม่ใช่จอด
--   และสุดท้ายคือชนระดับน้ำ → SwimmingController → FishCancel → session หลุด
--
-- ⚠ ทำไม Humanoid.PlatformStand ก็ไม่พอ (ลองแล้ว 2026-10-16: "ยังไหลเหมือนเดิม")
--   PlatformStand เป็น "ท่า" ของ Humanoid ไม่ใช่การล็อกตำแหน่ง
--   state machine ของ Humanoid เขียนทับกลับได้ แล้ว gravity ก็ทำงานต่อ
--   Anchored = true คือ engine ล็อก assembly จริง → ไม่มีทางไหล ไม่มีทางหลุด
--   และเกมเองใช้แบบเดียวกันอยู่แล้ว:
--     FishingController:LockHumanoidMovement (บรรทัด 1046) เขียน
--     HumanoidRootPart.Anchored = true ตอนตีบอสที่ยืนพื้นจริง
--   เราแค่ทำมัก่อนเข้า fight — คนละช่วงเวลา ไม่ใช่คนละกลไก
--
-- ⚠ เกมจะมาปลด Anchored ของเราเองไหม — ไม่
--   FishingController:RestoreHumanoidMovement (บรรทัด 1068) ปลดก็ต่อเมื่อ
--   LockHumanoidMovement เป็นคนตั้ง didAnchorRoot ไว้เท่านั้น
--   = ถ้าเราเป็นคนตรึงเอง มันไม่แตะ (จะปลดเฉพาะตอนตัวละครตาย/หลุดวง)
--   เรายังกู้ทุกเฟรมอยู่ (holdPin) เผื่อ server รีเซ็ต physics หรือสคริปต์อื่นแตะ
--
-- ⚠ กฎที่ผู้ใช้กำหนด (2026-10-16) — ตรึงมีเงื่อนไข ไม่ใช่ตลอดเวลา:
--   1) ตรึง "ตอนถึงจริงเท่านั้น" — วัดจากตำแหน่งจริงของตัวละคร เทียบจุดที่ไป
--   2) พอจะขยับไปไหน — ปล่อยก่อนเสมอ ทุกจุดที่เขียน CFrame (tweenOnce)
--   3) ตัวละครเปลี่ยน (ตาย/เกิดใหม่) = ปล่อย ไม่งั้นตัวใหม่ถูกล็อกทันที
--   4) ปิดสคริปต์ / รันใหม่ = ปล่อยเสมอ (ไม่งั้นรอบหนึ่งค้าง = ทุกรอบหลังค้าง
--      เหมือนบั๊ก CanCollide=false ที่เคยเจอ)
--
-- ⚠ ไม่มีการนับเวลาเลยทั้งบล็อกนี้ (ผู้ใช้ห้ามนับเวลาเองทุกอย่าง)
--   "ถึงแล้วหรือยัง" = อ่าน hrp.Position จริงเทียบจุดเป้า ไม่ใช่รอกี่วินาที
--
-- ⚠ อยู่ใน S.tools ไม่ใช่ local ระดับไฟล์ เพราะไฟล์ชนเพดาน 200 local พอดี
-- ⚠ ต้องประกาศ "ก่อน" tweenOnce เพราะ tweenOnce เรียกใช้

-- ⚠ เดิมตรงนี้: startAntiSink() ฆ่า velocity ทุกเฟรม แต่ gravity เพิ่งใส่ความเร็วลง
--   ให้หลัง step ของ engine เสมอ -> ตกได้สูงสุด ~g*dt/2 ต่อเฟรม ที่ 60 Hz และ
--   g = 196.2 = ~3.3 studs/วิ = "ไหลลงทุกวินาที" ไม่ใช่จอด
--   และสุดท้ายคือชนระดับน้ำ -> SwimmingController -> FishCancel -> session หลุด
--
-- ⚠ ทำไม Humanoid.PlatformStand ก็ไม่พอ (ลองแล้ว 2026-10-16: "ยังไหลเหมือนเดิม")
--   PlatformStand เป็น "ท่า" ของ Humanoid ไม่ใช่การล็อกตำแหน่ง
--   state machine ของ Humanoid เขียนทับกลับได้ แล้ว gravity ก็ทำงานต่อ
--   Anchored = true ล็อก assembly จริง แต่ engine จับทั้งก้อน = เดินไม่ได้
--   -> เปลี่ยนมาใช้ "ยกแรงโน้มถ่วง" แทน (ผู้ใช้สั่ง 2026-10-17 ดู S.tools.setNoGravity)
--
-- ⚠ เกมใช้ Anchored เองตอนตีบอสที่ยืนพื้นจริง (FishingController:LockHumanoidMovement
--   บรรทัด 1046) เราเลยไม่ต้องแตะตรงนั้น
--
-- ⚠ กฎที่ผู้ใช้กำหนด (2026-10-16) — ยกแรงโน้มถ่วงมีเงื่อนไข ไม่ใช่ตลอดเวลา:
--   1) ทำ "ตอนถึงจริงเท่านั้น" — วัดจากตำแหน่งจริงของตัวละคร เทียบจุดที่ไป
--   2) พอจะขยับไปไหน — ปล่อยก่อนเสมอ ทุกจุดที่สั่งเดินทาง (tweenOnce)
--   3) ตัวละครเปลี่ยน (ตาย/เกิดใหม่) = ปล่อย ไม่งั้นตัวใหม่ถูกยกแรงทันที
--   4) ปิดสคริปต์ / รันใหม่ = ปล่อยเสมอ (ไม่งั้นรอบหนึ่งค้าง = ทุกรอบหลังค้าง
--      เหมือนบั๊ก CanCollide=false ที่เคยเจอ)
--
-- ⚠ ไม่มีการนับเวลาเลยทั้งบล็อกนี้ (ผู้ใช้ห้ามนับเวลาเองทุกอย่าง)
--   "ถึงแล้วหรือยัง" = อ่าน hrp.Position จริงเทียบจุดเป้า ไม่ใช่รอกี่วินาที
--
-- ⚠ อยู่ใน S.tools ไม่ใช่ local ระดับไฟล์ เพราะไฟล์ชนเพดาน 200 local พอดี
-- ⚠ ต้องประกาศ "ก่อน" tweenOnce เพราะ tweenOnce เรียกใช้


--- "ถึงจุดเป้าแล้วไหม" — อ่านตำแหน่งจริงของตัวละคร ไม่เชื่อค่าที่เราจะไป
---   แนวนอนใช้ ArriveXZ / แนวตั้งใช้ StandHeight (คนละเกณฑ์ เพราะตอนหนีจากน้ำ
---   เกมดันตัวขึ้นมาได้หลายสิบ studs แต่แนวนอนต้องตรงจริง)
S.tools.arrived = function(hrp, want)
    if not (hrp and want) then return false end
    local xz = CONFIG.ArriveXZ or 2.5
    local dy = CONFIG.StandHeight or 4
    local dx = hrp.Position.X - want.X
    local dz = hrp.Position.Z - want.Z
    return (dx * dx + dz * dz) <= xz * xz
       and math.abs(hrp.Position.Y - want.Y) <= dy
end

-- ══════════════════════════════════════════════════════════════════════
-- NO-GRAVITY — ไม่ตรึงตัว แต่ "ลดแรงโน้มถ่วง" แทน (ผู้ใช้สั่ง 2026-10-17)
-- ══════════════════════════════════════════════════════════════════════
--- ของเดิม: ตอนถึงจุด -> hrp.Anchored = true + holdPin กู้ทุกเฟรม
---   ปัญหาของ Anchored: engine จับ assembly ทั้งก้อน = เดินไม่ได้ ปลาไม่งอย
---   และที่แก้ไม่ได้ด้วยการ "ไม่ตรึก" เฉย ๆ เพราะ noclip เปิดค้าง = ไม่มีพื้นให้ยืน
---   -> gravity ดึงลง -> หลุดถึงระดับน้ำ -> SwimmingController -> FishCancel
---
--- วิธีนี้: ยกแรงโน้มถ่วงของตัวเราออก "พอดี" แทนที่จะล็อกตำแหน่ง
---   -> ตัวละครยังเดินได้ปกติ แต่ไม่มีแรงดึงลง = ไม่ไหล ไม่จม
---
--- ⚠ ใช้ VectorForce แนบกับ HRP ของเราตัวเดียว ไม่แตะ workspace.Gravity
---   ผู้เล่นคนอื่นและของในเกมยังตกแบบปกติ
--- ⚠ แรง = น้ำหนักตัวละคร x gravity = ชดเชยพอดี ไม่ลอยขึ้น ไม่จมลง
---
--- ⚠ อยู่ใน S.tools ไม่ใช่ local ระดับไฟล์ เพราะไฟล์ชนเพดาน 200 local พอดี
S.tools.setNoGravity = function(on, at)
    local hrp = root()
    if not on then
        local f = S.grav
        S.grav = nil
        S.antiSinkBase = nil
        if f then pcall(function() f:Destroy() end) end
        return false
    end
    if not hrp then return false end
    -- ⚠ อ่าน gravity สดทุกครั้ง ถ้าอ่านไม่ได้ = อย่าเดา ไม่ผูกแรงมั่ว
    --   (S.antiSinkBase = ค่าที่ผูกไว้ตอนแรก ใช้เป็นตาข่าย: ถ้าค่าใน workspace
    --    เพี้ยนจนใช้ไม่ได้ หรือชดเชยไม่พอดี ให้รู้ว่าเป็นฝีมือเกม ไม่ใช่ค่าที่เราตั้ง)
    local g = tonumber(Workspace.Gravity)
    if type(g) ~= "number" or g <= 0 then
        if S.antiSinkBase == nil then
            logWarn("[Prog] อ่าน Workspace.Gravity ไม่ได้ — ยกแรงโน้มถ่วงไม่ได้")
        end
        return false
    end

    -- ⚠ ตัวละครเปลี่ยน (ตาย/เกิดใหม่) = ของเดิมหลุดไปแล้ว ต้องผูกใหม่
    if S.grav and S.grav.Parent ~= hrp then
        pcall(function() S.grav:Destroy() end)
        S.grav = nil
    end
    if not S.grav then
        local okF, f = pcall(function()
            local nf = Instance.new("VectorForce")
            nf.Name = "ProgNoGravity"
            -- ⚠ VectorForce ไม่มี Mode/ActuatorMode/MaxForce/ForceLimitsEnabled (เป็นของ constraint ตัวอื่น)
            --   ที่ต้องมีจริง: Attachment0 + RelativeTo + Force (+ ApplyAtCenterOfMass กันตัวหมุน)
            local att = hrp:FindFirstChild("RootAttachment")
            if not (att and att:IsA("Attachment")) then
                att = hrp:FindFirstChild("ProgNoGravityAtt")
                if not att then
                    att = Instance.new("Attachment")
                    att.Name = "ProgNoGravityAtt"
                    att.Parent = hrp
                end
            end
            nf.Attachment0 = att
            nf.ApplyAtCenterOfMass = true
            nf.RelativeTo = Enum.ActuatorRelativeTo.World
            nf.Force = Vector3.zero
            nf.Parent = hrp
            return nf
        end)
        if not (okF and f) then
            -- ⚠ พิมพ์เหตุผลจริงด้วย ไม่งั้นเจอแค่ "ไม่ได้" แล้วเดาไม่ออกว่าติดตรงไหน
            logWarn("[Prog] สร้าง VectorForce ไม่ได้: " .. tostring(f) .. " — ตัวละครจะไหลลงเหมือนเดิม")
            return false
        end
        S.grav = f
        S.antiSinkBase = g
    end
    -- ⚠ น้ำหนักตัวละครเปลี่ยนได้ (สวิตช์เปลี่ยนอุปกรณ์ = คนละมวล) อ่านสดทุกครั้ง
    local mass = tonumber(hrp.AssemblyMass)
    if type(mass) ~= "number" or mass <= 0 then mass = 1 end
    -- ⚠ เขียนแรงใหม่ทุกเฟรม: gravity ของ workspace อาจถูกเกมเปลี่ยนกลางทาง
    --   ถ้าใช้ค่าเก่าค้างไว้ = ชดเชยผิด = ตัวละครลอยขึ้นหรือจม
    pcall(function() S.grav.Force = Vector3.new(0, mass * g, 0) end)
    if at then S.arriveAt = at end
    return true
end

--- "ยังอยู่ในโซนที่ยกแรงไว้ไหม" — เกณฑ์หลวม (HoldXZ/HoldHeight)
---   ต่างจาก arrived() ตรงที่ arrived() = "ถึงตามที่สั่ง" (เข้ม 2.5/4)
---   อันนี้ = "อยู่ที่เดิม ยังลอยตัวรอกลับได้" (หลวม 14/18)
S.tools.inHoldZone = function(hrp, at)
    if not (hrp and at) then return false end
    local xz = CONFIG.HoldXZ or 14
    local dy = CONFIG.HoldHeight or 18
    local dx = hrp.Position.X - at.X
    local dz = hrp.Position.Z - at.Z
    return (dx * dx + dz * dz) <= xz * xz
       and math.abs(hrp.Position.Y - at.Y) <= dy
end

--- กู้ทุกเฟรม (อ่านสถานะจริง ไม่ใช่นับเวลา) — แทน holdPin เดิม
S.tools.holdNoGravity = function()
    if not S.grav then return false end
    local hrp = root()
    -- ⚠ ตัวละครไม่อยู่ = แรงเก่าเป็นของตัวที่หายไปแล้ว = ทำลายทิ้ง ไม่ใช่แค่ลืม flag
    --   (ถ้าปล่อยค้างไว้ แล้วเกมมาสร้างตัวใหม่ที่ยังพ่วงอยู่ = ตัวใหม่ลอยตั้งแต่เกิด)
    if not hrp then
        local of = S.grav
        S.grav = nil
        S.antiSinkBase = nil
        if of then pcall(function() of:Destroy() end) end
        return false
    end
    -- ⚠ เงื่อนไข 3 (เดิมของ holdPin): ตัวละครเปลี่ยน = ปล่อย ไม่งั้นขยับไม่ได้เลย
    if S.grav.Parent ~= hrp then
        pcall(function() S.grav:Destroy() end)
        S.grav = nil
        S.antiSinkBase = nil
        S.arriveAt = nil
        return false
    end
    -- ⚠ หลุดโซน = ปล่อย (ผู้ใช้สั่ง 2026-10-17 เรื่อง "โดนดึงกลับ")
    --   เดิมแรงค้างตลอดไม่ว่าตัวละครจะไปอยู่ที่ไหน = เราลอยค้างที่ผิดที่ แล้วสคริปต์
    --   ยังคิดว่ายืนที่จุดฟาร์ม นี่คืออาการ "คิดว่าถึงทั้งที่ยัง"
    --   เกณฑ์ = HoldXZ/HoldHeight (หลวม) ไม่ใช่ ArriveXZ/StandHeight (เข้ม)
    --   เพราะเซิร์ฟดันตัวเราหลุดบ่อย (คลื่น/แรงต้าน/การชน) เกณฑ์เข้มจะปล่อยทุกครั้ง = ตก
    if S.arriveAt and not S.tools.inHoldZone(hrp, S.arriveAt) then
        local away = (hrp.Position - S.arriveAt).Magnitude
        pcall(function() S.grav:Destroy() end)
        S.grav = nil
        S.antiSinkBase = nil
        S.arriveAt = nil
        S.pinned = nil
        -- ความเร็วตอนหลุด: ~0 = โดนดึง/วาร์ปทันที (ฝั่งเซิร์ฟ) · มีค่าต่อเนื่อง = ไหลออกเอง
        local spd = 0
        pcall(function() spd = hrp.AssemblyLinearVelocity.Magnitude end)
        logWarn(("[Prog] หลุดโซนที่ยกแรงไว้ %.1f studs (ความเร็วตอนนี้ %.1f) — ปล่อยแล้ว ไม่ลอยค้างที่ผิดที่")
            :format(away, spd))
        -- ไม่ต้องรอรอบ FarmSpotPoll (8 วิ): ระหว่างที่ปล่อยแรงตัวละครกำลังตกอยู่ ให้กลับจุดฟาร์มทันที
        S.farmRecheck = true
        return false
    end
    return S.tools.setNoGravity(true)
end

--- ปล่อยแรงโน้มถ่วง — คืน false (ไม่ตรึงอะไรอีกต่อไป)
---   ⚠ ต้องล้าง S.arriveAt ด้วยเสมอ (ผู้ใช้สั่ง 2026-10-17)
---     "ไม่มีแรง" กับ "จำว่ามาถึงแล้ว" ต้องเป็นสถานะเดียวกันเสมอ
---     ไม่งั้น pin() ที่ถูกเรียกทีหลังโดยไม่มี argument จะเอาจุดเก่าที่เราไม่ได้อยู่
---     ไปเทียบ แล้วคิดว่าถึงทั้งที่โดนดึงกลับไปแล้ว = นี่คือที่มาของบั๊กนั้น
S.tools.releasePin = function()
    S.tools.setNoGravity(false)
    S.pinned = nil
    S.arriveAt = nil
    return false
end

--- ยกแรงโน้มถ่วงหลัง "มาถึงจุดแล้ว" (ไม่ใช่ Anchored — ตัวละครยังเดินได้)
---   @param want Vector3 = จุดที่เพิ่งมาถึง (nil = ใช้ S.arriveAt ที่บันทึกไว้ตอนมาถึงครั้งก่อน)
S.tools.pin = function(want)
    if CONFIG.Pin == false then
        S.tools.releasePin()
        return false
    end
    local hrp = root()
    if not hrp then return false end
    local at = want or S.arriveAt
    -- ⚠ ยืนบนแท่นจริงอยู่ (โหมดบอส) = ตั้งใจไม่ยกแรงโน้มถ่วง และตั้งใจล้าง S.arriveAt
    --   ไม่ใช่ "ยังไม่ถึง" -> คืนเงียบ ๆ ไม่เตือน (เดิมเตือนทุก 15 วิตลอดการตีบอส)
    if not want and S.standSpot and S.standSpot.Parent then
        return false
    end
    -- ⚠ ไม่รู้ว่ามาถึงที่ไหน = ห้ามยกแรงมั่ว (เช่นจุดบอสที่มีแท่นจริงอยู่แล้ว
    --   ที่นั่นต้องปล่อยให้ gravity ทำงานปกติ ไม่ใช่ลอยเหนือแท่น)
    if not at then
        -- throttle: เดิมพิมพ์ทุกรอบของลูปตกปลา (หลายครั้งต่อวินาที) ท่วม log
        local tnow = nowReal()
        if tnow - (S.pinWarnAt or 0) > 15 then
            S.pinWarnAt = tnow
            logWarn("[Prog] ยังไม่มีจุดที่มาถึงล่าสุด — ไม่ยกแรงโน้มถ่วง (เตือนซ้ำได้ทุก 15 วิ)")
        end
        return false
    end
    -- ⚠ เงื่อนไข 1: ถึงจริงหรือยัง — เทียบตำแหน่งจริงกับจุดเป้า ไม่เดาเอง
    --   ยังไม่ถึง = ปล่อยของที่ค้างจากรอบก่อนด้วย ไม่งั้นจะค้างตรงที่ผิดจุด
    if not S.tools.arrived(hrp, at) then
        -- ⚠ หลุดเกณฑ์เข้ม แต่ยังอยู่ในโซนเดิม = ห้ามเพิ่งปล่อย (ผู้ใช้สั่ง 2026-10-17)
        --   เดิมปล่อยทันที = ตัวละครตกทันทีที่เซิร์ฟดันหลุดไป 3 studs
        --   = บั๊ก "ไหลลง/จม" เดิมกลับมาทั้งดุ้น และเจอบ่อยกว่าเดิมมาก เพราะ
        --   pin() ถูกเรียกทุกรอบของลูปตกปลา (ensureNotSwimming) ไม่ใช่ตอนมาถึงครั้งเดียว
        if S.grav and S.tools.inHoldZone(hrp, at) then
            return S.tools.setNoGravity(true, at)
        end
        S.tools.releasePin()
        logWarn(("[Prog] ยังไม่ถึงจุดเป้า (ห่าง %.1f studs) — ไม่ยกแรงโน้มถ่วง")
            :format((hrp.Position - at).Magnitude))
        return false
    end
    S.arriveAt = at
    S.pinned = { hrp = hrp }
    return S.tools.setNoGravity(true, at)
end

-- ══════════════════════════════════════════════════
-- HOLD — ตรึงตำแหน่งไว้กับที่
-- ──────────────────────────────────────────────────
-- ⚠ บั๊กจาก log 18:53:37-18:53:40 (ไม่ใช่ "เกมดันกลับ"):
--   เฟส 3 tween ขึ้นถึง y=16.6 สำเร็จ แต่ task.wait(0.3) ระหว่างรอเช็คตำแหน่ง
--   ตัวละครตกกลับเหลือ 7.1 studs  (ตกแค่ 0.3s = gravity ~8.8 studs ตรงเป๊ะ)
--   สาเหตุ: noclip เปิดตลอด (CanCollide=false) = ไม่มีพื้นให้ยืน
--   -> startAntiSink() ยังไม่ได้สตาร์ต ตอน tween (เรียกหลัง tween ไป House1)
--   -> gravity ดึงลงตลอดช่วง settle -> ทุกครั้งที่ tween ขึ้นก็ตกกลับ
--
-- HOLD แก้โดย "เขียน CFrame กลับทุกเฟรมที่หลุดจากจุดที่ตรึง"
--   ไม่ใช่การนับเวลา — อ่านตำแหน่งจริงของตัวละครแล้วเทียบกับจุดที่ตั้งใจไว้
-- ══════════════════════════════════════════════════
-- ==========================================================
-- FORBIDDEN: Hold (dragging the character with CFrame) was removed 2026-10-16
-- ==========================================================
-- It was a Heartbeat that dragged hrp.CFrame back to the target every frame
-- the body drifted more than 0.05 studs.
--
-- Why it caused "warping back and forth":
--   server/physics pulled the body back -> Hold yanked it forward
--   -> server pulled back -> Hold yanked forward ... every single frame.
--   The body visibly vibrated between two points and never settled.
--
-- Why it must never come back:
--   a position we write ourselves is NOT the position the server sees.
--   We used to read that fake position and decide "we have arrived",
--   then cast a line from a spot the server still thinks we are not at.
--   That fails silently - nothing in the log says why.
--   Proof from the game: the server measures cast range from the real
--   position (FishingConfig.Cast.ServerMaxDistance = 80) and computes
--   "current island" from the real position too.
--
-- ⚠ What replaced it is NOT a CFrame drag — it is Anchored (see S.tools.pin)
--   Anchored ไม่เขียนตำแหน่งใด ๆ เลย engine แค่ไม่ให้ assembly เคลื่อนที่
--   = ได้ผลเดียวกัน (อยู่กับที่) แต่ไม่มีวันสู้กับเซิร์ฟ เพราะไม่มีอะไรให้สู้
--   และตรึงเฉพาะตอน "อ่านตำแหน่งจริงแล้วเทียบว่าถึงจุดเป้า" (ผู้ใช้สั่ง 2026-10-16)
--   ไม่ใช่ทุกเฟรมแบบไร้เงื่อนไขแบบ Hold เดิม
--   ข้อความเดิมที่เขียนไว้ตอนนั้น ("startAntiSink zeroes velocity ...
--   the body floats still, never sinks") ผิด — มันไม่เคยจริง ผู้ใช้เจอว่า
--   "ตัวละครเราไหลลงเรื่อยๆ เลย" เพราะ gravity เติมความเร็วหลัง step ของ engine
--
-- Movement itself is still tweenOnce (CFrame stepped along TweenTick
--   toward the target) - that is gradual travel, not a teleport, and it
--   is what the user asked for ("stall 5s -> tween again from the live
--   position"). Nothing snaps the body to a point any more.

--- tween แบบ pass เดียว (ไม่มี retry) จากจุด A ไปจุด B — gradual CFrame lerp
--- ตัวละคร state ปกติ ไม่ตรึง (Anchored=false) ไม่ noclip (ตาม test_tween_npc ที่พิสูจน์แล้ว)
---
--- ความเร็วคงที่ทุก FPS (เดิมพังเมื่อ FPS ต่ำ)
--- ──────────────────────────────────────────────────
--- เดิม: steps = ceil(segTime / TweenTick) แล้ว task.wait(TweenTick) ทุก step
---   -> เวลาจริง = steps * max(TweenTick, เฟรมจริง) >= segTime
---   -> FPS ต่ำ (เฟรมยาวกว่า TweenTick) = เดินช้ากว่าที่ตั้งไว้
---   -> FPS สูง ก็ยังถูกลากด้วย TweenTick ตายตัว
---   ตอนนี้: alpha มาจาก "เวลาจริงที่ผ่านไป" ไม่ใช่ i/steps
---   -> FPS ต่ำ   : ข้าม alpha ทีละก้อน (ยิ่งก้าวยิ่งไกล) แต่เวลารวมยัง = segTime
---   -> FPS สูง   : อัปเดตถี่ขึ้น แต่เวลารวมยัง = segTime
---   => ความเร็วเฉลี่ย = segDist / segTime = CONFIG.TweenSpeed เสมอ
--- TweenService แบบ blocking: เลื่อน CFrame ของ part ไปที่ cf ภายใน dur วินาที (Linear)
---   ใช้แทนการเขียน hrp.CFrame = ... ตรง ๆ — อยู่ใน S.tools เพราะ main chunk ชนเพดาน 200 local แล้ว
S.tools.tweenCF = function(part, cf, dur)
    return pcall(function()
        local tw = game:GetService("TweenService"):Create(
            part, TweenInfo.new(math.max(dur or 0.05, 0.01), Enum.EasingStyle.Linear), { CFrame = cf })
        tw:Play()
        tw.Completed:Wait()
    end)
end

local function tweenOnce(from, to)
    local hrp = root()
    if not hrp then return end

    -- ⚠ จะเขียน CFrame = กำลังขยับ = เงื่อนไข 2 ของการตรึง: ปล่อยก่อนเสมอ
    --   ถ้ายัง Anchored อยู่ engine จะจับตัวไว้ตรงที่เดิมทั้งที่เรากำลังวางเส้นทาง
    --   และที่สำคัญกว่านั้นคือ "จะขยับไปไหน" = ห้ามค้างที่เดิมแม้แต่วินาทีเดียว
    S.tools.releasePin()

    -- เก็บทิศหันเดิมไว้ ไม่ให้ CFrame.new(to) รีเซ็ตการหมุนทุกเซกเมนต์
    local rot = hrp.CFrame - hrp.CFrame.Position

    local function zeroVel()
        pcall(function()
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end)
    end

    local segDist = (to - from).Magnitude
    if segDist < 1 then
        zeroVel()
        S.tools.tweenCF(hrp, CFrame.new(to) * rot, 0.05)
        return true
    end

    -- ⚙ เดินทางด้วย TweenService (ความเร็วคงที่ = CONFIG.TweenSpeed) ไม่เขียน CFrame เองทีละขั้น
    local segTime = segDist / CONFIG.TweenSpeed
    local tw, twDone = nil, false
    local okTw = pcall(function()
        tw = game:GetService("TweenService"):Create(
            hrp, TweenInfo.new(segTime, Enum.EasingStyle.Linear), { CFrame = CFrame.new(to) * rot })
        tw.Completed:Connect(function() twDone = true end)
        tw:Play()
    end)
    if not okTw or not tw then return false end
    -- ⚠ ตัวจับค้าง (ผู้ใชาสั่ง 2026-10-16)
    --   tweenOnce เดิมเขียน CFrame ไปเรื่อยจน alpha = 1 โดยไม่เคยดูว่าตัวละครขยับไหม
    --   ถ้าเกมดึงกลับ / มีอะไรมาบัง / สคริปต์อื่นแย่งตัวละคร
    --   -> เราเขียนทิ้งไปทั้งเส้นทางแต่ตัวเองไม่ขยับเลย = ค้างจน segTime ครบ
    --   ตอนนี้ถ้า "ขยับไม่ถึง TweenStuckMove studs ใน TweenStuckSec วินาที"
    --   -> เลิกรอบนี้ทันที ปล่อยให้ tweenTo ยิงรอบใหม่จากตำแหน่งจริง ณ ตอนนั้น
    -- ⚠ nowReal() ไม่ใช่ os.clock: os.clock = เวลา CPU (ไม่เดินตอน yield)
    --   ในลูปนี้มี Heartbeat:Wait() = yield ทุกเฟรม -> os.clock จะแทบไม่เดิน
    local lastPos     = from
    local lastMoveAt  = nowReal()
    local lastCheckAt = lastMoveAt
    -- ⚠ เวลาเริ่มจากนาฬิกาเซิร์ฟ แยกจาก t0 ข้างบน
    --   t0 = os.clock() ใช้ขับ alpha ตอนเขียน CFrame (ในเกมเดินปกติ)
    --   แต่ตัวจับข้างล่างต้องรู้ "ตอนนี้ควรอยู่ที่ไหน" เพื่อเทียบกับตำแหน่งจริง
    --   ใช้ nowReal() เพราะเดินแน่นอนทั้งในเกมและในชุดเทสต์
    --   (os.clock ใน Lua 5.x แทบไม่เดินข้าม yield = ทดสอบไม่ได้)
    local t0Real      = nowReal()
    -- ⚠ เวลาเฟรมสะสม (จำกัดเฟรมละ 0.1 วิ) ใช้ชดเชยตอนแลค: TweenService เดินตามเฟรม
    --   แต่ nowReal เดินตามเวลาจริง ถ้า FPS ตก tween จะช้ากว่านาฬิกา
    --   แล้วตัวจับจะเข้าใจผิดว่า "เซิร์ฟไม่รับตำแหน่ง"
    local frameElapsed = 0

    while true do
        local now = os.clock()
        -- เช็คทุก 1 วินาทีพอ (ถ้าเช็คทุกเฟรมจะแพงเกินไปโดยไม่ได้ข้อมูลเพิ่ม)
        if nowReal() - lastCheckAt >= 1 then
            lastCheckAt = nowReal()
            local cur = hrp.Position

            -- ⚠ ตัวจับ "เซิร์ฟไม่รับตำแหน่ง" (ผู้ใช้สั่ง 2026-10-16)
            --   เดิมเทียบ cur กับ lastPos = ตำแหน่งที่เราเพิ่งเขียน CFrame เอง
            --   -> ตัวจับมองตัวเองเสมอ = "ขยับทุกวินาที" = ไม่เคยติด
            --   อาการจริงจาก log: ข้ามเกาะแล้วเซิร์ฟดึงกลับที่เดิม
            --   สคริปต์เขียน CFrame ครบ 35 วินาที (1021.7/29) x 2 รอบ = 70 วิ
            --   โดยตัวละครไม่ขยับแม้แต่ 1 stud และไม่มี log อธิบายว่าทำไม
            --   แก้โดยเทียบกับ "จุดที่ควรจะอยู่ ณ เวลานี้" = from:Lerp(to, alphaNow)
            --   โดย alphaNow มาจาก nowReal() (นาฬิกาเซิร์ฟ) ไม่ใช่ os.clock
            --   เพราะ os.clock ใน Lua 5.x แทบไม่เดินข้าม yield = เทสต์ไม่ได้
            --   และตรงกับกฎ "ห้ามนับเวลาเอง" — นี่คือเวลาจากเกม
            -- ⚠ FORBIDDEN (2026-10-16): ห้ามเทียบ cur กับ lastPos หรือกับตำแหน่งที่เราเพิ่ง
            --   เขียน CFrame — tweenOnce เขียน CFrame ทุกเฟรม ตัวจับแบบนั้นจึงมองตัวเอง
            --   เสมอ = ไม่เคยติด แล้วรอจน segTime จบโดยไม่มี log อธิบาย (เคยเป็นแบบนี้จริง)
            --   ต้องเทียบกับ "จุดที่ควรจะอยู่ ณ เวลานี้" = from:Lerp(to, alphaNow) เท่านั้น
            local alphaNow  = (nowReal() - t0Real) / segTime
            local want      = (alphaNow >= 1) and to or from:Lerp(to, alphaNow)
            local gap       = (cur - want).Magnitude
            -- ⚠ เกณฑ์เป็น "กี่วินาทีของระยะทาง" ไม่ใช่ studs ตายตัว
            --   = ให้จับได้ในเวลาเท่ากันไม่ว่าผู้ใช้จะตั้ง TweenSpeed เท่าไร
            --   TweenSpeed 29 เช่นในเกม -> ยอมหลุดได้ 58 studs -> จับที่ ~2 วิ
            --   TweenSpeed  1 ในเทสต์       -> ยอมหลุดได้  2 studs -> จับที่ ~2 วิ
            local lagSec = math.max(0, (nowReal() - t0Real) - frameElapsed)
            local allow = CONFIG.TweenSpeed * ((CONFIG.TweenRejectedSec or 2) + lagSec)
            if gap > allow then
                logWarn(("[Prog] MOVE: เซิร์ฟไม่รับตำแหน่งที่เราเขียน — วางไว้ที่ %s "
                        .. "แต่ตัวละครอยู่ %s (ห่าง %.0f studs, อยู่ห่างเป้า %.0f) "
                        .. "· เลิกรอบนี้ ไม่เขียนทั้งเส้นทางต่อ")
                    :format(("%d,%.0f,%.0f"):format(want.X, want.Y, want.Z),
                        ("%d,%.0f,%.0f"):format(cur.X, cur.Y, cur.Z),
                        gap, (cur - to).Magnitude))
                pcall(function() tw:Cancel() end)
                return false
            end

            if (cur - lastPos).Magnitude >= (CONFIG.TweenStuckMove or 1) then
                lastPos, lastMoveAt = cur, nowReal()
            elseif (nowReal() - lastMoveAt) >= (CONFIG.TweenStuckSec or 5) then
                -- ⚠ tweenOnce ไม่ได้รับ label มา (มีแต่ from/to) = พิมพ์แบบไม่มีป้ายกำกับ
                logWarn(("[Prog] MOVE: ค้างนิ่ง %.0fs (ขยับไม่ถึง %s studs) — ยังห่างเป้า %.1f studs · เตรียม tween ใหม่จากตรงนี้")
                    :format(nowReal() - lastMoveAt, tostring(CONFIG.TweenStuckMove or 1),
                        (cur - to).Magnitude))
                pcall(function() tw:Cancel() end)
                return false   -- tweenTo จะยิงรอบใหม่จาก hrp.Position จริง
            end
        end
        if twDone then break end
        zeroVel()
        local dt = RunService.Heartbeat:Wait()
        frameElapsed = frameElapsed + math.min(tonumber(dt) or 0, 0.1)
    end
    return true
end

--- tween แบบ gradual + retry (pattern เดียวกับ test_tween_npc ที่พิสูจน์ว่าไม่ snapback)
--- ไม่ตรึงตัว (Anchored = false ตอนเดินทาง) ไม่ noclip — ตัวละคร state เดิมเหมือนเดินปกติ
--- หัวใจของการไม่โดน warp กลับ: (1) collision เปิดตลอด ไม่ตกทะลุพื้น
---                                 (2) ฆ่า velocity ทุก step ไม่ให้พุ่งตอนปล่อยมือ
---                                 (3) เป้าต้องเป็นพื้นจริง (raycast) ไม่ใช่ Y ที่เดาจากกลางบ้าน
--- ถ้ายังถูกดึงกลับ -> re-tween จากตำแหน่งจริงปัจจุบันรอบใหม่ (ไม่วนจุดเดิม)
--- ถึงเป้าหรือยัง — เทียบเฉพาะระยะแนวนอน
--- แนวดิ่งไม่ต้องเทียบ: gravity ดึงตัวละครลงจากจุดที่ยิงไปอีก 1-3 studs เสมอ
---   (ของเดิมเทียบระยะรวม < 1 -> เดินบนหลังคาตกลงมา 1.0 พอดี ก็โดนหาว่า "โดนดึงกลับ" วน 20 รอบ)
local function arrivedAt(target)
    local hrp = root()
    if not hrp then return false, 0, 0 end
    local p = hrp.Position
    local dxz = Vector3.new(target.X - p.X, 0, target.Z - p.Z).Magnitude
    local dy = math.abs(target.Y - p.Y)
    return (dxz < CONFIG.ArriveXZ and dy < CONFIG.StandHeight), dxz, dy
end

local function tweenTo(target, label)
    local hrp = root()
    if not hrp then logWarn("[Prog] ยังไม่มีตัวละคร") return false end

    local reached = false
    local attempts = 0
    local bestErr = math.huge      -- ระยะห่างที่ดีที่สุดเท่าที่เคยได้
    -- ⚠ เดิมนับ "รอบที่ไม่เข้าใกล้ขึ้น" -> เลิกใจที่ 3 รอบ (x task.wait(0.3) = ~0.9 วิ)
    --   ผู้ใชาสั่ง 2026-10-16: ค้างเกิน 5 วิค่อยยอมแพ้ แล้ว tween ใหม่จากตำแหน่งที่ยืนอยู่
    --   เปลี่ยนเป็นนับเป็น "วินาทีที่ไม่เข้าใกล้ขึ้น" ให้ตรงกับตัวจับค้างใน tweenOnce
    local noGainSec = 0.0
    local noGainAt  = nowReal()
    -- ปล่อยการตรึงก่อน ไม่งั้น Hold จะดึงกลับจุดเดิมพร้อมกับที่ tween กำลังพาไป
    while not reached and attempts < CONFIG.TweenMaxTry do
        attempts = attempts + 1
        local ok = arrivedAt(target)
        if ok then reached = true break end

        -- ตายแล้วเกิดใหม่กลางทาง = hrp ตัวเก่าใช้ไม่ได้ ต้องอ่านใหม่ทุกรอบ
        hrp = root() or hrp
        tweenOnce(hrp.Position, target)
        -- ตรึงที่เป้าทันทีระหว่างรอ ไม่งั้น noclip(no collision) + gravity
        --   จะดึงตัวละครตกกลับระหว่าง settle ~8.8 studs ทำให้ไม่มีวันขึ้นถึงเป้า
        task.wait(0.3)  -- รอให้ตำแหน่งนิ่ง แล้วค่อยเช็คตำแหน่งจริง

        -- ตรวจว่า "เข้าใกล้ขึ้นจริง" ไหม (อ่านตำแหน่งจริงหลังเกมรายงานกลับมา)
        -- ถ้าเป้าอยู่ที่ตัวละครเอาไปไม่ได้จริง (เช่น เหนือผิวน้ำมาก ๆ)
        --   -> ระยะไม่เคยลด -> หยุดทันที ไม่ต้องวนครบ 20 รอบ
        -- err = ระยะที่ "บังคับ" จริง (dxz กับ dy เอาอันที่ห่างกว่า)
        local _, ddxz, ddy = arrivedAt(target)
        local err = math.max(ddxz, ddy)
        if err < bestErr - 0.5 then
            bestErr, noGainSec = err, 0.0
            noGainAt = nowReal()
        else
            noGainSec = nowReal() - noGainAt
            -- ⚠ เกณฑ์เดียวกับ tweenOnce: ไม่เข้าใกล้ขึ้นเกิน TweenStuckSec วิ = เข้าเป้าไม่ได้
            if noGainSec >= (CONFIG.TweenStuckSec or 5) then
                logWarn(("[Prog] MOVE[%s]: เข้าเป้าไม่ได้ — ไม่เข้าใกล้ขึ้น %.0fs "
                        .. "(เหลือ %.1f studs หลัง %d รอบ) · ปล่อยตรงนี้ ให้ผู้เรียกจัดการต่อ")
                    :format(label, noGainSec, err, attempts))
                break
            end
        end
    end


    -- ⚠ เช็คอีกครั้งหลังออกลูป: รอบสุดท้ายอาจถึงเป้าพอดีแล้ว (ลูปเช็คแค่ต้นรอบ)
    if not reached and arrivedAt(target) then reached = true end

    -- ปล่อยมือแล้วห้ามปล่อย velocity เปล่า (กันพุ่งลงทะลุโลก)
    stopVelocity()

    -- noclip เปิดตลอด = CanCollide=false = ตัวละครไม่มีพื้นให้ยืนโดยการออกแบบของเราเอง
    --   (ทั้งใต้น้ำและที่ระดับผิวน้ำก็เหมือนกัน)
    -- ตำแหน่งที่ค้างไว้หลัง tween จบ เกิดจาก startAntiSink() ที่ฆ่า velocity
    --   ทุก Heartbeat ไม่ใช่การยืนพื้น -> ไม่ต้องรอ FloorMaterial
    -- ⚠ ถึงจบแล้วก็ "ปล่อย" ไม่มีการดึงกลับ: ถ้ามีอะไรผลักตัวละคร
    --   ให้ไปตามจริง แล้วเราค่อยตัดสินใจใหม่จากตำแหน่งจริง
    return reached
end

-- ══════════════════════════════════════════════════
-- SWIM SURFACE — ระดับผิวน้ำจริง ณ ตำแหน่งนั้น (อ่านจากเกม มีคลื่น Gerstner)
-- ใช้ Swimming:GetSurfaceY() ของ controller ตัวจริง -> ไม่เดาระดับน้ำเอง
-- ══════════════════════════════════════════════════
local function swimSurfaceY(x, z)
    local ok, y = pcall(function()
        local c = Client.GetController("Swimming") or Client.GetController("SwimmingController")
        if c and type(c.GetSurfaceY) == "function" then
            return c:GetSurfaceY(x, z)
        end
        return nil
    end)
    if ok and type(y) == "number" then return y end
    return nil
end

--- จุดยืนของ House1 = กลางบ้านลงมา House1Drop studs (กฎที่ผู้ใช้กำหนด)
--- ────────────────────────────────────────────────────────────
--- ⚠ บั๊กเดิมไม่ได้อยู่ที่ "ค่า 10" แต่อยู่ที่ raycast:
---   log 18:45:53 "ใต้จุดเป้าไม่มีพื้นเลย -> ใช้ระดับน้ำ y=3.0"
---   เพราะเดิมยิง ray จาก center.Y - 9 ซึ่ง "ต่ำกว่าผิวพื้นจริงอยู่แล้ว"
---   -> ray วิ่งลงไปใต้พื้น ไม่เจออะไรเลย -> เข้าใจผิดว่าไม่มีพื้น
---   -> ตกไปใช้ "ระดับน้ำ" แล้วบวก StandHeight -> เป้าลอยเหนือผิวน้ำ 4 studs
---   -> tween ขึ้นแล้วตกกลับ วน 15 รอบไม่จบ
---
--- ตอนนี้: ใช้กฎ center.Y - N ตามที่กำหนด ไม่ตีความใหม่
---   raycast เหลือไว้เป็น "กันหลุดใต้พื้น" อย่างเดียว (ยกเป้าขึ้นถ้ามันต่ำกว่าผิวพื้นจริง)
---   และยิงจากเหนือ center เสมอ ไม่ใช่จากใต้พื้น
-- ══════════════════════════════════════════════════
-- STAND SPOT — แท่นยืนที่สคริปต์สร้างเอง (ผู้ใช้สั่ง 2026-10-16)
-- ══════════════════════════════════════════════════
-- ⚠ ใช้ "เฉพาะตอนไปตกบอส" เท่านั้น (ผู้ใช้สั่ง 2026-10-16)
--   จุดฟาร์ม / ไป NPC / กลับเกาะ = ไม่สร้าง ใช้การตรึงตัวตอนถึงจุดแทน
--   ทางเดินเดิม: noclip เปิดตลอด = ตัวละคร CanCollide=false = ไม่มีพื้นให้ยืน
--     แก้ด้วยการฆ่า velocity ทุกเฟรม (startAntiSink) = แค่ชะลอ ไม่กันตก
--       (gravity เติมความเร็วหลัง step ของ engine = ยังไหลลง ~3.3 studs/วิ
--        พอถึงระดับน้ำ เกมจะสลับเป็น "กำลังว่าย" -> FishingController
--          ยกเลิก session ตกปลา -> cast ถัดไปโดน "Finish what you are doing first")
--     ที่ใช้จริงตอนนี้ = Anchored ตอนมาถึงจุดแล้ว (S.tools.pin) = ไม่มีพื้นก็ไม่ตก
--   บอสต่างจากนั้น: ต้อง "ยืน" ให้เหยือกตกลงเขตและให้รัศมีคำนวณจากจุดยืน
--     = ต้องมีพื้นจริง -> ใส่แท่นโปร่งใส CanCollide=true ใต้จุดเป้าปลายทาง
--       แล้วเปิด collision กลับตอนถึงปลายทาง = ยืนด้วยกลไกปกติของเกม
--
-- ⚠ FORBIDDEN: ห้ามใช้แท่นนี้เป็นที่ "ตรึงตัวละคร"
--   ห้ามเขียน CFrame หลังสร้างแท่น ห้ามตั้งตำแหน่งตัวละครให้ตรงกับแท่น
--   แท่นคือ "พื้นจริง" ไม่ใช่ "ตำแหน่งที่เราบังคับ"
--   ดูเหตุผลฉบับเต็มที่ tombstone ของ Hold ข้างล่าง
local function clearStandSpot()
    local old = S.standSpot
    S.standSpot = nil
    if old then pcall(function() old:Destroy() end) end
    -- ⚠ เก็บของค้างจากรอบก่อนด้วย
    --   executor เปิด environment ใหม่ทุกครั้งที่รัน = S ใหม่ (S.standSpot = nil)
    --   แต่ Part ที่ parent ไว้ใน Workspace ยังอยู่ = แท่นโปร่งใสกลืนทั้ง Workspace
    local nm = (CONFIG.StandSpot and CONFIG.StandSpot.Name) or "AP_StandSpot"
    local orphan = Workspace:FindFirstChild(nm)
    if orphan then pcall(function() orphan:Destroy() end) end
end

--- สร้าง/คงแท่นยืนใต้จุดเป้า — ทำซ้ำที่เดิมไม่ต้องสร้างใหม่ (กันกระพริบ)
--- คืน Part ที่ใช้งานได้ หรือ nil ถ้าสร้างไม่ได้
local function makeStandSpot(target)
    local cfg = CONFIG.StandSpot
    if not (cfg and cfg.Enabled ~= false and target) then return nil end

    -- ผิวบน = เป้าลงมานิดเดียว แต่ต้องสูงกว่าผิวน้ำเสมอ
    --   ถ้าต่ำกว่าผิวน้ำ ตัวละครที่ยืนบนแท่นจะอยู่ใต้น้ำ -> เกมคิดว่ากำลังว่าย -> ยกเลิก session
    local top = target.Y - (cfg.Drop or 2)
    local surf = swimSurfaceY(target.X, target.Z)
    -- ⚠ ถ้าอ่านระดับน้ำไม่ได้ = ไม่มี controller = ไม่มีทะเลที่นั่น (เกาะ/พื้นดิน)
    --   ถ้าใส่ (surf or top) จะกลายเป็น top + AboveWater = ยกแท่นขึ้นไปทับเป้า
    local minTop = (surf and surf + (cfg.AboveWater or 2)) or top
    if top < minTop then top = minTop end

    local old = S.standSpot
    if old and old.Parent then
        local okC, cf = pcall(function() return old.CFrame end)
        if okC and cf then
            local sameXZ = (Vector3.new(cf.Position.X, 0, cf.Position.Z)
                - Vector3.new(target.X, 0, target.Z)).Magnitude < 1
            local okY = math.abs((cf.Position.Y + (cfg.Height or 20) / 2) - top) < 0.5
            if sameXZ and okY then return old end
        end
    end

    clearStandSpot()
    local okP, part = pcall(function()
        local p = Instance.new("Part")
        p.Name = cfg.Name or "AP_StandSpot"
        p.Anchored = true
        p.CanCollide = true
        p.CanTouch  = true
        -- ⚠ CanQuery ต้องเปิด: Humanoid ยิง raycast หาพื้นใต้ตัว
        --   ถ้าปิด มันจะคิดว่าลอยอยู่ -> สถานะ Freefall -> ถ้าอยู่ระดับน้ำก็ว่าย
        p.CanQuery   = true
        p.Transparency = 1
        p.Size = Vector3.new(cfg.Width or 12, cfg.Height or 20, cfg.Width or 12)
        -- วางให้ผิวบน = top แล้วให้ก้นแท่งลงลึง (หนา 20) = ไม่มีทางทะลุขอบ
        p.CFrame = CFrame.new(target.X, top - (cfg.Height or 20) / 2, target.Z)
        p.Parent = Workspace
        return p
    end)
    if not (okP and part) then
        logWarn("[Prog] สร้างจุดยืนไม่สำเร็จ — ยืนลอยแบบเดิม (ฆ่า velocity แทน)")
        return nil
    end
    S.standSpot = part
    logWarn(("[Prog] จุดยืน: สร้างแท่นใต้ %.0f,%.0f,%.0f (ผิวบน %.0f กว้าง %d) — เปิด collision กลับ")
        :format(target.X, target.Y, target.Z, top, cfg.Width or 12))
    return part
end

--- ถึงปลายทางแล้ว — จัดการเรื่อง "มีพื้นให้ยืนไหม"
--- ⚠ wantSpot = true เฉพาะตอนไปตกบอสเท่านั้น (ผู้ใช้สั่ง 2026-10-16)
---   ทุกจุดอื่น "ไม่สร้างพื้น": noclip เปิดค้างไว้เหมือนเดิม
---   ให้ startAntiSink() จับตัวนิ่งที่จุดเดิมแทน (ตรงกับ CONFIG.Noclip:
---   เปิดค้างตลอดการทำงาน ไม่มีจุดที่ปิด)
--- ⚠ ตอนบอสต้องได้ทั้งแท่น และ collision กลับ พร้อมกันเสมอ:
---   มีแท่นแต่ noclip ยังเปิด   -> ตัวละคร CanCollide=false = ทะลุแท่น = ของเปล่า
---   collision เปิดแต่ไม่มีแท่น -> ตกลงไปถึงระดับน้ำ = ยกเลิก session ตกปลา
local function standAt(target, wantSpot)
    if not wantSpot then
        -- ⚠ ไม่มีแท่น = ต้องกลับไปอยู่ในโหมด noclip เหมือนตอนออกเดินทาง
        --   (เพิ่งออกจากบอส = noclip ถูกปิดไว้เพื่อยืนบนแท่น ถ้าปล่อยไว้
        --    ตัวละครจะยืนบนแท่นที่กำลังถูกลบ = ตกทันที)
        setNoclip(true)
        -- ⚠ ลบแท่นค้างด้วย เผื่อเพิ่งออกจากบอสแล้วสั้น ๆ ในระยะที่ไม่ได้เดินทาง
        --   (goToFarmSpot จบด้วย standAt ตรง ๆ ถ้ายืนใกล้จุดฟาร์มอยู่แล้ว)
        clearStandSpot()
        -- ⚠ จุดนี้คือปลายทางที่เพิ่งมาถึง
        --   เดิมเขียน S.arriveAt = target ก่อนเรียก pin() = "จำว่าถึงแล้ว" แม้ pin() จะปฏิเสธ
        --   แล้ว pin() ที่ถูกเรียกทีหลังโดยไม่มี argument (ensureNotSwimming) จะเอา
        --   จุดปลอมนั้นไปเทียบ = คิดว่าอยู่ที่จุดฟาร์มทั้งที่โดนดึงกลับไปแล้ว
        --   ตอนนี้ pin() บันทึก S.arriveAt เองเฉพาะตอนที่ยกแรงสำเร็จเท่านั้น
        S.tools.pin(target)
        return false
    end
    -- ⚠ บอสต่างจากนั้น: มีแท่นจริง + collision กลับ → gravity ต้องทำงานปกติ
    --   ถ้ายัง Anchored อยู่ = ยืนลอยเหนือแท่น = ไม่ยืนบนพื้นจริง
    --   และต้องล้าง S.arriveAt ทิ้งด้วย ไม่งั้น pin() รอบหลังจะเอาจุดนี้มาตรึงทับ
    S.arriveAt = nil
    S.tools.releasePin()
    local ok = makeStandSpot(target) ~= nil
    if ok then setNoclip(false) end
    return ok
end


local function house1StandPoint()
    local house = findHouse1()
    if not house then
        logWarn("[Prog] ไม่พบ House1")
        return nil
    end
    local center = modelCenter(house)
    if not center then
        logWarn("[Prog] หา center ของ House1 ไม่ได้")
        return nil
    end

    -- กฎหลัก: กลางบ้าน - House1Drop
    local wantY = center.Y - CONFIG.House1Drop

    -- กันหลุดใต้พื้น: ray จากเหนือ center เสมอ เก็บทุกผิวแล้วเอาต่ำสุดที่ไม่ใช่ของบ้าน
    local skip = {}
    local char = LocalPlayer and LocalPlayer.Character
    if char then table.insert(skip, char) end
    local hits = allSurfacesDown(center.X, center.Z, center.Y + 30, skip)
    local groundY = nil
    for _, h in ipairs(hits) do
        local inst = h.Instance
        if not (inst and inst:IsDescendantOf(house)) then
            groundY = h.Position.Y
        end
    end

    local y = wantY
    if groundY and y < groundY then
        -- เป้าต่ำกว่าผิวพื้นจริง = จะยืนฝังใต้ดิน -> ยกขึ้นมาที่ผิวพื้น
        y = groundY
    end

    return Vector3.new(center.X, y, center.Z)
end

--- tween 3 เฟสแบบมุดลง (ตามที่ผู้ใช้ต้องการ):
---   1) มุดลงใต้ตัวเองตรงที่ยืนอยู่  -> ไม่หาน้ำ ไม่ออกจากจุด แค่ลงตรงลง
---   2) tween ไปใต้จุดที่จะไป        -> ข้ามทางใต้ดิน/ใต้น้ำ
---   3) tween ขึ้นที่จุดเป้า          -> โผล่ขึ้นมาที่จุดเป้า
S.tools.diveRaw = function(target, label)
    local hrp = root()
    if not hrp then return false end

    -- ⚠ จุดยืนของปลายทางเก่าใช้ไม่ได้แล้ว (กำลังจะไปที่อื่น) -> ลบทิ้งก่อน
    clearStandSpot()
    -- ⚠ เดินทางต้องทะลุได้ ไม่งั้นชนเรื่องกลางทาง = เปิด noclip ก่อน
    --   ⚠ ทางนี้ไม่ปิด noclip ตอนถึง (ผู้ใช้สั่ง 2026-10-16: ไม่สร้างพื้นแล้ว
    --     นอกจากตกบอส = คง noclip เปิดค้าง ให้ startAntiSink จับตัวนิ่งที่จุดเดิม)
    setNoclip(true)

    if not CONFIG.TweenViaWater then
        local arrived = tweenTo(target, label)
        if arrived then standAt(target, false) end
        return arrived
    end

    -- เฟส 1: มุดลงใต้ตัวเองที่ยืนอยู่ตอนนี้ (X/Z เดิมไม่ขยับ)
    local cx, cz = hrp.Position.X, hrp.Position.Z
    local surfY = swimSurfaceY(cx, cz) or getWaterY()
    local diveY = surfY - CONFIG.UnderwaterDepth
    if diveY >= hrp.Position.Y then
        -- ผิวน้ำสูงกว่าหรือเท่ากับเรา = อยู่ใต้น้ำอยู่แล้ว -> ลงต่ำกว่าตัวเองตามลำดับ
        diveY = hrp.Position.Y - CONFIG.UnderwaterDepth
    end
    -- ทุกเฟสต้องตรวจผล: ถ้าเฟสไหนล้ม ลองซ้ำหนึ่งครั้ง แล้วถ้ายังล้มให้บอกชื่อเฟสและเลิก
    --   (เดิมทิ้งผล = เฟส 3 ลากเส้นตรงข้ามทะเลจากผิวน้ำโดยไม่มี log บอกว่าเฟสไหนพัง)
    local function phase(pos, name)
        if tweenTo(pos, label .. name) then return true end
        logWarn(("[Prog] MOVE[%s]: เฟส %s ไม่สำเร็จ — ลองซ้ำอีกครั้งจากตำแหน่งจริง"):format(tostring(label), name))
        if tweenTo(pos, label .. name .. "-retry") then return true end
        logWarn(("[Prog] MOVE[%s]: เฟส %s ล้มซ้ำ — เลิกรอบนี้ ให้ผู้เรียกลองใหม่"):format(tostring(label), name))
        return false
    end

    if not phase(Vector3.new(cx, diveY, cz), ":1-มุดลง") then return false end

    -- เฟส 2: tween ไปใต้จุดเป้า
    -- ระดับน้ำปลายทาง: ใช้เกาะที่ใกล้จุดเป้าที่สุด ไม่ใช่เกาะที่เรายืนอยู่ตอนนี้
    local function dstWaterY(p)
        local best, bd = nil, math.huge
        for id, row in pairs(CONFIG.IslandPoints or {}) do
            if type(row) == "table" and row.spawn then
                local d = Vector3.new(row.spawn.X - p.X, 0, row.spawn.Z - p.Z).Magnitude
                if d < bd then best, bd = id, d end
            end
        end
        if best then
            local okW, y = pcall(function() return Catalog.Island.GetWaterY(best) end)
            if okW and type(y) == "number" then return y end
        end
        return getWaterY()
    end
    local dstSurf = swimSurfaceY(target.X, target.Z) or dstWaterY(target)
    if not phase(Vector3.new(target.X, dstSurf - CONFIG.UnderwaterDepth, target.Z), ":2-ใต้เป้า") then
        return false
    end

    -- เฟส 3: tween ขึ้นที่จุดเป้า
    local arrived = tweenTo(target, label .. ":3-ขึ้น")
    if arrived then standAt(target, false) end
    return arrived
end

--- ตัวห่อ: error ข้างในไม่หลุดออกไปค้างธง S.moving / S.traveling ของผู้เรียก
local function tweenDiveTo(target, label)
    local okD, res = pcall(S.tools.diveRaw, target, label)
    if not okD then
        logWarn(("[Prog] MOVE[%s]: tweenDiveTo error — %s"):format(tostring(label), tostring(res)))
        return false
    end
    return res
end

-- ══════════════════════════════════════════════════
-- 8) FISHING (under-self + map-guard override + skill + x10)
-- ══════════════════════════════════════════════════
--- ปลด readonly ของตารางย่อยใน FishingConfig คืนตารางนั้น (nil = ถอดไม่ได้)
--- ────────────────────────────────────────────────────────────
--- FishingConfig.lua จบด้วย table.freeze(u0) และ table.freeze ของ Roblox
---   freeze แบบ recursive -> ทั้ง .Cast และ .LuckBar เขียนทับไม่ได้
---   เขียนตรงๆจะ error และ pcall เดี่ยวกลืนเงียบ ไม่มีทางรู้ว่าเขียนสำเร็จ
---   -> ทดสอบเขียนจริงหลังถอด readonly เสมอ คืน nil ถ้ายังเขียนไม่ได้
---      ผู้เรียกเลยตัดสินใจได้เองว่าจะทำงานต่อแบบไม่มี override หรือไม่
local function unfreezeConfig(key)
    local t = FishingConfig[key]
    if type(t) ~= "table" then return nil end
    if setreadonly ~= nil then pcall(function() setreadonly(t, false) end) end
    if makewriteable ~= nil then pcall(function() makewriteable(t) end) end
    local mt = getrawmetatable and getrawmetatable(t)
    if type(mt) == "table" and setreadonly ~= nil then pcall(function() setreadonly(mt, false) end) end
    -- เขียนค่าชั่วคราวแล้วอ่านกลับ = พิสูจน์ว่าเขียนได้จริง แล้วลบทิ้งให้สะอาด
    if not (pcall(function() t.__probe = true end) and t.__probe == true) then return nil end
    t.__probe = nil
    return t
end

--- ตาราง config ที่ปลด readonly แล้ว (nil = ถอดไม่ได้ ให้เกมใช้ค่าของมันเอง)
local CastCfg = nil     -- .Cast = ระยะเหวี่ยง + พื้นเวลากดปุ่ม

--- หลอด luck ตามธรรมชาติวิ่ง 0->1 ใน CycleMin/2 = 0.4-0.6s
---   = ยืนรอเปล่าเกือบครึ่งวินาทีทุกครั้งที่เหวี่ยง แล้วกดตอนหลอดขึ้น 0.92
--- ย่อรอบให้สั้นที่สุด -> u290 ถึง 1 ใน 1 เฟรม -> castUnderNative ปล่อยทันทีได้เลย
---   ค่าที่ยิงไปคือ 1.0 ตามปกติ ไม่ต่างจากจังหวะที่หลอดวิ่งถึงพีคจริง
---   (server มี FailReason.InvalidLuck แต่เป็น range check 1.0 ผ่าน)
--- ⚠ ห้าม 0 เด็ดขาด — OnTick หารด้วย u292 (2/u292) จะเป็น infinity
local function instantLuckBar()
    local lb = unfreezeConfig("LuckBar")
    if not lb then
        logWarn("[Prog] ถอด readonly LuckBar ไม่สำเร็จ — ยังต้องรอหลอด luck ตามปกติ")
        return
    end
    lb.CycleMin, lb.CycleMax = 0.001, 0.001
end

--- หลังตกปลา เกมรอ Loot.ConfirmReadyDelay ก่อนยิง FishLootConfirm
---   แล้วค่อย task.delay(General.CastCancelDelay, ResetAll) = 0.75 + 0.5 = 1.25s
--- ทดสอบแล้ว 1.25 คือขั้นต่ำจริงของ server — ย่อแล้วโดนทั้ง
---   SessionActive ("Finish what you are doing first") และ CastCooldown ("Casting too fast")
---   General.CastCancelDelay จึงไม่แตะ: ไม่มีทางเร็วขึ้น แต่เสี่ยงโดน rate limit ซ้อน
local function tightenCaughtCooldown()
    local loot = unfreezeConfig("Loot")
    if loot then loot.ConfirmReadyDelay = CONFIG.LootConfirmDelay end
end


--- ปลดล็อก CastMapGuard.IsBlocked เสมอ (เกมใช้บล็อกการเหวี่ยงข้ามแมพ) -> เหวี่ยงได้ทุกจุด
local function overrideCastMapGuard()
    -- ⚠ ModuleScript มีลูกได้ และ script.X อ่านลูกได้ — FishingController เป็น ModuleScript
    --   ที่มีลูกชื่อ CastMapGuard อยู่จริง (เกมเรียกด้วย require(script.CastMapGuard) ที่ :47)
    --   แต่ UnitController *ไม่* มีลูกชื่อ UnitController -> ต้องเรียกแบบ flat เท่านั้น
    --   (index ชื่อที่ไม่มีจริงจะ throw ตอนคำนวณ argument ของ req() = อยู่นอก pcall)
    local guard = req(ReplicatedStorage.Controllers.FishingController.CastMapGuard, "CastMapGuard")
    if not guard or type(guard.IsBlocked) ~= "function" then
        logWarn("[Prog] ไม่พบ CastMapGuard.IsBlocked")
        return false
    end
    local alwaysFalse = function() return false end
    if hookfunction ~= nil then
        local ok = pcall(function() hookfunction(guard.IsBlocked, alwaysFalse) end)
        if ok then return true end
    end
    if setreadonly ~= nil then pcall(function() setreadonly(guard, false) end) end
    if makewriteable ~= nil then pcall(function() makewriteable(guard) end) end
    return pcall(function() guard.IsBlocked = alwaysFalse end)
end

-- native input
local Cast = { action = nil, pressedConns = {}, releasedConns = {} }

local function findInputAction()
    if Cast.action then return Cast.action end
    local ok, inst = pcall(function()
        local inputs = ReplicatedStorage:FindFirstChild("Inputs")
        local fc = inputs and inputs:FindFirstChild("FishingContext")
        local fa = fc and fc:FindFirstChild("FishingPrimary")
        if fa and fa:IsA("InputAction") then return fa end
        return ReplicatedStorage:FindFirstChild("FishingPrimary")
    end)
    Cast.action = ok and inst or nil
    return Cast.action
end

local function collectPressedConns()
    Cast.pressedConns, Cast.releasedConns = {}, {}
    if not findInputAction() then return false end
    if getconnections == nil then return false end
    local ok = pcall(function()
        Cast.pressedConns  = getconnections(Cast.action.Pressed)
        Cast.releasedConns = getconnections(Cast.action.Released)
    end)
    return ok and #Cast.pressedConns > 0
end

local function fireConnections(conns)
    local fired = 0
    for _, c in ipairs(conns) do
        local ok = false
        if type(c) == "function" then ok = pcall(c)
        elseif type(c) == "table" then
            if type(c.Function) == "function" then ok = pcall(c.Function)
            elseif type(c.Fire) == "function" then ok = pcall(function() c:Fire() end)
            elseif fireconnection ~= nil then ok = pcall(fireconnection, c) end
        end
        if ok then fired = fired + 1 end
    end
    return fired
end

--- เหวี่ยงใต้ตัวพอดี (dist=0) ผ่าน native input
local function castUnderNative()
    local fc = getFishingController()
    if not fc then return false end
    if not findInputAction() or #Cast.pressedConns == 0 then return false end
    if fireConnections(Cast.pressedConns) == 0 then return false end

    local t0 = os.clock()
    local reachedThrowing = false
    while S.running and os.clock() - t0 < 3 do
        local st = fc.GetState and fc:GetState() or nil
        if st == "Throwing" then reachedThrowing = true break end
        RunService.Heartbeat:Wait()
    end
    if not reachedThrowing then
        fireConnections(Cast.releasedConns)
        return false
    end
    local targetLuck = (CONFIG.CastPerfect and CONFIG.CastLuckTarget) or 0.5
    while S.running do
        local luck = fc.GetLuckBarValue and fc:GetLuckBarValue() or 0
        if luck >= targetLuck or os.clock() - t0 > CONFIG.CastHoldTime + 2.0 then
            return fireConnections(Cast.releasedConns) > 0
        end
        RunService.Heartbeat:Wait()
    end
    return true
end

--- ═══ จับสาเหตุ "Cast failed, please try again" แบบเงียบ ═══
--
---   FishingController.lua:758 ShowCastRejection(reason) -> u344:Show(u458[reason].text)
---   บรรทัด 729-755: FailReason 6 ตัวใช้ข้อความเดียวกันเป๊ะ คือ
---     CastFailed / TooFar / NoCharacter / Swimming / Seated / InvalidLuck / InvalidTarget
---   = ดูจากหน้าจอแยกไม่ออกว่าตัวไหน และ client ตัดสินได้แค่ 2 ตัว
---     (Swimming/Seated ใน ResolveLocalCastGates:818-940 ซึ่งออก "ก่อน" animation)
---     ที่เหลือทั้งหมด server เป็นคนตัดสิน และ ServerScriptService ไม่มีในดัมป์ = อ่านโค้ดไม่ได้
---
---   ⚠ วิธีเดียวที่รู้แน่โดยไม่ต้องเดา: FishReset เป็น RemoteEvent ตัวเดียวกับที่เกมใช้
---     connect() ผูก OnClientEvent ตรง ๆ = ได้ reason ดิบเสมอ แม้ตัวเกมจะทิ้ง
---     (FishingController.lua:2908 `if Idling == State.Idling then return end`)
---     นี่คือเหตุผลที่ตอนก่อนหาไม่เจอ: ตัวเกมกรองทิ้งก่อนถึงจะได้ข้อความ
---
---   ⚠ ห้ามนับเวลาเอง (ผู้ใชาสั่ง) ที่นี่มีแต่จำนวนครั้ง + เหตุผล + บริบทของรอบเหวี่ยง
---   ⚠ ห้ามพิมพ์เอง = ผู้ใชาสั่งปิด warn ทั้งหมด อ่านทีหลังด้วย _G.FishingCastReport()
CastFail = { total = 0, byReason = {}, last = nil, pending = nil }
-- ⚠ เหตุผลที่แปลว่า "โยนเข้าไปแล้วไม่ได้" ทั้ง 7 ตัวที่ใช้ข้อความ CastFailedText เดียวกัน
--   (FishingController.lua:729-755) = ทั้งหมดนับเป็นความล้มเหลวของบอสได้
CAST_FAILED_REASONS = {
    CastFailed = true, TooFar = true, NoCharacter = true, Swimming = true,
    Seated = true, InvalidLuck = true, InvalidTarget = true,
}
_G.FishingCastFail = CastFail

--- จดว่าเราเพิ่งเหวี่ยงไปที่ไหน ระยะเท่าไร เกาะไหน -> จับคู่กับ FishReset ทีหลัง
function CastFail_mark(dist, hrp, baitMin, baitMax)
    CastFail.pending = {
        dist    = math.floor((dist or 0) * 10) / 10,
        baitMin = baitMin,
        baitMax = baitMax,
        island  = currentIslandId(),
        x = hrp and math.floor(hrp.Position.X) or nil,
        y = hrp and math.floor(hrp.Position.Y) or nil,
        z = hrp and math.floor(hrp.Position.Z) or nil,
    }
end

--- server สั่งรีเซ็ต = บันทึกเหตุผลดิบ (ไม่เดาแทน ไม่พิมพ์)
function CastFail_note(reason)
    local r = tostring(reason)
    local st = S.state
    local fcN = getFishingController()
    if fcN and fcN.GetState then
        local okN, sN = pcall(function() return fcN:GetState() end)
        if okN and type(sN) == "string" and sN ~= "" then st = sN end
    end
    CastFail.total = CastFail.total + 1
    CastFail.byReason[r] = (CastFail.byReason[r] or 0) + 1
    CastFail.last = {
        reason = r,
        state  = st,
        island = currentIslandId(),
        cast   = CastFail.pending,     -- nil = session นี้ไม่ได้มาจากการเหวี่ยงของเรา
    }
    CastFail.pending = nil
end

--- ผู้ใช้เรียกเองในคอนโซลหลังเจออาการ (เงียบจนกว่าจะกดเอง)
function _G.FishingCastReport()
    print("── Cast fail ── รวม " .. tostring(CastFail.total) .. " ครั้ง")
    if CastFail.total == 0 then
        print("   (ยังไม่เคยโดน FishReset เลย)")
        return
    end
    local keys = {}
    for r in pairs(CastFail.byReason) do keys[#keys + 1] = r end
    table.sort(keys)
    for _, r in ipairs(keys) do
        print("   " .. r .. "  x" .. tostring(CastFail.byReason[r]))
    end
    local l = CastFail.last
    if l then
        print("   ล่าสุด: " .. tostring(l.reason)
            .. "  state=" .. tostring(l.state)
            .. "  island=" .. tostring(l.island))
        if l.cast then
            print("   จากการเหวี่ยง: ระยะ " .. tostring(l.cast.dist)
                .. "  bait=" .. tostring(l.cast.baitMin) .. ".." .. tostring(l.cast.baitMax)
                .. "  ที่ (" .. tostring(l.cast.x) .. "," .. tostring(l.cast.y) .. "," .. tostring(l.cast.z) .. ")")
        else
            print("   จากการเหวี่ยง: ไม่ใช่รอบที่เราเพิ่งเหวี่ยง (session ค้างจากก่อน)")
        end
    end
end

--- เหวี่ยงไปน้ำเปิด: หาจุดน้ำ -> ตั้งระยะ -> หันหน้า -> set Throwing -> native cast
local function castToNearestWater()
    local hrp = root()
    if not (hrp and hrp:IsA("BasePart")) then return false end

    -- ⚠ ใน raid: GetCurrentIslandId() = "" ⇒ getWaterY() คืน SEA_LEVEL (3) ซึ่งผิด
    --   และ World.Islands ไม่มีอยู่ในแมป raid -> ต้องใช้ raidCastTarget (WaterBody + indicator)
    local water = (S.raidActive and raidCastTarget and raidCastTarget()) or findNearestOpenWater(hrp.Position)
    if not water then return false end

    local dist = Vector3.new(water.X - hrp.Position.X, 0, water.Z - hrp.Position.Z).Magnitude
    -- CalcTargetPos: dist = BaitMinDist + luck*(BaitMaxDist-BaitMinDist)
    --   Min==Max -> ระยะคงที่ = จุดน้ำที่เจอ ไม่ขึ้นกับ luck
    --   ถ้าปลด readonly ไม่ได้ เกมยังยิงได้ (30+luck*30 < ServerMaxDistance 80)
    --   แต่จะตกพ้นจุดน้ำถ้าน้ำอยู่ใกล้กว่านั้น
    if CastCfg then CastCfg.BaitMinDist, CastCfg.BaitMaxDist = dist, dist end
    faceTowards(water)

    -- ⚠ จดบริบทรอบนี้ไว้ก่อนยิง เพื่อจับคู่กับ FishReset ที่จะมาทีหลัง
    --   baitMin/baitMax คือค่าที่ "ได้จริง" หลังเขียนทับ ถ้า setreadonly ไม่ผ่าน
    --   ค่าจะยังเป็นของเกม (30..60) แทนระยะที่หาเจอ = บอกได้ว่าตกไปไกลเกินจริงหรือไม่
    CastFail_mark(dist, hrp, CastCfg and CastCfg.BaitMinDist, CastCfg and CastCfg.BaitMaxDist)

    -- ตั้ง state ก่อน cast (สำคัญ! ให้ state machine เดินต่อไปได้)
    S.state = "Throwing"
    S.castAckDeadline = os.clock() + (FishingConfig.Cast.AckTimeout or 8)

    return castUnderNative()
end


--- ═══ ตัวบล็อกปุ่มเหวี่ยงที่ "เงียบ" (อ่านจาก FishingController.OnFishingPrimaryPressed) ═══
--- ปุ่มเหวี่ยงของเกม return ทิ้งเฉยๆ (ไม่มี FishReset ไม่มี log ไม่มีข้อความ) เมื่อ:
---   • UIController:IsGameplayBlocked() = มีหน้าจอ UI เปิดค้างอยู่ (เช่น หน้ารางวัลบอส)
---   • LootController:IsGrantLootActive() = หน้าต่างรับ loot ค้าง
---   • ตัวละครตาย / นั่ง / ว่ายน้ำ
--- สคริปต์เดิมกดแล้วรอ 3 วิ ไม่เห็น Throwing ก็ปล่อย แล้ววนใหม่ไม่รู้จบ (state สลับ Throwing<->Idling
--- เหวี่ยงค้างที่เดิม) -> คืน (เหตุผล[], ตัวแก้[]) เพื่อให้บอกได้ว่าติดอะไรและเคลียร์ได้
S.tools.castBlockers = function()
    local why, fix = {}, {}

    local okU, ui = pcall(function() return Client and Client.GetController("UIController") end)
    if okU and ui and type(ui.IsGameplayBlocked) == "function" then
        local okB, blocked = pcall(function() return ui:IsGameplayBlocked() end)
        if okB and blocked then
            local nm = "?"
            pcall(function() nm = tostring(ui:GetActive()) end)
            why[#why + 1] = "หน้าจอ UI เปิดค้าง (" .. nm .. ")"
            fix[#fix + 1] = function() pcall(function() ui:CloseAll() end) end
        end
    end

    local okL, loot = pcall(function() return Client and Client.GetController("LootController") end)
    if okL and loot then
        if type(loot.IsGrantLootActive) == "function" then
            local okA, act = pcall(function() return loot:IsGrantLootActive() end)
            if okA and act then
                why[#why + 1] = "หน้าต่างรับ loot ค้าง (grant)"
                fix[#fix + 1] = function()
                    pcall(function() loot:ResetGrant() end)
                    pcall(function() loot:Reset() end)
                end
            end
        end
        if type(loot.IsFishingLootActive) == "function" then
            local okF, act2 = pcall(function() return loot:IsFishingLootActive() end)
            if okF and act2 and S.state == "Idling" then
                why[#why + 1] = "หน้าต่าง loot ปลาค้าง"
                fix[#fix + 1] = function() pcall(function() loot:Reset() end) end
            end
        end
    end

    local char = LocalPlayer and LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        if hum.Health <= 0 then
            why[#why + 1] = "ตัวละครตาย (รอเกิดใหม่)"
        end
        if hum.Sit or hum.SeatPart then
            why[#why + 1] = "ตัวละครนั่งอยู่"
            fix[#fix + 1] = function() pcall(function() hum.Sit = false end) end
        end
    end

    local sc = Client and (Client.GetController("Swimming") or Client.GetController("SwimmingController"))
    if sc and type(sc.IsSwimming) == "function" then
        local okS, sw = pcall(function() return sc:IsSwimming() end)
        if okS and sw then why[#why + 1] = "เกมคิดว่ากำลังว่ายน้ำ" end
    end

    return why, fix
end

--- เคลียร์ตัวบล็อกที่แก้ได้ทันที (ใช้ตอนบอสจบ ฯลฯ) คืนจำนวนที่เจอ
S.tools.clearBlockers = function()
    local why, fix = S.tools.castBlockers()
    for _, f in ipairs(fix) do pcall(f) end
    return #why
end

--- เรียกทุกครั้งที่เหวี่ยงไม่ออก (castToNearestWater คืน false) — ไม่ได้ถูกเซิร์ฟปฏิเสธ แต่ปุ่มไม่ทำงาน
S.tools.onCastRefused = function()
    S.castRefused = (S.castRefused or 0) + 1
    local t = nowReal()

    local why, fix = S.tools.castBlockers()
    if #why > 0 then
        if t - (S.blockLogAt or 0) > 20 then
            S.blockLogAt = t
            logWarn(("[Prog] เหวี่ยงไม่ออก #%d — เกมบล็อกปุ่ม: %s — เคลียร์ให้")
                :format(S.castRefused, table.concat(why, " · ")))
        end
        for _, f in ipairs(fix) do pcall(f) end
        return true
    end

    -- ไม่เจอตัวบล็อกที่รู้จัก: พิมพ์สภาพรวมให้ดู (ทุก 60 วิ) จะได้รู้ว่าติดที่ไหน
    if S.castRefused >= 5 and t - (S.refuseDiagAt or 0) > 60 then
        S.refuseDiagAt = t
        pcall(function()
            local fc = getFishingController()
            local gs = fc and fc.GetState and fc:GetState() or "?"
            local data = fetchData()
            local full = data and isSatchelFull(data)
            local rod = data and data.RodEquip
            local h = root()
            logWarn(("[Prog] เหวี่ยงไม่ออก #%d (ไม่เจอตัวบล็อกที่รู้จัก) · เกม=%s · กระเป๋าเต็ม=%s · เบ็ด=%s · เกาะ=%s · hrp=%s · บอส=%s · แท่น=%s · gravityForce=%s")
                :format(S.castRefused, tostring(gs), tostring(full), tostring(rod),
                    tostring(currentIslandId()),
                    h and ("%d,%d,%d"):format(h.Position.X, h.Position.Y, h.Position.Z) or "nil",
                    tostring(S.bossHolding), tostring(S.standSpot ~= nil), tostring(S.grav ~= nil)))
        end)
    end

    -- ยังไม่ออกนานเกินไป (~40 รอบ ≈ 2-3 นาที) = ลองขยับตำแหน่งใหม่ (ไม่เกิน 1 ครั้ง/5 นาที)
    if S.castRefused >= 40 and t - (S.relocAt or 0) > 300 then
        S.relocAt = t
        S.castRefused = 0
        logWarn("[Prog] เหวี่ยงไม่ออกต่อเนื่องนาน — ปิดหน้าจอ/loot ที่ค้าง แล้วว่ายออกจากจุดและกลับเข้าจุดฟาร์มใหม่")
        S.moving = true
        pcall(function()
            pcall(function() P.FishCancel:Fire() end)
            S.tools.clearBlockers()
            local h = root()
            S.tools.releasePin()
            if h then tweenDiveTo(h.Position + Vector3.new(0, 0, -60), "relocate-away") end
            goToFarmSpot()
        end)
        S.moving = false
    end
    return false
end

-- SKILLS (Moveset)
local Skill = { rodController = nil, rodId = nil, skillSlots = 0, slotNames = {} }

local function getRodController()
    if Skill.rodController then return Skill.rodController end
    if not Client then return nil end
    if not Client.HasController("RodController") then
        req(ReplicatedStorage.Controllers.RodController, "RodController")
    end
    Skill.rodController = Client.GetController("RodController")
    return Skill.rodController
end

local function getRodData()
    local data = fetchData()
    if not data then return nil end
    local rodId = data.RodEquip
    local rodData = rodId and data.Rods and data.Rods[rodId]
    local rodMeta = rodId and Catalog and Catalog.Rod.GetById and Catalog.Rod.GetById(rodId) or nil
    if rodId ~= Skill.rodId then
        Skill.rodId = rodId
        Skill.skillSlots = (rodMeta and rodMeta.skillSlots) or 4
        Skill.slotNames = {}
        for i = 1, Skill.skillSlots do
            Skill.slotNames[i] = ("Slot%d"):format(i)
        end
    end
    return rodId, rodData, rodMeta
end

-- AUTO-HOLD ROD (ถือเบ็ดอัตโนมัติ) — พอร์ตจาก fishing_auto.lua
local Equip = { heldTool = nil, lastEquipCheck = 0 }

--- เช็คว่าถือคันเบ็ดที่ติดตั้งไว้ถูกต้องไหม ถ้าไม่ -> Select(Slot.Rod=1)
--- คืน true ถ้าถือถูกแล้ว / false ถ้าต้องรอให้ server ยืนยันก่อนค่อย cast
local function ensureRodEquipped()
    local rodId, _, _ = getRodData()
    if not rodId or rodId == "" or rodId == "None" then
        return true  -- ไม่มีคันเบ็ดใน PlayerData -> ไม่มีอะไรให้ถือ
    end

    local rc = getRodController()
    local equipped = rc and rc.IsRodEquipped and rc:IsRodEquipped()
    local equippedId = rc and rc.GetEquippedRodId and rc:GetEquippedRodId()

    if equipped and equippedId == rodId then
        return true
    end

    -- กันกดถี่เกิน — sendSlot ของเกม gate ที่ 0.15s (HeldToolController:262)
    --   เอา 0.2 ตาม ถ้าใช้ค่าใหญ่กว่านั้น = เสียเวลาเปล่าโดยไม่ได้ประโยชน์
    if os.clock() - Equip.lastEquipCheck < 0.2 then
        return false
    end
    Equip.lastEquipCheck = os.clock()

    if not Equip.heldTool and Client then
        if not Client.HasController("HeldToolController") then
            req(ReplicatedStorage.Controllers.HeldToolController, "HeldToolController")
        end
        Equip.heldTool = Client.GetController("HeldToolController")
    end
    local htc = Equip.heldTool
    if htc and htc.Select then
        pcall(function() htc:Select(1) end)  -- 1 = BackpackEnums.Slot.Rod
    end

    -- ⚠ ไม่ return false ทันที: Select -> predictSlot -> predictHeld -> Humanoid:EquipTool
    --   เป็นงานฝั่ง client ที่จบทันที (HeldToolController:193) แล้ว OnToolEquipped
    --   ก็เซ็ต u104 ให้ทันทีด้วย (RodController:541) -> IsRodEquipped() เป็นจริง
    --   โดยไม่ต้องรอ server เลย ถ้า return false ตรงนี้ผู้เรียกต้องรอ CastCooldown
    --   ทิ้งเปล่า ~0.8s ต่อครั้งที่เพิ่งสลับเบ็ด จึง poll สั้น ๆ เองแทน
    local t0 = os.clock()
    while os.clock() - t0 < 0.5 do
        task.wait(0.03)
        local rc2 = getRodController()
        if rc2 and rc2.IsRodEquipped and rc2:IsRodEquipped()
           and rc2.GetEquippedRodId and rc2:GetEquippedRodId() == rodId then
            return true
        end
    end
    return false
end

--- ระยะเวลาที่ "ตัวเกมเอง" คาดว่าเฟส Casting จะอยู่
---   ที่มา: RodController.lua:990 ปล่อยเฟส Casting เมื่อ
---         os.clock() - castingStart >= GetNetworkPing() + FishingConfig.Latency.MaxCompensation
---   ใช้แทนตัวเลข 30 วินาทีเดิม ซึ่งไม่มีที่มาจากดัมป์ที่ไหนเลย
---   และยาวกว่าคัสต์จริงของสกิลปกติ (3.5-9s) ราว 75 เท่า
local function skillCastGuard()
    local lat = FishingConfig and FishingConfig.Latency
    local comp = (lat and lat.MaxCompensation) or 0.3
    return LocalPlayer:GetNetworkPing() + comp
end

local function hookSkillCooldown()
    if S.skillCooldownHooked then return end
    local rc = getRodController()
    local pkt = rc and rc.ReplicatedSkillCooldown
    if not pkt or not pkt.OnClientEvent then return end
    local ok = pcall(function()
        pkt.OnClientEvent:Connect(function(tbl)
            if typeof(tbl) ~= "table" then return end
            for slotName, st in pairs(tbl) do
                if type(slotName) == "string" and typeof(st) == "table" then
                    local phase = st.phase
                    S.slotServerAt[slotName] = true
                    -- ⚠ "Casting" = กำลังคัสต์อยู่ ไม่ใช่ "พร้อมยิงแล้ว"
                    --   เดิมบล็อกทิ้งไว้ 30 วินาที -> ช่องนั้นตายทั้งรอบตกปลา
                    --   ที่ผิดกว่านั้นคือ 30 วินาทีนับจากตอนเห็น event ซึ่งช้ากว่าจุดที่เกม
                    --   ปล่อยจริงเสมอ เพราะเกมส่ง Casting ก่อน แล้วค่อยส่ง Cooldown ทับ
                    --   ตอนนี้ใช้สูตรเดียวกับที่เกมเองใช้ปล่อยเฟส + Cooldown/Ready ที่ server
                    --   ส่งมาหลังจากนี้เขียนทับอยู่ดี ถ้า server ยอมรับ cooldown จริง
                    if phase == "Casting" then
                        S.slotReadyAt[slotName] = os.clock() + skillCastGuard()
                    elseif phase == "Cooldown" then
                        S.slotReadyAt[slotName] = os.clock() + (tonumber(st.remaining) or 0)
                    elseif phase == "Ready" then
                        S.slotReadyAt[slotName] = 0
                    end
                end
            end
        end)
    end)
    S.skillCooldownHooked = ok
end

--- ล้างเฉพาะ "การเดา" ของเราเอง (ค่าที่เราใส่ตอนยิง) — ห้ามล้างค่าที่ server ส่งมา
---   เดิมล้างทั้งตารางทุกครั้งที่ขึ้นรอบตกใหม่ แปลว่า "ลืม" cooldown ที่ server เพิ่งบอก
---   แล้วยิงช่องเดิมซ้ำทันทีในเฟรมแรก = สกิลเสียรอบเปล่าทุกครั้งที่ตกได้ปลา
local function clearClientSkillGuards()
    for slotName in pairs(S.slotReadyAt) do
        if not S.slotServerAt[slotName] then S.slotReadyAt[slotName] = 0 end
    end
end

local function tryUseSkillSlot(i)
    if not CONFIG.Skills or S.state ~= "Reeling" then return false end
    local rc = getRodController()
    if not rc or not rc.Moveset then return false end
    local fc = getFishingController()
    if fc and fc.IsAutoSession and fc:IsAutoSession() then return false end
    if fc and fc.IsReeling and not fc:IsReeling() then return false end

    -- เกมเช็คเงื่อนไขนี้ก่อนยิง Moveset (RodController:976) — ถ้าเราไม่เช็ค เราจะเป็นคนยิง
    --   ทิ้งที่เกมไม่ยอมรับ = สกิลนั้นเสียรอบเปล่า ๆ
    if LocalPlayer:GetAttribute("IsUsingSkill") then return false end

    local slotName = Skill.slotNames[i]
    if not slotName then return false end
    local now = os.clock()
    if (S.slotReadyAt[slotName] or 0) > now then return false end
    if (now - S.lastSkillAt) < CONFIG.SkillMinGap then return false end

    local _, rodData = getRodData()
    if not (rodData and rodData.BookSlots) then return false end
    local bookId = rodData.BookSlots[slotName]
    if not bookId or bookId == "" then return false end

    local ok, err = pcall(function() rc.Moveset:Fire(slotName, bookId) end)
    if not ok then logWarn(("[Prog] Moveset:Fire ล้มเหลว: %s"):format(tostring(err))) return false end

    S.lastSkillAt = now
    -- slotReadyAt เป็นแค่ "กันยิงซ้ำก่อนเกมบอก" เกมจะส่ง ReplicatedSkillCooldown มาแก้จริง
    --   ทำเครื่องหมายว่านี่เป็น "การเดาของเรา" เพื่อให้ clearClientSkillGuards() ล้างได้ถูกตัว
    --   แต่ไม่ล้าง cooldown ที่ server บอกมา (slotServerAt = true)
    S.slotReadyAt[slotName] = now + math.max(CONFIG.SkillCastWait, 0.3)
    S.slotServerAt[slotName] = false
    -- ⚠ หยุด "กดตี" ช่วงคัสต์สกิล (แอนิเมชันกำลังออก)
    --   แต่ห้ามไปบล็อกสกิลตัวอื่นด้วย — ต่อให้เกมเปิดหน้าต่างสกิลค้างอยู่
    --   สกิลถัดไปต้องยิงต่อได้ทันที ไม่ใช่รอ skillWindowUntil หมด
    S.skillWindowUntil = now + math.max(CONFIG.SkillCastWait * 0.5, 0.25)
    return true
end

local function useNextSkill()
    if not CONFIG.Skills or S.state ~= "Reeling" then return end
    local now = os.clock()
    if (now - S.lastSkillAt) < CONFIG.SkillMinGap then return end
    local _, rodData = getRodData()
    if not rodData or not rodData.BookSlots then return end

    local ready = {}
    for i = 1, #Skill.slotNames do
        local slotName = Skill.slotNames[i]
        local bookId = rodData.BookSlots[slotName]
        if bookId and bookId ~= "" and (S.slotReadyAt[slotName] or 0) <= now then
            local meta = Catalog and Catalog.Skill.GetById and Catalog.Skill.GetById(bookId)
            table.insert(ready, { i = i, score = skillPriority(meta) })
        end
    end
    if #ready == 0 then return end
    -- ⚠ table.sort ของ Lua ไม่ stable: สกิลที่คะแนนเท่ากันจะสลับที่กันได้ทุกเฟรม
    --   เพิ่ม index เป็นตัวตัดสินชั้นที่สอง -> เรียงเดิมทุกครั้ง สกิลอันดีกว่าถูกเลือกเสมอ
    table.sort(ready, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.i < b.i
    end)
    for _, r in ipairs(ready) do
        if tryUseSkillSlot(r.i) then return end
    end
end

-- SEND WRAPPERS
local function sendReelPull()
    ReelSeq = ReelSeq % SEQ_MAX + 1
    P.FishReelPull:Fire(ReelSeq)
end
local function sendFirstPull() P.FishFirstPull:Fire() end
local function sendQTEAck(key) P.FishQTEResponse:Fire(key) end

--- เวลาที่ต้องรอก่อนตอบ QTE (วินาที) — อ่านค่าจากเกมทุกครั้ง ไม่ hardcode
---
--- ⚠ มี "เพดาน" สองชั้น และต้องเอาที่ใหญ่กว่า:
---   FishingConfig.Latency.QteReactionFloor     = 0.1   (ชื่อบอกตรง ๆ ว่า reaction floor)
---   FishingConfig.Counter.StrictInputSettleTime = 0.08 (settle ของ input)
---   ทั้งสองชื่อไม่มีที่ไหนใน client dump ที่อ่านมัน (ยกเว้นตัว config เอง) = อ่านจาก server
---   ใช้แค่ 0.08 จะยังต่ำกว่า reaction floor ของเกม (0.1) อยู่ดี
---
--- ⚠ QteFastPenaltyCount = 5 = ตอบเร็วเกินกี่ครั้งแล้วโดนลงโทษ
---   นี่แหละที่อธิบายอาการ "บางช่วงถูกรัวๆ บางช่วงผิดรัวๆ" ได้ตรงที่สุด
---     = ไม่ใช่สุ่ม แต่คือ 5 ครั้งที่ยิงช้าเกินไปสะสมกันจนโดน penalty แล้วผิดเป็นช่วง ๆ
---
--- CONFIG.QteDelay ถ้า >= 0 = บังคับเอง (ผู้ใช้แก้เอง = ตั้งใจ ไม่แก้ให้)
local function qteSettleDelay()
    if type(CONFIG.QteDelay) == "number" and CONFIG.QteDelay >= 0 then
        return CONFIG.QteDelay
    end
    local settle = (FishingConfig.Counter or {}).StrictInputSettleTime
    local floorT = (FishingConfig.Latency or {}).QteReactionFloor
    local d = 0
    if type(settle) == "number" and settle > d then d = settle end
    if type(floorT) == "number" and floorT > d then d = floorT end
    return d
end

-- ══════════════════════════════════════════════════
-- LOOT WINDOW SUPPRESS (ไม่ให้หน้าต่าง "ได้ปลา" ขึ้นบล็อกตกต่อ)
-- ──────────────────────────────────────────────────
-- ทำไมต้องแก้แบบนี้ (ไม่ใช่แค่แทนที่ ShowCatch ด้วย Promise.resolve())
-- ──────────────────────────────────────────────────
-- LootController:ShowCatch เขียนไว้เอง 2 สาย:
--     local _refs = self._refs
--     if not _refs then
--         a1.logger:warn("Loot UI unavailable; auto-confirming after loot delay")
--         return Promise.delay(FishingConfig.Loot.ConfirmReadyDelay)   -- <-- สายนี้
--     end
--     ... SetLocked + Promise.new(รอคลิก) ...                          -- <-- สาย UI
--
-- สาย UI จะไม่ยิง FishLootConfirm จนกว่าจะ "คลิกปิดหน้าต่าง" ซึ่งเราไม่มีทางทำได้
-- เพราะฉะนั้นการมาแทน ShowCatch ทั้งก้อนเสี่ยงตัดสาย :andThen ที่ FishingController
-- ผูกไว้ -> StartCaughtCooldown(u27, true) -> FishLootConfirm:Fire() ออกไป
-- = server ไม่รู้ว่า session จบ -> cast ถัดไปโดน SessionActive
--   = "Finish what you are doing first"
--
-- วิธีที่ถูก: บังคับให้เกมเดิน "สายไม่มี UI" ของตัวเอง
--   -> ไม่ render ตั้งแต่ต้น (ไม่ใช่ไปซ่อนทีหลัง) และได้ FishLootConfirm กลับคืนมา
--   -> ตัวเวลาที่ใช้คือ FishingConfig.Loot.ConfirmReadyDelay ของเกม ไม่ใช่ที่เรานับเอง
-- ══════════════════════════════════════════════════
local Loot = { patched = false }

--- บังคับ LootController ให้ "ไม่มี loot UI" -> เกม auto-confirm ด้วยตัวเอง
--- ไม่แตะ ShowCatch เลย (คง flow/Promise ของเกมไว้ครบ)
local function suppressLootWindow()
    if not CONFIG.LootSuppress then return false end
    if not Client then return false end
    if Loot.patched then return true end
    local ok, lc = pcall(function() return Client.GetController("LootController") end)
    if not ok or not lc then
        return false
    end

    -- logger ต้องมี เพราะสาย "ไม่มี UI" ของเกมเรียก a1.logger:warn(...)
    if not lc.logger then
        local okL, Logger = pcall(function() return Stardust.Logger end)
        if okL and Logger and type(Logger.new) == "function" then
            pcall(function() lc.logger = Logger.new(lc.Name) end)
        end
    end
    if type(lc.logger) ~= "table" then
        lc.logger = setmetatable({}, { __index = function() return function() end end })
    end

    lc._ensure_refs = function(self)
        self._refs = nil   -- ไม่สร้าง UI เลย -> ShowCatch/_show_grant จะข้ามการ render
        return nil
    end

    Loot.patched = true
    return true
end

local function reelingLoop()
    local interval = 1 / CONFIG.ReelCps
    local nextAt = os.clock()
    -- ⚠ ต้องเริ่ม = os.clock() ไม่ใช่ +1.0
    --   เดิมหน่วงไว้ 1 วิ = ตอนเริ่มตกปลาใหม่จะกดตีปกติไปตั้ง 1 วินาทีก่อน
    --   ค่อยเริ่มคิดเรื่องสกิล = "กดตีก่อน แล้วค่อยใช้สกิล" ตามที่ผู้ใช้บอก
    --   สกิลต้องพร้อมใช้ตั้งแต่เฟรมแรกที่เข้า Reeling
    local nextSkillAt = os.clock()
    -- ⚠ เดิมลูปนี้ไม่มีทางออกนอกจาก S.state เปลี่ยนจาก packet ข้างนอก
    --   (FishCatchResult / FishReset) — ไม่มี timeout ไม่มี syncState ไม่มี GetState
    --   ถ้าสอง packet นั้นไม่มา -> วนตลอดจนกว่าจะแตก และ mainLoop ถูกบล็อกทั้งตัว
    --   การ sync ตอนตาย (mainLoop บรรทัด 5820) ก็ช่วยไม่ได้ เพราะอยู่เหนือสาขานี้
    --   แก้โดยอ่านสถานะจริงเอง และใช้ "เซิร์ฟเงียบนานผิดปกติ" เป็นตัวตัดสิน
    S.fighting = true
    local nextStateCheck = os.clock() + (CONFIG.Fight.StatePoll or 1)
    local warnedSilent = false
    while S.running and S.state == "Reeling" do
        local now = os.clock()

        -- ── ทางออกของรอบตก ──────────────────────────────────────
        if now >= nextStateCheck then
            nextStateCheck = now + (CONFIG.Fight.StatePoll or 1)
            local real = realFishingState()
            -- ① เกมบอกตรง ๆ ว่าไม่ได้อยู่ในรอบตกแล้ว -> ออกทันที ไม่ต้องรอ packet
            if real and not FIGHT_STATES[real] then
                S.fightExit = ("สถานะจริง=%s"):format(real)
                break
            end
            -- ② เกมยังบอกว่ากำลังตก แต่เซิร์ฟไม่ยิง HP มานานผิดปกติ
            --   = รอบตกจบไปแล้ว (หรือ packet หลุด) อย่าวนค้าง ให้ mainLoop ไปอ่านใหม่
            if S.hpAt > 0 and (nowReal() - S.hpAt) > (CONFIG.Fight.HPSilence or 12) then
                if not warnedSilent then
                    warnedSilent = true
                    logWarn(("[Fight] เซิร์ฟไม่ยิง HP มา %.0fs (สถานะจริง=%s) — ออกจากรอบตก"
                            .. " ให้ mainLoop ไปอ่านสถานะใหม่")
                        :format(nowReal() - S.hpAt, tostring(real)))
                end
                S.fightExit = ("เซิร์ฟเงียบ %.0fs"):format(nowReal() - S.hpAt)
                break
            end
        end
        if S.qteDir and now < S.qteExpireAt then
            local dir = S.qteDir
            local key = FishingConfig.Counter.DirectionToKey[dir]
            if key then
                local expire = S.qteExpireAt
                S.qteDir, S.qteExpireAt = nil, 0
                -- ⚠ ต้องรอ settle ของ server ก่อนตอบ ไม่ใช่ตอบทันทีที่ได้ prompt
                --   เดิม QteDelay = 0 -> ยิงภายใน 0-16ms ซึ่งอยู่ในช่วงที่ server ยังไม่ settle
                --   ผลคือถูก/ผิดขึ้นกับความยาวของเฟรมนั้น ๆ = สุ่ม
                local settle = qteSettleDelay()
                local gen = S.qteGen
                local answer = function()
                    if not S.running or S.state ~= "Reeling" then return end
                    if gen ~= S.qteGen then return end   -- เกมตัด prompt ทิ้งไปแล้ว (cancel/result/จังหวะใหม่)
                    if expire <= os.clock() then
                        -- หน้าต่างปิดไปแล้ว = กดทีหลังเกมตัด prompt ทิ้ง = เสียจังหวะฟรี
                        S.qteLate = S.qteLate + 1
                        if CONFIG.QteLog then
                            logWarn(("[QTE] %s -> %s · รอ %.0fms แล้วหน้าต่างปิดไปแล้ว — ไม่ยิง")
                                :format(tostring(dir), tostring(key), settle * 1000))
                        end
                        return
                    end
                    local ok = pcall(sendQTEAck, key)
                    if ok then S.qteSent = S.qteSent + 1 end
                end
                if settle > 0 then task.delay(settle, answer) else answer() end
            else
                -- direction ที่ DirectionToKey ไม่รู้จัก = ไม่มีปุ่มที่จะถูกต้อง
                --   (ตารางของเกมมีแค่ Left=A / Right=D / Up=W ดู FishingConfig.lua:64)
                S.qteNoKey = S.qteNoKey + 1
                S.qteDir, S.qteExpireAt = nil, 0
                if CONFIG.QteLog then
                    logWarn(("[QTE] direction %s ไม่มีใน DirectionToKey — จังหวะนี้กดอะไรก็ไม่ถูก")
                        :format(tostring(dir)))
                end
            end
        end

        -- ── สกิลก่อนเสมอ ────────────────────────────────────────
        -- ⚠ ต้องอยู่ "ก่อน" การกดตี และต้องไม่ถูก skillWindowUntil บล็อก
        --   FishSkillWindow คือเกมบอกว่า "หน้าต่างสกิลเปิด" ให้ใช้สกิลแทนการกดตี
        --   ดู TrySendReelPull ฝั่งเกม (FishingController:1439):
        --       if not (v1 < u309) and not (v1 < u310) then  -- เฉพาะตอนไม่อยู่ในหน้าต่างสกิล
        --   = ระหว่างหน้าต่างสกิล เกม "ห้าม" กดตี ไม่ใช่ห้ามใช้สกิล
        --   เดิมบล็อกทั้งสองอย่าง = หน้าต่างสกิลที่เกมเปิดให้ กลับถูกเราปิดทิ้ง
        --
        -- เงื่อนไขความพร้อมของแต่ละสกิลอ่านจากเกมตรง ๆ:
        --   ReplicatedSkillCooldown -> S.slotReadyAt (phase Casting/Cooldown/Ready)
        --   Player:GetAttribute("IsUsingSkill") -> กันซ้อนกับที่เกมกำลังคัสต์อยู่
        --     (RodController:976 ใช้เงื่อนไขเดียวกันเป๊ะก่อนยิง Moveset)
        if CONFIG.Skills and now >= nextSkillAt and now >= (S.lastSkillAt + CONFIG.SkillMinGap) then
            useNextSkill()
            nextSkillAt = os.clock() + CONFIG.SkillMinGap
        end

        -- ── กดตีปกติ ────────────────────────────────────────────
        -- หยุดชั่วคราวตอนอยู่ในหน้าต่างสกิล (เกมสั่งห้ามกดตีช่วงนั้น)
        --   และหยุดตอน boss stun (FishBossStun สั่ง u310 = เกมห้ามกดตีเช่นกัน)
        --   ⚠ ระหว่างที่หยุด ไม่ขยับ nextAt ข้างหน้า ไม่งั้นตอนกลับมาจะยิงรัวทันที
        if now >= S.stunnedUntil then
            if now >= nextAt and now >= S.skillWindowUntil then
                sendReelPull()
                nextAt = math.max(nextAt + interval, now)
                if CONFIG.ReelJitter > 0 then nextAt = nextAt + (math.random() * 2 - 1) * CONFIG.ReelJitter end
            end
        end
        RunService.Heartbeat:Wait()
    end
    -- ⚠ ปิดธงหัวใจการตกทุกครั้งที่ออกจากลูป (รวม break ข้างบน)
    --   ไม่งั้น watchdog จะเห็น "กำลังตก" ต่อไปแม้รอบตกจบไปแล้ว
    --   ถ้า error ไหลออกมาทำให้บรรทัดนี้ไม่รัน fightAlive() ยังตัดสินใจไม่ได้อยู่ดี
    --   เพราะมันเช็ค hpAt ด้วย = สูงสุดข้ามไปได้แค่ HPSilence x 2
    S.fighting = false
    S.qteDir, S.qteExpireAt = nil, 0
    S.qteGen = S.qteGen + 1     -- ฆ่า callback ที่หน่วงค้างอยู่
    S.skillWindowUntil = 0
    S.stunnedUntil = 0
end

-- ══════════════════════════════════════════════════
-- ANTI-SINK — กันตัวละครจมเองระหว่างตกปลา
-- ──────────────────────────────────────────────────
-- noclip เปิดตลอด -> ไม่มีพื้นให้ยืน -> gravity ดึงลงเรื่อย ๆ
-- พอตกถึงระดับน้ำ เกมจะสลับเป็น "กำลังว่ายน้ำ"
--   -> FishingController:HookSwimming() เห็น IsSwimmingChanged
--      -> ShouldCancelOnSwim(state) true ตอน state = Holding/Throwing/Waiting
--      -> ยิง FishCancel ทิ้ง session -> client/server หลุด sync
--      -> cast ถัดไปโดน StateBusy = "Finish what you are doing first"
-- แก้โดยฆ่า velocity ทุกเฟรม = ตัวละครลอยนิ่งที่จุดเดิม ไม่จม ไม่เข้าโซนว่าย
-- ⚠ แต่ฆ่า velocity "อย่างเดียว" = ไม่พอ (ผู้ใช้สั่งแก้ 2026-10-16)
--   gravity เติมความเร็วหลัง step ของ engine → ยังตกได้ ~3.3 studs/วิ
--   = "ไหลลงเรื่อยๆ" จนชนระดับน้ำ → HookSwimming → FishCancel
--   ต้องคู่กับการตรึงตัวตอน "มาถึงจุดแล้ว" = Anchored (ด้านบน)
-- ══════════════════════════════════════════════════
local function startAntiSink()
    if S.antiSinkConn then return end
    S.antiSinkConn = RunService.Heartbeat:Connect(function()
        local hrp = root()
        if not hrp then return end
        -- ⚠ มีแท่นยืนอยู่ = มีพื้นจริงแล้ว = ปล่อยให้ gravity ทำงานปกติ
        --   ถ้ายังฆ่า velocity อยู่ ตัวละครจะลอยเหนือแท่นตลอด = ยืนไม่ติดพื้นจริง
        --   และถ้าลอยต่ำถึงระดับน้ำ เกมจะสลับเป็น 'กำลังว่าย' -> ยกเลิก session ตกปลา
        local spot = S.standSpot
        -- ⚠ ยกแรงโน้มถ่วงอยู่แล้ว = gravity ถูกชดเชยหมดแล้ว ตัวละครเดินได้ปกติ
        --   ถ้ายังฆ่า velocity ทุกเฟรมตอนนี้ เราจะเดินไม่ขยับเลย = แย่กว่าการตรึงเดิม
        --   -> งดฆ่า velocity ตราบใดที่ S.grav ยังผูกกับตัวละครตัวนี้อยู่
        local lifted = S.grav and S.grav.Parent == hrp
        if not lifted and not (spot and spot.Parent and not S.noclipConn) then
            pcall(function() hrp.AssemblyLinearVelocity = Vector3.zero end)
            pcall(function() hrp.AssemblyAngularVelocity = Vector3.zero end)
        end

        -- ⚠ กู้แรงโน้มถ่วงทุกเฟรม (ไม่ใช่นับเวลา = อ่านสถานะจริงแล้วเทียบทุกเฟรม)
        --   holdNoGravity ทำ 2 อย่างในตัว:
        --     • ตัวละครเปลี่ยน (ตาย/เกิดใหม่) = ปล่อย ไม่งั้นตัวใหม่ถูกยกแรงทันทีที่เกิด
        --       (เกมเพิ่งวางตัวใหม่ลงจุดเกิด ต้องให้มันทำงานก่อน = เงื่อนไข 3)
        --     • เขียนแรงใหม่ทุกเฟรม = ตาม gravity/มวล ปัจจุบันเสมอ
        S.tools.holdNoGravity()
    end)
end

--- ก่อนกดเหวี่ยง: เช็คว่าเกมคิดว่าเรากำลังว่ายน้ำอยู่ไหม
--- ถ้าว่ายอยู่ -> ดันขึ้นเหนือผิวน้ำ (ExitSurfaceMargin = 4 จึงต้องสูงกว่านั้น) จนเกมปล่อยสถานะว่าย
--- คืน true ถ้าพร้อมเหวี่ยง / false ถ้ายังว่ายอยู่
local function ensureNotSwimming()
    local SwimmingCtl = Client.GetController("Swimming") or Client.GetController("SwimmingController")
    if not (SwimmingCtl and type(SwimmingCtl.IsSwimming) == "function") then return true end
    local hrp = root()
    if not hrp then return false end

    local n = 0
    -- ⚠ เพิ่งหนีจากน้ำมารอบนี้ไหม — ถ้าใช่ เราไม่ได้อยู่ที่จุดเดิมแล้ว
    --   เกมเพิ่งบอกว่า "ไม่ว่าย" ณ ตำแหน่งนี้ = ถือว่ามาถึงแล้ว (อ่านจากเกม ไม่ใช่เดา)
    local escaped = false
    while S.running and n < 100 do
        n = n + 1
        local swimming = false
        pcall(function() swimming = SwimmingCtl:IsSwimming() end)
        -- ⚠ เกมบอกว่าไม่ว่าย = กลับไปจอดนิ่งตามเดิม (คนที่เรียกคือลูปตกปลา
        --   = ต้องการให้ตัวละครอยู่กับที่ระหว่างรอปลา ไม่ใช่ตกไปเรื่อย ๆ)
        if not swimming then
            -- ⚠ หนีจากน้ำมา = จุดเดิมใช้ไม่ได้แล้ว ใช้ตำแหน่งจริงที่เกมยืนยันว่าหยุดว่าย
            --   pin() จะเทียบตำแหน่งจริงอีกครั้งก่อนตรึง (เงื่อนไข 1)
            if escaped then S.arriveAt = hrp.Position end
            S.tools.pin()
            return true
        end
        -- ⚠ ยังว่ายอยู่ = เงื่อนไข 2: ปล่อยตรึงก่อน ไม่งั้น engine จับตัวไว้
        --   ที่จุดเดิมตอนที่เรากำลังดันขึ้น = ดันไม่ขึ้น วนไม่จบ
        -- ดันซ้ำทุก 20 เฟรม ถ้าเกมดึงกลับลงน้ำ (เดิมดันครั้งเดียวแล้วรอเฉย ๆ)
        if n == 1 or n % 20 == 0 then
            hrp = root() or hrp
            S.tools.releasePin()
            S.arriveAt = nil
            escaped = true
            local sy = swimSurfaceY(hrp.Position.X, hrp.Position.Z) or getWaterY()
            local up = Vector3.new(hrp.Position.X, sy + 6, hrp.Position.Z)
            pcall(function() hrp.AssemblyLinearVelocity = Vector3.zero end)
            S.tools.tweenCF(hrp, CFrame.new(up), 0.2)
        end
        RunService.Heartbeat:Wait()
    end
    logWarn("[Prog] ยังออกจากโซนว่ายน้ำไม่ได้ — ข้ามการเหวี่ยงรอบนี้")
    return false
end

-- forward decl (นิยามจริงอยู่ฝั่ง orchestration ด้านล่าง)
local handleSatchelFull

-- ══════════════════════════════════════════════════════════════════
-- 4) AURA — สุ่ม / ใส่ / ทิ้ง
--
-- ⚠ กติกาของเกมที่ต้องยึด (อ่านจากดัมป์ ไม่เดา):
--   ช่องใส่ Aura = 1 ช่อง (PlayerData/Template.lua:18 AuraEquip = "None")
--     -> สลับไปมาได้ ไม่สะสมพร้อมกัน
--   สุ่ม  AuraGacha/Pull(NumberU8) -> { ok, reason, seed, pity_hit, pity_after,
--                                     gem_spent, credits_used, results }
--        (AuraGachaController.lua:38-51)
--   ใส่  Equipment/Equip("aura", key)   /  ถอด  Equipment/Equip("aura", "")
--   ทิ้้ง Equipment/Remove("aura", key)  ← เกมไม่มี "ขาย aura" มีแต่ลบทิ้ง
--        (EquipmentController.lua:2583)
--
-- ⚠ หน้าต่าง: ปุ่มลบใน UI ของเกมมี ConfirmController คุมก่อน (EquipmentController.lua:2366)
--   เรายิง packet ตรง ๆ ไม่ผ่าน ConfirmController = ไม่มีหน้าต่างโผล่
--
-- ⚠ ค่า stat ที่ใช้เทียบ อ่านจาก .rolled ที่เกมสุ่มจริงมา ไม่ใช่ min/max ใน Catalog
--   (equipmentItems.lua:8-30 — rolled = [{stat, op, value, luckMode?, group?, skillId?}])
-- ══════════════════════════════════════════════════════════════════
local AuraGachaCfg = req(ReplicatedStorage.Data.Config.AuraGachaConfig, "AuraGachaConfig")
local AuraCtl = (Client and Client.GetController) and Client.GetController("AuraGachaController") or nil

--- จำนวนครั้งที่สกิลฟัง (นับจาก hitPattern ด้วย Expand ของเกมเอง)
---   Utils/skillHitPattern.lua:45 — ช่อง Loop {startTime,interval,endTime}
---   = ยิงซ้ำทุก interval จนก่อน endTime และ dedupe ทั้งชุด
HitPatternUtil = req(ReplicatedStorage.Utils.skillHitPattern, "skillHitPattern")

function auraHitCount(pattern)
    if type(pattern) ~= "table" or #pattern == 0 then return 1 end
    if HitPatternUtil and HitPatternUtil.Expand then
        local ok, hits = pcall(function() return HitPatternUtil.Expand(pattern) end)
        if ok and type(hits) == "table" and #hits > 0 then return #hits end
    end
    return 1
end

--- สกิลที่ใส่อยู่ตอนนี้ -> [{id, name, group, coef, hits, w}]
---   ช่องสกิล = data.Rods[data.RodEquip].BookSlots (key เป็น "Slot1","Slot2",...)
---   และแต่ละสกิลมี group ของตัวเองใน Data/Catalog/Skill/Skill.lua
---
--- ⚠ w = ดาเมจต่อวินาทีจริง = damageCoef × จำนวนครั้งที่ฟัง ÷ max(cooldown, castTime)
---   ต้องใช้ตัวนี้แทนการนับ stat ดิบ เพราะ Aura ที่บังคับดาเมจสกิลเดียว
---   มีค่าน้อยกว่า Aura ที่บังคับทุกสกิล แม้ตัวเลขของมันจะใหญ่กว่ามาก
function readEquippedSkills(data)
    local out = {}
    local rods = data and data.Rods
    local rd = (type(rods) == "table" and rods[data.RodEquip]) or nil
    local slots = (type(rd) == "table" and rd.BookSlots) or nil
    if type(slots) ~= "table" then return out end
    for _, v in pairs(slots) do
        if type(v) == "string" and v ~= "" then
            local meta = nil
            if Catalog and Catalog.Skill and Catalog.Skill.GetById then
                pcall(function() meta = Catalog.Skill.GetById(v) end)
            end
            if type(meta) == "table" then
                local coef = tonumber(meta.damageCoef) or 1
                local cast = tonumber(meta.castTime) or 1
                local cool = tonumber(meta.cooldown) or cast
                local hits = auraHitCount(meta.hitPattern)
                out[#out + 1] = {
                    id = v, name = meta.name, group = meta.group or "",
                    coef = coef, hits = hits,
                    w = coef * hits / math.max(cast, cool, 0.01),
                }
            end
        end
    end
    return out
end

--- คิดค่าดาเมจของ Aura ตัวหนึ่ง เทียบกับสกิลที่เราใส่จริง
---   = value × (น้ำหนักของสกิลที่ stat นั้นไปถึง ÷ น้ำหนักรวมทั้งหมด)
---   = "ถ้าใส่ตัวนี้ ดาเมจรวมตอนตกปลาจะเพิ่มขึ้นประมาณกี่ %"
--- ⚠ ค่าใน rolled เป็นเศษสัดส่วน 0.01..0.5 ไม่ใช่เปอร์เซ็นต์เต็ม
function auraDmgScore(rolled, skills)
    local total = 0
    for _, s in ipairs(skills) do total = total + s.w end
    local raw, score = 0, 0
    for _, r in ipairs(rolled or {}) do
        if type(r) == "table" and type(r.stat) == "string" then
            local v = tonumber(r.value)
            local isDmg = (r.stat == "skillDamagePct"
                           or r.stat == "skillDamageByGroup"
                           or r.stat == "skillDamageById")
            if v and isDmg then
                raw = raw + v
                if total > 0 then
                    if r.stat == "skillDamagePct" then
                        score = score + v            -- ทุกสกิล -> ได้เต็ม v
                    else
                        local acc = 0
                        for _, s in ipairs(skills) do
                            if (r.stat == "skillDamageByGroup" and s.group == r.group)
                               or (r.stat == "skillDamageById" and s.id == r.skillId) then
                                acc = acc + s.w
                            end
                        end
                        score = score + v * (acc / total)
                    end
                end
            end
        end
    end
    -- ยังไม่ได้ใส่สกิลเลย = วัดเป็น % ไม่ได้ คืนค่าดิบไว้เทียบกัน (อย่างน้อยไม่ทิ้งทั้งหมด)
    if total <= 0 then return raw end
    return score
end

AURA_RANK = {
    Common = 1, Uncommon = 2, Rare = 3,
    Epic = 4, Legendary = 5, Mythical = 6, Divine = 7,
}

--- ราคาสุ่ม N ครั้ง — สูตรเดียวกับ AuraGachaUtil.CostFor ของเกม อ่านค่าจากคอนฟิกสด ๆ
--- คืน nil ถ้าอ่านคอนฟิกไม่ได้ = ไม่เดาราคา ไม่ยิงมั่ว
function auraCost(n)
    if not AuraGachaCfg then return nil end
    local ok, v = pcall(function()
        local disc = (AuraGachaCfg.Pull and AuraGachaCfg.Pull.BulkDiscount or {})[n] or 1
        local gem = (AuraGachaCfg.Pull and AuraGachaCfg.Pull.CostGem) or nil
        if type(gem) ~= "number" then error("no CostGem") end
        return math.ceil(gem * n * disc)
    end)
    if ok and type(v) == "number" then return v end
    return nil
end

--- อ่าน Aura ทั้งคลังจากข้อมูลผู้เล่นจริง -> [{key,id,name,rarity,locked,luck,sell,dmg}]
---   luck = ผลรวม stat "luck" · sell = ผลรวม "sellValuePct" · dmg = ผลรวม skillDamage*
--- ⚠ อ่านค่าที่ roll จริง เช่น aura luck 1..10 อาจได้ 3 ก็ได้ 3 ไม่ใช่ 10
function readAuras(data)
    local out = {}
    local inv = invOf(data)
    inv = inv and inv.Auras
    if type(inv) ~= "table" then return out end
    local skills = readEquippedSkills(data)
    for key, a in pairs(inv) do
        if type(a) == "table" and type(a.catalogId) == "string" then
            local meta = nil
            if Catalog and Catalog.Aura and Catalog.Aura.GetById then
                pcall(function() meta = Catalog.Aura.GetById(a.catalogId) end)
            end
            local luck, sell = 0, 0
            for _, r in ipairs(a.rolled or {}) do
                if type(r) == "table" and type(r.stat) == "string" then
                    local v = tonumber(r.value)
                    if v then
                        if r.stat == "luck" then
                            luck = luck + v
                        elseif r.stat == "sellValuePct" then
                            sell = sell + v
                        end
                    end
                end
            end
            -- ⚠ ดาเมจมี 3 แบบ คนละขอบเขตกัน:
            --   skillDamagePct      = ทุกสกิล            (7 ออร่า)
            --   skillDamageByGroup  = ทั้งกลุ่มสกิล        (1 ออร่า)
            --   skillDamageById     = สกิลเดียว           (42 ออร่า)
            --   รวมเป็นก้อนเดียวแล้วเทียบกันไม่ได้ (Aura +50% ให้สกิลที่ไม่ได้ใส่
            --   ต้องชนะ Aura +20% ให้ทุกสกิล = ตรงข้ามกับความจริง)
            --   -> คิดเป็น % ของดาเมจรวมที่ตกจริงแทน
            local dmg = auraDmgScore(a.rolled, skills)
            table.insert(out, {
                key = key,
                id = a.catalogId,
                name = (meta and meta.name) or a.catalogId,
                rarity = (meta and meta.rarity) or "?",
                locked = (a.locked == true),
                luck = luck, sell = sell, dmg = dmg,
            })
        end
    end
    table.sort(out, function(p, q) return tostring(p.key) < tostring(q.key) end)
    return out
end

--- เลือก Aura ที่ "ดีที่สุด" ตามโหมด (ข้ามตัวที่ locked เสมอ)
---   mode = "fishing" -> +Luck มากสุด · ถ้าไม่มีตัวไหนให้ luck เลย -> +ดาเมจสกิลมากสุด
---   mode = "sell"    -> +ราคาขายมากสุด · ถ้าไม่มีตัวไหนให้ราคาขายเลย -> nil (ไม่ต้องสลับ)
--- ⚠ เทียบเป็นตัวเลขดิบตามที่ผู้ใช้สั่ง: "ถ้ามี +coin 15% กับ 30% ก็เอา 30%"
---   (ข้ามตัวที่ค่าเป็น 0 ด้วย เพราะ 0 ไม่ใช่ "ดีกว่า" ของตัวอื่น)
function bestAura(list, mode)
    local field = (mode == "sell") and "sell" or "luck"
    local best, bestV = nil, 0
    for _, a in ipairs(list) do
        if (not a.locked) and a[field] > bestV then
            best, bestV = a, a[field]
        end
    end
    if best then return best end
    if mode == "sell" then return nil end
    for _, a in ipairs(list) do
        if (not a.locked) and a.dmg > bestV then
            best, bestV = a, a.dmg
        end
    end
    return best
end

--- ใส่ Aura (key = "" = ถอด) — ยิง packet ตรง ไม่เปิดหน้าต่าง Equipment
function equipAura(key)
    if not (EquipCtl and EquipCtl.EquipmentEquip) then return false end
    local ok, r = pcall(function() return EquipCtl.EquipmentEquip:Fire("aura", key or "") end)
    return (ok and r == true)
end

--- ใส่ Aura ที่ดีที่สุดตามโหมด · ถ้ายังใส่ตัวที่ดีอยู่แล้ว = ไม่ยิงซ้ำ (กันรัว)
--- คืน true ถ้าเพิ่งสลับ
local function equipBestAura(data, mode)
    if not CONFIG.Aura.Enabled then return false end
    if not (data and data.AuraEquip ~= nil) then return false end
    local want = bestAura(readAuras(data), mode)
    if not want then return false end
    if data.AuraEquip == want.key then return false end
    if not equipAura(want.key) then return false end
    return true
end

--- ทิ้ง Aura เพื่อเวร ๆ ตอนคลังเต็ม · needFree = ต้องการช่องว่างกี่ช่อง (เช่น 10 ก่อนสุ่ม)
---
--- ⚠ กติกาผู้ใช้ (แก้จากเดิม): "ห้ามขาย Aura ที่เพิ่มราคาขาย" ไม่ได้หมายความว่า
---   เก็บตัว +coin ทุกตัวไว้ แต่หมายถึง **เก็บแค่ตัวที่ดีที่สุดไว้ตัวเดียว**
---   เช่น มี +coin 15% (Common) ตัวเดียวในกระเป๋า แล้วกระเป๋าเต็มพอดี
---   -> ต้องทิ้งตัวอื่นเพื่อสุ่มใหม่ แต่ "ห้ามทิ้งตัว +coin ตัวนั้น"
---   ถ้ามีตัว +coin หลายตัว เก็บไว้แค่ตัวที่ sellValuePct มากที่สุด ที่เหลือทิ้งตามลำดับ
---
--- ⚠ ห้ามทิ้งตัวที่กำลังใส่อยู่ = ถอดให้เล่นกลางคันจะไปหัวเป็น None
--- ⚠ เกมไม่มี packet "ขาย aura" มีแต่ Equipment/Remove = ลบทิ้งถาวร
function pruneAuras(data, needFree)
    local list = readAuras(data)
    local over = #list - (CONFIG.Aura.KeepMax or 0) + math.max(0, tonumber(needFree) or 0)
    if over <= 0 then return false end
    local equipped = data and data.AuraEquip

    -- ตัวที่ "เก็บไว้เสมอ" = ตัว +coin ที่มากที่สุดในกระเป๋า (ถ้าไม่มีเลย = ไม่มีตัวที่ต้องเก็บ)
    local bestSell, bestSellV = nil, 0
    for _, a in ipairs(list) do
        if a.sell > bestSellV then bestSell, bestSellV = a, a.sell end
    end

    local cand = {}
    for _, a in ipairs(list) do
        if (not a.locked) and a.key ~= equipped and a ~= bestSell then
            table.insert(cand, a)
        end
    end
    if #cand == 0 then return false end
    -- แย่สุดขึ้นไป 2 ชั้น:
    --   ชั้นที่ 1 = ไม่มี sellValuePct เลย (ไม่มีอะไรให้เกม) เรียง luck+ดาเมจ ต่ำ -> สูง
    --   ชั้นที่ 2 = ยังเป็นตัว +coin อยู่ (แต่ไม่ใช่ตัวที่ดีที่สุด) เรียง sellValuePct ต่ำ -> สูง
    table.sort(cand, function(p, q)
        local sp = (p.sell > 0) and 2 or 1
        local sq = (q.sell > 0) and 2 or 1
        if sp ~= sq then return sp < sq end
        if sp == 2 then
            if p.sell ~= q.sell then return p.sell < q.sell end
        else
            local lp, lq = p.luck + p.dmg, q.luck + q.dmg
            if lp ~= lq then return lp < lq end
        end
        return (AURA_RANK[p.rarity] or 0) < (AURA_RANK[q.rarity] or 0)
    end)
    local did = 0
    for i = 1, math.min(over, #cand) do
        if EquipCtl and EquipCtl.EquipmentRemove then
            local ok, r = pcall(function() return EquipCtl.EquipmentRemove:Fire("aura", cand[i].key) end)
            if ok and r == true then
                did = did + 1
                S.auraPruned = (S.auraPruned or 0) + 1
            end
        end
    end
    return did > 0
end

--- สุ่ม Aura N ครั้ง · คืน true ถ้าสำเร็จ
--- ⚠ Fire() คืน nil = timeout ไม่ใช่ false (Packet.lua ตั้ง ResponseTimeout ไว้ 10s
---   แต่ ResponseTimeoutValue ไม่เคยถูกตั้ง -> ResumeResponse("timeout", false, ...))
---   จึงต้องเช็ค type(res) == "table" ไม่ใช่แค่ res.ok
function pullAuras(n)
    if not (AuraCtl and AuraCtl.Pull) then
        logWarn("[Aura] ไม่มี AuraGachaController — สุ่มไม่ได้")
        return false
    end
    local ok, res = pcall(function() return AuraCtl.Pull:Fire(n) end)
    if not ok or type(res) ~= "table" or res.ok ~= true then
        logWarn(("[Aura] สุ่มไม่สำเร็จ (%s)"):format(
            tostring((type(res) == "table" and res.reason) or "ไม่ตอบ/timeout")))
        return false
    end
    S.auraPulled = (S.auraPulled or 0) + 1
    return true
end

--- มี Aura ที่ +Luck ถึงเป้าแล้วหรือยัง (กติกา gems ของเกาะ Lotus)
function luckAuraReady(data)
    local t = CONFIG.Aura.LuckTarget or 4
    for _, a in ipairs(readAuras(data or {})) do
        if (a.luck or 0) >= t then return true end
    end
    return false
end

--- รอบตรวจ Aura: เลือกของดีสุด -> สุ่มถ้า gem พอ -> ทิ้งของแย่เมื่อคลังล้น
--- mode = "fishing" (ตอนตกปลา) / "sell" (ตอนจะขาย)
--- คืน true ถ้ามีอะไรเปลี่ยน
local function auraTick(data, mode, canPull)
    if not CONFIG.Aura.Enabled then return false end
    if not data then return false end
    local did = equipBestAura(data, mode)
    local n = CONFIG.Aura.PullCount or 1

    -- ⚠ SaveGemAfterDreadFishRod: ได้เบ็ด Dread Fish Rod แล้ว = หยุดสุ่ม เก็บ gem ไว้
    --   ไม่แตะการใส่/ทิ้ง Aura ที่มีอยู่ — เปลี่ยนแค่ไม่สุ่มเพิ่ม
    local hold = gemHoldActive(data)
    if hold and not S.gemHoldSaid then
        S.gemHoldSaid = true
        logWarn("[Aura] ได้เบ็ด Dread Fish Rod แล้ว — เลิกสุ่ม Aura เก็บ gem ไว้ตั้งแต่นี้")
    end

    -- ── กติกา gems ของเกาะ Lotus (ผู้ใช้สั่ง 2026-10-20) ────────────────
    --   สุ่มจนได้ Aura +Luck ≥ LuckTarget แล้วกัน gems ไว้ 200 เพื่อปลดเกาะ 7
    --   "ถ้ามี 219 ก็สุ่ม 1 รอบให้เหลือ 209" = เงื่อนไขคือ gem - reserve >= ราคาสุ่ม
    --   ⚠ ไม่แตะ CONFIG.Aura.ReserveGem (ภายนอกตั้งผ่าน FM_set ได้ตามเดิม)
    --     แค่ยกพื้น reserve ขึ้นชั่วคราวในรอบนี้
    local reserve = CONFIG.Aura.ReserveGem or 0
    if luckAuraReady(data) then
        reserve = math.max(reserve, CONFIG.Aura.LotusGemReserve or 200)
        if not S.lotusGemSaid then
            S.lotusGemSaid = true
            logWarn(("[Aura] ได้ Aura +Luck ≥ %d แล้ว — กัน gems ไว้ %d เพื่อปลดล็อก Lotus")
                :format(CONFIG.Aura.LuckTarget or 4, CONFIG.Aura.LotusGemReserve or 200))
        end
    end

    -- ── กัน gems ให้สาย Forge (Godslayer Rod V2) ────────────────────────
    --   ผู้ใช้สั่ง "เงินฟาร์มหลังสุดเสมอ" ⇒ gems ต้องไม่ถูก Aura กินก่อน forge
    --   กันเท่ากับ gemCost ที่ยังเหลือทั้งห่วงโซ่ (900 ถ้ายังไม่ได้ forge อะไรเลย)
    if CONFIG.Forge.Enabled and islandUnlocked(data, CONFIG.Forge.AfterIsland) then
        local need = forgeGemNeed(data)
        if need > 0 then
            reserve = math.max(reserve, need)
            if not S.forgeGemSaid then
                S.forgeGemSaid = true
                logWarn(("[Aura] กัน gems ไว้ %d สำหรับสาย Forge (V2 ใช้รวม 900)"):format(need))
            end
        end
    end

    local cost = (canPull and not hold) and auraCost(n) or nil

    -- ⚠ ต้องทิ้ง "ก่อน" สุ่ม: คลังเต็ม (100/100) แล้วสุ่มไม่ได้ = ต้องเวรก่อน
    if cost and numOr(data.Gem, 0) - reserve >= cost then
        if pruneAuras(data, n) then
            did = true
            data = fetchData()   -- อ่านของใหม่หลังทิ้ง เพราะ inventory เปลี่ยนไปแล้ว
        end
        if pullAuras(n) then did = true end
    end
    if pruneAuras(data) then did = true end
    return did
end

-- ══════════════════════════════════════════════════════════════════
-- 5) BOSS — บอสเกิด -> ไปตีทันที แล้วกลับมาทำงานเดิม
--
-- ⚠ อ่านสถานะจากเกมโดยตรง ไม่เดาเวลา ไม่นับวินาทีเอง:
--   BossSpawnerFX.IsActive อ่าน attribute "BossSpawnerFXActive" == true
--   (BossSpawnerFX.lua:45,99) อยู่บน part ของเขต (ลูกชื่อ BossSpawnerFX)
--   เขตบอส = part ที่ CollectionService tag "BossRegion"
--   (RegionConfig.BossTag) และมี attribute "bossRegionId" (RegionConfig.BossAttribute)
--   มี active แค่ 1 เขตทั้งเซิร์ฟ (FishingConfig.Boss.ActiveRegionsMax = 1)
--
-- ⚠ BossSpawnClaimed: server ส่ง true เมื่อมีคนไปเกี่ยวบอสก่อนเรา
--   เกาะนั้นแค่สั่งซ่อนภาพ (SetVisualsEnabled) แต่ attribute ยัง true = เรายังเห็นบอสอยู่
--   จึงต้องอ่าน _claimed ของ controller ถึงจะรู้ว่าคนอื่นได้ไปแล้ว
-- ══════════════════════════════════════════════════════════════════
local BossSpawnerFX   = req(ReplicatedStorage.Shared.Lib.BossSpawnerFX, "BossSpawnerFX")
local RegionConfig    = req(ReplicatedStorage.Data.Config.RegionConfig, "RegionConfig")
local BossRegionCtl   = (Client and Client.GetController) and Client.GetController("BossRegionController") or nil

--- เขตบอสที่กำลังมีบอสอยู่ตอนนี้ -> part (หรือ nil)
--- คืน part ที่เกิดจริง พร้อมเก็บไว้ใน S.bossRegion เพื่อให้รอบถัดไปไม่ต้องค้นใหม่
function bossActivePart()
    if not RegionConfig then return nil end
    local tag, attr = RegionConfig.BossTag, RegionConfig.BossAttribute
    local activeAttr = (BossSpawnerFX and BossSpawnerFX.ActiveAttribute) or "BossSpawnerFXActive"
    local cached = S.bossRegion
    local function isActive(part)
        local fx = BossSpawnerFX and BossSpawnerFX.GetForRegion(part) or nil
        if fx and fx:GetAttribute(activeAttr) == true then return true end
        return part:GetAttribute(activeAttr) == true
    end
    -- 1) เขตที่กำลังยืนอยู่ — ไม่ต้องสแกนทั้งแมพ
    if cached and cached.Parent and cached:IsA("BasePart") then
        if isActive(cached) then return cached end
        S.bossRegion = nil
    end
    -- 2) สแกนใหม่
    for _, part in ipairs(CollectionService:GetTagged(tag)) do
        if part:IsA("BasePart") and isActive(part) then
            S.bossRegion = part
            return part
        end
    end
    return nil
end

--- เขตนี้อยู่เกาะไหน — อ่าน attribute ตรง ๆ แล้วเทียบแคตตาล็อก
--- ⚠ ทางสำรอง: เดินขึ้น parent จนเจอโฟลเดอร์ใต้ Workspace.World.Islands
---   ใช้ตอนอ่าน attribute ไม่ได้ (เกมอัปเดต/แคตตาล็อกหาย) เพราะเดาเกาะจากพิกัด
---   ไม่ได้ แต่ "รู้ว่าอยู่เกาะไหน" ได้เสมอถ้า part ยัง stream อยู่
function bossRegionIsland(part)
    local attr = RegionConfig and RegionConfig.BossAttribute or "bossRegionId"
    local ok, meta = pcall(function()
        if not (Catalog and Catalog.BossRegion and Catalog.BossRegion.GetById) then return nil end
        return Catalog.BossRegion.GetById(part:GetAttribute(attr))
    end)
    if ok and type(meta) == "table" and meta.fallbackIslandId then
        return meta.fallbackIslandId
    end
    local islands = Workspace:FindFirstChild("World")
    islands = islands and islands:FindFirstChild("Islands")
    if not islands then return nil end
    local p = part
    while p and p ~= islands do
        if p.Parent == islands then return p.Name end
        p = p.Parent
    end
    return nil
end

--- มีคนไปเกี่ยวบอสก่อนเราไหม (server บอกเองผ่าน BossSpawnClaimed)
function bossClaimed()
    return (BossRegionCtl and BossRegionCtl._claimed == true) or false
end

--- เราเพิ่งพลาดบอส -> ถูกล็อกออก 3 นาที (FishingConfig.Boss.MissLockoutSec = 180)
--- ⚠ BossMissUntil เป็น integer บน profile เทียบกับนาฬิกาเซิร์ฟของเกมเอง
---   (DailyRewardUtil.get_now = math.floor(now(0))) ไม่ใช่ os.time ของเครื่อง
function bossLockedOut(data)
    local untilTs = tonumber(data and data.BossMissUntil)
    if not untilTs or untilTs <= 0 then return false end
    local ok, nowSec = pcall(function() return DailyRewardUtil.get_now() end)
    if not (ok and type(nowSec) == "number") then return false end
    return untilTs > nowSec
end

--- ถึงเกาะที่ยอมเริ่มล่าบอสแล้วหรือยัง (ผู้ใช้สั่ง 2026-10-24)
---   ต้องปลด CONFIG.Boss.MinIsland ก่อน (ปัจจุบัน = island_desert) ถึงจะไปตีบอส
---   เหตุผล: ปลด Desert ได้ = มีสกิลอย่างต่ำ Rare แล้ว = ตกบอสได้จริง
---   ก่อนหน้านั้นถ้าบอสเกิดแล้วทิ้งฟาร์มไปตี = เสียเวลาเปล่า เพราะดาเมจไม่พอ
---   nil = ปิดข้อจำกัด (ล่าบอสได้ทุกเกาะที่ปลดแล้ว) — เผื่อผู้ใช้ปิดเองในอนาคต
---   ⚠ แยกจาก "บอสอยู่เกาะที่ปลดหรือยัง" (islandUnlocked) — เป็นด่านคนละชั้น
function bossIslandReady(data)
    local min = CONFIG.Boss and CONFIG.Boss.MinIsland
    if type(min) ~= "string" or min == "" then return true end
    return islandUnlocked(data, min)
end

--- จุดอยู่ในกล่องเขตบอสไหม (กล่องเดียวกับที่ BossRegionController ใช้ตรวจ)
---   ⚠ ต้องเป็นกล่องเดียวกันเป๊ะ ไม่งั้น "ตกบอส" กับ "ตกปลาธรรมดา" จะคลาดกัน
function bossInsideRegion(part, p)
    if not (part and part:IsA("BasePart") and p) then return false end
    local okC, s = pcall(function() return part.CFrame:PointToObjectSpace(p) end)
    if not okC or not s then return false end
    local h = part.Size * 0.5
    return math.abs(s.X) <= h.X and math.abs(s.Y) <= h.Y and math.abs(s.Z) <= h.Z
end

--- พื้นดินที่ "ยืนได้จริง" ที่ (x,z) ใช่ไหม
---   เงื่อนไข 3 ข้อ อ่านจากฉากตอนนั้น ไม่เดา:
---     1) มีพื้นให้ยืน          (ray ลงเจอ และสูงกว่าระดับน้ำ)
---     2) ไม่ใช่ใต้น้ำ          (พื้นสูงกว่าระดับน้ำอย่างน้อย 2 studs)
---     3) เหนือหัวโล่ง          (ray ขึ้นไม่เจออะไรใน HeadRoom studs)
---   คืน Vector3 จุดยืน (สูงกว่าผิวพื้น LandStandUp) หรือ nil
local function dryLandAt(x, z, waterY)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.IgnoreWater = true
    params.RespectCanCollide = false
    -- ⚠ ตัวละครยังไม่โหลด = อย่าใส่ nil (error) และอย่าใส่ Workspace (ตัดทุกอย่าง)
    local chr = LocalPlayer.Character
    if chr then params.FilterDescendantsInstances = { chr } end

    local ok, down = pcall(function()
        return Workspace:Raycast(Vector3.new(x, 500, z), Vector3.new(0, -1000, 0), params)
    end)
    if not ok or not down then return nil end
    local gy = down.Position.Y
    -- ⚠ ต้องสูงกว่าระดับน้ำจริง ไม่ใช่ระดับน้ำเดา (getWaterY อ่านจาก Catalog)
    if gy <= waterY + 2 then return nil end

    local okU, up = pcall(function()
        return Workspace:Raycast(Vector3.new(x, gy + 0.5, z),
            Vector3.new(0, (CONFIG.Boss.LandHeadRoom or 8), 0), params)
    end)
    if not okU or up then return nil end      -- มีของบดบังหัว = ไม่นับเป็นที่ยืน

    return Vector3.new(x, gy + (CONFIG.Boss.LandStandUp or 3), z)
end

--- หาพื้นดินที่ใกล้เขตบอสที่สุด แล้ว "ตกยังเข้าเขตบอสได้จริง"
---   คืน Vector3 หรือ nil
---   ⚠ เงื่อนไขสำคัญ: น้ำที่จะเหวี่ยงไปต้องอยู่ในกล่องเขตด้วย
---     ไม่งั้นเดินขึ้นฝั่งแล้วเหวี่ยงออกนอกเขต = กลายเป็นตกปลาธรรมดา
function bossLandSpot(part)
    -- ⚠ อันนี้ยิง raycast ได้ถึง ~1,000 ครั้งในรอบเดียว (วง 9 รัศมี x ~55 จุด x 2)
    --   และถูกเรียกจาก mainLoop โดยไม่ผ่านธง busy เลย
    --   = beat นิ่งนานหลายวินาทีโดยที่ watchdog เข้าใจว่าหลักเดินค้าง
    S.moving = true
    local okP, pos = pcall(function() return part.Position end)
    if not (okP and pos) then S.moving = false return nil end
    local waterY = getWaterY()
    local maxCast = CONFIG.Boss.MaxCastDist or 70
    local searchR = CONFIG.Boss.LandSearchR or 70
    local step = 8

    for r = step, searchR, step do
        local samples = math.max(8, math.floor((2 * math.pi * r) / step))
        for i = 0, samples - 1 do
            local ang = (i / samples) * 2 * math.pi
            local x = pos.X + math.cos(ang) * r
            local z = pos.Z + math.sin(ang) * r
            local stand = dryLandAt(x, z, waterY)
            if stand then
                -- น้ำที่จะตกต้องอยู่ในระยะที่ตกได้ และอยู่ในกล่องเขต
                local w = findNearestOpenWater(stand)
                if w then
                    local d = Vector3.new(w.X - stand.X, 0, w.Z - stand.Z).Magnitude
                    if d <= maxCast and bossInsideRegion(part, w) then
                        S.moving = false
                        return stand
                    end
                end
            end
        end
    end
    S.moving = false
    return nil
end

--- ไปยืนเล่นบอส: ข้ามเกาะถ้าจำเป็น -> tween ไปจุดบอส + CONFIG.Boss.HeightUp
--- คืน false ถ้าไปไม่ถึง (ผู้เรียกจะปลด S.bossHolding เอง)
function goToBoss()
    local part = bossActivePart()
    if not part then return false end
    local isl = bossRegionIsland(part)
    if isl and currentIslandId() ~= isl then
        S.traveling = true
        -- ⚠ ไปตกบอสอย่างเดียว = ไม่ต้องตั้งจุดเกิด (เดินไป NPC เสียเวลาเปล่า)
        --   จุดเกิดจะยังอยู่ที่เกาะฟาร์ม พอกลับมาจึงไม่ต้องเซฟซ้ำอีก
        local ok = travelToIsland(isl, false)
        S.traveling = false
        if not ok then
            logWarn(("[Boss] ข้ามไป %s ไม่สำเร็จ — ยกเลิกรอบนี้"):format(tostring(isl)))
            return false
        end
    end
    -- ⚠ part อาจถูกลบไปแล้วระหว่างที่เราข้ามเกาะ = อ่าน Position ไม่ได้
    local okPos, pos = pcall(function() return part.Position end)
    if not (okPos and pos) then return false end
    local hrp = root()

    -- ⚠ สำรอง: ตกจากกลางน้ำไม่ผ่าน -> ย้ายไปยืนพื้นดินรอบเขตแทน
    --   (ผู้ใชาสั่ง 2026-10-15) ยังตกเข้าเขตบอสได้ เพราะเกมดูที่จุดที่เหยือกตก
    --   ไม่ได้ดูที่ตัวเรายืน (BossRegionController.GetBossRegionPartAtPoint)
    local target, onLand = nil, false
    if S.bossBackup then
        target = bossLandSpot(part)
        -- ⚠ ต้องกัน "หาทุกรอบ" — bossLandSpot ยิง raycast หลายร้อยครั้ง
        --   ถ้าไม่มีพื้นดินที่เข้าเงื่อนไขจะได้ทำทุกวินาทีไปเรื่อย ๆ
        S.bossBackedUp = true
        if target then
            onLand = true
        else
            logWarn("[Boss] หาพื้นดินที่ตกยังเข้าเขตได้ไม่พบ — กลับไปยืนกลางน้ำเหมือนเดิม")
            S.bossBackup = false
        end
    end
    if not target then
        target = pos + Vector3.new(0, CONFIG.Boss.HeightUp, 0)
    end

    if hrp and (hrp.Position - target).Magnitude > CONFIG.Boss.NearDist then
        S.moving = true
        -- ⚠ พื้นดินกับกลางน้ำต้องใช้วิธีเดินต่างกัน
        --   tweenDiveTo ลงไปใต้ผิวน้ำ (ใช้เมื่อยืนกลางน้ำ) · tweenTo เดินบนพื้น
        -- ⚠ ทั้งสองทางต้องได้แท่นยืนเหมือนกัน (tweenDiveTo เรียก standAt(..., false)
        --   ซึ่งลบแท่น แล้วบรรทัดถัดมาสร้างใหม่เองตรงนี้)
        local reached
        if onLand then
            reached = tweenTo(target, "boss-land")
        else
            reached = tweenDiveTo(target, "boss")
        end
        if reached then standAt(target, true) end
        S.moving = false
    end
    return true
end

--- เช็คบอสทุกรอบของ mainLoop
---   ไม่มีบอส           -> false  (ปล่อบให้ mainLoop ทำงานปกติ)
---   เพิ่งเจอ/กำลังตี -> true   (mainLoop จะบล็อก runStep / goToFarmSpot ไว้)
function bossTick()
    if not CONFIG.Boss.Enabled then return false end
    -- ⚠ ระหว่าง raid ห้ามออกไปตีบอส (จะหลุดวง raid ที่กิน quota ไปแล้ว)
    if S.raidActive then return false end
    if S.traveling or S.moving then return false end

    local part = bossActivePart()
    if S.bossHolding then
        -- ยังต้องอยู่ที่นั้น -> mainLoop เหวี่ยงต่อเองจากจุดที่ยืนอยู่ ไม่ต้องทำอะไร
        if part and not bossClaimed() then
            -- ⚠ ตกจากกลางน้ำโดนปฏิเสธครบ FailToBackup ครั้ง -> ย้ายไปพื้นดิน
            --   ย้ายครั้งเดียวต่อหนึ่งรอบบอส (bossBackedUp กันย้ายทุก mainLoop)
            if S.bossBackup and not S.bossBackedUp then
                logWarn(("[Boss] ตกจากกลางน้ำไม่ผ่าน %d ครั้ง — ย้ายไปยืนพื้นดินใกล้เขตแล้วตกจากตรงนั้น")
                    :format(CONFIG.Boss.FailToBackup or 3))
                goToBoss()
                return true
            end
            -- ⚠ กัน "ธงค้าง = ยืนผิดที่" (แก้ 2026-10-16)
            --   เดิมสาขานี้แค่ return true = "เหวี่ยงต่อจากที่ยืนอยู่" โดยไม่เคยดูว่ายืนถูกที่
            --   ถ้าตัวละครถูกลากออกจากเขตบอส (บูต 7900 / ขายปลาเต็ม 6072 / ไปตกที่เกาะอื่น)
            --   มันจะยืนเหวี่ยงที่จุดเดิมจนบอสหมดอายุ แล้วค่อยปลดธงตอนเจอสิ่งที่ใหม่
            --   -> อ่านตำแหน่งสด ๆ เทียบกับเขตบอส ถ้าหลุดเกิน DriftedDist ให้ว่ายกลับ
            --   (DriftRecoverSec เป็นแค่ตัวกันยิงซ้ำ ไม่ใช่เกณฑ์ว่ายังตีบอสอยู่ไหม)
            local okBp, bpos = pcall(function() return part.Position end)
            local hB = root()
            if okBp and bpos and hB then
                local far = (hB.Position - bpos).Magnitude
                if far > (CONFIG.Boss.DriftedDist or 120)
                   and nowReal() - S.bossDriftAt >= (CONFIG.Boss.DriftRecoverSec or 15) then
                    S.bossDriftAt = nowReal()
                    logWarn(("[Boss] หลุดจากเขตบอส (ห่าง %.0f studs) — ว่ายกลับไปตีต่อ")
                        :format(far))
                    goToBoss()
                end
            end
            return true
        end
        S.bossHolding = false
        S.bossRegion = nil
        S.bossFail, S.bossBackup, S.bossBackedUp = 0, false, false
        S.bossDriftAt = 0
        task.wait(0.3)
        -- บอสจบ = มักมีหน้ารางวัล/loot เปิดค้าง ซึ่งบล็อกปุ่มเหวี่ยงเงียบ ๆ (log จริง: เหวี่ยงหยุดที่ 291 นาน 3 ชม.)
        local nBlk = S.tools.clearBlockers()
        if nBlk > 0 then
            logWarn(("[Boss] จบรอบ — เคลียร์ตัวบล็อกปุ่มเหวี่ยงที่ค้างอยู่ %d อย่าง"):format(nBlk))
        end
        goToFarmSpot()
        return true
    end

    if not part then return false end
    if bossClaimed() then return false end

    -- ⚠ เขตบอส 2 เขตต่อเกาะ × 6 เกาะ = 12 เขต (Catalog/BossRegion.lua) ไม่ได้กรอง
    --   ด้วยเกาะที่ปลดแล้วในฝั่งเกม -> บอสมีโอกาสเกิดบนเกาะที่เรายังเข้าไม่ได้
    --   ถ้าไปไม่ได้ = เดินทางเสียเวลาเปล่า + บอสหายไปเปล่า ๆ -> ข้าม
    local isl = bossRegionIsland(part)
    local data = fetchData()
    if not isl then
        if S.bossSkip ~= "no-island" then
            S.bossSkip = "no-island"
            logWarn("[Boss] อ่านเกาะของเขตบอสไม่ได้ — ข้ามรอบนี้ (ไม่เดา)")
        end
        return false
    end
    if not islandUnlocked(data, isl) then
        if S.bossSkip ~= isl then
            S.bossSkip = isl
            logWarn(("[Boss] บอสเกิดที่ %s ซึ่งยังไม่ปลด — ข้าม (ไปตกไม่ได้อยู่แล้ว)"):format(tostring(isl)))
        end
        return false
    end

    -- ⚠ ด่านที่ "เหนือกว่า" isl (ผู้ใช้สั่ง 2026-10-24)
    --   เกาะนั้นปลดหรือยัง ≠ เราพร้อมล่าบอสหรือยัง — บอสบน Starter/Jungle เกิดได้
    --   และ islandUnlocked ก็ผ่าน แต่ดาเมจตอนนั้นไม่พอ = ทิ้งฟาร์มไปตีแล้วได้เปล่า
    --   เงื่อนไข: ต้องปลด CONFIG.Boss.MinIsland (island_desert) ก่อน = มีสกิลอย่างต่ำ
    --   Rare แล้ว (ได้มาจากบันไดเบ็ด 90k/เกาะ) จึงตกบอสได้จริง -> ก่อนหน้านั้นฟาร์มต่อ
    if not bossIslandReady(data) then
        if S.bossSkip ~= "min-island" then
            S.bossSkip = "min-island"
            logWarn(("[Boss] บอสเกิดที่ %s แต่ยังไม่ปลด %s — ยังไม่ล่าตอนนี้ (ดาเมจไม่พอ) ฟาร์มปลดเกาะก่อน")
                :format(tostring(isl), tostring(islandTag(CONFIG.Boss.MinIsland))))
        end
        return false
    end

    S.bossSkip = nil
    if bossLockedOut(data) then return false end

    logWarn(("[Boss] 🔴 พบบอสที่ %s — ไปตี (ยืนสูงกว่าจุดบอส %d studs)")
        :format(tostring(isl), CONFIG.Boss.HeightUp))
    S.bossSeenAt = os.clock()
    S.bossHolding = true
    S.bossDriftAt = 0      -- รอบใหม่ = ให้ว่ายกลับได้ทันทีไม่ต้องรอ DriftRecoverSec
    if not goToBoss() then
        S.bossHolding = false
        S.bossRegion = nil
        S.bossDriftAt = 0
        return false
    end
    return true
end

-- ══════════════════════════════════════════════════════════════════
-- 6) DAILY QUEST — ทำหลังแผนครบ (ได้ Dread Fish Rod) ต่อทุกวัน 20 ใบ
--
-- ⚠ ข้อที่คนมักเข้าใจผิด: "รับที่เกาะ Starter" ไม่ได้แปลว่าได้เควสต์ของ Starter
--   DailyQuestUtil.PickIsland (DailyQuestUtil.lua:207) สุ่มเกาะจากทุกเกาะที่ปลดแล้ว:
--     if #unlocked ~= 1 and not (rng:NextNumber() < 0.7) then
--         return unlocked[#unlocked - 1]   -- เกาะรองสูงสุด  โอกาส 30%
--     end
--     return unlocked[#unlocked]           -- เกาะสูงสุด    โอกาส 70%
--   แล้วเขียน IslandId ลงใน Active ที่รับมา -> ต้องไปตกที่ IslandId นั้นเท่านั้น
--   = สคริปต์ห้ามเดาเกาะเอง ต้องอ่าน Active.IslandId จากข้อมูลผู้เล่นสด ๆ
--
-- ⚠ รับได้ 20 ใบ/วัน กองจำกัด (Deck Easy 10 / Medium 5 / Hard 5) รีเซ็ตทุก 86400 วิ
--   "cancel" = กินโควตาทิ้ง + ตก FullClearBonus 25 gem (DailyQuestConfig)
--   -> สคริปต์นี้ไม่มี action ยกเลิกเด็ดขาด
--
-- ⚠ ต้องทำเควสต์ปกติให้เสร็จก่อน: Quest.Current.Id ~= "" = server ไม่ให้รับ
--
-- ⚠ ไม่ต้องยิงอะไรตอนครบ: เซิร์ฟ push DailyQuest/Completed(gem, coin) มาเอง
--   (QuestController.lua:984 แค่เล่นเสียง+โชว์ข้อความ)
-- ══════════════════════════════════════════════════════════════════
DailyQuestCfg = req(ReplicatedStorage.Data.Config.DailyQuestConfig, "DailyQuestConfig")
DailyQuestPkt = req(ReplicatedStorage.Data.Packets.DailyQuestPackets, "DailyQuestPackets")

--- เทมเพลตจริงของเควสต์ที่กำลังทำ (อ่านจากคอนฟิกสด ไม่ hardcode เงื่อนไข)
function dqTemplate(tier, id)
    if not (DailyQuestCfg and type(tier) == "string" and type(id) == "string") then return nil end
    local list = (DailyQuestCfg.Templates or {})[tier]
    if type(list) ~= "table" then return nil end
    for _, t in ipairs(list) do
        if t.id == id then return t end
    end
    return nil
end

--- เควสต์รายวันที่กำลังทำอยู่ -> ตาราง Active (หรือ nil)
---   Active = {Template,Tier,IslandId,FishId,Target,Progress,AcceptedAt}
---   (DailyQuestUtil.EmptyActive — โครงสร้างเดียวกับที่เกมเขียนลงโปรไฟล์)
function dqActive(data)
    local dq = data and data.DailyQuest
    if type(dq) ~= "table" then return nil end
    local a = dq.Active
    if type(a) ~= "table" then return nil end
    if a.Template == nil or a.Template == "" then return nil end
    return a
end

--- กองเควสต์วันนี้เหลือกี่ใบ (นับจาก DailyQuest.Deck ของโปรไฟล์)
function dqDeckLeft(data)
    local dq = data and data.DailyQuest
    if type(dq) ~= "table" or type(dq.Deck) ~= "table" then return 0 end
    local n = 0
    for _, v in pairs(dq.Deck) do
        if type(v) == "number" then n = n + v end
    end
    return n
end

--- ตอนนี้มีเควสต์ปกติค้างอยู่ไหม (รับ Daily ไม่ได้ตอนนั้น)
function dqNormalQuestBusy(data)
    local q = data and data.Quest
    local cur = q and q.Current
    if type(cur) ~= "table" then return false end
    return (cur.Id or "") ~= ""
end

--- เควสต์นี้คือแบบสุ่มสกิลหรือจับปลา?
---   skill_gacha นับจากจำนวนครั้งที่กด (DailyQuestUtil.CatchCounts ไม่เกี่ยว)
---   จับปลา นับตอนจับจริงบนเกาะที่ Active.IslandId ระบุ
function dqIsGacha(a)
    local t = dqTemplate(a.Tier, a.Template)
    return (t and t.objective == "skill_gacha") or false
end

--- ข้อความสรุปของเควสต์ที่กำลังทำ ใช้แสดงผลกับผู้ใช้
function dqLabel(a)
    if not a then return "?" end
    local t = dqTemplate(a.Tier, a.Template) or {}
    local need = a.Target or 0
    local got = a.Progress or 0
    local extra = ""
    if t.minRarity then extra = extra .. (" · ≥%s"):format(tostring(t.minRarity)) end
    if t.minWeight then extra = extra .. (" · ≥%dkg"):format(t.minWeight) end
    if t.species and a.FishId and a.FishId ~= "" then
        extra = extra .. (" · %s"):format(tostring(a.FishId))
    end
    if t.skillKill then extra = extra .. " · ต้องใช้สกิลฆ่า" end
    if t.newSpecies then extra = extra .. " · ต้องเป็นชนิดที่ยังไม่เคยจับ" end
    if t.objective == "skill_gacha" then
        extra = " · กดสุ่มสกิล"
    else
        extra = extra .. (" · ที่ %s"):format(islandTag(a.IslandId))
    end
    return ("Daily %s/%s %d/%d%s"):format(
        tostring(a.Tier), tostring(a.Template), got, need, extra)
end

--- เกาะของ instance ที่ระบุ -> เดินขึ้น parent จนถึงโฟลเดอร์ใต้ Workspace.World.Islands
function dqIslandOf(inst)
    local islands = Workspace:FindFirstChild("World")
    islands = islands and islands:FindFirstChild("Islands")
    if not (inst and islands) then return nil end
    local p = inst
    while p and p ~= islands do
        if p.Parent == islands then return p.Name end
        p = p.Parent
    end
    return nil
end

--- เดินไปยืนใกล้ NPC รับเควสต์รายวัน (ภายใน DailyQuestConfig.NpcRadius = 25)
---   1) มองหา NPC ที่ stream อยู่ก่อน แล้วข้ามไปเกาะของมัน (ข้ามได้เพราะเป็นเกาะที่ปลดแล้ว)
---   2) ถ้ามองไม่เห็นเลย = แสดงว่าไม่ได้ stream (เราอยู่คนละเกาะ) -> ไปที่ Starter แล้วหาใหม่
---      Starter เป็น defaultUnlocked = true จึงไปได้เสมอ และ NPC ประเภทนี้อยู่ที่ hub
--- คืน true ถ้ายืนใกล้แล้ว / ไม่พบ NPC เลยก็ true (ให้ยิงจากจุดที่ยืนไป)
function dqStandByNpc()
    -- อ่านรัศมีสดจากคอนฟิกของเกมก่อน (ค่าใน CONFIG เป็นแค่ fallback)
    local radius = tonumber(CONFIG.Daily.NpcRadius) or 25
    if DailyQuestCfg and type(DailyQuestCfg.NpcRadius) == "number" then
        radius = DailyQuestCfg.NpcRadius
    end
    local npc = findNearestNpcAnywhere(CONFIG.Daily.NpcId)
    local isl = npc and dqIslandOf(npc) or nil

    if not npc then
        -- ยังไม่เห็นตัวเลย -> ไป Starter ก่อนแล้วค่อยหา (รอให้ stream ทัน)
        if currentIslandId() ~= "island_starter" then
            S.traveling = true
            local ok = travelToIsland("island_starter")
            S.traveling = false
            if not ok then return false end
        end
        npc = waitForNpcOnIsland("island_starter", CONFIG.Daily.NpcId, 6)
    elseif isl and currentIslandId() ~= isl then
        S.traveling = true
        local ok = travelToIsland(isl)
        S.traveling = false
        if not ok then return false end
    end

    if not npc then
        logWarn("[Daily] หา NPC รับเควสต์ไม่เจอแม้แต่ที่ Starter — ยิงจากจุดที่ยืน")
        return true
    end
    local hrp = npc:FindFirstChild("HumanoidRootPart")
    if not (hrp and hrp:IsA("BasePart")) then return true end
    local me = root()
    if me and (me.Position - hrp.Position).Magnitude <= radius then
        return true      -- อยู่ใกล้พอแล้ว ไม่ต้องเดิน
    end
    S.moving = true
    -- ยืนข้าง NPC ไม่ใช่บนหัว NPC (กันตัวเองถูกบังแล้วนับระยะไม่ผ่าน)
    local reach = math.max(1, radius - 6)
    tweenDiveTo(hrp.Position + Vector3.new(reach, 0, 0), "dq-npc")
    S.moving = false
    return true
end

--- รับเควสต์รายวันใบใหม่ -> true เมื่อ server ตอบว่าได้
--- ⚠ ไม่เรียก QuestCtl:AcceptDaily() เพราะมันโยน NotificationController:Push
---   ตอนปฏิเสธ = มีหน้าต่างโผล่ (ผู้ใช้ห้ามมีหน้าต่าง) -> ยิง packet ตรงแทน
function dqAccept(data)
    if not (DailyQuestPkt and DailyQuestPkt.Action) then
        logWarn("[Daily] ไม่มี DailyQuestPackets — รับเควสต์ไม่ได้")
        return false
    end
    -- ⚠ DailyQuestConfig.NpcRadius = 25 เป็นรัศมีเดียวในทั้งชุดคอนฟิกที่ client ไม่มีที่ไหน
    --   อ่านมันเลย (เทียบ focus_radius / maxActivationDistance / InteractionRadius
    --   ที่ถูกใช้ทุกตัว) -> แทนที่ด้วยว่าเป็น **กติกาที่เซิร์ฟเช็ก** ไม่ใช่ค่าตายที่ลืม
    --   เควสต์ปกติไม่มีรัศมีแบบนี้เลย (ใช้แค่ QuestPacket ที่ไม่มีเช็กระยะ)
    --   = เควสต์รายวันเป็นตัวเดียวที่อาจต้องเดินไปใกล้ NPC
    if CONFIG.Daily.WalkToNpc then
        dqStandByNpc()
    end

    local ok, res, err = pcall(function()
        return DailyQuestPkt.Action:Fire("accept")
    end)
    if not ok then
        logWarn(("[Daily] ยิง accept error: %s"):format(tostring(res)))
        return false
    end
    if res ~= true then
        logWarn(("[Daily] server ไม่ให้รับ (%s) — ไม่ยิงซ้ำ"):format(tostring(err or "ไม่ตอบ/timeout")))
        return false
    end
    return true
end

--- สุ่มสกิล 1 ครั้งให้เควสต์ skill_gacha
--- คืน true เมื่อ "กดสำเร็จ" (runStep จะรอบหน้าค่อยตัดสินใจใหม่)
---   คืน false,"no-coin" เมื่อเงินไม่พอ -> runStep จะพาไปฟาร์มเงินเอง
---
--- ⚠ โปรเกรสของเควสต์รายวันนับที่ฝั่งเซิร์ฟ อาศัยข้อมูล replicate ช้ากว่า packet ที่เรายิง
---   = Progress ที่เราอ่านได้อาจยังเป็นค่าเก่า 1-2 รอบ
---   ถ้านับ "จำนวนครั้งที่กด" ตรง ๆ จะกดเกินเป้าโดยไม่รู้ตัว
---   แก้โดย: นับรอบเฉพาะที่ Progress ยังเป็นค่าเดิม + เผื่อไว้ 3 ครั้งแล้วพัก
function dqGachaPull(data, a)
    local got, need = a.Progress or 0, a.Target or 0
    local left = need - got
    if left <= 0 then return false end
    if S.dqGachaAt ~= got then          -- เซิร์ฟขยับโปรเกรสแล้ว = ตัดนับใหม่
        S.dqGachaAt, S.dqGachaPulls = got, 0
    end
    if S.dqGachaPulls >= left + 3 then
        logWarn(("[Daily] กดสุ่มไปแล้ว %d ครั้ง แต่ Progress ยังเป็น %d/%d — เว้นรอบให้ข้อมูลเซิร์ฟ")
            :format(S.dqGachaPulls, got, need))
        return false
    end
    local ok, why = rollSkillOnce(data)
    if not ok then
        S.dqGachaPulls = 0
        return false, why   -- "no-coin" = ไปฟาร์มเงิน · อื่น ๆ = ให้ runStep ลองซ้ำตาม backoff
    end
    S.dqGachaPulls = S.dqGachaPulls + 1
    return true
end

--- คืน action ขั้นตอนถัดไปของเควสต์รายวัน (หรือ nil = ไม่มีอะไรต้องทำตอนนี้)
--- ⚠ คืน nil ตอน "มีเควสต์แล้วแต่ยังไม่ครบ" โดยเจตนา เพราะการตกปลาเป็นหน้าที่
---   ของ mainLoop อยู่แล้ว — แค่ให้ activeFarmIsland พาไปเกาะที่ถูกต้อง
function dqStep(data)
    if not (CONFIG.Daily and CONFIG.Daily.Enabled) then return nil end
    if not data then return nil end
    local dq = data.DailyQuest
    if type(dq) ~= "table" then
        if not S.dqWarned then
            S.dqWarned = true
            logWarn("[Daily] อ่าน data.DailyQuest ไม่ได้ — ข้ามเควสต์รายวัน")
        end
        return nil
    end

    local a = dqActive(data)

    -- ตัวระบุเควสต์ใบที่กำลังทำ = Tier/Template/เวลาที่รับ
    --   เปลี่ยนเมื่อเปลี่ยนใบ (รวมตอนกลับมาเป็น nil) -> ใช้รีเซ็ตตัวนับกดสุ่ม
    local qid = a and ((a.Tier or "") .. "/" .. (a.Template or "") .. "@" .. tostring(a.AcceptedAt)) or nil
    if qid ~= S.dqQuestId then
        S.dqQuestId, S.dqGachaAt, S.dqGachaPulls = qid, nil, 0
    end

    -- 1) กำลังทำอยู่ -> ทำต่อให้ครบ
    if a then
        local got, need = a.Progress or 0, a.Target or 0
        if got >= need then
            -- ครบแล้ว (เซิร์ฟส่ง DailyQuest/Completed มาเอง ไม่ต้องยิงอะไร) -> รอบหน้าค่อยรับใบใหม่
            return nil
        end
        if dqIsGacha(a) then
            return {
                key = "dq:gacha",
                label = dqLabel(a),
                quiet = true,
                run = function() return dqGachaPull(data, a) end,
            }
        end
        -- เป็นเควสต์จับปลา -> ไม่ต้องยิงอะไร แค่ไปตกที่ Active.IslandId
        --   (activeFarmIsland อ่าน IslandId เดียวกันนี้แล้วพาไปตกถูกเกาะ)
        return nil
    end

    -- 2) ไม่มีใบที่กำลังทำ + กองยังเหลือ -> รับใบใหม่
    local left = dqDeckLeft(data)
    if left <= 0 then
        return nil
    end
    S.dqSaidDone = false

    if dqNormalQuestBusy(data) then return nil end

    return {
        key = "dq:accept",
        label = ("รับเควสต์รายวัน (เหลือ %d ใบ)"):format(left),
        run = function() return dqAccept(data) end,
    }
end

-- ══════════════════════════════════════════════════════════════════
-- 7) LOW MODE — ปิดการเรนเดอร์ 3D (หน้าจอดำ) + UI สถิติรวม · กด N สลับ
--
-- ⚙ วิธีปิด = RunService:Set3dRenderingEnabled(false)   ← ระดับเอนจิน คำสั่งเดียวจบ
--   เหมือนสคริปต์ 99 Nights in the Forest พอดี (MainScript.lua บรรทัด 676-691)
--   เอนจินหยุดวาดทั้งฉากในจังหวะเดียว ไม่ต้องไล่ Workspace ทีละชิ้น
--   = เร็วกว่าเดิมมาก และไม่ต้องเก็บค่า Transparency/Enabled เดิมไว้เป็นพันชิ้น
--
-- ⚠ ข้อดี: แผงสถิติ (GUI) อยู่คนละชั้นกับฉาก 3D จึงยังวาดอยู่ปกติ
-- ⚠ ข้อควรรู้ (ต่างจากเดิม): เดิมใช้ Transparency ซึ่งเป็นเรื่อง "ภาพ" อย่างเดียว
--   ตอนนี้เอนจินหยุดวาดทั้งไป ถ้าเกมเริ่มมีอาการแปลก ๆ (เช่น Raycast ไม่ชนชิ้นที่มองไม่เห็น
--   หรือเกมไม่ตอบแพ็กเก็ต) แก้กลับได้ทันที: ในคอนโซลพิมพ์ _G.LowSetRender3d(false)
--   หรือกด N สลับ (สคริปต์ยังรับอินพุตได้ตอนหน้าจอดำ)
-- ══════════════════════════════════════════════════════════════════
Low = {
    on      = false,
    render3d = true,   -- สถานะการเรนเดอร์ 3D ล่าสุด (true = วาดอยู่)
    gui     = nil,
    cover   = nil,
    -- ส่วนสถิติ: root จัดกึ่งกลาง + scale ยึดขนาดจอ + แถวชื่อเบ็ด/ออร่า
    root    = nil,
    scale   = nil,
    sizeRef = nil,   -- กรอบเต็มจอใน ScreenGui ใช้อ่านขนาดจอจริง (ดู lowScreenSize)
    rowLays = {},
    rootLayout = nil,
    logo    = nil,
    lblIsland   = nil,
    rowRod      = nil,
    rowAura     = nil,
    rowWallet   = nil,
    lblRuntime  = nil,
    camType = nil,
    fog     = nil,
    r3dMode  = nil,   -- "engine" = ปิดที่ระดับเอนจิน · "fallback" = ไล่ Workspace

    gapLogo  = nil,   -- ช่องไฟโลโก้ -> Island  (lowApplyScale ย่อตามจอเล็ก)
    gapRun   = nil,   -- ช่องไฟ Gems -> Runtime
    lastVS   = nil,   -- ขนาดจอครั้งล่าสุดที่ใช้ได้ (กัน ViewportSize = 0 ตอนปิด 3D)

    keyConn  = nil,
    camConn  = nil,
    viewConn = nil,
    sizeConn = nil,
    fixing   = false,  -- กัน lowApplyScale ยิงซ้ำเป็นวนจากตัวแก้ล้นจอ
    diagN    = 0,      -- จำนวนครั้งที่ lowApplyScale ทำงาน (นับไว้พิมพ์สถานะ)
    overLog  = 0,      -- จำนวนครั้งที่ตัวกันล้นจอทำงาน (จำกัดการพิมพ์)
    ticking  = false,
}

--- ⚙ ครั้งแรกตอนสตาร์ต: คืนภาพเสมอ แล้วค่อยเปิด LowMode ตามที่ตั้ง
---   (global ไม่ใช่ local: main chunk ของไฟล์นี้ชนเพดาน 200 slots ของ Lua 5.1)
---
--- ⚠ ต้องอยู่ที่ main chunk (เรียกตรงท้ายไฟล์ ไม่ผ่าน task.spawn)
---   ข้อสังเกตจากการรันจริงของผู้ใช้:
---     99 Nights MainScript.lua:697 เรียก Set3dRenderingEnabled ที่ top-level
---     ของ main chunk แล้วใช้ได้ปกติ ส่วนของเราเรียกจากใน
---     task.spawn(progression) แล้วได้ error ว่า
---     "The current THREAD cannot call 'Set3dRenderingEnabled'
---      (lacking capability RobloxScript)"
---   คำว่า "thread" คือกุญแจ: thread ที่ task.spawn สร้างขึ้นมาคนละตัวกับ
---   main chunk และไม่มี capability นี้ จึงต้องย้ายมาเรียกที่ main chunk
---
--- ⚠ ยังห่อ pcall ไว้ เพราะ:
---   ถ้าสมมติฐานนี้ผิด (เช่นคนละตัวรัน) ต้องไม่ลากทั้งสคริปต์ตาย
---   และมี fallback ไล่ Workspace ให้อยู่แล้ว
function LOW_FIRST_RUN()
    -- คืนภาพเสมอ (สถานะ "ปิด 3D" อยู่ที่ตัวเอนจิน = ค้างข้ามการ Execute ได้)
    -- ⚠ เรียกตรง ๆ: ถ้าล้ม error จะหลุดมาที่ fallback ไล่ Workspace แทน
    if not pcall(lowSetRender3d, false) then
        Low.render3d = true
        pcall(applyLowGraphics, false)
    end
    Low.on = false
    if not CONFIG.LowMode.Enabled then return end
    if CONFIG.LowMode.StartOn then
        setLowMode(true)
    end
end

--- ⚙ ปิด/เปิดภาพ 3D — ลองวิธีเอนจินก่อน ถ้าไม่ได้ค่อยใช้วิธีไล่ Workspace
---
--- ⚠ ข้อเท็จจริงที่พิสูจน์แล้ว (ห้ามลองซ้ำอีก ดูหมายเหตุท้ายไฟล์):
---   ทุกทางได้ "The current thread cannot call 'Set3dRenderingEnabled'
---   (lacking capability RobloxScript)" เหมือนกันหมด
---     ตัวแปร local RunService + pcall
---     game:GetService("RunService") + pcall
---     game:GetService("RunService") เรียกตรงที่ main chunk (log 18:56:33)
---
---   99 Nights MainScript.lua:697 เรียกตรงใน LocalScript ของเกมเอง ได้ผล
---   เพราะเป็นสคริปต์ของเกม (มี capability อยู่แล้ว) ส่วนเรารันโดย executor
---   -> ต่างกันที่ "สิทธิ์ของตัวสคริปต์" ไม่ใช่รูปแบบโค้ด
---   -> ที่เหลือคือ fallback ไล่ Workspace ซึ่งปิดภาพได้จริงเหมือนกัน
---
--- ⚠ ทำไมต้องห่อ pcall (สำคัญมาก):
---   ตอนที่เรียกตรง ๆ error ไหลขึ้นไปถึง progression() = สคริปต์ทั้งไฟล์ตาย
---   LowMode เป็นแค่ฟีเจอร์เสริม ห้ามลากส่วนที่เหลือตายเพราะมัน
---   -> ต้องห่อเสมอ แล้วค่อย fallback
---
--- ⚠ fallback = ไล่ Workspace ตั้ง Transparency = 1 (ชุดเดิมของ Infinite Yield)
---   ช้ากว่าและไม่ได้ปิดเอนจินจริง แต่ "ปิดภาพได้จริง" ดีกว่าไม่ได้ทำอะไรเลย
---
--- ⚠ ต้องอ่าน RunService จาก "ตัวแปรสายโลก" ไม่ใช่ตัว local
---   บรรทัด 34 ของไฟล์นี้ประกาศ local RunService = game:GetService("RunService")
---   ซึ่งบังชื่อไว้ทั้งไฟล์ — ผู้ใช้พิมพ์ RunService:Set3dRenderingEnabled(false)
---   ในคอนโซลได้ เพราะตรงนั้นเรียก *global* ตัวที่ตัวรันฉีดให้ ไม่ใช่ตัวนี้
---   การเรียกตรง ๆ ไม่ห่ออะไร (ผู้ใชาสั่ง 2026-10-15) ถ้าล้ม error จะไหลออกไป
---   ถึงจุดเรียก ซึ่งห่อ pcall อยู่แล้วและมี fallback ไล่ Workspace ต่อท้าย
function lowSetRender3d(hide)
    hide = (hide == true)
    local want = not hide                      -- สถานะที่ต้องการ = กำลังวาดอยู่ไหม
    local svc = _ENV.RunService or RunService
    svc:Set3dRenderingEnabled(want)            -- ตรง ๆ ไม่ห่ออะไร
    Low.render3d = want
    Low.r3dMode = "engine"
    return true
end

--- สร้าง ScreenGui + กรอบดำ + แผงสถิติ (สร้างครั้งเดียว แล้วใช้ซ้ำ)
function lowBuildUi()
    if Low.gui and Low.gui.Parent and Low.root and Low.root.Parent then return end
    local pg = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not pg then return end
    local old = pg:FindFirstChild("ProgLowUi")
    if old then pcall(function() old:Destroy() end) end

    local gui = Instance.new("ScreenGui")
    gui.Name = "ProgLowUi"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 1000
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = pg
    Low.gui = gui

    -- ⚙ กรอบอ้างอิงขนาดจอ — อ่านขนาดจอจาก "เลเยอร์ GUI" โดยตรง ไม่พึ่งกล้อง
    --   Size = fromScale(1,1) ใน ScreenGui = เต็มพื้นที่ที่ GUI ถูกจัดให้ = ขนาดจอจริงเสมอ
    --   ⚠ ทำไมต้องมี: ตอนปิดการเรนเดอร์ 3D กล้องรายงาน ViewportSize ผิดหรือเป็น 0
    --     ถ้าเอาไปคำนวณสเกลตรง ๆ = แผงพองจนล้นจอ เห็นแค่บรรทัดเดียวตรงกลาง
    -- ⚠ SizeRef (Frame fromScale(1,1) ใน ScreenGui) ไม่ใช่ตัวอ่านขนาดจอแล้ว
    --   มันคืน "ขนาดแสดงที่ดั้งเดิม" (1920x1080) ไม่ใช่ขนาดหน้าต่างที่ผู้ใช้ตั้ง
    --   ผล: แผงทำเป็น 1534x738 แล้วล้น SCREEN 160x210 -> เห็นแค่ชื่อเกาะ
    --   วัดจาก ViewportSize ของกล้องแทน ดู lowScreenSize
    local sizeRef = Instance.new("Frame")
    sizeRef.Name = "SizeRef"
    sizeRef.Size = UDim2.fromScale(1, 1)
    sizeRef.BackgroundTransparency = 1
    sizeRef.BorderSizePixel = 0
    sizeRef.ZIndex = 0
    sizeRef.Active = false
    sizeRef.Parent = gui
    Low.sizeRef = sizeRef

    -- กรอบดำเต็มจอ — ทำให้พื้นหลังที่เหลือเป็นสีดำ ไม่ใช่สีขาว
    if CONFIG.LowMode.BlackCover then
        local cover = Instance.new("Frame")
        cover.Name = "Cover"
        cover.Size = UDim2.fromScale(1, 1)
        cover.BackgroundColor3 = Color3.new(0, 0, 0)
        cover.BorderSizePixel = 0
        cover.ZIndex = 1
        cover.Active = false
        cover.Parent = gui
        Low.cover = cover
    end

    Low.rowLays = {}   -- layout ของรอบนี้ (ไม่ใช่ของรอบก่อนที่ถูกทิ้งแล้ว)

    -- ทุกอย่างอยู่ใต้ root ที่จัดกึ่งกลาง + UIScale = ข้อความและโลโก้ยึดตามขนาดจอ
    local root = lowMakeRoot(gui)

    local logo = Instance.new("ImageLabel")
    logo.Name = "Logo"
    logo.LayoutOrder = 1
    logo.Size = UDim2.new(0.62, 0, 0, 130)
    logo.BackgroundTransparency = 1
    logo.Image = CONFIG.LowMode.LogoAsset
    logo.ScaleType = Enum.ScaleType.Fit
    logo.ZIndex = 3
    logo.Parent = root
    Low.logo = logo

    -- เว้นโลโก้ออกจากบรรทัดข้อความชัด ๆ (ชื่อกลางจะเป็นไปเองตอนวาด)
    local gap = Instance.new("Frame")
    gap.Name = "LogoGap"
    gap.LayoutOrder = 1.5
    gap.Size = UDim2.new(1, 0, 0, 32)
    gap.BackgroundTransparency = 1
    gap.BorderSizePixel = 0
    gap.Parent = root
    Low.gapLogo = gap

    local LBL  = Color3.fromRGB(238, 238, 245)
    local DIM  = Color3.fromRGB(150, 150, 168)

    -- ⚠ Rod / Aura รวมหัวข้อกับชื่อไว้บรรทัดเดียวกัน (ดู lowHeadRow)
    Low.lblIsland = lowMakeLine(root, 2, "Island : -", LBL)
    Low.rowRod    = lowMakeRow(root, 3)
    Low.rowAura   = lowMakeRow(root, 4)
    -- คำว่า Coins = ทอง · Gems = ชมพูออกม่วง (ตัวเลขเป็นสีขาวตามปกติ)
    -- Coins กับ Gems รวมบรรทัดเดียว คั่นด้วยจุดกลาง (ประหยัดบรรทัด)
    Low.rowWallet = lowMakeRow(root, 5)
    -- ⚙ แยก Gems ออกมาบรรทัดของตัวเอง (ผู้ใช้สั่ง "ทำให้แยกบรรทัดเหมือนเดิม")
    Low.rowGems  = lowMakeRow(root, 6)

    -- เว้นจาก Gems ขึ้นไปประมาณ 1 บรรทัด (Gems เลื่อนไปเป็นบรรทัด 6 แล้ว)
    local gap2 = Instance.new("Frame")
    gap2.Name = "RuntimeGap"
    gap2.LayoutOrder = 6.5
    gap2.Size = UDim2.new(1, 0, 0, 22)
    gap2.BackgroundTransparency = 1
    gap2.BorderSizePixel = 0
    gap2.Parent = root
    Low.gapRun = gap2

    Low.lblRuntime = lowMakeLine(root, 7, "Runtime : 00:00:00", DIM)

    lowApplyScale()

    -- ⚠ จอเปลี่ยนขนาดต้องเห็นผล "ทันที" ไม่ใช่รอรอบถัดไป
    --   ตัวที่ฟังหลัก = กล้อง ViewportSize (ตัวที่ lowScreenSize ใช้จริง)
    --   SizeRef เก็บไว้เป็นตัวฟังรอง ไม่ได้ใช้อ่านขนาดจอแล้ว
    --   กล้องฟังไว้เป็นตัวรอง (ตอนสลับสายตา CurrentCamera เปลี่ยนตัว)
    if Low.sizeRef and not Low.sizeConn then
        pcall(function()
            Low.sizeConn = Low.sizeRef:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
                lowApplyScale()
            end)
        end)
    end
    if not Low.camConn then
        pcall(function()
            local function hookViewport()
                local cam = Workspace.CurrentCamera
                if Low.viewConn then pcall(function() Low.viewConn:Disconnect() end) end
                Low.viewConn = nil
                if not cam then return end
                Low.viewConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
                    lowApplyScale()
                end)
            end
            Low.camConn = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
                hookViewport()
                lowApplyScale()
            end)
            hookViewport()
        end)
    end

    -- นาฬิกาเวลารัน: อ่านเวลาจริงทุกวินาที (ไม่ใช่ตัวนับ) จึงไม่เพี้ยนตามแลค
    if not Low.ticking then
        Low.ticking = true
        task.spawn(function()
            while true do
                task.wait(1)
                lowTickRuntime()
            end
        end)
    end
end

--- ตัวเลขแบบมีคอมม่า (อ่านของเกมถ้ามี ไม่งั้นทำเอง)
NumberFormatLib = req(ReplicatedStorage.Utils.NumberFormat, "NumberFormat")

function lowNum(n)
    n = tonumber(n) or 0
    if NumberFormatLib and NumberFormatLib.FormatGrouped then
        local ok, s = pcall(function() return NumberFormatLib.FormatGrouped(n) end)
        if ok and type(s) == "string" and s ~= "" then return s end
    end
    local s = tostring(math.floor(n))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    out = out:gsub("^,", "")
    return out
end

--- เบ็ดที่ปลดล็อกแล้ว เรียงจาก luck มาก -> น้อย (ข้อมูลดิบ ใช้ร่วมกับ Horst)
--- สีตามระดับหายาก เป็น hex 6 หลัก (ไม่มี #) rarityColor3() แปลงเป็น Color3 ให้ TextColor3 โดยตรง
---   อ่านจาก RarityEnums.PrimaryColor ของเกมตรง ๆ = สีเดียวกับที่เกมใช้แสดงผล
---   ค่าสำรองท้าย ๆ คัดลอกจาก RarityEnums ไว้กัน require ไม่ได้
function buildRarityColors()
    local out = {}
    local pc = (type(RarityEnums) == "table" and RarityEnums.PrimaryColor) or nil
    if type(pc) == "table" then
        for r, c in pairs(pc) do
            local ok, hx = pcall(function() return c:ToHex() end)
            if ok and type(hx) == "string" then
                -- Color3:ToHex() ของ Roblox คืน "RRGGBB" ไม่มี # (เกมเขียน "#" .. hx เอง)
                -- กันเหนือกว่า: ตัด # / 0x ออก แล้วเอา 6 หลักท้าย + ทำเป็นตัวพิมพ์เล็ก
                local hex = hx:gsub("^#", ""):gsub("^0[xX]", "")
                if #hex >= 6 then out[r] = hex:sub(-6):lower() end
            end
        end
    end
    out.Common    = out.Common    or "ffffff"
    out.Uncommon  = out.Uncommon  or "00f900"
    out.Rare      = out.Rare      or "00fdff"
    out.Epic      = out.Epic      or "ff40ff"
    out.Legendary = out.Legendary or "ffc241"
    out.Mythical  = out.Mythical  or "ff3000"
    out.Divine    = out.Divine    or "ff407f"
    return out
end

RARITY_COLOR = buildRarityColors()

--- สีของระดับนั้น (fallback = สีที่ใช้เมื่ออ่านระดับไม่ได้)
function rarityColor(rarity, fallback)
    return RARITY_COLOR[rarity] or fallback or "cccccc"
end

function rodRankList(data)
    local rods = data and data.Rods
    if type(rods) ~= "table" then return {} end
    local rows = {}
    for id in pairs(rods) do
        if type(id) == "string" and id ~= "" then
            local meta = nil
            if Catalog and Catalog.Rod and Catalog.Rod.GetById then
                pcall(function() meta = Catalog.Rod.GetById(id) end)
            end
            local luck, atk = 0, 0
            if type(meta) == "table" then
                for _, s in ipairs(meta.stats or {}) do
                    if s.stat == "luck" then luck = luck + (tonumber(s.value) or 0) end
                    if s.stat == "attackDamage" then atk = atk + (tonumber(s.value) or 0) end
                end
            end
            rows[#rows + 1] = {
                name = (type(meta) == "table" and meta.name) or id,
                rarity = (type(meta) == "table" and meta.rarity) or "Common",
                luck = luck, atk = atk,
            }
        end
    end
    table.sort(rows, function(a, b)
        if a.luck ~= b.luck then return a.luck > b.luck end
        return a.atk > b.atk
    end)
    return rows
end


--- ห่อข้อความด้วยแท็กสี (เติม # ให้เอง) + escape ข้อความ


--- สร้างบรรทัด rich text ของเบ็ดให้ UI

--- Aura ที่ Legendary ขึ้นไป รวมตัวซ้ำเป็นจำนวน (ข้อมูลดิบ ใช้ร่วมกับ Horst)
--- เบ็ดที่แสดงใน UI — ตัด Common (เช่น Wooden Rod) ออก เหลือเฉพาะที่มีความหมาย
function lowRodNames(data)
    local out = {}
    for _, r in ipairs(rodRankList(data)) do
        local rar = tostring(r.rarity)
        if rar ~= "Common" then
            -- ตัดคำว่า "Rod" ท้ายชื่อทิ้ง ประหยัดความกว้างของบรรทัด
            -- (ทั้งแถวเขียนว่า "Rod : ..." อยู่แล้ว จะซ้ำสองรอบ)
            local nm = tostring(r.name):gsub("%s*[Rr]od%s*$", "")
            if nm == "" then nm = tostring(r.name) end
            out[#out + 1] = { name = nm, rarity = rar }
        end
    end
    return out
end

--- Aura ที่ Legendary ขึ้นไป ตัวซ้ำรวมเป็นจำนวนนำหน้าชื่อ ("2x Aura2")
function lowAuraNames(data)
    local out = {}
    for _, o in ipairs(auraHighList(data)) do
        local nm = tostring(o.name)
        if o.count and o.count > 1 then nm = ("%dx %s"):format(o.count, nm) end
        out[#out + 1] = { name = nm, rarity = tostring(o.rarity) }
    end
    return out
end

--- ข้อความ/ตัวเลขทั้งหมดที่ UI ใช้ + ลายเซ็นไว้เทียบว่าต้องวาดใหม่ไหม
function lowStatsModel(data)
    local rods, auras = lowRodNames(data), lowAuraNames(data)
    local m = {
        island = topIslandName(data) or "-",
        rods   = rods,
        auras  = auras,
        coin   = compactNum(data and data.Coin),
        gem    = compactNum(data and data.Gem),
    }
    local sig = { m.island, m.coin, m.gem }
    for _, r in ipairs(rods) do sig[#sig + 1] = r.name .. r.rarity end
    for _, a in ipairs(auras) do sig[#sig + 1] = a.name .. a.rarity end
    return m, table.concat(sig, "|")
end
function auraHighList(data)
    local minRank = AURA_RANK[CONFIG.LowMode.AuraMin] or 5
    local count, order = {}, {}
    for _, a in ipairs(readAuras(data)) do
        local r = AURA_RANK[a.rarity] or 0
        if r >= minRank then
            local nm = tostring(a.name)
            if count[nm] then
                count[nm] = count[nm] + 1
            else
                count[nm] = 1
                order[#order + 1] = { name = nm, rank = r, rarity = a.rarity }
            end
        end
    end
    if #order == 0 then return {} end
    table.sort(order, function(a, b)
        if a.rank ~= b.rank then return a.rank > b.rank end
        return count[a.name] > count[b.name]
    end)
    for _, o in ipairs(order) do o.count = count[o.name] end
    return order
end

--- สร้างบรรทัด rich text ของ Aura ให้ UI · ตัวไหนซ้ำกันเขียน x2/x3 นำหน้า

--- ชื่อเกาะที่ปลดสูงสุดตอนนี้ (อ่านจาก UnlockedIslands จริง ไม่ hardcode)
--- ชื่อเกาะแบบสั้นพร้อมลำดับที่ปลด เช่น "Jungle (2)"
---   ตัดคำว่า " Island" ท้ายชื่อทิ้ง (เกมตั้งชื่อว่า "Jungle Island")
---   อ่าน order จาก Catalog.Island ก่อน ถ้าไม่ได้ค่อยไล่จาก islandChain
function islandShortName(islandId)
    local meta = nil
    if Catalog and Catalog.Island and Catalog.Island.GetById then
        local ok, m = pcall(function() return Catalog.Island.GetById(islandId) end)
        if ok and type(m) == "table" then meta = m end
    end
    local nm, ord = islandId, nil
    if meta then
        if type(meta.name) == "string" and meta.name ~= "" then nm = meta.name end
        ord = tonumber(meta.order)
    end
    if not ord then
        for i, e in ipairs(islandChain()) do
            if e.id == islandId then ord = tonumber(e.order) or i break end
        end
    end
    nm = tostring(nm):gsub("%s*[Ii]sland%s*$", "")
    if ord then return ("%s (%d)"):format(nm, ord) end
    return nm
end

--- กระเป๋าของผู้เล่น — คืน nil ถ้า Inventory ไม่ใช่ตาราง
---   data จากเซิร์ฟอาจยังไม่ครบรูปตอนที่สคริปต์เริ่ม ห้ามเดาว่าเป็นตาราง
function invOf(data)
    local inv = data and data.Inventory
    return (type(inv) == "table") and inv or nil
end

--- ตัวเลขจากข้อมูลเกม — ถ้าไม่ใช่ตัวเลขจริงให้คืนค่าสำรอง
---   (หน้าตาแบบ `x or 0` กันแค่ nil เท่านั้น ถ้า server ส่งมาผิดชนิดจะเทียบแล้วพังทันที)
function numOr(v, d)
    return type(v) == "number" and v or d
end

--- จำนวนไอเทมที่มีในกระเป๋า (แบบเดียวกับ Shared/getItemCount.lua ของเกม)
---   ของเควสต์เบ็ดที่ไม่ใช่ปลา เช่น bamboo_fragment อยู่ใน Inventory.Items ไม่ใช่ Inventory.Fishes
--- ⚠ ต้องประกาศ "ก่อน" activeFarmIsland (7872) — ถ้าเป็น local ที่อยู่ใต้ call site
---   ตัวเรียกจะไปหยิบ global ชื่อเดียวกันซึ่งเป็น nil ⇒ "attempt to call a nil value"
---   ตอนรันจริงเท่านั้น (sim ไม่จับ เพราะ slice() แปลง local -> global ให้)
local function itemCount(data, itemId)
    local inv = invOf(data)
    local items = inv and inv.Items
    local e = type(items) == "table" and items[itemId]
    if type(e) == "table" and type(e.count) == "number" then return e.count end
    return 0
end

--- ชื่อเกาะสำหรับข้อความใน log — คืนชื่อย่อ + เลขลำดับ ("Jungle (2)")
---   กัน nil/ค่าผิดแบบไว้ก่อน เผื่อค่ามาจาก data ของเกมที่เราไม่ได้คุม
function islandTag(islandId)
    if type(islandId) ~= "string" or islandId == "" then return tostring(islandId) end
    return islandShortName(islandId)
end

--- ชื่อเบ็ดสำหรับข้อความใน log — อ่านจาก Catalog.Rod ถ้าอ่านไม่ได้คืน id เดิม
function rodTag(rodId)
    if type(rodId) ~= "string" or rodId == "" then return tostring(rodId) end
    local meta = nil
    if Catalog and Catalog.Rod and Catalog.Rod.GetById then
        local ok, m = pcall(function() return Catalog.Rod.GetById(rodId) end)
        if ok and type(m) == "table" then meta = m end
    end
    if meta and type(meta.name) == "string" and meta.name ~= "" then return meta.name end
    return rodId
end

function topIslandName(data)
    local best
    for _, e in ipairs(islandChain()) do
        if islandUnlocked(data, e.id) then best = e.id end
    end
    if not best then return nil end
    return islandShortName(best)
end

--- ตัวเลขย่อหน่วย: 999 -> "999" · 1.1K · 123.4K · 1.1M · 123.4M · 1.1B · 123.4B
function compactNum(n)
    n = tonumber(n) or 0
    if n < 0 then return "-" .. compactNum(-n) end
    if n < 1000 then return tostring(math.floor(n)) end
    -- ไล่จากหน่วยใหญ่สุดลงมา แล้วเอาหน่วยแรกที่ n ถึง
    local U = { { 1e3, "K" }, { 1e6, "M" }, { 1e9, "B" } }
    for i = #U, 1, -1 do
        if n >= U[i][1] then
            local v = n / U[i][1]
            -- เช่น 999,990 -> 1.0M ไม่ใช่ 1000.0K
            if v >= 999.95 and i < #U then
                return ("%.1f%s"):format(n / U[i + 1][1], U[i + 1][2])
            end
            return ("%.1f%s"):format(v, U[i][2])
        end
    end
    return tostring(math.floor(n))
end

--- hex 6 หลักจาก rarityColor() -> Color3 (เอาไปใส่ TextColor3 โดยตรง ไม่ต้องผ่านแท็ก)
function rarityColor3(rarity, fallback)
    local h = rarityColor(rarity, fallback or "9fe870")
    local r = tonumber(h:sub(1, 2), 16) or 255
    local g = tonumber(h:sub(3, 4), 16) or 255
    local b = tonumber(h:sub(5, 6), 16) or 255
    return Color3.fromRGB(r, g, b)
end

--- เวลาที่สคริปต์รันมานานเท่าไร -> "00:00:00" (ชั่วโมง:นาที:วินาที)
---   คิดจากผลต่างของนาฬิกาจริงสองครั้ง ไม่ใช่ตัวนับที่เพิ่มทีละ 1
---   = สคริปต์ค้าง/เฟรมตกหนักก็ยังขึ้นตรงกับเวลาจริง
function runtimeText()
    if type(PROG_STARTED_AT) ~= "number" then return "00:00:00" end
    local e = nowReal() - PROG_STARTED_AT
    if type(e) ~= "number" or e < 0 then e = 0 end
    e = math.floor(e)
    return ("%02d:%02d:%02d"):format(math.floor(e / 3600), math.floor(e / 60) % 60, e % 60)
end

--- วาดนาฬิกาเวลารัน (เรียกทุกวินาที) — ไม่ต้องรอให้ข้อมูลสถิติเปลี่ยน
function lowTickRuntime()
    if not (Low.on and Low.lblRuntime) then return end
    local t = "Runtime : " .. runtimeText()
    if Low.lblRuntime.Text ~= t then Low.lblRuntime.Text = t end
end

--- ค่าหน้าตาป้ายข้อความทุกป้ายในแผงสถิติ (หนา มีกรอบรอบ จัดกึ่งกลาง)
function lowLabelSkin(lbl, color)
    lbl.BackgroundTransparency = 1
    lbl.BorderSizePixel = 0
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 21
    lbl.TextColor3 = color or Color3.fromRGB(238, 238, 245)
    -- กรอบมืดรอบตัวอักษร · คุณสมบัติชุดนี้กันด้วย pcall เผื่อเวอร์ชันที่ไม่มี
    pcall(function()
        lbl.TextStrokeColor = Color3.fromRGB(8, 8, 12)
        lbl.TextStrokeTransparency = 0.35
        if Enum.TextStrokeApplyMode then
            lbl.TextStrokeApplyMode = Enum.TextStrokeApplyMode.Boundary
        end
    end)
    lbl.TextXAlignment = Enum.TextXAlignment.Center
    lbl.TextYAlignment = Enum.TextYAlignment.Center
    lbl.TextWrapped = false
    -- ⚠ สูง = เต็มพ่อ (1 = scale 100%) ไม่ใช่ 26px คงที่
    --   26px คงที่ทำให้จอใหญ่ (สูง 2160) แถวยังสูง 26 ขณะที่ป้าย Island
    --   สูง LOW_LINE ของจอ = ตัวอักษรต่างกันทุกขนาดจอ
    --
    --   ⚠ "เต็มพ่อ" ปลอดภัยตรงนี้ เพราะพ่อของป้ายถูกบังคับให้สูงเป็นพิกเซลคงที่
    --     เสมอ (ดู lowFillRow) ถ้าพ่อสูงเป็นสเกลของตัวเอง แล้วใช้ AutomaticSize
    --     คิดความสูงตัวเอง จะวนกันทุกเฟรม = แผงกระพริบรัว
    --   ความกว้างยังให้ AutomaticSize = X จัดเองตามความยาวข้อความ
    lbl.Size = UDim2.new(0, 0, 1, 0)

    -- ⚙ หัวใจของการปรับขนาดตามจอ: ให้ "เอนจิน" ย่อขยายตัวอักษรเอง
    --   TextScaled = ตัวอักษรเต็มกรอบเสมอ ไม่ว่าจอใหญ่แค่ไหน
    --   UITextSizeConstraint = กันไว้สองด้าน (เล็กเกินอ่านไม่ออก / ใหญ่เกินบังจอ)
    --   แบบนี้ไม่ต้องคำนวณขนาดตัวอักษรเองที่แต่ละขนาดจอเลย (วิธีของ 99 Nights)
    pcall(function()
        lbl.TextScaled = true
        local c = Instance.new("UITextSizeConstraint")
        c.MinTextSize = LOW_TEXT_MIN
        c.MaxTextSize = LOW_TEXT_MAX
        c.Parent = lbl
    end)

    -- AutomaticSize ทำให้ป้ายกว้างพอดีกับข้อความ (ไม่มี = กำหนดเอง)
    if not pcall(function() lbl.AutomaticSize = Enum.AutomaticSize.X end) then
        lbl.AutomaticSize = Enum.AutomaticSize.None
        lbl.TextXAlignment = Enum.TextXAlignment.Left
    end
    return lbl
end

--- สร้างป้ายบรรทัดเดียวจัดกึ่งกลางเต็มความกว้าง
function lowMakeLine(parent, order, text, color)
    local lbl = Instance.new("TextLabel")
    lbl.Name = "Line" .. tostring(order)
    lbl.LayoutOrder = order
    lowLabelSkin(lbl, color)
    lbl.Text = text
    -- ⚠ สูงเป็นสเกลของจอ ไม่ใช่ 26 พิกเซลคงที่
    --   (26 พิกเซลคงที่ = จอ 160x210 ที่สูง 210 จะกินพื้นที่ทั้งจอไป 3 บรรทัด)
    lbl.Size = UDim2.new(1, 0, LOW_LINE, 0)
    -- ⚠ ห้ามตั้ง AutomaticSize = Y ตรงนี้
    --   TextScaled + AutomaticSize.Y = เอนจินขยายความสูงให้พอดีตัวอักษร
    --   ผลจาก log: Island กับ Runtime สูง 100px ขณะที่ Rod/Aura/Coins 26px
    --   ค่าที่ถูกต้องคือ X (จาก lowLabelSkin) = กว้างพอดีข้อความ สูงคงที่ตามจอ
    lbl.Parent = parent
    return lbl
end

--- ความสูงหนึ่งบรรทัด = วัดจากป้ายที่เอนจินวาดให้อยู่แล้ว ไม่คำนวณเอง
---   ⚠ ห้ามคำนวณจาก lowScreenSize(): ตอนเรียกครั้งแรกแผงยังไม่ถูกวาด
---     AbsoluteSize = 0 -> ตกไปใช้ค่ากันพลาด 1920x1080 -> บรรทัดสูง 48 แทน 26
---     (log: Line2=26 แต่ Row5=48 พื้นที่ใช้ได้ 0) แถวกับป้ายเลยไม่เท่ากัน
---   การวัดจากป้าย Island ตรง ๆ ได้ค่าเดียวกับที่วาดจริงเสมอทุกขนาดจอ
function lowLinePx()
    local l = Low.lblIsland
    if l then
        local ok, a = pcall(function() return l.AbsoluteSize end)
        if ok and a and a.Y >= 4 then return math.floor(a.Y) end
    end
    if Low.root then
        local ok, a = pcall(function() return Low.root.AbsoluteSize end)
        if ok and a and a.Y >= 16 then
            return math.max(8, math.floor(a.Y * LOW_LINE))
        end
    end
    return 26
end

--- แถวที่ห่อชื่อเบ็ด/ออร่า — ไหลซ้าย->ขวา แล้วขึ้นบรรทัดใหม่เมื่อเต็ม
---   ตัดบรรทัดที่ระดับ "ป้าย" เสมอ = ไม่มีทางหักคำกลางคัน
function lowMakeRow(parent, order)
    local row = Instance.new("Frame")
    row.Name = "Row" .. tostring(order)
    row.LayoutOrder = order
    row.BackgroundTransparency = 1
    row.BorderSizePixel = 0
    -- ⚠ สูงเป็นสเกลของจอ (เดิม 26 พิกเซลคงที่ = จอเล็กแถวจะสูงเกินจริง)
    --   AutomaticSize = Y ต้องอยู่ เพราะชื่อยาวต้องโอนลงบรรทัดที่สองได้
    --   ลูกของแถว (Cell / ป้ายว่าง) ต้องสูงเป็นพิกเซลคงที่ ห้ามผูกกับความสูงแถว
    --   ไม่งั้นวงอ้างอิงวนทุกเฟรม = แผงกระพริบรัว (ดู lowFillRow)
    row.Size = UDim2.new(1, 0, LOW_LINE, 0)
    if not pcall(function() row.AutomaticSize = Enum.AutomaticSize.Y end) then
        row.AutomaticSize = Enum.AutomaticSize.None
    end
    row.Parent = parent
    local lay = Instance.new("UIListLayout")
    lay.FillDirection = Enum.FillDirection.Horizontal
    lay.SortOrder = Enum.SortOrder.LayoutOrder
    lay.HorizontalAlignment = Enum.HorizontalAlignment.Center
    lay.VerticalAlignment = Enum.VerticalAlignment.Center
    lay.Padding = UDim.new(0, LOW_GAP_CELL)
    -- Wraps = ตัดบรรทัดอัตโนมัติ (มีใน Roblox รุ่นใหม่ ถ้าไม่มีก็ข้าม ไม่ error)
    if pcall(function() lay.Wraps = true end) then lay.Wraps = true end
    lay.Parent = row
    Low.rowLays = Low.rowLays or {}
    Low.rowLays[#Low.rowLays + 1] = lay
    return row
end

--- เติมชื่อลงแถว (ล้างของเดิมก่อน) · items = { {name=..., rarity=...}, ... }
--- items = { {t=ข้อความ, c=สี, sep=จริง, tail=ข้อความต่อท้าย}, ... }
---   ไม่มี c = สีขาว
--- ⚠ ชิ้นหนึ่ง = เฟรม "Cell" หนึ่งใบ = หน่วยตัดบรรทัดหนึ่งหน่วย
---   ชื่อกับจุลภาคอยู่ใน Cell เดียวกัน การตัดบรรทัดจึงไม่มีวันคั่นจุลภาคไป
---   ขึ้นบรรทัดใหม่ (จอเล็กแล้วโชว์ ", Taoist Rod ," แยกบรรทัด) · sep/tail = สีขาวเสมอ
function lowFillRow(row, items, emptyText)
    if not row then return end
    -- ⚠ ลูกของแถว (Cell / ป้ายว่าง) ต้องสูง "หนึ่งบรรทัด" เป็นพิกเซลคงที่
    --   ห้ามใช้สเกล 1 (100% ของแถว) เพราะแถวใช้ AutomaticSize = Y
    --   เพื่อให้ชื่อที่ยาวโอนลงบรรทัดที่สองได้ -> ถ้าลูกสูงตามแถว แถวก็คำนวณ
    --   ความสูงจากลูก ทั้งสองฝั่งขึ้นกันและกันวนทุกเฟรม ไม่มีวันนิ่ง
    --   ผลคือตัวอักษรทับซ้อนกัน เหลือแค่คำเดียวโดด ๆ กระพริบไม่หยุด
    --   ค่านี้ = ความสูงเดียวกับป้าย Island พอดีโดยการวัด (ดู lowLinePx)
    --   = ทุกบรรทัดจึงได้ตัวอักษรเท่ากัน
    local linePx = lowLinePx()
    for _, c in ipairs(row:GetChildren()) do
        -- Cell = Frame ส่วนข้อความสำรอง = TextLabel ล้วนหมด (UIListLayout ไม่ต้องแตะ)
        if c:IsA("TextLabel") or c:IsA("Frame") then c:Destroy() end
    end
    local WHITE = Color3.fromRGB(238, 238, 245)
    if not items or #items == 0 then
        local l = Instance.new("TextLabel")
        l.LayoutOrder = 1
        lowLabelSkin(l, Color3.fromRGB(150, 150, 168))
        l.Text = emptyText or "-"
        l.Size = UDim2.new(0, 0, 0, linePx)   -- หนึ่งบรรทัด พิกเซลคงที่ ไม่ผูกกับความสูงแถว
        l.Parent = row
        return
    end

    local function piece(parent, order, text, color)
        local p = Instance.new("TextLabel")
        p.LayoutOrder = order
        lowLabelSkin(p, color or WHITE)
        p.Text = tostring(text)
        p.Parent = parent
    end

    for order, it in ipairs(items) do
        local cell = Instance.new("Frame")
        cell.Name = "Cell"
        cell.LayoutOrder = order
        cell.BackgroundTransparency = 1
        cell.BorderSizePixel = 0
        cell.Size = UDim2.new(0, 0, 0, linePx)   -- หนึ่งบรรทัด พิกเซลคงที่ ไม่ผูกกับความสูงแถว
        if not pcall(function() cell.AutomaticSize = Enum.AutomaticSize.X end) then
            cell.AutomaticSize = Enum.AutomaticSize.None
        end
        cell.Parent = row

        local inner = Instance.new("UIListLayout")
        inner.FillDirection = Enum.FillDirection.Horizontal
        inner.SortOrder = Enum.SortOrder.LayoutOrder
        inner.HorizontalAlignment = Enum.HorizontalAlignment.Left
        inner.VerticalAlignment = Enum.VerticalAlignment.Center
        inner.Padding = UDim.new(0, 0)
        inner.Parent = cell

        piece(cell, 1, it.t, it.c)
        if it.sep then
            piece(cell, 2, ",", WHITE)          -- ไม่มีช่องว่างนำหน้า: padding ของแถวอยู่รอบแล้ว
        elseif it.tail then
            piece(cell, 2, it.tail, WHITE)     -- หัวข้อ + ทวิภาค ต้องติดกันเสมอ
        end
    end
end

--- บรรทัดเดียว "หัวข้อ : ชื่อ1 , ชื่อ2" — หัวข้ออยู่แถวเดียวกับชื่อ ไม่ใช่บรรทัดแยก
function lowHeadRow(head, items, emptyText)
    -- หัวข้อกับทวิภาคอยู่ Cell เดียวกัน (tail) = จะไม่มีวันถูกตัดคั่นกลาง
    local row = { { t = head, c = COIN_COLOR, tail = ":" } }
    if not items or #items == 0 then
        row[#row + 1] = { t = emptyText or "-" }
        return row
    end
    for i, it in ipairs(items) do
        row[#row + 1] = { t = tostring(it.name), c = rarityColor3(it.rarity), sep = (i < #items) }
    end
    return row
end

--- สร้างคอนเทนเนอร์กลางจอ + UIScale เพื่อให้ข้อความและโลโก้ยึดตามขนาดจอ
function lowMakeRoot(gui)
    local root = Instance.new("Frame")
    root.Name = "Root"
    root.AnchorPoint = Vector2.new(0.5, 0.5)
    root.Position = UDim2.fromScale(0.5, 0.5)
    -- ⚙ หัวใจของงานรอบนี้: ขนาดเป็น "สเกลล้วน" ไม่มีพิกเซลเดียว
    --   เอนจินจะย่อขยายให้ตามขนาดหน้าต่างเอง (แบบ 99 Nights บรรทัด 211)
    --   = ไม่ต้องคำนวณ และเปลี่ยนขนาดจอแล้วเห็นผลทันทีโดยไม่ต้องมี hook
    root.Size = UDim2.fromScale(LOW_W, LOW_H)
    pcall(function() root.AutomaticSize = Enum.AutomaticSize.None end)
    root.BackgroundTransparency = 1
    root.BorderSizePixel = 0
    root.ClipsDescendants = false
    root.ZIndex = 2
    root.Parent = gui
    Low.root = root

    -- UIScale เหลือไว้เป็น "ตาข่ายนิรภัย" เท่านั้น ปกติ = 1 (ไม่ยุ่ง)
    --   ถ้าวัดแล้วเนื้อหาสูงเกินจอจริง ค่อยย่อทีหลัง
    local scale = Instance.new("UIScale")
    scale.Scale = 1
    scale.Parent = root
    Low.scale = scale

    local pad = Instance.new("UIPadding")
    -- ⚙ ขอบในเป็นสเกล = ย่อขยายตามจอ (เดิมเป็น 4 พิกเซลคงที่ = กินพื้นที่จอเล็ก)
    pad.PaddingTop = UDim.new(0, LOW_PAD)
    pad.PaddingBottom = UDim.new(0, LOW_PAD)
    pad.PaddingLeft = UDim.new(0, LOW_PAD)
    pad.PaddingRight = UDim.new(0, LOW_PAD)
    pad.Parent = root

    local lay = Instance.new("UIListLayout")
    lay.SortOrder = Enum.SortOrder.LayoutOrder
    lay.HorizontalAlignment = Enum.HorizontalAlignment.Center
    lay.VerticalAlignment = Enum.VerticalAlignment.Center
    lay.Padding = UDim.new(0, LOW_GAP_CELL * 0.4)
    lay.Parent = root
    Low.rootLayout = lay
    return root
end

--- สีหัวข้อในแผงสถิติ (ทอง = หัวข้อ + คำว่า Coins, ชมพูออกม่วง = คำว่า Gems)
COIN_COLOR = Color3.fromRGB(255, 212, 121)
GEM_COLOR  = Color3.fromRGB(232, 121, 249)
-- (เคยมี DIM_COLOR / MID_DOT สำหรับคั่น Coins กับ Gems บนบรรทัดเดียวกัน
--  ตอนนี้ผู้ใช้สั่งให้แยกบรรทัดกัน จึงไม่ต้องใช้จุดคั่นแล้ว -> ตัดทิ้งเพื่อคืน slot)

-- ══════════════════════════════════════════════════════════════════
-- ⚙ ค่าปรับขนาดแผงสถิติทั้งหมด (ผู้ใช้แก้เองได้ที่นี่ที่เดียว)
LOW_W           = 0.86    -- ความกว้างแผง = กี่ % ของจอ (สเกลล้วน)
LOW_H           = 1.0     -- ความสูงแผง = กี่ % ของจอ
LOW_FIT         = 0.90    -- ใช้พื้นที่สูงสูงสุดกี่ % (ตาข่ายนิรภัยตอนล้นจริง)
LOW_LINE        = 0.045   -- ความสูงหนึ่งบรรทัดข้อความ = กี่ % ของสูงจอ
                         --   ⚠ ห้ามเกิน 0.050: ทดสอบกับข้อมูลหนัว 8 เบ็ด/12 ออร่า
                         --   ที่ 0.050 ขึ้นไป ตาข่ายนิรภัยเริ่มย่อจริงแล้ว (_tune.py)
                         --   0.045 = ใช้พื้นที่ 78% โดยยังไม่ต้องย่อสักครั้ง
LOW_GAP_LOGO    = 0.014   -- ช่องไฟ โลโก้ -> ชื่อเกาะ
LOW_GAP_RUN     = 0.010   -- ช่องไฟ Gems -> Runtime
LOW_GAP_CELL    = 0.010   -- เว้นระหว่างชิ้นในแถวชื่อเบ็ด/ออร่า
LOW_PAD         = 0.010   -- ขอบในของแผง
LOW_LOGO_H      = 0.155   -- ความสูงโลโก้ = กี่ % ของสูงจอ
LOW_LOGO_W      = 0.62    -- ความกว้างกรอบโลโก้ (สัดส่วนของ root)
LOW_LOGO_MIN_PX = 20      -- โลโก้สูงอย่างน้อยกี่ "พิกเซลบนจอจริง"
                         --   (จอ 160x210 -> 0.155*210 = 32 พิกเซล = พอเห็น)
LOW_TEXT_MIN    = 5       -- ตัวอักษรเล็กสุดบนจอจริง (กันจอเล็กจนอ่านไม่ออก)
LOW_TEXT_MAX    = 120     -- ตัวอักษรใหญ่สุด (กันจอใหญ่บวมจนตัวอักษรยักษ์)

--- ⚠ ทำไมไม่คำนวณขนาดเอง (เรื่องนี้เสียเวลาไปหลายรอบ)
---   เดิมคำนวณพิกเซลทั้งชุด: สเกล, ความกว้าง, ช่องไฟ, กันล้นจอ
---   ปัญหาไม่ใช่สูตร แต่คือ "อ่านค่าผิดตั้งแต่ต้น" — เคยใช้ Frame fromScale(1,1) ใน ScreenGui
---   ซึ่งคืน 1920x1080 (ขนาดแสดงที่ดั้งเดิม) ไม่ใช่ขนาดหน้าต่างที่ผู้ใช้ตั้งจริง
---   ผลคือคำนวณไว้สำหรับจอใหญ่ แล้วไปแสดงบนจอ 160x210 -> เห็นแค่ชื่อเกาะ
---
---   วิธีของ 99 Nights in the Forest (MainScript.lua:208-234) ไม่คำนวณอะไรเลย:
---     mainFrame.Size     = UDim2.new(0.6, 0, 0.6, 0)   <- สเกลล้วน
---     mainPadding        = UDim.new(0.03, 0)          <- ขอบในเป็นสเกล
---     listLayout.Padding = UDim.new(0.02, 0)          <- ช่องไฟเป็นสเกล
---     nameLabel.TextScaled = true                    <- เอนจินย่อขยายตัวอักษรเอง
---   เอนจินจัดการให้เองทุกขนาดจอ รวมถึงที่ไม่มีในตารางที่ใครเคยคิด

--- ⚠ ตัวกันล้นจอที่เหลือ = "ตาข่ายนิรภัย" ไม่ใช่วิธีหลัก
---   TextScaled ย่อให้พอดีกรอบเสมอ แต่ถ้าบรรทัดตัดเยอะ (จอแคบมาก)
---   รวมกันแล้วสูงเกินจอ จึงยังต้องวัดค่าจริงแล้ว UIScale ย่ออีกที
---   ค่าที่วัดมาจาก AbsolutePosition + AbsoluteSize = ค่าที่วาดจริง ไม่ใช่การเดา

--- ขนาดจอจริง — อ่านจากเลเยอร์ GUI ก่อนเสมอ (ไม่ใช่กล้อง)
---   ไล่ลำดับ: กรอบอ้างอิงใน ScreenGui -> กล้อง -> ค่าที่ใช้ได้ล่าสุด -> ค่าเริ่มต้น
---   ⚠ ค่าที่เหลือเป็น "กันพลาด" ไม่ใช่ค่าปกติ — ถ้าพลาดหมด ใช้ค่าล่าสุดที่วัดสำเร็จ
function lowScreenSize()
    -- ⚠ ห้ามตรวจ type(v) == "Vector2" (ของเดิมตรวจ แล้วพังทั้งฟังก์ชัน)
    --   ตัวรันบางตัวคืนค่านี้มาเป็น userdata ที่ type() ไม่ใช่ "Vector2"
    --   ผลคือสาขาวัดจริงทิ้งทั้งหมด ไปจบที่ค่ากันพลาด 1920x1080 ตลอดการเล่น
    --   (log 18:24:06: root = 688x599 แต่ขนาดจอที่ใช้ = 1920x1080, lastVS = nil)
    --   อ่าน .X / .Y ตรง ๆ แล้วเช็คว่าเป็นตัวเลขและไม่เล็กผิดปกติแทน
    local function usable(v)
        -- เพดาน 64px = ต่ำกว่านี้ถือว่าอ่านไม่ได้ (หน้าต่างจริงเล็กสุดของ Roblox มากกว่านี้มาก)
        -- ⚠ เคยเจอค่า 0x0 ทำให้สเกล = 0.16 และความกว้าง = 6 พิกเซล
        --   ผลคือเห็นแค่เส้นจิ้วตรงกลางจอ
        if not v then return false end
        return type(v.X) == "number" and type(v.Y) == "number"
            and v.X >= 64 and v.Y >= 64
    end
    -- ⚠ ลำดับแหล่งที่มา: ขนาดจริงของแผง -> กล้อง -> ค่าสำรอง
    --   เดิมอ่านกล้องอย่างเดียว แต่ Workspace.CurrentCamera เป็น nil ได้
    --   (log 09:47:22 "จอจากกล้อง ViewportSize : nil") ทำให้ได้ 1920x1080
    --   ทั้งที่จอจริง 800x599 -> เลย์เอาต์คิดจาก 1080 ทั้งที่จริง 599
    --   = ทุกอย่างใหญ่เกินจอพอดี
    --   Low.root.AbsoluteSize คือขนาดที่เอนจินวาดจริงเสมอ เพราะ root
    --   กว้าง LOW_W x สูง LOW_H ของจอ -> หารกลับได้ขนาดจริง
    if Low.root then
        local good, a = pcall(function() return Low.root.AbsoluteSize end)
        if good and usable(a) and LOW_W > 0 and LOW_H > 0 then
            local w = a.X / LOW_W
            local h = a.Y / LOW_H
            if usable(Vector2.new(w, h)) then
                Low.lastVS = Vector2.new(w, h)
                return Low.lastVS
            end
        end
    end
    local cam = Workspace.CurrentCamera
    if cam then
        local good, v = pcall(function() return cam.ViewportSize end)
        if good and usable(v) then
            Low.lastVS = v
            return v
        end
    end
    if usable(Low.lastVS) then return Low.lastVS end
    return Vector2.new(1920, 1080)
end

--- ความสูงจริงของเนื้อหาในแผง = กรอบครอบลูกทั้งหมด (วัดจากตำแหน่งที่วาดจริง)
---   ⚠ ต้องวัดจากลูก ไม่ใช่จาก root: root ไม่มี AutomaticSize แล้ว (ดู lowMakeRoot)
---     ถ้าอ่าน root.AbsoluteSize.Y จะได้ค่าที่ตั้งไว้ ไม่ใช่ความสูงจริง
function lowContentHeight()
    if not Low.root then return nil end
    local top, bot
    for _, c in ipairs(Low.root:GetChildren()) do
        if c:IsA("GuiObject") then
            local y = c.AbsolutePosition.Y
            local b = y + c.AbsoluteSize.Y
            if not top or y < top then top = y end
            if not bot or b > bot then bot = b end
        end
    end
    if not top or not bot then return nil end
    local h = bot - top
    if h <= 1 then return nil end
    return h
end

--- พิมพ์สถานะจริงของแผงทั้งหมดลงคอนโซล (เรียกเองได้ที่: _G.lowDiag())
---   ใช้ตอนแผงดูผิด เพราะทุกค่าที่พิมพ์มาคือ "ค่าที่วัดได้จริง" ไม่ใช่ค่าที่ผมเดา
function lowDiag(tag)
    if not (Low.root and Low.scale) then
        if CONFIG.LowMode.Debug then logWarn("[Low] ยังไม่ได้สร้างแผง") end
        return
    end
    local cam = Workspace.CurrentCamera
    local vsRaw = "nil"
    if cam then
        local good, v = pcall(function() return cam.ViewportSize end)
        if good and type(v) == "Vector2" then vsRaw = ("%d x %d"):format(v.X, v.Y) end
    end
    local rootA = Low.root.AbsoluteSize
    local logoA = Low.logo and Low.logo.AbsoluteSize
    local kids = {}
    for _, c in ipairs(Low.root:GetChildren()) do
        if c:IsA("GuiObject") then
            kids[#kids + 1] = ("%s=%d"):format(c.Name, math.floor(c.AbsoluteSize.Y))
        end
    end
    -- ⚠ ต้องประกอบข้อความให้เสร็จก่อน แล้วค่อยส่งเข้า logWarn
    --   ถ้าเขียน logWarn(...):format(...) ตัว :format จะไปเกาะผลลัพธ์ของ logWarn
    --   ซึ่งคืน nil = error "attempt to index nil with 'format'"
    local msg = ("[Low] %s\n")
        .. "  จอจากกล้อง ViewportSize : %s\n"
        .. "  root           : %d x %d  ย่อ %.3f\n"
        .. "  เนื้อหาสูงจริง  : %s  (พื้นที่ที่ใช้ได้ %.0f)\n"
        .. "  โลโก้          : %s\n"
        .. "  ขนาดจอที่ใช้   : %s  (lastVS=%s)\n"
        .. "  บรรทัดที่วัดได้ : %d พิกเซล (แถวที่เติมล่าสุด %s)\n"
        .. "  ลูกของ root    : %s"
    -- ⚠ พิมพ์ค่าที่ lowScreenSize() คืนจริงด้วย เพราะ lastVS เป็น nil ได้
    --   ทำให้เห็นว่ามันตกไปใช้ค่ากันพลาด 1920x1080 หรือเปล่า
    local used = lowScreenSize()
    logWarn(msg:format(tostring(tag),
        vsRaw,
        rootA.X, rootA.Y, Low.scale.Scale,
        tostring(lowContentHeight()), (Low.lastVS and Low.lastVS.Y or 0) * LOW_FIT,
        logoA and ("%d x %d"):format(logoA.X, logoA.Y) or "nil",
        ("%d x %d"):format(used.X, used.Y), Low.lastVS and "มี" or "nil",
        lowLinePx(), tostring(S.rowLinePx),
        table.concat(kids)))
end

--- ปรับขนาดแผงสถิติให้พอดีจอเสมอ (เอนจินจัดการเองเกือบทั้งหมด)
---   ขนาดทั้งหมดเป็นสเกล + TextScaled = ไม่ต้องคำนวณพิกเซลที่แต่ละขนาดจอ
---   ฟังก์ชันนี้เหลือแค่ 2 อย่าง: ช่องไฟ และตาข่ายกันล้นจอ (ดูหัวข้อค่าปรับขนาดข้างบน)
function lowApplyScale()
    if not (Low.root and Low.scale) then return end

    -- ⚠ ไม่ต้องอ่านขนาดจอมาคำนวณอีกแล้ว ขนาดทั้งหมดเป็นสเกล
    --   เอนจินจัดการเอง (วิธีของ 99 Nights) -> ไม่มีจุดที่อ่านค่าผิดได้อีก
    --   เหลือแค่: (ก) ช่องไฟให้สัดส่วนเหมาะสม  (ข) ตาข่ายกันล้นจอ
    local vs = lowScreenSize()

    -- 1) ช่องไฟที่คำนวณไว้ (โลโก้ -> ชื่อเกาะ, Gems -> Runtime)
    pcall(function()
        if Low.gapLogo then Low.gapLogo.Size = UDim2.new(1, 0, LOW_GAP_LOGO, 0) end
        if Low.gapRun then Low.gapRun.Size = UDim2.new(1, 0, LOW_GAP_RUN, 0) end
    end)

    -- 2) โลโก้: สูงเป็นสเกล แต่ต้องไม่เล็กกว่า LOW_LOGO_MIN_PX พิกเซลจริง
    --    (จอ 160x210 -> 0.155*210 = 32 พิกเซล = พอเห็นแล้ว)
    if Low.logo then
        local h = LOW_LOGO_H
        if type(vs) == "Vector2" and vs.Y > 0 then
            local minH = LOW_LOGO_MIN_PX / vs.Y
            if minH > h then h = minH end
        end
        pcall(function() Low.logo.Size = UDim2.new(LOW_LOGO_W, 0, h, 0) end)
    end

    -- 3) ตาข่ายนิรภัย: ถ้าวัดแล้วสูงเกินพื้นที่ = ย่อทั้งแผงลงตามสัดส่วนที่เกิน
    --    ปกติ TextScaled จัดการได้เอง จึงไม่ควรเข้าที่นี่ แต่ถ้าเกิดก็ต้องกัน
    local cap = vs.Y * LOW_FIT
    local gotH = lowContentHeight()
    local over = false
    local s = 1
    if gotH and gotH > cap then
        over = true
        s = math.max(0.02, cap / gotH)
        pcall(function() Low.scale.Scale = s end)
        -- ย่อแล้วต้องวัดใหม่ในเฟรมถัดไป (AbsoluteSize เป็นค่าเฟรมก่อนหน้า)
        if not Low.fixing then
            Low.fixing = true
            task.delay(0, function()
                Low.fixing = false
                lowApplyScale()
            end)
        end
    elseif (Low.scale.Scale or 1) ~= 1 then
        pcall(function() Low.scale.Scale = 1 end)
    end

    -- 4) บันทึกสถานะจริงลงคอนโซล — เปิด/ปิดด้วย CONFIG.LowMode.Debug
    --   ปิดไว้เป็นค่าปกติ (ผู้ใชาสั่ง 2026-10-15) เพราะฟังก์ชันนี้ถูกเรียก
    --   ทุกครั้งที่รีเฟรชสถิติ ไม่ใช่แค่ตอนแผงพัง
    if not CONFIG.LowMode.Debug then return end
    Low.diagN = (Low.diagN or 0) + 1
    if over then Low.overLog = (Low.overLog or 0) + 1 end
    if Low.diagN <= 6 or (over and Low.overLog <= 10) then
        local t = "ครั้งที่ " .. Low.diagN
        if over then
            t = ("ล้นจอ %.0f > %.0f -> ย่อเป็น %.3f (%s)"):format(gotH, cap, s, t)
        end
        -- ⚠ ห่อ pcall ไว้เสมอ ตันฉบับพังตอน lowDiag พลาด -> error ไปตัด lowBuildUi
        pcall(lowDiag, t)
    end
end

--- ข้อความสถิติทั้งหมด -> (ข้อความ, ลายเซ็น) ลายเซ็นเอาไปเทียบว่าต้องวาดใหม่ไหม

--- รีเฟรชข้อความในแผง (ข้ามถ้าข้อมูลไม่เปลี่ยน)
function refreshStatsUi(data, force)
    -- ⚠ ยกเลิกการล็อกกล้องแล้ว (ผู้ใช้บอกว่า "ขยับกล้องไม่ได้")
    --   เดิมบังคับ cam.CameraType = Scriptable ทุกรอบที่ฟังก์ชันนี้ถูกเรียก
    --   Scriptable = เอนจินไม่ขยับกล้องตามเมาส์เลย = ผู้ใช้หันกล้องไม่ได้
    --   เหตุผลเดิมคือกันเกมตั้ง CameraType = Custom ตอนเข้าโหมดตกปลา
    --   (CameraFocusController.lua:84) แต่ตอนนี้ 3D ปิดอยู่จอดำ = มองไม่เห็น
    --   อยู่แล้วว่ามุมกล้องจะเปลี่ยนหรือไม่ จึงไม่ต้องไปแย่งสิทธิ์เมาส์
    if not (Low.gui and Low.root) then return end
    lowApplyScale()
    lowTickRuntime()          -- เวลารันเดินทุกครั้ง ไม่ต้องรอให้ข้อมูลสถิติเปลี่ยน

    local m, sig = lowStatsModel(data)
    -- ⚠ เติมแถวใหม่เมื่อ "ความสูงบรรทัดที่วัดได้" เปลี่ยน ไม่ใช่แค่ข้อมูลเปลี่ยน
    --   รอบแรกแผงยังไม่ถูกวาด วัดได้ค่าผิด (เช่น 26 จริง แต่ได้ 8)
    --   ถ้าข้ามเพราะข้อมูลไม่เปลี่ยน แถวจะค้างค่าผิดไปตลอดจนกว่าข้อมูลจะเปลี่ยน
    local linePx = lowLinePx()
    if (not force) and sig == S.statsSig and linePx == S.rowLinePx then return end
    S.statsSig = sig
    S.rowLinePx = linePx

    Low.lblIsland.Text = "Island : " .. m.island
    -- Coins กับ Gems แยกบรรทัดกัน (ผู้ใช้สั่ง) — tail ทำให้คำกับตัวเลข
    -- อยู่ Cell เดียวกัน ไม่ต้องพึ่งจุดกลางคั่นแล้ว
    lowFillRow(Low.rowWallet, { { t = "Coins", c = COIN_COLOR, tail = ": " .. m.coin } })
    lowFillRow(Low.rowGems,  { { t = "Gems",  c = GEM_COLOR,  tail = ": " .. m.gem } })
    lowFillRow(Low.rowRod, lowHeadRow("Rod", m.rods, "No rod"))
    lowFillRow(Low.rowAura, lowHeadRow("Aura", m.auras,
        ("No aura %s+"):format(tostring(CONFIG.LowMode.AuraMin))))

    -- ⚠ คำนวณสเกลซ้ำหลังเติมข้อความ: รอบแรกวัดตอนแถวยังว่าง จึงได้สเกลใหญ่เกิน
    lowApplyScale()
end

--- สลับ LowMode (ปิด/เปิดการเรนเดอร์ 3D ระดับเอนจิน)
function setLowMode(on)
    on = (on == true)
    if Low.on == on then return end
    Low.on = on

    -- กล้อง: ยกเลิกล็อก CameraType = Scriptable (ผู้ใช้บอกว่า "ขยับกล้องไม่ได้")
    --   Scriptable = เอนจินไม่ขยับกล้องตามเมาส์
    --   เดิมล็อกทั้งตอนเปิดโหมด (ตรงนี้) และทุกรอบที่ refreshStatsUi ถูกเรียก
    --   ตอนนี้ 3D ปิดจอดำอยู่ มุมกล้องมองไม่เห็นอยู่แล้ว จึงไม่มีเหตุผลที่จะแย่ง
    if on then
        local cam = Workspace.CurrentCamera
        if cam and cam.CameraType == Enum.CameraType.Scriptable then
            -- คืนเป็น Custom (ค่าปกติของเกม) เฉพาะตอนที่เราเป็นคนล็อกไว้เอง
            pcall(function() cam.CameraType = Enum.CameraType.Custom end)
        end
        if CONFIG.LowMode.FogBlack then
            local L = game:GetService("Lighting")
            if not Low.fog then
                Low.fog = { FogStart = L.FogStart, FogEnd = L.FogEnd, FogColor = L.FogColor }
            end
            pcall(function()
                L.FogStart = 0
                L.FogEnd = 0.5
                L.FogColor = Color3.new(0, 0, 0)
            end)
        end
    else
        local cam = Workspace.CurrentCamera
        if cam and Low.camType then
            pcall(function() cam.CameraType = Low.camType end)
        end
        Low.camType = nil
        if Low.fog then
            local L = game:GetService("Lighting")
            pcall(function()
                L.FogStart = Low.fog.FogStart
                L.FogEnd = Low.fog.FogEnd
                L.FogColor = Low.fog.FogColor
            end)
            Low.fog = nil
        end
    end

    if CONFIG.LowMode.ShowStats or CONFIG.LowMode.BlackCover then lowBuildUi() end
    if Low.gui then
        Low.gui.Enabled = on
        refreshStatsUi(fetchData(), true)
    end

    -- ⚠ ปิดที่ระดับเอนจิน = สั่งครั้งเดียวจบ ไม่ต้องไล่ Workspace ไม่ต้องรอเฟรม
    --   ถ้าตัวรันไม่ให้สิทธิ์ error จะหลุดมาที่ fallback ด้านล่าง (ผลเหมือนกัน)
    if pcall(lowSetRender3d, on) then return true end
    if Low.r3dWarned ~= true then
        Low.r3dWarned = true
        if CONFIG.LowMode.Debug then
            logWarn("[Low] ตัวรันไม่ให้สิทธิ์ Set3dRenderingEnabled -> ใช้วิธีไล่ Workspace แทน (ผลเหมือนกัน)")
        end
    end
    Low.render3d = on
    pcall(applyLowGraphics, not on)
    return true
end

--- ผูกปุ่มสลับ (ครั้งเดียวตอนสตาร์ต)
function bindLowToggle()
    -- ค้างจากรอบก่อน? (สคริพต์ตายตอนหน้าจอดำ แล้วผู้ Execute ใหม่ใน env เดิม)
    --   = เคลียร์ธงให้ผูกปุ่มใหม่ ไม่งั้น setLowMode จะเจอ Low.on == true
    --   แล้ว return ทิ้ง ไม่ผูกปุ่ม เห็นหน้าจอดำแล้วกด N ไม่มีผล
    --   ⚠ การคืนภาพตอนสตาร์ต ย้ายไปทำที่ main chunk แล้ว (ดู LOW_FIRST_RUN)
    --   เพราะ thread ของ task.spawn ไม่มี capability ตามที่พิสูจน์แล้ว
    --
    -- ⚠ ห้ามตั้ง Low.on = false ตรง ๆ ตรงนี้ (เดิมตั้ง = บั๊ก 2026-10-15)
    --   ตัวฟังก์ชันนี้รันใน task.spawn(progression) ซึ่งเกิด "หลัง" LOW_FIRST_RUN
    --   ที่เพิ่งเปิด LowMode ไปแล้ว (Low.gui.Enabled = true · Low.on = true)
    --   การตั้งเป็น false ทำให้ธงไม่ตรงกับภาพจริง ผลคือ
    --     (1) lowTickRuntime เช็ค Low.on -> นาฬิกา Runtime หยุดนับทั้งที่แผงเปิด
    --     (2) กด N รอบแรกไปเรียก setLowMode(true) ทั้งที่เปิดอยู่แล้ว
    --         = ไม่มีอะไรเกิดขึ้น ต้องกดรอบสองจึงจะปิดได้จริง
    --   ต้องอ่านสถานะจริงจากแผงที่วาดอยู่เสมอ ไม่ใช่เดา (ทำท้ายฟังก์ชัน)
    if not CONFIG.LowMode.Enabled then
        Low.on = false
        if Low.gui then Low.gui.Enabled = false end
        return
    end
    -- ⚠ กด N ได้แม้หน้าจอดำอยู่ เพราะยังรับ input ได้ตามปกติ
    if not Low.keyConn then
        local UIS = game:GetService("UserInputService")
        Low.keyConn = UIS.InputBegan:Connect(function(inp, processed)
            if processed then return end                      -- พิมพ์อยู่ในช่องข้อความ
            if inp.KeyCode == CONFIG.LowMode.ToggleKey then
                setLowMode(not Low.on)
            end
        end)
    end
    -- ⚠ เปิด LowMode ตอนสตาร์ต เสร็จที่ lowFirstRun (main chunk) แล้ว
    --   ที่นี่ทำแค่ "เตรียม UI" ในกรณี StartOn = false (ให้ผู้ใช้กด N เอง)
    if not CONFIG.LowMode.StartOn then
        lowBuildUi()
        if Low.gui then Low.gui.Enabled = false end
        refreshStatsUi(fetchData(), true)
    end

    -- ⚠ ซิงธงกับภาพจริงหลังสุด (LowMode เปิดอยู่ -> Low.on = true)
    --   อ่านจาก Low.gui.Enabled ซึ่งเป็นค่าเดียวที่ตรงกับสิ่งที่ผู้ใช้เห็น
    --   มีแผงแล้วจึงซิงได้ ถ้ายังไม่มีแผง (เกมยังไม่พร้อม) ปล่อยค่าเดิมไว้
    if Low.gui then Low.on = (Low.gui.Enabled == true) end
end

-- 8) HORST — รายงานสถานะไปบอร์ด + ชีท Google
--
--   อ้างอิงจาก 99 Nights in the Forest/MainScript.lua
--   (เอกสาร: https://github.com/HorstSpaceX/Documentation)
--
--   _G.Horst_SetDescription(ข้อความ, json)  = ข้อความบนรีจอย + ข้อมูลชีท
--
-- ⚠ ห้ามใช้ตัวอักษร | และ ; ในข้อความ (Horst ใช้เป็นตัวคั่นฟิลด์)
--   -> horstSend ตัดออกให้อัตโนมัติก่อนส่งเสมอ
--
-- ⚠⚠ ไม่มีการส่ง DONE เด็ดขาด
--   ไม่มี Horst_AccountChangeDone อยู่ในสคริปต์นี้เลยแม้แต่ครั้งเดียว
--   (ต่างจาก 99 Nights ที่ยิง DONE เมื่อถึงเป้าหมาย)
-- ══════════════════════════════════════════════════════════════════
HorstLog = { on = false, sent = 0, last = nil, err = nil }

--- ติดตั้ง on_loaded.lua + กรอง log ของมัน (ต้องเรียกก่อนงานอื่นทั้งหมด)
function horstInstall()
    if not cfgOn("Horst", CONFIG.Horst.Enabled) then return false end
    if HorstLog.on then return true end

    -- on_loaded.lua พิมพ์ "ส่งชีทสำเร็จ" ทุกครั้งที่อัปเดต (ทุก 30 วิตาม throttle)
    -- = สัญญาณว่าส่งถึงปลายทาง ไม่ต้องเห็นทุกครั้ง
    -- ต้องติดตั้งก่อนโหลด on_loaded.lua: โค้ดอาจจับค่า print ไปตั้งแต่ตอนโหลด
    local realPrint = print
    print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        local line = string.lower(table.concat(parts, " "))
        if line:find("sheet", 1, true)
            or line:find("sent description", 1, true)
            or line:find("sent done", 1, true) then
            return
        end
        realPrint(...)
    end

    local ls = loadstring or load
    local ok, err = pcall(function()
        ls(game:HttpGet(CONFIG.Horst.Source))()
    end)
    if not ok then
        HorstLog.err = tostring(err)
        print = realPrint
        logWarn("[Horst] โหลด on_loaded.lua ไม่สำเร็จ: " .. tostring(err))
        return false
    end
    HorstLog.on = true
    return true
end

--- กันยิงถี่: ผ่านได้ก็ต่อเมื่อพอเวลา MinInterval แล้ว (หรือบังคับ force)
function horstThrottle(force)
    if not cfgOn("Horst", CONFIG.Horst.Enabled) then return false end
    if type(_G.Horst_SetDescription) ~= "function" then return false end
    local gap = tonumber(CONFIG.Horst.MinInterval) or 30
    local now = os.clock()
    if force or (now - S.horstAt) >= gap then
        S.horstAt = now
        return true
    end
    return false
end

--- Description — เนื้อหาเดียวกับ UI สถิติ (เบ็ด / Aura / เกาะ / coin / gem)
--- ชื่อเบ็ดที่มี สำหรับ Description — ไม่ใช่แค่จำนวน
---   รวมเฉพาะ CONFIG.Horst.RodList ตัวแรก (เรียงตาม luck มาก->น้อย) ที่เหลือสรุปเป็น +N
function topRodNames(rows)
    local top = math.min(#rows, tonumber(CONFIG.Horst.RodList) or 3)
    local names = {}
    for i = 1, top do names[#names + 1] = tostring(rows[i].name) end
    if #rows > top then names[#names + 1] = ("+%d more"):format(#rows - top) end
    if #names == 0 then return "-" end
    return table.concat(names, ", ")
end

function horstDescription(data)
    local rods = rodRankList(data)
    local aura = auraHighList(data)
    local bits = {
        "🐟 Fishing Master",
        ("Coin: %s"):format(lowNum(data and data.Coin)),
        ("Gem: %s"):format(lowNum(data and data.Gem)),
        ("Island: %s"):format(topIslandName(data) or "-"),
        ("Rod: %s"):format(topRodNames(rods)),
        ("Aura: %d"):format(#aura),
    }
    local top = math.min(#aura, tonumber(CONFIG.Horst.AuraList) or 3)
    if top > 0 then
        local names = {}
        for i = 1, top do
            local o = aura[i]
            names[#names + 1] = ((o.count > 1) and ("x" .. tostring(o.count) .. " ") or "")
                .. tostring(o.name)
        end
        bits[#bits + 1] = "Top: " .. table.concat(names, ", ")
    end
    return table.concat(bits, " • ")
end

--- ข้อมูลชีท — คอลัมน์ย่อย ข้อความยาวไม่ยัด (ชื่อคอลัมน์ตั้งในบอร์ด Horst เอง)
function horstSheetJson(data)
    local rods = rodRankList(data)
    local packed = {
        Coin = math.floor(tonumber(data and data.Coin) or 0),
        Gem = math.floor(tonumber(data and data.Gem) or 0),
        Island = topIslandName(data) or "None",
        -- บอกชื่อเบ็ดจริง ไม่บอกจำนวน (ตามคำสั่ง) — ตัดเหลือ RodList ตัวแรก ที่เหลือเป็น +N
        Rods = topRodNames(rods),
        RodCount = #rods,
        Auras = #auraHighList(data),
    }
    local ok, json = pcall(function() return HttpService:JSONEncode(packed) end)
    return ok and json or nil
end

--- ส่งจริง (ตัด | และ ; ออกก่อนเสมอ)
function horstSend(data)
    local text = horstDescription(data)
    text = tostring(text):gsub("|", "/"):gsub(";", ",")
    local json = nil
    if CONFIG.Horst.SendSheet then json = horstSheetJson(data) end
    local ok, err = pcall(function() _G.Horst_SetDescription(text, json) end)
    if not ok then
        logWarn("[Horst] ส่งไม่สำเร็จ: " .. tostring(err))
        return false
    end
    HorstLog.sent = HorstLog.sent + 1
    HorstLog.last = text
    return true
end

--- จุดเรียกหลัก (ข้ามเงียบ ๆ ถ้ายังไม่ถึงเวลา)
function sendHorstDescription(force)
    if not horstThrottle(force) then return false end
    return horstSend(fetchData())
end

--- HEARTBEAT: กัน "ค่าล่าสุดหาย" — ค่าที่เปลี่ยนตอนที่ throttle ยังไม่คลาย
---   แล้วไม่มีอีกอีเวนต์ตามมา ข้อความนั้นจะไม่ถูกส่งเลย
function startHorstHeartbeat()
    if not cfgOn("Horst", CONFIG.Horst.Enabled) then return end
    task.spawn(function()
        while S.running do
            task.wait(tonumber(CONFIG.Horst.MinInterval) or 30)
            if not S.running then break end
            sendHorstDescription()
        end
    end)
end

local function mainLoop()
    local deferCheckAt = os.clock() + CONFIG.SkillSlotPoll
    local protectAt   = 0   -- ล็อกปลาของเควสต์ (1 วินาทีต่อรอบ ตอน Idling)
    local sellCheckAt = os.clock() + 5   -- เช็ค satchel เต็มทุก 5s (กัน spam)
    local auraAt      = os.clock() + CONFIG.Aura.Poll   -- เช็ค aura (สลับชิด/สุ่ม/ทิ้ง)
    local goalCheckAt = 0   -- 0 = เดินแผนในรอบ Idling ครั้งแรกเลย   -- เดินแผน (ซื้อเบ็ด/ปลดล็อก/ย้ายเกาะ)
    local farmCheckAt = os.clock() + CONFIG.FarmSpotPoll  -- เช็คว่ายังอยู่ที่จุดฟาร์มของเกาะปัจจุบัน
    local deathSeen = DEATH_STAMP  -- ตัวนับที่เห็นล่าสุด (ตัวตาย = เกมเปลี่ยน state เองโดยไม่ยิง packet)
    -- ⚠ เลขรอบ: retryBoot ตั้ง S.running=false แล้วรันใหม่ทันที ลูปเก่าอาจตื่นมาเจอ true อีกครั้ง
    --   เทียบเลขรอบแทน = ลูปเก่าเลิกแน่นอนเมื่อมีรอบใหม่
    local myRunGen = S.runGen
    while S.running and S.runGen == myRunGen do
        S.beat = S.beat + 1          -- watchdog ใช้ตัวนี้ว่าหลักเดินยังไหว
        -- ⚠ ตัวละครตาย/ถูกแทนที่: เกมเรียก ResetAll() ตั้ง state = "Idling" เองโดยไม่ยิง packet
        --   (FishingController.lua:1329-1339) ถ้าไม่ล้างตรงนี้ S.state จะค้าง "Reeling"
        --   แล้ว reelingLoop ยังยิง packet ทิ้งใส่ Idling ไปเรื่อยจนกว่าเซิร์ฟจะส่ง FishReset
        --   การล้างตรงนี้ = อ่านสถานะจริงใหม่ ข้ามการเดา และปล่อยให้ syncState() เติมค่า
        if DEATH_STAMP ~= deathSeen then
            deathSeen = DEATH_STAMP
            S.state = nil
            S.castAckDeadline = 0
            S.qteExpireAt = 0
            syncState()
            task.wait(0.1)
        end
        -- LOW MODE: รีเฟรชข้อความสถิติในแผง (ข้ามถ้าข้อมูลไม่เปลี่ยน)
        --   อยู่นอก if S.state ตั้งแต่ต้น เพราะหน้าจอดำต้องเห็นค่าตลอดเวลา ไม่ใช่ตอนว่างอย่างเดียว
        if CONFIG.LowMode.Enabled and Low.on and os.clock() >= S.statsAt then
            S.statsAt = os.clock() + (CONFIG.LowMode.Poll or 2)
            refreshStatsUi(fetchData())
        end
        -- ⚠ บรรทัดสรุป: ตอบได้ทันทีว่า "รอบนี้ตกปลาได้จริงไหม" (ผู้ใช้สั่ง 2026-10-16)
        if (CONFIG.Log or {}).Summary then
            S.summaryBeat = (S.summaryBeat or 0) + 1
            if S.summaryBeat >= ((CONFIG.Log or {}).SummaryEvery or 300) then
                S.summaryBeat = 0
                pcall(S.tools.summary)
            end
        end
        if S.state == "Idling" then
            -- sync state จริงจากเกมก่อน (เราเดาเองไม่ได้ server เป็นคนตัดสิน)
            -- ⚠️ ต้องใช้ผลของมันจริง ๆ: ถ้าเกมยังไม่ว่าง (รอปลา/กำลังเหวี่ยง/กำลังงัด/
            --    กำลังดึง/กำลังโชว์ผล) แล้วไปกดเหวี่ยงต่อ -> server ตอบ StateBusy
            --    = "Finish what you are doing first"
            syncState()
            if S.state ~= "Idling" then
                task.wait(0.1)
            else
                -- ⚠ บอสเกิด = ขัดทุกอย่าง ต้องมาก่อน ensureNotSwimming / aura / ขายปลา
                --   ที่ผ่านมาสคริปต์เช็คหลังอย่างอื่น ทำให้บอสถูกเลื่อนไปก่อน
                --   (ผู้ใชาสั่ง 2026-10-15) ย้ายมาที่นี่ = จุดแรกที่ตัวละครว่างจริง
                if os.clock() >= S.bossPollAt then
                    S.bossPollAt = os.clock() + CONFIG.Boss.Poll
                    bossTick()
                end
                -- ── RAID: เดินเครื่องวง raid ทุก phase ──────────────────
                --   ⚠ ระหว่าง raid ห้ามให้ boss/แผน/การขายปลาแทรก (จะหลุดวง)
                --   ใช้ os.clock() เป็นตัวจับรอบเหมือนจุดอื่น (ไม่ใช่ nowReal —
                --   ตัวนี้เป็นแค่ throttle ไม่ใช่ deadline)
                --   ⚠ ต้องเดินเครื่องแม้ปิด CONFIG.Forge — raid เป็นแหล่ง gems ของ
                --     "ปลดล็อก Lotus" ด้วย (S.raidActive คือหลักฐานว่ากำลังอยู่ในวง)
                if (CONFIG.Forge.Enabled or S.raidActive) and os.clock() >= (S.raidPollAt or 0) then
                    S.raidPollAt = os.clock() + 1
                    raidTick()
                end
                -- เกมบอกว่าว่างแล้ว แต่ถ้ามันคิดว่าเราว่ายน้ำอยู่ กดเหวี่ยงไม่ได้อยู่ดี
                -- (HookSwimming จะยิง FishCancel ทิ้ง session พอเริ่มว่าย)
                if not ensureNotSwimming() then
                    task.wait(0.2)
                else
                    -- re-check เบ็ดที่ติดตั้ง + ช่องสกิลที่ยังว่าง — ทำงานควบคู่กับตอนตกปลา
                    -- ⚠ ต้องเรียกทุกรอบ ไม่มีเงื่อนไข gate ที่ caller
                    --   เพราะทั้ง "เบ็ดที่ดีที่สุด" และ "ช่องว่าง" เปลี่ยนได้ตลอด
                    --   (ผู้ใช้สลับเบ็ดเอง / เบงดที่ดีกว่าเข้าคลัง / เลเวลเบ็ดเพิ่ม = ช่องปลดล็อกเพิ่ม)
                    --   ข้างในอ่านสถานะจริงทุกครั้ง แล้ว return ทันทีถ้าไม่ต้องทำอะไร
                    if os.clock() >= deferCheckAt then
                        deferCheckAt = os.clock() + CONFIG.SkillSlotPoll
                        ensureBestLoadout()
                    end
                    -- ล็อกปลาของเควสต์ทันทีที่จับได้ (ไม่รอให้กระเป๋าเต็ม)
                    -- ⚡ ถี่กว่า ensureBestLoadout เพราะรอบแรกที่กระเป๋าเต็มคือรอบที่ขายเลย
                    if os.clock() >= protectAt then
                        protectAt = os.clock() + 1
                        protectQuestFish()
                        forgeFishLock()     -- ล็อกปลาที่เบ็ด forge ต้องใช้ (ปลดล็อกไม่ทำเอง)
                    end
                    -- (เช็คบอสย้ายไปอยู่ต้นสาขานี้แล้ว — ก่อน ensureNotSwimming
                    --  เพื่อให้บอสมาก่อนทุกอย่างจริง ๆ ไม่ใช่หลังงานอื่นเสร็จ)

                    -- ── AURA: ใส่ตัวที่ดีที่สุด -> สุ่มถ้า gem พอ -> ทิ้งตัวแย่ ──
                    if CONFIG.Aura.Enabled and os.clock() >= auraAt then
                        auraAt = os.clock() + CONFIG.Aura.Poll
                        auraTick(fetchData(), "fishing", true)
                    end

                    -- ถ้า satchel เต็ม -> ไปขาย (tween กลับมาเอง)
                    if os.clock() >= sellCheckAt then
                        sellCheckAt = os.clock() + 5
                        local data = fetchData()
                        -- ⚠ ห้ามขายระหว่าง raid: การขายต้องเดินไป NPC = ออกจากวง raid
                        --   (satchel เต็มใน raid ไม่เป็นไร — เกมข้าม gate นี้ให้อยู่แล้ว)
                        if data and isSatchelFull(data) and not S.raidActive then
                            local hrpBefore = root()
                            local posBefore = hrpBefore and hrpBefore.Position
                            handleSatchelFull(data)
                            -- ⚠ ห้าม tween กลับตรง ๆ: house1StandPoint() คือพิกัดของเกาะ Starter เสมอ
                            --   ถ้าตอนนี้เรายืนคนละเกาะ มันจะวิ่งทะลุน้ำข้ามไปเรื่อย ๆ
                            --   goToFarmSpot() เช็คเกาะให้เอง (คนละเกาะ -> ว่ายไป NPC + ตั้งจุดเกิด)
                            --   และถ้ายืนใกล้จุดฟาร์มอยู่แล้วก็ไม่เดินใหม่
                            local hrpAfter = root()
                            if posBefore and hrpAfter and (hrpAfter.Position - posBefore).Magnitude > 2 then
                                -- ⚠ ต้องตั้งธงรอบนอกด้วย ไม่ใช่พึ่งธงข้างใน goToFarmSpot อย่างเดียว
                                --   ข้างในครอบแค่ travelToIsland / tweenDiveTo ส่วน fetchData +
                                --   activeFarmIsland + farmSpotFor + findNearestOpenWater อยู่นอกธง
                                if S.bossHolding then
                                    -- กำลังตีบอส: ขายเสร็จต้องกลับไปที่บอส ไม่ใช่ลากไปจุดฟาร์ม
                                    --   (log จริง: โดนลากออก 188 studs แล้วต้องรอรอบ drift ว่ายกลับ)
                                    pcall(goToBoss)
                                else
                                    S.moving = true
                                    goToFarmSpot()
                                    S.moving = false
                                end
                            end
                            task.wait(0.5)
                        end
                    end
                    -- ── เดินแผน (nextStep) ───────────────────────────────
                    -- วัตถุประสงค์เดียว: อ่านสถานะจริงจากเกม แล้วทำสิ่งที่ควรทำขั้นถัดไป
                    --   เงินพอ? อยู่เกาะไหน? มีเบ็ดดีที่สุดของเกาะนั้นหรือยัง? มีสกิลเป้าหมายหรือยัง?
                    -- ไม่มีการนับเวลาในการตัดสินใจ — ทุกอย่างอ่านจาก data ตอนนั้น
                    --
                    -- ⚠ ต้องวาง "หลัง" เช็ค satchel เต็ม: การขายปลาเป็นการออกจากจุด
                    --   และ nextStep อาจสั่ง respawn ซึ่งแทนตัวละคร — ทำสองอย่างพร้อมกันไม่ได้

                    -- ── 1) เช็คแผนก่อนเสมอ ──────────────────────────────
                    -- ⚠ ลำดับสำคัญ: goal ต้องมาก่อน farm เสมอ
                    --   ถ้าย้ายไปฟาร์มก่อน เราจะตัดสินใจย้ายตัวละครด้วยเงื่อนไขของรอบก่อนหน้า
                    --   แผนจึงต้อง "คิดก่อน" แล้วค่อยให้ฟาร์มเป็นตัวสำรองเมื่อแผนไม่มีอะไรให้ทำ
                    local acted, pending = false, false
                    -- ⚠ ตีบอสอยู่ = ห้ามเดินแผน (ซื้อ/สุ่ม/ข้ามเกาะ) จะดึงเราออกจากจุด
                    if not S.traveling and not S.moving and not S.bossHolding
                       and not S.raidActive
                       and os.clock() >= goalCheckAt then
                        goalCheckAt = os.clock() + CONFIG.GoalPoll
                        acted, pending = runStep()
                        if acted then
                            -- ทำงานเสร็จ -> รอให้ตัวละคร/สถานะนิ่งก่อนเหวี่ยงต่อ
                            task.wait(0.5)
                        end
                    end

                    -- ── 2) แผนไม่มีอะไรให้ทำ -> ค่อยกลับไปจุดฟาร์ม ──────────
                    -- pending = true คือยังมีงานค้าง (รวมถึงกำลังรอ retry) ห้ามย้าย
                    -- ⚠ ต้องผ่าน farmCheckAt เสมอ ไม่งั้นตอนที่ goToFarmSpot ล้มเหลว
                    --   (เช่น NPC ยังไม่โหลด) จะวนเรียกทุกรอบของ mainLoop
                    if not pending and not acted
                       and not S.traveling and not S.moving and not S.bossHolding
                       and not S.raidActive
                       and (os.clock() >= farmCheckAt or S.farmRecheck) then
                        S.farmRecheck = false
                        farmCheckAt = os.clock() + CONFIG.FarmSpotPoll
                        -- ⚠ ต้องตั้งธงรอบนอกด้วย ไม่ใช่พึ่งธงข้างใน goToFarmSpot อย่างเดียว
                        --   (หาพื้นที่ฟาร์ม = งานหนัก ดูเหตุผลข้างบน)
                        S.moving = true
                        goToFarmSpot()
                        S.moving = false
                        task.wait(0.3)
                    end

                    if acted or pending then
                        -- ⚠ แผนมีงานรอบนี้ = ห้ามเหวี่ยงทั้งรอบ
                        --   เดิมไหลลงมาเหวี่ยงต่อเสมอ แม้เพิ่งซื้อ/ปลดล็อกเสร็จ
                        --   ผลคือ "เดินแผนทีหลัง" แต่ของจริงคือฟาร์มไปตัวนึงก่อน
                        task.wait(0.3)
                    elseif os.clock() < S.castRetryAt then
                        task.wait(0.05)
                    -- ถือเบ็ดให้ถูกคันก่อนเหวี่ยง (ถ้ายังไม่ถูก -> รอแล้วลองใหม่รอบหน้า)
                    -- ⚠ ไม่ต้อง task.wait(0.4) + CastCooldown ต่อ: ensureRodEquipped
                    --   poll เองจนถือสำเร็จใน ~0.03s แล้ว (Select เป็นงาน client ล้วน)
                    --   ถ้ายังไม่สำเร็จ = ยังรอ server อยู่จริง ค่อยเสียเวลารอหน่อย
                    elseif not ensureRodEquipped() then
                        task.wait(0.15)
                    else
                        -- ไม่ต้องปลดอะไรก่อนเหวี่ยง: ไม่มี anchor เหลือในสคริปต์แล้ว
                        -- (ดู tombstone ของ Hold) — ตัวละครลอยนิ่งด้วย startAntiSink
                        -- และไม่มีอะไรดึงกลับไปสู้กับเซิร์ฟอีก
                        S.state = "Throwing"
                        S.castAckDeadline = os.clock() + (FishingConfig.Cast.AckTimeout or 8)
                        if not castToNearestWater() then
                            S.state = "Idling"
                            S.tools.onCastRefused()
                            task.wait(CONFIG.CastCooldown)
                        end
                        -- สำเร็จ -> ไม่ต้องรอ (state = Throwing อยู่แล้ว รอบถัดไปจะ poll เอง)
                        task.wait(CONFIG.RecastDelay)
                    end
                end
            end
        elseif S.state == "Throwing" then
            -- ตอนนี้เรา "คิด" ว่ากำลังเหวี่ยง แต่ต้องเชื่อ state จริงของเกมมากกว่า
            -- (เกมอาจ ResetAll เองเพราะ local gate ไม่ผ่าน / FishReset จาก server)
            -- ถ้าไม่ sync ตรงนี้ เราจะรอครบ 8s แล้วยิง FishCancel ทิ้งใส่ session ของรอบหน้า
            -- -> รอบถัดไปโดน SessionActive = "Finish what you are doing first"
            local fcNow = getFishingController()
            local gameState = nil
            if fcNow and fcNow.GetState then
                local ok2, st = pcall(function() return fcNow:GetState() end)
                if ok2 then gameState = st end
            end

            if gameState and gameState ~= "Throwing" and gameState ~= "Holding" then
                -- เกมไม่ได้อยู่ที่ Throwing ต่อไปแล้ว = cast ไม่ออก / ถูกปฏิเสธไปแล้ว
                S.state = gameState
                S.castAckDeadline = 0
            elseif S.castAckDeadline > 0 and os.clock() > S.castAckDeadline then
                -- ยิง FishCancel เฉพาะตอนเกมยัง "ค้าง" ที่ Throwing จริงๆ
                -- (ถ้าเกมไป state อื่นแล้ว การยิงตอนนี้คือไปตี session ของรอบหน้าแทน)
                if gameState == "Throwing" then
                    pcall(function() P.FishCancel:Fire() end)
                    -- ⚠ เซิร์ฟเงียบ (ไม่ตอบแม้แต่ FishReset) = นับเป็น "cast ไม่มีคำตอบ"
                    --   เหวี่ยงซ้ำที่เดิมไม่มีวันหาย (log จริง: 7 ครั้งติด ~85 วิ แล้วเกมดึงตัวกลับ
                    --   177 studs หลังจากนั้นเหวี่ยงได้ปกติ) -> พิมพ์ข้อมูลช่วยหาสาเหตุ แล้วย้ายตำแหน่งใหม่
                    S.ackMiss = (S.ackMiss or 0) + 1
                    pcall(function()
                        local h = root()
                        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
                        local sw = nil
                        local sc = Client and (Client.GetController("Swimming") or Client.GetController("SwimmingController"))
                        if sc and type(sc.IsSwimming) == "function" then sw = sc:IsSwimming() end
                        local pc = CastFail and CastFail.pending or {}
                        logWarn(("[Prog] CAST เงียบ #%d · hrp=%s · เกาะ=%s · humanoid=%s · ว่าย=%s · ระยะน้ำ=%s (bait %s..%s) · gravityForce=%s")
                            :format(S.ackMiss,
                                h and ("%d,%d,%d"):format(h.Position.X, h.Position.Y, h.Position.Z) or "nil",
                                tostring(currentIslandId()),
                                hum and tostring(hum:GetState()) or "nil",
                                tostring(sw), tostring(pc.dist), tostring(pc.baitMin), tostring(pc.baitMax),
                                tostring(S.grav ~= nil)))
                    end)
                    if S.ackMiss >= (CONFIG.AckMissLimit or 3) then
                        S.ackMiss = 0
                        logWarn("[Prog] CAST เงียบติดกันหลายครั้ง — ว่ายออกจากจุดแล้วกลับเข้าจุดฟาร์มใหม่ (ให้เซิร์ฟเห็นตำแหน่งสดอีกรอบ)")
                        S.moving = true
                        pcall(function()
                            local h = root()
                            S.tools.releasePin()
                            if h then tweenDiveTo(h.Position + Vector3.new(0, 0, -60), "relocate-away") end
                            goToFarmSpot()
                        end)
                        S.moving = false
                    end
                end
                S.state = "Idling"
                S.castAckDeadline = 0
            else
                task.wait(0.1)
            end
        elseif S.state == "Waiting" then
            S.ackMiss = 0     -- เซิร์ฟตอบ cast แล้ว = เลิกนับความเงียบ
            -- ก็ต้อง sync เหมือนกัน: ถ้าเกม cancel session เอง (ว่ายน้ำ/นั่ง/
            -- server ส่ง FishReset) เราต้องรู้ ไม่งั้นค้างที่ Waiting ไปเรื่อยๆ
            local fcW = getFishingController()
            local stW = nil
            if fcW and fcW.GetState then
                local ok3, st = pcall(function() return fcW:GetState() end)
                if ok3 then stW = st end
            end
            if stW and stW ~= "Waiting" then
                S.state = stW
                S.castAckDeadline = 0
            else
                task.wait(0.1)
            end
        elseif S.state == "Reeling" then
            reelingLoop()
        elseif S.state == "Caught" or S.state == "Escaped" then
            -- หน้าต่าง loot ไม่ถูกสร้างตั้งแต่ต้น (เราบังคับสาย "ไม่มี loot UI")
            -- เกมจะ auto-confirm -> FishLootConfirm -> ResetAll เอง -> sync state จริงกลับมา
            -- ยิงถี่ที่สุด = จับค่า Idling ได้เร็วที่สุดตอนมันเกิด (อย่าเดา ต้องอ่านจากเกมทุกครั้ง)
            task.wait(CONFIG.ResultPoll)
            syncState()
        else
            -- ⚠ เกมมี 8 สถานะ (FishingEnums.lua:2-10) แต่สาขาบนจัดการแค่ 6
            --   Holding / FirstPull ตกลงมาที่นี่ ถ้าไม่ sync state
            --   S.state จะถูกตรึงตลอด เพราะไม่มี packet ไหนมาแก้มัน -> บอทค้างถาวร
            --   สถานะที่ไม่รู้จัก = อ่านค่าจริงจากเกม เหมือนที่สาขา Throwing/Waiting ทำ
            syncState()
            task.wait(0.2)
        end
    end
end

local conns = {}
local function connect(name, fn)
    local pkt = P[name]
    if not pkt then logWarn(("[Prog] ไม่มี packet '%s'"):format(name)) return end
    table.insert(conns, pkt.OnClientEvent:Connect(fn))
end

local function subscribe()
    connect("FishWaitingAck", function()
        if S.state == "Throwing" then
            S.state = "Waiting"
            S.castAckDeadline = 0
            -- ⚠ เซิร์ฟรับแล้ว = หลักฐานว่า "ตกปลาจริง" 1 ครั้ง
            --   รอบก่อนไม่มีตัวนับนี้ = ล็อกบอกไม่ได้ว่าเหวี่ยงได้กี่ครั้ง
            S.casts = (S.casts or 0) + 1
            S.castRefused = 0
            -- ⚠ เซิร์ฟรับเหวี่ยงแล้ว = นับว่าตกผ่าน ล้างตัวนับความล้มเหลวของบอส
            --   ไม่งั้นจะสะสมจากรอบก่อน ๆ แล้วครั้งหน้าล้มครั้งเดียวก็ย้ายทันที
            S.bossFail = 0
        end
    end)
    -- งัดแรก: FishFirstPullStart มา = หลอดดาเมจขึ้นปุ๊บ = กดปุ๊บ ไม่สนว่าจะได้ x เท่าไหร่
    --   FishFirstPull ไม่มี payload เลย -> server วัดค่าเองตอน packet มาถึง
    --   ยิงตอนหลอดเพิ่งขึ้นจึงเป็นจังหวะที่เร็วที่สุด
    connect("FishFirstPullStart", function(fishId, hp, maxHP, timeLimit, serverTime, _dmg)
        S.state = "FirstPull"
        noteFightHP(hp, maxHP)   -- ⚠ เดิมรับมาแล้วทิ้งทั้งคู่ = ตัวชี้ว่าปลายังไม่โดนตีไม่ได้
        sendFirstPull()
    end)
    connect("FishFirstPullResult", function() end)
    -- ══ หัวใจการตก: HP สดจากเซิร์ฟ ══════════════════════════════════════
    --⚠ สองตัวนี้คือตัวเดียวที่บอกได้ว่า "ตกนานเพราะปลาดุ" ต่างจาก "ค้างจริง"
    --   ไม่ต่อไว้ = watchdog เห็นแต่ beat นิ่ง แยกสองเรื่องนี้ไม่ออกเลย
    connect("FishReelHPUpdate", function(hp, maxHP)
        noteFightHP(hp, maxHP)
    end)
    connect("FishReelPhaseHP", function(hp, maxHP)
        noteFightHP(hp, maxHP)   -- บอสเฟส 2 = HP เต็มชุดใหม่ (FishingController.lua:3045)
    end)
    connect("FishReelStartAck", function(fishId, hp, maxHP)
        S.state = "Reeling"
        noteFightHP(hp, maxHP)   -- ⚠ เดิมรับมาแล้วทิ้งทั้งคู่
        ReelSeq = 0
        -- ⚠ ล้างค่าคราวหน้าจากปลาตัวก่อน ไม่งั้นตอนเริ่มตกปลาใหม่
        --   reelingLoop จะเช็ค slotReadyAt เฟรมแรก = สกิลที่ "พร้อม" อยู่จริง
        --   จะถูกมองว่ายังคัสต์อยู่จากรอบก่อน แล้วข้ามสกิลไปทั้งช่วง
        --
        -- ⚠ แต่ห้ามล้าง "ทั้งตาราง" — เดิมทำแบบนั้น ซึ่งแปลว่าทุกรอบตกใหม่จะทิ้ง
        --   cooldown ที่ server เพิ่งส่งมาทิ้งด้วย แล้วยิงช่องเดิมซ้ำในเฟรมแรก
        --   ผลจาก skill_rate_test: ห่างจริง 6-7s = cooldown ของสกิลข้ามขอบเขตรอบตก
        --   ถ้าล้างทิ้ง = เสียสกิลรอบแรกของทุกครั้งที่ตกได้ปลา
        S.lastSkillAt = 0
        S.skillWindowUntil = 0
        clearClientSkillGuards()
    end)
    connect("FishSkillWindow", function(window)
        local w = tonumber(window) or 0
        if w > 0 then
            S.skillWindowUntil = math.max(S.skillWindowUntil, os.clock() + w)
        end
    end)
    -- ── QTE ────────────────────────────────────────────────────
    -- ⚠ FishQTEResult มี payload เดียว: correct (true/false) ไม่มีทาง/โอกาสแนบ
    --   = เดิมไม่นับอะไรเลย ทำให้บอกไม่ได้ว่าทำไมกด WASD แล้วไม่เข้า
    connect("FishQTEPrompt", function(direction, window)
        S.qtePrompt = S.qtePrompt + 1
        S.qteGen = S.qteGen + 1
        S.qteDir = direction
        S.qteExpireAt = os.clock() + (tonumber(window) or 1.25)
    end)
    connect("FishQTEResult", function(correct)
        S.qteDir, S.qteExpireAt = nil, 0
        S.qteGen = S.qteGen + 1
        if correct then S.qteHit = S.qteHit + 1 else S.qteMiss = S.qteMiss + 1 end
        local total = S.qteHit + S.qteMiss
        if CONFIG.QteLog and total > 0 and CONFIG.QteLogEvery > 0
           and total % CONFIG.QteLogEvery == 0 then
            local pct = (S.qteHit / total) * 100
            logWarn(("[QTE] สรุป %d ครั้ง — ถูก %d / ผิด %d (%.0f%%) · ส่งไป %d · ปิดทัน %d · ไม่มีปุ่ม %d")
                :format(total, S.qteHit, S.qteMiss, pct, S.qteSent, S.qteLate, S.qteNoKey))
        end
    end)
    connect("FishQTECancel", function()
        S.qteDir, S.qteExpireAt = nil, 0
        S.qteGen = S.qteGen + 1
    end)
    -- ── BOSS STUN ──────────────────────────────────────────────
    -- เกมใช้ u310 เป็นตัวห้ามกดตี (TrySendReelPull:1439 เช็ค v1 < u310)
    --   และ FishBossStun สั่งปิด prompt ทิ้งในตัว (u311 = false, u313 = nil)
    --   = ถ้าเราไม่มี handler นี้ เราจะยังถือ prompt ที่เกมทิ้งแล้ว
    --     แล้วยิง FishQTEResponse ใส่หน้าต่างที่ไม่มีอยู่ = เสียจังหวะฟรี + เสียดาเมจ
    connect("FishBossStun", function(duration)
        local d = tonumber(duration) or 0
        if d <= 0 then return end
        S.qteDir, S.qteExpireAt = nil, 0
        S.qteGen = S.qteGen + 1
        S.stunnedUntil = math.max(S.stunnedUntil or 0, os.clock() + d)
        if CONFIG.QteLog then
            logWarn(("[QTE] boss stun %.2fs — หยุดกดตีและทิ้ง prompt"):format(d))
        end
    end)
    connect("FishCatchResult", function(caught)
        clearFightHP()          -- รอบตกจบแล้ว = หัวใจต้องดับ ไม่งั้น watchdog เข้าใจผิด
        S.state = caught and "Caught" or "Escaped"
        -- ⚠ ตัวนับ + พิมพ์ตัวที่จับได้ (CONFIG.Log.Catch)
        --   รอบก่อนล็อกไม่มีตรงนี้เลย = พิสูจน์ไม่ได้ว่าตกปลาได้จริงไหม
        if caught then
            S.catches = (S.catches or 0) + 1
            S.tools.catch(fetchData())
        else
            S.escapes = (S.escapes or 0) + 1
        end
    end)
    connect("FishReset", function(reason)
        -- ⚠ บันทึกเหตุผลดิบก่อนเสมอ ทุกเหตุผล ไม่ใช่เฉพาะที่เราแสดง log
        --   นี่คือตัวเดียวที่บอกได้ว่า "Cast failed, please try again" มาจาก FailReason ไหน
        CastFail_note(reason)
        -- ── raid: ที่ยืนจับปลาไม่ได้ / ถูกจอง ───────────────────────────
        --   server ส่งมาเฉพาะ raid ("RaidSpotTaken" / "RaidNoSpot")
        --   -> ขยับไปจุดอื่นแล้วปล่อยให้ mainLoop เหวี่ยงใหม่
        --   ⚠ จำกัด 6 ครั้ง กันเดินวนไม่จบ (จุดเหวี่ยงถูกเลือกจาก raidCastTarget อยู่แล้ว)
        if S.raidActive and (reason == "RaidSpotTaken" or reason == "RaidNoSpot") then
            S.raidReloc = (S.raidReloc or 0) + 1
            local hrpR = root()
            if hrpR and S.raidReloc <= 6 then
                S.moving = true
                tweenDiveTo(hrpR.Position + Vector3.new(math.random(-30, 30), 0, math.random(-30, 30)), "raid-reloc")
                S.moving = false
            end
            logWarn(("[Raid] %s (ครั้งที่ %d) — ย้ายจุดเหวี่ยง"):format(tostring(reason), S.raidReloc))
        end
        -- ⚠ นับความล้มเหลวของการตกบอส (ผู้ใชาสั่ง 2026-10-15)
        --   ตั้งแต่ครบ FailToBackup ครั้ง -> ย้ายไปยืนพื้นดินรอบเขตแทน
        --   ⚠ นับเฉพาะตอนกำลังตีบอสอยู่ ไม่งั้น reset ตอนฟาร์มปกติจะทำให้ย้ายผิดที่
        if S.bossHolding and CAST_FAILED_REASONS[tostring(reason)] then
            S.bossFail = S.bossFail + 1
            if S.bossFail >= (CONFIG.Boss.FailToBackup or 3) then
                S.bossBackup = true
                S.bossFail = 0
            end
        end
        -- server สั่งรีเซ็ต = ปฏิเสธบางอย่างที่เราทำ
        --   SessionActive = "Finish what you are doing first" (ยังไม่ปิด session ทัน)
        --   CastCooldown  = "Casting too fast" (เหวี่ยงถี่เกิน)
        --   ทั้งคู่คือ "เร็วเกิน" -> หยุดก่อนลองใหม่ ไม่งั้นยิงรัวจนช้ากว่าเดิม
        if reason == "SessionActive" or reason == "CastCooldown" then
            S.castRetryAt = os.clock() + CONFIG.CastRetryDelay
        else
            logWarn(("[Prog] server reset: %s (เราอยู่ที่ %s)"):format(tostring(reason), tostring(S.state)))
        end
        -- เชื่อ state ของเกม ไม่ใช่เหตุผลของ FishReset:
        -- ทุกเส้นทางในเกมจบด้วย ResetAll() (ตอนนี้เกมจะกลับเป็น Idling เสมอ)
        S.castAckDeadline = 0
        clearFightHP()          -- server สั่งรีเซ็ต = รอบตกจบแล้วแน่นอน
        S.qteDir, S.qteExpireAt = nil, 0
        S.qteGen = S.qteGen + 1
        S.stunnedUntil = 0
        local fcR = getFishingController()
        local stR = nil
        if fcR and fcR.GetState then
            local ok4, st = pcall(function() return fcR:GetState() end)
            if ok4 then stR = st end
        end
        S.state = stR or "Idling"
    end)
end

-- ══════════════════════════════════════════════════
-- MISSION — ภารกิจที่ต้องไปทำที่เกาะอื่น (นับปลาเฉพาะชนิด ไม่ใช่แค่เก็บเงิน)
-- ══════════════════════════════════════════════════
-- ⚠ เกมไม่เก็บ "เกาะที่จับ" ไว้กับปลาเลย ตัวที่ว่า "จับที่ Desert" มาจากการจับคู่
--   fishId กับตาราง fishes ของเกาะใน Catalog.Island (QuestFishRules.qualifiesIsland:16-41)
--   และนับสด ๆ จาก Inventory.Fishes ทุกครั้งที่ถาม — ไม่มีตัวนับสะสมใน Progress
--   (ต่างจากเควสต์แบบนับสะสม เช่น crimson_bead_rod / zen_staff_rod ที่ใช้ Progress.CurrentFish)
--   ผลคือ "ขายไปแล้ว = ไม่นับ" และ "ล็อกไว้ = ไม่นับ" (QuestFishRules.SelectIsland:43-52)
--   -> ต้องเก็บปลาไว้ให้ครบ แล้วปลดล็อกตอนกด Complete
local FISH_ID_SETS = {}      -- islandId -> { [fishId] = true }
local RARITY_OF    = {}      -- fishId   -> rarity string

--- ชุด fishId ที่เกาะนี้มีให้จับ (แคชไว้ เพราะไม่เปลี่ยนตลอดเกม)
local function islandFishIds(islandId)
    local set = FISH_ID_SETS[islandId]
    if set then return set end
    set = {}
    local meta = nil
    if Catalog and Catalog.Island and Catalog.Island.GetById then
        pcall(function() meta = Catalog.Island.GetById(islandId) end)
    end
    for _, e in ipairs((type(meta) == "table" and meta.fishes) or {}) do
        if type(e) == "table" and type(e.fishId) == "string" then set[e.fishId] = true end
    end
    FISH_ID_SETS[islandId] = set
    return set
end

--- rarity ของปลา (เกมไม่เก็บไว้กับตัวปลา — ต้อง resolve จาก Catalog ทุกครั้ง)
local function fishRarity(fishId)
    local r = RARITY_OF[fishId]
    if r ~= nil then return r end
    local meta = nil
    if Catalog and Catalog.Fish and Catalog.Fish.GetById then
        pcall(function() meta = Catalog.Fish.GetById(fishId) end)
    end
    r = (type(meta) == "table" and type(meta.rarity) == "string") and meta.rarity or ""
    RARITY_OF[fishId] = r
    return r
end

--- ภารกิงนี้เสร็จไปแล้วหรือยัง
---   kind = "rod"   -> มีเบ็ดในคลัง หรือเกมบันทึกว่าเควสต์นั้น Done แล้ว
---   kind = island  -> เกาะเป้าหมายถูกปลดแล้ว
--- ⚠ ต้องเช็คทั้งสองทาง ไม่ใช่อันเดียว: server อาจให้เบ็ดมาแล้วแต่ data.Rods ยังไม่ replicate
---   (หรือกลับกัน) การรออย่างเดียวทำให้สคริปต์ค้างหรือทำงานซ้ำ
local function missionDone(data, m)
    if not (data and m) then return true end
    if m.kind == "rod" then
        if ownsRod(data, m.targetRod) then return true end
        local done = data.Quest and data.Quest.Done
        return type(done) == "table" and done[m.targetRod] == true
    end
    return islandUnlocked(data, m.targetIsland)
end

--- ภารกิจแรกที่ยังไม่เสร็จ (ไม่มี = ไม่มีแผนอะไรต้องทำแล้ว)
--- ⚠ เกาะที่นับปลาของเควสต์ = farmIsland ของภารกิจ (สำหรับภารกิจนี้คือ Desert)
local function activeMission(data)
    if not data then return nil end
    for _, m in ipairs(CONFIG.Missions or {}) do
        if not missionDone(data, m) then return m end
    end
    return nil
end

--- เกาะที่ปลดแล้วและ order สูงสุด ณ ตอนนี้ (อ่านจาก Catalog ไม่ hardcode)
--- = เกาะที่ควรฟาร์มเสมอ เพราะทุกอย่างที่ทำได้ (ยิง packet ซื้อเบ็ด/ปลดเกาะ/สุ่มสกิล)
---   ไม่มีเงื่อนไขระยะ — คนขายปลาก็ยิงจากห่างได้ เกมไม่ได้เช็กว่าอยู่เกาะไหน
---   เหลือแค่ "จะขายที่ไหน" ซึ่ง handleSatchelFull ใช้ currentIslandId() อยู่แล้ว
local function highestUnlockedIsland(data)
    if not data then return nil end
    local best
    for _, entry in ipairs(islandChain()) do
        if islandUnlocked(data, entry.id) then best = entry.id end
    end
    return best
end

--- เกาะที่ควรฟาร์มตอนนี้
---   1) ภารกิจที่ยังไม่เสร็จ -> ไปที่ farmIsland ของมัน (ต้องตกปลาให้ตรงชนิด)
---   2) ไม่มีภารกิจ        -> เกาะที่ปลดสูงสุด ณ ตอนนั้น (ขายที่เกาะนั้นด้วย)
---   3) อ่านข้อมูลไม่ได้     -> CONFIG.FarmIsland (กันพลัง)
function activeFarmIsland(data)
    local m = activeMission(data)
    -- ── เกาะ 7 (Lotus): เกาะฟาร์มขึ้นกับสเต็ป ─────────────────────────
    --   Step 2 = ต้องตกที่ Volcanic จน Magma Essence ครบ (ดรอปฝั่งเซิร์ฟตาม rarity)
    --   Step 1 (รอฝน) / Step 3 (หาเงิน) = เกาะที่ปลดสูงสุด (Fossil)
    --     ⚠ Fossil เป็นเกาะของปลา Mythical ที่ dread_fish_rod ต้องใช้พอดี
    --       = เงิน + ปลา dread เก็บไปพร้อมกับเควสต์ Lotus ได้เอง
    --   ⚠ ต้องอยู่ก่อน branch ด้านล่าง: m.farmIsland = volcano จะถูกใช้ทั้ง 3 สเต็ป
    --     ถ้าไม่แยก บอทจะไปนั่ง Volcanic ตอน Step 1/3 ที่ควรหาเงินที่ Fossil
    --   ⚠ ระหว่าง detour เดลี่ (ยกเลิก Lotus ชั่วคราว) ต้องไม่เข้ากิ่งนี้
    --     ไม่งั้นจะไม่มีทางไปเกาะของเดลี่เลย (กิ่งนี้ + m.farmIsland return ก่อนเสมอ)
    --     ⚠ activeMission ยังคืนภารกิจ lotus อยู่แม้ยกเลิกไปแล้ว (missionDone ดูแค่เกาะ)
    --       -> ต้องใช้ S.lotusDetour เป็นตัวตัดสิน ไม่ใช่ Quest.Current
    local lotusMission = (m ~= nil and m.kind == "lotus")
    local lotusDetouring = lotusMission and S.lotusDetour == "daily"
    if lotusMission and not lotusDetouring then
        if lotusStepOf(data) == 2
           and itemCount(data, "magma_essence") < lotusNeed("EssenceCount", 10) then
            return "island_volcano"
        end
        -- Step 3 + gems ยังไม่ครบ = ต้องหา gems: ถ้าจะแลกตั๋ว raid ต้องมีปลา Legendary
        --   ครบ 8 ตัวก่อน -> ไปเกาะที่ยังขาด (ผู้ใช้สั่ง 2026-10-24)
        --   ⚠ ระหว่าง raid ต้องไม่ย้ายเกาะ (จะหลุดวง)
        if lotusGemPhase(data) and not S.raidActive and RaidCfg and raidWanted(data)
           and itemCount(data, RaidCfg.TicketId or "raid_ticket") < 1 then
            local short = raidTicketShort(data)
            if short and islandUnlocked(data, short) then return short end
        end
        return highestUnlockedIsland(data) or "island_fossil"
    end
    -- ── สาย Forge (Godslayer Rod V2): ไปเกาะที่ "ของที่ขาด" อยู่ ─────────
    --   ⚠ ต้องอยู่ก่อน branch ของ mission แต่ gate ด้วย activeMission == nil
    --     เพื่อไม่แย่งเงิน 10M ของ dread_fish_rod ที่ยังค้างอยู่
    --   ⚠ ระหว่าง raid ห้ามย้ายเกาะ (จะหลุดวง) — raidTick/raidMoveToIsland ดูแลเอง
    --   ⚠ กิ่ง Lotus ด้านบนจัดการช่วงหา gems ปลดเกาะไปแล้ว (m ~= nil) — ที่นี่คือหลังปลดเกาะ
    if CONFIG.Forge.Enabled and islandUnlocked(data, CONFIG.Forge.AfterIsland)
       and m == nil and not S.raidActive and RodForgeCfg and RodForgeRules then
        local fr = forgeRodId(data)
        if fr then
            local recipe = RodForgeCfg.Recipes[fr]
            local st = RodForgeRules.GetStatus(data, fr)
            if recipe and st and (st.fishCount or 0) < (recipe.fishCount or 0) then
                local k = recipe.fishKind
                if k == "Island7Legendary" then return "island_lotus" end
                if k == "Islands23Legendary" then
                    -- ต้อง jungle 3 + desert 3 — เลือกเกาะที่ยังขาดก่อน
                    local jSet, dSet = islandFishIds("island_jungle"), islandFishIds("island_desert")
                    local jungle, desert = 0, 0
                    for _, f in pairs((invOf(data) or {}).Fishes or {}) do
                        if type(f) == "table" and f.locked ~= true and fishRarity(f.fishId) == "Legendary" then
                            if jSet[f.fishId] then jungle = jungle + 1
                            elseif dSet[f.fishId] then desert = desert + 1 end
                        end
                    end
                    local half = math.floor((tonumber(recipe.fishCount) or 0) / 2)
                    if jungle < half then return "island_jungle" end
                    if desert < half then return "island_desert" end
                end
                -- Rarities / Boss = เกาะสูงสุด (Lotus) ตามปกติ
            end
            -- ต้องแลกตั๋ว raid -> ไปเกาะที่ยังขาดปลา Legendary
            if RaidCfg and raidWanted(data)
               and itemCount(data, RaidCfg.TicketId or "raid_ticket") < 1 then
                local short = raidTicketShort(data)
                if short and islandUnlocked(data, short) then return short end
            end
        end
    end

    if m and m.farmIsland and islandUnlocked(data, m.farmIsland) and not lotusDetouring then
        -- ⚠ เช็คว่า "ของที่ต้องเก็บ" ครบแล้วหรือยัง ก่อนตัดสินว่าจะอยู่ที่ farmIsland
        --   ถ้าครบแล้ว = เหลือแค่เงิน ให้ไปหาเงินที่เกาะที่ปลดสูงสุดแทน
        --   (bamboo_rod: ได้ fragment ครบ 20 ต้องกลับไปฟาร์ม Volcanic ไม่ใช่วนที่ Jungle)
        local ok, req = missionCollect(data, m)
        if req and ok then
            local cost = missionCoin(data, m)
            if type(cost) ~= "number" or numOr(data.Coin, 0) < cost then
                return highestUnlockedIsland(data) or m.farmIsland
            end
        end
        return m.farmIsland
    end

    -- ── DAILY QUEST: เกาะที่จะตกถูกสุ่มมาตอนกดรับ ไม่ใช่ตอนยืนอยู่ ──────
    --   DailyQuestUtil.PickIsland สุ่มจากทุกเกาะที่ปลดแล้ว (70% สูงสุด / 30% รองสูงสุด)
    --   แล้วเขียนลง Active.IslandId -> ต้องไปตกที่นั้น ไม่ใช่เกาะสูงสุดเสมอ
    -- ⚠ เควสต์ skill_gacha ไม่ต้องไปตกที่ไหน (นับจากจำนวนครั้งที่กดสุ่ม)
    if CONFIG.Daily.Enabled then
        local a = dqActive(data)
        if a and not dqIsGacha(a)
           and (a.Progress or 0) < (a.Target or 0)
           and type(a.IslandId) == "string" and a.IslandId ~= ""
           and islandUnlocked(data, a.IslandId) then
            return a.IslandId
        end
    end

    return highestUnlockedIsland(data) or CONFIG.FarmIsland
end

--- จุดยืนตกปลาของเกาะ
---   CONFIG.FarmSpots -> House1 (Starter) -> จุดเกิดของเกาะนั้น -> nil
--- ⚠ จุดเกิดเป็นทางเลือกสุดท้าย ไม่ได้การันตีว่ามีน้ำข้างๆ
---   เตือนครั้งเดียวต่อเกาะให้ผู้ใช้ไปประกาศ CONFIG.FarmSpots เอง
local function farmSpotFor(islandId)
    local v = (CONFIG.FarmSpots or {})[islandId]
    if v then return v end
    if islandId == "island_starter" then return house1StandPoint() end
    local spawn = islandLandingSpot(islandId)
    if spawn and not S.warnedNoSpot[islandId] then
        S.warnedNoSpot[islandId] = true
        logWarn(("[Prog] เกาะ %s ยังไม่ได้ประกาศ CONFIG.FarmSpots — ใช้จุดเกิดของเกาะแทน "
            .. "ถ้าตกปลาไม่ได้ให้ใส่พิกัดจุดที่มีน้ำลงใน FarmSpots")
            :format(islandTag(islandId)))
    end
    return spawn
end


--- พิมพ์ตัวที่เพิ่งเข้ากระเป๋า (อ่านจาก Inventory.Fishes ตรง ๆ ไม่เดา)
---   uid ในกระเป๋าที่ยังไม่เคยพิมพ์ = ตัวใหม่ (เกมบอก ไม่ใช่เรานับเอง)
function S.tools.catch(data)
    if not ((CONFIG.Log or {}).Catch) then return end
    local inv = (type(data) == "table" and type(data.Inventory) == "table") and data.Inventory or nil
    local fishes = inv and inv.Fishes or nil
    if type(fishes) ~= "table" then return end

    local seen = S.catchSeen or {}
    local n, fresh = 0, {}
    for key, f in pairs(fishes) do
        n = n + 1
        local id = tostring(key)
        if (not seen[id]) and type(f) == "table" then
            seen[id] = true
            fresh[#fresh + 1] = f
        end
    end
    -- ⚠ กระเป๋าถูกขาย/ล้าง = uid เก่าไม่มีแล้ว = เคลียร์ทิ้ง ไม่ให้ตารางโตไม่จำกัด
    if n < (S.catchSeenCount or 0) then
        seen = {}
        for key in pairs(fishes) do seen[tostring(key)] = true end
    end
    S.catchSeen, S.catchSeenCount = seen, n

    table.sort(fresh, function(x, y) return tostring(x.fishId) < tostring(y.fishId) end)
    for _, f in ipairs(fresh) do
        logWarn(("[Prog] 🎣 ได้ %s (%s) %.1f kg%s")
            :format(tostring(f.fishId), tostring(fishRarity(f.fishId)),
                tonumber(f.weight) or -1,
                (f.locked == true) and " · ล็อคไว้ทำเควสต์" or ""))
    end
end

--- บรรทัดสรุปรอบเวลา — ทุกอย่างในบรรทัดนี้อ่านจากข้อมูลเกมตอนนั้น
---   (เวลารันมาจาก nowReal = เวลาเซิร์ฟ ไม่ใช่นาฬิกาที่เราตั้งเอง)
function S.tools.summary()
    local data = fetchData()
    local hrp  = root()
    local isle = "?"
    if data then
        local okI, v = pcall(currentIslandId)
        if okI and v then isle = tostring(v) end
    end
    local extra = ""
    if data and hrp then
        local tgt = nil
        local okT, v = pcall(activeFarmIsland, data)
        if okT then tgt = v end
        if tgt then
            local okS, sp = pcall(farmSpotFor, tgt)
            if okS and sp then
                extra = (" · ห่างจุดฟาร์ม %.1f"):format((hrp.Position - sp).Magnitude)
            end
        end
    end
    -- · บอก state จริงของ state machine ทุกบรรทัดสรุป:
    --   ทั้ง 3 ทางที่รอไม่มี timeout (ไม่มีน้ำให้เหวี่ยง / Waiting / Caught)
    --   พิมพ์ออกมาเหมือนกันหมด = ผู้ใช้เห็นแค่ตัวเลขค้าง เดาไม่ได้ว่าค้างตรงไหน
    --   · อ่านจาก S.state = ค่าที่ syncState() เอามาจากเกม ไม่ใช่นับเวลาเอง
    extra = extra .. " · state=" .. tostring(S.state or "?")
    logWarn(("[Prog] สรุป: รัน %.0f นาที · เหวี่ยง %d · ได้ %d · หลุด %d · สกิลล้มเหลว %d"
            .. " · เบ็ด %s · เงิน %s · %s%s")
        :format(((nowReal() - PROG_STARTED_AT) / 60),
            S.casts or 0, S.catches or 0, S.escapes or 0, S.skillFail or 0,
            tostring(data and data.RodEquip or "?"),
            tostring(data and data.Coin or "?"), isle, extra))
end

--- น้ำหนักขั้นต่ำของปลาแต่ละชนิด อ่านสดจากเกมก่อน (QuestConfig[cfgKey])
---   ค่านี้เป็นค่าคงที่ของเกม ไม่ใช่ Progress — อ่านได้เลยแม้ยังไม่ได้รับเควสต์
---   ถ้าอ่านไม่ได้ (เกมอัปเดต/โมดูลหาย) -> คืน nil ให้ผู้เรียก fallback ไปใช้ค่าใน CONFIG.Missions
---
--- ⚠ ต้องส่ง key มาเสมอ ห้าม default ไปที่ key ของเควสต์อื่น
---   เควสต์ที่ไม่มีเงื่อนไขน้ำหนัก (unlock_island_5) ถ้าไปใช้ตารางของ island 6
---   จะตัดปลาที่หนักเกินจริงทิ้งทั้งที่เกมนับอยู่ = เควสต์ค้างถาวร
local function minWeightsFromConfig(cfgKey)
    if type(cfgKey) ~= "string" then return nil end
    local v = type(QuestConfig) == "table" and QuestConfig[cfgKey] or nil
    if type(v) ~= "table" then return nil end
    local out, n = {}, 0
    for fishId, kg in pairs(v) do
        if type(fishId) == "string" and type(kg) == "number" then
            out[fishId] = kg
            n = n + 1
        end
    end
    if n > 0 then return out end
    return nil
end

--- คืน mission, รายการปลาที่ตรงเงื่อนไขของภารกิจ (ทุกตัว ไม่สนว่าล็อกหรือไม่)
--- รองรับ 4 โหมด: named / rarity / counter / item
local function missionRequirement(data, m)
    if not m then return nil end

    -- Progress ของเควสต์ที่กำลังทำอยู่ = ค่าจริงจาก server (สูงกว่า CONFIG เสมอ)
    local prog = nil
    if data then
        -- ⚠ อ่าน Progress ได้ก็ต่อเมื่อเควสต์ที่กำลังทำอยู่คือเควสต์ของภารกิจนี้จริงๆ
        --   ตอนที่เควสต์อื่น (เช่น unlock_island_5) เป็นตัวที่ทำอยู่ ตาราง RequiredFishes
        --   ใน Progress จะเป็นสายปลาของเควสต์นั้น ไม่ใช่ของ m
        --   ถ้าไม่เช็ค -> protectQuestFish จะไปล็อคปลาผิดชนิด แล้วกดสวิตช์ซ้ำจนปลดออก
        local cur = data.Quest and data.Quest.Current
        if type(cur) == "table" and cur.Id == questIdOf(m)
           and type(cur.Progress) == "table" then
            prog = cur.Progress
        end
    end

    local function toNamed(src, minW)
        if type(src) ~= "table" then return nil end
        local ids, total = {}, 0
        for fishId, n in pairs(src) do
            if type(fishId) == "string" and type(n) == "number" and n > 0 then
                ids[fishId] = n
                total = total + n
            end
        end
        if total == 0 then return nil end
        return { mode = "named", ids = ids, count = total, total = total, minWeight = minW }
    end

    -- ── เควสต์เบ็ด: อ่านตาม "need" ที่ประกาศใน CONFIG.Missions ──
    local nd = m.need
    if type(nd) == "table" then
        if nd.mode == "counter" then
            -- ตัวนับสะสมที่ server นับให้ (เช่น CurrentFished ตอนจับด้วย Legacy Rod)
            --   ไม่ใช่การสแกนกระเป๋า -> ไม่ต้องล็อคปลาอะไรเลย
            local need = (prog and tonumber(prog[nd.need])) or nd.fallback or 0
            local got  = (prog and tonumber(prog[nd.have])) or 0
            return { mode = "counter", got = got, count = need, total = need }
        end
        if nd.mode == "item" then
            -- นับไอเทมในกระเป๋า (bamboo_fragment) — ไม่ใช่ปลา = SellAll ไม่กิน
            local need = (prog and tonumber(prog.RequiredBamboo)) or nd.count or 0
            return { mode = "item", itemId = nd.itemId, count = need, total = need,
                     got = itemCount(data, nd.itemId) }
        end
        if nd.mode == "rarity" then
            -- สแกนกระเป๋าตามชั้นหายากของเกาะที่ระบุ (dread_fish_rod = Mythical ของ Fossil)
            --   islandId สำคัญ: ต้องเป็นเกาะของเควสต์ ไม่ใช่เกาะที่กำลังฟาร์มอยู่
            -- ⚠ dread_fish_rod ใช้ Progress.RequiredFish เป็น "ตัวเลข" ไม่ใช่ตารางชื่อปลา
            --   (Requirements/dread_fish_rod.lua:51-53) -> อ่านสดได้เหมือนกัน
            local need = (prog and tonumber(prog.RequiredFish)) or nd.count or 1
            return { mode = "rarity", rarity = nd.rarity, count = need,
                     islandId = nd.islandId or m.farmIsland, total = need }
        end
    end

    -- ── เควสต์ปลดเกาะ ──
    local nf = m.needFish
    if type(nf) ~= "table" then return nil end

    -- ⚠ ตารางน้ำหนักขั้นต่ำต้องมาจาก key ที่ประกาศไว้ของเควสต์นี้เท่านั้น
    --   ไม่มี key = เควสต์นี้ไม่มีเงื่อนไขน้ำหนัก = นับทุกตัวที่ชื่อตรง
    -- ⚠ ลำดับสำคัญ: ค่าสดจากเกมมาก่อน แล้วค่าในไฟล์นี้เป็นแค่ fallback
    --   ถ้าสลับลำดับ needFish.minWeight จะบังค่าจากเกมทิ้งเสมอ = dead code
    local mw = minWeightsFromConfig(nf.minWeightFromConfig) or nf.minWeight

    -- 1) quest that is CURRENTLY active -> read Progress straight from the game
    if prog and prog.RequiredFishes ~= nil then
        local named = toNamed(prog.RequiredFishes, mw)
        if named then return named end
    end

    -- 2) not accepted yet -> fall back to CONFIG.Missions
    local named = toNamed(nf.ids, mw)
    if named then return named end
    if type(nf.rarity) == "string" then
        return { mode = "rarity", rarity = nf.rarity, count = nf.count or 1,
                 islandId = m.farmIsland, total = nf.count or 1 }
    end
    return nil
end

--- เงินที่เควสต์นี้ต้องใช้ — อ่านสดจาก Progress.RequiredCoin ก่อน ไม่งั้นใช้ m.coin
function missionCoin(data, m)
    -- ⚠ เช็คด้วยว่าเควสต์ที่กำลังทำอยู่คือเควสต์ของ m ด้วย ไม่ใช่แค่ "มีเควสต์อยู่"
    --   เควสต์ทุกใบมี field RequiredCoin ของตัวเอง ถ้าอ่านของเควสต์อื่น
    --   เงินที่ใช้จะเป็นยอดของเควสต์นั้น (เช่น 15,000,000 มากกว่า 3,600,000)
    local cur = data and data.Quest and data.Quest.Current
    if type(cur) == "table" and cur.Id == questIdOf(m) then
        local prog = cur.Progress
        local v = type(prog) == "table" and tonumber(prog.RequiredCoin)
        if v then return v end
    end
    local n = tonumber(m and m.coin)
    return n
end

-- krab conditional-ready helper: mode "named" counts PER FISH ID, not the total
local function missionFishReady(list, req)
    if not req then return false end
    if req.mode == "named" then
        local byId = {}
        for _, f in ipairs(list) do byId[f.fishId] = (byId[f.fishId] or 0) + 1 end
        for fishId, n in pairs(req.ids) do
            if (byId[fishId] or 0) < n then return false end
        end
        return true
    end
    return #list >= (req.count or 0)
end

-- human-readable requirement, for the action label
local function missionFishLabel(req, got)
    if req.mode == "named" then
        local t = {}
        for fishId, n in pairs(req.ids) do
            local mw = req.minWeight and req.minWeight[fishId]
            t[#t + 1] = ("%s x%d%s"):format(fishId, n, mw and (" >=" .. tostring(mw) .. "kg") or "")
        end
        table.sort(t)
        return table.concat(t, ", ")
    end
    if req.mode == "counter" then
        return ("จับด้วยเบ็ด %d/%d"):format(req.got or 0, req.count or 0)
    end
    if req.mode == "item" then
        return ("%s %d/%d"):format(tostring(req.itemId), req.got or 0, req.count or 0)
    end
    return ("%s x%d"):format(tostring(req.rarity), got or 0)
end

--- ปลาของภารกิงที่ "ตรงเงื่อนไข" ทุกตัวในกระเป๋า (ทั้งล็อกและไม่ล็อก)
---   m = ภารกิจ, list = ปลาที่ผ่าน, req = โครงเงื่อนไข
---   ถ้า m == nil -> คืน nil (ไม่มีภารกิงที่ต้องเก็บปลา)
local function missionFish(data, m)
    m = m or activeMission(data)
    local req = missionRequirement(data, m)
    if not (m and req) then return nil, nil, nil end
    if req.mode ~= "named" and req.mode ~= "rarity" then
        return m, nil, req       -- โหมด counter/item ไม่เกี่ยวกับปลา
    end
    local inv = invOf(data)
    local fishes = inv and inv.Fishes
    local out = {}
    if type(fishes) ~= "table" then return m, out, req end

    local set = (req.mode == "rarity") and islandFishIds(req.islandId or m.farmIsland) or nil
    for _, f in pairs(fishes) do
        if type(f) == "table" then
            local hit
            if set then
                hit = set[f.fishId] ~= nil and fishRarity(f.fishId) == req.rarity
            else
                hit = req.ids[f.fishId] ~= nil
            end
            -- ⚠ น้ำหนักขั้นต่ำ (unlock_island_6) — ปลาที่ไม่ถึง "ไม่นับ"
            --   และตาม QuestFishRules.SelectNamed:92-101 ก็ "ไม่กินโควตา" ของชนิดนั้น
            --   = ถ้าไม่กรองตรงนี้ เราจะล็อคปลา 900kg กินโควตาที่ 1
            --     แล้วไม่ล็อคตัว 1,200kg ที่จับมาทีหลัง -> เควสต์ติดขัดถาวร
            local mw = req.minWeight and req.minWeight[f.fishId]
            if hit and mw then
                hit = (type(f.weight) == "number") and (f.weight >= mw)
            end
            if hit then out[#out + 1] = f end
        end
    end
    return m, out, req
end

--- ของที่ต้อง "เก็บ" ของภารกิงครบแล้วหรือยัง (ไม่รวมเงิน)
---   คืน collectDone, req, list — list มีค่าเฉพาะโหมด named/rarity (ต้องเอาไปล็อค/ปลดล็อก)
--- ⚠ เขียนเป็น "function" ไม่ใช่ "local function" เพราะ activeFarmIsland เรียกก่อนถึงบรรทัดนี้
function missionCollect(data, m)
    local req = missionRequirement(data, m)
    if not req then return false, nil, nil end
    if req.mode == "counter" then return (req.got or 0) >= (req.count or 0), req, nil end
    if req.mode == "item" then return (req.got or 0) >= (req.count or 0), req, nil end
    local _, list = missionFish(data, m)
    if not list then return false, req, nil end
    return missionFishReady(list, req), req, list
end

--- มูลค่าขายโดยประมาณของปลาตัวในกระเป๋า — ใช้สูตรของเกมเอง ไม่เดาราคา
---   Catalog.GetValue(fishId, weight) = max(floorValue, averageValue / avg^2 * weight^2)
---   (Data/Catalog/Catalog.lua:29-36)
---
--- ⚠ ในกระเป๋าไม่มี field ราคาให้อ่าน: MigrationSteps.lua:95 เขียนว่า
---   "Stamp sell value and lock flag on owned fish" = server คำนวณแล้ว stamp ตอนจับ
---   และไม่มีโค้ด client ในดัมป์ที่ไหนอ่าน field นั้นเลย -> คำนวณกลับจาก Catalogแทน
---   (สูตรเดียวกัน ต่างแค่ไม่ได้ math.round เพราะเราใช้แค่เทียบ "ตัวไหนแพงกว่า")
---
---   คืน math.huge ถ้าอ่านไม่ได้ = ให้จัดเป็นตัวแพงที่สุด ไปรอท้ายสุดตอนเรียง
---   (ปลอดภัย เพราะโควตาที่ล็อกได้คือ N ตัวแรกที่เรียงได้ ไม่ใช่ "ตัวที่รู้ราคาเท่านั้น")
local function fishWorth(f, exact)
    local w = tonumber(f and f.weight)
    if not w then return math.huge end
    local meta = nil
    if Catalog and Catalog.Fish and Catalog.Fish.GetById then
        pcall(function() meta = Catalog.Fish.GetById(f.fishId) end)
    end
    if type(meta) ~= "table" or type(meta.averageValue) ~= "number" then return math.huge end
    local avg = (type(meta.weight) == "table") and tonumber(meta.weight.avg) or nil
    if not avg or avg <= 0 then return math.huge end
    local v = meta.averageValue / (avg * avg) * w * w
    -- exact = true คืนค่าตรงกับ Catalog.GetValue ทุกหลัก (มี math.round)
    --   ใช้ตอน "รวมราคาทั้งกระเป๋า" เพราะถ้าขาดไปแค่ 1 coin ต่อตัว
    --   ก็พอจะพลิกคำตัดสินจาก "พอ" เป็น "ไม่พอ" แล้ววิ่งไปขายเปล่า ๆ
    --   ไม่ใช้ exact = เดิม ไม่ round (เรียงล็อกปลาเควสต์ ต่างกันไม่เกิน 1 ต่อตัว)
    return math.max(meta.floorValue or 0, exact and math.round(v) or v)
end

-- ══════════════════════════════════════════════════
-- มูลค่าปลาในกระเป๋า — รู้ว่า "ขายได้เท่าไหร่" ก่อนตัดสินใจวิ่งไปขาย
-- ──────────────────────────────────────────────────
--- คืน coins, count, unknown, huge
---   coins   = เงินที่จะได้จากการขาย (คำนวณด้วยสูตรของเกมเอง = fishWorth exact)
---   count   = จำนวนตัวที่ขายได้
---   unknown = true เมื่อมีตัวที่อ่านราคาไม่ได้ (น้ำหนักขาด / ไม่มีใน Catalog)
---   huge    = จำนวนตัวปลายักษ์ (ขายได้มากกว่าสูตร แต่ไม่มีสูตรฝั่ง client)
---
--- ⚠ ข้ามปลาที่ล็อกไว้ เพราะ SellAll ไม่กินของที่ล็อก
---   (ToggleLock ใช้กันปลาของเควสต์ — protectQuestFish ล็อกไว้ ขายแล้วไม่หาย)
--- ⚠ อ่านราคาไม่ได้ = นับเป็น 0 กับพร้อมตั้ง unknown
---   ประมาณต่ำไว้ปลอดภัย เพราะคำตัดสินแค่ "พอไหม"
---   (ประมาณสูงเกิน = วิ่งไปขายแล้วยังไม่พอ = เสียเวลาเปล่า)
function satchelValue(data)
    local fishes = data and data.Inventory and data.Inventory.Fishes
    if type(fishes) ~= "table" then return 0, 0, false, 0 end
    local coins, count, unknown, huge = 0, 0, false, 0
    for _, f in pairs(fishes) do
        if type(f) == "table" and f.locked ~= true then
            count = count + 1
            if f.isHuge == true then huge = huge + 1 end
            local v = fishWorth(f, true)
            if v == math.huge then
                unknown = true
            else
                coins = coins + v
            end
        end
    end
    return coins, count, unknown, huge
end

--- พิมพ์มูลค่ากระเป๋าตอนนี้ (เรียกเองได้ที่ _G.FishingSatchelReport())
function _G.FishingSatchelReport()
    local data = fetchData()
    if not data then
        warn("[Satchel] อ่านข้อมูลผู้เล่นไม่ได้")
        return
    end
    local coins, count, unknown, huge = satchelValue(data)
    local full = isSatchelFull(data)
    warn(("[Satchel] %d ตัว · ขายได้ %s coin%s · กระเป๋า%s · มือ %s")
        :format(count, compactNum(coins),
            (unknown and " (มีตัวที่อ่านราคาไม่ได้ ไม่นับ)" or ""),
            (full and "เต็ม" or "ยังไม่เต็ม"),
            compactNum(numOr(data.Coin, 0))))
    if huge > 0 then
        warn(("[Satchel] มีปลายักษ์ %d ตัว — ขายได้มากกว่าที่คำนวณนี้"):format(huge))
    end
end

--- ล็อกปลาของภารกิจไว้ก่อน ไม่ให้ SellAll ไปกิน
---   (SellAll ขายทั้งกระเป๋าทีเดียว ไม่มี argument เลือกรายตัวไม่ได้ —
---    มีแต่ SellHeld ที่ต้อง "ถือ" ปลาตัวนั้นอยู่ ซึ่งทำแทนไม่ได้)
---   ล็อกได้ไม่เกิน needFish.count เพราะปลาที่ล็อกยังกินช่อง satchel (BaseCapacity = 50)
---
--- ⚠ สแกน "ทุกภารกิจที่ยังไม่เสร็จ" ไม่ใช่แค่ภารกิจแรก
---   เพราะปลาปลด Fossil ต้องเก็บ "ล่วงหน้า" ได้ตั้งแต่ตอนยังทำเควสต์เบ็ดอยู่
---   (missionFish เดิมใช้ activeMission = อันแรกที่ยังไม่เสร็จ -> ช่วงนั้นปลาจะไม่ถูกล็อคเลย)
---   ผลข้างเคียงที่ถูกต้อง: ระหว่างตกที่ Volcanic ถ้าหยิบ Stormblade Shark ที่น้ำหนักผ่านเกณฑ์
---   มันจะถูกเก็บไว้ทันที แม้ยังไม่ได้แตะเควสต์ unlock_island_6 เลย
function protectQuestFish()
    local data = fetchData()
    if not data then return false end
    if not (SellController and SellController.ToggleLock) then
        logWarn("[Prog] ไม่มี SellToggleLock — ปกป้องปลาของเควสต์ไม่ได้")
        return false
    end

    local anyWork = false
    for _, m in ipairs(CONFIG.Missions or {}) do
        if not missionDone(data, m) then
            local _, list, req = missionFish(data, m)
            if (req and list) and (req.count or 0) > 0 then
                -- ⚠ เรียงจาก "กินโควตาน้อยสุด" ไปหา "แพงสุด"
                --   เหตุผล: ค่าปลาแปรตามน้ำหนักยกกำลังสอง (value = averageValue/avg^2 * weight^2)
                --   ปลาหนักกว่า 2 เท่า = ขายได้ 4 เท่า เก็บตัวหนักทิ้ง = เสียเงินเปล่า ๆ
                --
                -- ⚠ "ล็อกครบโควตาแล้ว" ไม่ได้แปลว่าหยุดคิด ต้องเช็คใหม่ทุกรอบ:
                --   ถ้ามีตัวที่ถูกกว่าและยังไม่ได้ล็อก ให้สลับ (ล็อกตัวถูก -> ปลดตัวแพง)
                --   ไม่งั้นปลาหนักกว่าจะถูกขายทิ้ง ทั้งที่เราเก็บตัวเบาไว้เปล่า ๆ
                --
                -- ⚠ m.keepLightest (dread_fish_rod): ผู้ใช้สั่ง 2026-10-21 ว่า
                --   "เก็บปลา Mythical ไว้ 1 ตัว เป็นตัวที่น้ำหนักน้อยที่สุดที่ Quest ยอมรับได้"
                --   -> เรียงด้วยน้ำหนักจริง ไม่ใช่ราคา เพราะข้ามชนิดปลาแล้วสองค่านี้ไม่เรียงตรงกัน
                --     (mechmaw 5,000kg = 9.7M แพงกว่า voidmaw 5,500kg = 9.5M)
                --   เงื่อนไขน้ำหนักขั้นต่ำของ Quest ถูกกรองมาแล้วใน missionFish = ทุกตัวใน list รับได้หมด
                local byWeight = (m.keepLightest == true)
                table.sort(list, function(a, b)
                    if byWeight then
                        local ka = tonumber(a.weight) or math.huge
                        local kb = tonumber(b.weight) or math.huge
                        if ka ~= kb then return ka < kb end
                    end
                    local wa, wb = fishWorth(a), fishWorth(b)
                    if wa ~= wb then return wa < wb end
                    return tostring(a.fishId) < tostring(b.fishId)   -- กันลำดับไม่นิ่งตอนราคาเท่ากัน
                end)

                local need = req.count
                local byName = (req.mode == "named")
                -- โควตานับต่อชนิด (named) หรือรวมทั้งหมด (rarity)
                local function quotaOf(k)
                    if byName then return tonumber(req.ids[k]) or 0 end
                    return need
                end
                local function keyOf(f)
                    return byName and f.fishId or "*"
                end

                -- ── 1) ชุดที่ "ควร" ล็อก = ตัวที่ถูกที่สุด ตามจำนวนที่ต้องใช้ของแต่ละกุ้ม ──
                local want, counted = {}, {}
                for _, f in ipairs(list) do
                    local k = keyOf(f)
                    if (counted[k] or 0) < quotaOf(k) then
                        counted[k] = (counted[k] or 0) + 1
                        if type(f.uid) == "string" then want[f.uid] = true end
                    end
                end
                local lockedNow = {}
                for _, f in ipairs(list) do
                    if f.locked == true then
                        local k = keyOf(f)
                        lockedNow[k] = (lockedNow[k] or 0) + 1
                        S.lockedUids[f.uid] = true
                    end
                end

                -- ── 2) ล็อกตัวที่ยังขาด ──
                --   ⚠ ต้องทำก่อนปลดเสมอ: ถ้าล็อกตัวที่จะมาแทนไม่สำเร็จ แล้วค่อยปลดของเดิม
                --     = ปลาเควสต์หลุดมือถาวร เพราะไม่มีตัวสำรองให้ล็อกแทน
                local didLock = 0
                for _, f in ipairs(list) do
                    if want[f.uid] and f.locked ~= true and not S.lockedUids[f.uid] then
                        local ok, st, now = pcall(function() return SellController:ToggleLock(f.uid) end)
                        -- Status: Ok=0 .. Busy=8 — ถ้าเป็น Busy แปลว่ายิงถี่เกิน ข้ามไปรอบหน้า
                        if ok and st == 0 and now == true then
                            S.lockedUids[f.uid] = true   -- จำไว้กันกดซ้ำรอบหน้า
                            local k = keyOf(f)
                            lockedNow[k] = (lockedNow[k] or 0) + 1
                            didLock = didLock + 1
                        end
                    end
                end

                -- ── 3) ปลดตัวที่ "แพงเกินโควตา" = ล็อกอยู่แต่ไม่อยู่ในชุด want ──
                --   ⚠ อ่านข้อมูลใหม่ก่อนเสมอ: ถ้าใช้ state เก่า จะพลาดเคสที่ ToggleLock
                --     รอบล็อกสำเร็จจริงแต่ response ช้ากว่าที่เราอ่าน -> คิดว่าล็อกไม่สำเร็จ
                --     แล้วไม่กล้าปลดของเดิม = ค้างเป็นล็อก 2 ตัวตลอด (กินช่อง satchel เปล่า ๆ)
                local didUnlock = 0
                local _, list2 = missionFish(fetchData(), m)
                for _, f in ipairs(list2 or {}) do
                    if f.locked == true and not want[f.uid] then
                        local k = keyOf(f)
                        -- ปลดได้ก็ต่อเมื่อกุ้มนี้ยังล็อกเกินโควตาอยู่จริง = ปลดแล้วยังครบ
                        if (lockedNow[k] or 0) > quotaOf(k) then
                            local ok, st, now = pcall(function() return SellController:ToggleLock(f.uid) end)
                            if ok and st == 0 and now == false then
                                S.lockedUids[f.uid] = nil   -- เราปลดเอง = ล้างบันทึกกันกดซ้ำ
                                lockedNow[k] = (lockedNow[k] or 0) - 1
                                didUnlock = didUnlock + 1
                            end
                        end
                    end
                end

                if didLock > 0 or didUnlock > 0 then anyWork = true end
            end
        end
    end
    return anyWork
end

--- ปลดล็อกปลาของภารกิงที่กำลังจะกด Complete — เรียกก่อนกด Complete เท่านั้น
---   ตอนนี้เกมนับได้แล้ว และเราไม่ต้องขายอะไรอีกจนกว่าจะจบภารกิจ
---   ถ้าปลดไม่ครบ ให้คืน false (ปลาที่ยังล็อกอยู่ยังปลอดภัย)
--- ⚠ m = ภารกิงที่จะกด Complete เสมอ อย่าปล่อยให้ใช้ activeMission
---   เพราะตอนนั้นอาจมีภารกิงอื่นที่ล็อคปลาไว้ล่วงหน้า ซึ่งยังต้องเก็บไว้
function releaseQuestFish(m)
    if not (SellController and SellController.ToggleLock) then return false end
    m = m or activeMission(fetchData())
    local toggled = {}          -- กันยิงซ้ำตัวเดียวในรอบนี้ (ToggleLock เป็นสวิตช์ ไม่ใช่ set)
    local t0 = os.clock()
    while os.clock() - t0 < 3 do
        local _, list = missionFish(fetchData(), m)
        if not list then return true end
        local left = 0
        for _, f in ipairs(list) do
            if f.locked == true then
                left = left + 1
                if type(f.uid) == "string" and not toggled[f.uid] then
                    local ok, st, now = pcall(function() return SellController:ToggleLock(f.uid) end)
                    if ok and st == 0 and now == false then
                        toggled[f.uid] = true
                        S.lockedUids[f.uid] = nil   -- เราปลดเอง = ล้างบันทึกกันกดซ้ำ
                        logWarn(("[Prog] ปลดล็อก %s — พร้อมนับให้เควสต์"):format(tostring(f.fishId)))
                    end
                end
            end
        end
        if left == 0 then return true end
        task.wait(0.25)
    end
    logWarn("[Prog] ปลดล็อกปลาของเควสต์ไม่ครบในเวลาที่กำหนด — ยังไม่กด Complete")
    return false
end

-- ══════════════════════════════════════════════════
-- ORCHESTRATION
-- ══════════════════════════════════════════════════
-- forward decl (startFishing ถูกนิยามหลัง progression — ต้องประกาศล่วงหน้า)
local startFishing

--- ขายปลาทิ้งทั้งหมด (SellAll) คืน true ถ้าขายสำเร็จ
local function trySellAll()
    if not SellController then
        logWarn("[Prog] ไม่มี SellController — ขายไม่ได้")
        return false
    end
    local ok, st = pcall(function() return SellController:SellAll() end)
    return (ok and st == 0)
end

--- ถ้า satchel เต็ม: tween ไปใกล้คนขาย (ถ้ายังไกล) แล้วขาย
--- คืน true ถ้าขายได้ / false ถ้ายังไม่พร้อม (ไม่มี NPC, ไกล, ขายไม่ผ่าน)
--- ⚠ คนขายต้องเป็นของ "เกาะที่เราอยู่" ไม่ใช่ตัวแรกที่เจอ
---   ทุกเกาะมี npc_fish_seller_1 ของตัวเอง และ NPC ทุกเกาะโหลดมาพร้อมกัน
---   ถ้าไม่กรอง IslandId -> ไปเกาะ 2 แล้วยังวิ่งไปขายที่คนขายของเกาะ 1
--- ⚠ ล็อกปลาของเควสต์ก่อนขายเสมอ: จับ Legendary ได้ -> กระเป๋าเต็ม -> ขาย
---   อาจเกิดในรอบเดียวกัน ถ้าไม่ล็อกก่อน SellAll จะกินทิ้งทั้งกระเป๋า
--- เดินไปหาคนขาย + ขายปลา (ไม่ต้องรอให้กระเป๋าเต็มก็ได้)
--- คืน true ถ้าขายสำเร็จ / false ถ้ายังทำไม่ได้
--- ⚠ ล็อกปลาของเควสต์ก่อนขายเสมอ: จับ Legendary ได้ -> กระเป๋าเต็ม -> ขาย
---   อาจเกิดในรอบเดียวกัน ถ้าไม่ล็อกก่อน SellAll จะกินทิ้งทั้งกระเป๋า
function sellNow()
    protectQuestFish()

    local isl = currentIslandId()
    local dist = sellerDistance(isl)
    if dist == nil then
        logWarn(("[Prog] SELL: satchel เต็ม แต่หาคนขายปลาของ %s ไม่พบ"):format(tostring(isl)))
        return false
    end

    -- ยังไกลเกิน 25 (MerchantRadius) -> tween ไปหาคนขายก่อน (ดำน้ำ->เดินใต้น้ำ->โผล่)
    -- ⚠ ต้องเป็น tweenDiveTo ไม่ใช่ tweenTo: เรายืนใต้น้ำอยู่
    --   tweenTo ขึ้นไปเป็นเส้นตรง = ลากผ่านน้ำ/พื้นดิน ซึ่งเป็นแบบที่ snapback
    if dist > 25 then
        local seller = findSellerHrp(isl)
        if not seller then return false end
        S.moving = true
        tweenDiveTo(seller.Position, "sell")
        S.moving = false
        dist = sellerDistance(isl) or dist
    end

    if dist <= 25 then
        -- ── AURA: ใส่ตัวที่ +ราคาขายสูงสุดก่อนขาย (ผู้ใช้สั่ง) ────────────
        --   mode = "sell" = เลือกจาก sellValuePct มากสุด / ไม่มีตัวไหนเลย = ไม่สลับ
        if CONFIG.Aura.Enabled then
            equipBestAura(data, "sell")
        end
        local sold = trySellAll()
        -- ขายเสร็จ -> กลับไปใส่ตัวที่ +Luck / +ดาเมจตามปกติ (อ่านข้อมูลใหม่ ปลาเปลี่ยนคลัง)
        if sold and CONFIG.Aura.Enabled then
            equipBestAura(fetchData(), "fishing")
        end
        return sold
    end
    logWarn("[Prog] SELL: ยังไกลเกิน 25 studs — ขายไม่ได้")
    return false
end

handleSatchelFull = function(data)
    if not isSatchelFull(data) then return true end  -- ยังไม่เต็ม -> ไม่ต้องทำ
    return sellNow()
end

-- ══════════════════════════════════════════════════
-- ขั้นตอน "ขายก่อนทำงานที่ต้องใช้เงิน" (ผู้ใชาสั่ง 2026-10-16)
-- ──────────────────────────────────────────────────
--- คืน action ขั้นตอน "ขายปลา" ถ้าเงินในมือไม่พอ แต่รวมกับมูลค่าในกระเป๋าแล้วพอ
---   คืน nil = ไม่ต้องขาย (เงินในมือพอแล้ว / ขายแล้วก็ยังไม่พอ -> ไปฟาร์มต่อ)
---
--- ⚠ คืนเป็น "action" ไม่ใช่ขายเลย เพราะ action ต้องผ่าน backoff/attempt ของ runStep
---   และ runStep จะเรียก nextStep ใหม่ในรอบถัดไปทันที = ขายเสร็จก็ทำงานต่อเลย
---   ไม่ต้องรอรอบ FarmSpotPoll หรือรอกระเป๋าเต็ม
function needCoinsStep(data, need, why)
    if not CONFIG.Sell.OnDemand then return nil end
    if not data or type(need) ~= "number" then return nil end
    local coin = numOr(data.Coin, 0)
    if coin >= need then return nil end
    local coins, count, unknown, huge = satchelValue(data)
    if count <= 0 then return nil end
    if coin + coins < need then return nil end        -- ขายหมดก็ยังไม่พอ -> ไปฟาร์มต่อ

    if CONFIG.Sell.Log then
        logWarn(("[Sell] เงินในมือ %s + กระเป๋า %s = พอ %s — ไปขายก่อนเพื่อ%s")
            :format(compactNum(coin), compactNum(coins),
                compactNum(need), tostring(why or "ทำงานต่อ")))
    end
    local whyTxt = tostring(why or "ทำงานต่อ")
    return {
        key = "sell",
        label = ("ขายปลา %d ตัว (%s) เพื่อ%s"):format(count, compactNum(coins), whyTxt),
        run = function()
            local ok = sellNow()
            if not ok and CONFIG.Sell.Log then
                logWarn("[Sell] ขายไม่สำเร็จ — รอบหน้าลองใหม่")
            end
            return ok, (not ok) and "no-coin" or nil
        end,
    }
end

-- ══════════════════════════════════════════════════
-- เดินทางข้ามเกาะ — ว่ายไป NPC แล้วตั้งจุดเกิดของเกาะเป้า
-- ══════════════════════════════════════════════════
--- ตั้งจุดเกิดที่เกาะที่ระบุ (ยิง packet — ต้องอยู่ใกล้ NPC ภายใน 12 studs อยู่แล้ว)
--- เกมให้ตั้งได้เฉพาะตอนอยู่ใกล้ NPC ("Come a little closer..." = OutOfRange)
---   -> ผู้เรียกต้องพาเราไปยืนใกล้ NPC ของเกาะเป้าก่อน
--- คืน true ถ้าตั้งสำเร็จ
local function setSpawnAtIsland(islandId)
    local okPkt, pkt = pcall(function()
        return (Stardust.Packet("SetSpawnAtUnlockNPC")):Response(Stardust.Packet.NumberU8)
    end)
    if not (okPkt and pkt) then
        logWarn("[Prog] สร้าง packet SetSpawnAtUnlockNPC ไม่ได้")
        return false
    end
    local st = pkt:Fire()
    -- SpawnEnums.SetSpawnStatus: Ok=0 NotReady=1 OutOfRange=2 Locked=3 Error=4
    if st == (SpawnStatus and SpawnStatus.SetSpawnStatus and SpawnStatus.SetSpawnStatus.Ok or 0) then
        return true
    end
    logWarn(("[Prog] ตั้งจุดเกิดที่ %s ไม่ผ่าน (สถานะ %s)"):format(islandTag(islandId), tostring(st)))
    return false
end

--- ไปยืนใกล้ NPC "ปลดล็อกเกาะ" ของเกาะนั้น ก่อนที่ใครจะยิง QuestPacket
---
--- ⚠ server ตรวจระยะเอง: QuestConfig.NpcDistance (QuestConfig.lua:6) = 12 ตอนนี้
---   อ่านสดตอนรัน ไม่ hardcode — ถ้าเกมเปลี่ยนลิมิตเราต้องตามให้ทัน ไม่ใช่เดาเอง
---   หลักฐานว่า server เช็คจริง: ผู้ใช้ยิงจากระยะไกวแล้วเจอ
---   "Move closer to Jungle Island Guide" เมื่อ: 2026-10-16
---
--- ⚠ ลำดับที่ผู้ใช้สั่ง 2026-10-17: ไปจุด "Set Spawn" ของเกาะก่อน แล้วค่อยไปจุดปลดล็อก
---   เหตุผลที่ผู้ใช้ให้: จุดที่จะไปก่อนคือจุด Set Spawn เพราะถ้าไปถึงแล้ว
---   ของที่เหลือก็จะ stream เข้ามาแล้ว = ต้องไปที่เกาะก่อน ไม่ใช่กระโดดไปจุดปลดล็อกเฉย ๆ
---
--- ⚠ ฟังก์ชันนี้ยิง packet ไม่ได้เด็ดขาด: เดินทางสำเร็จ != server ยอมรับ
---   = คืนค่าความสำเร็จของ "ยืนใกล้แล้ว" เท่านั้น การตัดสินใจยังอยู่ที่ผู้เรียก
---
--- ไม่ประกาศพิกัดของเกาะนี้ = ยิงเหมือนเดิมทุกประการ (ไม่เดา กลับไปยิงจากที่ยืน)
S.tools.approachUnlock = function(islandId)
    local row = (CONFIG.IslandPoints or {})[islandId]
    if type(row) ~= "table" or not row.unlock then return true end

    -- ลิมิตจริงตอนนี้ = ค่าจากเกม ไม่ใช่ค่าที่เราเดา
    local lim = type(QuestConfig) == "table" and tonumber(QuestConfig.NpcDistance) or nil
    if type(lim) ~= "number" then
        logWarn("[Prog] อ่าน QuestConfig.NpcDistance ไม่ได้ — ไม่เดินทาง (ยิงจากที่ยืน)")
        return true
    end

    local hrp = root()
    if not hrp then return false end

    -- ยืนใกล้พอแล้ว = ไม่ต้องเดินทาง (ทุกรอบของ nextStep จะเรียกฟังก์ชันนี้)
    if (hrp.Position - row.unlock).Magnitude <= lim then return true end

    -- 1) จุด NPC ปลดล็อกก่อน = เกาะใหม่ยังตั้งจุดเกิดไม่ได้ (ผู้ใช้สั่ง 2026-10-17)
    --   ไป Set Spawn ก่อนจะเสียเวลาเปล่า เพราะต้องปลดล็อคให้เสร็จก่อนถึงตั้งจุดเกิดได้
    S.moving = true
    local reached = tweenDiveTo(row.unlock, "island-" .. tostring(islandId) .. "-unlock")
    S.moving = false
    if not reached then
        logWarn(("[Prog] ว่ายไปจุดปลดล็อก %s ไม่ถึง — ยังไม่ยิง packet"):format(islandTag(islandId)))
        return false
    end

    -- 2) เช็คจากตำแหน่งจริงอีกครั้ง: tween บอกว่าถึง != เราอยู่ใกล้จริง
    --   (เกมอาจดึงตัวกลับเข้าเขตเก่า = ระยะจริงไม่ใช่ระยะที่สั่งไป)
    local h2 = root()
    if not h2 then return false end
    local d = (h2.Position - row.unlock).Magnitude
    if d > lim then
        logWarn(("[Prog] ยืนใกล้ NPC ปลดล็อก %s ไม่ได้ — ห่าง %.1f studs (ลิมิต %.1f) เซิร์ฟจะปฏิเสธ")
            :format(islandTag(islandId), d, lim))
        return false
    end
    return true
end

-- ⚠ เกาะใหม่ยังตั้งจุดเกิดไม่ได้เพราะยังไม่ปลดล็อค (ผู้ใช้สั่ง 2026-10-17)
--   = ห้ามไปจุด Set Spawn ก่อนยิง packet และห้ามไปหลังยิงแต่ก่อนปลดล็อคเสร็จ
--     (จุด Set Spawn ห่างจุดปลดล็อค ~109 studs = ไกลเกิน NpcDistance ที่เซิร์ฟเช็ค)
--   เดินทางเรียงเป็น: ไปจุดปลดล็อค -> เช็คระยะจริง -> [ยิง packet] -> ไปจุด Set Spawn
S.tools.afterUnlockSpawn = function(islandId)
    local at = islandLandingSpot(islandId)
    if not at then return false end
    S.moving = true
    local reached = tweenDiveTo(at, "after-unlock-" .. tostring(islandId) .. "-spawn")
    S.moving = false
    if not reached then
        logWarn(("[Prog] ปลดล็อก %s ได้แล้ว แต่ว่ายไปจุด Set Spawn ไม่ถึง"):format(islandTag(islandId)))
        return false
    end
    return true
end


--- ข้ามไปเกาะเป้า: เดิน/ว่ายไปใกล้ NPC -> ตั้งจุดเกิดของเกาะนั้น
--- คราวหน้าที่เกมรีเซ็ตตัวละครเอง เราจะเกิดที่จุดเกิดของเกาะนั้น
--- ⚠ ข้อนี้คือหัวใจของการข้ามเกาะ — ห้าม PivotTo/Warp ข้ามเกาะเด็ดขาด
---   เกมไม่รับการวาร์ปข้ามเกาะ: ตัวละครถูกดึงกลับที่เดิม
---   พอยิง SetSpawnAtUnlockNPC ก็เลยได้ OutOfRange (สถานะ 2) = "Come a little closer..."
---   เพราะเซิร์ฟเวอร์เช็กระยะจากตำแหน่งจริงของเรา ไม่ใช่ตำแหน่งที่สั่ง PivotTo
---   วิธีเดียวที่ใช้ได้ = เดิน/ว่ายไปจริงด้วย tween (เขียน CFrame ต่อเนื่อง) แล้วค่อยยิง packet
--- ⚠ ระยะที่ต้องอยู่ใกล้ = 12 studs (InteractiveConfig.lua:22 — NPC แบบ Dialogue ทุกตัว)
--- saveSpawn = false -> ข้ามการตั้งจุดเกิดทั้งหมด ใช้ตอนไปตกบอส
---   NPC ที่ตั้งจุดเกิดมีไว้เพื่อยิง packet อย่างเดียว เดินไปเท่ากับเสียเวลาเปล่า
---   ผลข้างเคียงที่ถูก: จุดเกิดยังอยู่ที่เกาะฟาร์ม พอกลับมาจึงไม่ต้องเซฟซ้ำอีก
S.tools.travelRaw = function(islandId, saveSpawn)
    if saveSpawn == false then
        local landB = islandLandingSpot(islandId)
        if not landB then return false end
        S.moving = true
        local landedB = tweenDiveTo(landB, "land-" .. islandId)
        S.moving = false
        if not landedB then
            return false
        end
        -- ⚠ เกมคำนวณเกาะจากตำแหน่ง อาจรายงานช้ากว่าที่ถึง — รอจนรายงานตรงก่อนตัดสิน
        pollUntil(function() return currentIslandId() == islandId end, 5, 0.1)
        if currentIslandId() ~= islandId then
            return false
        end
        return true
    end

    -- ⚠ ลำดับที่ผู้ใช้สั่ง 2026-10-17: ไปจุด "Set Spawn" ของเกาะก่อนเสมอ
    --   เหตุผลที่ผู้ใช้ให้: จุดที่จะไปก่อนคือจุด Set Spawn
    --   เพราะถ้าไปถึงแล้วของที่เหลือก็จะ stream เข้ามาแล้ว
    --   เดิมไล่หา NPC ก่อน = ผิดลำดับ เพราะ NPC ของเกาะอื่นอาจ stream อยู่ตอนที่ยังไม่ไป
    --
    -- ⚠ เกาะที่ไม่ได้ประกาศพิกัด = ไม่มีจุดลงที่เชื่อถือได้ -> ข้ามขั้นนี้ไป
    --   ไล่หา NPC ตามเดิม (ไม่เดา และไม่หยุดทั้งที่อาจทำได้)
    local land = islandLandingSpot(islandId)
    if not land then
        logWarn(("[Prog] %s ไม่มีจุดลงที่ประกาศไว้ (CONFIG.IslandPoints) — ข้ามการไปจุด Set Spawn")
            :format(islandTag(islandId)))
    else
        local hrp0 = root()
        -- ⚠ ถ้ายืนที่จุดลงอยู่แล้ว ห้ามวิ่งมุดลงใต้น้ำเปล่า ๆ: tweenDiveTo มีเฟสมุดลง
        --   ที่จะพาลงใต้น้ำแม้ยืนถูกจุดแล้ว = เสียเวลา + ต้องว่ายขึ้นมาใหม่ทุกครั้ง
        if not (hrp0 and S.tools.arrived(hrp0, land)) then
            logWarn(("[Prog] ไปจุด Set Spawn ของ %s ก่อน (%s) — พอถึงแล้วเกาะจะ stream")
                :format(islandTag(islandId), tostring(land)))
            S.moving = true
            local landed = tweenDiveTo(land, "land-" .. islandId)
            S.moving = false
            if not landed then
                logWarn(("[Prog] ว่ายไปจุด Set Spawn ของ %s ไม่ถึง — ไม่ยิง packet")
                    :format(islandTag(islandId)))
                return false
            end
            -- ⚠ เช็คว่าทะลุมาได้จริงไหม เกมคำนวณ "เกาะปัจจุบัน" จากตำแหน่งจริงของเรา
            --   ถ้ายังบอกว่าอยู่เกาะเดิม = เกมดึงเรากลับมา -> ทางนี้ใช้ไม่ได้
            --   บอกตรง ๆ ดีกว่านั่งรอ NPC ที่จะไม่มีวันโผล่ แล้ว retry ไปเรื่อย ๆ
            pollUntil(function() return currentIslandId() == islandId end, 5, 0.1)
            local landedIsle = currentIslandId()
            if landedIsle ~= islandId then
                logWarn(("[Prog] ว่ายไปจุดลง %s แล้วแต่เกมยังรายงานว่าอยู่ที่ %s — เกมไม่ให้ว่ายข้ามเกาะ")
                    :format(islandTag(islandId), islandTag(landedIsle)))
                return false
            end
            -- ⚠ ไม่ต้องตรึงเองที่นี่: tweenDiveTo จบด้วย standAt(target, false) อยู่แล้ว
            --   = ถึงจุดแล้วตรึงเอง (Anchored) ไม่ใช่การดึงกลับด้วย CFrame
            --   ถ้ามาตรึงเองที่นี่อีกชั้น = จะตรึงทั้งที่ตัวยังไม่นิ่ง = เดินทางต่อไม่ได้
        end
    end
    --
    -- ⚠ หลังถึงจุดลงแล้ว ของที่เหลือของเกาะควร stream ครบ แต่การรอยังจำเป็นอยู่:
    --   stream คือการคัดกรองตามระยะ ไม่ใช่สัญญาว่าเสร็จทันที
    -- NPC ที่ตั้ง spawn ได้ = คนขายรถ (npc_car_merchant_*) ตาม SpawnPointDialogue
    --
    local npc = findNpcOnIsland(islandId, "npc_car_merchant")
    if not npc then
        npc = waitForNpcOnIsland(islandId, "npc_car_merchant", 8)
        if not npc then
            -- ทางสำรองสุดท้าย: ใช้ตัวที่ stream อยู่และใกล้เราที่สุด (พอเรายืนบนเกาะเป้า
            --   ตัวนั้นแทบจะเป็นของเกาะเป้าเสมอ) แล้วเดินไปหาให้สุดระยะที่แรงพอ
            local near, nd = findNearestNpcAnywhere("npc_car_merchant")
            -- ⚠ ต้องเป็น NPC ของเกาะเป้าจริง ไม่งั้นว่ายไปผิดเกาะแล้วค่อยมาล้มทีหลัง
            local rootIsl = islandRoot(islandId)
            if near and rootIsl and not near:IsDescendantOf(rootIsl) then
                logWarn(("[Prog] NPC ที่ stream อยู่ (ห่าง %.0f studs) ไม่ใช่ของ %s — ไม่ใช้")
                    :format(nd, tostring(islandId)))
                return false
            end
            if near then
                logWarn(("[Prog] ใน %s ไม่มี NPC แต่มีตัวที่ stream อยู่ห่าง %.0f studs — ใช้ตัวนั้นแทน")
                    :format(tostring(islandId), nd))
                npc = near
            else
                logWarn(("[Prog] ว่ายถึงจุดลง %s แล้วแต่ยังไม่มี npc_car_merchant สักตัว — ข้ามเกาะไม่ได้")
                    :format(islandTag(islandId)))
                return false
            end
        end
    end
    local hrpN = npc:FindFirstChild("HumanoidRootPart")
    if not (hrpN and hrpN:IsA("BasePart")) then
        logWarn(("[Prog] npc_car_merchant ของ %s ไม่มี HumanoidRootPart"):format(islandTag(islandId)))
        return false
    end


    -- 1) ไปใกล้ NPC ด้วยการเดิน/ว่ายจริง (ห่าง ~4 studs จากลิมิต 12) — ห้ามวาร์ป
    if currentIslandId() ~= islandId then
        logWarn(("[Prog] กำลังว่ายไป %s เพื่อตั้งจุดเกิด (เกมไม่รับการวาร์ปข้ามเกาะ)"):format(islandTag(islandId)))
    end
    local stand = hrpN.Position + Vector3.new(0, 0, 4)
    S.moving = true
    -- ไม่ตรึงตอนยืนข้าง NPC: startAntiSink() ฆ่า velocity ทุกเฟรม
    --   = ไม่หลุดออกจากระยะ 12 studs ที่เซิร์ฟเช็กก่อนรับ packet ตั้งจุดเกิด
    local reached = tweenDiveTo(stand, "goto-" .. islandId)
    S.moving = false
    if not reached then
        logWarn(("[Prog] ไปใกล้ NPC ของ %s ไม่ถึง"):format(islandTag(islandId)))
        return false
    end
    -- ตรึงตัวไว้ข้าง NPC ระหว่างรอ + ยิง packet
    -- (ไม่ตรึง = ลอย/ไหลตาม physics แล้วอาจหลุดออกจากระยะ 12 ก่อนเซิร์ฟเวอร์เช็ก)

    -- 2) รอให้เกมรายงานว่าเราอยู่เกาะนั้นจริง — GetCurrentIslandId() คำนวณจากตำแหน่ง
    --    ถ้ายังไม่ใช่เกาะเป้า แปลว่ายังไม่ทัน = ยิง packet ได้แต่จะ OutOfRange
    pollUntil(function() return currentIslandId() == islandId end, 5, 0.1)
    if currentIslandId() ~= islandId then
        logWarn(("[Prog] ถึงใกล้ NPC แล้วแต่เกมยังรายงานว่าอยู่ที่ %s (ไม่ใช่ %s) — ไม่ยิง packet")
            :format(tostring(currentIslandId()), tostring(islandId)))
        return false
    end

    -- 3) ตอนนี้อยู่ใกล้ NPC จริงแล้ว ค่อยตั้งจุดเกิด
    if not setSpawnAtIsland(islandId) then
        return false
    end

    -- เราว่ายมาถึง NPC แล้ว = ยืนอยู่เกาะนั้นจริงแล้ว ไม่ต้องรีเซ็ตตัวละคร
    -- ⚠ LocalPlayer:LoadCharacter() ใช้ไม่ได้: Roblox บล็อกว่า
    --   "LoadCharacter can only be called by the backend server" (ทดสอบแล้ว)
    --   ในตัวเกมไม่มี packet รีเซ็ตให้ มีแต่ Cmdr `$respawn` ที่ต้องมีสิทธิ์ DefaultAdmin
    --
    --   ไม่ต้องรีเซ็ตก็ครบ: จุดเกิดที่เพิ่งตั้งจะทำให้ "คราวหน้าที่เกมรีเซ็ตเอง"
    --   (ตาย / ออกเกมแล้วกลับมา) เกิดที่เกาะนี้ ซึ่งก็คือจุดประสงค์ของการตั้งจุดเกิด
    -- ⚠ ห้ามนับเวลาเอง: ตอนนี้เซิร์ฟรับแล้ว (setSpawnAtIsland ได้ Ok) แต่ค่าใน
    --   Template.SpawnIsland ยังไม่ replicate กลับมา ต้องอ่านสดจนกว่าจะเป็นเกาะนี้จริง
    --   0.5 เป็นแค่เพดานกันค้าง ไม่ใช่เวลาที่เราเดาเองว่าใช้เท่าไร
    local spawned = pollUntil(function()
        local d = fetchData()
        return (d and d.SpawnIsland) == islandId
    end, 0.5, 0.05)
    if spawned then
        -- ⚠ บันทึกว่าฟิลด์นี้ replicate กลับมาจริง = เอาไปใช้ตัดสินได้
        --   SpawnIsland มีแค่ใน Template/schema/MigrationSteps ของดัมป์ ไม่มี client
        --   ไหนเขียนมันเลย (ดู wrongSpawn) = ถ้าเซิร์ฟไม่ส่งกลับ ค่าจะติด island_starter
        --   ตลอด แล้ว wrongSpawn จะเป็นจริงตลอด = สั่งว่ายวนไม่จบ ตกปลาไม่ได้เลย
        --   วิธีกัน: เชื่อก็ต่อเมื่อเคยเห็นมันเปลี่ยนจริงสักครั้ง
        S.spawnReplicates = true
    else
        logWarn(("[Prog] ตั้งจุดเกิดที่ %s สำเร็จแต่เกมยังรายงานจุดเกิดเดิม — จุดเกิดรอบนี้อาจยังไม่ถูกบันทึก")
            :format(tostring(islandId)))
    end
    setNoclip(true)
    return true
end

--- ตัวห่อ: error ข้างในไม่หลุดออกไปค้างธงของผู้เรียก (คืน false แทน)
function travelToIsland(islandId, saveSpawn)
    local okT, res = pcall(S.tools.travelRaw, islandId, saveSpawn)
    if not okT then
        logWarn(("[Prog] travelToIsland(%s) error — %s"):format(tostring(islandId), tostring(res)))
        S.moving = false
        return false
    end
    return res
end

--- กลับไปยืนที่จุดฟาร์มของเกาะที่ควรฟาร์มตอนนี้ — คืน true ถ้าไปถึงแล้ว
---
--- ⚠ ข้ามเกาะ = ตั้ง Spawn Point ที่ NPC ของเกาะเป้า แล้วเดิน/ว่ายไปถึง NPC นั้น
---   (เกมไม่รับการวาร์ปข้ามเกาะ — tween ต่อเนื่องเท่านั้นที่ได้ผล)
S.tools.farmRaw = function()
    -- เกาะเป้าหมาย = จุดหมายของภารกิจที่ยังไม่เสร็จ ไม่งั้นเกาะหลัก
    local target = activeFarmIsland(fetchData())
    if not target then
        logWarn("[Prog] ยังไม่รู้ว่าจะฟาร์มที่เกาะไหน")
        return false
    end

    -- 1) ยืนผิดเกาะ -> travelToIsland (ว่ายไป NPC + ตั้งจุดเกิด)
    if currentIslandId() ~= target then
        S.traveling = true
        local ok = travelToIsland(target)
        S.traveling = false
        if not ok then return false end
        -- รอให้เกมรายงานว่าเราอยู่เกาะนั้นจริง
        pollUntil(function() return root() and currentIslandId() == target end, 10, 0.2)
        if currentIslandId() ~= target then
            logWarn(("[Prog] ข้ามไป %s แล้วแต่เกมยังไม่รายงานว่าอยู่ที่นั่น — รอรอบหน้า"):format(tostring(target)))
            return false
        end
    end

    -- 2) ยังไม่อยู่จุดฟาร์มของเกาะนี้ -> tween ไปจุดเป้า (ภายในเกาะเดียวกัน ไม่ใช่ข้ามเกาะ)
    local spot = farmSpotFor(target)
    local hrp = root()

    -- ⚙ บันทึกตัวเลขจริงครั้งเดียวตอนสตาร์ต (ผู้ใช้บอกว่า "ตัวขยับไม่ได้")
    --   tween ใช้ CFrame ตรง ๆ = ถ้ารันต้องขยับแน่ ๆ ไม่มีทางค้าง
    --   แต่ log ไม่มีบรรทัด [Prog] MOVE[...] เลย = ไม่ได้เข้า tween เลย
    --   จึงต้องเห็นก่อนว่า "คิดว่าเกาะไหน / ยืนที่ไหน / เป้าไหน / ห่างเท่าไร"
    if not Guard.diagMove then
        Guard.diagMove = true
        logWarn(("[Prog MOVE] เกาะที่ยืน=%s  เป้าหมาย=%s  hrp=%s  จุดฟาร์ม=%s  ห่างจุดฟาร์ม=%s  noclip=%s")
            :format(tostring(currentIslandId()), tostring(target),
                hrp and (("%.0f,%.0f,%.0f"):format(hrp.Position.X, hrp.Position.Y, hrp.Position.Z)) or "nil",
                spot and (("%.0f,%.0f,%.0f"):format(spot.X, spot.Y, spot.Z)) or "nil",
                (hrp and spot) and ("%.1f"):format((hrp.Position - spot).Magnitude) or "?",
                tostring(S.noclipConn ~= nil)))
    end
    if not spot then
        logWarn(("[Prog] เกาะ %s ยังไม่ได้ประกาศจุดฟาร์มใน CONFIG.FarmSpots")
            :format(tostring(target)))
        return false
    end
    if not hrp then
        logWarn("[Prog] ยังไม่มีตัวละคร")
        return false
    end
    -- ⚠ ทางลัดเดิม: ห่างจุดฟาร์มไม่เกิน 25 studs ก็ถือว่ามาถึงแล้ว
    --   แก้เป็น "ถึงจริง" ตามเกณฑ์เดียวกับที่ S.tools.pin ใช้ (ArriveXZ/StandHeight)
    --   เพราะ 25 studs = ใกล้พอจะขยับ แต่ยังไม่ถึง — ถ้าตรึงตรงนี้ pin() จะปฏิเสธ
    --   แล้วเราก็ไหลลงที่จุดเก่า = บั๊ก "ไหลลง" ที่แก้ไปกลับมาทั้งดุ้น
    if S.tools.arrived(hrp, spot) then
        -- ⚠ ไม่สร้างแท่นตรงนี้ (ผู้ใช้สั่ง 2026-10-16: แท่นมีแค่ตอนตกบอส)
        --   standAt(..., false) = ลบแท่นค้างจากรอบบอส แล้วตรึงที่จุดที่มาถึงจริง
        standAt(spot, false)
        return true
    end

    S.moving = true
    local arrived = tweenDiveTo(spot, "farm")
    if not arrived and root() then
        -- ล้มครั้งแรก (เช่นโดนดึงกลับตอนเริ่ม) = ลองอีกครั้งจากตำแหน่งจริงทันที
        --   เดิมรอรอบ FarmSpotPoll (8 วิ) + ตัวละครไหลลงระหว่างนั้น
        task.wait(0.5)
        arrived = tweenDiveTo(spot, "farm-retry")
    end
    S.moving = false

    -- ⚙ บันทึก "หลัง" เทียบกับ "ก่อน" ข้างบน ต้องเห็นว่า tween ได้ผลจริงไหม
    if Guard.diagMove then
        local h2 = root()
        logWarn(("[Prog MOVE] tween farm -> %s  ตอนนี้=%s  เหลืออีก=%s")
            :format(tostring(arrived),
                h2 and (("%.0f,%.0f,%.0f"):format(h2.Position.X, h2.Position.Y, h2.Position.Z)) or "nil",
                h2 and ("%.1f"):format((h2.Position - spot).Magnitude) or "?"))
    end
-- ⚙ เช็คเกาะอีกครั้งหลัง tween จบ — จุดที่พลาดบ่อยที่สุด
    --   ข้างบนเช็กก่อน tween ว่า "เราอยู่เกาะไหน" แต่พอโดนดึงกลับระหว่างทาง
    --   หรือทันทีหลัง tween เสร็จ เกมจะยังรายงานเกาะเดิมอยู่
    --   = tween คืน true (ตำแหน่งใกล้เป้า) แต่ของจริงเรายังอยู่เกาะเดิม
    --   แล้วลูปตกปลายิงตามเกาะที่คิดไว้ = จับผิดที่ / เควสต์ไม่ขึ้น
    --   ⚠ ตรวจซ้ำสองครั้งติดกัน: ครั้งแรกจับการดึงกลับทันที ครั้งที่สองจับที่ช้ากว่า
    --     (ตอนนี้ยังเป็นเกาะเดิม = เพิ่งถูกดึงกลับ ไม่ใช่แค่ replicate ช้า)
    for _c = 1, 2 do
        if currentIslandId() ~= target then
            local there = currentIslandId()
            logWarn(("[Prog] ทะเบียน: tween ไป %s แล้วแต่เกมยังรายงานว่าอยู่ที่ %s "
                  .. "(ห่างจุดฟาร์ม %.1f studs) — โดนดึงกลับ ไม่ถือว่าถึง")
                :format(tostring(target), tostring(there),
                    hrp and (("%.1f"):format((hrp.Position - spot).Magnitude)) or "?"))
            S.tools.releasePin()
            S.arriveAt = nil
            task.wait(0.5)
        end
    end
    if currentIslandId() ~= target then
        return false
    end
    -- ⚠ เคยเขียน S.farmIsland = target ตรงนี้ แต่ไม่มีใครอ่านมันเลย
    --   (เกาะที่กำลังฟาร์มจริงอ่านจาก currentIslandId() ทุกครั้ง) = state ตายที่ไม่มีทางรู้ค่าเก่า
    --   แถมยังขัดกับ goToFarmSpot ที่บอกว่าย่ายอาจไปเกาะอื่นได้ = ค่าจะโกหกเสมอ ตัดทิ้ง
    return arrived
end

--- ตัวห่อ: error ข้างในไม่หลุดออกไปทำให้ mainLoop ตายหรือธงค้าง
function goToFarmSpot()
    local okF, res = pcall(S.tools.farmRaw)
    if not okF then
        logWarn(("[Prog] goToFarmSpot error — %s"):format(tostring(res)))
        S.moving = false
        S.traveling = false
        return false
    end
    return res
end

-- ── เดินเข้าหา NPC ที่รับเควสต์ (ใช้เฉพาะตอนยิงจากที่ยืนแล้วไม่ผ่าน) ──
--- QuestController.lua:126 — Complete(questId) รับแค่ id ไม่มีตำแหน่งตัวละคร
---   และ dialogue ทั้งสามใบเรียกตรงๆ ไม่มีเช็กระยะ (npc_*_rod.lua:87-88)
---   -> ปกติยิงจากที่ยืนก็ผ่าน ฟังก์ชันนี้มีไว้เป็นทางออกเผื่อ server เช็กจริง
---   ซึ่งพิสูจน์จากดัมป์ไม่ได้ เพราะดัมป์เป็นฝั่ง client ล้วน
local function walkToNpc(islandId, interactiveId)
    local mm = findNpcOnIsland(islandId, interactiveId)
    -- ⚠ ห้ามใช้ตัวของเกาะอื่นที่ stream อยู่ — เดินไปตัวของ Jungle
    --   ไม่ได้พิสูจน์อะไรเกี่ยวกับ NPC ตัวที่อยู่ Volcanic นอกจากว่าไม่มี
    if not mm then
        logWarn(("[Prog] หา %s ที่ %s ไม่เจอ (น่าจะยังไม่ stream) — ยิงจากที่ยืนอยู่")
            :format(tostring(interactiveId), tostring(islandId)))
        return false
    end
    local hrp = mm:FindFirstChild("HumanoidRootPart")
    if not (hrp and hrp:IsA("BasePart")) then return false end
    -- ⚠ ต้องตั้ง S.moving คุมไว้เหมือนทุกจุดที่เรียก tweenDiveTo
    --   วงตกปลาเช็ค S.moving/S.traveling ก่อนยิง (บรรทัด ~2759) ถ้าไม่ตั้งจะยิงกลางทาง
    S.moving = true
    local reached = tweenDiveTo(hrp.Position + Vector3.new(0, 0, -5), "npc-" .. tostring(interactiveId))
    S.moving = false
    return reached
end

--- เดินไปยืนใกล้ NPC ของเควสต์เบ็ด (kind="rod") ให้อยู่ในระยะ QuestConfig.NpcDistance ก่อนกด Accept
--- ⚠ บั๊กเดิม: ขั้น "รับเควสต์" เรียก approachUnlock(m.targetIsland) แต่เควสต์เบ็ดไม่มี targetIsland (เป็น nil)
---   -> approachUnlock คืน true ทันทีโดยไม่เดินไปไหน -> ยิง Accept จากจุดฟาร์ม -> เซิร์ฟตอบ
---   "Move closer to Bac Minh." ซ้ำไม่รู้จบ (log จริง: 10 ครั้งติดแล้วพัก แล้ววนอีก)
S.tools.approachRodNpc = function(m)
    if not (m and m.npcIsland and m.npcId) then return true end
    local lim = type(QuestConfig) == "table" and tonumber(QuestConfig.NpcDistance) or nil
    if type(lim) ~= "number" then
        logWarn("[Prog] อ่าน QuestConfig.NpcDistance ไม่ได้ — ไม่เดินไปหา NPC (ยิงจากที่ยืน)")
        return true
    end

    local npc = findNpcOnIsland(m.npcIsland, m.npcId)
    if not npc then
        -- NPC ยังไม่ stream (อยู่ไกล): ไปเกาะของ NPC ก่อน แล้วรอให้โหลด
        if currentIslandId() ~= m.npcIsland then
            if not travelToIsland(m.npcIsland) then return false end
        end
        npc = waitForNpcOnIsland(m.npcIsland, m.npcId, 8)
    end
    if not npc then
        logWarn(("[Prog] หา NPC %s ที่ %s ไม่เจอ — ยังรับเควสต์ไม่ได้"):format(tostring(m.npcId), tostring(m.npcIsland)))
        return false
    end

    local nh = npc:FindFirstChild("HumanoidRootPart") or npc.PrimaryPart
    if not (nh and nh:IsA("BasePart")) then return false end
    local me = root()
    if not me then return false end
    if (me.Position - nh.Position).Magnitude <= lim then return true end

    S.moving = true
    local reached = tweenDiveTo(nh.Position + Vector3.new(0, 0, -5), "npc-" .. tostring(m.npcId))
    S.moving = false

    local h2 = root()
    local d = h2 and (h2.Position - nh.Position).Magnitude or math.huge
    if not reached or d > lim then
        logWarn(("[Prog] ไปยืนใกล้ NPC %s ไม่ได้ — ห่าง %.1f studs (ลิมิต %.1f)"):format(tostring(m.npcId), d, lim))
        return false
    end
    return true
end

--- เดินไป NPC ใด ๆ ที่หาเจอ (World.Islands/*/Interactives + Workspace.Raids/RaidSlots)
--- ⚠ NPC ของ raid (Ticket Keeper / Raid Guide) ไม่ได้อยู่ใน World.Islands
---   และพื้นที่ raid ไม่อยู่ในระบบ travelToIsland -> ห้ามเรียก travelToIsland ที่นี่
S.tools.approachNpcAnywhere = function(interactiveId, radius)
    local lim = tonumber(radius) or 12
    local npc = findNearestNpcAnywhere(interactiveId)
    if not npc then return false end
    local nh = npc:FindFirstChild("HumanoidRootPart") or npc.PrimaryPart
    if not (nh and nh:IsA("BasePart")) then return false end
    local me = root()
    if not me then return false end
    if (me.Position - nh.Position).Magnitude <= lim then return true end
    S.moving = true
    local reached = tweenDiveTo(nh.Position + Vector3.new(0, 0, -5), "npc-" .. tostring(interactiveId))
    S.moving = false
    me = root()
    local d = me and (me.Position - nh.Position).Magnitude or math.huge
    if not reached or d > lim then
        logWarn(("[Raid] ไปยืนใกล้ NPC %s ไม่ได้ — ห่าง %.1f studs (ลิมิต %.1f)")
            :format(tostring(interactiveId), d, lim))
        return false
    end
    return true
end

--- NPC ตัวรับรางวัลหลังชนะ raid (server ติด attribute RaidWon = true ให้ตัวที่กด Claim ได้)
S.tools.approachRaidWonNpc = function()
    for _, folderName in ipairs({ "Raids", "RaidSlots" }) do
        local f = Workspace:FindFirstChild(folderName)
        if f then
            for _, d in ipairs(f:GetDescendants()) do
                if d:IsA("Model") and d:GetAttribute("RaidWon") == true then
                    local nh = d:FindFirstChild("HumanoidRootPart") or d.PrimaryPart
                    local me = root()
                    if nh and nh:IsA("BasePart") and me then
                        if (me.Position - nh.Position).Magnitude > 12 then
                            S.moving = true
                            tweenDiveTo(nh.Position + Vector3.new(0, 0, -5), "raid-won-npc")
                            S.moving = false
                        end
                        me = root()
                        return me ~= nil and (me.Position - nh.Position).Magnitude <= 15
                    end
                end
            end
        end
    end
    return false
end

-- ── เบ็ดที่เควสต์เบ็ด "บังคับต้องมี" ──
--- crimson_bead_rod ต้องมี legacy_rod (ซื้อที่ร้านของ Snow 3,000,000)
--- bamboo_rod       ต้องมี crimson_bead_rod (ได้จากเควสต์ก่อนหน้า = ซื้อไม่ได้)
---
--- ⚠ ต้องทำก่อนขั้น "รับเควสต์" เสมอ ไม่ใช่หลัง
---   เหตุผลที่ยืนยันได้: ตัวนับของเควสต์นับ "จับด้วยเบ็ดนี้" — crimson_bead_rod
---   นับ CurrentFished เฉพาะที่จับตอนใส่ Legacy Rod (Requirements/crimson_bead_rod.lua:51)
---   ไม่มี legacy_rod = ตัวนับไม่ขยับ = ทำเควสต์ไม่จบ
--- ⚠ ไม่ได้ยืนยันว่าเซิร์ฟปฏิเสธตอน Accept ถ้ายังไม่มีเบ็ด — ในดัมป์ไม่มีข้อความ
---   ปฏิเสธเรื่องนี้เลย (npc_crimson_bead_rod.lua:16-52 เช็คแค่ Done/Progress/เงิน)
---   เพราะ missionStep จะคืน action ของ Accept ทุกรอบ และไม่มีทางไปถึงขั้นซื้อเบ็ดเลย
local function needRodAction(data, m)
    if not (m and m.needRod) then return nil end
    if ownsRod(data, m.needRod) then return nil end
    local shop = type(RodShopConfig) == "table" and RodShopConfig[m.needRod] or nil
    local price = rodPrice(m.needRod)
    local canBuy = (type(price) == "number")
        and (not (type(shop) == "table" and shop.islandId) or islandUnlocked(data, shop.islandId))
    -- ซื้อไม่ได้ = ได้จากเควสต์ก่อนหน้าที่ยังไม่เสร็จ -> ปล่อยให้ไปทำมันก่อน
    if not canBuy then return nil end
    -- ⚠ ก่อนตัดสินว่า "รอเงิน" ลองดูกระเป๋าก่อน = อาจขายแล้วพอเลย ไม่ต้องไปฟาร์มเพิ่ม
    local sellStep = needCoinsStep(data, price, ("ซื้อ %s"):format(rodTag(m.needRod)))
    if sellStep then return sellStep end
    if numOr(data.Coin, 0) < price then return nil end     -- รอเงิน -> ฟาร์มเกาะที่ดีที่สุด
    return {
        key = "buy:" .. m.needRod,
        label = ("ซื้อ %s (%s) เพื่อทำเควสต์ %s"):format(
            tostring(m.needRod), tostring(price), tostring(m.targetRod)),
        newRod = m.needRod,
        run = function() return buyRod(m.needRod, fetchData() or data) end,
    }
end

-- ── ขั้นของเควสต์เบ็ด (kind = "rod") ──
--- กติกาต่างจากเควสต์ปลดเกาะตรงที่ "สิ่งที่ต้องเก็บ" ไม่ใช่ปลาเสมอไป:
---   crimson_bead_rod = ตัวนับสะสมที่ server นับให้ (Progress.CurrentFished)
---   bamboo_rod       = ไอเทมในกระเป๋า (Inventory.Items.bamboo_fragment)
---   dread_fish_rod   = ปลา Mythical ของเกาะที่ระบุ
--- จึงต้องใช้ missionCollect + missionCoin (อ่านตามโหมด) แทน missionFish + islandCost
local function rodMissionStep(data, m)
    -- a) เบ็ดที่เควสต์บังคับต้องมีก่อน — ย้ายไปทำใน missionStep แล้ว (ก่อนขั้น Accept)
    --    เพราะเซิร์ฟบังคับตอนรับเควสต์ ไม่ใช่ตอนกด Complete

    -- a0) ⚠ dread_fish_rod: ต้องได้สกิล Fossil (Legendary x2) ก่อน (ผู้ใช้สั่ง 2026-10-21)
    --   คืน "action สุ่ม" ไม่ใช่ nil — ตอนนี้ best.id = Lotus แล้ว (ปลดไปแล้ว)
    --   ขั้น 5 ของ nextStep เช็คสกิลของ best.id (= Lotus, fallback 1 ตัว) = ผ่านแล้ว
    --   ถ้าคืน nil เฉย ๆ nextStep จะไหลไป stop gate (StopIsland = lotus) แล้วจอดถาวร
    if m.key == DREAD_ROD_ID then
        local skOk, skMsg = dreadSkillsReady(data)
        if not skOk then
            return {
                key = "gacha",
                label = ("สุ่มสกิลที่ %s ก่อนรับ %s (%s)"):format(
                    islandTag(m.farmIsland or "island_fossil"), rodTag(m.targetRod), tostring(skMsg)),
                quiet = true,
                run = function() return rollSkillOnce(data) end,
            }
        end
    end

    -- b) ครบหรือยัง — ครบเมื่อ "สิ่งที่ต้องเก็บ" ครบ AND เงินพอ
    --    ครบแล้วยังไม่ต้องไปไหน: Complete ยิงจากที่ยืนก็ได้ ไม่ต้องไปหา NPC
    --    bamboo_rod: ตกที่ Jungle ให้ครบ 20 ชิ้น + เงิน 3.6M แล้วกดรับเบ็ดจากตรงนั้นเลย
    local collectOk, rq, rlist = missionCollect(data, m)
    if not rq then return nil end
    -- จำนวนที่เก็บได้จริง: โหมด named/rarity นับจากรายการปลา ที่เหลืออ่านจาก Progress
    local rgot = rlist and #rlist or rq.got
    local cost = missionCoin(data, m)
    -- ⚠ ก่อนตัดสินว่า "ยังไม่พร้อม" ลองดูกระเป๋าก่อน = อาจขายแล้วพร้อมเลย
    local sellStep = needCoinsStep(data, cost, ("ทำเควสต์ %s"):format(tostring(m.key)))
    if sellStep then return sellStep end
    local ready = collectOk and (type(cost) == "number") and (numOr(data.Coin, 0) >= cost)

    -- c) ยังไม่ครบ -> ไปเกาะที่ต้องตกปลา + ตั้งจุดเกิดใหม่ที่นั่น
    if not ready then
        -- ⚠ ต้องแยกสองกรณีนี้ออกจากกัน มิฉะนั้นจะวนสองเกาะไม่จบ
        --   ของยังไม่ครบ          -> ต้องอยู่ farmIsland (ไปเก็บของต่อ)
        --   ของครบแล้ว เงินไม่พอ  -> อยู่ที่ไหนก็ได้ ให้ activeFarmIsland ไปหาเงินที่
        --                          เกาะที่ปลดสูงสุดแทน ถ้าเรายังสั่งให้ไป farmIsland
        --                          ทุกรอบ เราจะถูกสั่งให้กลับทันทีที่ถึง แล้วถูกสั่งไปต่อ
        --                          = เดินทางวนไปมาจนไม่เหลือเวลาตกปลาเลย
        --   (เคสนี้เกิดจริงกับ bamboo_rod: farmIsland = Jungle แต่เกาะที่ดีที่สุด = Volcanic)
        if collectOk then
            return nil        -- ครบของแล้ว เหลือแค่เงิน -> ปล่อยให้ activeFarmIsland ตัดสิน
        end
        local farm = m.farmIsland
        if farm and islandUnlocked(data, farm) then
            local wrongIsland = currentIslandId() ~= farm
            local spawnIsland = (data and data.SpawnIsland) or nil
            -- ⚠ เชื่อ data.SpawnIsland ได้ก็ต่อเมื่อเคยเห็นมันเปลี่ยนจริงสักครั้ง
            --   ถ้าเซิร์ฟไม่ replicate ค่านี้ มันจะติด island_starter ตลอด = วนว่ายไม่จบ
            local wrongSpawn = S.spawnReplicates and (spawnIsland ~= nil) and (spawnIsland ~= farm)
            if wrongIsland or wrongSpawn then
                return {
                    key = "travel:" .. farm,
                    label = ("ไปเกาะ %s เพื่อทำเควสต์ %s%s"):format(
                        islandTag(farm), tostring(m.key),
                        wrongSpawn and (" (ตั้งจุดเกิดใหม่ที่ %s)"):format(islandTag(farm)) or ""),
                    run = function() return travelToIsland(farm) end,
                }
            end
        end
        return nil                    -- อยู่เกาะถูกแล้ว -> ปล่อยให้ไปตกต่อ
    end

    -- d) กด Complete จากที่ยืนอยู่ก็ได้ ไม่ต้องเดินไปหา NPC ไม่ต้องว่ายไปเกาะ NPC
    --    QuestController:Complete รับแค่ questId (QuestController.lua:126)
    --    ⚠ "ยิงจากเกาะไหนก็ได้" = เดาจากฝั่ง client ที่ไม่มีเช็คระยะเลย
    --      ยังไม่มีหลักฐานว่า server ยอมรับ (ดัมป์เป็น client ล้วน) = อย่าวางแผนพึ่งมัน
    -- e) Complete (completeQuest ปลดล็อกปลาของเควสต์ให้เองอยู่แล้ว)
    return {
        key = "mission:" .. m.key,
        label = ("รับ %s (%s + %s)"):format(
            rodTag(m.targetRod), tostring(cost), missionFishLabel(rq, rgot)),
        run = function()
            local d2 = fetchData() or data
            if completeQuest(m, d2) then return true end
            -- ทางออกเผื่อ: ยิงจากที่ยืนไม่ผ่าน -> ไปหา NPC จริงแล้วลองอีกครั้ง
            --   ไม่ใช่ข้อสมมติที่ต้องเชื่อ แค่ไม่มีทางพิสูจน์ว่า server ไม่เช็ก
            if not (m.npcId and m.npcIsland and islandUnlocked(d2, m.npcIsland)) then return false end
            if not travelToIsland(m.npcIsland) then return false end
            walkToNpc(m.npcIsland, m.npcId)
            return completeQuest(m, fetchData())
        end,
    }
end

--- ══════════════════════════════════════════════════
-- ISLAND 7 (LOTUS) — เควสต์ 3 สเต็ป + การสลับไปเอา Dread Fish Rod
--
-- ⚠ ทุกฟังก์ชันในบล็อกนี้เป็น "global" (function ชื่อ(...)) ไม่ใช่ local
--   เพราะไฟล์ชนเพดาน 200 local แล้ว — เพิ่ม local อีกตัวเดียวก็ compile ไม่ผ่าน
--   และ global ที่นิยามทีหลังก็ปลอดภัย เพราะถูกเรียกตอนรันจริง (ไฟล์โหลดจบแล้ว)
--   (เหมือน missionCollect / missionCoin / needCoinsStep ที่ทำแบบนี้อยู่แล้ว)
--
-- ลำดับจริงของเกม (npc_unlock_island_7.lua:85-125):
--   Step 1 ดอกครบ -> Advance -> Step 2
--   Step 2 essence ครบ -> Advance -> Step 3
--   Step 3 จ่าย coin+gem -> Complete
-- ══════════════════════════════════════════════════
--- สเต็ปของเควสต์ Lotus ตอนนี้ (nil = ยังไม่ได้รับเควสต์นี้)
function lotusStepOf(data)
    local cur = data and data.Quest and data.Quest.Current
    if type(cur) ~= "table" or cur.Id ~= "unlock_island_7" then return nil end
    local st = type(cur.Progress) == "table" and tonumber(cur.Progress.Step)
    return st
end

--- ค่าจริงจากเกม อ่านสด (fallback ตามดัมป์ QuestConfig.Island7:6-33)
function lotusNeed(field, fallback)
    local i7 = QuestConfig and QuestConfig.Island7
    local v = type(i7) == "table" and tonumber(i7[field])
    return v or fallback
end

function lotusGemCost()
    return lotusNeed("GemCost", 200)
end

--- ภารกิจ dread จาก CONFIG.Missions
---   ⚠ ห้ามใช้ activeMission ตอนนี้ — ตอนนั้น active คือ lotus ไม่ใช่ dread
function lotusDreadMission()
    for _, m in ipairs(CONFIG.Missions or {}) do
        if m.key == "dread_fish_rod" then return m end
    end
    return nil
end

--- สกิลของเกาะ Fossil ครบเป้าหมายหรือยัง — "ต้องได้สกิลก่อนปลดเบ็ด Dread Fish Rod"
---   (ผู้ใช้สั่ง 2026-10-21: Fossil ต้องมี Legendary ขึ้นไป 2 ตัว = 2 สกิลรวมทั้งบัญชี)
---   ⚠ ใช้เป็น gate ของทั้ง 2 เส้นทางที่ได้เบ็ด:
---     1) lotusDreadSwap (สลับระหว่างทำ Lotus) — ดู lotusDreadReady
---     2) rodMissionStep (เส้นทางปกติหลังปลด Lotus) — คืน action สุ่มแทน nil
---     ถ้าไม่ gate เส้นทางที่ 2 จะคืน nil -> nextStep ไหลไป stop gate (StopIsland = lotus)
---     แล้วจอดถาวร ไม่มีใครกลับมาสุ่มให้ = ไม่มีทางได้เบ็ดเลย
function dreadSkillsReady(data)
    local dm = lotusDreadMission()
    local isl = (dm and dm.farmIsland) or "island_fossil"
    return islandSkillsReady(data, isl)
end

--- ของครบสำหรับกด Complete dread หรือยัง (ปลา Mythical Fossil 1 ตัว + เงิน 10M)
---   missionCollect ใช้ได้แม้เควสต์ที่กำลังทำอยู่จะเป็น lotus:
---   missionRequirement(mode="rarity") อ่าน Progress เฉพาะเมื่อ Current.Id ตรงกับ questIdOf(m)
---   ไม่ตรง -> ใช้ nd.count แล้วสแกน Inventory.Fishes (ปลาที่ protectQuestFish ล็อกไว้ให้แล้ว)
function lotusDreadReady(data)
    local m = lotusDreadMission()
    if not (m and data) then return false end
    if missionDone(data, m) then return false end      -- ได้เบ็ดแล้ว = ไม่ต้องสลับ
    -- ⚠ ต้องได้สกิล Fossil (Legendary x2) ก่อน (ผู้ใช้สั่ง 2026-10-21)
    --   ระหว่างนี้ lotusMissionStep คืน nil -> nextStep ไปขั้น 5 สุ่มสกิลที่ Fossil ให้เอง
    if not dreadSkillsReady(data) then return false end
    if not missionCollect(data, m) then return false end
    local cost = missionCoin(data, m)
    return type(cost) == "number" and numOr(data.Coin, 0) >= cost
end

--- ยกเลิกเควสต์ Lotus (คืน true = ไม่มีเควสต์ค้างแล้ว)
---   ⚠ ปลอดภัยเพราะไอเทมไม่หาย: dialogue หน้า 13 + confirm message หน้า 36 เขียนตรง ๆ ว่า
---   "collected Snow Flowers and Magma Essences will stay in your inventory"
function lotusAbandon()
    if not (QuestCtl and QuestCtl.Cancel) then
        logWarn("[Lotus] QuestController ไม่มี Cancel")
        return false
    end
    if currentQuestId(fetchData()) ~= "unlock_island_7" then return true end
    local ok, res, err = pcall(function() return QuestCtl:Cancel("unlock_island_7") end)
    if not ok or not res then
        logWarn(("[Lotus] ยกเลิกเควสต์ไม่ผ่าน: %s"):format(tostring(err)))
        return false
    end
    -- รอให้ข้อมูลจริงว่าง ไม่ใช่รอเวลาตายตัว (แบบเดียวกับ clearOtherQuest)
    local cleared = pollUntil(function() return currentQuestId(fetchData()) == nil end, 2, 0.1)
    if not cleared then
        logWarn("[Lotus] ยกเลิกแล้วแต่ข้อมูลยังไม่ว่างใน 2s — รอรอบหน้า")
        return false
    end
    return true
end

--- รับ Lotus ใหม่แล้วไล่ Advance คืนตามของที่ถืออยู่
---   ⚠ Accept ใหม่รีเซ็ต Progress.Step กลับเป็น 1 เสมอ (dialogue หน้า 36:
---   "Your current step will reset") แต่ไอเทมยังอยู่ครบ
---   = ถ้าถือดอกครบแล้วต้อง Advance ทันที (dialogue หน้า 2 ทำแบบเดียวกัน)
function lotusResume(d)
    if lotusStepOf(d) == 1
       and itemCount(d, "snow_flower") >= lotusNeed("FlowerCount", 10) then
        if not questAdvance("unlock_island_7") then return false end
        d = fetchData() or d
    end
    if lotusStepOf(d) == 2
       and itemCount(d, "magma_essence") >= lotusNeed("EssenceCount", 10) then
        if not questAdvance("unlock_island_7") then return false end
    end
    return true
end

--- action สลับไปเอาเบ็ด Dread (คืน nil = ยังไม่พร้อม / เพิ่งล้มเหลวบ่อย)
---   ลำดับ: ไปใกล้ NPC dread -> ยกเลิก Lotus -> Accept+Complete dread -> รับ Lotus คืน
---   ⚠ ไปใกล้ NPC ก่อนยกเลิกเสมอ: ถ้าไปไม่ถึง เรายังถือเควสต์ Lotus อยู่ (ปลอดภัยสุด)
function lotusDreadSwap(data, m)
    if not lotusDreadReady(data) then
        S.lotusSwapFail = 0                 -- ของยังไม่ครบ = รีเซ็ตตัวนับล้มเหลว
        return nil
    end
    if (S.lotusSwapFail or 0) >= 2 then return nil end   -- กันวน Cancel/Accept ไม่จบ
    local dm = lotusDreadMission()
    return {
        key = "lotus:dreadSwap",
        label = "สลับไปเอา Dread Fish Rod แล้วกลับมารับเควสต์ Lotus",
        run = function()
            local d = fetchData() or data
            -- 1) ไปยืนใกล้ NPC dread (Fossil) ก่อน — ล้มเหลวตรงนี้ = ยังไม่ยกเลิกเควสต์
            if not S.tools.approachRodNpc(dm) then return false end
            -- 2) ยกเลิก Lotus (ไอเทมไม่หาย)
            if not lotusAbandon() then return false end
            -- 3) Accept + ปลดล็อกปลา + Complete (completeQuest ทำครบในตัว)
            if not completeQuest(dm, fetchData() or d) then
                S.lotusSwapFail = (S.lotusSwapFail or 0) + 1
                logWarn("[Lotus] ส่งเควสต์ dread ไม่ผ่าน — รับ Lotus คืนก่อน (ของยังอยู่ครบ)")
                if S.tools.approachUnlock("island_lotus")
                   and ensureQuestAccepted("unlock_island_7", fetchData()) then
                    lotusResume(fetchData() or d)
                end
                return false
            end
            -- 4) กลับไปรับ Lotus ใหม่ + ไล่ Advance คืน
            if not S.tools.approachUnlock("island_lotus") then return false end
            if not ensureQuestAccepted("unlock_island_7", fetchData()) then return false end
            S.lotusSwapFail = 0
            if not lotusResume(fetchData() or d) then return false end
            logWarn("[Lotus] ได้ Dread Fish Rod แล้ว — รับเควสต์ Lotus คืนเรียบร้อย")
            return true
        end,
    }
end

--- ตรวจว่าตอนนี้มี Rainbow Rain อยู่ไหม (อ่านจาก EventController ตัวจริง)
function lotusWeatherOn()
    local ec = Client and Client.GetController and Client.GetController("EventController")
    if not (ec and ec.GetActiveEvents) then return false end
    local ok, map = pcall(function() return ec:GetActiveEvents() end)
    return ok and type(map) == "table" and map["weather_rainbow_rain"] ~= nil
end

--- เตือนครั้งเดียว (ห้าม spam — nextStep ถูกเรียกทุกไม่กี่วินาที)
function lotusGemWarn(data, need)
    if S.lotusGemWarned then return end
    S.lotusGemWarned = true
    logWarn(("[Lotus] gems %d/%d — ยังกด Complete ไม่ได้ กำลังหา gems เพิ่ม (Raid / Daily Quest)")
        :format(numOr(data.Gem, 0), need))
end

--- ══════════════════════════════════════════════════
-- LOTUS — หา gems ให้ครบตอน Step 3 (ผู้ใช้สั่ง 2026-10-24)
-- ══════════════════════════════════════════════════
-- ปัญหาเดิม: Step 3 ที่ gems ยังไม่ครบ บอทคืน nil เฉย ๆ = ยืนรอ Aura/บอสเก็บ gems ให้
-- ตอนนี้ทำแบบเดียวกับสาย Forge: Raid ก่อน (181-363 gems/รอบ) แล้วค่อย Daily Quest
--
-- ⚠ Raid ทำได้ทั้งที่ถือเควสต์ Lotus อยู่ — ไม่มีข้อห้ามฝั่งเซิร์ฟ
-- ⚠ Daily Quest รับไม่ได้ถ้ามีเควสต์ปกติค้าง (npc_daily_quest.lua:167
--   "Finish or abandon your current quest first, then come back for a daily quest.")
--   -> ต้องยกเลิก Lotus ชั่วคราวแล้วรับคืน (แบบเดียวกับ lotusDreadSwap ที่ใช้อยู่จริง)
--   ปลอดภัยเพราะของไม่หาย (npc_unlock_island_7.lua:262-263 เขียนไว้ชัด)
--   และ lotusResume ไล่ Step 1 -> 2 -> 3 คืนได้ทันทีถ้าของครบ (มันครบอยู่แล้วถึงได้ Step 3)

--- อยู่ในช่วง "ต้องหา gems ให้ปลดล็อก Lotus" ไหม
---   = gems ยังไม่ถึง GemCost และ (ถือเควสต์ Lotus ที่ Step 3 หรือกำลัง detour อยู่)
function lotusGemPhase(data)
    if not data then return false end
    if islandUnlocked(data, "island_lotus") then return false end   -- ปลดแล้ว = ไม่ต้องหา gems แล้ว
    if numOr(data.Gem, 0) >= lotusGemCost() then return false end
    if S.lotusDetour == "daily" then return true end
    local m = activeMission(data)
    return m ~= nil and m.kind == "lotus" and lotusStepOf(data) == 3
end

--- action หา gems ระหว่างรอปลดล็อก Lotus (คืน nil = หาเพิ่มไม่ได้แล้ว -> ฟาร์มต่อ)
function lotusGemFarm(data)
    if not data then return nil end
    if numOr(data.Gem, 0) >= lotusGemCost() then return nil end
    -- 1) Raid: gems เยอะที่สุดและไม่ต้องแตะเควสต์ Lotus
    local rs = raidStep(data)
    if rs then return rs end
    -- 2) Raid ยังทำได้แต่ยังไม่มีตั๋ว (ขาดปลา Legendary) -> ปล่อยให้ไปฟาร์มปลา
    --    activeFarmIsland จะพาไปเกาะที่ยังขาด (raitTicketShort)
    if raidWanted(data) then return nil end
    -- 3) Raid ใช้ไม่ได้ (โควตาหมด / ไม่มีปลาแลกแล้ว) -> Daily Quest
    if S.lotusDetour == "daily" then return nil end
    if not (CONFIG.Daily and CONFIG.Daily.Enabled) then return nil end
    if dqDeckLeft(data) <= 0 then return nil end
    if not (QuestCtl and QuestCtl.Cancel) then return nil end
    -- ⚠ กัน detour วน: เพิ่งกลับมาถือ Lotus ไปแล้วแต่ gems ยังไม่พอ
    --   (เช่น เดลี่หมดกอง/โควตาวันหมด) -> อย่ายกเลิกซ้ำทันที ให้ฟาร์ม/รอ raid รอบใหม่ก่อน
    --   เดลี่รีเซ็ตที่ 86400 วิ = 1 ชม. คือช่วงพักที่ปลอดภัยและไม่ทำให้บอทหยุดทำงาน
    if (nowReal() - (S.lotusDetourEnd or 0)) < 3600 then return nil end
    return {
        key = "lotus:gemDetour",
        label = "ยกเลิก Lotus ชั่วคราว -> ไปฟาร์ม Daily Quest หา gems",
        run = function() return lotusGemDetour() end,
    }
end

--- ยกเลิก Lotus แล้วรับเดลี่ใบแรก (ของที่เก็บไว้ไม่หาย · lotusResume ไล่ Step คืนได้)
function lotusGemDetour()
    if not lotusAbandon() then return false end
    S.lotusDetour = "daily"
    S.lotusDetourAt = nowReal()
    logWarn("[Lotus] gems ยังไม่พอ + raid ใช้ไม่ได้ — ยกเลิก Lotus ชั่วคราวไปทำ Daily Quest (ของไม่หาย)")
    local a = dqStep(fetchData())
    if a and a.run then return a.run() end
    return true
end

--- กลับจาก detour: gems ครบ หรือไม่มีเดลี่ให้ทำต่อแล้ว -> รับ Lotus คืน
---   ⚠ ต้องรอให้เดลี่ใบที่ทำอยู่จบก่อน (ไม่งั้นใบนั้นค้างและไม่มีความคืบหน้า)
function lotusDetourReturn(data)
    if S.lotusDetour ~= "daily" then return nil end
    if not data then return nil end
    local enough = numOr(data.Gem, 0) >= lotusGemCost()
    local noMore = (dqActive(data) == nil) and (dqDeckLeft(data) <= 0)
    -- ⚠ ต้องรอเดลี่ใบที่ทำอยู่จบก่อน — รับเควสต์ปกติตอนเดลี่ค้างอยู่ไม่ชัวร์ว่าเซิร์ฟยอม
    --   (ทางกลับกันมีหลักฐานชัดว่าต้องการเดลี่ตอนเควสต์ปกติค้างไม่ได้)
    local idle = dqActive(data) == nil
    -- raid กลับมาใช้ได้อีก (โควตารีเซ็ตรายวัน) = ไม่ต้องทิ้งเควสต์ Lotus ต่อ
    --   ⚠ raid ทำงานได้ทั้งที่ถือ Lotus อยู่ -> กลับไปถือดีกว่า
    local raidBack = raidWanted(data) and not S.raidActive
    -- กันค้าง: ถ้าเดลี่ไม่ขยับเลยเกิน 30 นาที ให้กลับไปถือ Lotus ก่อน
    local stuck = (nowReal() - (S.lotusDetourAt or 0)) > 1800
    if not (raidBack or (idle and (enough or noMore)) or stuck) then return nil end
    if stuck and not (raidBack or (idle and (enough or noMore))) then
        logWarn("[Lotus] detour เดลี่นานเกิน 30 นาที — กลับไปถือเควสต์ Lotus ก่อน (กันค้าง)")
    end
    return {
        key = "lotus:gemReturn",
        label = "กลับไปรับเควสต์ Lotus",
        run = function()
            local d = fetchData() or data
            if not S.tools.approachUnlock("island_lotus") then return false end
            local ok, why = ensureQuestAccepted("unlock_island_7", d)
            if not ok then
                logWarn(("[Lotus] รับเควสต์คืนไม่สำเร็จ: %s"):format(tostring(why)))
                return false
            end
            S.lotusDetour = nil
            S.lotusDetourEnd = nowReal()
            return lotusResume(fetchData() or d)
        end,
    }
end

--- ยิง Advance แล้วยืนยันจากข้อมูลจริงว่า Step ขยับ (ไม่เดาเวลา)
function questAdvance(questId)
    if not (QuestCtl and QuestCtl.Advance) then
        logWarn("[Lotus] QuestController ไม่มี Advance")
        return false
    end
    local before = lotusStepOf(fetchData())
    local ok, res, err = pcall(function() return QuestCtl:Advance(questId) end)
    if not ok then
        logWarn(("[Lotus] Advance %s error: %s"):format(tostring(questId), tostring(res)))
        return false
    end
    if res ~= true then
        logWarn(("[Lotus] Advance %s ไม่ผ่าน: %s"):format(tostring(questId), tostring(err)))
        return false
    end
    local moved = pollUntil(function() return lotusStepOf(fetchData()) ~= before end, 2, 0.1)
    if not moved then
        logWarn("[Lotus] Advance ตอบ ok แต่ Step ยังไม่ขยับใน 2s — รอรอบหน้า")
        return false
    end
    return true
end

--- action เก็บดอกไม้ (nil = ไม่มีฝน / ยังไม่ปลด Snow / ไม่ใช่ Step 1)
function lotusFlowerAction(data)
    if not lotusWeatherOn() then return nil end
    if not islandUnlocked(data, "island_snow") then return nil end
    -- ต้องเป็นเควสต์นี้จริง ไม่งั้นดอกไม้ไม่เกิดฝั่ง client (SnowFlowerController.lua:26-33)
    if lotusStepOf(data) ~= 1 then return nil end
    return {
        key = "lotus:flower", quiet = true,
        label = ("เก็บ Snow Flower (%d/%d)"):format(
            itemCount(data, "snow_flower"), lotusNeed("FlowerCount", 10)),
        run = function() return collectOneFlower() end,
    }
end

--- ตำแหน่งดอกที่ควรเก็บตอนนี้ (nil = ยังไม่เกิด)
---   1) Progress.SpawnIndex -> child ชื่อ "<index>" ใน Workspace.World.SnowFlowerSpawns
---      (SnowFlowerController.BindFolder ใช้ชื่อตัวเลขเป็น index — setPart:212)
---   2) ProximityPrompt "CollectSnowFlower" ที่ controller สร้างให้ -> .Parent
function activeFlowerPart(data)
    local cur = data and data.Quest and data.Quest.Current
    local prog = type(cur) == "table" and cur.Progress
    local idx = type(prog) == "table" and tonumber(prog.SpawnIndex)
    local world = Workspace:FindFirstChild("World")
    local folder = world and world:FindFirstChild("SnowFlowerSpawns")
    if folder and idx and idx >= 1 then
        local p = folder:FindFirstChild(tostring(math.floor(idx)))
        if p and p:IsA("BasePart") then return p end
    end
    local prompt = Workspace:FindFirstChild("CollectSnowFlower", true)
    if prompt and prompt:IsA("ProximityPrompt") and prompt.Parent
       and prompt.Parent:IsA("BasePart") then
        return prompt.Parent
    end
    return nil
end

--- เก็บดอกไม้ทีละดอก (runStep ตั้ง S.traveling ไว้ตลอด run()
---   -> เก็บทีละดอก = mainLoop กลับไปเช็คบอสได้ทุก iteration ตามที่ผู้ใช้สั่ง)
function collectOneFlower()
    local d = fetchData()
    if not d or not lotusWeatherOn() then return true end    -- ฝนหยุด -> จบรอบ ไม่ retry
    if itemCount(d, "snow_flower") >= lotusNeed("FlowerCount", 10) then return true end
    if currentIslandId() ~= "island_snow" then return travelToIsland("island_snow") end

    local part = activeFlowerPart(d)
    if not part then return true end               -- ยังไม่เกิด (respawn) -> ปล่อยรอบหน้า
    local hrp = root()
    if hrp and (hrp.Position - part.Position).Magnitude > 6 then
        S.moving = true
        local reached = tweenDiveTo(part.Position, "snow-flower")
        S.moving = false
        if not reached then return false end
    end

    local before = itemCount(fetchData() or d, "snow_flower")
    -- ⚠ ยิง packet ตรง ไม่กด prompt: เป็นช่องทางเดียวกับที่เกมใช้
    --   (SnowFlowerController.lua:191-196 ยิงตอน prompt ถูก trigger) และไม่ต้องพึ่ง
    --   fireproximityprompt ของ executor ที่อาจไม่มี
    local okPkt, pkt = pcall(function()
        return (Stardust.Packet("Quest/CollectSnowFlower"))
            :Response(Stardust.Packet.Boolean8, Stardust.Packet.String)
    end)
    if not (okPkt and pkt) then
        logWarn("[Lotus] สร้าง packet เก็บดอกไม้ไม่ได้")
        return false
    end
    local res, why = pkt:Fire()
    if not res then
        logWarn(("[Lotus] เก็บดอกไม้ไม่ผ่าน: %s"):format(tostring(why)))
        return false
    end
    -- รอให้ยอดขยับจริง (กันนับซ้ำตอน replicate ช้า) — ไม่เกิน 1.5s
    pollUntil(function() return itemCount(fetchData() or d, "snow_flower") > before end, 1.5, 0.1)
    task.wait(0.75)                                -- QuestConfig.Island7.CollectCooldownSeconds
    return true
end

--- เครื่องเดินเควสต์ Lotus (3 สเต็ป)
function lotusMissionStep(data, m)
    local st = lotusStepOf(data)
    local needF = lotusNeed("FlowerCount", 10)
    local needE = lotusNeed("EssenceCount", 10)

    -- a) ยังไม่ได้รับเควสต์ -> ไปหา NPC แล้ว Accept (+ ไล่ Advance ถ้าถือของครบแล้ว)
    if not st then
        return {
            key = "quest:unlock_island_7",
            label = "รับเควสต์ Lotus",
            run = function()
                if not S.tools.approachUnlock("island_lotus") then return false end
                local ok, why = ensureQuestAccepted("unlock_island_7", fetchData() or data)
                if not ok then
                    logWarn(("[Lotus] รับเควสต์ไม่สำเร็จ: %s"):format(tostring(why)))
                    return false
                end
                return lotusResume(fetchData() or data)
            end,
        }
    end

    -- b) Step 1: ดอกไม้ (ฝนมาก่อนการสลับไปเอาเบ็ดเสมอ)
    if st == 1 then
        if itemCount(data, "snow_flower") >= needF then
            return {
                key = "lotus:advance1",
                label = "ส่ง Snow Flowers ให้ NPC Lotus",
                run = function()
                    if not S.tools.approachUnlock("island_lotus") then return false end
                    return questAdvance("unlock_island_7")
                end,
            }
        end
        local fl = lotusFlowerAction(data)
        if fl then return fl end
        local swap = lotusDreadSwap(data, m)
        if swap then return swap end
        return nil                                  -- ฟาร์มต่อ (เกาะที่ปลดสูงสุด = Fossil)
    end

    -- c) Step 2: Magma Essence (Advance ก่อนสลับ เพื่อไม่เสียสเต็ปฟรี)
    if st == 2 then
        if itemCount(data, "magma_essence") >= needE then
            return {
                key = "lotus:advance2",
                label = "ส่ง Magma Essence ให้ NPC Lotus",
                run = function()
                    if not S.tools.approachUnlock("island_lotus") then return false end
                    return questAdvance("unlock_island_7")
                end,
            }
        end
        local swap = lotusDreadSwap(data, m)
        if swap then return swap end
        if currentIslandId() ~= "island_volcano" then
            return {
                key = "travel:island_volcano",
                label = "ไป Volcanic เก็บ Magma Essence",
                run = function() return travelToIsland("island_volcano") end,
            }
        end
        return nil                                  -- อยู่ถูกเกาะแล้ว -> ตกปลาต่อ (ดรอปฝั่งเซิร์ฟ)
    end

    -- d) Step 3: จ่ายเหรียญ + gems (Complete)
    -- ⚠ ใช้ missionCoin(m) ไม่ใช่ islandCost ตรง ๆ — แตะ Progress.RequiredCoin ก่อนถ้ามี
    local cost = missionCoin(data, m) or islandCost("island_lotus")
    local gemNeed = lotusGemCost()
    -- จ่ายได้เดี๋ยวนี้ = ปิดเกาะก่อน (เป้าหมายหลัก) แล้ว dread ถูกจัดการต่อโดย rodMissionStep
    if type(cost) == "number"
       and numOr(data.Coin, 0) >= cost and numOr(data.Gem, 0) >= gemNeed then
        return {
            key = "mission:unlock_island_7",
            label = ("ปลดล็อก Lotus (%s + %d gems)"):format(compactNum(cost), gemNeed),
            run = function() return unlockIsland("island_lotus", fetchData() or data) end,
        }
    end
    local swap = lotusDreadSwap(data, m)
    if swap then return swap end
    local sellStep = needCoinsStep(data, cost, "ปลดล็อก Lotus")
    if sellStep then return sellStep end
    -- gems ยังไม่ครบ -> หาเพิ่มจริง ๆ (Raid ก่อน แล้วค่อย Daily Quest)
    --   ⚠ คืน nil = หาเพิ่มไม่ได้แล้ว (โควตาหมด/ไม่มีเดลี่) -> ฟาร์มต่อตามปกติ
    local gemStep = lotusGemFarm(data)
    if gemStep then return gemStep end
    if numOr(data.Gem, 0) < gemNeed then
        lotusGemWarn(data, gemNeed)                 -- เตือนครั้งเดียว ไม่ค้าง action
    end
    return nil                                      -- เงิน/gems ยังไม่พอ -> ฟาร์มต่อ
end

--- ══════════════════════════════════════════════════
-- STEP MACHINE — คิด "ทำอะไรต่อ" จากสถานะจริงทุกครั้งที่ถูกเรียก
-- ══════════════════════════════════════════════════
--- ภารกิจที่ยังไม่เสร็จ + พร้อมไปตกที่เกาะเป้าหมายของมันหรือยัง
---   (ถูกลบไปแล้ว — เดิมมีเงื่อนไข "ต้องมีเบ็ด + สกิล Legendary ก่อน" ทับบน activeFarmIsland
---    ทำให้ฟาร์มที่เกาะหลักทั้งที่ปลดล็อกเกาะใหม่แล้ว ตอนนี้กติกาเดียวคือเกาะที่ปลดสูงสุด)
--- ══════════════════════════════════════════════════
-- FORGE — Godslayer Rod V2 (RodForgeConfig.Order)
-- ══════════════════════════════════════════════════
-- ⚠ ทุกฟังก์ชันในบล็อกนี้เป็น global (ไม่ใช่ local) เพราะไฟล์ชนเพดาน 200 local แล้ว
--
-- ห่วงโซ่ 4 เบ็ด + ของที่ใช้ (RodForgeConfig.lua):
--   1 godslayer_rod_v1   Rarities x5 (C/U/R/E/L ตัวเบาสุด)        20,000,000 coin
--   2 golden_beast_rod   Lotus Legendary x3                        200 gem
--   3 diamond_dragon_rod Jungle x3 + Desert x3 Legendary           200 gem + Mythical book 1
--   4 godslayer_rod_v2   ปลา kind == "Boss" x5                     500 gem
--
-- ⚠ การ forge "กินเบ็ดก่อนหน้า" — หลัง forge golden_beast สำเร็จ v1 จะหายจาก data.Rods
--   ถ้าหา "ตัวแรกที่ยังไม่มี ForgedStats" ตรง ๆ จะวนกลับไป forge v1 ไม่จบ
--   วิธีที่ถูก: หา index ของเบ็ดที่ forge แล้ว "ล่าสุด" ใน Order แล้วเอา index+1

--- เบ็ดตัวถัดไปที่ต้อง forge — nil = ครบทั้งห่วงโซ่แล้ว
function forgeRodId(data)
    if not (RodForgeCfg and RodModifiers) then return nil end
    local rods = type(data) == "table" and data.Rods or nil
    if type(rods) ~= "table" then return nil end
    local last = 0
    for i, id in ipairs(RodForgeCfg.Order) do
        local ok, fs = pcall(function() return RodModifiers.GetForgedStats(id, rods[id]) end)
        if ok and fs ~= nil then last = i end
    end
    return RodForgeCfg.Order[last + 1]
end

--- ผลรวม gemCost ของเบ็ดที่ยังไม่ forge (ใช้เป็น gem reserve ของ Aura)
---   = gems ทั้งหมดที่สาย Forge ยังต้องใช้ เหลือจากเบ็ดตัวปัจจุบันไปจนจบห่วงโซ่
function forgeGemNeed(data)
    if not (RodForgeCfg and RodForgeCfg.Order) then return 0 end
    local nxt = forgeRodId(data)
    if not nxt then return 0 end
    local startIdx = nil
    for i, id in ipairs(RodForgeCfg.Order) do
        if id == nxt then startIdx = i break end
    end
    if not startIdx then return 0 end
    local sum = 0
    for i = startIdx, #RodForgeCfg.Order do
        local recipe = RodForgeCfg.Recipes[RodForgeCfg.Order[i]]
        if type(recipe) == "table" then
            sum = sum + (tonumber(recipe.gemCost) or 0)
        end
    end
    return sum
end

--- สถานะ Mythical book ที่ forge Diamond Dragon ต้องใช้
---   คืน "ready" (มีเล่มที่ยังไม่ถูกใส่) | "equipped" (มีแต่ใส่ในเบ็ดอยู่) | "missing" (ไม่มีเลย)
---
--- ⚠ RodForgeRules.findMythicalBook (RodForgeRules.lua:167-183) เลือก "เล่ม Mythical
---   ตัวแรกตามตัวอักษรที่ skillBookAvailability.available > 0"
---   = เงื่อนไขจริงคือ "มีเล่ม Mythical อย่างน้อย 1 เล่มที่ยังไม่ถูกใส่ในเบ็ดไหน"
---   ไม่ผูกกับสกิลตัวใดตัวหนึ่ง — เล่มไหนก็ได้
function forgeBookState(data)
    -- ⚠ ไม่บังคับ SkillBookAvail: availableSkillCopies มี fallback คำนวณเองอยู่แล้ว
    --   (บังคับไว้จะทำให้ "missing" ตลอดเมื่อโมดูลของเกมหาย/ยังไม่โหลด)
    if not (Catalog and Catalog.Skill) then return "missing", nil end
    local inv = invOf(data)
    local books = (type(inv) == "table" and inv.Books) or {}
    local best, bestScore = nil, math.huge
    for skillId, n in pairs(books) do
        if type(n) == "number" and n > 0 then
            local meta = nil
            if Catalog.Skill.GetById then
                pcall(function() meta = Catalog.Skill.GetById(skillId) end)
            end
            if type(meta) == "table" and meta.rarity == "Mythical" then
                local avail = availableSkillCopies(data, skillId)
                if avail > 0 then return "ready", skillId end
                -- ใส่ในเบ็ดอยู่ -> เก็บตัวที่ "แย่สุด" ไว้ถอด (เสียผลกระทบน้อยสุด)
                local sc = skillPriority(meta)
                if sc < bestScore then best, bestScore = skillId, sc end
            end
        end
    end
    if best then return "equipped", best end
    return "missing", nil
end

--- uid ของปลาที่ "ควรล็อก" สำหรับเบ็ดตัวนี้
--- ⚠ ต่างจาก RodForgeRules.selectFish: ที่นี่นับปลาที่ล็อกอยู่ด้วย
---   เพราะ selectFish ข้ามปลา locked (RodForgeRules.lua:89) — ถ้าเราไม่นับ ล็อกแล้วจะดูเหมือนขาด
---   แล้วไปล็อกซ้ำตัวอื่นไม่จบ
--- ⚠ ต้อง mirror กติกาของ selectFish ให้ตรงทุกโหมด:
---   Rarities           = C/U/R/E/L ตัวเบาสุดของแต่ละ rarity (ตัด Divine/Mythical ออก)
---   Island7Legendary   = Lotus Legendary N ตัวเบาสุด
---   Islands23Legendary = Jungle N/2 + Desert N/2 (assert N เป็นเลขคู่)
---   Boss               = ปลาที่ Catalog บอก kind == "Boss" N ตัวเบาสุด
function forgeWantUids(data, rodId)
    local recipe = RodForgeCfg and RodForgeCfg.Recipes[rodId]
    if type(recipe) ~= "table" then return {} end
    local inv = invOf(data)
    local fishes = (type(inv) == "table" and inv.Fishes) or {}
    local kind = recipe.fishKind
    local quota = tonumber(recipe.fishCount) or 0

    local function metaOf(f)
        if not (Catalog and Catalog.Fish and Catalog.Fish.GetById) then return nil end
        local m = nil
        pcall(function() m = Catalog.Fish.GetById(f.fishId) end)
        return m
    end
    local function weightOf(f)
        return (type(f.weight) == "number") and f.weight or math.huge
    end

    local groups = {}
    local function add(k, uid, f)
        groups[k] = groups[k] or {}
        groups[k][#groups[k] + 1] = { uid = uid, weight = weightOf(f) }
    end

    local lotusSet, jungleSet, desertSet
    if kind == "Island7Legendary" then
        lotusSet = islandFishIds("island_lotus")
    elseif kind == "Islands23Legendary" then
        jungleSet = islandFishIds("island_jungle")
        desertSet = islandFishIds("island_desert")
    end

    -- ⚠ uid คือ "คีย์" ของตาราง ไม่ใช่ฟิลด์ — RodForgeRules.selectFish ก็ใช้ i6 (คีย์)
    --   (RodForgeRules.lua:88-98: `for i6, i7 in Fishes_2` แล้ว `uid = i6`)
    for uid, f in pairs(fishes) do
        if type(f) == "table" and type(f.fishId) == "string" and type(uid) == "string" then
            local m = metaOf(f)
            if m then
                if kind == "Rarities" then
                    if m.rarity ~= "Divine" and m.rarity ~= "Mythical" then add(m.rarity, uid, f) end
                elseif kind == "Island7Legendary" then
                    if m.rarity == "Legendary" and lotusSet[f.fishId] then add("lotus", uid, f) end
                elseif kind == "Islands23Legendary" then
                    if m.rarity == "Legendary" then
                        if jungleSet[f.fishId] then add("jungle", uid, f)
                        elseif desertSet[f.fishId] then add("desert", uid, f) end
                    end
                elseif kind == "Boss" then
                    if m.kind == "Boss" then add("boss", uid, f) end
                end
            end
        end
    end

    local want = {}
    local function take(list, n)
        if not list or n <= 0 then return end
        table.sort(list, function(a, b)
            if a.weight ~= b.weight then return a.weight < b.weight end
            return a.uid < b.uid
        end)
        for i = 1, math.min(#list, n) do want[list[i].uid] = true end
    end
    if kind == "Rarities" then
        for _, r in ipairs({ "Common", "Uncommon", "Rare", "Epic", "Legendary" }) do
            take(groups[r], 1)
        end
    elseif kind == "Island7Legendary" then
        take(groups.lotus, quota)
    elseif kind == "Islands23Legendary" then
        local half = math.floor(quota / 2)
        take(groups.jungle, half)
        take(groups.desert, half)
    elseif kind == "Boss" then
        take(groups.boss, quota)
    end
    return want
end

--- ล็อกปลาที่เบ็ดตัวปัจจุบันต้องใช้ (เรียกทุก 1 วิ จาก mainLoop คู่กับ protectQuestFish)
---   ⚠ "ล็อกอย่างเดียว" — ไม่ปลดของที่เกินให้อัตโนมัติ
---     การปลดผิดตัวแพงกว่าการกินช่อง satchel 2-3 ช่องมาก
---     (ของที่เกินจะถูกปลดตอน releaseForgeFish ก่อนยิง forge อยู่แล้ว)
function forgeFishLock()
    if not (CONFIG.Forge and CONFIG.Forge.Enabled) then return false end
    local data = fetchData()
    if not data then return false end
    if not islandUnlocked(data, CONFIG.Forge.AfterIsland) then return false end
    if activeMission(data) ~= nil then return false end
    local rodId = forgeRodId(data)
    if not rodId then return false end
    if not (SellController and SellController.ToggleLock) then return false end

    local want = forgeWantUids(data, rodId)
    local did = 0
    -- ⚠ uid = คีย์ของ Inventory.Fishes (ไม่ใช่ฟิลด์) — ดูหมายเหตุที่ forgeWantUids
    for uid, f in pairs((invOf(data) or {}).Fishes or {}) do
        if type(f) == "table" and type(uid) == "string"
           and want[uid] and f.locked ~= true and not S.lockedUids[uid] then
            local ok, st, now = pcall(function() return SellController:ToggleLock(uid) end)
            if ok and st == 0 and now == true then
                S.lockedUids[uid] = true
                did = did + 1
            end
        end
    end
    return did > 0
end

--- ปลดล็อกปลาทั้งหมดของเบ็ดตัวนี้ ก่อนยิง forge
--- ⚠ จำเป็น: RodForgeRules.selectFish ข้ามปลาที่ locked == true (RodForgeRules.lua:89)
---   ถ้ายังล็อกอยู่ GetStatus.ready ไม่มีทางเป็น true
function releaseForgeFish(data, rodId)
    if not (SellController and SellController.ToggleLock) then return false end
    local want = forgeWantUids(data or fetchData(), rodId)
    local toggled = {}
    local t0 = nowReal()
    while nowReal() - t0 < 3 do
        local d = fetchData() or data
        local left = 0
        for uid, f in pairs((invOf(d) or {}).Fishes or {}) do
            if type(f) == "table" and f.locked == true and want[uid]
               and type(uid) == "string" and not toggled[uid] then
                left = left + 1
                local ok, st, now = pcall(function() return SellController:ToggleLock(uid) end)
                if ok and st == 0 and now == false then
                    toggled[uid] = true
                    S.lockedUids[uid] = nil
                end
            end
        end
        if left == 0 then return true end
        task.wait(0.25)
    end
    return false
end

--- เดินไป NPC ตาชั่งที่ Lotus (server ตรวจระยะเอง — ใช้ตัวช่วยเดียวกับเควสต์เบ็ด)
function forgeApproach()
    local cfg = CONFIG.Forge
    return S.tools.approachRodNpc({ npcIsland = cfg.NpcIsland, npcId = cfg.NpcId })
end

--- ยิง RodForge/Forge ตรง ๆ
---   RodForgeController._Forge() (RodForgeController.lua:509-547) เช็คแค่ GetStatus(...).ready
---   แล้วยิง u87 = (Packet("RodForge/Forge", Packet.String)):Response(Boolean8, String)
---   ไม่มีด่าน UI/Confirm ฝั่ง server -> ยิงจากสคริปต์ได้เลย
function forgeFire(rodId)
    if not (Stardust and Stardust.Packet) then
        logWarn("[Forge] ไม่มี Stardust.Packet — ยิง forge ไม่ได้")
        return false
    end
    if not forgeApproach() then
        logWarn(("[Forge] ไปยืนใกล้ %s ไม่ได้ — ยังไม่ยิง forge"):format(tostring(CONFIG.Forge.NpcId)))
        return false
    end
    local okPkt, pkt = pcall(function()
        return (Stardust.Packet("RodForge/Forge", Stardust.Packet.String))
            :Response(Stardust.Packet.Boolean8, Stardust.Packet.String)
    end)
    if not (okPkt and pkt) then
        logWarn("[Forge] สร้าง packet RodForge/Forge ไม่ได้")
        return false
    end
    -- pkt:Fire คืน (Boolean8, String) — ต้องจับทั้งสองค่า จึงห่อด้วยตาราง
    local ok, r = pcall(function()
        local a, b = pkt:Fire(rodId)
        return { ok = a, text = b }
    end)
    if not ok then
        logWarn(("[Forge] ยิง forge %s ไม่ผ่าน: %s"):format(tostring(rodId), tostring(r)))
        return false
    end
    if r.ok == false then
        logWarn(("[Forge] server ปฏิเสธ forge %s: %s"):format(tostring(rodId), tostring(r.text)))
        return false
    end
    -- ⚠ ไม่เชื่อคำตอบอย่างเดียว — ยืนยันจาก ForgedStats ที่ replicate กลับมาจริง
    local got = pollUntil(function()
        local d = fetchData()
        local ok2, fs = pcall(function()
            return RodModifiers.GetForgedStats(rodId, d and d.Rods and d.Rods[rodId])
        end)
        return ok2 and fs ~= nil
    end, 8, 0.2)
    if not got then
        logWarn(("[Forge] server ตอบรับแล้วแต่ %s ยังไม่มี ForgedStats ใน 8s"):format(tostring(rodId)))
        return false
    end
    -- ปลาที่ถูกกินไปแล้ว = uid เก่าใช้ไม่ได้อีก
    S.lockedUids = {}
    S.forgeBook  = nil
    S.forgeWarned = {}
    logWarn(("[Forge] ✓ forge %s สำเร็จ"):format(tostring(rodId)))
    return true
end

--- ถอด Mythical book ออกจากเบ็ดทุกใบที่ถือมันอยู่ แล้วจองไว้ (กัน tryEquipAllSkills ใส่กลับ)
--- ⚠ EquipMoveset ไม่มีพารามิเตอร์ rodId — server แก้ได้แค่เบ็ดที่ติดตั้งอยู่
---   ต้อง switchToRod(rid) ก่อนแล้วค่อยยิงค่าว่าง (แบบเดียวกับ unequipRodSkills)
function forgeUnequipBook(skillId)
    S.forgeBook = skillId
    local where = S.tools.whereSkillLives(fetchData(), skillId)
    local any = false
    for rid, slot in pairs(where) do
        any = true
        if not switchToRod(rid) then
            logWarn(("[Forge] สลับไป %s เพื่อถอด %s ไม่ได้"):format(tostring(rid), tostring(skillId)))
            return false
        end
        local idx = tonumber(slot) or slot
        local ok, res = pcall(function() return EquipCtl.EquipMoveset:Fire("", idx) end)
        if not ok then
            logWarn(("[Forge] ยิง EquipMoveset ถอด %s ไม่ผ่าน: %s"):format(tostring(skillId), tostring(res)))
            return false
        end
        local key = ("Slot%d"):format(tonumber(idx) or 0)
        local cleared = pollUntil(function()
            local d = fetchData()
            local rd = d and type(d.Rods) == "table" and d.Rods[rid]
            local sl = (type(rd) == "table" and rd.BookSlots) or nil
            return type(sl) == "table" and sl[key] ~= skillId
        end, 3, 0.1)
        if not cleared then
            logWarn(("[Forge] ถอด %s จาก %s ไม่สำเร็จ (server ตอบ %s)")
                :format(tostring(skillId), tostring(rid), tostring(res)))
            return false
        end
        logWarn(("[Forge] ถอด %s ออกจาก %s แล้ว — เก็บไว้ให้ forge"):format(tostring(skillId), tostring(rid)))
    end
    if not any then
        -- ไม่ได้ใส่ที่ไหนอยู่แล้ว = พร้อมใช้
        return true
    end
    -- คืนเบ็ดที่ดีที่สุดให้ผู้เล่น
    ensureBestLoadout()
    return true
end

--- ไม่มีเล่ม Mythical เลย: ลองสุ่มสกิลด้วยงบจำกัด (fallback)
---   ⚠ 0.5% Mythical + pity 500 ⇒ งบ 2M (~25 สุ่ม) โอกาสได้จริงต่ำมาก
---   ทางที่ถูกคือผู้ใช้มีเล่มอยู่แล้ว — ฟังก์ชันนี้แค่ไม่ปล่อยให้ค้างเงียบ ๆ
function forgeBookAcquire(data)
    local budget = tonumber(CONFIG.Forge and CONFIG.Forge.BookGachaBudget) or 0
    if budget <= 0 then return nil end
    if (S.forgeSpent or 0) >= budget then return nil end
    if not (GachaCtl and GachaCtl.GetQuote) then return nil end
    local okQ, q = pcall(function() return GachaCtl.GetQuote:Fire(1) end)
    if not (okQ and type(q) == "table" and q.ok) then return nil end
    local cost = tonumber(q.coin_cost) or 0
    if numOr(q.credits_available, 0) > 0 then cost = 0 end
    if (S.forgeSpent or 0) + cost > budget then return nil end
    if numOr(data and data.Coin, 0) < cost then return nil end
    return {
        key   = "forge:book-gacha",
        quiet = true,
        label = ("สุ่มสกิลหาสกิล Mythical (งบ %s/%s)")
            :format(compactNum(S.forgeSpent or 0), compactNum(budget)),
        run = function()
            local okR = rollSkillOnce(data)
            if okR then S.forgeSpent = (S.forgeSpent or 0) + cost end
            return okR
        end,
    }
end

--- ตัวตัดสินใจหลักของสาย Forge
---   คืน action ถ้ามีอะไรต้อง "ทำ" · คืน nil = ให้ mainLoop ไปฟาร์ม (เงิน/ปลาไหลเข้ามาเอง)
---
--- ลำดับภายใน (ตามที่ผู้ใช้สั่ง):
---   1) Mythical book (Diamond Dragon ต้องใช้) — มี/ถอด/ไม่มี
---   2) ปลาของเบ็ดตัวปัจจุบัน — ยังไม่ครบ = ปล่อยให้ฟาร์ม
---   3) gems — ไม่พอ = raid แล้วค่อย daily quest
---   4) coins — ไม่พอ = ฟาร์มที่ Lotus (เงินฟาร์มหลังสุดเสมอ)
---   5) ครบทุกอย่าง = ปลดล็อกปลา -> ยิง forge
function forgeStep(data)
    if not (CONFIG.Forge and CONFIG.Forge.Enabled) then return nil end
    if not (RodForgeCfg and RodForgeRules) then return nil end
    if not data then return nil end
    -- ⚠ S.forgeWarned ต้องมีก่อนแตะ (entry point อื่นอาจเรียกก่อน S ถูกสร้างครบ)
    if type(S.forgeWarned) ~= "table" then S.forgeWarned = {} end
    if not islandUnlocked(data, CONFIG.Forge.AfterIsland) then return nil end
    -- ⚠ ภารกิจก่อนเสมอ — กันแย่งเงิน 10,000,000 ของ dread_fish_rod
    if activeMission(data) ~= nil then return nil end

    local rodId = forgeRodId(data)
    if not rodId then return nil end
    local recipe = RodForgeCfg.Recipes[rodId]
    local st = nil
    do
        local ok, r = pcall(function() return RodForgeRules.GetStatus(data, rodId) end)
        if ok then st = r end
    end
    if type(recipe) ~= "table" or type(st) ~= "table" then return nil end

    -- ── 0) เตือน band ดาเมจครั้งเดียวต่อเบ็ด ─────────────────────────
    --   ⚠ ดัมป์ให้เบ็ด 2-4 อยู่ที่ 110-120 ซึ่งต่ำกว่า Dread Fish Rod (52,897) มาก
    --     ค่าที่ควรเป็น (ตาม RodForgeRules.spec) คือหลักหมื่น-แสน
    --     สคริปต์ไม่บล็อก — แค่บอกให้ไปตรวจที่หน้า Forge ในเกมก่อนจ่าย 20M
    if not S.forgeWarned["band:" .. rodId] then
        S.forgeWarned["band:" .. rodId] = true
        local d0 = type(recipe.damage) == "table" and recipe.damage[1] or nil
        logWarn(("[Forge] %s — band ดาเมจในคอนฟิก %s..%s (เบ็ด forge 2-4 ในดัมป์ = 110-120 "
            .. "ซึ่งอ่อนกว่า Dread Fish Rod 52,897 มาก — ตรวจที่หน้า Forge ก่อนจ่าย 20M)")
            :format(tostring(rodId),
                tostring(type(d0) == "table" and d0.min or "?"),
                tostring(type(d0) == "table" and d0.max or "?")))
    end

    -- ── 1) Mythical book (เฉพาะเบ็ดที่ต้องใช้) ───────────────────────
    if (tonumber(recipe.mythicalBookCount) or 0) > 0 and st.bookId == nil then
        local state, skillId = forgeBookState(data)
        if state == "equipped" and skillId then
            return {
                key   = "forge:book-unequip:" .. rodId,
                label = ("ถอด %s ออกจากเบ็ดเพื่อให้ forge ใช้ได้"):format(tostring(skillId)),
                run   = function() return forgeUnequipBook(skillId) end,
            }
        end
        if state == "missing" then
            local step = forgeBookAcquire(data)
            if step then return step end
            if not S.forgeWarned["book"] then
                S.forgeWarned["book"] = true
                logWarn("[Forge] ไม่มีสกิล Mythical เลย — สาย Forge หยุดที่ Diamond Dragon "
                    .. "(ต้องมีเล่ม Mythical 1 เล่มที่ยังไม่ถูกใส่ในเบ็ด)")
            end
            return nil
        end
    end

    -- ── 2) ปลายังไม่ครบ -> ปล่อยให้ฟาร์ม (activeFarmIsland พาไปเกาะที่ถูก) ──
    if (tonumber(st.fishCount) or 0) < (tonumber(recipe.fishCount) or 0) then
        return nil
    end

    -- ── 3) gems ยังไม่พอ -> raid (ถ้าลงครบโควตาแล้ว daily quest ทำงานต่อเอง) ──
    if not st.hasGem then
        local step = raidStep(data)
        if step then return step end
        return nil
    end

    -- ── 4) coins ยังไม่พอ -> ฟาร์มที่ Lotus (เงินฟาร์มหลังสุด) ────────
    if not st.hasCoin then return nil end

    -- ── 5) พร้อมยิง ─────────────────────────────────────────────────
    if not st.ready then return nil end
    return {
        key    = "forge:fire:" .. rodId,
        label  = ("Forge %s"):format(tostring(rodId)),
        newRod = rodId,     -- ให้ ensureBestLoadout รอข้อมูล replicate
        run    = function()
            local d = fetchData() or data
            if not releaseForgeFish(d, rodId) then
                logWarn(("[Forge] ปลดล็อกปลาของ %s ไม่ครบ — ยังไม่ยิง forge"):format(tostring(rodId)))
                return false
            end
            local d2 = fetchData() or d
            local st2 = nil
            local ok2, r2 = pcall(function() return RodForgeRules.GetStatus(d2, rodId) end)
            if ok2 then st2 = r2 end
            if not (type(st2) == "table" and st2.ready) then
                logWarn(("[Forge] หลังปลดล็อกแล้ว GetStatus ยังไม่ ready (ปลา %s/%s)")
                    :format(tostring(st2 and st2.fishCount or "?"), tostring(recipe.fishCount)))
                return false
            end
            return forgeFire(rodId)
        end,
    }
end

--- ══════════════════════════════════════════════════
-- RAID — แหล่ง gems หลักของสาย Forge (เต็มวง: แลกตั๋ว -> ลงแท่น -> ตกปลา -> Claim)
-- ══════════════════════════════════════════════════
-- ⚠ ทุกฟังก์ชันเป็น global (เพดาน local 200 ตัว)
--
-- กติกาจริง (RaidConfig.lua):
--   ตั๋ว 1 ใบ = Legendary 2 ตัวจากแต่ละเกาะใน Exchange.Islands
--             = starter + jungle + desert + snow = 8 ตัว
--   แลกได้ 5 ใบ/วัน · ลงได้ 3 รอบ/วัน · รอบละ 20 นาที (RunSeconds 1200)
--   gems ที่ได้ขึ้นกับจำนวนคนในทีม (Profiles): 1 คน ≈181 · 2 ≈245 · 3 ≈294 · 4 ≈363
--
-- ⚠ ใน raid เกม "ปิด auto-fishing เอง" (FishingController.TryAutoCast:1976-1984
--   return ทิ้งเมื่อ GetRaidRegionId() ~= "") => ต้องเหวี่ยงด้วยลูปของเราเอง
--   ลูปเดิมใช้ได้เลย (HP-based, packet เดิม) แต่จุดเหวี่ยงต้องหาใหม่
--   เพราะ GetCurrentIslandId() = "" ใน raid -> GetWaterY("") = SEA_LEVEL 3 ซึ่งผิด

--- true = ต้องการ gems เพิ่ม และยังลง raid ได้อีก
---   ⚠ 2 แหล่งความต้องการ gems: (1) ปลดล็อก Lotus Step 3  (2) สาย Forge (Godslayer V2)
---     เดิมฟังก์ชันนี้ดูแค่สาย Forge ทำให้ช่วง "รอ gems ปลดเกาะ Lotus" ไม่เคยลง raid เลย
---     (ผู้ใช้สั่ง 2026-10-24: ต้องหา gems ได้เหมือนตอนทำเบ็ด)
---   ⚠ สาย Forge ยังต้อง gate activeMission == nil เหมือนเดิม — กันแย่งเงิน 10M ของ dread
function raidWanted(data)
    if not data then return false end
    if not (RaidCfg and RaidWindow) then return false end

    local need
    if lotusGemPhase(data) then
        -- ช่วงปลดล็อก Lotus: ไม่มีข้อห้ามเรื่องภารกิจค้าง (raid ไม่สนใจ Quest.Current)
        --   และไม่ต้องพึ่ง CONFIG.Forge — raid เป็นแหล่ง gems ของการปลดเกาะเอง
        need = lotusGemCost() - numOr(data.Gem, 0)
    else
        if not (CONFIG.Forge and CONFIG.Forge.Enabled) then return false end
        if not islandUnlocked(data, CONFIG.Forge.AfterIsland) then return false end
        if activeMission(data) ~= nil then return false end
        local rodId = forgeRodId(data)
        if not rodId then return false end
        local recipe = RodForgeCfg.Recipes[rodId]
        if type(recipe) ~= "table" then return false end
        need = (tonumber(recipe.gemCost) or 0) - numOr(data.Gem, 0)
    end
    if need <= 0 then return false end

    local raid = data.Raid or {}
    local now = nowReal()
    local runs = RaidWindow.Used(raid.RunWindowStart or 0, raid.RunCount or 0, now) or 0
    local exch = RaidWindow.Used(raid.ExchangeWindowStart or 0, raid.ExchangeCount or 0, now) or 0
    -- ⚠ ตั๋วอย่างเดียวไม่ได้ gems — ต้องมี "รอบ" เหลือด้วย
    --   ถ้าเหลือแต่โควตาแลกแต่ลงรอบไม่ได้ raidWanted ต้องเป็น false
    --   ไม่งั้น raidStep จะคืน raid:join ทุก 3 วิ แล้วเซิร์ฟปฏิเสธ DailyLimit ไม่จบ
    if runs >= (RaidCfg.RunsPerWindow or 3) then return false end
    if itemCount(data, RaidCfg.TicketId or "raid_ticket") >= 1 then return true end
    return exch < (RaidCfg.ExchangesPerWindow or 5)
end

--- เกาะที่ยังขาดปลา Legendary สำหรับแลกตั๋ว — nil = แลกได้แล้ว
--- ⚠ นับเฉพาะปลาที่ locked ~= true เพราะ CraftController ใช้ QuestFishRules.Count
---   ซึ่งข้ามปลาที่ล็อกอยู่ (QuestFishRules.lua) — ล็อกไว้ = แลกตั๋วไม่ได้
function raidTicketShort(data)
    if not (RaidCfg and type(RaidCfg.Exchange) == "table") then return nil end
    local ex = RaidCfg.Exchange
    local need = tonumber(ex.PerIsland) or 2
    local rarity = ex.Rarity or "Legendary"
    local fishes = (invOf(data) or {}).Fishes or {}
    for _, islId in ipairs(ex.Islands or {}) do
        local set = islandFishIds(islId)
        local n = 0
        for _, f in pairs(fishes) do
            if type(f) == "table" and f.locked ~= true and set[f.fishId]
               and fishRarity(f.fishId) == rarity then n = n + 1 end
        end
        if n < need then return islId end
    end
    return nil
end

--- แลกตั๋วที่ Ticket Keeper (ต้องมีปลาครบ 8 ตัว)
function raidExchangeTicket()
    if not (RaidPkts and RaidPkts.ExchangeTicket) then return false end
    local npcId = (RaidCfg.InteractiveIds or {}).TicketNpc or CONFIG.Forge.TicketNpc
    local radius = tonumber(RaidCfg.NpcRadius) or 15
    if not S.tools.approachNpcAnywhere(npcId, radius) then
        logWarn("[Raid] ไปหา Ticket Keeper ไม่ได้ (NPC ยังไม่ stream)")
        return false
    end
    local before = itemCount(fetchData(), RaidCfg.TicketId or "raid_ticket")
    local ok, st = pcall(function() return RaidPkts.ExchangeTicket:Fire() end)
    if not ok then
        logWarn(("[Raid] ยิง ExchangeTicket ไม่ผ่าน: %s"):format(tostring(st)))
        return false
    end
    local OK = (RaidEnums and RaidEnums.Status and RaidEnums.Status.Ok) or 0
    if st ~= OK then
        logWarn(("[Raid] แลกตั๋วไม่ผ่าน (status %s)"):format(tostring(st)))
        return false
    end
    local got = pollUntil(function()
        return itemCount(fetchData(), RaidCfg.TicketId or "raid_ticket") > before
    end, 5, 0.2)
    if got then logWarn("[Raid] ✓ ได้ Raid Ticket") end
    return got ~= nil
end

--- หาแท่นใน Workspace.Raids ที่ยังว่าง แล้วเดินเข้าไปในรัศมี PadJoinRadius ก่อนยิง JoinPad
---   ⚠ server ตรวจระยะ (PadJoinRadius = 18) — ยิงจากที่ไกลไม่ผ่าน
function raidJoinPad()
    if not (RaidPkts and RaidPkts.JoinPad) then return false end
    local folder = Workspace:FindFirstChild("Raids")
    if not folder then
        logWarn("[Raid] ไม่มี Workspace.Raids — ยังลง raid ไม่ได้")
        return false
    end
    local hrp = root()
    if not hrp then return false end
    local radius = tonumber(RaidCfg.PadJoinRadius) or 18
    local waiting = (RaidEnums and RaidEnums.Phase and RaidEnums.Phase.Waiting) or 0
    local best, bestD = nil, math.huge
    for _, pad in ipairs(folder:GetChildren()) do
        local ph = pad:FindFirstChild("HumanoidRootPart")
        local phase = pad:GetAttribute("RaidPhase")
        if ph and ph:IsA("BasePart") and (type(phase) ~= "number" or phase == waiting) then
            local d = (ph.Position - hrp.Position).Magnitude
            if d < bestD then best, bestD = ph, d end
        end
    end
    if not best then
        logWarn("[Raid] ไม่มีแท่นว่างให้ลง (ทุกแท่นไม่ใช่ Waiting)")
        return false
    end
    if bestD > radius then
        S.moving = true
        local reached = tweenDiveTo(best.Position, "raid-pad")
        S.moving = false
        if not reached then return false end
        hrp = root()
        if not hrp or (hrp.Position - best.Position).Magnitude > radius then
            logWarn(("[Raid] ไปยืนบนแท่นไม่ได้ (ห่าง %.1f > %.1f)"):format(bestD, radius))
            return false
        end
    end
    local ok, st = pcall(function() return RaidPkts.JoinPad:Fire() end)
    local OK = (RaidEnums and RaidEnums.Status and RaidEnums.Status.Ok) or 0
    if not ok or st ~= OK then
        logWarn(("[Raid] JoinPad ตอบ %s"):format(tostring(st)))
        return false
    end
    S.raidActive  = true
    S.raidJoinAt  = nowReal()
    S.raidStartAt = 0
    S.raidClaimAt = 0
    S.raidReloc   = 0
    logWarn("[Raid] ✓ เข้าแท่นแล้ว — รอ countdown")
    return true
end

--- คำสั่งระดับสูงสุดของ raid (คืน action เดียวต่อรอบ)
---   มีตั๋ว -> ไปแท่น · ไม่มีตั๋ว + ปลาครบ -> แลก · ปลาไม่ครบ -> nil (ไปฟาร์มเกาะนั้น)
function raidStep(data)
    if S.raidActive then return nil end        -- raidTick ดูแลอยู่
    if not raidWanted(data) then return nil end
    local tickets = itemCount(data, (RaidCfg.TicketId or "raid_ticket"))
    if tickets < 1 then
        if raidTicketShort(data) then return nil end    -- ปลายังไม่ครบ -> ไปฟาร์ม
        return {
            key   = "raid:exchange",
            label = "แลก Raid Ticket (Legendary 8 ตัว)",
            run   = function() return raidExchangeTicket() end,
        }
    end
    return {
        key   = "raid:join",
        label = "ลง Sea Raid",
        run   = function() return raidJoinPad() end,
    }
end

--- ตำแหน่ง indicator ของเกาะใน raid (Workspace.RaidSlots.Slot<N>/Indicators/<island>)
---   RaidController._UpdateBeam (RaidController.lua:252) อ่าน Attachment ตัวแรกของโฟลเดอร์นี้
function raidIslandPoint(slot, islandIdx)
    if not slot then return nil end
    local slots = Workspace:FindFirstChild("RaidSlots")
    local s = slots and slots:FindFirstChild(("Slot%d"):format(slot))
    local ind = s and s:FindFirstChild("Indicators")
    local part = ind and ind:FindFirstChild(tostring(islandIdx))
    if part and part:IsA("BasePart") then return part.Position end
    if part and part:IsA("Attachment") then return part.WorldPosition end
    return nil
end

--- ย้ายไปเกาะถัดไปใน raid (ไม่ย้ายถ้าอยู่ใกล้พอแล้ว)
function raidMoveToIsland(slot, islandIdx)
    if S.moving or S.traveling then return end
    local target = raidIslandPoint(slot, islandIdx)
    local hrp = root()
    if not (target and hrp) then return end
    local flat = Vector3.new(target.X - hrp.Position.X, 0, target.Z - hrp.Position.Z)
    if flat.Magnitude < 40 then return end
    S.moving = true
    tweenDiveTo(target, "raid-island-" .. tostring(islandIdx))
    S.moving = false
end

--- จุดเหวี่ยงใน raid
--- ⚠ ใน raid GetCurrentIslandId() = "" ⇒ getWaterY() คืน SEA_LEVEL (3) ซึ่งผิด
---   ต้องหาน้ำจริงจาก WaterBody (raid water ถูก tag "WaterBody" เหมือนน้ำปกติ)
---   ถ้าหาไม่เจอ -> เหวี่ยงไปทาง indicator ของเกาะปัจจุบันแล้วพึ่ง server ตอบ RaidNoSpot
function raidCastTarget()
    local hrp = root()
    if not hrp then return nil end
    if WaterBody and WaterBody.SurfaceY then
        for r = 8, 80, 8 do
            local n = math.max(8, math.floor(2 * math.pi * r / 8))
            for i = 0, n - 1 do
                local a = (i / n) * 2 * math.pi
                local x = hrp.Position.X + math.cos(a) * r
                local z = hrp.Position.Z + math.sin(a) * r
                local ok, y = pcall(function() return WaterBody.SurfaceY(x, z) end)
                if ok and type(y) == "number" then return Vector3.new(x, y, z) end
            end
        end
    end
    local p = raidIslandPoint(S.raidSlot, math.min((S.raidIslandIdx or 1), #(RaidCfg.Islands or {})))
    if p then
        local dir = Vector3.new(p.X - hrp.Position.X, 0, p.Z - hrp.Position.Z)
        if dir.Magnitude > 0.1 then
            dir = dir.Unit * math.min(40, dir.Magnitude)
            return Vector3.new(hrp.Position.X + dir.X, hrp.Position.Y, hrp.Position.Z + dir.Z)
        end
    end
    return nil
end

--- เดินเครื่อง raid ทุก phase (เรียกจาก mainLoop ทุก 1 วิ)
---   ตัวเหวี่ยงปลาใช้ mainLoop เดิม — ไม่ต้องเขียนใหม่
function raidTick()
    if not S.raidActive then return false end
    local rc = Client and Client.GetController and Client.GetController("RaidController")
    if not rc then return false end
    local phase = tonumber(rc._phase) or 0
    local slot  = tonumber(rc._slot)
    if slot then S.raidSlot = slot end
    local Ph = (RaidEnums and RaidEnums.Phase) or {}
    local OK = (RaidEnums and RaidEnums.Status and RaidEnums.Status.Ok) or 0
    local now = nowReal()

    -- อยู่ใน raid region จริงไหม (ใช้ตัดสินว่า "จบรอบแล้ว" อย่างปลอดภัย)
    local inRaid = false
    pcall(function()
        local irc = Client.GetController("IslandRegionController")
        inRaid = (irc and irc:GetRaidRegionId() ~= "") or false
    end)

    -- ── Waiting + หลุดจาก raid region = จบรอบแล้ว ──
    if phase == (Ph.Waiting or 0) and not inRaid then
        if now - (S.raidJoinAt or 0) > 5 then
            S.raidActive, S.raidSlot = false, nil
            logWarn("[Raid] จบรอบ raid (กลับโลกปกติ)")
            S.farmRecheck = true
        end
        return true
    end

    -- ── ก่อนถึง AwaitReady: รอ countdown / ล็อกแมป ──
    if phase < (Ph.AwaitReady or 3) then
        if now - (S.raidJoinAt or 0) > (CONFIG.Forge.MaxRaidWait or 900) then
            S.raidActive = false
            logWarn("[Raid] รอเข้า raid นานเกิน — ยกเลิก (แท่นอาจไม่ครบคน)")
        end
        return true
    end

    -- ── AwaitReady: ไปกด Start ที่ Raid Guide ──
    if phase == (Ph.AwaitReady or 3) then
        if now - (S.raidStartAt or 0) < 3 then return true end
        S.raidStartAt = now
        local npcId = (RaidCfg.InteractiveIds or {}).StartNpc or CONFIG.Forge.StartNpc
        if S.tools.approachNpcAnywhere(npcId, tonumber(RaidCfg.NpcRadius) or 15) then
            local ok, st = pcall(function() return RaidPkts.StartIsland:Fire() end)
            if not ok or st ~= OK then
                logWarn(("[Raid] StartIsland ตอบ %s"):format(tostring(st)))
            else
                logWarn("[Raid] ✓ เริ่ม raid แล้ว")
            end
        end
        return true
    end

    -- ── Won: ไปกด Claim ที่ NPC ที่มี attribute RaidWon == true ──
    if phase == (Ph.Won or 5) then
        if now - (S.raidClaimAt or 0) < 3 then return true end
        S.raidClaimAt = now
        if S.tools.approachRaidWonNpc() then
            local ok, st = pcall(function() return RaidPkts.Claim:Fire() end)
            if not ok or st ~= OK then
                logWarn(("[Raid] Claim ตอบ %s"):format(tostring(st)))
            else
                logWarn("[Raid] ✓ รับรางวัล raid แล้ว")
            end
        else
            logWarn("[Raid] ชนะแล้วแต่ไปหา NPC รับรางวัลไม่ได้ (ยังไม่ stream)")
        end
        return true
    end

    -- ── Failed: ออก ──
    if phase == (Ph.Failed or 6) then
        S.raidActive = false
        logWarn("[Raid] raid ล้มเหลว — กลับไปฟาร์ม")
        S.farmRecheck = true
        return true
    end

    -- ── Running: ย้ายไปเกาะที่กำลังตก + ปล่อยให้ mainLoop เหวี่ยงเอง ──
    if phase == (Ph.Running or 4) then
        local done = tonumber(rc._done) or 0
        local idx = math.min(done + 1, #(RaidCfg.Islands or {}) or 1)
        S.raidIslandIdx = idx
        raidMoveToIsland(slot, idx)
    end
    return true
end

--- ขั้นของภารกิจ (CONFIG.Missions) — คืน action ถัดไป หรือ nil = ยังต้องฟาร์มต่อ
local function missionStep(data)
    local m = activeMission(data)
    if not m then return nil end
    -- (ใหม่) Lotus มีเครื่องเดินของตัวเอง (3 สเต็ป + Advance)
    --   ⚠ ต้องอยู่ "ก่อน" guard missionRequirement ด้านล่าง — ภารกิจนี้ไม่มี need/needFish
    --     missionRequirement จึงคืน nil และจะตัดมันทิ้งทันที
    if m.kind == "lotus" then return lotusMissionStep(data, m) end
    if not missionRequirement(data, m) then return nil end

    -- ── เกาะขั้นก่อน: ต้องปลดก่อนถึงจะแตะเควสต์นี้ได้เลย ──────────
    -- ⚠ ต้องเช็คก่อน "ซื้อเบ็ดที่เควสต์บังคับ" ด้วย ไม่งั้นจะซื้อของให้เควสต์
    --   ที่ยังรับไม่ได้ = เปลืองเงินไปกับเควสต์ที่ยังไม่ถึงตา
    --   (ตอนนี้ยังไม่กระทบ เพราะ activeMission เอาภารกิจแรกที่ยังไม่เสร็จ
    --    แต่ถ้าวันหลังสลับลำดับ CONFIG.Missions มันจะพังแบบเงียบ ๆ)
    --
    --   ทุกเควสต์มี visibleWhenIslandUnlocked บังคับว่าต้องปลดเกาะก่อนหน้ามาก่อน
    --   server ตอบกลับเป็น "You must unlock <X> Island first!" = ยิงซ้ำก็ไม่มีทางผ่าน
    --   ถ้าไม่ gate ไว้ nextStep จะคืน action เดิมทุกรอบจนกว่าจะ ActionGiveUpAfter
    --   แล้วค้างเป็น pending ทั้งเซสชัน ไม่มีทางได้กลับไปทำเกาะก่อนหน้าให้ครบ
    --
    --   เควสต์เบ็ด -> เกาะขั้นก่อนคือเกาะที่ NPC อยู่ (crimson/bamboo = volcano, dread_fish = fossil)
    --   เควสต์ปลดเกาะ -> เกาะขั้นก่อนคือเกาะที่ต้องไปตก (unlock_island_4 = desert)
    -- ⚠ island_starter เป็น defaultUnlocked จึงผ่านอัตโนมัติ ไม่ทำให้ภารกิงแรกค้าง
    local preIsland = (m.kind == "rod" and m.npcIsland) or m.farmIsland
    local preOk = (type(preIsland) ~= "string") or islandUnlocked(data, preIsland)
    if not preOk then
        return nil    -- ยังปลดเกาะขั้นก่อนไม่ได้ -> ปล่อยให้ nextStep ไปทำเกาะนั้นก่อน
    end

    -- ⚠ a00) ซื้อเบ็ดที่เควสต์บังคับ ต้องมาก่อนขั้น "รับเควสต์"
    --   เหตุผลที่ยืนยันได้จริง: ตัวนับของเควสต์นับ "จับด้วยเบ็ดนี้" เช่น crimson_bead_rod
    --   นับ CurrentFished เฉพาะที่จับตอนใส่ Legacy Rod (Requirements/crimson_bead_rod.lua:51)
    --   ถ้ายังไม่มี legacy_rod ตัวนับจะไม่ขยับ = ทำเควสต์ไม่จบ แม้จะรับได้แล้ว
    -- ⚠ ไม่ได้ยืนยันว่าเซิร์ฟปฏิเสธตอน Accept ถ้าไม่มีเบ็ด — ในดัมป์ไม่มีข้อความปฏิเสธ
    --   เรื่องนี้เลย แต่ซื้อก่อนเป็นการเรียงลำดับที่ปลอดภัยอยู่ดี
    if m.kind == "rod" then
        local nr = needRodAction(data, m)
        if nr then return nr end
    end

    -- a0) รับเควสต์ก่อนเป็นอันดับแรก — ลำดับจริงของเกมคือ รับ -> ไปตกปลา -> กลับมากด Complete
    --    (npc_unlock_island_4.lua: หน้า 2 "Accept" แล้วค่อยหน้า 4 "Unlock")
    --
    -- ⚠ ต้องอยู่ก่อนข้อ a (ซื้อเบ็ด) / a2 (สกิลครบไหม) / b (ไปเกาะไหม) เพราะทั้งสามข้อ
    --   เป็น "return nil หรือ return action อื่น" = ถ้าวางไว้หลัง จะไม่มีโอกาสรับเควสต์เลย
    --   ถ้าสกิลยังไม่ครบ หรือเงินยังไม่พอซื้อเบ็ด หรือยังไม่ได้ไปเกาะฟาร์ม
    -- ⚠ ถ้ารอให้ปลาครบแล้วค่อยรับ ปลาจะถูก "ปลดล็อก -> ล็อก" วนทุก 10 วินาที
    --   ทุกครั้งที่กด Complete แล้วล้มเหลว เพราะ server ยังไม่เคยเห็นว่าเรารับเควสต์
    -- ⚠ เควสต์เบ็ดใช้ id ของเบ็ดตัวเอง ไม่ใช่คีย์เกาะ
    --   ถ้าอ่านแค่ UNLOCK_QUEST[m.targetIsland] มันจะเป็น nil ตลอด = ไม่มีทางรับเควสต์เบ็ด
    local questId = (m.kind == "rod" and m.targetRod) or UNLOCK_QUEST[m.targetIsland]
    if questId and currentQuestId(data) ~= questId then
        return {
            key = "quest:" .. questId,
            label = ("รับเควสต์ %s"):format(
                (m.kind == "rod") and rodTag(m.targetRod) or islandTag(m.targetIsland)),
            run = function()
                -- ⚠ ต้องยืนที่จุดปลดล็อคเกาะก่อนยิง — server เช็คระยะเอง
                --   ยิงจากที่ยืนไม่ผ่าน ("Move closer to Snow Island Guide.")
                --   approachUnlock เดินไปจุดปลดล็อคใน CONFIG.IslandPoints โดยอ่าน
                --   ลิมิต QuestConfig.NpcDistance สด ๆ = ไม่ต้องรู้พิกัดเอง
                -- เควสต์เบ็ดไม่มี targetIsland -> ต้องเดินไปหา NPC ของมันเอง (ดู approachRodNpc)
                local near
                if m.kind == "rod" then
                    near = S.tools.approachRodNpc(m)
                else
                    near = S.tools.approachUnlock(m.targetIsland)
                end
                if not near then return false end
                local ok, why = ensureQuestAccepted(questId, fetchData() or data)
                if not ok then
                    logWarn(("[Prog] รับเควสต์ %s ไม่สำเร็จ: %s"):format(questId, tostring(why or "[no reason returned] ensureQuestAccepted gave 1 value only")))
                end
                return ok
            end,
        }
    end

    -- ── เควสต์เบ็ด: แยกออกไปทั้งก้อน ──
    -- ⚠ ต้องมาหลังข้อ a0 เสมอ เพราะตัวนับของเควสต์เบ็ด (CurrentFished / RequiredBamboo)
    --   มีค่าต่อเมื่อเควสต์ถูก "รับ" แล้วเท่านั้น — ถ้ารับทีหลังค่าจะเป็น 0 ทั้งชีวิต
    -- ⚠ ต้องมาก่อนข้อ a (ซื้อเบ็ดของเกาะฟาร์ม) และ a2 (สกิลของเกาะฟาร์ม)
    --   เพราะสองข้อนั้นผูกกับ island_unlock เท่านั้น และ a2 จะค้างไปตลอดถ้าเกาะนั้นยังสุ่มสกิลไม่ครบ
    if m.kind == "rod" then
        return rodMissionStep(data, m)
    end

    -- a) เบ็ดที่ดีที่สุดของเกาะเป้าหมาย — PurchaseRod ไม่มีเช็กระยะ ยืนที่ไหนก็ซื้อได้
    --    เลยซื้อก่อนแล้วค่อยว่ายไป ไม่ต้องเผื่อเดินทางมาซื้อ
    --
    -- ⚠ เป้าหมายมีตัวเดียวต่อเกาะ = ตัวท็อปของเกาะนั้น (bestRodForIsland)
    --   เงินไม่ถึงราคา = ไม่ซื้ออะไรเลย -> return nil ไปฟาร์มที่เกาะหลัก
    --   ไม่ไล่เบ็ดระดับกลาง เพราะทุกชั้นที่ราคา >= 90,000 ปลดช่องสกิล 4 ช่องเท่ากันหมด
    --   (เดิมเคยมีโหมด "ขั้นบันได" ที่ซื้อเบ็ดที่แพงที่สุดที่เงินพอ ตัดแล้ว — ดู CONFIG)
    --   ⚠ ต้องเช็ก islandUnlocked ของเกาะที่จะซื้อด้วย
    --     FishingRodShopController.lua:300-323 ปฏิเสธว่า
    --     "Unlock this island before buying this rod."
    local rod = bestRodForIsland(m.farmIsland)
    if rod and not ownsRod(data, rod) and islandUnlocked(data, m.farmIsland) then
        local price = rodPrice(rod)
        if type(price) ~= "number" then return nil end
        local sellStep = needCoinsStep(data, price, ("ซื้อ %s"):format(rodTag(rod)))
        if sellStep then return sellStep end
        if numOr(data.Coin, 0) < price then return nil end      -- เงินไม่พอ -> ฟาร์มที่เกาะหลัก
        return {
            key = "buy:" .. rod,
            label = ("ซื้อ %s (%s)"):format(rodTag(rod), tostring(price)),
            newRod = rod,
            run = function() return buyRod(rod, data) end,
        }
    end
    -- a1) เบ็ดของเกาะภารกิจยังซื้อไม่ได้เพราะเกาะนั้นยังไม่ปลด
    --    ⚠ ถ้าไม่ข้ามขั้นนี้ ขั้นนี้จะคืน action ที่ซื้อไม่ได้ทุกรอบ -> nextStep ไม่เคยไหลถึง
    --      ข้อ 5 (สุ่มสกิล Legendary) และข้อ 6 (ปลดล็อกเกาะ) เลย = ค้างตลอดไป
    --      เบ็ดของ Desert ราคา 520,000 ซึ่งมากกว่า unlockCost ของ Desert (180,000)
    --      แปลว่ามีโอกาสสูงมากที่จะเงินถึง 520k ก่อน Desert จะปลด -> ต้องกันไว้

    -- a2) สกิลของเกาะภารกิจยังไม่ครบ -> ปล่อยให้ข้อ 5 ของแผนปกติสุ่มให้
    --    (เกาะภารกิจ = เกาะที่สุ่มอยู่ตอนนี้ เพราะเป็นเกาะที่ปลดสูงสุดอยู่แล้ว)
    local skOk = islandSkillsReady(data, m.farmIsland)
    if not skOk then
        return nil
    end

    -- b) ยังไม่ได้ไปเกาะเป้าหมาย -> ว่ายไป NPC + ตั้งจุดเกิดที่นั่น
    --    (ทำก่อนรอปลา เพราะไปตกที่นั่นต้องใช้เวลาเดินทางจริง)
    -- ⚠ เกาะของภารกิจยังไม่ปลด = ว่ายไปไม่ได้อยู่ดี ๆ (เซิร์ฟเวอร์ไม่รับข้ามเข้าเกาะที่ยังล็อก)
    --   ปล่อยให้ข้อ 6 ของแผนปกติไปปลดล็อกเกาะนั้นก่อน แล้วค่อยกลับมาทำขั้นนี้
    if islandUnlocked(data, m.farmIsland) then
        -- ⚠ ต้องเช็ค 2 อย่าง ไม่ใช่แค่อยู่ตรงไหน
        --   เดิมเช็คแค่ currentIslandId() = พลาดกรณี "ยืนอยู่บนเกาะเป้าหมายแล้ว
        --   แต่จุดเกิดยังเป็นเกาะเก่า" -> ข้าม travelToIsland ไปเฉย ๆ
        --   = ไม่มีวันได้จุดเกิดที่ถูกเกาะ แล้วพอตายก็โดนส่งกลับเกาะเดิม ฟาร์มผิดที่เงียบ ๆ
        --
        -- ⚠ จุดเกิดอยู่ที่ data.SpawnIsland (Data/PlayerData/Template.lua:24)
        --   ไม่ใช่ตำแหน่งตัวละคร — สองอย่างนี้ไม่จำเป็นต้องตรงกัน
        local wrongIsland = currentIslandId() ~= m.farmIsland
        local spawnIsland = (data and data.SpawnIsland) or nil
        -- ⚠ เชื่อได้ก็ต่อเมื่อเคยเห็นค่านี้เปลี่ยนจริง (ดู S.spawnReplicates)
        local wrongSpawn = S.spawnReplicates and (spawnIsland ~= nil) and (spawnIsland ~= m.farmIsland)
        if wrongIsland or wrongSpawn then
            return {
                key = "travel:" .. m.farmIsland,
                label = ("ไปเกาะ %s เพื่อทำเควสต์ %s%s"):format(
                    islandTag(m.farmIsland), tostring(m.key),
                    wrongSpawn and (" (ตั้งจุดเกิดใหม่ที่ %s)"):format(islandTag(m.farmIsland)) or ""),
                run = function() return travelToIsland(m.farmIsland) end,
            }
        end
    end

    -- c) นับปลา: have = ตัวที่เกมนับได้ตอนนี้ / locked = ตัวที่ต้องปลดก่อนกด Complete
    --    ⚠ ต้องนับรวมสองกลุ่ม เพราะ locked คือปลาที่เราจงใจเก็บไว้
    local okReq, req, list = missionCollect(data, m)
    if not req then return nil end
    if not okReq then return nil end
    local got = (type(list) == "table") and #list or (req.got or 0)

    -- d) เงินพอไหม (อ่านค่า cost จาก IslandConfig ตอนนี้ ไม่เก็บไว้ล่วงหน้า)
    local cost = islandCost(m.targetIsland)
    if type(cost) ~= "number" then return nil end
    local sellStep = needCoinsStep(data, cost, ("ปลดล็อก %s"):format(islandTag(m.targetIsland)))
    if sellStep then return sellStep end
    if numOr(data.Coin, 0) < cost then return nil end

    -- e) ครบทุกอย่าง -> "ปลดล็อกปลา" กับ "กด Complete" ต้องติดกันเดียว
    --    ถ้ามีอะไรแทรกระหว่างทาง (เช่นขายปลา) ปลาจะหายทั้งกระเป๋าทันที
    return {
        key = "mission:" .. m.key,
        label = ("ปลดล็อก %s (%s + %s)"):format(
            islandTag(m.targetIsland), tostring(cost), missionFishLabel(req, got)),
        run = function()
            if not releaseQuestFish(m) then
                protectQuestFish()          -- ปลดไม่ครบ -> ล็อกกลับที่เหลือ รอรอบหน้า
                return false
            end
            -- อ่าน data ใหม่: เพิ่งปลดล็อกปลา ตัวเลขควร replicate มาแล้ว
            local ok = unlockIsland(m.targetIsland, fetchData() or data)
            if not ok then
                protectQuestFish()          -- server ไม่ผ่าน -> กันปลาไว้ก่อนรอบหน้า
            end
            return ok
        end,
    }
end
--- อ่านสถานะจริง แล้วคืน action ถัดไปที่ "ควรทำ" หรือ nil = ยังไม่ต้องทำอะไร (ฟาร์มต่อ)
--- ไม่มีตารางขั้นตอนตายตัว — ทุกอย่างคำนวณใหม่จาก data ตอนที่เรียก
---   จึงทำซ้ำได้ ค้างกลางทางก็กู้เอง และถ้าเกาะไหนถูกปลดล็อกนอกแผนก็ยังเดินต่อได้
---
--- ลำดับการตัดสินใจ (ทุกข้ออ่านจากเกม ณ ตอนนั้น ไม่นับเวลา):
---   1) เกาะที่ปลดล็อกแล้ว เอาตัวที่ order สูงสุด = "เกาะที่ดีที่สุด"
---   2) มีภารกิจที่ยังไม่เสร็จไหม (CONFIG.Missions) -> missionStep: ซื้อเบ็ด / เดินทาง / ปลดล็อก
---   3) ถ้าเข้าเกาะดีที่สุดตาม CONFIG.StopIsland แล้ว -> จบ
---   4) ยังไม่มีเบ็ดดีที่สุดของเกาะนั้น -> ซื้อ (เงินพอพอ)
---   5) สกิลของเกาะนี้ยังไม่ครบเป้าหมาย (CONFIG.SkillTargets) -> สุ่ม
---   6) เกาะนี้ครบแล้ว -> ปลดล็อกเกาะถัดไป (เช็คแค่ unlockCost — เลเวลเป็นข้อมูลตาย เตือนอย่างเดียว)
---
--- ⚠ ข้อ 2 ต้องอยู่ก่อนข้อ 3: ถ้า StopIsland <= เกาะที่ภารกิจต้องไปทำ
---   nextStep จะหยุดที่ stop gate ก่อน แล้วทุกขั้นของภารกิจกลายเป็น dead code
---
--- ⚠ ไม่มีขั้น "เดินไปซื้อเบ็ด" เพราะไม่จำเป็น:
---   PurchaseRod เช็กแค่ UnlockedIslands + เงิน ไม่มีเช็กระยะห่าง
---   (FishingRodShopController.lua:295-330) = ยืนที่ Starter ก็ซื้อเบ็ดของ Desert ได้
---   ⚠ แต่ unlockIsland ยิงจากที่ไหนก็ไม่ได้: server เช็กระยะจากตำแหน่งจริง
---     (QuestConfig.NpcDistance) ดู S.tools.approachUnlock
---   เดินทางมีเฉพาะตอนที่ต้อง "ตั้งจุดเกิด" หรือไปตกปลาให้ตรงเกาะของเควสต์
function nextStep(data)
    if not data then return nil end

    local chain = islandChain()
    if #chain == 0 then return nil end

    -- 1) เกาะที่ดีที่สุด = เกาะที่ปลดล็อกแล้วที่ order สูงที่สุด
    local best, bestIdx = nil, 0
    for i, entry in ipairs(chain) do
        if islandUnlocked(data, entry.id) then
            best, bestIdx = entry, i
        end
    end
    if not best then return nil end

    -- 2) ภารกิจที่ยังไม่เสร็จ (ไปตกปลาที่เกาะอื่น) — ต้องมาก่อน stop gate
    --
    -- ⚠ LOTUS GEM DETOUR: ระหว่างที่ยกเลิก Lotus ไปทำเดลี่หา gems อยู่
    --   ต้อง "ข้าม" lotusMissionStep (ไม่งั้นมันจะรับ Lotus คืนทันทีแล้ววนกลับมาจุดเดิม)
    if S.lotusDetour == "daily" then
        local ret = lotusDetourReturn(data)
        if ret then return ret end
        local dqD = dqStep(data)
        if dqD then return dqD end
        return nil        -- เดลี่ไม่มีอะไรต้องทำ -> ฟาร์มต่อ (activeFarmIsland จัดการเกาะ)
    end

    local actM = missionStep(data)
    if actM then return actM end

    -- 2b) DAILY QUEST — เริ่มหลังปลดเกาะที่ตั้งไว้ (CONFIG.Daily.AfterIsland = Lotus) แล้ว
    --   ⚠ บอสมาก่อนเสมอ: bossTick อยู่ก่อนบรรทัดนี้ใน mainLoop และตั้ง S.bossHolding
    --     ซึ่งบล็อก runStep ทั้งบล็อก -> เควสต์จะไม่แย่งบอส
    --   ⚠ ยังต้องมี AfterMissionDone: activeFarmIsland ให้ farmIsland ของภารกิจมาก่อนเสมอ
    --     ถ้ารับเดลี่ตอนภารกิจยังค้าง บอทจะไม่ไปเกาะของเดลี่เลย = ใบนั้นไม่มีความคืบหน้า
    local dqGate = (not CONFIG.Daily.AfterIsland or islandUnlocked(data, CONFIG.Daily.AfterIsland))
                   and (not CONFIG.Daily.AfterMissionDone or activeMission(data) == nil)
    -- ⚠ raid มาก่อนเดลี่: gems จาก raid (181-363/รอบ) มากกว่าเดลี่ (5-20/ใบ) มาก
    --   พอ raid เต็มโควตาวัน raidWanted() = false -> เดลี่กลับมาทำเองตามคำสั่งผู้ใช้
    if CONFIG.Daily.Enabled and dqGate and not (RaidCfg and raidWanted(data)) then
        local dqA = dqStep(data)
        if dqA then return dqA end
    end

    -- 2c) FORGE CHAIN (Godslayer Rod V2) — หลังภารกิจ/เดลี่, ก่อน stop gate
    --   ⚠ ต้องอยู่ก่อน stop gate เพราะ StopIsland = lotus ⇒ ข้อ 3 จะ return nil ทันที
    --   ⚠ forgeStep คืน nil = "ให้ไปฟาร์ม" (เงินฟาร์มหลังสุด) ไม่ใช่ "จบงาน"
    if CONFIG.Forge.Enabled then
        local fa = forgeStep(data)
        if fa then return fa end
    end

    -- 3) ถึงจุดจบที่ตั้งไว้หรือยัง (หา index ของ StopIsland จาก chain เดียวกัน)
    local stopIdx = 0
    for i, entry in ipairs(chain) do
        if entry.id == CONFIG.StopIsland then stopIdx = i break end
    end
    if stopIdx > 0 and bestIdx >= stopIdx then
        if not S.stopReported then
            S.stopReported = true
            logWarn(("[Prog] ══ ครบแผนแล้ว (ถึง %s แล้ว) — ฟาร์มต่อไปเงียบๆ ══"):format(tostring(best.id)))
        end
        return nil
    end

    -- 4) ยังไม่มีเบ็ดดีที่สุดของเกาะนี้แล้วหรือยัง
    --    bestRodForIsland คืน nil ได้ (volcano/fossil ไม่มีเบ็ดในร้าน) = ไม่ต้องซื้ออะไร
    --    ⚠ ซื้อจากที่ยืนอยู่ก็ได้ ไม่ต้องเดินไปเกาะของเบ็ด — server เช็กแค่
    --      UnlockedIslands[cfg.islandId] กับเงิน ไม่มีเช็กระยะ (FishingRodShopController)
    --
    -- ⚠ เป้าหมายมีตัวเดียว: เบ็ดท็อปของเกาะที่ปลดสูงสุด (best.id)
    --   เงินไม่ถึงราคา = return nil ไปฟาร์ม จนกว่าจะพอ
    --   เดิมเคยมีโหมด "ขั้นบันได" ที่ซื้อเบ็ดที่แพงที่สุดที่เงินพอ ณ ตอนนี้
    --   ซึ่งทำให้หยุดครึ่งทาง (มีเงิน 1,300,000 -> ซื้อ taoist_rod แล้วนั่งต่อไป
    --   ตลอด เพราะ legacy_rod ที่ 3,000,000 ยังไปไม่ถึง) ตัดแล้ว ดู CONFIG
    local rod = bestRodForIsland(best.id)
    if rod and not ownsRod(data, rod) then
        local price = rodPrice(rod)
        if type(price) ~= "number" then
            -- อ่านราคาไม่ได้ = ยังตัดสินไม่ได้ว่าเงินพอไหม -> รอรอบหน้า ไม่ยิงมั่ว
            return nil
        end
        local sellStep = needCoinsStep(data, price, ("ซื้อ %s"):format(rodTag(rod)))
        if sellStep then return sellStep end
        if numOr(data.Coin, 0) >= price then
            return {
                key = "buy:" .. rod,
                label = ("ซื้อ %s (%s)"):format(rodTag(rod), tostring(price)),
                newRod = rod,   -- ให้ ensureBestLoadout รอเบ็ดใบนี้โผล่ในคลังก่อนสลับ
                run = function() return buyRod(rod, data) end,
            }
        end
        return nil        -- เงินไม่พอ -> ฟาร์มต่อ
    end

    -- 5) สกิลเป้าหมายของเกาะนี้ (ดู CONFIG.SkillTargets + islandSkillsReady)
    local skOk, skMsg = islandSkillsReady(data, best.id)
    if not skOk then
        return {
            key = "gacha",
            label = ("สุ่มสกิลที่ %s (%s)"):format(islandTag(best.id), tostring(skMsg)),
            quiet = true,   -- สุ่มได้หลายรอบ ถ้าพิมพ์ทุกครั้งจะรกจนอ่านไม่ออก
            -- rollSkillOnce คืน false,"no-coin" เองเมื่อเงินไม่พอ -> ไปฟาร์มต่อ
            run = function() return rollSkillOnce(data) end,
        }
    end

    -- 6) Unit เป้าหมายของเกาะนี้ (ดู CONFIG.UnitTargets + islandUnitsReady)
    --   ⚠ ต่างจากสกิล: เกาะที่ไม่ประกาศใน CONFIG.UnitTargets = ไม่สุ่ม Unit เลย
    --   และ "คลังเต็ม" ไม่บล็อกแผน — แค่เตือนแล้วปล่อยไปข้อ 7 ต่อ
    --     (คลัง Unit มีแค่ 3 ช่อง และเกมไม่มีทางขาย มีแต่ลบถาวร สคริปต์นี้จึงไม่ลบให้)
    local unOk, unMsg, unFree = islandUnitsReady(data, best.id)
    if not unOk and (unFree or 0) < 1 then
        -- คลังเต็ม = สุ่มไม่ได้ (เตือนครั้งเดียว) แล้วปล่อยไปข้อ 7 ต่อ
        if S.lastUnitMsg ~= best.id .. "|full" then
            S.lastUnitMsg = best.id .. "|full"
            logWarn(("[Prog] 🎰 คลัง Unit เต็ม (%d ช่อง) — สุ่มที่ %s ไม่ได้ "
                .. "(ถอดช่องเพิ่มด้วย gem หรือลบตัวที่ไม่ใช้เอง — การลบถาวร สคริปต์นี้ไม่ลบให้)")
                :format(tonumber((data.Units or {}).Capacity) or 0, islandTag(best.id)))
        end
    elseif not unOk then
        return {
            key = "gachaUnit",
            label = ("สุ่ม Unit ที่ %s (%s)"):format(islandTag(best.id), tostring(unMsg)),
            quiet = true,   -- สุ่มได้หลายรอบ ถ้าพิมพ์ทุกครั้งจะรกจนอ่านไม่ออก
            -- rollUnitOnce คืน false,"no-coin" เองเมื่อเงินไม่พอ -> ไปฟาร์มต่อ
            run = function() return rollUnitOnce(data) end,
        }
    end

    -- 7) เกาะนี้ครบแล้ว -> เกาะถัดไปคืออันไหน
    local nxt = chain[bestIdx + 1]
    if not nxt then return nil end          -- จบลำดับเกาะแล้ว

    local questId = UNLOCK_QUEST[nxt.id]
    if not questId then return nil end

    -- เกาะถัดไปมีภารกิจผูกอยู่ -> ให้ missionStep จัดการ (นับปลา/เงิน) ไม่ใช่กดตรงนี้
    --   กดตรงนี้ตอนปลา/เงินยังไม่ครบจะได้แต่คำปฏิเสธจาก server เปล่า ๆ
    local am = activeMission(data)
    if am and am.targetIsland == nxt.id then return nil end

    local unlockCost = islandCost(nxt.id)
    local sellStep = needCoinsStep(data, unlockCost, ("ปลดล็อก %s"):format(islandTag(nxt.id)))
    if sellStep then return sellStep end
    if numOr(data.Coin, 0) < (unlockCost or math.huge) then return nil end

    -- เลเวลของเกาะ (jungle 10 / desert 20 / ...) เป็นข้อมูลตายที่เกมไม่เคยเอามาเช็ค
    --   NPC ปลดล็อกของเกมดูแค่ 3 อย่าง: ปลดล็อกเกาะก่อนหน้าแล้วหรือยัง + รับเควสต์นี้มาหรือยัง
    --   + เหรียญพอไหม ไม่มีการอ่านเลเวลที่ไหนเลย (npc_unlock_island_3.lua)
    --   ถ้าเอาเลเวลมาบล็อกตรงนี้ สคริปต์จะ return nil = "แผนไม่มีอะไรให้ทำ"
    --   แล้วฟาร์มเงียบ ๆ ไปเรื่อย ๆ โดยไม่บอกอะไรเลย
    --   เลยเปลี่ยนเป็นเตือนครั้งเดียว แล้วปล่อยให้ยิง packet ไป ให้ server ตัดสินใจเอง
    local lv = playerLevel(data)
    local needLv = (IslandConfig and IslandConfig[nxt.id] or {}).requiredLevel or 1
    if lv and lv < needLv and not S.warnedLevel[nxt.id] then
        S.warnedLevel[nxt.id] = true
        logWarn(("[Prog] %s ระบุเลเวล %d แต่เราอ่านได้ %d - เกมไม่ได้เช็คเลเวลตอนปลดล็อก "
            .. "จึงยังยิงไปก่อน ถ้าไม่ผ่านจะเห็นคำตอบจริงจาก server")
            :format(islandTag(nxt.id), needLv, lv))
    end

    return {
        key = "unlock:" .. nxt.id,
        label = ("ปลดล็อก %s (%s)"):format(islandTag(nxt.id), tostring(islandCost(nxt.id))),
        run = function() return unlockIsland(nxt.id, data) end,
    }
end

--- ลงมือกับ action ที่ nextStep คืนมา + จัดการผลลัพธ์
--- คืน acted, pending
---   acted  = มีอะไรถูกทำจริงรอบนี้ (เหวี่ยงต่อไม่ได้รอบนี้)
---   pending = ยังมี action ที่ตั้งใจทำอยู่ไหม (รวมกรณียังไม่ถึงเวลา retry)
---     mainLoop จะไม่ย้ายไปฟาร์มขณะที่ pending = true — แผนต้องมาก่อนฟาร์มเสมอ
function runStep()
    local data = fetchData()
    if not data then return false, false end     -- data ยังไม่มา = ยังตัดสินไม่ได้ -> ฟาร์มต่อ (ไม่ค้าง)

    -- เหวี่ยงอยู่? ต้องปิด session ก่อน ย้าย/ซื้อ/ปลดล็อก
    if S.state ~= "Idling" then
        syncState()
        if S.state ~= "Idling" then return false, true end
    end

    local act = nextStep(data)
    if not act then return false, false end       -- แผนไม่มีอะไรให้ทำ -> ไปฟาร์มได้

    -- action เปลี่ยน = เริ่มนับล้มเหลวใหม่ (backoff ของของเก่าไม่เกี่ยวกัน)
    if S.actionKey ~= act.key then
        S.actionKey, S.attempts, S.retryAt = act.key, 0, 0
    elseif os.clock() < S.retryAt then
        return false, true        -- ยังไม่ถึงเวลาลองซ้ำ — ยังมีงานค้างอยู่
    end

    S.traveling = true
    local okRun, ok, why = pcall(act.run, data)
    S.traveling = false
    S.moving = false
    if not okRun then
        logWarn(("[Prog] ขั้น %s error — %s"):format(tostring(act.key), tostring(ok)))
        ok, why = false, "error"
    end

    -- "no-coin" = เงินยังไม่พอจริง ๆ ไม่ใช่ของเสีย -> ไม่นับเป็นครั้งที่ล้มเหลว
    -- (rollSkillOnce คืนค่านี้เอง ตัวอื่นคืน nil)
    if not ok and why == "no-coin" then
        S.retryAt = os.clock() + CONFIG.GoalPoll
        return false, false       -- เงินไม่พอ = ไม่มีอะไรทำได้ตอนนี้ -> ฟาร์ม
    end

    if ok then
        S.attempts = 0
        S.retryAt = 0
        task.wait(0.5)
        -- ได้ของใหม่ (เบ็ด/สกิล) -> สลับเป็นเบ็ดดีที่สุดในกระเป๋า + ใส่สกิลให้ครบทุกช่อง
        --   เพิ่งซื้อเบ็ดมา = ส่ง id เข้าไปด้วย ให้รอข้อมูล replicate ก่อนเลือก
        ensureBestLoadout(act.newRod)
        return true, false        -- ทำเสร็จ -> รอบหน้าค่อยคิดใหม่
    end

    -- ล้มเหลว: หน่องแล้วลองซ้ำอัตโนมัติ — ไม่มีทาง "ข้ามขั้นถาวร"
    --   เพราะสาเหตุเกือบทั้งหมดชั่วคราว (เงิน/เควสต์ค้าง/data ยังไม่มา)
    S.attempts = S.attempts + 1
    S.retryAt = os.clock() + CONFIG.ActionBackoff
    if S.attempts <= CONFIG.ActionMaxWarn then
        logWarn(("[Prog] %s ยังไม่สำเร็จ (ครั้งที่ %d) — ลองใหม่ใน %.0fs"):format(
            act.label, S.attempts, CONFIG.ActionBackoff))
    elseif S.attempts == CONFIG.ActionGiveUpAfter then
        logWarn(("[Prog] %s ล้มเหลว %d ครั้งติด — พัก action นี้ไปก่อน ไปตกปลาหาเงิน/ของที่ขาด แล้วค่อยลองใหม่")
            :format(act.label, S.attempts))
    end
    -- ⚠ ครบ CONFIG.ActionGiveUpAfter = action นี้ทำไม่ได้จริงในสภาพปัจจุบัน
    --   คืน pending=false เพื่อปล่อบอทไปตกปลาได้ มิฉะนั้น action ที่ปฏิเสธถาวร
    --   (เช่น Accept ที่ยังไม่มีเงื่อนไขครบ) จะหยุดตกปลาทั้งเซสชันโดยไม่มีทางออก
    --   S.retryAt ยังอยู่ กันยิงซ้ำถี่ และ attempts ถูกรีเซ็ตเมื่อ action เปลี่ยนหรือสำเร็จ
    if S.attempts >= CONFIG.ActionGiveUpAfter then
        return false, false
    end
    return false, true
end

local function progression()
    -- ⚙ รอยตามขั้น: ถ้าสคริปต์ตายกลางคัน ให้ดูว่าค้างที่บรรทัดไหน
    --   แทนที่จะเดาว่า "ทำไมตัวไม่ขยับ" โดยไม่มีหลักฐาน
    local step = 0
    local function mark(tag)
        step = step + 1
        logWarn(("[Prog] %d - %s"):format(step, tag))
    end

    setNoclip(true)          -- เปิดค้างตลอดการทำงาน ไม่ปิด
    -- ⚠ กันจมตั้งแต่แรก (2026-10-16)
    --   noclip เปิด = ไม่มีพื้นให้ยืน = gravity ดึงลงตลอด
    --   เดิม startAntiSink() อยู่ใน startFishing() ซึ่งอยู่หลัง goToFarmSpot()
    --   = ช่วงข้ามเกาะครั้งแรกไม่มีอะไรกันจม เลยต้องพึ่ง Hold ตรึงไว้ทุกจุด
    --   พอผู้ใชาสั่งลดการตรึง (ดู travelToIsland) ตัวนี้คือตาข่ายแทน
    --   ฟังก์ชันเป็น idempotent (if S.antiSinkConn then return end)
    --   = เรียกซ้ำที่ startFishing ได้ ไม่ต่อ connection ซ้ำ
    startAntiSink()
    mark("noclip เปิดแล้ว")

    -- HORST: ต้องเป็นบรรทัดแรก ๆ เพราะมันแก้ print ก่อนโหลด on_loaded.lua
    horstInstall()

    -- LOW MODE: ปิด Render3D + UI สถิติ (ผู้กด N เพื่อดูภาพปกติ)
    --   ต้องอยู่บรรทัดแรก ๆ เพื่อครอบหน้าจอตั้งแต่ต้น ก่อนเกิดอาการกะพริบขาว
    bindLowToggle()
    mark("LowMode ผูกปุ่มแล้ว")

    local data = waitForData(30)
    if not data then
        mark("รอข้อมูลผู้เล่น 30 วินาทีไม่ได้ -> หยุด")
        return
    end
    mark("ได้ข้อมูลผู้เล่นแล้ว")

    -- HORST: ครั้งแรกบังคับส่ง (ไม่ต้องรอ throttle) แล้วเปิด heartbeat ต่อเนื่อง
    if cfgOn("Horst", CONFIG.Horst.Enabled) then
        sendHorstDescription(true)
        startHorstHeartbeat()
    end

    -- 1) Tutorial
    if isInTutorial(data) then doTutorialSkip() end

    -- 2) Skill แรก: ถ้ายังไม่มีสกิล -> สุ่ม (รอบแรกฟรี)
    --    ส่วน "สุ่มจนครบเป้าหมายของเกาะ" ไม่ต้องทำตอนนี้ — nextStep จัดการให้เอง
    --    เมื่อไปถึงเกาะที่ไม่ใช่เกาะแรก (ดู CONFIG.SkillTargets)
    data = fetchData() or data
    if next(ownedSkills(data)) == nil then
        rollSkillOnce(data)
        task.wait(0.5)
        data = fetchData() or data
    end

    -- 3) เบ็ดดีที่สุดในกระเป๋า + สกิลดีที่สุดในช่องที่ว่าง (ช่องที่ปลดล็อกแล้วเท่านั้น)
    --   ต้องทำ "ก่อนเริ่มตกปลา" เพราะ mainLoop จะเริ่มเหวี่ยงทันทีหลังจากนี้
    ensureBestLoadout()
    task.wait(0.5)
    mark("เลือกเบ็ด+สกิลดีที่สุดแล้ว")

    -- 4) เดินแผนให้ครบก่อนเริ่มฟาร์ม — แผนต้องมาก่อนเสมอ
    --   ⚠ เดิมกระโดดไป goToFarmSpot() ก่อน แล้วค่อยให้ mainLoop เดินแผนทีหลัง
    --     ผลคือ "tween ไปจุดฟาร์ม -> ตกปลา 1 ตัว -> ค่อยซื้อ/ปลดล็อก"
    --     แผนจริง ๆ (เกาะที่ปลดแล้ว > เบ็ดดีสุดของเกาะ > ...) ไม่เคยถูกเช็คเลย
    -- ⚠ บอสเกิดอยู่แล้ว = ไปตกบอสก่อนเดินแผนเสมอ (ผู้ใชาสั่ง 2026-10-15)
    --   เดิมบูตวน runStep() 10 รอบโดยไม่เช็คบอสเลย บอสที่เกิดก่อนสตาร์ต
    --   จถูกมองข้ามทั้งช่วง -> สคริปต์ tween ไปทำอย่างอื่นก่อน
    --   พอเข้า mainLoop ค่อยเจอบอสทีหลัง = ทำงานผิดลำดับที่ผู้ใช้เห็น
    for _ = 1, 10 do
        if bossTick() then break end     -- เจอบอส = ไปตีเลย ไม่เดินแผนต่อ
        local acted = runStep()
        if not acted then break end      -- ไม่มีงาน / ติด backoff -> ปล่อยให้ mainLoop จัดการต่อ
        task.wait(0.3)
    end

    mark("เดินแผนรอบแรกเสร็จแล้ว")

    -- 5) เริ่มที่จุดฟาร์ม — ใช้ goToFarmSpot ไม่ใช่ tween ตรง ๆ
    --   เพราะถ้าผู้ใช้เกิดบนเกาะอื่น (เช่นเพิ่งตั้ง spawn ไว้ที่นั่น) มันจะวิ่งข้ายน้ำไปเรื่อย ๆ
    --   ⚠ ยกเว้นตอนกำลังตีบอส (แก้ 2026-10-16)
    --     ข้อ 4 จะ break ออกจากลูปทันทีที่เจอบอส แต่ถ้าบรรทัดนี้ยังวิ่งต่อ
    --     มันจะลากตัวละครออกจากบอสไปตกที่เกาะฟาร์ม (jungle) ทั้งที่ S.bossHolding
    --     ยัง true — mainLoop เช็คธงนี้ที่ 6092/6107 แต่ตรงบูตไม่เช็ค
    --     = เสีย tween ไปหาบอสแล้ว แล้วทิ้งบอสไปตกโดยไม่ได้ตี้สักครั้ง
    if not S.bossHolding then
        goToFarmSpot()
    end

    -- 6) เข้า auto-fishing + เดินแผนไปพร้อมกัน
    startFishing()

    -- ⚙ บูตครบทุกขั้นแล้ว = ปลดธงให้ watchdog เลิกเฝ้า
    --   ธงนี้คือของเดียวที่ยืนยันว่า "สคริปต์รันถูกต้อง"
    --   ถ้า execute ใหม่ทับของเดิมที่ยังวิ่งอยู่ ธงเดิมต้องถูกล้างก่อน
    --   (ล้างที่บล็อก if CONFIG.Watchdog.Enabled ท้ายไฟล์ ก่อน task.spawn(progression))
    _G.FishingMasterBooted = true
end

startFishing = function()
    local hrp = root()
    if not hrp then
        logWarn("[Prog] ยังไม่มีตัวละคร — ลองใหม่ใน 3s")
        task.wait(3)
        hrp = root()
        if not hrp then return end
    end
    overrideCastMapGuard()
    -- ไม่ overrideCastDist(0) แล้ว — castToNearestWater ตั้งระยะตามจุดน้ำเปิดจริงแต่ละครั้ง
    if not collectPressedConns() then
        logWarn("[Prog] ไม่มี getconnections/firesignal — native input ใช้ไม่ได้")
        return
    end
    startAntiSink()

    -- ปลด readonly ของ config ก่อนเหวี่ยงครั้งแรก (เกม freeze ทั้งก้อน)
    CastCfg = unfreezeConfig("Cast")
    if not CastCfg then
        logWarn("[Prog] ถอด readonly Cast ไม่สำเร็จ — ระยะเหวี่ยงจะเป็นค่าของเกม")
    else
        -- PreCastDelay = task.delay(CAST_MIN_HOLD) คือพื้นเวลาที่เกมบังคับ
        -- ระหว่าง "กดปุ่ม" กับ "เข้าสู่ Throwing" (FishingController.lua:1564)
        --   = เวลาที่ต้องรอทุกครั้ง ไม่เกี่ยวกับหลอด luck เลย -> ย่อได้
        CastCfg.MinHoldTime = CONFIG.MinHoldTime
    end
    instantLuckBar()
    tightenCaughtCooldown()

    S.runGen = (S.runGen or 0) + 1
    S.running = true
    subscribe()
    if CONFIG.Skills then hookSkillCooldown() end
    if CONFIG.LootSuppress then suppressLootWindow() end
    task.spawn(function()
        local ok, err = pcall(mainLoop)
        if not ok then logWarn("[Prog] main loop error: " .. tostring(err)) end
    end)
end

-- ⚙ บล็อกนี้อยู่ที่ main chunk ตรง ๆ (ไม่ผ่าน task.spawn) เพราะ
--   Set3dRenderingEnabled ใช้ได้เฉพาะ thread ของ main chunk
--   (99 Nights MainScript.lua:697 ก็เรียกตรงตำแหน่งเดียวกันนี้)
-- ⚙ ท้ายไฟล์ = บรรทัดสุดท้ายของ main chunk ถ้ามี error ตรงนี้
--   บรรทัดถัดไป (task.spawn(progression)) จะไม่เคยถูกรันเลย
--   แล้วตัวละครจะไม่เดินไปจุดฟาร์ม + ไม่มี noclip ใหม่มาแก้ของค้าง
do
    -- 1) กู้ CanCollide ที่รอบก่อนทิ้งไว้ก่อนเป็นอันดับแรก
    --    (ถ้าไม่ทำตรงนี้ แล้วข้อ 2 ล้ม ตัวละครจะทะลุพื้นต่อไปอีก)
    pcall(setNoclip, false)
    pcall(clearStandSpot)
    -- ⚠ เงื่อนไข 4: ปล่อยตรึงทุกครั้งที่รันบล็อกนี้
    --   Anchored เป็นสถานะของเอนจิน รอบก่อนที่ตายไปแล้ว Heartbeat ของมันหายไป
    --   เหลือตัวละครติด Anchored=true ค้าง -> ทุกรอบหลังจากนี้ตัวละครขยับไม่ได้
    --   แบบเดียวกับ CanCollide=false ที่เคยค้างแล้วทำให้ตัวละครทะลุพื้น
    pcall(S.tools.releasePin)

    -- 2) คืนภาพ 3D + เปิด LowMode (ถ้าเปิดไว้)
    if not CONFIG.LowMode.Enabled then
        pcall(lowSetRender3d, false)
    else
        -- ⚠ ต้องห่อ: LOW_FIRST_RUN เรียก setLowMode -> refreshStatsUi
        --   ซึ่งแตะข้อมูลเกม ถ้าตอน main chunk เกมยังไม่พร้อมจะ error
        --   แล้วลากทั้งสคริปต์ตายโดยที่ผู้ใช้ไม่เห็นอะไรเลย
        pcall(LOW_FIRST_RUN)
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 🛡 WATCHDOG — ยก pattern จาก 99 Nights MainScript.lua:20-38
--
--   99 Nights: รอ KaitunExecuted 30 วินาที ถ้ายังไม่มี -> TP กลับแมพ
--   ของเรา:   ตรวจ 2 ระดับ เพราะบูตผ่านแล้วยังพังต่อได้อีก
--     1) บูตค้าง — _G.FishingMasterBooted ยังไม่ขึ้น เกิน BootTimeout วินาที
--        (เช่น waitForData รอไม่ได้ / require พัง / error ก่อนถึง startFishing)
--     2) เดินค้าง — บูตผ่านแล้ว แต่ S.beat ไม่ขยับเกิน StallTimeout วินาที
--        (mainLoop ตายเพราะ error, หรือค้างในงานที่บล็อกนานเกินไป)
--
-- ⚠ ใช้ nowReal() ไม่ใช่ os.clock() — os.clock() นับเวลา CPU
--   ตอนสคริปต์ yield (ซึ่งเกือบทั้งหมด) มันแทบไม่เดิน = นับเวลาไม่ได้
--   ตัวอย่างเดียวกับ 99 Nights MainScript.lua:24 ที่เขียนกำกับไว้เอง
--
-- ⚠ ใส่ task.spawn แยก thread เสมอ ไม่งั้น error ตรงนี้จะฆ่าตัว progression ตาย
--   (หลักเดียวกับที่ 99 Nights เขียนกำกับไว้ที่บรรทัด 22)
-- ──────────────────────────────────────────────────────────────────
--- ตัดสินว่า watchdog ต้องทำอะไรตอนนี้ — แยกออกมาให้ไม่มี side effect
---   (ถ้ารวมไว้ใน task.spawn จะทดสอบทุกกรณีไม่ได้ เพราะต้องรอเวลาจริง)
---   คืน nil = ยังไม่ต้องทำอะไร · "boot" = บูตค้าง · "stall" = หลักเดินค้าง
function watchdogVerdict(booted, beatMoved, waitedSec, blockedSec, cfg)
    cfg = cfg or CONFIG.Watchdog
    -- ⚠ เพดานแข็ง: บล็อกติดกันนานเกินนี้ = ค้างจริง ไม่ใช่กำลังว่าย
    --   ข้ามเกาะหนึ่งครั้ง ~123 วินาที + retry ได้ -> 600 วินาทียังพอสำรอง
    if (blockedSec or 0) > (cfg.MaxBlockTimeout or 600) then return "blocked" end
    if not booted then
        if waitedSec > (cfg.BootTimeout or 90) then return "boot" end
        return nil
    end
    if beatMoved then return nil end          -- ยังเดินได้ = ปกติ ไม่ต้องแตะ
    if waitedSec > (cfg.StallTimeout or 60) then return "stall" end
    return nil
end

local function watchdogStart()
    local W = CONFIG.Watchdog
    -- ⚠ เลขรอบ = ตัวแทนของ thread เก่า (execute ทับบ่อยในเกมนี้)
    --   รอบใหม่ต้องเติม 1 เพื่อสั่งรอบเก่าเลิก ไม่งั้น 2 watchdog TP พร้อมกัน
    _G.FishingMasterWatchdogGen = (_G.FishingMasterWatchdogGen or 0) + 1
    local myGen = _G.FishingMasterWatchdogGen
    task.spawn(function()
        local bootStart = nowReal()
        local beatSeen  = S.beat
        local beatAt    = bootStart
        local tries     = 0
        local bootTries = 0
        local blockedAt = nil    -- เริ่มบล็อกเมื่อไหร่ = nil = ยังไม่บล็อก
        local wasBooted = false  -- รอบก่อนหน้าบูตเสร็จไปหรือยัง (จับช่วง "เพิ่งบูตเสร็จ")

        -- ⚠ "สคริปต์ไม่รัน" ต้องแก้ด้วยการรันใหม่ก่อน ไม่ใช่รีเกมทันที
        --   (ผู้ใชาสั่ง 2026-10-15) ต่างจาก stall/blocked ซึ่งสคริปต์ยังวิ่งอยู่
        --   แต่ทำงานผิด — การรันบูตใหม่ไม่ช่วย จึง TP ได้เลย
        local function retryBoot(why)
            bootTries = bootTries + 1
            if bootTries > (W.MaxBootRetry or 3) then return false end
            logWarn(("[Watchdog] %s -> ลองรันสคริปต์ใหม่ (ครั้งที่ %d/%d)")
                :format(why, bootTries, W.MaxBootRetry or 3))
            -- ⚠ ปิดหลักเดินของรอบก่อนก่อน ไม่งั้นจะมี 2 mainLoop วิ่งพร้อมกัน
            --   แล้วยิง packet ซ้ำสองชุด (mainLoop เช็คด้วย S.running)
            S.running = false
            -- ⚠ ต้องทำ "ครบทุกขั้น" เหมือน main chunk (บรรทัด 7356-7370)
            --   เดิมข้ามข้อ 1 = ปล่อยให้ CanCollide=false ที่รอบก่อนทิ้งไว้
            --   แล้วตัวละครทะลุพื้นต่อไปอีก (เคยเจอจริง)
            pcall(setNoclip, false)
            pcall(clearStandSpot)
            if not CONFIG.LowMode.Enabled then
                pcall(lowSetRender3d, false)
            else
                pcall(LOW_FIRST_RUN)
            end
            _G.FishingMasterBooted = false
            task.spawn(progression)
            bootStart = nowReal()
            blockedAt = nil
            return true
        end

    -- ⚠ ห้าม Teleport เด็ดขาด (ผู้ใชาสั่ง 2026-10-16)
        --   ค่าที่คืนคือ "จะตั้งนาฬิกาใหม่ไหม" — คืน true = ตั้งใหม่แล้วเดินต่อ, false = ปล่อยนาฬิกาเดิน
        --   ตัวหลักเดินที่ watchdog จับ stall บ่อยที่สุดคือ "กำลังตกบอส" ซึ่งไม่ใช่การค้าง
        --   TP ทิ้งหมด = เสียรอบตก + ปลาในกระเป๋า + เวลาที่ฟาร์มมา
        --   ค้างจริง? tweenOnce มีตัวจับค้างในตัวเองแล้ว (TweenStuckSec)
        local function recover(why)
            tries = tries + 1
            -- ⚠ ธง S.moving/S.traveling ที่ค้างคือสาเหตุที่ "บล็อกค้าง" จริง ๆ — ล้างทิ้งเสมอ
            --   (เดิมแค่ log ไม่ล้าง = ค้างถาวร) จุดนี้ถูกเรียกเฉพาะตอนไม่มีงานเดินทางจริงหรือครบเพดานแล้ว
            S.moving = false
            S.traveling = false
            if tries > (W.MaxRetry or 3) then
                -- log ครั้งเดียวเท่านั้น กันสแปมทุกรอบ (tries รีเซ็ตเองเมื่อหลักเดินกลับมาขยับ)
                if tries == (W.MaxRetry or 3) + 1 then
                    logWarn(("[Watchdog] %s · เตือนครบ %d ครั้งแล้ว (ไม่ TP ไม่รีเกม สคริปต์เดินต่อเอง)")
                        :format(why, tries - 1))
                end
                return true
            end
            logWarn(("[Watchdog] %s -> เตือนแล้ว ไม่ TP ไม่รีเกม (ครั้งที่ %d/%d) · สคริปต์เดินต่อ")
                :format(why, tries, W.MaxRetry or 3))
            return true
    end

        while true do
            task.wait(1)
            if _G.FishingMasterWatchdogGen ~= myGen then return end   -- รอบใหม่ทับ = หยุด
            local t = nowReal()
            local booted    = (_G.FishingMasterBooted == true)
            local beatMoved = (S.beat ~= beatSeen)
            -- ⚠ กำลังว่ายข้ามเกาะ/ทำ tween = หลักเดินหยุดโดยตั้งใจ ไม่ใช่ค้าง
            --   -> เดินนาฬิกาเฉพาะตอนที่ S.traveling / S.moving = false
            --   แต่มีเพดานแข็ง (MaxBlockTimeout) เผื่อบล็อกค้างจริง
            -- ⚠ "กำลังตกอยู่" ต้องนับเป็น busy ด้วย ไม่งั้นบอสที่ใช้เวลานานโดยการออกแบบ
            --   (Phase1 .25 -> เฟส 2 HP เต็ม + ฮีลทุก 15 วิ) จะโดนตัดสินว่าค้าง
            --   ตอนครบ StallTimeout แล้วถูก TP ทิ้งกลางรอบ = ลงโทษสคริปต์ที่ทำงานถูก
            -- ⚠ เงื่อนไขคือ "เซิร์ฟยังยิง HP มา" ไม่ใช่แค่ S.fighting
            --     HP นิ่งเกิน HPSilence = รอบตกจบแล้ว = ค้างจริง = นับ stall ตามปกติ
            local busy = (S.traveling == true) or (S.moving == true) or fightAlive()
            local v
            if busy then
                -- ⚠ ตอนบล็อก ห้ามตัดสิน stall/boot เด็ดขาด
                --   waited = now - ref จะยังโตต่อระหว่างที่บล็อก เพราะ now เดิน
                --   แต่ ref ถูกยกขึ้นมาชดเฉพาะตอน "ออกจาก" บล็อกเท่านั้น
                --   = ถ้าตัดสินตอนบล็อก จะเตือนทันทีที่บล็อกนานพอ -> รีเกมกลางทาง
                --   ระหว่างบล็อกตัดสินได้อย่างเดียวคือ "บล็อกนานเกินเพดาน" เท่านั้น
                blockedAt = blockedAt or t
                v = watchdogVerdict(booted, beatMoved, 0, t - blockedAt)
            else
                -- ⚠ ยกจุดอ้างอิงไปเท่าเวลาที่บล็อก เพื่อ "ล้าง" เวลาที่บล็อกออกจากรอบนี้
                if blockedAt then
                    local busyFor = t - blockedAt
                    bootStart = bootStart + busyFor
                    beatAt    = beatAt + busyFor
                end
                blockedAt = nil
                -- ⚠ "เพิ่งบูตเสร็จ" = หลักเดินเพิ่งเริ่มเดิน ต้องตั้งนาฬิกาใหม่
                --   ไม่งั้นเวลาที่บูตใช้ (ได้สูงถึง BootTimeout) จะถูกนับเป็น
                --   "หลักเดินค้าง" ทันทีที่บูตจบ = TP ทิ้งสคริปต์ที่เพิ่งขึ้นเสร็จ
                --   (เกิดได้จริงถ้าบูตนานเกิน StallTimeout = 60 วินาที)
                if booted and not wasBooted then
                    beatSeen, beatAt = S.beat, t
                end
                wasBooted = booted
                if beatMoved then beatSeen, beatAt = S.beat, t; tries = 0 end
                v = watchdogVerdict(booted, beatMoved,
                    booted and (t - beatAt) or (t - bootStart), 0)
            end
            if v == "boot" then
                -- ลองรันใหม่ก่อนเสมอ (ผู้ใชาสั่ง) ไม่ใช่กระโดดไป TP ทันที
                if retryBoot(("บูตไม่จบใน %ds"):format(W.BootTimeout or 90)) then
                    -- รอบใหม่เริ่มนับใหม่ แต่เพดานรวมยังถูกนับด้วย bootTries
                elseif not recover(("บูตลองใหม่ครบ %d ครั้งแล้วยังไม่ขึ้น")
                        :format(W.MaxBootRetry or 3)) then return end
                bootStart = nowReal()
            elseif v == "stall" then
                -- ⚠ พิมพ์บริบทของรอบตกด้วย ถ้าค้างอยู่ในรอบตกจะได้เห็นทันทีว่าอะไรเกิด
                local fx = ""
                if S.fighting then
                    fx = (" · ค้างในรอบตก (%s)"):format(
                        tostring(S.fightExit or ("hp=" .. tostring(S.hpNow) .. "/" .. tostring(S.hpMax))))
                end
                if not recover(("หลักเดินไม่ขยับ %ds%s"):format(W.StallTimeout or 60, fx)) then return end
                beatSeen, beatAt = S.beat, nowReal()
            elseif v == "blocked" then
                if not recover(("บล็อกค้างนานเกิน %ds"):format(W.MaxBlockTimeout or 600)) then return end
                beatSeen, beatAt, blockedAt = S.beat, nowReal(), nil
            end
        end
    end)
end

-- ⚠ ล้างธงของรอบก่อนเสมอ — ถ้าไม่ล้าง แล้ว execute ใหม่ทับของเดิมที่บูตเสร็จแล้ว
--   watchdog รอบใหม่จะเห็นธงค้าง = คิดว่าบูตเสร็จทันที ทั้งที่หลักเดินยังไม่ได้เริ่ม
if CONFIG.Watchdog.Enabled then
    _G.FishingMasterBooted = false
    watchdogStart()
end
task.spawn(progression)

-- ⚠ หมายเหตุเรื่อง capability Set3dRenderingEnabled
--
--   lowSetRender3d เรียกตรงหนึ่งบรรทัด ไม่ห่ออะไร (ผู้ใชาสั่ง 2026-10-15)
--   จุดเดียวที่ต้องระวัง: อ่าน RunService จากตัวแปรสายโลก ไม่ใช่ local บรรทัด 34
--   เพราะ local บังชื่อไว้ทั้งไฟล์ ทำให้เรียกผิดตัว (เคยเสียเวลาไล่หลายรอบ)
--
--   ถ้าบรรทัดตรง error = ตัวรันไม่ให้ capability RobloxScript
--   จุดเรียก (LOW_FIRST_RUN / setLowMode) ห่อ pcall ไว้แล้ว
--   และมี fallback ไล่ Workspace ต่อท้าย = ยังปิดภาพได้จริงเหมือนกัน
