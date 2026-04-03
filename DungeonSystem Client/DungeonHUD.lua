-- ==========================================================
-- Script Criado por GAS_Games
-- DungeonHUD.lua - (CLIENT) Season 6 Louis Emulator (IgkGamers Build)
-- Sistema de Dungeons com ondas de monstros, dificuldades e boss final
-- HUD 2 colunas: lista à esquerda, detalhes à direita.
-- Boss renderizado via RenderMonster (modelo 3D animado ao vivo).
-- Coloque este arquivo em: Scripts\DungeonSystem\DungeonHUD.lua
-- ScriptMain.lua: requirefolder('Scripts\\DungeonSystem')
-- ==========================================================

-- ----------------------------------------------------------
-- CÓDIGOS DE PACOTE  (devem coincidir com Dungeon.lua)
-- ----------------------------------------------------------
local PACKET_ID       = 0xF0
local PKT_STATUS      = PACKET_ID        -- GS→CL: status das dungeons
local PKT_JOINED      = PACKET_ID + 1    -- GS→CL: confirmação de inscrição
local PKT_TIMER       = PACKET_ID + 2    -- GS→CL: tick do timer de lobby
local PKT_WAVE        = PACKET_ID + 3    -- GS→CL: nova onda
local PKT_CLEAR       = PACKET_ID + 4    -- GS→CL: dungeon concluída
local PKT_OPEN_HUD    = PACKET_ID + 5    -- GS→CL: abrir HUD
local PKT_PLAYER_INFO = PACKET_ID + 6    -- GS→CL: level/reset do player
local PKT_ENTER       = PACKET_ID        -- CL→GS: pedido de entrada

-- ----------------------------------------------------------
-- IDs DAS IMAGENS TGA
-- Registre no LoadImages.lua:
--   LoadBitmap("Data\\Custom\\ScriptImages\\NOME.tga", ID)
-- ----------------------------------------------------------
local IMG = {
    BG             = 53000,   -- dg_bg.tga           270×190
    HEADER         = 53001,   -- dg_header.tga        270×18
    BTN_DG         = 53002,   -- dg_btn.tga            83×20
    BTN_DG_SEL     = 53003,   -- dg_btn_sel.tga        83×20
    BTN_ENTER      = 53004,   -- dg_btn_enter.tga      90×15
    BTN_ENTER_OFF  = 53005,   -- dg_btn_enter_off.tga  90×15
    BTN_ENTER_OK   = 53006,   -- dg_btn_enter_ok.tga   90×15
    ARROW_L        = 53007,   -- dg_arrow_l.tga         8×8
    ARROW_R        = 53008,   -- dg_arrow_r.tga         8×8
    CLOSE          = 53009,   -- dg_close.tga          10×10
    TIMER_BG       = 53013,   -- dg_timer_bg.tga      100×4
    TIMER_FILL     = 53014,   -- dg_timer_fill.tga    100×4
    -- TGAs de boss REMOVIDAS — usamos RenderMonster
}

-- ----------------------------------------------------------
-- CONFIGURAÇÃO DOS BOSSES  (RenderMonster)
-- monsterCode: código do monstro no servidor
-- scale:       tamanho do render 3D (ajuste conforme o modelo)
-- offsetX/Y:   ajuste fino de posição dentro da área do retrato
-- ----------------------------------------------------------
local BOSS_RENDER = {
    [1] = { monsterCode=875,  scale=4.5, offsetX=0, offsetY=0 },
    [2] = { monsterCode=893,  scale=0.8, offsetX=0, offsetY=0 },
    [3] = { monsterCode=894,  scale=0.9, offsetX=0, offsetY=0 },
}

-- Handles dos modelos carregados (preenchido no init)
local bossHandles = { [1]=-1, [2]=-1, [3]=-1 }

