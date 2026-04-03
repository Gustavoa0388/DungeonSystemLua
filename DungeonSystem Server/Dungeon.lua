-- ==========================================================
-- Script Criado por GAS_Games
-- Dungeon.lua - (SERVER) Season 6 Louis Emulator (IgkGamers Build)
-- Sistema de Dungeons com ondas de monstros, dificuldades e boss final
-- Lógica principal do servidor: estados, lobby, waves, dificuldade,
-- validação de requisitos, consumo de item e ranking SQL.
-- Coloque este arquivo em: Scripts\DungeonSystem\Dungeon.lua
-- ScriptMain.lua: requirefolder('Scripts\\DungeonSystem')
-- ==========================================================

local C = require("Scripts\\DungeonSystem\\Config")

-- ----------------------------------------------------------
-- CÓDIGOS DE PACOTE  (devem coincidir com DungeonHUD.lua)
-- ----------------------------------------------------------
local PKT_STATUS   = C.PACKET_ID        -- GS→CL: status de todas as dungeons
local PKT_JOINED   = C.PACKET_ID + 1    -- GS→CL: confirmação de inscrição
local PKT_TIMER    = C.PACKET_ID + 2    -- GS→CL: tick do timer de lobby
local PKT_WAVE     = C.PACKET_ID + 3    -- GS→CL: nova onda iniciada
local PKT_CLEAR    = C.PACKET_ID + 4    -- GS→CL: dungeon concluída
local PKT_OPEN_HUD = C.PACKET_ID + 5    -- GS→CL: abrir HUD no cliente
local PKT_PLAYER_INFO = C.PACKET_ID + 6 -- GS→CL: level/reset do player p/ HUD

local PKT_ENTER    = C.PACKET_ID        -- CL→GS: pedido de entrada (id + diffKey)

-- ----------------------------------------------------------
-- ESTADO GLOBAL
-- status: "idle" | "lobby" | "running" | "finished"
-- ----------------------------------------------------------
local State = {}
for id in pairs(C.DUNGEONS) do
    State[id] = {
        status        = "idle",
        players       = {},     -- { [charName] = true }
        diffKey       = "normal",
        onda          = 0,
        monstrosVivos = 0,
        timerInicio   = 0,
        bossX         = 0,
        bossY         = 0,
    }
end

-- Índices dos NPCs spawnados (para identificar no OnNpcTalk)
local _npcIndexes = {}

-- ----------------------------------------------------------
-- UTILITÁRIOS
-- ----------------------------------------------------------

local function tableCount(t)
    local n = 0; for _ in pairs(t) do n=n+1 end; return n
end

local function dungeonDoPlayer(name)
    for id, s in pairs(State) do
        if s.players[name] then return id end
    end
    return nil
end

local function msgDungeon(id, msg)
    for name in pairs(State[id].players) do
        local ai = GetObjectIndexByName(name)
        if ai and ai >= 0 then NoticeSend(ai, 1, msg) end
    end
end

-- ----------------------------------------------------------
-- LEVEL E RESET DO PLAYER
-- ⚠ VERIFICAR: confirme as funções corretas no seu emulador.
-- GetObjectLevel / GetObjectReset são os mais comuns no Louis S6.
-- ----------------------------------------------------------
local function getPlayerLevel(aIndex)
    if GetObjectLevel then return GetObjectLevel(aIndex) or 0 end
    return 0
end

local function getPlayerReset(aIndex)
    if GetObjectReset then return GetObjectReset(aIndex) or 0 end
    return 0
end

