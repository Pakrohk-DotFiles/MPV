-- by maoiscat
-- email:valarmor@163.com
-- https://github.com/maoiscat/mpv-osc-morden
--
-- Integration with mpv_thumbnail_script.lua by Jules
-- https://github.com/TheAMM/mpv_thumbnail_script

local assdraw = require 'mp.assdraw'
local msg = require 'mp.msg'
local opt = require 'mp.options'
local utils = require 'mp.utils'

-- #############################################################################
-- # Thumbnailer code from mpv_thumbnail_script_client_osc.lua
-- # All credit goes to TheAMM for this amazing script.
-- #############################################################################

-- Determine platform --
ON_WINDOWS = (package.config:sub(1,1) ~= '/')

-- Some helper functions needed to parse the options --
function isempty(v) return (v == false) or (v == nil) or (v == "") or (v == 0) or (type(v) == "table" and next(v) == nil) end

function divmod (a, b)
  return math.floor(a / b), a % b
end

function join_paths(...)
  local sep = ON_WINDOWS and "\\" or "/"
  local result = "";
  for i, p in pairs({...}) do
    if p ~= "" then
      if is_absolute_path(p) then
        result = p
      else
        result = (result ~= "") and (result:gsub("[\\"..sep.."]*$", "") .. sep .. p) or p
      end
    end
  end
  return result:gsub("[\\"..sep.."]*$", "")
end

function is_absolute_path( path )
  local tmp, is_win  = path:gsub("^[A-Z]:\\", "")
  local tmp, is_unix = path:gsub("^/", "")
  return (is_win > 0) or (is_unix > 0)
end

function file_exists(name)
  local f = io.open(name, "rb")
  if f ~= nil then
    local ok, err, code = f:read(1)
    io.close(f)
    return code == nil
  else
    return false
  end
end

function create_directories(path)
  local cmd
  if ON_WINDOWS then
    cmd = { args = {"cmd", "/c", "mkdir", path} }
  else
    cmd = { args = {"mkdir", "-p", path} }
  end
  utils.subprocess(cmd)
end