-- ----------------------------------------------------------
-- CONFIGURAÇÃO DAS DUNGEONS  (espelho do Config.lua)
-- ----------------------------------------------------------
local DG_CFG = {
    [1] = {
        nome         = "Dungeon das Sombras",
        bossNome     = "Sombra Corrompida",
        dificuldades = { "normal", "hard" },
        reqLevel     = 200,  reqReset  = 0,
        itemNome     = "Joia da Alma", itemQty = 1,
        tempoLobby   = 120,  totalOndas = 4,
    },
    [2] = {
        nome         = "Caverna do Caos",
        bossNome     = "Lich do Caos",
        dificuldades = { "normal", "hard", "extreme" },
        reqLevel     = 280,  reqReset  = 1,
        itemNome     = "Joia do Caos", itemQty = 3,
        tempoLobby   = 120,  totalOndas = 5,
    },
    [3] = {
        nome         = "Abismo Eterno",
        bossNome     = "Senhor do Abismo",
        dificuldades = { "normal", "hard", "extreme" },
        reqLevel     = 380,  reqReset  = 3,
        itemNome     = "Cristal Abisal", itemQty = 5,
        tempoLobby   = 120,  totalOndas = 6,
    },
}

local DIFF_INFO = {
    normal  = { label="Normal",  hp=100, dmg=100, def=100 },
    hard    = { label="Hard",    hp=150, dmg=130, def=120 },
    extreme = { label="Extreme", hp=200, dmg=180, def=160 },
}

-- ----------------------------------------------------------
-- DIMENSÕES DO PAINEL  (270×190 = ~50% do original)
-- RenderText5 tem altura fixa de ~10px — layout ajustado para isso.
-- ----------------------------------------------------------
local W       = 270   -- largura total do painel
local H       = 190   -- altura total
local HDR_H   = 18    -- altura do header
local COL_L   = 89    -- largura da coluna esquerda (lista)
local DIV     = 1     -- largura do divisor

-- Coluna direita começa em COL_L + DIV
local RX_OFF  = COL_L + DIV + 6   -- offset X dentro do painel para a col. direita
local RW      = W - COL_L - DIV - 10  -- largura útil da col. direita

-- Lista esquerda
local BTN_H   = 20    -- altura de cada botão da lista
local BTN_GAP = 2     -- espaçamento entre botões
local LST_Y0  = HDR_H + 6   -- Y de início da lista

-- Área do boss (RenderMonster)
local BOSS_AREA_W = 36   -- largura da área reservada ao render do boss
local BOSS_AREA_H = 36   -- altura

-- Botão Entrar
local ENTER_W = 90
local ENTER_H = 15

-- Posição inicial (nil = centraliza na tela)
local INIT_X  = nil
local INIT_Y  = 80

-- ----------------------------------------------------------
-- ESTADO DA HUD
-- ----------------------------------------------------------
local HUD = {
    visible   = false,
    x = nil, y = nil,
    dragging  = false,
    dragOffX  = 0, dragOffY = 0,
    selected  = 1,

    dungeons = {
        [1] = { status=0, players=0, inscrito=false, timerAtual=0, onda=0, totalOndas=0 },
        [2] = { status=0, players=0, inscrito=false, timerAtual=0, onda=0, totalOndas=0 },
        [3] = { status=0, players=0, inscrito=false, timerAtual=0, onda=0, totalOndas=0 },
    },

    diffIdx     = { 1, 1, 1 },   -- índice da dificuldade selecionada por dungeon
    playerLevel = 0,
    playerReset = 0,
}

local STATUS_LABEL = { [0]="Fechada", [1]="Aberta", [2]="Em Andamento", [3]="Concluida" }

-- Cores de status
local STATUS_COLOR = {
    [0] = { 80,  80,  80 },
    [1] = { 60, 200,  80 },
    [2] = {220, 130,  30 },
    [3] = { 80, 160, 220 },
}

-- ----------------------------------------------------------
-- UTILITÁRIOS
-- ----------------------------------------------------------

local function sc(r, g, b, a)
    SetTextColor(r, g, b, a or 255)
end

local function over(mx, my, x, y, w, h)
    return mx >= x and mx <= x+w and my >= y and my <= y+h
end

local function getPos()
    local sx = INIT_X or math.floor((GetWideX() - W) / 2)
    return HUD.x or sx, HUD.y or INIT_Y
end

local function fmtTimer(s)
    s = math.max(0, math.floor(s))
    return string.format("%02d:%02d", math.floor(s/60), s%60)