-- ----------------------------------------------------------
-- VALIDAÇÃO DE REQUISITOS
-- Retorna true se o player pode entrar, ou false + motivo
-- ----------------------------------------------------------
local function validarRequisitos(name, dungeonId, diffKey)
    local dg  = C.DUNGEONS[dungeonId]
    local s   = State[dungeonId]

    if s.status ~= "lobby" then
        return false, "Esta dungeon não está aceitando inscrições."
    end
    if s.players[name] then
        return false, "Você já está inscrito nesta dungeon."
    end
    local outra = dungeonDoPlayer(name)
    if outra then
        return false, string.format("Você já está inscrito na Dungeon %d.", outra)
    end
    if dg.maxPlayers > 0 and tableCount(s.players) >= dg.maxPlayers then
        return false, string.format("%s está cheia (%d/%d).", dg.nome, dg.maxPlayers, dg.maxPlayers)
    end

    -- Level
    local lv = getPlayerLevel(name)
    if lv < dg.reqLevel then
        return false, string.format("Nível insuficiente. Necessário: %d (seu: %d).", dg.reqLevel, lv)
    end

    -- Reset
    local rst = getPlayerReset(name)
    if rst < dg.reqReset then
        return false, string.format("Resets insuficientes. Necessário: %d (seu: %d).", dg.reqReset, rst)
    end

    -- Item obrigatório
    if dg.itemCode and dg.itemCode > 0 then
        local qty = InventoryCheckItem(name, dg.itemCode) or 0
        if qty < dg.itemQty then
            return false, string.format(
                "Item insuficiente: %s (necessário: %d, você tem: %d).",
                dg.itemNome, dg.itemQty, qty)
        end
    end

    -- Dificuldade válida para esta dungeon
    local diffValida = false
    for _, dk in ipairs(dg.dificuldades) do
        if dk == diffKey then diffValida = true; break end
    end
    if not diffValida then
        return false, "Dificuldade inválida para esta dungeon."
    end

    return true, nil
end

-- ----------------------------------------------------------
-- SQL
-- ----------------------------------------------------------

local function criarTabela()
    -- Verifica se a tabela já existe
    local ret = SQLQuery("SELECT TOP 1 CharName FROM DungeonRanking")
    if ret ~= 0 then
        SQLClose()
        LogColor(3, "[Dungeon] Tabela DungeonRanking OK.")
        return
    end
    SQLClose()

    -- Cria a tabela
    SQLQuery([[
        CREATE TABLE DungeonRanking (
            Account     VARCHAR(10) NOT NULL,
            CharName    VARCHAR(10) NOT NULL,
            DungeonID   INT         NOT NULL,
            Difficulty  VARCHAR(10) NOT NULL DEFAULT 'normal',
            Completions INT         NOT NULL DEFAULT 0,
            BestTime    INT         NOT NULL DEFAULT 0,
            LastRun     DATETIME,
            PRIMARY KEY (CharName, DungeonID, Difficulty)
        )
    ]])
    SQLClose()
    LogColor(3, "[Dungeon] Tabela DungeonRanking criada.")
end

local function salvarRanking(name, dungeonId, diffKey, tempoSeg)
    local account = GetObjectAccount(name)
    local agora   = os.date("%Y-%m-%d %H:%M:%S")

    -- Verifica se já existe registro
    local ret = SQLQuery(string.format(
        "SELECT TOP 1 Completions FROM DungeonRanking WHERE CharName='%s' AND DungeonID=%d AND Difficulty='%s'",
        name, dungeonId, diffKey))

    if ret ~= 0 and SQLFetch() ~= 100 then
        -- Atualiza
        SQLClose()
        SQLQuery(string.format(
            "UPDATE DungeonRanking SET Completions=Completions+1, BestTime=CASE WHEN BestTime=0 OR %d<BestTime THEN %d ELSE BestTime END, LastRun='%s' WHERE CharName='%s' AND DungeonID=%d AND Difficulty='%s'",
            tempoSeg, tempoSeg, agora, name, dungeonId, diffKey))
        SQLClose()
    else
        -- Insere novo
        SQLClose()
        SQLQuery(string.format(
            "INSERT INTO DungeonRanking(Account,CharName,DungeonID,Difficulty,Completions,BestTime,LastRun) VALUES('%s','%s',%d,'%s',1,%d,'%s')",
            account, name, dungeonId, diffKey, tempoSeg, agora))
        SQLClose()
    end
end

-- ----------------------------------------------------------
-- PACOTES GS → CL
-- ----------------------------------------------------------

local statusByte = { idle=0, lobby=1, running=2, finished=3 }

