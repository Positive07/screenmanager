--===============================================================================--
--                                                                               --
-- Copyright (c) 2014 - 2017 Robert Machmer                                      --
--                                                                               --
-- This software is provided 'as-is', without any express or implied             --
-- warranty. In no event will the authors be held liable for any damages         --
-- arising from the use of this software.                                        --
--                                                                               --
-- Permission is granted to anyone to use this software for any purpose,         --
-- including commercial applications, and to alter it and redistribute it        --
-- freely, subject to the following restrictions:                                --
--                                                                               --
--  1. The origin of this software must not be misrepresented; you must not      --
--      claim that you wrote the original software. If you use this software     --
--      in a product, an acknowledgment in the product documentation would be    --
--      appreciated but is not required.                                         --
--  2. Altered source versions must be plainly marked as such, and must not be   --
--      misrepresented as being the original software.                           --
--  3. This notice may not be removed or altered from any source distribution.   --
--                                                                               --
--===============================================================================--

---
-- The ScreenManager library is a state manager at heart which allows some nifty
-- things, like stacking multiple screens on top of each other.
-- @module ScreenManager
--
local ScreenManager = {
    _VERSION     = '2.0.1',
    _DESCRIPTION = 'Screen/State Management for the LÖVE framework',
    _URL         = 'https://github.com/rm-code/screenmanager/',
}

-- ------------------------------------------------
-- Constants
-- ------------------------------------------------

local ERROR_MSG = [[
"%s" is not a valid screen!

You will have to add a new one to your screen list or use one of the existing screens:

%s]]

-- ------------------------------------------------
-- Local Variables
-- ------------------------------------------------

local stack
local screens

local changes = {}
local height = 0 --Stack height

-- ------------------------------------------------
-- Private Functions
-- ------------------------------------------------

---
-- Close and remove all screens from the stack.
--
local function clear()
    for i = #stack, 1, -1 do
        stack[i]:close()
        stack[i] = nil
    end
end