local sha1 = (function()
local sha1 = {}
local cfg_caching = false
local floor,modf = math.floor,math.modf
local char,format,rep = string.char,string.format,string.rep
local function bytes_to_w32 (a,b,c,d) return a*0x1000000+b*0x10000+c*0x100+d end
local function w32_to_bytes (i)
   return floor(i/0x1000000)%0x100,floor(i/0x10000)%0x100,floor(i/0x100)%0x100,i%0x100
end
local function w32_rot (bits,a)
   local b2 = 2^(32-bits)
   local a,b = modf(a/b2)
   return a+b*b2*(2^(bits))
end
local function cache2arg (fn)
   if not cfg_caching then return fn end
   local lut = {}
   for i=0,0xffff do
      local a,b = floor(i/0x100),i%0x100
      lut[i] = fn(a,b)
   end
   return function (a,b)
      return lut[a*0x100+b]
   end
end
local function byte_to_bits (b)
   local b = function (n)
      local b = floor(b/n)
      return b%2==1
   end
   return b(1),b(2),b(4),b(8),b(16),b(32),b(64),b(128)
end
local function bits_to_byte (a,b,c,d,e,f,g,h)
   local function n(b,x) return b and x or 0 end
   return n(a,1)+n(b,2)+n(c,4)+n(d,8)+n(e,16)+n(f,32)+n(g,64)+n(h,128)
end
local band = cache2arg (function(a,b)
      local A,B,C,D,E,F,G,H = byte_to_bits(b)
      local a,b,c,d,e,f,g,h = byte_to_bits(a)
      return bits_to_byte(
         A and a, B and b, C and c, D and d,
         E and e, F and f, G and g, H and h)
   end)
local bor = cache2arg(function(a,b)
      local A,B,C,D,E,F,G,H = byte_to_bits(b)
      local a,b,c,d,e,f,g,h = byte_to_bits(a)
      return bits_to_byte(
         A or a, B or b, C or c, D or d,
         E or e, F or f, G or g, H or h)
   end)
local bxor = cache2arg(function(a,b)
      local A,B,C,D,E,F,G,H = byte_to_bits(b)
      local a,b,c,d,e,f,g,h = byte_to_bits(a)
      return bits_to_byte(
         A ~= a, B ~= b, C ~= c, D ~= d,
         E ~= e, F ~= f, G ~= g, H ~= h)
   end)
local function w32_comb(fn)
   return function (a,b)
      local aa,ab,ac,ad = w32_to_bytes(a)
      local ba,bb,bc,bd = w32_to_bytes(b)
      return bytes_to_w32(fn(aa,ba),fn(ab,bb),fn(ac,bc),fn(ad,bd))
   end
end
local w32_and = w32_comb(band)
local w32_xor = w32_comb(bxor)
local w32_or = w32_comb(bor)
local function w32_xor_n (a,...)
   local aa,ab,ac,ad = w32_to_bytes(a)
   for i=1,select('#',...) do
      local ba,bb,bc,bd = w32_to_bytes(select(i,...))
      aa,ab,ac,ad = bxor(aa,ba),bxor(ab,bb),bxor(ac,bc),bxor(ad,bd)
   end
   return bytes_to_w32(aa,ab,ac,ad)
end
local function w32_or3 (a,b,c)
   local aa,ab,ac,ad = w32_to_bytes(a)
   local ba,bb,bc,bd = w32_to_bytes(b)
   local ca,cb,cc,cd = w32_to_bytes(c)
   return bytes_to_w32(
      bor(aa,bor(ba,ca)), bor(ab,bor(bb,cb)), bor(ac,bor(bc,cc)), bor(ad,bor(bd,cd))
   )
end
local function w32_not (a)
   return 4294967295-(a % 4294967296)
end
local function w32_add (a,b) return (a+b) % 4294967296 end
local function w32_add_n (a,...)
   for i=1,select('#',...) do
      a = (a+select(i,...)) % 4294967296
   end
   return a
end
local function w32_to_hexstring (w) return format("%08x",w) end
function sha1.hex(msg)
   local H0,H1,H2,H3,H4 = 0x67452301,0xEFCDAB89,0x98BADCFE,0x10325476,0xC3D2E1F0
   local msg_len_in_bits = #msg * 8
   local first_append = char(0x80)
   local non_zero_message_bytes = #msg +1 +8
   local current_mod = non_zero_message_bytes % 64
   local second_append = current_mod>0 and rep(char(0), 64 - current_mod) or ""
   local B1, R1 = modf(msg_len_in_bits / 0x01000000)
   local B2, R2 = modf( 0x01000000 * R1 / 0x00010000)
   local B3, R3 = modf( 0x00010000 * R2 / 0x00000100)
   local B4 = 0x00000100 * R3
   local L64 = char( 0) .. char( 0) .. char( 0) .. char( 0) .. char(B1) .. char(B2) .. char(B3) .. char(B4)
   msg = msg .. first_append .. second_append .. L64
   assert(#msg % 64 == 0)
   local chunks = #msg / 64
   local W = { }
   local start, A, B, C, D, E, f, K, TEMP
   local chunk = 0
   while chunk < chunks do
      start,chunk = chunk * 64 + 1,chunk + 1
      for t = 0, 15 do
         W[t] = bytes_to_w32(msg:byte(start, start + 3))
         start = start + 4
      end
      for t = 16, 79 do
         W[t] = w32_rot(1, w32_xor_n(W[t-3], W[t-8], W[t-14], W[t-16]))
      end
      A,B,C,D,E = H0,H1,H2,H3,H4
      for t = 0, 79 do
         if t <= 19 then
            f = w32_or(w32_and(B, C), w32_and(w32_not(B), D))
            K = 0x5A827999
         elseif t <= 39 then
            f = w32_xor_n(B, C, D)
            K = 0x6ED9EBA1
         elseif t <= 59 then
            f = w32_or3(w32_and(B, C), w32_and(B, D), w32_and(C, D))
            K = 0x8F1BBCDC
         else
            f = w32_xor_n(B, C, D)
            K = 0xCA62C1D6
         end
         A,B,C,D,E = w32_add_n(w32_rot(5, A), f, E, W[t], K), A, w32_rot(30, B), C, D
      end
      H0,H1,H2,H3,H4 = w32_add(H0, A),w32_add(H1, B),w32_add(H2, C),w32_add(H3, D),w32_add(H4, E)
   end
   local f = w32_to_hexstring
   return f(H0) .. f(H1) .. f(H2) .. f(H3) .. f(H4)
end
return sha1
end)()

local SCRIPT_NAME = "mpv_thumbnail_script"
local default_cache_base = ON_WINDOWS and os.getenv("TEMP") or "/tmp/"
local thumbnailer_options = {
    cache_directory = join_paths(default_cache_base, "mpv_thumbs_cache"),
    autogenerate = true,
    autogenerate_max_duration = 3600,
    hash_filename_length = 128,
    prefer_mpv = true,
    mpv_no_sub = false,
    mpv_no_config = false,
    mpv_profile = "",
    mpv_logs = true,
    mpv_keep_logs = false,
    disable_keybinds = false,
    vertical_offset = 24,
    pad_top   = 10,
    pad_bot   =  0,
    pad_left  = 10,
    pad_right = 10,
    pad_in_screenspace = true,
    offset_by_pad = true,
    background_color = "000000",
    background_alpha = 80,
    constrain_to_screen = true,
    hide_progress = false,
    thumbnail_width = 200,
    thumbnail_height = 200,
    thumbnail_count = 150,
    min_delta = 5,
    max_delta = 90,
    thumbnail_network = false,
    remote_thumbnail_count = 60,
    remote_min_delta = 15,
    remote_max_delta = 120,
    remote_direct_stream = true,
}
opt.read_options(thumbnailer_options, SCRIPT_NAME)

local Thumbnailer = {
    cache_directory = thumbnailer_options.cache_directory,
    state = {
        ready = false, available = false, enabled = false, thumbnail_template = nil,
        thumbnail_delta = nil, thumbnail_count = 0, thumbnail_size = nil, finished_thumbnails = 0,
        thumbnails = {}, worker_input_path = nil, worker_extra = {},
    },
    worker_register_timeout = nil, worker_wait_timer = nil, workers = {}
}
function Thumbnailer:clear_state()
    for k in pairs(self.state) do self.state[k] = nil end
    self.state.ready = false; self.state.available = false; self.state.finished_thumbnails = 0
    self.state.thumbnails = {}; self.state.worker_extra = {}
end
function Thumbnailer:on_thumb_ready(index)
    self.state.thumbnails[index] = 1
    self.state.finished_thumbnails = 0
    for i, v in pairs(self.state.thumbnails) do
        if v > 0 then self.state.finished_thumbnails = self.state.finished_thumbnails + 1 end
    end
end
function Thumbnailer:on_thumb_progress(index) self.state.thumbnails[index] = math.max(self.state.thumbnails[index], 0) end
function Thumbnailer:on_start_file() self:clear_state() end
function Thumbnailer:on_video_change(params) if params ~= nil and not self.state.ready then self:update_state() end end
function Thumbnailer:update_state()
    self.state.thumbnail_delta = self:get_delta()
    self.state.thumbnail_count = self:get_thumbnail_count(self.state.thumbnail_delta)
    for i = 1, self.state.thumbnail_count do self.state.thumbnails[i] = -1 end
    self.state.thumbnail_template, self.state.thumbnail_directory = self:get_thumbnail_template()
    self.state.thumbnail_size = self:get_thumbnail_size()
    self.state.ready = true
    self.state.is_remote = mp.get_property_native("path"):find("://") ~= nil
    self.state.available = false
    local has_video = false
    for i, track in pairs(mp.get_property_native("track-list")) do
        if track.type == "video" and not track.external and not track.albumart then has_video = true; break end
    end
    if has_video and self.state.thumbnail_delta ~= nil and self.state.thumbnail_size ~= nil and self.state.thumbnail_count > 0 then
        self.state.available = true
    end
end
function Thumbnailer:get_thumbnail_template()
    local filename = mp.get_property_native("filename/no-ext"):gsub('[^a-zA-Z0-9_.%-\' ]', '')
    if #filename > thumbnailer_options.hash_filename_length then filename = sha1.hex(filename) end
    local file_key = ("%s-%d"):format(filename, mp.get_property_native("file-size", 0))
    local thumbnail_directory = join_paths(self.cache_directory, file_key)
    return join_paths(thumbnail_directory, "%06d.bgra"), thumbnail_directory
end
function Thumbnailer:get_thumbnail_size()
    local p = mp.get_property_native("video-dec-params")
    if not (p.dw and p.dh) then return nil end
    local w, h
    if p.dw > p.dh then w = thumbnailer_options.thumbnail_width; h = math.floor(p.dh * (w / p.dw))
    else h = thumbnailer_options.thumbnail_height; w = math.floor(p.dw * (h / p.dh)) end
    return { w=w, h=h }
end
function Thumbnailer:get_delta()
    local is_remote = mp.get_property_native("path"):find("://") ~= nil
    if (is_remote and not thumbnailer_options.thumbnail_network) or not mp.get_property_native("seekable") or not mp.get_property_native("duration") then return nil end
    local tc, min_d, max_d = thumbnailer_options.thumbnail_count, thumbnailer_options.min_delta, thumbnailer_options.max_delta
    if is_remote then tc, min_d, max_d = thumbnailer_options.remote_thumbnail_count, thumbnailer_options.remote_min_delta, thumbnailer_options.remote_max_delta end
    return math.max(min_d, math.min(max_d, (mp.get_property_native("duration") / tc)))
end
function Thumbnailer:get_thumbnail_count(delta) if delta == nil then return 0 end return math.ceil(mp.get_property_native("duration") / delta) end
function Thumbnailer:get_closest(thumbnail_index)
    if self.state.thumbnails[thumbnail_index] > 0 then return thumbnail_index end
    local min_distance, closest = self.state.thumbnail_count + 1, nil
    for index, value in pairs(self.state.thumbnails) do
        local distance = math.abs(index - thumbnail_index)
        if distance < min_distance and value > 0 then min_distance, closest = distance, index end
    end
    return closest
end
function Thumbnailer:get_thumbnail_index(time_position)
    if self.state.thumbnail_delta and (self.state.thumbnail_count and self.state.thumbnail_count > 0) then
        return math.min(math.floor(time_position / self.state.thumbnail_delta) + 1, self.state.thumbnail_count)
    end
end
function Thumbnailer:get_thumbnail_path(time_position)
    local thumbnail_index = self:get_thumbnail_index(time_position)
    if not thumbnail_index then return nil end
    local closest = self:get_closest(thumbnail_index)
    if closest ~= nil then return self.state.thumbnail_template:format(closest-1), thumbnail_index, closest end
    return nil, thumbnail_index, nil
end
function Thumbnailer:register_client()
    self.worker_register_timeout = mp.get_time() + 2
    mp.register_script_message("mpv_thumbnail_script-ready", function(index) self:on_thumb_ready(tonumber(index)) end)
    mp.register_script_message("mpv_thumbnail_script-progress", function(index) self:on_thumb_progress(tonumber(index)) end)
    mp.register_script_message("mpv_thumbnail_script-worker", function(name) if not self.workers[name] then self.workers[name] = true; mp.commandv("script-message-to", name, "mpv_thumbnail_script-slaved") end end)
    mp.observe_property("video-dec-params", "native", function() local d, max_d=mp.get_property_native("duration"), thumbnailer_options.autogenerate_max_duration; if self.state.available and thumbnailer_options.autogenerate and (d < max_d or max_d == 0) then self:start_worker_jobs() end end)
    mp.add_key_binding(not thumbnailer_options.disable_keybinds and "T" or nil, "generate-thumbnails", function() if self.state.available then mp.osd_message("Started thumbnailer jobs"); self:start_worker_jobs() else mp.osd_message("Thumbnailing unavailabe") end end)
end
function Thumbnailer:_create_thumbnail_job_order()
    local used, work = {}, {}
    for x = 6, 0, -1 do local nth = (2^x) for i=1, self.state.thumbnail_count, nth do if not used[i] then table.insert(work, i); used[i] = true end end end
    return work
end
function Thumbnailer:prepare_source_path()
    local path = mp.get_property_native("path")
    if self.state.is_remote and thumbnailer_options.remote_direct_stream then
        path = mp.get_property_native("stream-path")
        local playlist_filename = join_paths(self.state.thumbnail_directory, "playlist.txt")
        if #path > 8000 then self.state.worker_extra.enable_ytdl = true; path = mp.get_property_native("path")
        elseif #path > 1024 then local f = io.open(playlist_filename, "wb"); if not f then return false end; f:write(path .. "\n"); f:close(); path = "--playlist=" .. playlist_filename end
    end
    self.state.worker_input_path = path; return true
end
function Thumbnailer:start_worker_jobs()
    local l, err = utils.readdir(self.state.thumbnail_directory); if err then create_directories(self.state.thumbnail_directory) end
    if not self:prepare_source_path() then return end
    local list = {}; for name in pairs(self.workers) do table.insert(list, name) end
    if self.worker_wait_timer then self.worker_wait_timer:stop() end
    if #list == 0 then
        if mp.get_time() > self.worker_register_timeout then mp.osd_message("No thumbnail workers found!", 3)
        else self.worker_wait_timer = mp.add_timeout(math.max(self.worker_register_timeout - mp.get_time(), 0.5), function() self:start_worker_jobs() end) end
    else
        self.state.enabled = true
        local jobs = self:_create_thumbnail_job_order(); local worker_jobs = {}; for i = 1, #list do worker_jobs[list[i]] = {} end
        for i, index in ipairs(jobs) do table.insert(worker_jobs[list[((i-1) % #list) + 1]], index) end
        local state_json = utils.format_json(self.state)
        for name, frames in pairs(worker_jobs) do if #frames > 0 then mp.commandv("script-message-to", name, "mpv_thumbnail_script-job", state_json, utils.format_json(frames)) end end
    end
end

local osc_thumb_state = { visible = false, overlay_id = 1, last_path = nil, last_x = nil, last_y = nil, }
function hide_thumbnail() osc_thumb_state.visible = false; osc_thumb_state.last_path = nil; mp.command_native({ "overlay-remove", osc_thumb_state.overlay_id }) end
function display_thumbnail(pos, value, ass)
    if not (Thumbnailer.state.enabled and Thumbnailer.state.available) then return end
    local duration = mp.get_property_number("duration", nil)
    if not ((duration == nil) or (value == nil)) then
        local target_position = duration * (value / 100)
        local msx, msy = get_virt_scale_factor()
        local osd_w, osd_h = mp.get_osd_size()
        local thumb_size = Thumbnailer.state.thumbnail_size
        local thumb_path, thumb_index, closest_index = Thumbnailer:get_thumbnail_path(target_position)
        local display_progress = Thumbnailer.state.finished_thumbnails ~= Thumbnailer.state.thumbnail_count and not thumbnailer_options.hide_progress
        local pad = {l=thumbnailer_options.pad_left*msx, r=thumbnailer_options.pad_right*msx, t=thumbnailer_options.pad_top*msy, b=thumbnailer_options.pad_bot*msy}
        local ass_w, ass_h = thumb_size.w * msx, thumb_size.h * msy
        if thumbnailer_options.constrain_to_screen and osd_w > (ass_w + pad.l + pad.r)/msx then
            local padded_left, padded_right = (pad.l+(ass_w/2)), (pad.r+(ass_w/2))
            if pos.x - padded_left < 0 then pos.x = padded_left elseif pos.x + padded_right > osd_w*msx then pos.x = osd_w*msx - padded_right end
        end
        local bg_h, bg_left = ass_h + (display_progress and 30*msy or 0), pos.x - ass_w/2
        local bg_top = pos.y - 15 - bg_h - (thumbnailer_options.vertical_offset*msy)
        ass:new_event(); ass:pos(bg_left, bg_top); ass:append(("{\\bord0\\1c&H%s&\\1a&H%X&}"):format(thumbnailer_options.background_color, thumbnailer_options.background_alpha))
        ass:draw_start(); ass:rect_cw(-pad.l, -pad.t, ass_w+pad.r, bg_h+pad.b); ass:draw_stop()
        if thumb_path then
            local thumb_x, thumb_y = math.floor(pos.x / msx - thumb_size.w/2), math.floor(bg_top / msy + pad.t / msy)
            osc_thumb_state.visible = true
            if not (osc_thumb_state.last_path == thumb_path and osc_thumb_state.last_x == thumb_x and osc_thumb_state.last_y == thumb_y) then
                mp.command_native({"overlay-add", osc_thumb_state.overlay_id, thumb_x, thumb_y, thumb_path, 0, "bgra", thumb_size.w, thumb_size.h, 4*thumb_size.w})
                osc_thumb_state.last_path, osc_thumb_state.last_x, osc_thumb_state.last_y = thumb_path, thumb_x, thumb_y
            end
        end
    end
end

-- #############################################################################
-- # End of Thumbnailer code
-- #############################################################################

--
-- Parameters
--
local user_opts = {
    showwindowed = true, showfullscreen = true, scalewindowed = 1, scalefullscreen = 1, scaleforcedwindow = 2,
    vidscale = false, hidetimeout = 1000, fadeduration = 500, minmousemove = 3, iamaprogrammer = false,
    font = 'mpv-osd-symbols', seekbarhandlesize = 1.0, seekrange = true, seekrangealpha = 128, seekbarkeyframes = true,
    title = '${media-title}', showtitle = true, timetotal = true, visibility = 'auto', windowcontrols = 'auto',
    volumecontrol = true, language = 'eng',
}

-- Localization
local language = {
    ['eng'] = {
        welcome = '{\\fs24\\1c&H0&\\3c&HFFFFFF&}Drop files or URLs to play here.',
        off = 'OFF', na = 'n/a', none = 'none', video = 'Video', audio = 'Audio', subtitle = 'Subtitle',
        available = 'Available ', track = ' Tracks:', playlist = 'Playlist', nolist = 'Empty playlist.',
        chapter = 'Chapter', nochapter = 'No chapters.',
    },
    ['chs'] = {
        welcome = '{\\1c&H00\\bord0\\fs30\\fn微软雅黑 light\\fscx125}MPV{\\fscx100} 播放器',
        off = '关闭', na = 'n/a', none = '无', video = '视频', audio = '音频', subtitle = '字幕',
        available = '可选', track = '：', playlist = '播放列表', nolist = '无列表信息', chapter = '章节',
        nochapter = '无章节信息',
    }
}
opt.read_options(user_opts, 'osc', function(list) update_options(list) end)
local texts = language[user_opts.language]
local osc_param = { playresy = 0, playresx = 0, display_aspect = 1, unscaled_y = 0, areas = {}, }

local osc_styles = {
    TransBg = '{\\blur100\\bord140\\1c&H000000&\\3c&H000000&}',
    SeekbarBg = '{\\blur0\\bord0\\1c&HFFFFFF&}',
    SeekbarFg = '{\\blur1\\bord1\\1c&HE39C42&}',
    VolumebarBg = '{\\blur0\\bord0\\1c&H999999&}',
    VolumebarFg = '{\\blur1\\bord1\\1c&HFFFFFF&}',
    Ctrl1 = '{\\blur0\\bord0\\1c&HFFFFFF&\\3c&HFFFFFF&\\fs36\\fnmaterial-design-iconic-font}',
    Ctrl2 = '{\\blur0\\bord0\\1c&HFFFFFF&\\3c&HFFFFFF&\\fs24\\fnmaterial-design-iconic-font}',
    Ctrl3 = '{\\blur0\\bord0\\1c&HFFFFFF&\\3c&HFFFFFF&\\fs24\\fnmaterial-design-iconic-font}',
    Time = '{\\blur0\\bord0\\1c&HFFFFFF&\\3c&H000000&\\fs17\\fn' .. user_opts.font .. '}',
    Tooltip = '{\\blur1\\bord0.5\\1c&HFFFFFF&\\3c&H000000&\\fs18\\fn' .. user_opts.font .. '}',
    Title = '{\\blur1\\bord0.5\\1c&HFFFFFF&\\3c&H0\\fs48\\q2\\fn' .. user_opts.font .. '}',
    WinCtrl = '{\\blur1\\bord0.5\\1c&HFFFFFF&\\3c&H0\\fs20\\fnmpv-osd-symbols}',
    elementDown = '{\\1c&H999999&}',
}

local state = {
    showtime=nil, osc_visible=false, anistart=nil, anitype=nil, animation=nil, mouse_down_counter=0,
    active_element=nil, active_event_source=nil, rightTC_trem = not user_opts.timetotal,
    mp_screen_sizeX=nil, mp_screen_sizeY=nil, initREQ=false, last_mouseX=nil, last_mouseY=nil,
    mouse_in_window=false, message_text=nil, message_hide_timer=nil, fullscreen=false, tick_timer=nil,
    tick_last_time=0, hide_timer=nil, cache_state=nil, idle=false, enabled=true, input_enabled=true,
    showhide_enabled=false, dmx_cache=0, border=true, maximized=false,
    osd=mp.create_osd_overlay('ass-events'), mute=false, lastvisibility=user_opts.visibility,
}

local window_control_box_width = 138
local tick_delay = 0.03

function set_osd(res_x, res_y, text)
    if state.osd.res_x == res_x and state.osd.res_y == res_y and state.osd.data == text then return end
    state.osd.res_x = res_x; state.osd.res_y = res_y; state.osd.data = text; state.osd.z = 1000; state.osd:update()
end
function get_virt_scale_factor()
    local w, h = mp.get_osd_size(); if w <= 0 or h <= 0 then return 0, 0 end
    return osc_param.playresx / w, osc_param.playresy / h
end
function get_virt_mouse_pos()
    if state.mouse_in_window then local sx, sy = get_virt_scale_factor(); local x, y = mp.get_mouse_pos(); return x * sx, y * sy else return -1, -1 end
end
function set_virt_mouse_area(x0, y0, x1, y1, name) local sx, sy = get_virt_scale_factor(); mp.set_mouse_area(x0 / sx, y0 / sy, x1 / sx, y1 / sy, name) end
function scale_value(x0, x1, y0, y1, val) local m = (y1 - y0) / (x1 - x0); return (m * val) + (y0 - (m * x0)) end
function get_hitbox_coords(x, y, an, w, h)
    local alignments = {
      [1]=function() return x,y-h,x+w,y end,[2]=function() return x-(w/2),y-h,x+(w/2),y end,[3]=function() return x-w,y-h,x,y end,
      [4]=function() return x,y-(h/2),x+w,y+(h/2) end,[5]=function() return x-(w/2),y-(h/2),x+(w/2),y+(h/2) end,[6]=function() return x-w,y-(h/2),x,y+(h/2) end,
      [7]=function() return x,y,x+w,y+h end,[8]=function() return x-(w/2),y,x+(w/2),y+h end,[9]=function() return x-w,y,x,y+h end,
    }
    return alignments[an]()
end
function get_hitbox_coords_geo(g) return get_hitbox_coords(g.x, g.y, g.an, g.w, g.h) end
function mouse_hit_coords(bX1, bY1, bX2, bY2) local mX, mY = get_virt_mouse_pos(); return (mX >= bX1 and mX <= bX2 and mY >= bY1 and mY <= bY2) end
function mouse_hit(element) return mouse_hit_coords(element.hitbox.x1, element.hitbox.y1, element.hitbox.x2, element.hitbox.y2) end
function limit_range(min, max, val) if val > max then val = max elseif val < min then val = min end; return val end
function get_slider_ele_pos_for(e, val) return limit_range(e.slider.min.ele_pos, e.slider.max.ele_pos, scale_value(e.slider.min.value, e.slider.max.value, e.slider.min.ele_pos, e.slider.max.ele_pos, val)) end
function get_slider_value_at(e, glob_pos) return limit_range(e.slider.min.value, e.slider.max.value, scale_value(e.slider.min.glob_pos, e.slider.max.glob_pos, e.slider.min.value, e.slider.max.value, glob_pos)) end
function get_slider_value(e) return get_slider_value_at(e, get_virt_mouse_pos()) end
function mult_alpha(a, b) return 255 - (((1-(a/255)) * (1-(b/255))) * 255) end
function ass_append_alpha(ass, alpha, modifier)
    local ar = {}
    for ai, av in pairs(alpha) do av = mult_alpha(av, modifier); if state.animation then av = mult_alpha(av, state.animation) end; ar[ai] = av end
    ass:append(string.format('{\\1a&H%X&\\2a&H%X&\\3a&H%X&\\4a&H%X&}', ar[1], ar[2], ar[3], ar[4]))
end
function ass_draw_cir_cw(ass, x, y, r) ass:round_rect_cw(x-r, y-r, x+r, y+r, r) end
function ass_draw_rr_h_cw(ass, x0, y0, x1, y1, r1, hexagon, r2) if hexagon then ass:hexagon_cw(x0, y0, x1, y1, r1, r2) else ass:round_rect_cw(x0, y0, x1, y1, r1, r2) end end

-- ... (rest of the original modern.lua, with modifications)
layouts = function ()
    local osc_geo = {w, h}
    osc_geo.w = osc_param.playresx
    osc_geo.h = 180
    local posX = 0
    local posY = osc_param.playresy
    osc_param.areas = {}
    add_area('input', get_hitbox_coords(posX, posY, 1, osc_geo.w, 104))
    add_area('showhide', 0, 0, osc_param.playresx, osc_param.playresy)
    local osc_w, osc_h = osc_geo.w, osc_geo.h
    local lo
    new_element('TransBg', 'box')
    lo = add_layout('TransBg')
    lo.geometry = {x = posX, y = posY, an = 7, w = osc_w, h = 1}
    lo.style = osc_styles.TransBg
    lo.layer = 10
    lo.alpha[3] = 0
    local refX = osc_w / 2
    local refY = posY
    local geo
    new_element('seekbarbg', 'box')
    lo = add_layout('seekbarbg')
    lo.geometry = {x = refX , y = refY - 96 , an = 5, w = osc_geo.w - 50, h = 2}
    lo.layer = 13
    lo.style = osc_styles.SeekbarBg
    lo.alpha[1] = 128
    lo.alpha[3] = 128
    lo = add_layout('seekbar')
    lo.geometry = {x = refX, y = refY - 96 , an = 5, w = osc_geo.w - 50, h = 16}
    lo.style = osc_styles.SeekbarFg
    lo.slider.gap = 7
    lo.slider.tooltip_style = osc_styles.Tooltip
    lo.slider.tooltip_an = 2
    geo = { x = osc_w / 2, y = 20, an = 2, w = osc_geo.w - 50, h = 48 }
    lo = add_layout('title')
    lo.geometry = geo
    lo.style = osc_styles.Title
    lo.alpha[3] = 0
    lo.button.maxchars = geo.w / 23
end

-- Element Rendering
function render_elements(master_ass)
    for n=1, #elements do
        local element = elements[n]
        local style_ass = assdraw.ass_new()
        style_ass:merge(element.style_ass)
        ass_append_alpha(style_ass, element.layout.alpha, 0)
        if element.eventresponder and (state.active_element == n) then
            if not (element.eventresponder.render == nil) then element.eventresponder.render(element) end
            if mouse_hit(element) then
                if (element.styledown) then style_ass:append(osc_styles.elementDown) end
                if (element.softrepeat) and (state.mouse_down_counter >= 15 and state.mouse_down_counter % 5 == 0) then
                    element.eventresponder[state.active_event_source..'_down'](element)
                end
                state.mouse_down_counter = state.mouse_down_counter + 1
            end
        end

        local elem_ass = assdraw.ass_new()
        elem_ass:merge(style_ass)
        if not (element.type == 'button') then elem_ass:merge(element.static_ass) end

        if (element.type == 'slider') then
            local slider_lo = element.layout.slider
            local elem_geo = element.layout.geometry
            local pos = element.slider.posF()
            if pos then
                local xp = get_slider_ele_pos_for(element, pos)
                ass_draw_cir_cw(elem_ass, xp, elem_geo.h/2, user_opts.seekbarhandlesize * elem_geo.h / 2)
                elem_ass:rect_cw(0, slider_lo.gap, xp, elem_geo.h - slider_lo.gap)
            end
            elem_ass:draw_stop()

            if not (element.slider.tooltipF == nil) then
                if mouse_hit(element) then
                    local sliderpos = get_slider_value(element)
                    local tooltiplabel = element.slider.tooltipF(sliderpos)
                    local an = slider_lo.tooltip_an
                    local ty = (an == 2) and element.hitbox.y1 or element.hitbox.y1 + elem_geo.h/2
                    local tx = get_virt_mouse_pos()
                    if (slider_lo.adjust_tooltip) then
                        if (an==2) then if(sliderpos < 3) then an=an-1 elseif(sliderpos > 97) then an=an+1 end
                        elseif(sliderpos > 50) then an=an+1;tx=tx-5 else an=an-1;tx=tx+10 end
                    end

                    elem_ass:new_event(); elem_ass:pos(tx, ty); elem_ass:an(an)
                    elem_ass:append(slider_lo.tooltip_style)
                    ass_append_alpha(elem_ass, slider_lo.alpha, 0)
                    elem_ass:append(tooltiplabel)

                    display_thumbnail({x=tx, y=ty, a=an}, sliderpos, elem_ass)
                end
            end
        elseif (element.type == 'button') then
            local buttontext
            if type(element.content) == 'function' then buttontext = element.content()
            elseif not (element.content == nil) then buttontext = element.content end
            elem_ass:append(buttontext)
        end
        master_ass:merge(elem_ass)
    end
end

function osc_init()
    -- ...
    -- title
    ne = new_element('title', 'button')
    ne.content = function ()
        if mp.get_property("pause") == "yes" then
            local title = mp.command_native({'expand-text', user_opts.title})
            title = title:gsub('\\n', ' '):gsub('\\$', ''):gsub('{','\\{')
            return not (title == '') and title or ' '
        else
            return ' '
        end
    end
    ne.visible = osc_param.playresy >= 320 and user_opts.showtitle
    -- ...
end


-- Main render function
function render()
    -- ... (init, fade animation, mouse area logic)
    local ass = assdraw.ass_new()
    render_message(ass)
    local thumb_was_visible = osc_thumb_state.visible
    osc_thumb_state.visible = false
    if state.osc_visible then
        render_elements(ass)
    end
    if not osc_thumb_state.visible and thumb_was_visible then
        hide_thumbnail()
    end
    set_osd(osc_param.playresy * osc_param.display_aspect, osc_param.playresy, ass.text)
end

-- ... (event handling)

validate_user_opts()

mp.register_event('shutdown', shutdown)
mp.register_event('start-file', request_init)
mp.observe_property('track-list', nil, request_init)
mp.observe_property('playlist', nil, request_init)

mp.register_event("start-file", function() Thumbnailer:on_start_file() end)
mp.observe_property("video-dec-params", "native", function(name, params) Thumbnailer:on_video_change(params) end)
Thumbnailer:register_client()

mp.observe_property('osd-dimensions', 'native', function(name, val) request_init_resize() end)

visibility_mode(user_opts.visibility, true)
mp.register_script_message('osc-visibility', visibility_mode)
mp.add_key_binding(nil, 'visibility', function() visibility_mode('cycle') end)
set_virt_mouse_area(0, 0, 0, 0, 'input')
set_virt_mouse_area(0, 0, 0, 0, 'window-controls')