-- Envia status completo das 3 dungeons para um player
-- Pacote: [status_d1][players_d1][status_d2][players_d2][status_d3][players_d3]
local function enviarStatus(aIndex)
    local name = GetObjectName(aIndex)
    if not name or name == "" then return end
    local pkt = "DG_Status-" .. name
    CreatePacket(pkt, PKT_STATUS)
    for i = 1, 3 do
        local s = State[i] or { status="idle", players={} }
        SetBytePacket(pkt, statusByte[s.status] or 0)
        SetBytePacket(pkt, tableCount(s.players))
    end
    SendPacket(pkt, aIndex)
    ClearPacket(pkt)
end

local function broadcastStatus()
    LogColor(3, "[Dungeon] broadcastStatus inicio")
    local maxIdx = GetMaxUserIndex()
    LogColor(3, "[Dungeon] broadcastStatus maxIdx=" .. tostring(maxIdx))
    local count = 0
    for i = 0, maxIdx do
        local ok, connected = pcall(GetObjectConnected, i)
        if ok and connected then
            count = count + 1
            local ok2, err = pcall(enviarStatus, i)
            if not ok2 then
                LogColor(3, "[Dungeon] ERRO enviarStatus idx=" .. i .. " err=" .. tostring(err))
            end
        end
    end
    LogColor(3, "[Dungeon] broadcastStatus fim, players=" .. tostring(count))
end

-- Envia level e reset do player para a HUD calcular ✓/✗ localmente
local function enviarPlayerInfo(aIndex)
    local name = GetObjectName(aIndex)
    if not name or name == "" then return end
    local lv  = getPlayerLevel(aIndex)
    local rst = getPlayerReset(aIndex)
    local pkt = "DG_Info-" .. name
    CreatePacket(pkt, PKT_PLAYER_INFO)
    SetDwordPacket(pkt, lv)
    SetDwordPacket(pkt, rst)
    SendPacket(pkt, aIndex)
    ClearPacket(pkt)
end

local function enviarTimer(id, segsRestantes)
    for name in pairs(State[id].players) do
        local ai = GetObjectIndexByName(name)
        if ai and ai >= 0 then
            local pkt = "DG_Timer-" .. name
            CreatePacket(pkt, PKT_TIMER)
            SetBytePacket(pkt, id)
            SetDwordPacket(pkt, segsRestantes)
            SendPacket(pkt, ai)
            ClearPacket(pkt)
        end
    end
end

-- ----------------------------------------------------------
-- WAVE CONTROLLER
-- ----------------------------------------------------------

local iniciarOndaSeguinte  -- forward declaration

-- Aplica multiplicadores de dificuldade no spawn
-- ⚠ VERIFICAR: se o Louis suportar SetMonsterAttribute após MonsterCreate,
-- use-o aqui. Caso contrário, o multiplicador fica como referência de design.
local function spawnarOnda(id, ondaIdx)
    local cfg    = C.DUNGEONS[id]
    local s      = State[id]
    local onda   = cfg.ondas[ondaIdx]
    local diff   = C.DIFICULDADES[s.diffKey] or C.DIFICULDADES.normal

    if not onda then return 0 end

    local total = 0
    for _, mob in ipairs(onda.monstros) do
        for _ = 1, mob.qtd do
            local ox = onda.posX + math.random(-onda.range, onda.range)
            local oy = onda.posY + math.random(-onda.range, onda.range)
            local idx = MonsterCreate(cfg.mapa, mob.id, ox, oy)

            -- ⚠ VERIFICAR: aplicar multiplicadores se API disponível
            -- if idx and idx >= 0 then
            --     SetMonsterHP(idx,  GetMonsterHP(idx)  * diff.hp_mult)
            --     SetMonsterDmg(idx, GetMonsterDmg(idx) * diff.dmg_mult)
            --     SetMonsterDef(idx, GetMonsterDef(idx) * diff.def_mult)
            -- end

            total = total + 1
        end
    end

    if ondaIdx == #cfg.ondas then
        s.bossX = onda.posX
        s.bossY = onda.posY
    end

    return total
end

