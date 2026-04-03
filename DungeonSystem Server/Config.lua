-- ==========================================================
-- Script Criado por GAS_Games
-- Config.lua - (SERVER) Season 6 Louis Emulator (IgkGamers Build)
-- Sistema de Dungeons com ondas de monstros, dificuldades e boss final
-- Todas as configurações do evento. Edite aqui sem mexer na lógica principal.
-- Coloque este arquivo em: Scripts\DungeonSystem\Config.lua
-- ScriptMain.lua: requirefolder('Scripts\\DungeonSystem')
-- ==========================================================

local C = {}

-- ----------------------------------------------------------
-- CONFIGURAÇÕES GERAIS
-- ----------------------------------------------------------

-- Código do NPC Mestre de Dungeon (abre HUD ao conversar)
-- Use 0 para desativar o NPC (abrir HUD só via item ou INSERT)
C.NPC_CODE = 888

-- Locais onde o NPC Mestre de Dungeon aparece no mapa
-- { map=MapNumber, x=X, y=Y, dir=Direcao }
C.NPC_SPAWNS = {
    { map=0, x=130, y=133, dir=3 },  -- Lorencia
    -- { map=2, x=218, y=21, dir=3 }, -- Devias (descomente para ativar)
}

-- Código do item para abrir a HUD (0 = desativado)
C.ITEM_OPEN_HUD = 0

-- Lista de nomes com permissão para usar /startdg e /stopdg
-- (além dos GMs com autoridade configurada no emulador)
C.GM_NAMES = { "Admin", "GUDM" }

-- Segundos de espera entre fim de uma onda e início da próxima
C.INTERVALO_ONDAS = 3

-- String de conexão ODBC
C.DB_CONN = "MuOnline"

-- Código base dos pacotes GS <-> CL (deve coincidir com DungeonHUD.lua)
-- Intervalo usado: PACKET_ID+0 até PACKET_ID+6
C.PACKET_ID = 0xF0

-- ----------------------------------------------------------
-- DIFICULDADES GLOBAIS
-- Multiplicadores aplicados aos atributos dos monstros no spawn.
--   hp_mult  : multiplicador de HP    (1.0 = 100%)
--   dmg_mult : multiplicador de Dano
--   def_mult : multiplicador de Defesa
-- ----------------------------------------------------------
C.DIFICULDADES = {
    normal  = { label="Normal",  hp_mult=1.0, dmg_mult=1.0, def_mult=1.0 },
    hard    = { label="Hard",    hp_mult=1.5, dmg_mult=1.3, def_mult=1.2 },
    extreme = { label="Extreme", hp_mult=2.0, dmg_mult=1.8, def_mult=1.6 },
}

-- Ordem de exibição na HUD (setas ◀ ▶)
C.DIFICULDADE_ORDEM = { "normal", "hard", "extreme" }

