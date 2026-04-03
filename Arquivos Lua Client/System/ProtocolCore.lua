ProtocolFunctions = {}

BridgeFunctionAttach('ClientProtocol','ClientProtocolRecv')

-- Packets que vem do gameserver
local ClientProtocol_Handles = {}

function ClientProtocolRecv(Packet, PacketName)
    for i = 1, #ClientProtocol_Handles do
        if ClientProtocol_Handles[i].callback(Packet, PacketName) then
            return
        end
    end
    ClearPacket(PacketName)
end

function ProtocolFunctions.ClientProtocol(callback)
    table.insert(ClientProtocol_Handles, { callback = callback })
end

function ProtocolFunctions.Init()
    ProtocolFunctions.ClientProtocol(ProtocolFunctions.ProtocolRecv)
end

-- ==========================================================
-- FUNÇÃO DE RECEBIMENTO DE PROTOCOLOS
-- ==========================================================
function ProtocolFunctions.ProtocolRecv(Packet, PacketName)
    -- Log para debug no console do cliente
    -- Console(3, string.format("[ProtocolCore] Name: %s Head: %d", PacketName, Packet))

    -- Sincronização da Janela de Quests (Packet 0x15 vindo do Server)
    if Packet == 0x15 then
        -- Atribui os valores às variáveis globais usadas pela QuestWindow.lua
        -- Usamos GetWordPacket para ler os valores de 2 bytes enviados pelo servidor
        QuestAtivaID   = GetWordPacket(PacketName, 1) 
        QuestProgresso = GetWordPacket(PacketName, 3) 
        QuestAlvo      = GetWordPacket(PacketName, 5) 

        -- Força a atualização visual se a janela estiver aberta
        if UICustomInterface == 160 then
            -- A interface renderiza novamente no próximo frame automaticamente
        end
        
        ClearPacket(PacketName)
        return true
    end

    -- Outros protocolos existentes
    if PacketName == "WindowTitle" then
        SetWindowTitle("GAS Gaming Station")
        ClearPacket(PacketName)
        return true
    end

    return false
end

ProtocolFunctions.Init()