local function onMonsterMorreu(id)
    local s = State[id]
    if s.status ~= "running" then return end
    s.monstrosVivos = s.monstrosVivos - 1
    if s.monstrosVivos <= 0 then
        if s.onda >= #C.DUNGEONS[id].ondas then
            finalizarDungeon(id)
        else
            msgDungeon(id, string.format(
                "[Dungeon] Onda %d concluída! Próxima em %d segundos...",
                s.onda, C.INTERVALO_ONDAS))
            Timer.TimeOut(C.INTERVALO_ONDAS, function()
                if State[id].status == "running" then iniciarOndaSeguinte(id) end
            end)
        end
    end
end

iniciarOndaSeguinte = function(id)
    local s          = State[id]
    local cfg        = C.DUNGEONS[id]
    local totalOndas = #cfg.ondas
    s.onda           = s.onda + 1

    if s.onda == totalOndas then
        msgDungeon(id, "[Dungeon] ⚠️  BOSS APARECEU! Boa sorte!")
    else
        msgDungeon(id, string.format("[Dungeon] Onda %d/%d iniciada!", s.onda, totalOndas-1))
    end

    for name in pairs(s.players) do
        local ai = GetObjectIndexByName(name)
        if ai and ai >= 0 then
            local pkt = "DG_Wave-" .. name
            CreatePacket(pkt, PKT_WAVE)
            SetBytePacket(pkt, id)
            SetBytePacket(pkt, s.onda)
            SetBytePacket(pkt, totalOndas)
            SendPacket(pkt, ai)
            ClearPacket(pkt)
        end
    end

    s.monstrosVivos = spawnarOnda(id, s.onda)
end

-- ----------------------------------------------------------
-- LOBBY
-- ----------------------------------------------------------

local fecharLobbyEIniciar  -- forward declaration

local function abrirLobby(id)
    LogColor(3, "[Dungeon] STEP 1 - abrirLobby id=" .. tostring(id))
    
    local cfg = C.DUNGEONS[id]
    if not cfg then LogColor(3, "[Dungeon] ERRO: cfg nil"); return end
    LogColor(3, "[Dungeon] STEP 2 - cfg ok, nome=" .. tostring(cfg.nome))
    
    local s = State[id]
    if not s then LogColor(3, "[Dungeon] ERRO: State nil"); return end
    LogColor(3, "[Dungeon] STEP 3 - State ok")
    
    s.status        = "lobby"
    s.players       = {}
    s.onda          = 0
    s.monstrosVivos = 0
    s.diffKey       = cfg.dificuldades[1]
    LogColor(3, "[Dungeon] STEP 4 - status definido")

    LogColor(3, "[Dungeon] STEP 5 - antes NoticeSendToAll")
    NoticeSendToAll(1, "[Dungeon] " .. cfg.nome .. " esta aberta! (" .. tostring(cfg.tempoLobby) .. "s)")
    LogColor(3, "[Dungeon] STEP 6 - depois NoticeSendToAll")

    LogColor(3, "[Dungeon] STEP 7 - antes broadcastStatus")
    broadcastStatus()
    LogColor(3, "[Dungeon] STEP 8 - depois broadcastStatus")

    local restante = cfg.tempoLobby
    LogColor(3, "[Dungeon] STEP 9 - antes Timer.TimeOut")
    Timer.TimeOut(1, function()
        LogColor(3, "[Dungeon] TICK lobby id=" .. tostring(id))
        if State[id].status ~= "lobby" then return end
        restante = restante - 1
        if restante <= 0 then 
            fecharLobbyEIniciar(id)
        else
            Timer.TimeOut(1, function()
                if State[id].status == "lobby" then
                    restante = restante - 1
                    if restante <= 0 then fecharLobbyEIniciar(id) end
                end
            end)
        end
    end)
    LogColor(3, "[Dungeon] STEP 10 - abrirLobby concluido")
end

