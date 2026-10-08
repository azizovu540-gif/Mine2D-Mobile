-- Мобильное управление (Сенсорный экран):
-- Джойстик слева — Ходьба влево/вправо
-- Кнопка со стрелкой вверх справа — Прыжок
-- Кнопка [ЛОМ] — Режим разрушения блоков
-- Кнопка [СТРОЙ] — Режим установки блоков
-- Кнопка [||] сверху — Пауза
-- Тап по экрану — Взаимодействие с миром (сломать/поставить)

local world = {}
local WORLD_WIDTH = 70
local WORLD_HEIGHT = 40
local TILE_SIZE = 32

local gameState = "menu"

local BLOCKS = {
    [1] = { name = "Трава", color = { 0.2, 0.7, 0.2 } },
    [2] = { name = "Земля", color = { 0.5, 0.3, 0.1 } },
    [3] = { name = "Камень", color = { 0.5, 0.5, 0.5 } },
    [4] = { name = "Древесина", color = { 0.6, 0.4, 0.2 } },
    [5] = { name = "Листва", color = { 0.1, 0.5, 0.1 } }
}

local selectedBlock = 1
local camX, camY = 0, 0
local menuTimer = 0

-- Режим касания: "break" (ломать) или "build" (строить)
local touchMode = "break"

local tilesetImage = nil
local tilesetQuads = {}
local bgMusic = nil

local player = {
    x = 0, y = 0, width = 20, height = 54,
    vx = 0, vy = 0, speed = 180, gravity = 950, jumpForce = -390,
    grounded = false, animTimer = 0, direction = 1
}

-- Координаты сенсорных элементов управления
local screenW, screenH = 800, 600
local controls = {
    joyX = 120, joyY = 500, joyR = 50,      
    btnJump = { x = 700, y = 480, r = 35 },  
    btnBreak = { x = 600, y = 510, r = 25 }, 
    btnBuild = { x = 600, y = 450, r = 25 }, 
    btnPause = { x = 750, y = 20, w = 35, h = 35 } 
}

local buttons = {
    menu = {
        play = { x = 300, y = 260, w = 200, h = 45, text = "Играть", hovered = false },
        exit = { x = 300, y = 325, w = 200, h = 45, text = "Выход", hovered = false }
    },
    paused = {
        resume = { x = 300, y = 240, w = 200, h = 45, text = "Продолжить", hovered = false },
        toMenu = { x = 300, y = 305, w = 200, h = 45, text = "В главное меню", hovered = false }
    }
}

local function playDigSound()
    local samplingRate = 44100
    local duration = 0.08
    local numSamples = math.floor(samplingRate * duration)
    local soundData = love.sound.newSoundData(numSamples, samplingRate, 16, 1)
    for i = 0, numSamples - 1 do
        local t = i / samplingRate
        local frequency = 800 + (1 - (t / duration)) * 400
        local sample = math.sin(t * frequency * math.pi * 2) * (1 - (t / duration))
        soundData:setSample(i, sample)
    end
    local audioSource = love.audio.newSource(soundData)
    audioSource:setVolume(0.4)
    audioSource:play()
end

local function checkCollision(x, y, w, h, bx, by, bw, bh)
    return x < bx + bw and x + w > bx and y < by + bh and y + h > by
end

local function isSolid(gx, gy)
    if gx < 1 or gx > WORLD_WIDTH or gy < 1 or gy > WORLD_HEIGHT then return true end
    return world[gx][gy] and world[gx][gy] > 0
end

local function checkMouseOverButton(bx, by, bw, bh)
    local mx, my = love.mouse.getPosition()
    return mx > bx and mx < bx + bw and my > by and my < by + bh
end

-- Функция отрисовки стилизованных кнопок для мобильного меню (Исправлено!)
local function drawButton(btn)
    if btn.hovered then
        love.graphics.setColor(0.4, 0.4, 0.4, 0.9) 
    else
        love.graphics.setColor(0.3, 0.3, 0.3, 0.8) 
    end
    love.graphics.rectangle("fill", btn.x, btn.y, btn.w, btn.h, 4, 4)
    love.graphics.setColor(1, 1, 1)
    local textWidth = love.graphics.getFont():getWidth(btn.text)
    love.graphics.print(btn.text, btn.x + (btn.w - textWidth) / 2, btn.y + 12)
end

