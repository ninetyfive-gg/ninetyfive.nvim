local function CreateCompletion(completion, is_terminal)
  return {
      completion = completion,
      is_terminal = is_terminal
  }
end

-- This is pretty much Proggraming in Lua's queue
local Queue = {}

function Queue.New()
  return {first = 0, last = -1}
end

function Queue.append (queue, completion, is_terminal)
  local last = queue.last + 1
  queue.last = last
  queue[last] = CreateCompletion(completion, is_terminal)
end

function Queue.pop (queue)
  local first = queue.first
  if first > queue.last then error("queue is empty") end
  local value = queue[first]
  queue[first] = nil
  queue.first = first + 1
  return value
end

function Queue.length(queue)
  return queue.last - queue.first + 1
end

function Queue.clear(queue)
  queue.first = 0
  queue.last = -1
end

return Queue