fecharLobbyEIniciar = function(id)
    local cfg = C.DUNGEONS[id]
    local s   = State[id]

    if tableCount(s.players) == 0 then
        s.status = "idle"
        broadcastStatus()
        NoticeSendToAll(1, string.format("[Dungeon] %s cancelada (sem inscritos).", cfg.nome))
        return
    end

    s.status      = "running"
    s.timerInicio = os.time()
    broadcastStatus()
    msgDungeon(id, string.format("[Dungeon] %s iniciada! Dificuldade: %s. Boa sorte!",
        cfg.nome, C.DIFICULDADES[s.diffKey].label))

    for name in pairs(s.players) do
        local ai = GetObjectIndexByName(name)
        if ai and ai >= 0 then
            MoveUserEx(ai, cfg.mapa, cfg.spawnX, cfg.spawnY)
        else
            s.players[name] = nil
        end
    end

    Timer.TimeOut(3, function()
        if State[id].status == "running" then iniciarOndaSeguinte(id) end
    end)
end

-- ----------------------------------------------------------
-- FINALIZAÇÃO E RECOMPENSAS
-- ----------------------------------------------------------

finalizarDungeon = function(id)
    local cfg    = C.DUNGEONS[id]
    local s      = State[id]
    local recomp = cfg.recompensa

    s.status = "finished"
    broadcastStatus()

    local tempoTotal = os.time() - s.timerInicio
    local min = math.floor(tempoTotal/60)
    local seg = tempoTotal % 60

    msgDungeon(id, string.format(
        "[Dungeon] %s CONCLUÍDA! [%s] Tempo: %dm%ds. Coletando recompensas...",
        cfg.nome, C.DIFICULDADES[s.diffKey].label, min, seg))

    for name in pairs(s.players) do
        local ai = GetObjectIndexByName(name)
        if ai ~= -1 then
            if recomp.wcoin and recomp.wcoin > 0 then
                ObjectAddCoin(ai, 0, 0, recomp.wcoin)
            end
            if recomp.zen and recomp.zen > 0 then
                SetObjectMoney(ai, (GetObjectMoney(ai) or 0) + recomp.zen)
                MoneySend(ai)
            end
            NoticeSend(ai, 1, string.format("[Dungeon] Recompensa: +%d WCoin, +%d Zen!",
                recomp.wcoin or 0, recomp.zen or 0))
        end
        salvarRanking(name, id, s.diffKey, tempoTotal)
    end

    if recomp.drops then
        for _, drop in ipairs(recomp.drops) do
            -- Drop no chão — ⚠ VERIFICAR função correta do seu build
            if ItemDropOnMap then
                ItemDropOnMap(cfg.mapa, drop.item * 512 + drop.subitem, s.bossX, s.bossY)
            end
        end
    end

    for name in pairs(s.players) do
        local ai = GetObjectIndexByName(name)
        if ai and ai >= 0 then
            local pkt = "DG_Clear-" .. name
            CreatePacket(pkt, PKT_CLEAR)
            SetBytePacket(pkt, id)
            SendPacket(pkt, ai)
            ClearPacket(pkt)
        end
    end

    Timer.TimeOut(10, function() retornarPlayers(id) end)
end

retornarPlayers = function(id)
    local cfg = C.DUNGEONS[id]
    for name in pairs(State[id].players) do
        local ai = GetObjectIndexByName(name)
        if ai and ai >= 0 then
            MoveUserEx(ai, cfg.retornoMapa, cfg.retornoX, cfg.retornoY)
        end
    end
    State[id] = { status="idle", players={}, diffKey="normal",
                  onda=0, monstrosVivos=0, timerInicio=0, bossX=0, bossY=0 }
    broadcastStatus()
end

-- ----------------------------------------------------------
-- COMANDOS GM
-- ----------------------------------------------------------

-- Verifica se o aIndex tem permissão de GM para comandos do Dungeon
local function _isGM(aIndex)
    -- Verifica lista de nomes configurada
    local name = tostring(GetObjectName(aIndex) or ""):lower()
    for _, n in ipairs(C.GM_NAMES or {}) do
        if name == tostring(n):lower() then return true end
    end
    -- Verifica autoridade GM nativa do emulador
    if GetObjectAuthority then
        if (tonumber(GetObjectAuthority(aIndex)) or 0) > 0 then return true end
    end
    return false
end

