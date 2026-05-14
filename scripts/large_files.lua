#!/usr/bin/env lua
-- Find and display the largest files on the filesystem with deletion suggestions.

-- ── categories ──────────────────────────────────────────────────────────────

local EXT_TO_CAT = {}
local function def(cat, ...)
  for _, e in ipairs({...}) do EXT_TO_CAT["." .. e] = cat end
end
def("Video",      "mp4","mkv","avi","mov","wmv","flv","webm","m4v","ts","vob")
def("Audio",      "mp3","flac","wav","aac","ogg","m4a","wma","opus")
def("Image",      "jpg","jpeg","png","gif","bmp","tiff","webp","heic","raw","cr2","nef")
def("Archive",    "zip","tar","gz","bz2","xz","7z","rar","zst","tgz","tbz2","tbz")
def("Disk Image", "iso","img","vmdk","vdi","qcow2","dmg")
def("Document",   "pdf","doc","docx","xls","xlsx","ppt","pptx","odt","ods")
def("Code",       "py","js","ts","go","rs","c","cpp","h","java","rb","sh")
def("Database",   "db","sqlite","sqlite3","sql")
def("Package",    "deb","rpm","pkg","apk","msi","exe")
def("Log",        "log")
def("Cache",      "cache")
def("Backup",     "bak","old","orig","backup")
def("Library",    "so","dylib","dll","a")

local DEL_PATHS = {
  "/.cache/","/tmp/","/var/tmp/","/var/cache/","/.local/share/Trash/",
  "/__pycache__/","/node_modules/","/.npm/_cacache/","/.cargo/registry/cache/",
  "/go/pkg/mod/cache/","/.gradle/caches/","/.m2/repository/",
  "/.thumbnails/","/thumbnails/",
}
local DEL_EXTS  = { [".log"]=true,[".bak"]=true,[".old"]=true,[".orig"]=true,
                    [".backup"]=true,[".cache"]=true,[".pyc"]=true,[".pyo"]=true }
local DEL_NAMES = { ["core"]=true,["core.gz"]=true,[".DS_Store"]=true,
                    ["Thumbs.db"]=true,["desktop.ini"]=true,
                    ["npm-debug.log"]=true,["yarn-error.log"]=true }

-- ── helpers ──────────────────────────────────────────────────────────────────

local function categorize(path, ext)
  local p = path:lower()
  if p:find("/node_modules/", 1, true) then return "Package" end
  if p:find("/__pycache__/",  1, true) or ext == ".pyc" then return "Cache" end
  if p:find("/.cache/", 1, true) or p:find("/cache/", 1, true) then return "Cache" end
  if p:find("/log/",  1, true) or p:find("/logs/", 1, true) then return "Log" end
  return EXT_TO_CAT[ext:lower()] or "Other"
end

local function is_deletable(path, ext, name)
  local p = path:lower()
  for _, pat in ipairs(DEL_PATHS) do
    if p:find(pat, 1, true) then
      return true, "in " .. pat:gsub("^/",""):gsub("/$","")
    end
  end
  if DEL_EXTS[ext:lower()]   then return true, ext .. " file"   end
  if DEL_NAMES[name:lower()] then return true, "temp/junk file" end
  return false, ""
end

local function human_size(n)
  for _, u in ipairs({"B","KB","MB","GB","TB"}) do
    if n < 1024 then return ("%.1f %s"):format(n, u) end
    n = n / 1024
  end
  return ("%.1f PB"):format(n)
end