function love.load()
    love.window.setTitle("LÖVE 2D MineClone Mobile")
    screenW, screenH = love.graphics.getDimensions()
    
    local fontFile = "arial.ttf"
    if not love.filesystem.getInfo(fontFile) then fontFile = "Arial.ttf" end
    if love.filesystem.getInfo(fontFile) then
        love.graphics.setFont(love.graphics.newFont(fontFile, 16))
    end
    
    if love.filesystem.getInfo("tileset.png") then
        tilesetImage = love.graphics.newImage("tileset.png")
        tilesetImage:setFilter("nearest", "nearest")
        for i = 1, 5 do
            tilesetQuads[i] = love.graphics.newQuad((i - 1) * 16, 0, 16, 16, tilesetImage:getDimensions())
        end
    end

    if love.filesystem.getInfo("music.mp3") then
        bgMusic = love.audio.newSource("music.mp3", "stream")
        bgMusic:setLooping(true)
        bgMusic:setVolume(0.4)
        bgMusic:play()
    end
    
    math.randomseed(os.time())
    
    -- Генерация мира
    for x = 1, WORLD_WIDTH do
        world[x] = {}
        local surfaceHeight = 20 + math.floor(math.sin(x * 0.15) * 4)
        for y = 1, WORLD_HEIGHT do
            if y > surfaceHeight then
                if y == surfaceHeight + 1 then world[x][y] = 1
                elseif y <= surfaceHeight + 5 then world[x][y] = 2
                else world[x][y] = 3 end
            else
                world[x][y] = 0
            end
        end
    end
    
    -- Деревья
    for x = 5, WORLD_WIDTH - 5 do
        local surfaceY = 0
        for y = 1, WORLD_HEIGHT do if world[x][y] == 1 then surfaceY = y break end end
        if surfaceY > 5 and math.random(1, 8) == 1 and world[x-1][surfaceY] == 1 and world[x+1][surfaceY] == 1 then
            local trunkHeight = math.random(3, 5)
            for t = 1, trunkHeight do world[x][surfaceY - t] = 4 end
            local leavesY = surfaceY - trunkHeight
            for lx = x - 2, x + 2 do
                for ly = leavesY - 2, leavesY do
                    if world[lx] and world[lx][ly] == 0 then world[lx][ly] = 5 end
                end
            end
        end
    end
    
    player.x = (WORLD_WIDTH / 2) * TILE_SIZE
    player.y = 5 * TILE_SIZE
end

function love.update(dt)
    screenW, screenH = love.graphics.getDimensions()
    
    controls.joyX, controls.joyY = 120, screenH - 120
    controls.btnJump.x, controls.btnJump.y = screenW - 100, screenH - 140
    controls.btnBreak.x, controls.btnBreak.y = screenW - 220, screenH - 100
    controls.btnBuild.x, controls.btnBuild.y = screenW - 220, screenH - 180
    controls.btnPause.x = screenW - 60

    if gameState == "menu" then
        menuTimer = menuTimer + dt * 3
        for _, btn in pairs(buttons.menu) do btn.hovered = checkMouseOverButton(btn.x, btn.y, btn.w, btn.h) end
        if bgMusic then bgMusic:setVolume(0.4) end
        return
    elseif gameState == "paused" then
        for _, btn in pairs(buttons.paused) do btn.hovered = checkMouseOverButton(btn.x, btn.y, btn.w, btn.h) end
        if bgMusic then bgMusic:setVolume(0.15) end
        return
    end

    -- Поддержка смены блоков с клавиатуры для тестов на ПК
    if love.keyboard.isDown("1") then selectedBlock = 1 end
    if love.keyboard.isDown("2") then selectedBlock = 2 end
    if love.keyboard.isDown("3") then selectedBlock = 3 end
    if love.keyboard.isDown("4") then selectedBlock = 4 end
    if love.keyboard.isDown("5") then selectedBlock = 5 end

    player.vx = 0
    local isMoving = false
    local jumpPressed = false
    
    -- Опрашиваем мультитач
    local touches = love.touch.getTouches()
    local touchList = {}
    for _, id in ipairs(touches) do
        local tx, ty = love.touch.getPosition(id)
        table.insert(touchList, { x = tx, y = ty })
    end
    
    -- ПК-управление дублирует джойстики при зажатой ЛКМ
    if love.mouse.isDown(1) then
        table.insert(touchList, { x = love.mouse.getX(), y = love.mouse.getY() })
    end

    -- Также оставим обычные стрелочки/A-D для тестов на ПК
    if love.keyboard.isDown("a") or love.keyboard.isDown("left") then
        player.vx = -player.speed
        player.direction = -1
        isMoving = true
    end
    if love.keyboard.isDown("d") or love.keyboard.isDown("right") then
        player.vx = player.speed
        player.direction = 1
        isMoving = true
    end
    if love.keyboard.isDown("space") or love.keyboard.isDown("w") or love.keyboard.isDown("up") then
        jumpPressed = true
    end

    -- Обрабатываем координаты джойстиков на экране
    for _, t in ipairs(touchList) do
        local distToJoy = math.sqrt((t.x - controls.joyX)^2 + (t.y - controls.joyY)^2)
        if distToJoy < controls.joyR + 40 then
            if t.x < controls.joyX - 15 then
                player.vx = -player.speed
                player.direction = -1
                isMoving = true
            elseif t.x > controls.joyX + 15 then
                player.vx = player.speed
                player.direction = 1
                isMoving = true
            end
        end
        
        local distToJump = math.sqrt((t.x - controls.btnJump.x)^2 + (t.y - controls.btnJump.y)^2)
        if distToJump < controls.btnJump.r then
            jumpPressed = true
        end
    end

    if isMoving and player.grounded then
        player.animTimer = player.animTimer + dt * 12
    else
        player.animTimer = player.animTimer + (0 - player.animTimer) * 10 * dt
    end

    player.vy = player.vy + player.gravity * dt
    if jumpPressed and player.grounded then
        player.vy = player.jumpForce
        player.grounded = false
    end

    -- Физика
    player.x = player.x + player.vx * dt
    local startX = math.max(1, math.floor(player.x / TILE_SIZE))
    local endX = math.min(WORLD_WIDTH, math.floor((player.x + player.width) / TILE_SIZE) + 1)
    local startY = math.max(1, math.floor(player.y / TILE_SIZE))
    local endY = math.min(WORLD_HEIGHT, math.floor((player.y + player.height) / TILE_SIZE) + 1)

    for x = startX, endX do
        for y = startY, endY do
            if isSolid(x, y) then
                if checkCollision(player.x, player.y, player.width, player.height, (x-1)*TILE_SIZE, (y-1)*TILE_SIZE, TILE_SIZE, TILE_SIZE) then
                    if player.vx > 0 then player.x = (x - 1) * TILE_SIZE - player.width
                    elseif player.vx < 0 then player.x = x * TILE_SIZE end
                end
            end
        end
    end

    player.y = player.y + player.vy * dt
    startX = math.max(1, math.floor(player.x / TILE_SIZE))