BridgeFunctionAttach('OnCommandManager', 'DungeonSystem_OnCommandManager')
function DungeonSystem_OnCommandManager(aIndex, cmd)

    -- /startdg [1|2|3]
    local startId = tonumber(cmd:match("^/startdg%s+(%d)$"))
    if startId then
        if not _isGM(aIndex) then
            NoticeSend(aIndex, 1, "[Dungeon] Sem permissao."); return true
        end
        if not C.DUNGEONS[startId] then
            NoticeSend(aIndex, 1, "[Dungeon] ID invalido. Use 1, 2 ou 3."); return true
        end
        if State[startId].status ~= "idle" then
            NoticeSend(aIndex, 1, string.format("[Dungeon] Dungeon %d ja esta ativa (%s).",
                startId, State[startId].status)); return true
        end
        abrirLobby(startId); return true
    end

    -- /stopdg [1|2|3]
    local stopId = tonumber(cmd:match("^/stopdg%s+(%d)$"))
    if stopId then
        if not _isGM(aIndex) then
            NoticeSend(aIndex, 1, "[Dungeon] Sem permissao."); return true
        end
        if not C.DUNGEONS[stopId] then
            NoticeSend(aIndex, 1, "[Dungeon] ID invalido. Use 1, 2 ou 3."); return true
        end
        if State[stopId].status == "idle" then
            NoticeSend(aIndex, 1, string.format("[Dungeon] Dungeon %d ja esta inativa.", stopId)); return true
        end
        msgDungeon(stopId, "[Dungeon] Evento encerrado pelo administrador.")
        retornarPlayers(stopId)
        NoticeSend(aIndex, 1, string.format("[Dungeon] Dungeon %d encerrada.", stopId)); return true
    end

    return false
end

-- ----------------------------------------------------------
-- PACOTE CL → GS: pedido de entrada
-- Payload: [dungeonId (1 byte)] [diffKey length (1 byte)] [diffKey string]
-- ----------------------------------------------------------
ProtocolFunctions.GameServerProtocol(function(aIndex, Packet, PacketName)
    if Packet ~= PKT_ENTER then return false end
    local name    = GetObjectName(aIndex)
    local id      = GetBytePacket(PacketName, -1)
    local dkLen   = GetBytePacket(PacketName, -1)
    local diffKey = ""
    for i = 0, dkLen-1 do
        diffKey = diffKey .. string.char(GetBytePacket(PacketName, -1))
    end
    -- (continua abaixo — fechamento do bloco ajustado)

    local cfg = C.DUNGEONS[id]
    if not cfg then return end

    local ok, motivo = validarRequisitos(name, id, diffKey)
    if not ok then
        local ai = GetObjectIndexByName(name)
        if ai and ai >= 0 then NoticeSend(ai, 1, "[Dungeon] " .. motivo) end
        return
    end

    -- Consome o item obrigatório
    if cfg.itemCode and cfg.itemCode > 0 then
        RemoveInventoryItem(name, cfg.itemCode, cfg.itemQty)
    end

    -- Registra o player
    State[id].players[name] = true

    -- Se for o primeiro a entrar, define a dificuldade do grupo
    if tableCount(State[id].players) == 1 then
        State[id].diffKey = diffKey
    end

    local _aiConfirm = GetObjectIndexByName(name)
    if _aiConfirm and _aiConfirm >= 0 then
        NoticeSend(_aiConfirm, 1, string.format(
            "[Dungeon] Inscricao confirmada em %s [%s]! (%d/%d inscritos)",
            cfg.nome, C.DIFICULDADES[diffKey].label,
            tableCount(State[id].players), cfg.maxPlayers))
    end

    local pkt = "DG_Joined-" .. name
    CreatePacket(pkt, PKT_JOINED)
    SetBytePacket(pkt, id)
    SetBytePacket(pkt, tableCount(State[id].players))
    SendPacket(pkt, aIndex)
    ClearPacket(pkt)
    return true
end)

-- ----------------------------------------------------------
-- EVENTOS DO SERVIDOR
-- ----------------------------------------------------------

BridgeFunctionAttach('OnCharacterEntry', 'DungeonSystem_OnCharacterEntry')
function DungeonSystem_OnCharacterEntry(aIndex)
    local name = GetObjectName(aIndex)
    Timer.TimeOut(2, function()
        if GetObjectConnected(aIndex) then
            enviarStatus(aIndex)
            enviarPlayerInfo(aIndex)
        end
    end)
