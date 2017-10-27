---
 -- Find out current branch
 -- @return {false|git branch name}
---
function get_git_branch()
    --for line in io.popen("git branch 2>nul"):lines() do
        --local m = line:match("%* (.+)$")
        --if m then
            --return m
        --end
    --end
    local out = assert(io.popen("git symbolic-ref --short HEAD", "r"))

    if out then
      local branch = out:read('*all')

      out:close()
      return string.gsub(branch, "\n", "")
    end

    return false
end

---
 -- Get the status of working dir
 -- @return {bool}
---
function get_git_status()
    return os.execute("git diff --quiet --ignore-submodules HEAD")
end

function git_prompt_filter()

    -- Colors for git status
	-- clean = "\x1b[1;37;40m",
	-- dirty = "\x1b[31;1m",
    local colors = {
    clean = "\x1b[34;42m\x1b[30;42m",
        dirty = "\x1b[34;43m\x1b[30;43m",
		--clean = "\x1b[34;43m\x1b[30;43m",
        --dirty = "\x1b[34;41m\x1b[30;41m",
    }

    local branch = get_git_branch()
    if branch then
        -- Has branch => therefore it is a git folder, now figure out status
        if true then
			-- clean
            color = colors.clean
            clink.prompt.value = string.gsub(clink.prompt.value, "{git}", color.."  "..branch.." \x1b[32;40m")
			--clink.prompt.value = string.gsub(clink.prompt.value, "{git}", color.."  "..branch.." \x1b[33;40m")
        else
			-- dirty
            color = colors.dirty
            clink.prompt.value = string.gsub(clink.prompt.value, "{git}", color.."  "..branch.." \x1b[33;40m")
        end
        
        return true
    end

    -- No git present or not in git file
    clink.prompt.value = string.gsub(clink.prompt.value, "{git}", " \x1b[34;40m")
    return false
end

clink.prompt.register_filter(git_prompt_filter, 50)
