-- Data\Custom\Script\System\LoadImages.lua
BridgeFunctionAttach('MainLoader','LoadImages')

function LoadImages()
    -- Carrega a imagem bg500.ozt (janela grande - 500x500)
    LoadBitmap("Custom\\ScriptImages\\bg500.tga", 50005) 
    
    -- Carrega a nova imagem bg501.ozt (janela pequena - 300x350)
    LoadBitmap("Custom\\ScriptImages\\bg501.tga", 50000)
    
    -- Carrega as setas apenas se necessário
    LoadBitmap("Custom\\ScriptImages\\Next.tga", 50002)
    LoadBitmap("Custom\\ScriptImages\\Previous.tga", 50003)
    
    Console(2,"[LoadImages] Imagens carregadas - bg505(50005), bg501(50000)")
end