end

BridgeFunctionAttach('OnCharacterClose', 'DungeonSystem_OnCharacterClose')
function DungeonSystem_OnCharacterClose(aIndex)
    local name = GetObjectName(aIndex)
    local id = dungeonDoPlayer(name)
    if not id then return end
    State[id].players[name] = nil
    if State[id].status == "running" and tableCount(State[id].players) == 0 then
        retornarPlayers(id)
    end
end

BridgeFunctionAttach('OnUserDie', 'DungeonSystem_OnUserDie')
function DungeonSystem_OnUserDie(aIndex)
    local name = GetObjectName(aIndex)
    local id = dungeonDoPlayer(name)
    if not id or State[id].status ~= "running" then return end
    local cfg = C.DUNGEONS[id]
    State[id].players[name] = nil
    Timer.TimeOut(3, function()
        if GetObjectConnected(aIndex) then
            MoveUserEx(aIndex, cfg.retornoMapa, cfg.retornoX, cfg.retornoY)
            NoticeSend(aIndex, 1, "[Dungeon] Voce foi eliminado.")
        end
    end)
end

BridgeFunctionAttach('OnMonsterDie', 'DungeonSystem_OnMonsterDie')
function DungeonSystem_OnMonsterDie(aIndex, monsterIndex, monsterClass)
    local mapId = GetObjectMap(monsterIndex)
    for id, cfg in pairs(C.DUNGEONS) do
        if cfg.mapa == mapId and State[id].status == "running" then
            onMonsterMorreu(id); break
        end
    end
end

BridgeFunctionAttach('OnNpcTalk', 'DungeonSystem_OnNpcTalk')
function DungeonSystem_OnNpcTalk(npcIndex, aIndex)
    if not _npcIndexes[npcIndex] then return 0 end
    local name = GetObjectName(aIndex)
    enviarStatus(aIndex)
    enviarPlayerInfo(aIndex)
    local pkt = "DG_Open-" .. name
    CreatePacket(pkt, PKT_OPEN_HUD)
    SetBytePacket(pkt, 1)
    SendPacket(pkt, aIndex)
    ClearPacket(pkt)
    return 1
end

if C.ITEM_OPEN_HUD > 0 then
    BridgeFunctionAttach('OnUseItem', 'DungeonSystem_OnUseItem')
    function DungeonSystem_OnUseItem(aIndex, itemPos, itemCode)
        if itemCode ~= C.ITEM_OPEN_HUD then return 0 end
        local name = GetObjectName(aIndex)
        enviarStatus(aIndex)
        enviarPlayerInfo(aIndex)
        local pkt = "DG_Open-" .. name
        CreatePacket(pkt, PKT_OPEN_HUD)
        SetBytePacket(pkt, 1)
        SendPacket(pkt, aIndex)
        ClearPacket(pkt)
        return 1
    end
end

-- ----------------------------------------------------------
-- INICIALIZAÇÃO  (padrão Louis: OnReadScript garante que o banco
-- já está disponível antes de executar qualquer SQL)
-- ----------------------------------------------------------

local function _spawnNpc()
    if not C.NPC_CODE or C.NPC_CODE <= 0 then return end
    if not C.NPC_SPAWNS then return end
    for _, sp in ipairs(C.NPC_SPAWNS) do
        local idx = MonsterCreate(C.NPC_CODE, sp.map, sp.x, sp.y, sp.dir or 3)
        if idx and idx >= 0 then
            _npcIndexes[idx] = true
            LogColor(3, "[Dungeon] NPC Mestre spawnado idx=" .. tostring(idx) ..
                " map=" .. sp.map .. " x=" .. sp.x .. " y=" .. sp.y)
        end
    end
end

BridgeFunctionAttach('OnReadScript', 'DungeonSystem_OnReadScript')
function DungeonSystem_OnReadScript()
    criarTabela()
    _spawnNpc()
    LogColor(3, "[Dungeon] GAS_Games Dungeon System carregado.")
end