-- ----------------------------------------------------------
-- DUNGEONS
-- ----------------------------------------------------------
C.DUNGEONS = {

    -- ======================================================
    -- DUNGEON 1
    -- ======================================================
    [1] = {
        -- Nome exibido na HUD
        nome = "Dungeon das Sombras",

        -- Boss (nome exibido na HUD + ID da TGA do retrato)
        -- TGA: Data\Custom\ScriptImages\dg1_boss.tga (64x64, BGRA 32-bit)
        bossNome = "Sombra Corrompida",
        bossTGA  = 53010,   -- ID registrado no LoadImages.lua

        -- Mapa e coordenadas
        mapa   = 99, spawnX=128, spawnY=109,
        retornoMapa=0, retornoX=125, retornoY=125,

        -- Lobby
        tempoLobby = 120,   -- segundos para inscrição
        maxPlayers = 10,    -- 0 = sem limite

        -- Dificuldades disponíveis nesta dungeon
        dificuldades = { "normal", "hard" },

        -- --------------------------------------------------
        -- REQUISITOS DE ENTRADA (validados no servidor)
        -- --------------------------------------------------
        reqLevel = 1,     -- nível mínimo do personagem
        reqReset = 0,       -- resets mínimos (0 = sem requisito)

        -- Item obrigatório consumido ao confirmar entrada
        -- itemCode = 0 desativa a exigência
        itemCode = 0,
        itemQty  = 1,
        itemNome = "Jóia da Alma",

        -- --------------------------------------------------
        -- ONDAS (última = BOSS)
        -- monstros: { id=MonsterCode, qtd=quantidade }
        -- posX/posY: centro do spawn
        -- range: variação aleatória em torno do centro (+/- range)
        -- --------------------------------------------------
        ondas = {
            [1] = { monstros={{id=815, qtd=5},{id=816, qtd=3}}, 				 posX=128,posY=109,range=10 },
            [2] = { monstros={{id=815, qtd=8},{id=816, qtd=8}}, 				 posX=128,posY=109,range=10 },
            [3] = { monstros={{id=815,qtd=10},{id=816,qtd=10},{id=817, qtd=10}}, posX=128,posY=109,range=12 },
            [4] = { monstros={{id=875,qtd=1}},                                   posX=128,posY=109,range=0  }, -- BOSS
        },

        -- Recompensas ao derrotar o boss
        recompensa = {
            wcoin=50, zen=1000,
            drops={ {item=13,subitem=0},{item=14,subitem=0} },
        },
    },

    ---- ======================================================
    ---- DUNGEON 2
    ---- ======================================================
    --[2] = {
    --    nome     = "Caverna do Caos",
    --    bossNome = "Lich do Caos",
    --    bossTGA  = 53011,   -- dg2_boss.tga
	--
    --    mapa=35, spawnX=100, spawnY=100,
    --    retornoMapa=0, retornoX=125, retornoY=125,
    --    tempoLobby=120, maxPlayers=10,
	--
    --    dificuldades = { "normal", "hard", "extreme" },
	--
    --    reqLevel=280, reqReset=1,
    --    itemCode=14, itemQty=3, itemNome="Jóia do Caos",
	--
    --    ondas = {
    --        [1]={ monstros={{id=15,qtd=6},{id=16,qtd=2}}, posX=100,posY=100,range=10 },
    --        [2]={ monstros={{id=17,qtd=5},{id=18,qtd=3}}, posX=105,posY=95, range=10 },
    --        [3]={ monstros={{id=19,qtd=4},{id=20,qtd=4}}, posX=100,posY=100,range=12 },
    --        [4]={ monstros={{id=21,qtd=2},{id=22,qtd=2}}, posX=100,posY=100,range=10 },
    --        [5]={ monstros={{id=60,qtd=1}},               posX=100,posY=100,range=0  }, -- BOSS
    --    },

     --   recompensa={ wcoin=80,zen=2000000, drops={{item=15,subitem=0},{item=16,subitem=0}} },
   -- },

    -- ======================================================
    -- DUNGEON 3
    -- ======================================================
    --[3] = {
    --    nome     = "Abismo Eterno",
    --    bossNome = "Senhor do Abismo",
    --    bossTGA  = 53012,   -- dg3_boss.tga
	--
    --    mapa=36, spawnX=200, spawnY=200,
    --    retornoMapa=0, retornoX=125, retornoY=125,
    --    tempoLobby=120, maxPlayers=10,
	--
    --    dificuldades = { "normal", "hard", "extreme" },
	--
    --    reqLevel=380, reqReset=3,
    --    itemCode=15, itemQty=5, itemNome="Cristal Abisal",
	--
    --    ondas = {
    --        [1]={ monstros={{id=25,qtd=8},{id=26,qtd=4}}, posX=200,posY=200,range=12 },
    --        [2]={ monstros={{id=27,qtd=6},{id=28,qtd=4}}, posX=205,posY=195,range=12 },
    --        [3]={ monstros={{id=29,qtd=5},{id=30,qtd=5}}, posX=200,posY=200,range=14 },
    --        [4]={ monstros={{id=31,qtd=4},{id=32,qtd=4}}, posX=200,posY=200,range=12 },
    --        [5]={ monstros={{id=33,qtd=3},{id=34,qtd=3}}, posX=200,posY=200,range=12 },
    --        [6]={ monstros={{id=70,qtd=1}},               posX=200,posY=200,range=0  }, -- BOSS
    --    },
	--
    --    recompensa={ wcoin=120,zen=5000000, drops={{item=20,subitem=0},{item=21,subitem=0},{item=22,subitem=0}} },
    --},
}

return C