end

local function getDiffKey(dgId)
    local dg  = DG_CFG[dgId]
    local idx = HUD.diffIdx[dgId] or 1
    return dg.dificuldades[idx] or "normal"
end

local function checkReqs(dgId)
    local dg = DG_CFG[dgId]
    return HUD.playerLevel >= dg.reqLevel,
           HUD.playerReset >= dg.reqReset
end

-- ----------------------------------------------------------
-- RENDER — COLUNA ESQUERDA
-- Layout: título, 3 botões de dungeon com status
-- RenderText5 usa ~10px de altura
-- ----------------------------------------------------------
local function renderLeft(wx, wy)
    -- Título da coluna
    sc(160, 140, 90, 180)
    RenderText5(wx + 4, wy + HDR_H + 3, "Selec. Dungeon", 0, 0)

    -- Linha separadora abaixo do título
    sc(55, 42, 18, 160)
    RenderText5(wx + 4, wy + HDR_H + 13, "─────────────", 0, 0)

    for i = 1, 3 do
        local info = HUD.dungeons[i]
        local by   = wy + LST_Y0 + 18 + (i-1) * (BTN_H + BTN_GAP)
        local bx   = wx + 3

        -- Fundo do botão
        local btnImg = (HUD.selected == i) and IMG.BTN_DG_SEL or IMG.BTN_DG
        RenderImage(btnImg, bx, by, COL_L - 6, BTN_H)

        -- Ponto de status
        local sc3 = STATUS_COLOR[info.status] or STATUS_COLOR[0]
        sc(sc3[1], sc3[2], sc3[3], 255)
        RenderText5(bx + 3, by + 3, "●", 0, 0)

        -- Nome da dungeon (abreviado para caber)
        if HUD.selected == i then
            sc(230, 200, 100, 255)
        else
            sc(185, 170, 135, 220)
        end
        -- Exibe só as primeiras ~12 chars para caber na coluna estreita
        local nome = DG_CFG[i].nome
        if #nome > 13 then nome = nome:sub(1,12) .. "." end
        RenderText5(bx + 12, by + 3, nome, 0, 0)

        -- Status abaixo do nome
        sc(100, 92, 68, 180)
        RenderText5(bx + 12, by + 12, STATUS_LABEL[info.status] or "?", 0, 0)
    end
end

