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

local ERROR_MSG_SCREEN = [[
"%s" is not a valid screen!

You will have to add a new one to your screen list or use one of the existing screens:

%s]]
local ERROR_MSG_NEW = 'Invalid screen "%s", screens should be tables with a "new" method'

-- ------------------------------------------------
-- Local Variables
-- ------------------------------------------------

local stack
local screens

local old_changes, old_args
do
    local weak = {__mode = 'v'}
    old_changes = setmetatable({}, weak)
    old_args    = setmetatable({}, weak)
end

local cache = {}
local returns = { n = 0 }

local changes = {}
local height = 0 --Stack height

local function null() end

local concat = { '{' }

-- ------------------------------------------------
-- Private Functions
-- ------------------------------------------------

---
-- Cleans a table and fills it with the passed arguments
--
local function refill( t, ... )
    local n = select( '#', ... )

    for i=1, math.max( t.n, n ) do
        t[i] = select( i, ... )
    end

    t.n = n
    return t
end

---
-- Close and remove all screens from the stack.
--
local function clear()
    for i = #stack, 1, -1 do
        if type( stack[i].close ) == "function" then
            stack[i]:close()
        end

        stack[i] = nil
    end
end

---
-- Close and pop the current active state and activate the one beneath it
--
local function pop()
    -- Close the currently active screen.
    local tmp = ScreenManager.peek()

    -- Close the previous screen.
    if type( tmp.close ) == "function" then
        tmp:close()
    end

    -- Remove the now inactive screen from the stack.
    stack[#stack] = nil

    -- Activate next screen on the stack.
    local top = ScreenManager.peek()
    if type( top.setActive ) == "function" then
        top:setActive( true )
    end
end

---
-- Deactivate the current state, push a new state and initialize it
--
local function push( screen, args )
    local current = ScreenManager.peek()
    if current and current.setActive then
        current:setActive( false )
    end

    -- Push the new screen onto the stack.
    local new = screens[screen].new()
    stack[#stack + 1] = new

    -- Create the new screen and initialise it.
    if type( new.init ) == "function" then
        new:init( unpack( args, 1, args.n ) )
    end
end

---
-- Check if the screen is valid or error if not
--
local function validateScreen( screen )
    if not screens[screen] then
        local n = 1

        for i, _ in pairs( screens ) do
            concat[n+1] = i
            concat[n+2] = ', '
            n = n + 2
        end
        concat[n] = '}'

        for i=n, #concat do
            concat[i] = nil
        end

        local str = table.concat( concat )
        error( ERROR_MSG_SCREEN:format( tostring( screen ), str ), 3 )
    elseif type( screens[screen].new ) ~= 'function' then
        error( ERROR_MSG_NEW:format( tostring( screen ) ), 3 )
    end
end

---
-- Delegates a callback to the stack, with the apropiate propagate function
-- callback is the callback name
-- args a table containing the event arguments
-- level is the level of the stack to delegate to (defaults to the top)
--
local function delegate( callback, args, level )
    level = level or #stack
    local state = stack[level]

    if not state or type( state[callback] ) ~= "function" then return end

    local function propagate()
        return delegate( callback, args, level - 1 )
    end

    return state[callback]( state, propagate, unpack( args, 1, args.n ) )
end

local function call( callback, ... )
    local args = refill( old_args[#old_args] or { n = 0 }, ... )
    old_args[#old_args] = nil

    refill( returns, delegate( callback, args ) )

    old_args[#old_args + 1] = args
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
    for i=1, #changes do
        if changes[i].action == 'pop' then
            pop()
        elseif changes[i].action == 'switch' then
            clear()
            push( changes[i].screen, changes[i].args )
        elseif changes[i].action == 'push' then
            push( changes[i].screen, changes[i].args )
        end

        old_changes[#old_changes + 1] = changes[i]
        changes[i] = nil
    end
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
    if type( nscreens ) ~= "table" then
        error( "The first argument of ScreenManager.init should be a table containing screens", 2 )
    end

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

    local change = old_changes[#old_changes] or {}
    old_changes[#old_changes] = nil

    change.action = 'switch'
    change.screen = screen
    change.args = refill( change.args or { n = 0 }, ... )

    changes[#changes + 1] = change
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

    local change = old_changes[#old_changes] or {}
    old_changes[#old_changes] = nil

    change.action = 'push'
    change.screen = screen
    change.args = refill( change.args or { n = 0 }, ... )

    changes[#changes + 1] = change
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

        local change = old_changes[#old_changes] or {}
        old_changes[#old_changes] = nil

        change.action = 'pop'

        changes[#changes + 1] = change
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
-- Reroutes the draw callback to all screens on the stack.
-- Screens that are higher on the stack will overlay screens that are below
-- them.
--
function ScreenManager.draw( ... )
    call( 'draw', ... )

    ScreenManager.performChanges()

    return unpack( returns, 1, returns.n )
end

local meta = {
    __index = function ( self, index )
        local v = rawget( self, index )

        if v then
            return v
        elseif cache[index] then
            return cache[index]
        else
            local f = function ( ... )
                call( index, ... )
                return unpack( returns, 1, returns.n )
            end

            cache[index] = f
            return f
        end
    end
}

---
-- Register to multiple LÖVE callbacks, defaults to all.
-- @param callbacks (table) Table with the names of the callbacks to register to.
--
function ScreenManager.registerCallbacks( callbacks )
    local registry = {}

    if type( callbacks ) ~= 'table' then
        callbacks = {'update', 'draw'}

        for name in pairs( love.handlers ) do --luacheck:ignore
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

return setmetatable(ScreenManager, meta)

--==================================================================================================
-- Created 02.06.14 - 17:30                                                                        =
--==================================================================================================