---
-- Close and pop the current active state and activate the one beneath it
--
local function pop()
    -- Close the currently active screen.
    local tmp = ScreenManager.peek()

    -- Remove the now inactive screen from the stack.
    stack[#stack] = nil

    -- Close the previous screen.
    tmp:close()

    -- Activate next screen on the stack.
    ScreenManager.peek():setActive( true )
end

---
-- Deactivate the current state, push a new state and initialize it
--
local function push( screen, args )
    if ScreenManager.peek() then
        ScreenManager.peek():setActive( false )
    end

    -- Push the new screen onto the stack.
    stack[#stack + 1] = screens[screen].new()

    -- Create the new screen and initialise it.
    stack[#stack]:init( unpack( args ) )
end

---
-- Check if the screen is valid or error if not
--
local function validateScreen( screen )
    if not screens[screen] then
        local str = "{"

        for i, _ in pairs( screens ) do
            str = str .. i .. ', '
        end

        str = str:sub( 1, -3 ) .. "}"

        error( string.format( ERROR_MSG, tostring( screen ), str ), 3 )
    end
end

---
-- Delegates a callback to the stack, with the apropiate propagate function
-- callback is the callback name
-- a, b, c, d, e, f are the event arguments
-- level is the level of the stack to delegate to (defaults to the top)
--
local function delegate( callback, a, b, c, d, e, f, level )
    level = level or #stack
    local state = stack[level]

    if not state or type( state[callback] ) ~= "function" then return end

    local function propagate()
        return delegate( callback, a, b, c, d, e, f, level - 1 )
    end

    return state[callback]( state, propagate, a, b, c, d, e, f )
end

-- ------------------------------------------------
-- Public Functions
-- ------------------------------------------------

---
-- This function is used internally by the ScreenManager library.
-- It performs all changes that have been added to the changes queue (FIFO) and
-- resets the queue afterwards.
-- @see push, pop, switch
--
function ScreenManager.performChanges()
    if #changes == 0 then
        return
    end

    for _, change in ipairs( changes ) do
        if change.action == 'pop' then
            pop()
        elseif change.action == 'switch' then
            clear()
            push( change.screen, change.args )
        elseif change.action == 'push' then
            push( change.screen, change.args )
        end
    end

    changes = {}
end

---
-- Initialises the ScreenManager library.
-- It sets up the stack table, the list of screens to use and then proceeds with
-- validating and switching to the initial screen.
-- @tparam table nscreens
--                 A table containing pointers to the different screen classes.
--                 The keys will are used to call a specific screen.
-- @tparam string screen
--                 The key of the first screen to push to the stack. Use the
--                 key under which the screen in question is stored in the
--                 nscreens table.
-- @tparam[opt] vararg ...
--                 Aditional arguments which will be passed to the new
--                 screen's init function.
--
function ScreenManager.init( nscreens, screen, ... )
    stack = {}
    screens = nscreens

    validateScreen( screen )

    ScreenManager.switch( screen, ... )
    ScreenManager.performChanges()
end

---
-- Switches to a screen.
-- Removes all screens from the stack, creates a new screen and switches to it.
-- Use this if you don't want to stack onto other screens.
-- @tparam string screen
--                 The key of the screen to switch to.
-- @tparam[opt] vararg ...
--                 One or multiple arguments passed to the new screen's init
--                 function.
--
function ScreenManager.switch( screen, ... )
    validateScreen( screen )
    height = 1
    changes[#changes + 1] = { action = 'switch', screen = screen, args = { ... } }
end

---
-- Pushes a new screen to the stack.
-- Creates a new screen and pushes it onto the stack, where it will overlay the
-- other screens below it. Screens below this new screen will be set inactive.
-- @tparam string screen
--                 The key of the screen to push to the stack.
-- @tparam[opt] vararg ...
--                 One or multiple arguments passed to the new screen's init
--                 function.
--
function ScreenManager.push( screen, ... )
    validateScreen( screen )
    height = height + 1
    changes[#changes + 1] = { action = 'push', screen = screen, args = { ... } }
end

---
-- Returns the screen on top of the screen stack without removing it.
-- @treturn table
--                 The screen on top of the stack.
--
function ScreenManager.peek()
    return stack[#stack]
end

---
-- Removes the topmost screen of the stack.
-- @raise Throws an error if the screen to pop is the last one on the stack.
--
function ScreenManager.pop()
    if height > 1 then
        height = height - 1
        changes[#changes + 1] = { action = 'pop' }
    else
        error("Can't close the last screen. Use switch() to clear the screen manager and add a new screen.", 2)
    end
end

---
-- Publishes a message to all screens which have a public receive function.
-- @tparam string event A string by which the message can be identified.
-- @tparam varargs ...  Multiple parameters to push to the receiver.
--
function ScreenManager.publish( event, ... )
    for i = 1, #stack do
        if stack[i].receive then
            stack[i]:receive( event, ... )
        end
    end
end

-- ------------------------------------------------
-- LOVE Callbacks
-- ------------------------------------------------

---
-- Reroutes the directorydropped callback to the currently active screen.
-- @param path (string) The full platform-dependent path to the directory.
--                       It can be used as an argument to love.filesystem.mount,
--                       in order to gain read access to the directory with
--                       love.filesystem.
--
function ScreenManager.directorydropped( path )
    return delegate( "directorydropped", path )
end

---
-- Reroutes the draw callback to all screens on the stack.
-- Screens that are higher on the stack will overlay screens that are below
-- them.
--
function ScreenManager.draw()
    local values = { delegate( "draw" ) }

    ScreenManager.performChanges()

    return unpack(values)
end

---
-- Reroutes the filedropped callback to the currently active screen.
-- @param file (File) The unopened File object representing the file that was
--                     dropped.
--
function ScreenManager.filedropped( file )
    return delegate( "filedropped", file )
end

---
-- Reroutes the focus callback to all screens on the stack.
-- @param focus (boolean) True if the window gains focus, false if it loses focus.
--
function ScreenManager.focus( focus )
    return delegate( "focus", focus )
end

---
-- Reroutes the keypressed callback to the currently active screen.
-- @param key      (KeyConstant) Character of the pressed key.
-- @param scancode (Scancode)    The scancode representing the pressed key.
-- @param isrepeat (boolean)     Whether this keypress event is a repeat. The
--                                delay between key repeats depends on the
--                                user's system settings.
--
function ScreenManager.keypressed( key, scancode, isrepeat )
    return delegate( "keypressed", key, scancode, isrepeat )
end

---
-- Reroutes the keyreleased callback to the currently active screen.
-- @param key      (KeyConstant) Character of the released key.
-- @param scancode (Scancode)    The scancode representing the released key.
--
function ScreenManager.keyreleased( key, scancode )
    return delegate( "keyreleased", key, scancode )
end

---
-- Reroutes the lowmemory callback to the currently active screen.
-- mobile devices.
--
function ScreenManager.lowmemory()
    return delegate( "lowmemory" )
end

---
-- Reroutes the mousefocus callback to the currently active screen.
-- @param focus (boolean) Wether the window has mouse focus or not.
--
function ScreenManager.mousefocus( focus )
    return delegate( "mousefocus", focus )
end

---
-- Reroutes the mousemoved callback to the currently active screen.
-- @param x  (number) Mouse x position.
-- @param y  (number) Mouse y position.
-- @param dx (number) The amount moved along the x-axis since the last time
--                     love.mousemoved was called.
-- @param dy (number) The amount moved along the y-axis since the last time
--                     love.mousemoved was called.
--
function ScreenManager.mousemoved( x, y, dx, dy )
    return delegate( "mousemoved", x, y, dx, dy )
end

---
-- Reroutes the mousepressed callback to the currently active screen.
-- @param x       (number)  Mouse x position, in pixels.
-- @param y       (number)  Mouse y position, in pixels.
-- @param button  (number)  The button index that was pressed. 1 is the primary
--                           mouse button, 2 is the secondary mouse button and 3
--                           is the middle button. Further buttons are mouse
--                           dependent.
-- @param istouch (boolean) True if the mouse button press originated from a
--                           touchscreen touch-press.
--
function ScreenManager.mousepressed( x, y, button, istouch )
    return delegate( "mousepressed", x, y, button, istouch )
end

---
-- Reroutes the mousereleased callback to the currently active screen.
-- @param x       (number)  Mouse x position, in pixels.
-- @param y       (number)  Mouse y position, in pixels.
-- @param button  (number)  The button index that was released. 1 is the primary
--                           mouse button, 2 is the secondary mouse button and 3
--                           is the middle button. Further buttons are mouse
--                           dependent.
-- @param istouch (boolean) True if the mouse button release originated from a
--                           touchscreen touch-release.
--
function ScreenManager.mousereleased( x, y, button, istouch )
    return delegate( "mousereleased", x, y, button, istouch )
end

---
-- Reroutes the quit callback to the currently active screen.
-- @return quit (boolean) Abort quitting. If true, do not close the game.
--
function ScreenManager.quit()
    return delegate( "quit" )
end

---
-- Reroutes the resize callback to all screens on the stack.
-- @param w (number) The new width, in pixels.
-- @param h (number) The new height, in pixels.
--
function ScreenManager.resize( w, h )
    return delegate( "resize", w, h )
end

---
-- Reroutes the textedited callback to the currently active screen.
-- @param text   (string) The UTF-8 encoded unicode candidate text.
-- @param start  (number) The start cursor of the selected candidate text.
-- @param length (number) The length of the selected candidate text. May be 0.
--
function ScreenManager.textedited( text, start, length )
    return delegate( "textedited", text, start, length )
end

---
-- Reroutes the textinput callback to the currently active screen.
-- @param input (string) The UTF-8 encoded unicode text.
--
function ScreenManager.textinput( input )
    return delegate( "textinput", input )
end

---
-- Reroutes the threaderror callback to all screens.
-- @param thread   (Thread) The thread which produced the error.
-- @param errorstr (string) The error message.
--
function ScreenManager.threaderror( thread, errorstr )
    return delegate( "threaderror", thread, errorstr )
end


---
-- Reroutes the touchmoved callback to the currently active screen.
-- @param id       (light userdata) The identifier for the touch press.
-- @param x        (number)         The x-axis position of the touch press inside the
--                                   window, in pixels.
-- @param y        (number)         The y-axis position of the touch press inside the
--                                   window, in pixels.
-- @param dx       (number)         The x-axis movement of the touch inside the
--                                   window, in pixels.
-- @param dy       (number)         The y-axis movement of the touch inside the
--                                   window, in pixels.
-- @param pressure (number)         The amount of pressure being applied. Most
--                                   touch screens aren't pressure sensitive,
--                                   in which case the pressure will be 1.
--
function ScreenManager.touchmoved( id, x, y, dx, dy, pressure )
    return delegate( "touchmoved", id, x, y, dx, dy, pressure )
end

---
-- Reroutes the touchpressed callback to the currently active screen.
-- @param id       (light userdata) The identifier for the touch press.
-- @param x        (number)         The x-axis position of the touch press inside the
--                                   window, in pixels.
-- @param y        (number)         The y-axis position of the touch press inside the
--                                   window, in pixels.
-- @param dx       (number)         The x-axis movement of the touch inside the
--                                   window, in pixels.
-- @param dy       (number)         The y-axis movement of the touch inside the
--                                   window, in pixels.
-- @param pressure (number)         The amount of pressure being applied. Most
--                                   touch screens aren't pressure sensitive,
--                                   in which case the pressure will be 1.
--
function ScreenManager.touchpressed( id, x, y, dx, dy, pressure )
    return delegate( "touchpressed", id, x, y, dx, dy, pressure )
end

---
-- Reroutes the touchreleased callback to the currently active screen.
-- @param id       (light userdata) The identifier for the touch press.
-- @param x        (number)         The x-axis position of the touch press inside the
--                                   window, in pixels.
-- @param y        (number)         The y-axis position of the touch press inside the
--                                   window, in pixels.
-- @param dx       (number)         The x-axis movement of the touch inside the
--                                   window, in pixels.
-- @param dy       (number)         The y-axis movement of the touch inside the
--                                   window, in pixels.
-- @param pressure (number)         The amount of pressure being applied. Most
--                                   touch screens aren't pressure sensitive,
--                                   in which case the pressure will be 1.
--
function ScreenManager.touchreleased( id, x, y, dx, dy, pressure )
    return delegate( "touchreleased", id, x, y, dx, dy, pressure )
end

---
-- Reroutes the update callback to all screens.
-- @param dt (number) Time since the last update in seconds.
--
function ScreenManager.update( dt )
    return delegate( "update", dt )
end

---
-- Reroutes the visible callback to all screens.
-- @param visible (boolean) True if the window is visible, false if it isn't.
--
function ScreenManager.visible( visible )
    return delegate( "visible", visible )
end

---
-- Reroutes the wheelmoved callback to the currently active screen.
-- @param x (number) Amount of horizontal mouse wheel movement. Positive values
--                    indicate movement to the right.
-- @param y (number) Amount of vertical mouse wheel movement. Positive values
--                    indicate upward movement.
--
function ScreenManager.wheelmoved( x, y )
    return delegate( "wheelmoved", x, y )
end

---
-- Reroutes the gamepadaxis callback to the currently active screen.
-- @param joystick (Joystick)    The joystick object.
-- @param axis     (GamepadAxis) The joystick object.
-- @param value    (number)      The new axis value.
--
function ScreenManager.gamepadaxis( joystick, axis, value )
    return delegate( "gamepadaxis", joystick, axis, value )
end

---
-- Reroutes the gamepadpressed callback to the currently active screen.
-- @param joystick (Joystick)      The joystick object.
-- @param button   (GamepadButton) The virtual gamepad button.
--
function ScreenManager.gamepadpressed( joystick, button )
    return delegate( "gamepadpressed", joystick, button )
end

---
-- Reroutes the gamepadreleased callback to the currently active screen.
-- @param joystick (Joystick)      The joystick object.
-- @param button   (GamepadButton) The virtual gamepad button.
--
function ScreenManager.gamepadreleased( joystick, button )
    return delegate( "gamepadreleased", joystick, button )
end

---
-- Reroutes the joystickadded callback to the currently active screen.
-- @param joystick (Joystick) The newly connected Joystick object.
--
function ScreenManager.joystickadded( joystick )
    return delegate( "joystickadded", joystick )
end

---
-- Reroutes the joystickhat callback to the currently active screen.
-- @param joystick  (Joystick)    The newly connected Joystick object.
-- @param hat       (number)      The hat number.
-- @param direction (JoystickHat) The new hat direction.
--
function ScreenManager.joystickhat( joystick, hat, direction )
    return delegate( "joystickhat", joystick, hat, direction )
end

---
-- Reroutes the joystickpressed callback to the currently active screen.
-- @param joystick (Joystick) The newly connected Joystick object.
-- @param button   (number)   The button number.
--
function ScreenManager.joystickpressed( joystick, button )
    return delegate( "joystickpressed", joystick, button )
end

---
-- Reroutes the joystickreleased callback to the currently active screen.
-- @param joystick (Joystick) The newly connected Joystick object.
-- @param button   (number)   The button number.
--
function ScreenManager.joystickreleased( joystick, button )
    return delegate( "joystickreleased", joystick, button )
end

---
-- Reroutes the joystickremoved callback to the currently active screen.
-- @param joystick (Joystick) The now-disconnected Joystick object.
--
function ScreenManager.joystickremoved( joystick )
    return delegate( "joystickremoved", joystick )
end

---
-- Register to multiple LÖVE callbacks, defaults to all.
-- @param callbacks (table) Table with the names of the callbacks to register to.
--
function ScreenManager.registerCallbacks( callbacks )
    local registry = {}
    local function null() end

    if type( callbacks ) ~= 'table' then
        callbacks = { 'update', 'draw' }

        for name in pairs( love.handlers ) do
            callbacks[#callbacks + 1] = name
        end
    end

    for _, f in ipairs( callbacks ) do
        registry[f] = love[f] or null

        love[f] = function( ... )
            registry[f]( ... )
            return ScreenManager[f]( ... )
        end
    end
end

-- ------------------------------------------------
-- Return Module
-- ------------------------------------------------

return ScreenManager

--==================================================================================================
-- Created 02.06.14 - 17:30                                                                        =
--==================================================================================================