-- ----------------------------------------------------------
-- RENDER — COLUNA DIREITA
-- Layout ajustado linha a linha para RenderText5 (~10px/linha)
-- ----------------------------------------------------------
local function renderRight(wx, wy)
    local i    = HUD.selected
    local dg   = DG_CFG[i]
    local info = HUD.dungeons[i]
    local st   = info.status
    local rx   = wx + RX_OFF
    local ry   = wy + HDR_H + 4   -- Y inicial da coluna direita

    -- ── Nome da dungeon ──────────────────────────────────
    sc(220, 195, 110, 255)
    RenderText5(rx, ry, dg.nome, 0, 0)

    -- Badge de status (alinhado à direita)
    local sc3 = STATUS_COLOR[st] or STATUS_COLOR[0]
    sc(sc3[1], sc3[2], sc3[3], 220)
    local badge = "[" .. (STATUS_LABEL[st] or "?") .. "]"
    RenderText5(rx + RW - #badge * 5, ry, badge, 0, 0)

    ry = ry + 12

    -- ── Separador ────────────────────────────────────────
    sc(60, 48, 20, 160)
    RenderText5(rx, ry, "───────────────────────", 0, 0)
    ry = ry + 9

    -- ── Boss (RenderMonster + nome) ───────────────────────
    local br    = BOSS_RENDER[i]
    local bossX = rx
    local bossY = ry

    -- Área de fundo do boss (retrato)
    -- Desenhamos um retângulo escuro como "moldura"
    sc(30, 20, 10, 200)
    -- Usando RenderText5 como "bloco" não funciona — usamos o próprio
    -- RenderMonster que ocupa a área BOSS_AREA_W × BOSS_AREA_H

    -- RenderMonster: (handle, screenX, screenY, scale)
    -- O modelo é centralizado no ponto X,Y pelo Louis
    -- Ajustamos para ficar dentro da área do retrato
    if bossHandles[i] and bossHandles[i] >= 0 then
        RenderMonster(
            bossHandles[i],
            bossX + math.floor(BOSS_AREA_W/2) + br.offsetX,
            bossY + BOSS_AREA_H + br.offsetY,
            br.scale
        )
    end

    -- Info do boss ao lado do render
    local infoX = rx + BOSS_AREA_W + 4
    sc(110, 90, 70, 180)
    RenderText5(infoX, bossY, "Boss Final", 0, 0)
    sc(200, 130, 130, 255)
    RenderText5(infoX, bossY + 11, dg.bossNome, 0, 0)

    -- Seletor de dificuldade (ao lado do boss info)
    local diffKey  = getDiffKey(i)
    local diffInfo = DIFF_INFO[diffKey] or DIFF_INFO.normal
    local hasL = HUD.diffIdx[i] > 1
    local hasR = HUD.diffIdx[i] < #dg.dificuldades

    local diffY  = bossY + 23
    local arrowLX = infoX

    sc(110, 90, 70, 160)
    RenderText5(infoX, diffY, "Dific.:", 0, 0)

    -- Seta esquerda
    if hasL then sc(200, 160, 80, 255) else sc(55, 45, 22, 140) end
    RenderImage(IMG.ARROW_L, arrowLX + 38, diffY, 8, 8)

    -- Label de dificuldade
    if diffKey == "normal"   then sc(90, 210, 70, 255)
    elseif diffKey == "hard"  then sc(220, 130, 45, 255)
    else                          sc(210,  65, 65, 255) end
    RenderText5(arrowLX + 48, diffY, diffInfo.label, 0, 0)

    -- Seta direita
    if hasR then sc(200, 160, 80, 255) else sc(55, 45, 22, 140) end
    local labelW = #diffInfo.label * 6
    RenderImage(IMG.ARROW_R, arrowLX + 50 + labelW, diffY, 8, 8)

    ry = bossY + BOSS_AREA_H + 4

    -- ── Separador ────────────────────────────────────────
    sc(60, 48, 20, 160)
    RenderText5(rx, ry, "───────────────────────", 0, 0)
    ry = ry + 9

    -- ── Stats de dificuldade ──────────────────────────────
    sc(140, 125, 85, 200)
    RenderText5(rx, ry, "Monstros:", 0, 0)

    sc(100, 90, 65, 180)
    RenderText5(rx + 44, ry, "HP", 0, 0)
    RenderText5(rx + 68, ry, "DMG", 0, 0)
    RenderText5(rx + 96, ry, "DEF", 0, 0)

    ry = ry + 10

    if diffKey == "normal"   then sc(90, 200, 70, 255)
    elseif diffKey == "hard"  then sc(210, 120, 40, 255)
    else                          sc(200,  55, 55, 255) end
    RenderText5(rx + 44, ry, diffInfo.hp  .. "%", 0, 0)
    RenderText5(rx + 68, ry, diffInfo.dmg .. "%", 0, 0)
    RenderText5(rx + 96, ry, diffInfo.def .. "%", 0, 0)

    ry = ry + 11

    -- ── Requisitos ────────────────────────────────────────
    local lvOk, rstOk = checkReqs(i)

    sc(140, 125, 85, 200)
    RenderText5(rx, ry, "Requisitos:", 0, 0)
    ry = ry + 10

    sc(100, 90, 65, 180)
    RenderText5(rx + 2, ry, "Nivel:", 0, 0)
    if lvOk then sc(70, 200, 70, 255) else sc(200, 60, 60, 255) end
    RenderText5(rx + 32, ry, string.format("%d (%d)%s", dg.reqLevel, HUD.playerLevel, lvOk and " v" or " x"), 0, 0)

    ry = ry + 10
    sc(100, 90, 65, 180)
    RenderText5(rx + 2, ry, "Reset:", 0, 0)
    if rstOk then sc(70, 200, 70, 255) else sc(200, 60, 60, 255) end
    RenderText5(rx + 32, ry, string.format("%d (%d)%s", dg.reqReset, HUD.playerReset, rstOk and " v" or " x"), 0, 0)

    ry = ry + 11

    -- ── Item obrigatório ──────────────────────────────────
    sc(140, 125, 85, 200)
    RenderText5(rx, ry, "Item: ", 0, 0)
    sc(160, 145, 100, 220)
    RenderText5(rx + 26, ry, dg.itemNome, 0, 0)
    sc(200, 185, 130, 200)
    RenderText5(rx + RW - 18, ry, "x" .. dg.itemQty, 0, 0)

    ry = ry + 11

    -- ── Timer de lobby ────────────────────────────────────
    if st == 1 then
        local pct = dg.tempoLobby > 0
            and math.max(0, math.min(1, info.timerAtual / dg.tempoLobby))
            or 0

        sc(100, 90, 65, 180)
        RenderText5(rx, ry, string.format("Inscritos: %d", info.players), 0, 0)
        sc(190, 170, 75, 255)
        RenderText5(rx + RW - 28, ry, fmtTimer(info.timerAtual), 0, 0)
        ry = ry + 10

        RenderImage(IMG.TIMER_BG,   rx, ry, RW, 4)
        if pct > 0 then
            RenderImage(IMG.TIMER_FILL, rx, ry, math.floor(RW * pct), 4)
        end
    end

    if st == 2 then
        local ondaLabel
        if info.onda > 0 and info.totalOndas > 0 then
            if info.onda == info.totalOndas then
                ondaLabel = ">> BOSS EM ANDAMENTO"
            else
                ondaLabel = string.format("Onda %d/%d", info.onda, info.totalOndas - 1)
            end
        else
            ondaLabel = "Em andamento..."
        end
        if info.onda == info.totalOndas then sc(220, 60, 60, 255)
        else                                 sc(210, 140, 40, 220) end
        RenderText5(rx, ry, ondaLabel, 0, 0)
    end

    -- ── Botão Entrar ──────────────────────────────────────
    local btnY = wy + H - ENTER_H - 6
    local btnX = wx + COL_L + DIV + math.floor((W - COL_L - DIV - ENTER_W) / 2)

    local canEnter = (st == 1) and not info.inscrito and lvOk and rstOk

    if info.inscrito then
        RenderImage(IMG.BTN_ENTER_OK, btnX, btnY, ENTER_W, ENTER_H)
        sc(80, 220, 90, 255)
        RenderText5(btnX + 28, btnY + 3, "INSCRITO  v", 0, 0)
    elseif canEnter then
        RenderImage(IMG.BTN_ENTER, btnX, btnY, ENTER_W, ENTER_H)
        sc(130, 230, 70, 255)
        RenderText5(btnX + 30, btnY + 3, "ENTRAR", 0, 0)
    else
        RenderImage(IMG.BTN_ENTER_OFF, btnX, btnY, ENTER_W, ENTER_H)
        sc(85, 80, 58, 170)
        local lbl = st == 1 and "REQ. NAO ATEND."
                 or st == 2 and "EM ANDAMENTO"
                 or st == 3 and "CONCLUIDA"
                 or "FECHADA"
        RenderText5(btnX + 8, btnY + 3, lbl, 0, 0)
    end
end

-- ----------------------------------------------------------
-- RENDER PRINCIPAL
-- ----------------------------------------------------------
local function renderHUD()
    if not HUD.visible then return end

    local wx, wy = getPos()

    -- Painel de fundo
    RenderImage(IMG.BG, wx, wy, W, H)

    -- Header
    RenderImage(IMG.HEADER, wx, wy, W, HDR_H)
    sc(220, 195, 110, 255)
    RenderText5(wx + math.floor(W/2) - 20, wy + 4, "DUNGEON", W, 0)

    -- Botão fechar
    RenderImage(IMG.CLOSE, wx + W - 14, wy + 4, 10, 10)

    -- Colunas
    renderLeft(wx, wy)
    renderRight(wx, wy)
end

-- ----------------------------------------------------------
-- UPDATE MOUSE  (padrão NpcRescue / Louis v40)
-- Chamado a cada frame via MainInterfaceProcThread.
-- Centraliza: lock de walk, drag, cliques e envio de pacotes.
-- ----------------------------------------------------------
local function updateMouse()
    if not HUD.visible then return end

    local mx, my = MousePosX(), MousePosY()
    local wx, wy = getPos()

    -- Drag ativo: atualiza posição da janela
    if HUD.dragging then
        if CheckReleasedKey(Keys.LButton) == 1 then
            HUD.dragging = false
        else
            HUD.x = math.max(0, math.min(GetWideX() - W, mx - HUD.dragOffX))
            HUD.y = math.max(0, math.min(GetWideY() - H, my - HUD.dragOffY))
        end
        return
    end

    -- Lock de walk quando mouse está sobre a janela
    if over(mx, my, wx, wy, W, H) then
        LockPlayerWalk()
    else
        UnlockPlayerWalk()
    end

    -- Processa clique esquerdo
    if CheckReleasedKey(Keys.LButton) == 1 then
        if not over(mx, my, wx, wy, W, H) then return end

        -- Consome o clique (não vaza para o jogo)
        ResetMouseL()

        -- Botão fechar
        if over(mx, my, wx + W - 14, wy + 4, 10, 10) then
            HUD.visible = false
            UnlockPlayerWalk()
            return
        end

        -- Drag pelo header
        if over(mx, my, wx, wy, W, HDR_H) then
            HUD.dragging = true
            HUD.dragOffX = mx - wx
            HUD.dragOffY = my - wy
            return
        end

        -- Botões da lista esquerda (seleciona dungeon)
        for i = 1, 3 do
            local by = wy + LST_Y0 + 18 + (i-1) * (BTN_H + BTN_GAP)
            if over(mx, my, wx + 3, by, COL_L - 6, BTN_H) then
                HUD.selected = i
                return
            end
        end

        -- Setas de dificuldade (coluna direita)
        local sel     = HUD.selected
        local dg      = DG_CFG[sel]
        local infoX   = wx + RX_OFF + BOSS_AREA_W + 4
        local diffY   = wy + HDR_H + 4 + 12 + 9 + 23
        local arrowLX = infoX + 38

        if over(mx, my, arrowLX, diffY, 8, 8) then
            if HUD.diffIdx[sel] > 1 then
                HUD.diffIdx[sel] = HUD.diffIdx[sel] - 1
            end
            return
        end
        local diffKey = getDiffKey(sel)
        local labelW  = #(DIFF_INFO[diffKey] or DIFF_INFO.normal).label * 6
        local arrowRX = arrowLX + 10 + labelW + 2
        if over(mx, my, arrowRX, diffY, 8, 8) then
            if HUD.diffIdx[sel] < #dg.dificuldades then
                HUD.diffIdx[sel] = HUD.diffIdx[sel] + 1
            end
            return
        end

        -- Botão Entrar
        local info         = HUD.dungeons[sel]
        local lvOk, rstOk  = checkReqs(sel)
        local canEnter     = (info.status == 1) and not info.inscrito and lvOk and rstOk
        local btnY = wy + H - ENTER_H - 6
        local btnX = wx + COL_L + DIV + math.floor((W - COL_L - DIV - ENTER_W) / 2)

        if canEnter and over(mx, my, btnX, btnY, ENTER_W, ENTER_H) then
            local dk    = getDiffKey(sel)
            local dkLen = #dk
            local p     = CreatePacket(PKT_ENTER, 2 + dkLen)
            SetPacketByte(p, 1, sel)
            SetPacketByte(p, 2, dkLen)
            for c = 1, dkLen do
                SetPacketByte(p, 2 + c, string.byte(dk, c))
            end
            SendPacket(p)
            return
        end
    end
end

-- ----------------------------------------------------------
-- PACOTES DO SERVIDOR  (padrão Louis v40)
-- ----------------------------------------------------------
local PKT_PREFIX = {
    ["DG_Status"]  = PKT_STATUS,
    ["DG_Joined"]  = PKT_JOINED,
    ["DG_Timer"]   = PKT_TIMER,
    ["DG_Wave"]    = PKT_WAVE,
    ["DG_Clear"]   = PKT_CLEAR,
    ["DG_Open"]    = PKT_OPEN_HUD,
    ["DG_Info"]    = PKT_PLAYER_INFO,
}

ProtocolFunctions.ClientProtocol(function(Packet, PacketName)
    -- Filtra só pacotes do sistema Dungeon
    local prefix = PacketName:match("^(DG_%a+)%-")
    if not prefix then return false end
    if not PKT_PREFIX[prefix] then return false end

    local code = Packet

    if code == PKT_STATUS then
        for i = 1, 3 do
            HUD.dungeons[i].status  = GetBytePacket(PacketName, -1)
            HUD.dungeons[i].players = GetBytePacket(PacketName, -1)
        end
        ClearPacket(PacketName)
        return true
    end

    if code == PKT_JOINED then
        local id = GetBytePacket(PacketName, -1)
        local pl = GetBytePacket(PacketName, -1)
        if HUD.dungeons[id] then
            HUD.dungeons[id].inscrito = true
            HUD.dungeons[id].players  = pl
        end
        ClearPacket(PacketName)
        return true
    end

    if code == PKT_TIMER then
        local id   = GetBytePacket(PacketName, -1)
        local secs = GetDwordPacket(PacketName, -1)
        if HUD.dungeons[id] then
            HUD.dungeons[id].timerAtual = secs
        end
        ClearPacket(PacketName)
        return true
    end

    if code == PKT_WAVE then
        local id    = GetBytePacket(PacketName, -1)
        local atual = GetBytePacket(PacketName, -1)
        local total = GetBytePacket(PacketName, -1)
        if HUD.dungeons[id] then
            HUD.dungeons[id].onda       = atual
            HUD.dungeons[id].totalOndas = total
        end
        ClearPacket(PacketName)
        return true
    end

    if code == PKT_CLEAR then
        local id = GetBytePacket(PacketName, -1)
        if HUD.dungeons[id] then
            HUD.dungeons[id].inscrito   = false
            HUD.dungeons[id].onda       = 0
            HUD.dungeons[id].totalOndas = 0
        end
        ClearPacket(PacketName)
        return true
    end

    if code == PKT_OPEN_HUD then
        HUD.visible = true
        ClearPacket(PacketName)
        return true
    end

    if code == PKT_PLAYER_INFO then
        HUD.playerLevel = GetDwordPacket(PacketName, -1)
        HUD.playerReset = GetDwordPacket(PacketName, -1)
        ClearPacket(PacketName)
        return true
    end

    return false
end)

-- ----------------------------------------------------------
-- LAZY LOADING DOS BOSSES
-- LoadMonster só é chamado quando a HUD abre pela primeira vez,
-- nunca durante o carregamento do script (evita crash R6030).
-- ----------------------------------------------------------
local bossesCarregados = false

local function carregarBosses()
    if bossesCarregados then return end
    bossesCarregados = true
    for id, br in pairs(BOSS_RENDER) do
        local ok, handle = pcall(LoadMonster, br.monsterCode)
        if ok and handle and handle >= 0 then
            bossHandles[id] = handle
        else
            bossHandles[id] = -1
        end
    end
end

-- ----------------------------------------------------------
-- REGISTRO NO LOUIS  (padrão Louis v40 / IgkGamers)
-- BridgeFunctionAttach EXIGE funções globais nomeadas —
-- o ScriptCore chama via _G[nome]() e anônimas causam loop de erro.
-- ----------------------------------------------------------

BridgeFunctionAttach('MainInterfaceProcThread', 'DungeonHUD_Render')
function DungeonHUD_Render()
    if HUD.visible and not bossesCarregados then
        carregarBosses()
    end
    renderHUD()
end

BridgeFunctionAttach('UpdateMouseEvent', 'DungeonHUD_UpdateMouse')
function DungeonHUD_UpdateMouse()
    updateMouse()
end

BridgeFunctionAttach('KeyboardEvent', 'DungeonHUD_KeyboardEvent')
function DungeonHUD_KeyboardEvent(key)
    if key == Keys.Insert then
        HUD.visible = not HUD.visible
        if not HUD.visible then UnlockPlayerWalk() end
    end
end

print("[DungeonHUD] GAS_Games Dungeon HUD v3 carregada.")