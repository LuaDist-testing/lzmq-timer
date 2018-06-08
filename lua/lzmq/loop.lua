local zmq      = require "lzmq"
local zpoller  = require "lzmq.poller"
local ztimer   = require "lzmq.timer"

local ZMQ_POLL_MSEC = 1000
do local ver = zmq.version()
  if ver and ver[1] > 2 then
    ZMQ_POLL_MSEC = 1
  end
end

-------------------------------------------------------------------
local time_event = {} do

-- �������� �������.

function time_event:new(...)
  local t = setmetatable({},{__index = self})
  return t:init(...)
end

function time_event:init(fn)
  self.private_ = {
    timer = ztimer.monotonic();
    lock  = false;
    fn    = fn;
  }
  return self
end

function time_event:set_time(tm)
  if self.private_.timer:is_monotonic() then
    self.private_.timer = ztimer.absolute()
  end
  self.private_.timer:start(tm)
end

function time_event:set_interval(interval)
  if self.private_.timer:is_absolute() then
    self.private_.timer = ztimer.monotonic()
  end
  self.private_.once = false
  self.private_.timer:start(interval)
end

function time_event:set_interval_once(interval)
  self:set_interval(interval)
  self.private_.once = true
end

---
-- ���������� ���������� �� �� ������� ������������
function time_event:sleep_interval()
  return self.private_.timer:rest()
end

---
-- ������� ��������� � ������� ���������
function time_event:started()
  return self.private_.timer:started()
end

---
-- ��������� �������. 
function time_event:reset()
  self.private_.timer:stop()
end

---
-- "�������" ������� ������.
-- ���� ��� ����������� �������, �� ��� ���������������.
-- ���������� ������� started
function time_event:restart()
  local is_once = self.private_.once or self.private_.timer:is_absolute()
  if is_once then
    if self.private_.timer:started() then
      self.private_.timer:stop()
    end
    return false
  end
  self.private_.timer:start()
  return true
end

function time_event:fire(...)
  return self.private_.fn( self, ... )
end

function time_event:pfire(...)
  local ok, err = pcall( self.private_.fn, self, ... )
  if (not ok) and self.on_error then
    self:on_error(err)
  end
end

function time_event:lock()   self.private_.lock = true  end
function time_event:unlock() self.private_.lock = false end
function time_event:locked() return self.private_.lock  end

end
-------------------------------------------------------------------

-------------------------------------------------------------------
local event_list = {} do
event_list.__index = event_list 

function event_list:new(...)
  return setmetatable({}, self):init(...)
end

function event_list:init()
  self.private_ = {events = {}}
  return self
end

function event_list:destroy()
  self.private_.events = nil
end

function event_list:add(ev)
  table.insert(self.private_.events, ev)
  return true
end

function event_list:count()
  return #self.private_.events
end

---
-- ���������� ����� �� ���������� �������
function event_list:sleep_interval(min_interval)
  for i, ev in ipairs(self.private_.events) do
    if (not ev:locked()) and (ev:started()) then
      local int = ev:sleep_interval()
      if min_interval > int then min_interval = int end
    end
  end
  return min_interval
end