local function shell_quote(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function term_width()
  local h = io.popen("tput cols 2>/dev/null")
  local w = h and tonumber(h:read("*l"))
  if h then h:close() end
  return math.min(w or 120, 160)
end

-- ── scan ─────────────────────────────────────────────────────────────────────

local function scan(roots, skip_mounts, min_size)
  local seen    = {}
  local entries = {}

  for _, root in ipairs(roots) do
    local xdev = skip_mounts and "-xdev" or ""
    -- find prints null-terminated paths; xargs batches them into stat calls.
    -- stat '%d %i %z %N' → "dev ino size /full/path" (path always last, may have spaces)
    local cmd = ("find %s %s -type f -size +%dc -print0 2>/dev/null"
              .. " | xargs -0 stat -f '%%d %%i %%z %%N' 2>/dev/null"):format(
                   shell_quote(root), xdev, min_size - 1)

    local h = io.popen(cmd)
    if not h then
      io.stderr:write("error: cannot scan " .. root .. "\n")
    else
      for line in h:lines() do
        local dev, ino, sz, path = line:match("^(%d+) (%d+) (%d+) (.+)$")
        if dev then
          local key = dev .. ":" .. ino
          if not seen[key] then
            seen[key] = true
            local name = path:match("[^/]+$") or path
            local ext  = name:match("(%.[^.]+)$") or ""
            local cat  = categorize(path, ext)
            local del, reason = is_deletable(path, ext, name)
            entries[#entries + 1] = {
              path = path, size = tonumber(sz),
              category = cat, deletable = del, reason = reason,
            }
          end
        end
      end
      h:close()
    end
  end

  table.sort(entries, function(a, b) return a.size > b.size end)
  return entries
end

-- ── output ───────────────────────────────────────────────────────────────────

local function print_table(entries, top_n, color)
  local n   = math.min(top_n, #entries)
  local w   = term_width()
  local sep = ("-"):rep(w)

  local RED  = color and "\27[31m"   or ""
  local HEAD = color and "\27[1;36m" or ""
  local RST  = color and "\27[0m"    or ""

  print(("\n%sTop %d Largest Files%s"):format(HEAD, n, RST))
  print(sep)
  print(("%4s  %10s  %-12s  %-5s  %-22s  Path"):format(
        "#", "Size", "Category", "Del?", "Reason"))
  print(sep)

  local total, del_size, del_count = 0, 0, 0
  for i = 1, n do
    local e   = entries[i]
    local del = e.deletable and "  *  " or "     "
    local row = ("%4d  %10s  %-12s  %-5s  %-22s  %s"):format(
                  i, human_size(e.size), e.category, del, e.reason, e.path)
    if color and e.deletable then
      print(RED .. row .. RST)
    else
      print(row)
    end
    total = total + e.size
    if e.deletable then
      del_size  = del_size  + e.size
      del_count = del_count + 1
    end
  end

  print(sep)
  print(("Total shown: %s  |  Flagged deletable: %d files (%s)"):format(
        human_size(total), del_count, human_size(del_size)))
end

-- ── arg parsing ──────────────────────────────────────────────────────────────

local function parse_args()
  local opts = { roots={}, top=100, min_size=1024*1024, skip_mounts=true, plain=false }
  local i = 1
  while i <= #arg do
    local a = arg[i]
    if a == "-h" or a == "--help" then
      io.write(
        "usage: large_files.lua [opts] [roots...]\n"
        .. "  -n N, --top N     files to show (default: 100)\n"
        .. "  --min-size BYTES  minimum size in bytes (default: 1048576)\n"
        .. "  --no-skip-mounts  cross filesystem boundaries\n"
        .. "  --plain           disable ANSI color\n"
        .. "  roots             paths to scan (default: /)\n")
      os.exit(0)
    elseif a == "-n" or a == "--top" then
      i = i + 1; opts.top = tonumber(arg[i]) or opts.top
    elseif a:match("^%-n(%d+)$") then
      opts.top = tonumber(a:match("^%-n(%d+)$"))
    elseif a == "--min-size" then
      i = i + 1; opts.min_size = tonumber(arg[i]) or opts.min_size
    elseif a == "--no-skip-mounts" then
      opts.skip_mounts = false
    elseif a == "--plain" then
      opts.plain = true
    elseif not a:match("^%-") then
      opts.roots[#opts.roots + 1] = a
    else
      io.stderr:write("unknown option: " .. a .. "\n"); os.exit(1)
    end
    i = i + 1
  end
  if #opts.roots == 0 then opts.roots = {"/"} end
  return opts
end

-- ── main ─────────────────────────────────────────────────────────────────────

local opts  = parse_args()
local color = not opts.plain and os.execute("[ -t 1 ]") == true

io.stderr:write(("Scanning %s (min size: %s) ...\n"):format(
  table.concat(opts.roots, ", "), human_size(opts.min_size)))

local entries = scan(opts.roots, opts.skip_mounts, opts.min_size)

io.stderr:write(("Found %d files above threshold.\n"):format(#entries))

if #entries == 0 then
  print("No files found.")
  os.exit(0)
end

print_table(entries, opts.top, color)