endX = math.min(WORLD_WIDTH, math.floor((player.x + player.width) / TILE_SIZE) + 1)
startY = math.max(1, math.floor(player.y / TILE_SIZE))
endY = math.min(WORLD_HEIGHT, math.floor((player.y + player.height) / TILE_SIZE) + 1)
player.grounded = false
for x = startX, endX do
for y = startY, endY do
if isSolid(x, y) then
if checkCollision(player.x, player.y, player.width, player.height, (x-1)*TILE_SIZE, (y-1)*TILE_SIZE, TILE_SIZE, TILE_SIZE) then
if player.vy > 0 then
player.y = (y - 1) * TILE_SIZE - player.height
player.vy = 0
player.grounded = true
elseif player.vy < 0 then
player.y = y * TILE_SIZE
player.vy = 0
end
end
end
end
end
camX = player.x - screenW / 2 + player.width / 2
camY = player.y - screenH / 2 + player.height / 2
end
function love.keypressed(key)
if key == "escape" then
if gameState == "playing" then gameState = "paused"
elseif gameState == "paused" then gameState = "playing" end
end
end
function love.mousereleased(mx, my, button)
if gameState == "menu" then
if mx > buttons.menu.play.x and mx < buttons.menu.play.x + buttons.menu.play.w and my > buttons.menu.play.y and my < buttons.menu.play.y + buttons.menu.play.h then
gameState = "playing"
elseif mx > buttons.menu.exit.x and mx < buttons.menu.exit.x + buttons.menu.exit.w and my > buttons.menu.exit.y and my < buttons.menu.exit.y + buttons.menu.exit.h then
love.event.quit()
end
return
elseif gameState == "paused" then
if mx > buttons.paused.resume.x and mx < buttons.paused.resume.x + buttons.paused.resume.w and my > buttons.paused.resume.y and my < buttons.paused.resume.y + buttons.paused.resume.h then
gameState = "playing"
elseif mx > buttons.paused.toMenu.x and mx < buttons.paused.toMenu.x + buttons.paused.toMenu.w and my > buttons.paused.toMenu.y and my < buttons.paused.toMenu.y + buttons.paused.toMenu.h then
gameState = "menu"
end
return
end
if mx > controls.btnPause.x and mx < controls.btnPause.x + controls.btnPause.w and my > controls.btnPause.y and my < controls.btnPause.y + controls.btnPause.h then
gameState = "paused"
return
end
local distToBreak = math.sqrt((mx - controls.btnBreak.x)^2 + (my - controls.btnBreak.y)^2)
if distToBreak < controls.btnBreak.r then touchMode = "break" return end
local distToBuild = math.sqrt((mx - controls.btnBuild.x)^2 + (my - controls.btnBuild.y)^2)
if distToBuild < controls.btnBuild.r then touchMode = "build" return end
local hbWidth = 300
local hbX = (screenW - hbWidth) / 2
local hbY = screenH - 65
if mx > hbX and mx < hbX + hbWidth and my > hbY and my < hbY + 50 then
local slot = math.floor((mx - hbX - 15) / 55) + 1
if slot >= 1 and slot <= 5 then selectedBlock = slot end
return
end
if mx < 250 and my > screenH - 220 then return end
if mx > screenW - 180 and my > screenH - 220 then return end
local gridX = math.floor((mx + camX) / TILE_SIZE) + 1
local gridY = math.floor((my + camY) / TILE_SIZE) + 1
if gridX >= 1 and gridX <= WORLD_WIDTH and gridY >= 1 and gridY <= WORLD_HEIGHT then
if touchMode == "break" then
if world[gridX][gridY] > 0 then
world[gridX][gridY] = 0
playDigSound()
end
elseif touchMode == "build" then
if world[gridX][gridY] == 0 then
local bx, by = (gridX - 1) * TILE_SIZE, (gridY - 1) * TILE_SIZE
if not checkCollision(player.x, player.y, player.width, player.height, bx, by, TILE_SIZE, TILE_SIZE) then
world[gridX][gridY] = selectedBlock
end
end
end
end
end
function love.draw()
love.graphics.clear(0.5, 0.8, 1)
love.graphics.push()
love.graphics.translate(-math.floor(camX), -math.floor(camY))
for x = 1, WORLD_WIDTH do
for y = 1, WORLD_HEIGHT do
local blockId = world[x][y]
if blockId and blockId > 0 then
local bx, by = (x - 1) * TILE_SIZE, (y - 1) * TILE_SIZE
if tilesetImage and tilesetQuads[blockId] then
love.graphics.setColor(1, 1, 1)
love.graphics.draw(tilesetImage, tilesetQuads[blockId], bx, by, 0, TILE_SIZE / 16, TILE_SIZE / 16)
else
love.graphics.setColor(BLOCKS[blockId].color)
love.graphics.rectangle("fill", bx, by, TILE_SIZE, TILE_SIZE)
end
end
end
end
-- Стив
love.graphics.push()
love.graphics.translate(player.x + player.width / 2, player.y)
local swing = math.cos(player.animTimer) * 12
local colSkin, colHair, colShirt, colPants, colShoes = {0.87, 0.67, 0.53}, {0.45, 0.24, 0.14}, {0.0, 0.64, 0.67}, {0.24, 0.27, 0.68}, {0.3, 0.3, 0.3}
love.graphics.setColor(colShirt)
love.graphics.rectangle("fill", -5 - (swing * 0.3 * player.direction), 14 + (swing * 0.1), 10, 10)
love.graphics.setColor(colSkin)
love.graphics.rectangle("fill", -5 - (swing * 0.5 * player.direction), 24 + (swing * 0.2), 10, 8)
love.graphics.setColor(colPants)
love.graphics.rectangle("fill", -9 + (swing * 0.4), 34, 9, 14)
love.graphics.setColor(colShoes)
love.graphics.rectangle("fill", -9 + (swing * 0.4) + (player.direction * 1), 48, 9, 6)
love.graphics.setColor(colPants)
love.graphics.rectangle("fill", 0 - (swing * 0.4), 34, 9, 14)
love.graphics.setColor(colShoes)
love.graphics.rectangle("fill", 0 - (swing * 0.4) + (player.direction * 1), 48, 9, 6)
love.graphics.setColor(colShirt)
love.graphics.rectangle("fill", -10, 14, 20, 20)
love.graphics.setColor(colSkin)
love.graphics.rectangle("fill", -8, -2, 16, 16)
love.graphics.setColor(colHair)
love.graphics.rectangle("fill", -8, -2, 16, 5)
local faceOffset = 3 * player.direction
love.graphics.setColor(0.2, 0.4, 0.8)
love.graphics.rectangle("fill", faceOffset + (player.direction > 0 and 1 or -5), 3, 4, 3)
love.graphics.setColor(colHair)
love.graphics.rectangle("fill", faceOffset - 2, 7, 4, 3)
love.graphics.setColor(colShirt)
love.graphics.rectangle("fill", -5 + (swing * 0.3 * player.direction), 14 - (swing * 0.1), 10, 10)
love.graphics.setColor(colSkin)
love.graphics.rectangle("fill", -5 + (swing * 0.5 * player.direction), 24 - (swing * 0.2), 10, 8)
love.graphics.pop()
love.graphics.pop()
if gameState == "menu" then
love.graphics.setColor(0, 0, 0, 0.5)
love.graphics.rectangle("fill", 0, 0, screenW, screenH)
love.graphics.push()
love.graphics.translate(screenW / 2, 120 + math.sin(menuTimer) * 8)
love.graphics.scale(2.5, 2.5)
love.graphics.setColor(0, 0, 0, 0.6)
love.graphics.printf("MINECRAFT 2D", -150 + 2, 2, 300, "center")
love.graphics.setColor(0.3, 0.7, 0.3)
love.graphics.printf("MINECRAFT 2D", -150, 0, 300, "center")
love.graphics.pop()
buttons.menu.play.x = (screenW - 200) / 2
buttons.menu.exit.x = (screenW - 200) / 2
drawButton(buttons.menu.play)
drawButton(buttons.menu.exit)
elseif gameState == "paused" then
love.graphics.setColor(0, 0, 0, 0.6)
love.graphics.rectangle("fill", 0, 0, screenW, screenH)
love.graphics.setColor(1, 1, 1)
love.graphics.printf("ИГРА НА ПАУЗЕ", 0, 150, screenW, "center")
buttons.paused.resume.x = (screenW - 200) / 2
buttons.paused.toMenu.x = (screenW - 200) / 2
drawButton(buttons.paused.resume)
drawButton(buttons.paused.toMenu)
elseif gameState == "playing" then
-- Сенсорный интерфейс
love.graphics.setColor(1, 1, 1, 0.25)
love.graphics.circle("fill", controls.joyX, controls.joyY, controls.joyR)
love.graphics.setColor(1, 1, 1, 0.6)
love.graphics.circle("line", controls.joyX, controls.joyY, controls.joyR)
love.graphics.print("<  >", controls.joyX - 16, controls.joyY - 8)
love.graphics.setColor(1, 1, 1, 0.3)
love.graphics.circle("fill", controls.btnJump.x, controls.btnJump.y, controls.btnJump.r)
love.graphics.setColor(1, 1, 1, 0.7)
love.graphics.print("ВВЕРХ", controls.btnJump.x - 22, controls.btnJump.y - 8)
if touchMode == "break" then love.graphics.setColor(0.9, 0.3, 0.3, 0.6)
else love.graphics.setColor(1, 1, 1, 0.25) end
love.graphics.circle("fill", controls.btnBreak.x, controls.btnBreak.y, controls.btnBreak.r)
love.graphics.setColor(1, 1, 1, 0.7)
love.graphics.print("ЛОМ", controls.btnBreak.x - 15, controls.btnBreak.y - 8)
if touchMode == "build" then love.graphics.setColor(0.3, 0.8, 0.3, 0.6)
else love.graphics.setColor(1, 1, 1, 0.25) end
love.graphics.circle("fill", controls.btnBuild.x, controls.btnBuild.y, controls.btnBuild.r)
love.graphics.setColor(1, 1, 1, 0.7)
love.graphics.print("СТРОЙ", controls.btnBuild.x - 22, controls.btnBuild.y - 8)
love.graphics.setColor(0, 0, 0, 0.4)
love.graphics.rectangle("fill", controls.btnPause.x, controls.btnPause.y, controls.btnPause.w, controls.btnPause.h, 4, 4)
love.graphics.setColor(1, 1, 1)
love.graphics.print("||", controls.btnPause.x + 12, controls.btnPause.y + 8)
-- Хотбар
local hbWidth, hbHeight = 300, 50
local hbX, hbY = (screenW - hbWidth) / 2, screenH - hbHeight - 15
love.graphics.setColor(0, 0, 0, 0.6)
love.graphics.rectangle("fill", hbX, hbY, hbWidth, hbHeight, 8, 8)
for i = 1, 5 do
local slotX = hbX + 15 + (i - 1) * 55
local slotY = hbY + 9
if i == selectedBlock then
love.graphics.setColor(1, 1, 1, 0.4)
love.graphics.rectangle("fill", slotX - 4, slotY - 4, 40, 40, 4, 4)
end
if tilesetImage and tilesetQuads[i] then
love.graphics.setColor(1, 1, 1)
love.graphics.draw(tilesetImage, tilesetQuads[i], slotX, slotY, 0, 2, 2)
else
love.graphics.setColor(BLOCKS[i].color)
love.graphics.rectangle("fill", slotX, slotY, 32, 32)
end
end
end
end