---
-- �������� ��������������� �������
function event_list:fire(...)
  local cnt = 0
  local i = 0
  while(true)do
    --[[ � �������� ��������� ���������� ������� events ����� ���������
    -- ** ��� ����� fire ���� ������ ����������. 
    -- ** ��� ��������� ������������ ������ ������� �� �� ��������� �� ����� ���������
    -- ** � �������� ��������� ������� ������ ������� ����� ���� ��������� ��� �������
    -- ** ������� ����� ���� �������� �� ���: ev = loop:add_XXX(...); ev:reset()
    -- ** ����� ������� ����� ������ �������. 
    -- ** 
    -- ** ��������� �������� ������� 
    -- **  �� ������� ������� (1) ������� #1 ���������� � ������� �������� (�������� ����������� �����)
    -- **  ������� #2 � �������� ��������� �������� sleep_ex, ��� �������� ����������� ����� fire.
    -- **  ���� ������ (2) ������������ ������� #1 ��� ��������� � �������� ��� �� �������� 
    -- **  ������� #2 ������������� � �� ����� ���� ���������.
    -- **  ������ (2) ��������� ��������� �������
    -- **  ������ (2) ������� ������� #1 � �����������
    -- **  ���� ������� ����� ���������� ��������� ��� ��� ��������� ����������
    -- **  ����������� ��������� ������� #2 �� ������� (1).
    -- **  ������ ������� ���������. ���� � ������ ���� 3 �������, �� ������� ������ ��������� �� ���. 
    -- **   ������������ - �������� ������ � ������ ����� ������ ev:fire() -
    -- **     ������� � ����� ������ ����� �� ����� �� ����������.
    -- **   ������������ - ����������� ������ ����� �������� - ������ �������� �����������, ��� ������� 
    -- **     ������� ��������� ������ �������.
    -- **  � ������ ����, ��� ��� ������������ ��� ����� ������ ��������� � �������� �� ������� ���������� 
    -- **    ���������� ���������� �������(������� ������ ���� ����� �� ������� #1 ��������) �� �������� �������
    -- **    ����� �������� � ���, ��� ��� ������� ����� �������� ����� �������� poll ��� �� ��������� ����������� ������
    -- **    �������� � ������ ��������� ������� #4
    -- ]]

    i = i + 1
    local ev = self.private_.events[i]
    if not ev then break end
    if not ev:locked() then
      if ev:started() then 
        local int = ev:sleep_interval()
        if int == 0 then 
          ev:lock()
          ev:fire(...) -- ����� ������� ��������
          ev:unlock()
          if ev:started() and ev:restart() then assert(ev:started()) else assert(not ev:started()) end
          cnt = cnt + 1
        end
      else
        table.remove(self.private_.events, i)
        i = i - 1
      end
    end
  end
  self:purge()
  return cnt
end

---
-- ������� ������������� �������
function event_list:purge()
  for i = #self.private_.events, 1, -1 do
    if (not self.private_.events[i]:locked()) 
    and(not self.private_.events[i]:started())
    then
      table.remove(self.private_.events, i)
    end
  end
end

end
-------------------------------------------------------------------

-------------------------------------------------------------------
local zmq_loop = {} do
zmq_loop.__index = zmq_loop

-- static
function zmq_loop.sleep(ms) ztimer.sleep(ms) end

---
-- ctor
function zmq_loop:new(...)
  return setmetatable({}, self):init(...)
end

function zmq_loop:init(N, ctx)
  self.private_ = self.private_ or {}
  self.private_.sockets = {}
  self.private_.event_list = event_list:new()

  local poller, err  = zpoller.new(N)
  if not poller then return nil, err end
  self.private_.poller = poller

  local context, err
  if not ctx then context, err = zmq.init(1)
  else context, err = ctx end
  if not context then self:destroy() return nil, err end
  self.private_.context = context

  return self
end

function zmq_loop:destroyed()
  return nil == self.private_.event_list
end

function zmq_loop:destroy()
  if self:destroyed() then return end

  self.private_.event_list:destroy()
  for s in pairs(self.private_.sockets) do
    self.private_.poller:remove(s)
    if( type(s) ~= 'number' ) then
      s:close()
    end
  end
  if self.private_.context  then self.private_.context:term() end

  self.private_.sockets = nil
  self.private_.event_list = nil
  self.private_.poller = nil
  self.private_.context = nil
end

function zmq_loop:context()
  return self.private_.context
end

function zmq_loop:interrupt()
  self.private_.poller:stop()
  self.private_.interrupt = true
end
zmq_loop.stop = zmq_loop.interrupt

function zmq_loop:interrupted()
  return (self.private_.interrupt) or (self.private_.poller.is_running == false)
end
zmq_loop.stopped = zmq_loop.interrupted

function zmq_loop:poll(interval)
  if self:interrupted() then return nil, 'interrupt' end
  interval = self.private_.event_list:sleep_interval(interval)
  local cnt, msg = self.private_.poller:poll(interval * ZMQ_POLL_MSEC)
  if not cnt then
    self:interrupt()
    return nil, msg
  end
  if self:interrupted() then return nil, 'interrupt' end
  cnt = cnt + self.private_.event_list:fire(self)
  return cnt
end

---
-- � ������� �������� �������������� ��� �������
-- � ��� ����� � ���������������
function zmq_loop:sleep_ex(interval)
  local start = ztimer.monotonic_time()
  local rest = interval
  local c = 0
  while true do
    local cnt, msg = self:poll(rest)
    if not cnt then return nil, msg end
    c = c + cnt
    rest = interval - ztimer.monotonic_elapsed(start)
    if rest <= 0 then return c end
  end
end

---
-- ������������ ������ ������� IO ����������� �� ������� ������
-- ���� ������� ���, �� ������� ���������� ���������� ����������
function zmq_loop:flush(interval)
  if self:interrupted() then return nil, 'interrupt' end
  interval = interval or 0
  local start = ztimer.monotonic_time()
  local rest = interval
  local c = 0
  while true do 
    local cnt, msg = self.private_.poller:poll(0)
    if not cnt then return nil, msg end
    c = c + cnt
    rest = interval - ztimer.monotonic_elapsed(start)
    if (cnt == 0) or (rest <= 0) then break end
  end
  if self:interrupted() then return nil, 'interrupt', c end
  return c
end

---
-- ��������� ���� ��������� �������
--
function zmq_loop:start(ms, fn)
  local self_ = self
  
  -- ���� �� ����� ��������, �� �� ���� ��������
  if not ms then fn = function()end end

  if (not fn) and ms then 
    -- ���� ���� �� ������ �������, �� �������� ����������
    -- � �������� ��� ������������� � ���������� �����������
    fn = function() if self_.on_time then self_:on_time() end end
  end
  ms = ms or 60000 -- ������ ������� �����.

  while true do
    local cnt, msg = self:sleep_ex(ms)
    if not cnt then return nil, msg end
    fn()
    if self:interrupted() then return nil, 'interrupt' end
  end
end

---------------------------------------------------------
-- ����������� �������
---------------------------------------------------------

---
-- ��������� zmq ����� 
-- fn - ������ ��������� �/�. ������ ���������� ���������� zmq_loop
-- zmq_flag - ����� ��� poll(�� ��������� zmq.POLLIN)
-- 
-- ����� ��������� �� �������� zmq_loop � ����������� � 
-- ������ ����������� zmq_loop
function zmq_loop:add_socket(skt, fn_or_flags, fn)
  if fn == nil then 
    assert(fn_or_flags and type(fn_or_flags) ~= 'number', 'function expected')
    fn, fn_or_flags = fn_or_flags, nil
  end
  local zmq_flag = fn_or_flags or zmq.POLLIN
  local loop = self
  self.private_.poller:add(skt, zmq_flag, function(skt, events)
    return fn(skt, events, loop)
  end)
  self.private_.sockets[skt] = true
  return skt
end

function zmq_loop:add_time(tm, fn)
  local ev = time_event:new(fn)
  ev:set_time(tm)
  self.private_.event_list:add(ev)
  return ev
end

function zmq_loop:add_interval(interval, fn)
  assert(type(interval) == 'number')
  local ev = time_event:new(fn)
  ev:set_interval(interval)
  self.private_.event_list:add(ev)
  return ev
end

function zmq_loop:add_once(interval, fn)
  assert(type(interval) == 'number')
  local ev = time_event:new(fn)
  ev:set_interval_once(interval)
  self.private_.event_list:add(ev)
  return ev
end

function zmq_loop:remove_socket(skt)
  if not self.private_.sockets[skt] then return end
  self.private_.poller:remove(skt)
  self.private_.sockets[skt] = nil
  return skt
end

---------------------------------------------------------
-- �������� �������
---------------------------------------------------------
---
-- ��� ��������� ������� �������� �� ������������� � 
-- ������ ��� ��������� �������� �������

-- create_XXX - ������ �������, �� �� ��������� ����� � zmq_loop
-- add_XXX -  ��������� �����(�������� ����� ���������) � zmq_loop 

---
-- ������� ����� � ��������� zmq_loop
function zmq_loop:create_socket(...)
  local skt, err = self.private_.context:socket(...)
  if not skt then return nil, err end
  if type(skt) ~= 'userdata' then return nil, skt end
  return skt
end

function zmq_loop:create_sub(subs)
  local skt, err = self:create_socket(zmq.SUB)
  if not skt then return nil, err end
  local ok, err = skt:set_linger(0)
  if not ok then skt:close() return nil, err end
  if type(subs) == 'string' then 
    ok,err = skt:set_subscribe(subs)
    if not ok then skt:close() return nil, err end
  else
    for k, str in ipairs(subs) do
      ok,err = skt:set_subscribe(str)
      if not ok then skt:close() return nil, err end
    end
  end
  return skt
end

function zmq_loop:create_sub_bind(addr, subs)
  local skt, err = self:create_sub(subs)
  if not skt then return nil, err end
  local ok, err = skt:bind(addr)
  if not ok then skt:close() return nil, err end
  return skt
end

function zmq_loop:create_sub_connect(addr, subs)
  local skt, err = self:create_sub(subs)
  if not skt then return nil, err end
  local ok, err = skt:connect(addr)
  if not ok then skt:close() return nil, err end
  return skt
end

function zmq_loop:create_bind(sock_type, addr)
  local skt, err = self:create_socket(sock_type)
  if not skt then return nil, err end
  local ok, err = skt:set_linger(0)
  if not ok then skt:close() return nil, err end
  if type(addr) == 'table' then 
    for _, v in ipairs(addr) do
      ok, err = skt:bind(v)
      if not ok then skt:close() return nil, err end
    end
  else
    ok, err = skt:bind(addr)
    if not ok then skt:close() return nil, err end
  end
  return skt
end

function zmq_loop:create_connect(sock_type, addr)
  local skt, err = self:create_socket(sock_type)
  if not skt then return nil, err end
  local ok, err = skt:set_linger(0)
  if not ok then skt:close() return nil, err end
  if type(addr) == 'table' then 
    for _, v in ipairs(addr) do
      ok, err = skt:connect(v)
      if not ok then skt:close() return nil, err end
    end
  else
    ok, err = skt:connect(addr)
    if not ok then skt:close() return nil, err end
  end
  return skt
end

function zmq_loop:add_new_bind(sock_type, addr, fn)
  local skt,err = self:create_bind(sock_type, addr)
  if not skt then return nil, err end
  self:add_socket(skt, fn)
  return skt
end

function zmq_loop:add_new_connect(sock_type, addr, fn)
  local skt,err = self:create_connect(sock_type, addr)
  if not skt then return nil, err end
  self:add_socket(skt, fn)
  return skt
end

function zmq_loop:add_sub_connect(addr, subs, fn)
  local skt,err = self:create_sub_connect(addr, subs)
  if not skt then return nil, err end
  self:add_socket(skt, fn)
  return skt
end

function zmq_loop:add_sub_bind(addr, subs, fn)
  local skt,err = self:create_sub_bind(addr, subs, addr)
  if not skt then return nil, err end
  self:add_socket(skt, fn)
  return skt
end

end
-------------------------------------------------------------------

local M = {}

function M.new(p, ...)
  if p == _M then return zmq_loop:new(...) end
  return zmq_loop:new(p, ...)
end

M.sleep = ztimer.sleep

M.zmq_loop_class = zmq_loop

return M
